-- Comment coverage of tables and views, per object and in total. Read-only.
--
-- Used to measure database_review.md Finding 9 and the §13 documentation criteria the same way
-- each time, rather than counting by hand. Run with:
--
--     psql -f scripts/comment_coverage.sql
--
-- Archive schemas are listed but left out of the totals: they are being dropped (R.8, RG.7).

\echo 'Per object'
SELECT n.nspname                                        AS schema,
       c.relname                                        AS object,
       CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view'
                      WHEN 'm' THEN 'matview' ELSE 'partitioned' END AS kind,
       obj_description(c.oid, 'pg_class') IS NOT NULL   AS has_comment,
       count(a.attnum)                                  AS columns,
       count(col_description(c.oid, a.attnum))          AS commented
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE c.relkind IN ('r', 'v', 'm', 'p')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
GROUP BY n.nspname, c.relname, c.relkind, c.oid
ORDER BY 1, 2;

\echo 'Totals (excluding *_archive schemas)'
SELECT CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view'
                      WHEN 'm' THEN 'matview' ELSE 'partitioned' END AS kind,
       count(DISTINCT c.oid)                                                       AS objects,
       count(DISTINCT c.oid) FILTER (WHERE obj_description(c.oid, 'pg_class') IS NOT NULL)
                                                                                   AS with_comment,
       count(a.attnum)                                                             AS columns,
       count(col_description(c.oid, a.attnum))                                     AS commented
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE c.relkind IN ('r', 'v', 'm', 'p')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
  AND n.nspname NOT LIKE '%\_archive'
GROUP BY 1
ORDER BY 1;
