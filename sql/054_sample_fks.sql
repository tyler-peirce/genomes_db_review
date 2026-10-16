-- 054_sample_fks.sql -- Phase R.4: declare five FKs to sample between existing public tables.
--
-- Why. These tables each carry an og_id but declare no relation to sample
-- (docs/assembly_relations_plan.md §5). Live, 2026-10-16:
--   ena_specimen_accessions.og_id      2,848 rows, all in sample
--   og_workflow_recommendation.og_id   0 rows
--   og_workflow_assignment_log.og_id   0 rows
--   og_workflow_notification.og_id     5 rows, all in sample
--   raw_data.og_id                     8,010 rows: 7,980 in sample, 30 NULL (allowed by an FK;
--                                      left for the lab, docs/assembly_relations_r0_record.md)
-- Owner decision 9 (2026-10-16): declare the og_workflow_* FKs. The og_workflow_* tables
-- belong to OceanGenom_Web; from now on the app must write a sample before anything that names
-- it, which it does today.
--
-- Nothing new is created and nothing in v3 is involved, so this does not wait for the merge.
--
-- How. Each FK is added NOT VALID, then VALIDATEd, so a failure names the constraint. No
-- ON DELETE action, matching the other FKs to sample. Each child column gets an index where
-- it has none (ena_specimen_accessions and og_workflow_recommendation already lead an index
-- with og_id, as their primary keys).
--
-- Revert: sql/revert/054_sample_fks_revert.sql.

BEGIN;

DO $fks$
DECLARE
  f record;
BEGIN
  FOR f IN SELECT * FROM (VALUES
      ('ena_specimen_accessions',    'ena_specimen_accessions_og_id_fkey'),
      ('og_workflow_recommendation', 'og_workflow_recommendation_og_id_fkey'),
      ('og_workflow_assignment_log', 'og_workflow_assignment_log_og_id_fkey'),
      ('og_workflow_notification',   'og_workflow_notification_og_id_fkey'),
      ('raw_data',                   'raw_data_og_id_fkey')) AS v (tbl, con)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conrelid = ('public.' || f.tbl)::regclass AND conname = f.con) THEN
      EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (og_id) '
                     'REFERENCES public.sample (og_id) NOT VALID', f.tbl, f.con);
    END IF;
    EXECUTE format('ALTER TABLE public.%I VALIDATE CONSTRAINT %I', f.tbl, f.con);
  END LOOP;
END
$fks$;

CREATE INDEX IF NOT EXISTS og_workflow_assignment_log_og_id_idx ON public.og_workflow_assignment_log (og_id);
CREATE INDEX IF NOT EXISTS og_workflow_notification_og_id_idx   ON public.og_workflow_notification (og_id);
CREATE INDEX IF NOT EXISTS raw_data_og_id_idx                   ON public.raw_data (og_id);

COMMIT;
