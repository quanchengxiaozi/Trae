#!/bin/bash

# PostgreSQL 连接信息
PGHOST="localhost"
PGPORT="5432"
PGUSER="postgres"
PGPASSWORD=""
PGDATABASE="postgres"

# 创建或检查 pgpass 文件
PGPASSFILE="$HOME/.pgpass"
if [ ! -f "$PGPASSFILE" ]; then
    echo "${PGHOST}:${PGPORT}:${PGDATABASE}:${PGUSER}:your_password" > "$PGPASSFILE"
    chmod 0600 "$PGPASSFILE"
    echo "已创建 .pgpass 文件，请修改密码后重新运行脚本"
    exit 1
fi

# 设置 PGPASSFILE 环境变量
export PGPASSFILE

# 输出目录
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
OUTPUT_DIR="${SCRIPT_DIR}/pg_check_reports"
DATE=$(date +%Y%m%d_%H%M%S)
HTML_FILE="${OUTPUT_DIR}/pg_check_${DATE}.html"

# 创建输出目录
mkdir -p "${OUTPUT_DIR}"

# 创建 HTML 头部
cat > "${HTML_FILE}" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>PostgreSQL 数据库巡检报告 - ${DATE}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #336699; }
        h2 { color: #666666; margin-top: 20px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f5f5f5; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .warning { color: #ff6600; }
        .error { color: #ff0000; }
        .success { color: #008000; }
    </style>
</head>
<body>
    <h1>PostgreSQL 数据库巡检报告</h1>
    <p>生成时间：$(date '+%Y-%m-%d %H:%M:%S')</p>
EOF

# 执行SQL并将结果写入HTML
run_query() {
    local title="$1"
    local query="$2"
    
    echo "<h2>${title}</h2>" >> "${HTML_FILE}"
    echo "<div class='query-result'>" >> "${HTML_FILE}"
    psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" \
        -H -c "${query}" >> "${HTML_FILE}" 2>&1
    echo "</div>" >> "${HTML_FILE}"
}

# 开始检查
echo "<h2>检查开始</h2>" >> "${HTML_FILE}"

# 1. 数据库版本
run_query "数据库版本" "SELECT version();"

# 2. 数据库运行时间
run_query "数据库运行时间" "
SELECT 
    pg_postmaster_start_time() as start_time,
    now() - pg_postmaster_start_time() as uptime;"

# 3. 数据库大小
run_query "数据库大小" "
SELECT datname, 
       pg_size_pretty(pg_database_size(datname)) as size,
       pg_size_pretty(pg_database_size(datname)::numeric) as raw_size
FROM pg_database 
ORDER BY pg_database_size(datname) DESC;"

# 4. 表空间使用情况
run_query "表空间使用情况" "
SELECT spcname, pg_size_pretty(pg_tablespace_size(spcname)) 
FROM pg_tablespace;"

# 5. 连接情况
run_query "当前连接情况" "
SELECT datname, usename, client_addr, state, query_start, wait_event_type, wait_event 
FROM pg_stat_activity 
WHERE state IS NOT NULL;"

# 6. 锁等待情况
run_query "锁等待情况" "
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_statement
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
WHERE NOT blocked_locks.granted;"

# 7. 缓存命中率
run_query "缓存命中率" "
SELECT 
    sum(heap_blks_read) as heap_read,
    sum(heap_blks_hit)  as heap_hit,
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read))::float as ratio
FROM pg_statio_user_tables;"

# 8. 死元组情况
run_query "死元组情况" "
SELECT schemaname, relname, n_live_tup, n_dead_tup, 
       ROUND(CAST(n_dead_tup AS numeric) / NULLIF(n_live_tup, 0) * 100, 2) as dead_ratio
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC
LIMIT 10;"

# 9. 复制状态（如果配置了复制）
run_query "复制状态" "SELECT * FROM pg_stat_replication;"

# 10. 最大年龄的数据库
run_query "数据库年龄" "
SELECT datname, age(datfrozenxid) as xid_age 
FROM pg_database 
ORDER BY xid_age DESC;"

# 11. 检查长事务
run_query "长事务" "
SELECT pid, usename, datname, xact_start, now() - xact_start as duration, state, query 
FROM pg_stat_activity 
WHERE xact_start IS NOT NULL 
ORDER BY xact_start;"

# 12. 检查未使用的索引
run_query "未使用索引" "
SELECT schemaname, relname as table_name, indexrelname as index_name, 
       idx_scan, idx_tup_read, idx_tup_fetch 
FROM pg_stat_user_indexes 
WHERE idx_scan = 0 
AND idx_tup_read = 0 
AND idx_tup_fetch = 0;"

# 添加HTML尾部
cat >> "${HTML_FILE}" << EOF
    <hr>
    <p>巡检完成时间：$(date '+%Y-%m-%d %H:%M:%S')</p>
</body>
</html>
EOF

echo "巡检报告已生成：${HTML_FILE}"