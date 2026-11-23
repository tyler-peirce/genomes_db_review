-- 091_drop_archive_schemas_revert.sql -- undo 091: restore pre_v2_archive, pre_v3_archive and
-- pre_v4_archive, with their rows, from the dump taken before the drop.
--
-- This is not a psql script: the schemas come back with pg_restore. From a shell, with the usual
-- connection settings (~/postgresql_details/oceanomics.cfg):
--
--   sha256sum ~/oceanomics_genomes_archives_pre_091_261123.dump
--     # must be f5f3945840862b6220a2c390c687445f60dd3b9dd502cbf81efedde4d87312e9
--   pg_restore -h <host> -p <port> -U postgres -d oceanomics_genomes \
--     ~/oceanomics_genomes_archives_pre_091_261123.dump
--
-- then delete 091's ledger row. The dump carries the schemas, tables, rows, keys, indexes,
-- views, trigger functions, triggers, comments and grants (readonly, oceangenom_web) as they were
-- on 2026-11-23. Rehearsed: the restore reproduced all 35 tables' row counts and row-set md5s
-- and a schema identical to before the drop.
--
-- Running this file with psql does nothing but say so.

\echo '091 revert: restore with pg_restore; see the header of this file.'
