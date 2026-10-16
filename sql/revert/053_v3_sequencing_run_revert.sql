-- 053_v3_sequencing_run_revert.sql -- remove v3.sequencing_run and its views.
--
-- Nothing references sequencing_run before R.7, so this loses nothing.
--
-- After running this, delete 053's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '053_v3_sequencing_run.sql';

BEGIN;

DROP VIEW IF EXISTS v3.v_sequencing_run_fk_readiness;
DROP VIEW IF EXISTS v3.v_sequencing_run_issues;
DROP FUNCTION IF EXISTS v3.sync_sequencing_run();
DROP TABLE IF EXISTS v3.sequencing_run;

COMMIT;
