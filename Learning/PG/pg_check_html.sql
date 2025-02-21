\set current_time `date +%Y%m%d_%H%M%S`
\o pg_check_report_:current_time.html

\qecho <!DOCTYPE html>
\qecho <html>
\qecho <head>
\qecho <meta charset="UTF-8">
\qecho <title>PostgreSQL 数据库巡检报告 - :current_time</title>
\qecho <style>
\qecho body { font-family: Arial, sans-serif; margin: 20px; }
\qecho h1 { color: #336699; }
\qecho h2 { color: #666666; margin-top: 20px; }
\qecho table { border-collapse: collapse; width: 100%; margin: 10px 0; }
\qecho th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
\qecho th { background-color: #f5f5f5; }
\qecho tr:nth-child(even) { background-color: #f9f9f9; }
\qecho </style>
\qecho </head>
\qecho <body>
\qecho <h1>PostgreSQL 数据库巡检报告</h1>

\H

\qecho <h2>数据库版本</h2>
SELECT version();

\qecho <h2>数据库运行时间</h2>
SELECT 
    pg_postmaster_start_time() as start_time,
    now() - pg_postmaster_start_time() as uptime;

\qecho <h2>数据库大小</h2>
SELECT datname, 
       pg_size_pretty(pg_database_size(datname)) as size,
       pg_size_pretty(pg_database_size(datname)::numeric) as raw_size
FROM pg_database 
ORDER BY pg_database_size(datname) DESC;

\qecho <h2>表空间使用情况</h2>
SELECT spcname, pg_size_pretty(pg_tablespace_size(spcname)) 
FROM pg_tablespace;

\qecho <h2>当前连接情况</h2>
SELECT datname, usename, client_addr, state, query_start, wait_event_type, wait_event 
FROM pg_stat_activity 
WHERE state IS NOT NULL;

\qecho <h2>锁等待情况</h2>
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
WHERE NOT blocked_locks.granted;

\qecho <h2>缓存命中率</h2>
SELECT 
    sum(heap_blks_read) as heap_read,
    sum(heap_blks_hit)  as heap_hit,
    ROUND((sum(heap_blks_hit)::numeric / (sum(heap_blks_hit) + sum(heap_blks_read))::numeric * 100), 2) as hit_ratio
FROM pg_statio_user_tables;

\qecho <h2>死元组情况</h2>
SELECT schemaname, relname, n_live_tup, n_dead_tup, 
       ROUND(CAST(n_dead_tup AS numeric) / NULLIF(n_live_tup, 0) * 100, 2) as dead_ratio
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC
LIMIT 10;

\qecho <h2>复制状态</h2>
SELECT * FROM pg_stat_replication;

\qecho <h2>数据库年龄</h2>
SELECT datname, age(datfrozenxid) as xid_age 
FROM pg_database 
ORDER BY xid_age DESC;

\qecho <h2>长事务</h2>
SELECT pid, usename, datname, xact_start, now() - xact_start as duration, state, query 
FROM pg_stat_activity 
WHERE xact_start IS NOT NULL 
ORDER BY xact_start;

\qecho <h2>未使用索引</h2>
SELECT schemaname, relname as table_name, indexrelname as index_name, 
       idx_scan, idx_tup_read, idx_tup_fetch 
FROM pg_stat_user_indexes 
WHERE idx_scan = 0 
AND idx_tup_read = 0 
AND idx_tup_fetch = 0;

\qecho </body>
\qecho </html>

\o