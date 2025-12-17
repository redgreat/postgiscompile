#!/bin/bash

# PostgreSQL 巡检报告生成脚本 (Markdown 格式)
# 支持现代 PostgreSQL 性能监控插件
# 作者: wangcw antigravity
# 日期: 2025-12-17
# 用法: bash bin/generate_pg_report.sh

# ========== 自动输出到文件 ==========
# 获取脚本所在目录的父目录(项目根目录)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="${PROJECT_ROOT}/docs"

# 确保 docs 目录存在
mkdir -p "$DOCS_DIR"

# 生成报告文件名
REPORT_DATE_SHORT=$(date +"%Y%m%d")
REPORT_FILE="${DOCS_DIR}/pg_report_${REPORT_DATE_SHORT}.md"

# 如果不是重定向到文件,则自动重定向
if [ -t 1 ]; then
    echo "正在生成巡检报告..."
    echo "报告将保存到: $REPORT_FILE"
    exec > "$REPORT_FILE"
fi

# ========== 配置区域 ==========
# 请根据实际环境修改以下配置
export PGHOST=${PGHOST:-/run/postgresql}
export PGPORT=${PGPORT:-5432}
export PGDATABASE=${PGDATABASE:-postgres}
export PGUSER=${PGUSER:-postgres}
export PGDATA=${PGDATA:-/opt/postgresql/data}
export PREFIX_PG=${PREFIX_PG:-/opt/postgresql}

# 报告生成时间
REPORT_DATE=$(date +"%Y-%m-%d %H:%M:%S")

