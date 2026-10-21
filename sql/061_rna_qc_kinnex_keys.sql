-- 061_rna_qc_kinnex_keys.sql -- Phase C.2 for rna_qc_kinnex: capture the table, give it a
-- primary key, and FK both tube columns to rna_library_kinx.
--
-- Why. rna_qc_kinnex (Kinnex RNA read QC, one row per library per run) arrived by direct DDL:
-- no migration creates it, and it has no primary key and no FK (Finding 13). Live, 2026-10-20:
--   96 rows; rna_tube_id 96 distinct, 0 NULL, all 96 in rna_library_kinx;
--   rna_tube_id_2 set on 32 rows, all 32 in rna_library_kinx, none equal to rna_tube_id;
--   run_id set on all 96, every one in v3.sequencing_run, and every (rna_tube_id, run_id) has a
--   sequencing row;
--   an existing UNIQUE (run_id, rna_tube_id), rna_qc_run_id_tube_uniq. Finding 13's "no unique
--   constraint" was out of date.
-- No writer exists in any repository on this host; the rows predate the migration rule.
--
-- How.
--   1. CREATE TABLE IF NOT EXISTS with the live shape, so a rebuild from sql/ has the table
--      (Phase C.0's catch-up rule: capture a table in the change that constrains it). On live
--      it is a no-op.
--   2. The primary key is (run_id, rna_tube_id), not rna_tube_id alone. QC describes a library
--      on a run; a library sequenced again gets a second row. That is the existing unique key,
--      which the primary key replaces. run_id becomes NOT NULL.
--   3. rna_tube_id and rna_tube_id_2 -> rna_library_kinx(rna_library_tube_id), NOT VALID then
--      VALIDATE, as 054. No ON DELETE action. Both columns are indexed.
--   4. Assert the row count and the constraints before COMMIT.
--
-- Rejected: PRIMARY KEY (rna_tube_id). True today, but it would refuse the first resequenced
-- library's QC.
--
-- Not here, and why:
--   run_id -> sequencing_run: sequencing_run is in v3, and public must not point into v3 before
--   the merge. It is on R.7's list (docs/assembly_relations_plan.md) beside sequencing.run_id
--   and raw_data.run_id.
--
-- Depends on: OceanOmics-Database import_v2.py counting rna_qc_kinnex as a dependent of
-- rna_library_kinx (DEPENDENTS), so a displaced Kinnex tube with QC rows is quarantined, not
-- deleted. Without it the delete would fail on this FK and roll back the whole nightly import.
--
-- Revert: sql/revert/061_rna_qc_kinnex_keys_revert.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS public.rna_qc_kinnex (
  rna_tube_id      text    NOT NULL,
  rna_tube_id_2    text,
  read_count       bigint,
  run_id           text,
  read_length_mean integer,
  read_length_n50  integer
);

DO $keys$
DECLARE
  n_before bigint;
  n bigint;
BEGIN
  SELECT count(*) INTO n_before FROM public.rna_qc_kinnex;

  ALTER TABLE public.rna_qc_kinnex ALTER COLUMN run_id SET NOT NULL;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'public.rna_qc_kinnex'::regclass AND contype = 'p') THEN
    ALTER TABLE public.rna_qc_kinnex
      ADD CONSTRAINT rna_qc_kinnex_pkey PRIMARY KEY (run_id, rna_tube_id);
  END IF;
  ALTER TABLE public.rna_qc_kinnex DROP CONSTRAINT IF EXISTS rna_qc_run_id_tube_uniq;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'public.rna_qc_kinnex'::regclass
                   AND conname = 'rna_qc_kinnex_rna_tube_id_fkey') THEN
    ALTER TABLE public.rna_qc_kinnex ADD CONSTRAINT rna_qc_kinnex_rna_tube_id_fkey
      FOREIGN KEY (rna_tube_id) REFERENCES public.rna_library_kinx (rna_library_tube_id) NOT VALID;
  END IF;
  ALTER TABLE public.rna_qc_kinnex VALIDATE CONSTRAINT rna_qc_kinnex_rna_tube_id_fkey;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'public.rna_qc_kinnex'::regclass
                   AND conname = 'rna_qc_kinnex_rna_tube_id_2_fkey') THEN
    ALTER TABLE public.rna_qc_kinnex ADD CONSTRAINT rna_qc_kinnex_rna_tube_id_2_fkey
      FOREIGN KEY (rna_tube_id_2) REFERENCES public.rna_library_kinx (rna_library_tube_id) NOT VALID;
  END IF;
  ALTER TABLE public.rna_qc_kinnex VALIDATE CONSTRAINT rna_qc_kinnex_rna_tube_id_2_fkey;

  CREATE INDEX IF NOT EXISTS rna_qc_kinnex_rna_tube_id_idx   ON public.rna_qc_kinnex (rna_tube_id);
  CREATE INDEX IF NOT EXISTS rna_qc_kinnex_rna_tube_id_2_idx ON public.rna_qc_kinnex (rna_tube_id_2);

  SELECT count(*) INTO n FROM public.rna_qc_kinnex;
  IF n <> n_before THEN
    RAISE EXCEPTION '061: rna_qc_kinnex has % rows, expected %', n, n_before;
  END IF;
  SELECT count(*) INTO n FROM pg_constraint
  WHERE conrelid = 'public.rna_qc_kinnex'::regclass AND convalidated
    AND conname IN ('rna_qc_kinnex_pkey', 'rna_qc_kinnex_rna_tube_id_fkey',
                    'rna_qc_kinnex_rna_tube_id_2_fkey');
  IF n <> 3 THEN
    RAISE EXCEPTION '061: expected 3 validated constraints on rna_qc_kinnex, found %', n;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint
             WHERE conrelid = 'public.rna_qc_kinnex'::regclass AND conname = 'rna_qc_run_id_tube_uniq') THEN
    RAISE EXCEPTION '061: rna_qc_run_id_tube_uniq is still present';
  END IF;
  RAISE NOTICE '061: rna_qc_kinnex % rows; primary key (run_id, rna_tube_id); 2 FKs to rna_library_kinx', n_before;
END
$keys$;

COMMENT ON TABLE public.rna_qc_kinnex IS
  'Kinnex RNA read QC: one row per library (rna_tube_id) per sequencing run (run_id). '
  'rna_tube_id_2 is a second library pooled into the same QC row. Keys and FKs: migration 061.';

COMMIT;
