-- Revert 075_r7_run_fks.sql: drop the three run FKs, the sequencing.run_id index, the upkeep
-- triggers and their functions, and restore sequencing_run's comment.
--
-- After it nothing keeps sequencing_run current: a run first seen after the revert gets no row.
--
--     psql -f sql/revert/075_r7_run_fks_revert.sql   then delete 075's ledger row.

BEGIN;

ALTER TABLE sequencing    DROP CONSTRAINT sequencing_run_id_fkey;
ALTER TABLE raw_data      DROP CONSTRAINT raw_data_run_id_fkey;
ALTER TABLE rna_qc_kinnex DROP CONSTRAINT rna_qc_kinnex_run_id_fkey;
DROP INDEX public.sequencing_run_id_idx;

DROP TRIGGER sequencing_run_ensure ON sequencing;
DROP TRIGGER sequencing_run_refresh_ins ON sequencing;
DROP TRIGGER sequencing_run_refresh_upd ON sequencing;
DROP TRIGGER sequencing_run_refresh_del ON sequencing;

DROP FUNCTION public.sequencing_run_refresh();
DROP FUNCTION public.sequencing_run_ensure();
DROP FUNCTION public.refresh_sequencing_run(text[]);

COMMENT ON TABLE sequencing_run IS
  'One sequencing run, seeded from the distinct sequencing.run_id. FKs to it arrive at R.7.';

COMMIT;
