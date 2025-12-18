-- 函数: 表与索引膨胀估计 (无需扩展版本)
SELECT
  schemaname,
  relname,
  n_live_tup,
  n_dead_tup,
  CASE WHEN (n_live_tup + n_dead_tup) = 0 THEN 0
       ELSE round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
  END AS dead_ratio
FROM pg_stat_user_tables
ORDER BY dead_ratio DESC
LIMIT 50;

-- 函数: 索引膨胀估计 (需 pgstattuple 扩展)
-- CREATE EXTENSION IF NOT EXISTS pgstattuple;
SELECT
  schemaname,
  relname,
  indexrelname,
  round(100.0 * (pgstattuple_approx(indexrelid)).approximate_bloat_ratio, 2) AS bloat_pct
FROM pg_stat_user_indexes
ORDER BY bloat_pct DESC
LIMIT 50;

