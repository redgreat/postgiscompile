#!/usr/bin/env python3
import os
import sys
import json
import time
import ssl
import traceback
import logging
from datetime import datetime
from urllib import request, error
from typing import Any, Dict, List, Optional, Tuple


class ConfigError(Exception):
    """配置错误异常"""


def load_config(path: str) -> Dict[str, Any]:
    """加载并解析配置文件"""
    if not os.path.isfile(path):
        raise ConfigError("配置文件不存在: {}".format(path))
    with open(path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise ConfigError("配置文件 JSON 解析失败: {}".format(str(e)))
    return data


def validate_config(cfg: Dict[str, Any]) -> Dict[str, Any]:
    """验证配置并填充缺省值"""
    required_sections = ["db", "webhook", "thresholds"]
    for s in required_sections:
        if s not in cfg:
            raise ConfigError("缺少必须配置段: {}".format(s))
    db = cfg["db"]
    for k in ["host", "port", "dbname", "user"]:
        if k not in db:
            raise ConfigError("db 段缺少字段: {}".format(k))
    if "password" not in db and "password_env" not in db:
        db["password"] = ""
    cfg.setdefault("interval_seconds", 300)
    cfg.setdefault("templates", {})
    cfg["templates"].setdefault("title", "[{severity}] PostgreSQL 监控告警 - {metric}")
    cfg["templates"].setdefault(
        "body",
        "时间: {timestamp}\n指标: {metric}\n当前值: {value}\n阈值: {threshold}\n级别: {severity}\n详情: {details}\n建议: {action}"
    )
    cfg.setdefault("log_file", "/var/log/monitor_pg/monitor_pg.log")
    cfg.setdefault("options", {})
    opts = cfg["options"]
    opts.setdefault("use_pg_stat_kcache", True)
    opts.setdefault("use_pg_stat_statements", True)
    opts.setdefault("collect_bloat", True)
    opts.setdefault("enable_replication_check", True)
    return cfg


def setup_logger(log_file: str) -> logging.Logger:
    """初始化日志记录器"""
    logger = logging.getLogger("monitor_pg")
    logger.setLevel(logging.INFO)
    try:
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        fh = logging.FileHandler(log_file, encoding="utf-8")
    except Exception:
        fallback = os.path.join("/tmp", "monitor_pg.log")
        os.makedirs(os.path.dirname(fallback), exist_ok=True)
        fh = logging.FileHandler(fallback, encoding="utf-8")
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    fh.setFormatter(fmt)
    logger.addHandler(fh)
    return logger


class AlertSender:
    """企业微信告警发送器"""
    def __init__(self, webhook_url: str, timeout: int = 10) -> None:
        self.webhook_url = webhook_url
        self.timeout = timeout
        self._ctx = ssl.create_default_context()

    def send_text(self, content: str) -> Tuple[bool, Optional[str]]:
        """发送文本消息到企业微信机器人"""
        payload = json.dumps({"msgtype": "text", "text": {"content": content}}).encode("utf-8")
        req = request.Request(self.webhook_url, data=payload, headers={"Content-Type": "application/json"})
        try:
            with request.urlopen(req, timeout=self.timeout, context=self._ctx) as resp:
                data = resp.read().decode("utf-8", errors="ignore")
                return True, data
        except error.URLError as e:
            return False, str(e)
        except Exception as e:
            return False, str(e)

    def safe_send(self, content: str, retries: int = 3, backoff_seconds: int = 2) -> None:
        """带重试的告警发送"""
        for i in range(retries):
            ok, err = self.send_text(content)
            if ok:
                return
            time.sleep(backoff_seconds * (i + 1))


class DBClient:
    """PostgreSQL 数据库客户端"""
    def __init__(self, cfg: Dict[str, Any], logger: logging.Logger) -> None:
        self.cfg = cfg
        self.logger = logger
        self.conn = None

    def _resolve_password(self) -> str:
        """解析数据库密码来源"""
        db = self.cfg["db"]
        if db.get("password_env"):
            return os.environ.get(db["password_env"], "")
        return db.get("password", "")

    def connect(self) -> None:
        """建立数据库连接"""
        try:
            import psycopg2
            import psycopg2.extras
        except Exception as e:
            raise ConfigError("缺少 psycopg2 依赖: {}".format(str(e)))
        sslmode = self.cfg["db"].get("sslmode")
        dsn = (
            "host={host} port={port} dbname={dbname} user={user} password={password}".format(
                host=self.cfg["db"]["host"],
                port=self.cfg["db"]["port"],
                dbname=self.cfg["db"]["dbname"],
                user=self.cfg["db"]["user"],
                password=self._resolve_password(),
            )
        )
        if sslmode:
            dsn += " sslmode={}".format(sslmode)
            for key in ["sslrootcert", "sslcert", "sslkey"]:
                if self.cfg["db"].get(key):
                    dsn += " {}={}".format(key, self.cfg["db"][key])
        import psycopg2
        self.conn = psycopg2.connect(dsn)
        self.conn.autocommit = True

    def execute(self, sql: str, params: Optional[Tuple[Any, ...]] = None) -> List[Dict[str, Any]]:
        """执行 SQL 并返回字典列表"""
        import psycopg2.extras
        with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params or ())
            rows = cur.fetchall()
            return [dict(r) for r in rows]

    def execute_one(self, sql: str, params: Optional[Tuple[Any, ...]] = None) -> Optional[Dict[str, Any]]:
        """执行 SQL 并返回单行字典"""
        import psycopg2.extras
        with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params or ())
            row = cur.fetchone()
            return dict(row) if row else None