# ========== 工具函数 ==========
# 查找 psql 命令路径
find_psql() {
    # 优先使用 PREFIX_PG 中的 psql
    if [ -n "$PREFIX_PG" ] && [ -x "$PREFIX_PG/bin/psql" ]; then
        echo "$PREFIX_PG/bin/psql"
        return 0
    fi
    
    # 尝试从环境变量中查找
    local psql_path=$(command -v psql 2>/dev/null)
    if [ -n "$psql_path" ]; then
        echo "$psql_path"
        return 0
    fi
    
    # 常见安装路径
    for path in /opt/postgresql/postgres/bin/psql /usr/local/pgsql/bin/psql /usr/pgsql-*/bin/psql; do
        if [ -x "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    echo "psql" # 回退到默认
}

PSQL_CMD=$(find_psql)

# DEBUG: 调试开关
DEBUG_MODE=1

# DEBUG: 调试日志函数
debug_log() {
    if [ "$DEBUG_MODE" = "1" ]; then
        echo "[DEBUG] $*" >&2
    fi
}

debug_log "PSQL命令: $PSQL_CMD"
debug_log "PGHOST: $PGHOST"
debug_log "PGPORT: $PGPORT"

# 执行 SQL 并返回结果 (使用临时文件)
psql_exec() {
    debug_log "psql_exec 调用,参数: $*"
    
    # 创建临时 SQL 文件
    local tmpfile=$(mktemp)
    chmod 644 "$tmpfile"  # DEBUG: 设置文件权限,让 postgres 用户可读
    
    # 将所有参数写入临时文件,去掉 -c 参数
    local sql_content=""
    local skip_next=0
    for arg in "$@"; do
        if [ $skip_next -eq 1 ]; then
            sql_content="$arg"
            skip_next=0
        elif [ "$arg" = "-c" ]; then
            skip_next=1
        elif [ "$arg" = "-d" ]; then
            skip_next=1
            # -d 参数需要传递给 psql
        else
            sql_content="${sql_content} ${arg}"
        fi
    done
    
    echo "$sql_content" > "$tmpfile"
    debug_log "SQL内容: $sql_content"
    debug_log "临时文件: $tmpfile"
    
    # 执行 SQL
    local result
    result=$(su - postgres -c "PGHOST='${PGHOST}' '${PSQL_CMD}' --no-password --pset=pager=off -q -t -A -f '$tmpfile'" 2>&1)
    local exit_code=$?
    
    rm -f "$tmpfile"
    
    if [ $exit_code -ne 0 ]; then
        debug_log "psql_exec 失败 (退出码: $exit_code): $result"
    fi
    
    echo "$result"
    return $exit_code
}

# 执行 SQL 并返回格式化表格 (使用临时文件)
psql_table() {
    debug_log "psql_table 调用,参数: $*"
    
    # 创建临时 SQL 文件
    local tmpfile=$(mktemp)
    chmod 644 "$tmpfile"  # DEBUG: 设置文件权限,让 postgres 用户可读
    local db_name=""
    
    # 解析参数
    local sql_content=""
    local skip_next=0
    local last_arg=""
    for arg in "$@"; do
        if [ $skip_next -eq 1 ]; then
            if [ "$last_arg" = "-d" ]; then
                db_name="$arg"
            else
                sql_content="$arg"
            fi
            skip_next=0
        elif [ "$arg" = "-c" ] || [ "$arg" = "-d" ]; then
            last_arg="$arg"
            skip_next=1
        else
            sql_content="${sql_content} ${arg}"
        fi
    done
    
    echo "$sql_content" > "$tmpfile"
    debug_log "SQL内容: $sql_content"
    debug_log "数据库: $db_name"
    debug_log "临时文件: $tmpfile"
    
    # 执行 SQL
    local result
    if [ -n "$db_name" ]; then
        result=$(su - postgres -c "PGHOST='${PGHOST}' '${PSQL_CMD}' --no-password --pset=pager=off -q -d '$db_name' -f '$tmpfile'" 2>&1)
    else
        result=$(su - postgres -c "PGHOST='${PGHOST}' '${PSQL_CMD}' --no-password --pset=pager=off -q -f '$tmpfile'" 2>&1)
    fi
    local exit_code=$?
    
    rm -f "$tmpfile"
    
    if [ $exit_code -ne 0 ]; then
        debug_log "psql_table 失败 (退出码: $exit_code): $result"
    fi
    
    echo "$result"
    return $exit_code
}

# 检查扩展是否已安装
check_extension() {
    local ext_name=$1
    debug_log "检查扩展: $ext_name"
    
    local result=$(psql_exec -c "SELECT COUNT(*) FROM pg_extension WHERE extname='$ext_name'" 2>/dev/null | grep -v "^$" | grep -v "DEBUG" | head -1)
    debug_log "扩展检查结果: $result"
    
    if echo "$result" | grep -q "^1$"; then
        return 0
    else
        return 1
    fi
}

# 检查数据库连接
check_db_connection() {
    debug_log "开始检查数据库连接..."
    
    local test_result
    test_result=$(su - postgres -c "PGHOST='${PGHOST}' '${PSQL_CMD}' --no-password -c 'SELECT 1'" 2>&1)
    local exit_code=$?
    
    debug_log "连接测试退出码: $exit_code"
    debug_log "连接测试结果: $test_result"
    
    if [ $exit_code -ne 0 ]; then
        echo "错误: 无法连接到 PostgreSQL 数据库" >&2
        echo "请检查以下配置:" >&2
        echo "  PGHOST=$PGHOST" >&2
        echo "  PGPORT=$PGPORT" >&2
        echo "  PGUSER=$PGUSER" >&2
        echo "  PGDATABASE=$PGDATABASE" >&2
        echo "  PSQL命令: $PSQL_CMD" >&2
        echo "" >&2
        echo "提示: 请确保以 root 用户运行此脚本" >&2
        echo "提示: 请确保 PostgreSQL 服务正在运行" >&2
        echo "测试结果: $test_result" >&2
        exit 1
    fi
    
    debug_log "数据库连接成功"
}

# 检查数据库连接
check_db_connection

# 检查是否为备库
debug_log "检查数据库角色..."
is_standby=$(psql_exec -c "SELECT pg_is_in_recovery()" 2>/dev/null | grep -v "^$" | grep -v "DEBUG" | head -1)
debug_log "is_standby 结果: $is_standby"

# ========== 报告开始 ==========
cat << EOF
# PostgreSQL 数据库巡检报告

**生成时间**: $REPORT_DATE  
**数据库角色**: $([ "$is_standby" = "t" ] && echo "Standby 备库" || echo "Primary 主库")

---

## 目录

1. [系统信息](#系统信息)
2. [数据库版本信息](#数据库版本信息)
3. [已安装扩展](#已安装扩展)
4. [数据库配置](#数据库配置)
5. [连接状态](#连接状态)
6. [性能统计](#性能统计)
7. [慢查询分析](#慢查询分析)
8. [等待事件分析](#等待事件分析)
9. [空间使用](#空间使用)
10. [表和索引分析](#表和索引分析)
11. [垃圾回收状态](#垃圾回收状态)
12. [复制状态](#复制状态)
13. [锁等待](#锁等待)
14. [长事务检查](#长事务检查)
15. [建议汇总](#建议汇总)

---

## 系统信息

### 主机名
\`\`\`
$(hostname)
\`\`\`

### 操作系统
\`\`\`
$(uname -a)
\`\`\`

### CPU 信息
\`\`\`
$(lscpu 2>/dev/null | grep -E "^Architecture|^CPU\(s\)|^Model name|^CPU MHz" || echo "无法获取 CPU 信息")
\`\`\`

### 内存信息
\`\`\`
$(free -h)
\`\`\`

### 磁盘使用
\`\`\`
$(df -h | grep -v tmpfs | grep -v devtmpfs | grep -v efivarfs)
\`\`\`

---

## 数据库版本信息

### PostgreSQL 版本
\`\`\`sql
$(psql_table -c 'SELECT version();')
\`\`\`

### 数据库启动时间
\`\`\`sql
$(psql_table -c 'SELECT pg_postmaster_start_time() AS "启动时间", 
       NOW() - pg_postmaster_start_time() AS "运行时长";')
\`\`\`

---

## 已安装扩展

### 所有数据库的扩展列表
\`\`\`sql
EOF

for db in $(psql_exec -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1') ORDER BY datname")
do
    echo "-- 数据库: $db"
    psql_table -d "$db" -c "SELECT extname AS \"扩展名\", 
           extversion AS \"版本\", 
           nspname AS \"模式\" 
    FROM pg_extension e 
    JOIN pg_namespace n ON e.extnamespace = n.oid 
    ORDER BY extname;" 2>/dev/null || echo "-- 无法连接到数据库 $db"
    echo ""
done

cat << 'EOF'
```

**建议**: 
- 确保关键性能监控扩展已启用: `pg_stat_statements`, `pg_stat_kcache`, `pg_wait_sampling`
- PostGIS 相关应用应确保 `postgis`, `postgis_topology`, `postgis_raster` 已安装

---

## 数据库配置

### 关键配置参数
```sql
EOF

psql_table -c "SELECT name AS \"参数名\", 
       setting AS \"当前值\", 
       unit AS \"单位\",
       source AS \"来源\"
FROM pg_settings 
WHERE name IN (
    'max_connections', 'shared_buffers', 'effective_cache_size',
    'maintenance_work_mem', 'work_mem', 'wal_buffers',
    'checkpoint_timeout', 'max_wal_size', 'min_wal_size',
    'random_page_cost', 'effective_io_concurrency',
    'max_worker_processes', 'max_parallel_workers',
    'shared_preload_libraries', 'log_min_duration_statement',
    'autovacuum', 'autovacuum_max_workers'
)
ORDER BY name;"

cat << 'EOF'
```

### 用户/数据库级别定制参数
```sql
EOF

psql_table -c "SELECT COALESCE(r.rolname, 'ALL') AS \"角色\",
       COALESCE(d.datname, 'ALL') AS \"数据库\",
       unnest(setconfig) AS \"配置\"
FROM pg_db_role_setting s
LEFT JOIN pg_roles r ON r.oid = s.setrole
LEFT JOIN pg_database d ON d.oid = s.setdatabase;"

cat << 'EOF'
```

**建议**: 
- 定制参数优先级高于配置文件,排查问题时需特别关注
- 建议根据工作负载调整 `work_mem` 和 `shared_buffers`

---

## 连接状态

### 当前连接统计
```sql
EOF

psql_table -c "SELECT state AS \"状态\",
       COUNT(*) AS \"连接数\"
FROM pg_stat_activity
GROUP BY state
ORDER BY COUNT(*) DESC;"

cat << 'EOF'
```

### 各数据库连接数
```sql
EOF

psql_table -c "SELECT datname AS \"数据库\",
       COUNT(*) AS \"当前连接数\",
       (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS \"最大连接数\"
FROM pg_stat_activity
GROUP BY datname
ORDER BY COUNT(*) DESC;"

cat << 'EOF'
```

### 各用户连接数
```sql
EOF

psql_table -c "SELECT usename AS \"用户\",
       COUNT(*) AS \"连接数\",
       r.rolconnlimit AS \"连接限制\"
FROM pg_stat_activity a
LEFT JOIN pg_roles r ON a.usename = r.rolname
GROUP BY usename, r.rolconnlimit
ORDER BY COUNT(*) DESC;"

cat << 'EOF'
```

**建议**: 
- `idle in transaction` 状态过多说明应用层事务管理有问题
- 连接数接近 `max_connections` 时考虑使用连接池 (如 pgbouncer)

---

## 性能统计

### pg_stat_statements - TOP 10 慢查询 (按总耗时)
```sql
EOF

if check_extension "pg_stat_statements"; then
    psql_table -c "SELECT 
    substring(query, 1, 80) AS \"查询语句(截断)\",
    calls AS \"调用次数\",
    ROUND(total_exec_time::numeric, 2) AS \"总耗时(ms)\",
    ROUND(mean_exec_time::numeric, 2) AS \"平均耗时(ms)\",
    ROUND(max_exec_time::numeric, 2) AS \"最大耗时(ms)\",
    ROUND(stddev_exec_time::numeric, 2) AS \"标准差(ms)\"
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;" 2>/dev/null || echo "-- pg_stat_statements 数据不可用"
else
    echo "-- 扩展 pg_stat_statements 未安装"
fi

cat << 'EOF'
```

### pg_stat_statements - TOP 10 高频查询
```sql
EOF

if check_extension "pg_stat_statements"; then
    psql_table -c "SELECT 
    substring(query, 1, 80) AS \"查询语句(截断)\",
    calls AS \"调用次数\",
    ROUND(mean_exec_time::numeric, 2) AS \"平均耗时(ms)\",
    ROUND(total_exec_time::numeric, 2) AS \"总耗时(ms)\"
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;" 2>/dev/null || echo "-- pg_stat_statements 数据不可用"
else
    echo "-- 扩展 pg_stat_statements 未安装"
fi

cat << 'EOF'
```

### pg_stat_kcache - 系统资源消耗 TOP 10
```sql
EOF

if check_extension "pg_stat_kcache"; then
    psql_table -c "SELECT 
    substring(s.query, 1, 60) AS \"查询语句(截断)\",
    k.reads AS \"物理读\",
    k.writes AS \"物理写\",
    ROUND((k.user_time + k.system_time)::numeric, 2) AS \"CPU时间(ms)\"
FROM pg_stat_kcache k
JOIN pg_stat_statements s ON k.queryid = s.queryid AND k.userid = s.userid AND k.dbid = s.dbid
ORDER BY (k.user_time + k.system_time) DESC
LIMIT 10;" 2>/dev/null || echo "-- pg_stat_kcache 数据不可用"
else
    echo "-- 扩展 pg_stat_kcache 未安装"
fi

cat << 'EOF'
```

### pg_stat_monitor - 查询性能监控摘要
```sql
EOF

if check_extension "pg_stat_monitor"; then
    psql_table -c "SELECT 
    bucket AS \"时间桶\",
    substring(query, 1, 60) AS \"查询(截断)\",
    calls AS \"次数\",
    ROUND(mean_exec_time::numeric, 2) AS \"平均耗时(ms)\",
    ROUND(stddev_exec_time::numeric, 2) AS \"标准差(ms)\"
FROM pg_stat_monitor
ORDER BY mean_exec_time DESC
LIMIT 10;" 2>/dev/null || echo "-- pg_stat_monitor 数据不可用"
else
    echo "-- 扩展 pg_stat_monitor 未安装"
fi

cat << 'EOF'
```

**建议**: 
- 优化总耗时最高的查询,可显著提升整体性能
- 关注平均耗时和标准差,标准差大说明性能不稳定
- 使用 `EXPLAIN ANALYZE` 分析慢查询的执行计划

---

## 慢查询分析

### 当前正在执行的慢查询 (>5秒)
```sql
EOF

psql_table -c "SELECT 
    pid AS \"进程ID\",
    usename AS \"用户\",
    datname AS \"数据库\",
    state AS \"状态\",
    NOW() - query_start AS \"执行时长\",
    substring(query, 1, 100) AS \"查询语句(截断)\"
FROM pg_stat_activity
WHERE state = 'active'
  AND query NOT LIKE '%pg_stat_activity%'
  AND NOW() - query_start > interval '5 seconds'
ORDER BY query_start;"

cat << 'EOF'
```

**建议**: 
- 执行时间过长的查询可能需要优化或添加索引
- 必要时可使用 `pg_cancel_backend(pid)` 取消查询

---

## 等待事件分析

### pg_wait_sampling - 等待事件统计
```sql
EOF

if check_extension "pg_wait_sampling"; then
    psql_table -c "SELECT 
    event_type AS \"等待类型\",
    event AS \"等待事件\",
    COUNT(*) AS \"等待次数\"
FROM pg_wait_sampling_profile
GROUP BY event_type, event
ORDER BY COUNT(*) DESC
LIMIT 20;" 2>/dev/null || echo "-- pg_wait_sampling 数据不可用"
else
    echo "-- 扩展 pg_wait_sampling 未安装"
fi

cat << 'EOF'
```

**建议**: 
- `Lock` 类型等待过多说明存在锁竞争
- `IO` 类型等待过多说明磁盘性能是瓶颈
- `CPU` 类型等待说明计算密集

---

## 空间使用

### 表空间使用情况
```sql
EOF

psql_table -c "SELECT 
    spcname AS \"表空间名\",
    pg_tablespace_location(oid) AS \"位置\",
    pg_size_pretty(pg_tablespace_size(oid)) AS \"大小\"
FROM pg_tablespace
ORDER BY pg_tablespace_size(oid) DESC;"

cat << 'EOF'
```

### 数据库大小
```sql
EOF

psql_table -c "SELECT 
    datname AS \"数据库名\",
    pg_size_pretty(pg_database_size(datname)) AS \"大小\"
FROM pg_database
ORDER BY pg_database_size(datname) DESC;"

cat << 'EOF'
```

### TOP 10 最大的表
```sql
EOF

for db in $(psql_exec -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1') ORDER BY datname" | head -3)
do
    echo "-- 数据库: $db"
    psql_table -d "$db" -c "SELECT 
    schemaname AS \"模式\",
    tablename AS \"表名\",
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS \"总大小\",
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS \"表大小\",
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS \"索引大小\"
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;" 2>/dev/null || echo "-- 无法连接到数据库 $db"
    echo ""
done

cat << 'EOF'
```

**建议**: 
- 单表超过 10GB 且频繁更新的表考虑分区
- 定期清理历史数据,避免表过度膨胀

---

## 表和索引分析

### 未使用的索引 (扫描次数 < 10)
```sql
EOF

for db in $(psql_exec -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1') ORDER BY datname" | head -3)
do
    echo "-- 数据库: $db"
    psql_table -d "$db" -c "SELECT 
    schemaname AS \"模式\",
    relname AS \"表名\",
    indexrelname AS \"索引名\",
    idx_scan AS \"扫描次数\",
    pg_size_pretty(pg_relation_size(indexrelid)) AS \"索引大小\"
FROM pg_stat_user_indexes
WHERE idx_scan < 10
  AND schemaname NOT IN ('pg_catalog', 'information_schema')
  AND pg_relation_size(indexrelid) > 65536
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 10;" 2>/dev/null || echo "-- 无法连接到数据库 $db"
    echo ""
done

cat << 'EOF'
```

### 索引数量过多的表 (>4个索引)
```sql
EOF

for db in $(psql_exec -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1') ORDER BY datname" | head -3)
do
    echo "-- 数据库: $db"
    psql_table -d "$db" -c "SELECT 
    schemaname AS \"模式\",
    tablename AS \"表名\",
    COUNT(*) AS \"索引数量\",
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS \"表总大小\"
FROM pg_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
GROUP BY schemaname, tablename
HAVING COUNT(*) > 4
ORDER BY COUNT(*) DESC
LIMIT 10;" 2>/dev/null || echo "-- 无法连接到数据库 $db"
    echo ""
done

cat << 'EOF'
```

**建议**: 
- 删除未使用的索引可提升写入性能
- 索引过多会降低 INSERT/UPDATE/DELETE 性能

---

## 垃圾回收状态

### Autovacuum 配置
```sql
EOF

psql_table -c "SELECT 
    name AS \"参数名\",
    setting AS \"值\",
    unit AS \"单位\"
FROM pg_settings
WHERE name LIKE 'autovacuum%'
ORDER BY name;"

cat << 'EOF'
```

### 垃圾数据最多的表 TOP 10
```sql
EOF

for db in $(psql_exec -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1') ORDER BY datname" | head -3)
do
    echo "-- 数据库: $db"
    psql_table -d "$db" -c "SELECT 
    schemaname AS \"模式\",
    relname AS \"表名\",
    n_live_tup AS \"活跃行数\",
    n_dead_tup AS \"死亡行数\",
    ROUND(n_dead_tup::numeric * 100 / NULLIF(n_live_tup, 0), 2) AS \"垃圾比例(%)\",
    last_autovacuum AS \"最后自动清理\"
FROM pg_stat_user_tables
WHERE n_live_tup > 0
  AND schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n_dead_tup DESC
LIMIT 10;" 2>/dev/null || echo "-- 无法连接到数据库 $db"
    echo ""
done

cat << 'EOF'
```

### 表年龄检查 (XID 消耗)
```sql
EOF

for db in $(psql_exec -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1') ORDER BY datname" | head -3)
do
    echo "-- 数据库: $db"
    psql_table -d "$db" -c "SELECT 
    n.nspname AS \"模式\",
    c.relname AS \"表名\",
    age(c.relfrozenxid) AS \"年龄\",
    2^31 - age(c.relfrozenxid) AS \"剩余XID\"
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE c.relkind IN ('r', 't')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
ORDER BY age(c.relfrozenxid) DESC
LIMIT 10;" 2>/dev/null || echo "-- 无法连接到数据库 $db"
    echo ""
done

cat << 'EOF'
```

**建议**: 
- 垃圾比例超过 20% 的表需要执行 VACUUM
- 表年龄超过 15 亿需要关注,接近 20 亿需要立即处理
- 确保 autovacuum 已开启且配置合理

---

## 复制状态

### 流复制状态
```sql
EOF

if [ "$is_standby" != "t" ]; then
    psql_table -c "SELECT 
    client_addr AS \"备库地址\",
    state AS \"状态\",
    sync_state AS \"同步状态\",
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS \"发送延迟(bytes)\",
    pg_wal_lsn_diff(sent_lsn, write_lsn) AS \"写入延迟(bytes)\",
    pg_wal_lsn_diff(write_lsn, flush_lsn) AS \"刷盘延迟(bytes)\",
    pg_wal_lsn_diff(flush_lsn, replay_lsn) AS \"应用延迟(bytes)\"
FROM pg_stat_replication;" 2>/dev/null || echo "-- 无流复制或查询失败"
else
    echo "-- 当前为备库,跳过主库复制状态检查"
fi

cat << 'EOF'
```

### 复制槽状态
```sql
EOF

psql_table -c "SELECT 
    slot_name AS \"槽名称\",
    slot_type AS \"类型\",
    database AS \"数据库\",
    active AS \"活跃\",
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS \"WAL延迟(bytes)\"
FROM pg_replication_slots;" 2>/dev/null || echo "-- 无复制槽"

cat << 'EOF'
```

**建议**: 
- 复制延迟过大需检查网络带宽和磁盘 IO
- 不活跃的复制槽会导致 WAL 堆积,需及时清理

---

## 锁等待

### 当前锁等待
```sql
EOF

psql_table -c "SELECT 
    blocked_locks.pid AS \"被阻塞PID\",
    blocked_activity.usename AS \"被阻塞用户\",
    blocking_locks.pid AS \"阻塞PID\",
    blocking_activity.usename AS \"阻塞用户\",
    blocked_activity.query AS \"被阻塞查询\",
    blocking_activity.query AS \"阻塞查询\"
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;" 2>/dev/null || echo "-- 当前无锁等待"

cat << 'EOF'
```

**建议**: 
- 锁等待时间过长需要分析业务逻辑,优化事务粒度
- 必要时可使用 `pg_terminate_backend(pid)` 终止阻塞会话

---

## 长事务检查

### 运行超过 30 分钟的事务
```sql
EOF

psql_table -c "SELECT 
    pid AS \"进程ID\",
    usename AS \"用户\",
    datname AS \"数据库\",
    state AS \"状态\",
    NOW() - xact_start AS \"事务时长\",
    NOW() - query_start AS \"查询时长\",
    substring(query, 1, 100) AS \"查询(截断)\"
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND NOW() - xact_start > interval '30 minutes'
ORDER BY xact_start;" 2>/dev/null || echo "-- 无长事务"

cat << 'EOF'
```

### 准备事务 (2PC)
```sql
EOF

psql_table -c "SELECT 
    gid AS \"全局事务ID\",
    prepared AS \"准备时间\",
    owner AS \"所有者\",
    database AS \"数据库\"
FROM pg_prepared_xacts
ORDER BY prepared;" 2>/dev/null || echo "-- 无准备事务"

cat << 'EOF'
```

**建议**: 
- 长事务会阻止垃圾回收,导致表膨胀
- 2PC 事务必须及时提交或回滚,否则会导致严重问题

---

## 建议汇总

### 性能优化建议
EOF

echo ""
echo "1. **慢查询优化**: 使用 \`pg_stat_statements\` 找出耗时最长的查询并优化"
echo "2. **索引优化**: 删除未使用的索引,为高频查询添加合适的索引"
echo "3. **连接池**: 如果连接数较高,建议使用 pgbouncer 等连接池"
echo "4. **配置调优**: 根据硬件资源调整 \`shared_buffers\`, \`work_mem\` 等参数"

echo ""
echo "### 空间管理建议"
echo ""
echo "1. **定期清理**: 对垃圾比例高的表执行 VACUUM"
echo "2. **分区策略**: 对大表考虑使用 \`pg_partman\` 进行分区管理"
echo "3. **归档策略**: 定期归档或删除历史数据"

echo ""
echo "### 监控建议"
echo ""
echo "1. **启用关键扩展**: 确保 \`pg_stat_statements\`, \`pg_stat_kcache\`, \`pg_wait_sampling\` 已启用"
echo "2. **定期巡检**: 建议每周运行本巡检脚本"
echo "3. **日志分析**: 定期分析 PostgreSQL 日志,关注错误和警告"

echo ""
echo "### 高可用建议"
echo ""
echo "1. **复制监控**: 密切监控流复制延迟"
echo "2. **备份策略**: 确保有完善的备份和恢复流程"
echo "3. **故障演练**: 定期进行故障切换演练"

cat << 'EOF'

---

## 报告结束

**生成工具**: PostgreSQL 巡检报告生成脚本  
**脚本位置**: bin/generate_pg_report.sh  

---
EOF

# 输出成功信息到 stderr (如果输出被重定向到文件)
if [ ! -t 1 ]; then
    echo "✓ 巡检报告生成成功: $REPORT_FILE" >&2
    echo "✓ 报告大小: $(du -h "$REPORT_FILE" | cut -f1)" >&2
fi
