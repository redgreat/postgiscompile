-- 函数: 锁阻塞检查 (建议在分析锁竞争时执行)
SELECT blocked.pid       AS blocked_pid,
       blocker.pid       AS blocking_pid,
       blocked.usename   AS blocked_user,
       blocked.datname   AS blocked_db,
       now() - blocked.query_start AS blocked_duration,
       substring(blocked.query, 1, 400) AS blocked_query,
       substring(blocker.query, 1, 200) AS blocker_query
FROM pg_catalog.pg_locks blocked_l
JOIN pg_catalog.pg_stat_activity blocked ON blocked.pid = blocked_l.pid
JOIN pg_catalog.pg_locks blocker_l ON blocker_l.locktype = blocked_l.locktype
  AND (blocker_l.database, blocker_l.relation) IS NOT DISTINCT FROM (blocked_l.database, blocked_l.relation)
  AND blocker_l.pid <> blocked_l.pid
JOIN pg_catalog.pg_stat_activity blocker ON blocker.pid = blocker_l.pid
WHERE NOT blocked_l.granted
  AND blocker_l.granted
ORDER BY blocked.query_start ASC
LIMIT 50;