def severity_of(value: float, threshold: Dict[str, Any]) -> Optional[str]:
    """根据阈值计算严重级别"""
    warn = threshold.get("warning")
    crit = threshold.get("critical")
    if crit is not None and value >= crit:
        return "CRITICAL"
    if warn is not None and value >= warn:
        return "WARNING"
    return None


def now_ts() -> str:
    """返回当前时间戳字符串"""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


class Monitor:
    """核心监控器"""
    def __init__(self, cfg: Dict[str, Any], db: DBClient, sender: AlertSender, logger: logging.Logger) -> None:
        self.cfg = cfg
        self.db = db
        self.sender = sender
        self.logger = logger
        self.prev_state: Dict[str, Any] = {}

    def _ext_installed(self, ext_name: str) -> bool:
        """检测扩展是否安装"""
        row = self.db.execute_one(
            "SELECT EXISTS(SELECT 1 FROM pg_available_extensions WHERE name=%s AND installed_version IS NOT NULL) AS ok",
            (ext_name,)
        )
        return bool(row and row.get("ok"))

    def get_connection_counts(self) -> Dict[str, int]:
        """采集连接数统计"""
        sql = """
        SELECT
          COUNT(*) FILTER (WHERE pid != pg_backend_pid()) AS total,
          COUNT(*) FILTER (WHERE state = 'active') AS active,
          COUNT(*) FILTER (WHERE state = 'idle') AS idle
        FROM pg_stat_activity
        """
        row = self.db.execute_one(sql) or {"total": 0, "active": 0, "idle": 0}
        return {"total": int(row["total"]), "active": int(row["active"]), "idle": int(row["idle"])}

    def get_lock_contention(self) -> Dict[str, Any]:
        """采集锁竞争信息"""
        sql = """
        SELECT blocked.pid AS blocked_pid,
               blocker.pid AS blocking_pid,
               EXTRACT(EPOCH FROM (now() - blocked.query_start)) * 1000 AS blocked_ms,
               substring(blocked.query, 1, 200) AS blocked_query
        FROM pg_catalog.pg_locks blocked_l
        JOIN pg_catalog.pg_stat_activity blocked ON blocked.pid = blocked_l.pid
        JOIN pg_catalog.pg_locks blocker_l ON blocker_l.locktype = blocked_l.locktype
          AND (blocker_l.database, blocker_l.relation) IS NOT DISTINCT FROM (blocked_l.database, blocked_l.relation)
          AND blocker_l.pid <> blocked_l.pid
        JOIN pg_catalog.pg_stat_activity blocker ON blocker.pid = blocker_l.pid
        WHERE NOT blocked_l.granted
          AND blocker_l.granted
        ORDER BY blocked.query_start ASC
        LIMIT 20
        """
        rows = self.db.execute(sql)
        max_wait = max([float(r["blocked_ms"]) for r in rows], default=0.0)
        return {"blocking": rows, "max_wait_ms": max_wait}

    def get_deadlocks_delta(self) -> int:
        """采集死锁增量"""
        sql = "SELECT COALESCE(SUM(deadlocks),0)::bigint AS deadlocks FROM pg_stat_database"
        row = self.db.execute_one(sql) or {"deadlocks": 0}
        total = int(row["deadlocks"])
        last = int(self.prev_state.get("deadlocks_total", 0))
        self.prev_state["deadlocks_total"] = total
        return max(0, total - last)

    def get_slow_queries(self, threshold_ms: int, excludes: List[str]) -> List[Dict[str, Any]]:
        """采集慢查询列表"""
        sql = """
        SELECT
          pid, usename, datname,
          EXTRACT(EPOCH FROM (now() - query_start)) * 1000 AS runtime_ms,
          substring(query, 1, 400) AS query
        FROM pg_stat_activity
        WHERE state = 'active'
          AND query NOT LIKE '%pg_stat_activity%'
          AND now() - query_start > (make_interval(secs => %s/1000.0))
        ORDER BY query_start ASC
        LIMIT 50
        """
        rows = self.db.execute(sql, (threshold_ms,))
        filtered = []
        for r in rows:
            q = r.get("query", "") or ""
            if any(pat in q for pat in excludes):
                continue
            filtered.append(r)
        return filtered

    def get_cpu_time_delta_ms(self) -> float:
        """采集 CPU 时间增量(ms)"""
        if not self.cfg["options"].get("use_pg_stat_kcache"):
            return 0.0
        if not self._ext_installed("pg_stat_kcache"):
            return 0.0
        row = self.db.execute_one("SELECT COALESCE(SUM(user_time + system_time),0)::bigint AS cpu_ms FROM pg_stat_kcache")
        total = float(row["cpu_ms"]) if row else 0.0
        last = float(self.prev_state.get("cpu_ms_total", 0.0))
        self.prev_state["cpu_ms_total"] = total
        return max(0.0, total - last)

    def get_memory_pressure_delta_bytes(self) -> int:
        """采集临时文件字节增量以评估内存压力"""
        row = self.db.execute_one("SELECT COALESCE(SUM(temp_bytes),0)::bigint AS temp_bytes FROM pg_stat_database")
        total = int(row["temp_bytes"]) if row else 0
        last = int(self.prev_state.get("temp_bytes_total", 0))
        self.prev_state["temp_bytes_total"] = total
        return max(0, total - last)

    def get_shared_buffers_bytes(self) -> int:
        """获取 shared_buffers 配置值(字节)"""
        row = self.db.execute_one("SELECT setting, unit FROM pg_settings WHERE name='shared_buffers'")
        if not row:
            return 0
        setting = int(row["setting"])
        unit = str(row.get("unit") or "").lower()
        if unit == "8kB":
            return setting * 8 * 1024
        if unit.endswith("kB"):
            return setting * 1024
        if unit.endswith("MB"):
            return setting * 1024 * 1024
        if unit.endswith("GB"):
            return setting * 1024 * 1024 * 1024
        return setting

    def get_bloat(self) -> Dict[str, Any]:
        """采集表/索引膨胀估计"""
        if not self.cfg["options"].get("collect_bloat"):
            return {"table": [], "index": [], "max_pct": 0.0}
        rows = self.db.execute("""
        SELECT
          schemaname, relname,
          n_live_tup, n_dead_tup,
          CASE WHEN (n_live_tup + n_dead_tup) = 0 THEN 0
               ELSE round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
          END AS dead_ratio
        FROM pg_stat_user_tables
        ORDER BY dead_ratio DESC
        LIMIT 20
        """)
        max_pct = max([float(r["dead_ratio"]) for r in rows], default=0.0)
        idx_rows: List[Dict[str, Any]] = []
        if self._ext_installed("pgstattuple"):
            try:
                idx_rows = self.db.execute("""
                SELECT
                  schemaname, relname, indexrelname,
                  round(100.0 * (pgstattuple_approx(indexrelid)).approximate_bloat_ratio, 2) AS bloat_pct
                FROM pg_stat_user_indexes
                ORDER BY bloat_pct DESC
                LIMIT 20
                """)
                max_pct = max(max_pct, max([float(r["bloat_pct"]) for r in idx_rows], default=0.0))
            except Exception:
                pass
        return {"table": rows, "index": idx_rows, "max_pct": max_pct}

    def get_replication_lag(self) -> float:
        """采集复制延迟(秒)"""
        if not self.cfg["options"].get("enable_replication_check"):
            return 0.0
        row = self.db.execute_one("SELECT pg_is_in_recovery() AS standby")
        standby = bool(row and row.get("standby"))
        if standby:
            r = self.db.execute_one(
                "SELECT GREATEST(0, EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))) AS lag_s"
            )
            return float(r["lag_s"]) if r else 0.0
        rows = self.db.execute("""
        SELECT
          COALESCE(EXTRACT(EPOCH FROM write_lag),0) AS write_lag_s,
          COALESCE(EXTRACT(EPOCH FROM flush_lag),0) AS flush_lag_s,
          COALESCE(EXTRACT(EPOCH FROM replay_lag),0) AS replay_lag_s
        FROM pg_stat_replication
        """)
        vals = []
        for r in rows:
            for k in ["write_lag_s", "flush_lag_s", "replay_lag_s"]:
                try:
                    vals.append(float(r.get(k) or 0.0))
                except Exception:
                    pass
        return max(vals) if vals else 0.0

    def get_disk_usage(self) -> Dict[str, Any]:
        """采集数据库与表空间占用"""
        db_rows = self.db.execute("""
        SELECT datname, pg_database_size(datname) AS size_bytes
        FROM pg_database
        WHERE datname NOT IN ('template0','template1')
        """)
        ts_rows = self.db.execute("""
        SELECT spcname, pg_tablespace_size(oid) AS size_bytes
        FROM pg_tablespace
        """)
        db_total = sum([int(r["size_bytes"]) for r in db_rows]) if db_rows else 0
        ts_max = max([int(r["size_bytes"]) for r in ts_rows], default=0)
        return {"databases": db_rows, "tablespaces": ts_rows, "db_total_bytes": db_total, "ts_max_bytes": ts_max}

    def build_message(self, metric: str, value: Any, threshold: Any, severity: str, details: str, action: str) -> str:
        """构建告警消息文本"""
        title = self.cfg["templates"]["title"].format(severity=severity, metric=metric)
        body = self.cfg["templates"]["body"].format(
            timestamp=now_ts(),
            metric=metric,
            value=value,
            threshold=threshold,
            severity=severity,
            details=details,
            action=action,
        )
        return "{}\n{}".format(title, body)

    def evaluate_and_alert(self) -> None:
        """评估各项指标并发送告警"""
        counts = self.get_connection_counts()
        locks = self.get_lock_contention()
        deadlocks_delta = self.get_deadlocks_delta()
        cpu_delta_ms = self.get_cpu_time_delta_ms()
        mem_temp_delta = self.get_memory_pressure_delta_bytes()
        shared_buffers_bytes = self.get_shared_buffers_bytes()
        slow_queries = self.get_slow_queries(
            int(self.cfg["thresholds"].get("slow_query_ms", {}).get("warning", 5000)),
            self.cfg.get("slow_query_exclude_patterns", []),
        )
        bloat = self.get_bloat()
        repl_lag = self.get_replication_lag()
        disk = self.get_disk_usage()

        t = self.cfg["thresholds"]
        try:
            sev = severity_of(counts["total"], t.get("connections_total", {}))
            if sev:
                details = "total={} active={} idle={}".format(counts["total"], counts["active"], counts["idle"])
                msg = self.build_message("连接总数", counts["total"], t.get("connections_total", {}), sev, details, "启用连接池或减少长连接")
                self.sender.safe_send(msg)
            sev = severity_of(counts["active"], t.get("connections_active", {}))
            if sev:
                details = "active={} idle={}".format(counts["active"], counts["idle"])
                msg = self.build_message("活跃连接", counts["active"], t.get("connections_active", {}), sev, details, "排查慢查询与热点锁等待")
                self.sender.safe_send(msg)
            sev = severity_of(locks["max_wait_ms"], t.get("lock_wait_ms", {}))
            if sev:
                detail_query = locks["blocking"][0]["blocked_query"] if locks["blocking"] else ""
                msg = self.build_message("锁等待", int(locks["max_wait_ms"]), t.get("lock_wait_ms", {}), sev, detail_query, "定位阻塞会话并优化或终止")
                self.sender.safe_send(msg)
            sev = severity_of(float(deadlocks_delta), t.get("deadlocks", {}))
            if sev:
                msg = self.build_message("死锁次数(增量)", deadlocks_delta, t.get("deadlocks", {}), sev, "最近周期发生死锁", "检查并优化并发事务顺序")
                self.sender.safe_send(msg)
            sev = severity_of(float(len(slow_queries)), t.get("slow_query_count", {}))
            if sev and slow_queries:
                q = slow_queries[0]
                detail = "[{}] {}ms {}".format(q.get("datname", ""), int(q["runtime_ms"]), q["query"])
                msg = self.build_message("慢查询数量", len(slow_queries), t.get("slow_query_count", {}), sev, detail, "为慢查询添加索引或重写SQL")
                self.sender.safe_send(msg)
            sev = severity_of(bloat["max_pct"], t.get("bloat_pct", {}))
            if sev:
                msg = self.build_message("膨胀比例(最大)", bloat["max_pct"], t.get("bloat_pct", {}), sev, "建议对高膨胀表执行 VACUUM/重建索引", "规划维护窗口执行整理")
                self.sender.safe_send(msg)
            sev = severity_of(repl_lag, t.get("replication_lag_sec", {}))
            if sev:
                msg = self.build_message("复制延迟(秒)", int(repl_lag), t.get("replication_lag_sec", {}), sev, "主备延迟升高", "检查网络/磁盘性能与WAL生成速率")
                self.sender.safe_send(msg)
            sev = severity_of(float(disk["db_total_bytes"]), t.get("disk_usage_database_bytes", {}))
            if sev:
                msg = self.build_message("数据库总占用(字节)", disk["db_total_bytes"], t.get("disk_usage_database_bytes", {}), sev, "数据库体量增长较快", "考虑分区归档或扩容存储")
                self.sender.safe_send(msg)
            sev = severity_of(float(disk["ts_max_bytes"]), t.get("disk_usage_tablespace_bytes", {}))
            if sev:
                msg = self.build_message("表空间占用最大(字节)", disk["ts_max_bytes"], t.get("disk_usage_tablespace_bytes", {}), sev, "单表空间压力较大", "扩容或迁移热数据到新表空间")
                self.sender.safe_send(msg)
            sev = severity_of(float(cpu_delta_ms), t.get("cpu_time_delta_ms", {}))
            if sev and cpu_delta_ms > 0:
                msg = self.build_message("CPU时间增量(ms)", int(cpu_delta_ms), t.get("cpu_time_delta_ms", {}), sev, "周期 CPU 累计时间较高", "优化高 CPU 消耗查询或增加并行度")
                self.sender.safe_send(msg)
            sev = severity_of(float(mem_temp_delta), t.get("work_mem_pressure_bytes", {}))
            if sev and mem_temp_delta > 0:
                msg = self.build_message("临时文件增量(字节)", int(mem_temp_delta), t.get("work_mem_pressure_bytes", {}), sev, "排序/哈希溢出到磁盘", "增大 work_mem 或优化查询管道")
                self.sender.safe_send(msg)
        except Exception as e:
            self.logger.error("评估告警失败: %s", str(e))

        self.prev_state["shared_buffers_bytes"] = shared_buffers_bytes

    def run(self, once: bool = False) -> None:
        """运行监控循环"""
        interval = int(self.cfg.get("interval_seconds", 300))
        while True:
            start = time.time()
            try:
                self.evaluate_and_alert()
            except Exception as e:
                self.logger.error("监控执行异常: %s\n%s", str(e), traceback.format_exc())
            dur = time.time() - start
            self.logger.info("采集周期完成,耗时 %.2fs", dur)
            if once:
                break
            sleep_left = max(1.0, interval - dur)
            time.sleep(sleep_left)


def main(argv: List[str]) -> int:
    """主函数入口"""
    import argparse
    parser = argparse.ArgumentParser(prog="monitor_pg", description="PostgreSQL 轻量监控与企业微信告警")
    parser.add_argument("--config", required=False, default=os.environ.get("MONITOR_PG_CONFIG", "monitor/config/config.json"))
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--interval", type=int, default=None)
    parser.add_argument("--log-file", type=str, default=None)
    args = parser.parse_args(argv)
    cfg = validate_config(load_config(args.config))
    if args.interval:
        cfg["interval_seconds"] = args.interval
    if args.log_file:
        cfg["log_file"] = args.log_file
    logger = setup_logger(cfg["log_file"])
    sender = AlertSender(cfg["webhook"]["url"])
    db = DBClient(cfg, logger)
    db.connect()
    mon = Monitor(cfg, db, sender, logger)
    mon.run(once=args.once)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

