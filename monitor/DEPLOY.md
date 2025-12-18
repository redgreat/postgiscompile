# 监控项目部署指南

## 目录结构
- `monitor/monitor_pg.py`：Python 监控脚本（企业微信告警、阈值评估、错误重试）
- `monitor/config/config.json`：配置模板（连接、阈值、周期、消息模板）
- `monitor/systemd/monitor_pg.service`：监控服务 systemd 单元
- `monitor/logrotate/monitor_pg`：监控日志轮转规则
- `monitor/tests/test_monitor_pg.py`：关键函数单元测试
- `monitor/pg_collector.sh`：可选主机系统采集脚本（CPU/内存/磁盘/负载）
- `monitor/systemd/pg_collector.service`：系统采集服务
- `monitor/systemd/pg_collector.timer`：系统采集定时器（默认 5 分钟）
- `monitor/sql/*.sql`：锁竞争与膨胀分析 SQL
- `monitor/perl/monitor_pg.pl`：Perl 备用脚本
- `monitor/package.sh`：打包脚本（生成 `monitor-YYYYMMDD.tar.gz`）

## 运行环境
- 监控机为 Linux，Python 3.6+，可访问企业微信 Webhook（出网）。
- 目标 PostgreSQL 实例可被监控机访问（内网或专线），建议授予监控账号 `pg_monitor` 角色。

## 安装步骤
- 安装依赖：
  - `sudo apt/dnf install python3 python3-pip`
  - `pip3 install psycopg2-binary`
- 创建运行用户与目录：
  - `sudo useradd -r -s /sbin/nologin monitor || true`
  - `sudo mkdir -p /opt/monitor /etc/monitor /var/log/monitor_pg`
  - `sudo chown -R monitor:monitor /opt/monitor /var/log/monitor_pg`
- 部署文件：
  - 将 `monitor` 目录下文件复制到对应位置：
    - `/opt/monitor/monitor_pg.py`
    - `/opt/monitor/pg_collector.sh`
    - `/opt/monitor/sql/*`
    - `/opt/monitor/perl/monitor_pg.pl`
    - `/etc/monitor/config.json`
    - `/etc/systemd/system/monitor_pg.service`
    - `/etc/systemd/system/pg_collector.service`
    - `/etc/systemd/system/pg_collector.timer`
    - `/etc/logrotate.d/monitor_pg`
- 配置文件：
  - 编辑 `/etc/monitor/config.json`，设置数据库连接、Webhook、阈值等。
  - 可通过环境变量注入密码（设置 `password_env`）。
- 启动服务：
  - `sudo systemctl daemon-reload`
  - `sudo systemctl enable --now monitor_pg`
  - `sudo systemctl enable --now pg_collector.timer`
  - 查看状态：`systemctl status monitor_pg`、`systemctl status pg_collector.timer`
- 日志轮转：
  - 验证：`sudo logrotate -f /etc/logrotate.d/monitor_pg`

## 使用说明
- 单次运行：`python3 /opt/monitor/monitor_pg.py --config /etc/monitor/config.json --once`
- 调整周期：`--interval 120` 临时覆盖采集周期（秒）。
- 自定义日志位置：`--log-file /tmp/monitor_pg.log`。
- 系统采集结果：`/var/log/monitor_pg/collector.jsonl`（每次采集一行 JSON）。

## 阈值建议
- 连接类：`connections_total`、`connections_active` 根据实例规模与连接池策略调整。
- 锁等待：`lock_wait_ms` 结合业务特点设定；建议 WARNING 5s，CRITICAL 15s 起步。
- 慢查询：`slow_query_ms` 与 `slow_query_count` 配合设置，避免告警洪泛。
- 膨胀与空间：`bloat_pct`、`disk_usage_*` 按历史增长与存储规划设定。
- 复制延迟：`replication_lag_sec` 根据主备容忍度与负载峰值调整。
- CPU/内存压力：`cpu_time_delta_ms`、`work_mem_pressure_bytes` 随业务复杂度与硬件配置调优。

## 安全与可靠性
- 建议开启 TLS：在配置中设置 `sslmode=require` 并提供证书路径。
- 使用只读监控账号并授予 `pg_monitor` 角色，避免高权限暴露。
- 企业微信发送器带重试机制，日志记录所有异常，便于问题定位。

## 常见问题
- 连接失败：检查防火墙/ACL、`pg_hba.conf`、网络连通性；优先走内网与 Socket。
- 扩展不可用：未安装 `pg_stat_kcache`/`pgstattuple` 时对应指标自动跳过或降级。
- 告警噪声：适当提高阈值、过滤维护语句（`slow_query_exclude_patterns`）。

## 打包与分发
- 在仓库根目录执行：`bash monitor/package.sh` 生成 `monitor-YYYYMMDD.tar.gz`，将压缩包分发至监控机并按上述路径解压、部署。

