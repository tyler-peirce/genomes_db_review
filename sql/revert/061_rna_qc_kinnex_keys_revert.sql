-- 061_rna_qc_kinnex_keys_revert.sql -- undo 061: drop the FKs, indexes and primary key, and
-- restore UNIQUE (run_id, rna_tube_id) and a nullable run_id. The table stays: 061 captured it,
-- it did not create it on live, and dropping it would be data loss, not a rollback.
--
-- After running this, delete 061's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '061_rna_qc_kinnex_keys.sql';

BEGIN;

ALTER TABLE public.rna_qc_kinnex DROP CONSTRAINT IF EXISTS rna_qc_kinnex_rna_tube_id_fkey;
ALTER TABLE public.rna_qc_kinnex DROP CONSTRAINT IF EXISTS rna_qc_kinnex_rna_tube_id_2_fkey;
DROP INDEX IF EXISTS public.rna_qc_kinnex_rna_tube_id_idx;
DROP INDEX IF EXISTS public.rna_qc_kinnex_rna_tube_id_2_idx;

DO $u$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'public.rna_qc_kinnex'::regclass AND conname = 'rna_qc_run_id_tube_uniq') THEN
    ALTER TABLE public.rna_qc_kinnex ADD CONSTRAINT rna_qc_run_id_tube_uniq UNIQUE (run_id, rna_tube_id);
  END IF;
END
$u$;
ALTER TABLE public.rna_qc_kinnex DROP CONSTRAINT IF EXISTS rna_qc_kinnex_pkey;
ALTER TABLE public.rna_qc_kinnex ALTER COLUMN run_id DROP NOT NULL;
COMMENT ON TABLE public.rna_qc_kinnex IS NULL;

COMMIT;
