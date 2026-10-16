-- 054_sample_fks_revert.sql -- drop the five FKs to sample, and the indexes 054 created.
--
-- After running this, delete 054's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '054_sample_fks.sql';

BEGIN;

ALTER TABLE public.ena_specimen_accessions    DROP CONSTRAINT IF EXISTS ena_specimen_accessions_og_id_fkey;
ALTER TABLE public.og_workflow_recommendation DROP CONSTRAINT IF EXISTS og_workflow_recommendation_og_id_fkey;
ALTER TABLE public.og_workflow_assignment_log DROP CONSTRAINT IF EXISTS og_workflow_assignment_log_og_id_fkey;
ALTER TABLE public.og_workflow_notification   DROP CONSTRAINT IF EXISTS og_workflow_notification_og_id_fkey;
ALTER TABLE public.raw_data                   DROP CONSTRAINT IF EXISTS raw_data_og_id_fkey;

DROP INDEX IF EXISTS public.og_workflow_assignment_log_og_id_idx;
DROP INDEX IF EXISTS public.og_workflow_notification_og_id_idx;
DROP INDEX IF EXISTS public.raw_data_og_id_idx;

COMMIT;
