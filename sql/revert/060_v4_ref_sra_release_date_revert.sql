-- 060_v4_ref_sra_release_date_revert.sql -- release_date back to 059's status_date.
--
-- Renames the column, view column and constraint back, and restores 059's comments and sync
-- function by re-running 059's definitions (re-apply 059 after this: every object in it is
-- CREATE ... IF NOT EXISTS or CREATE OR REPLACE, so only the function and comments change).
--
-- After running this, delete 060's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '060_v4_ref_sra_release_date.sql';
-- then re-run 059's function and comments, e.g. psql -f sql/059_v4_ref_submission.sql (its
-- sync is then a no-op and its checks pass).

BEGIN;

DO $rev$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'v4' AND table_name = 'ref_sra_upload' AND column_name = 'release_date') THEN
    ALTER TABLE v4.ref_sra_upload RENAME COLUMN release_date TO status_date;
    ALTER TABLE v4.ref_sra_upload RENAME CONSTRAINT ref_sra_upload_status_or_release_date TO ref_sra_upload_status_or_date;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'v4' AND table_name = 'sync_ref_sra_source' AND column_name = 'release_date') THEN
    ALTER VIEW v4.sync_ref_sra_source RENAME COLUMN release_date TO status_date;
  END IF;
END
$rev$;

COMMIT;
