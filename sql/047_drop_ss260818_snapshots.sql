-- sql/cutover/drop_ss260818_snapshots.sql -- Phase F: drop the eight SS260818 snapshot objects.
--
-- Prerequisite for Phase V.6. lca_results_view_SS260818 reads sample_pre_v2, the only
-- dependant of a _pre_v2 relation outside the _pre_v2 set itself, and mitogenome_data_SS260818
-- holds the index name mitogenome_data_pkey, which v2.mitogenome_data needs when it moves into
-- public. Kept outside the numbered sequence until the day, like 045, and numbered when it runs
-- (docs/phase_v6_plan.md, Apply).
--
-- What goes: three views, then five tables, in dependency order. Four of the five tables are
-- archived in archive/snapshots_SS260818/ (exported 2026-10-05, verified EXCEPT-identical).
-- The fifth, blast_filtered_lca_SS260818 (192,207 rows), was deliberately kept out of the repo
-- for size -- see that directory's MANIFEST.md -- so it must be exported somewhere else first.
--
-- Opt-in: refuses to run unless the operator passes the row count of a verified export of
-- blast_filtered_lca_SS260818, and that count equals the table's:
--
--   PGOPTIONS="-c oceanomics.blast_filtered_lca_ss260818_exported_rows=192207" bin/apply_migrations.py
--
-- A drop that loses the only copy of 192k rows should not be one keystroke away.
--
-- What stays: lca_validation_report_view_upd(). It is the INSTEAD OF UPDATE trigger function of
-- lca_validation_report_view_SS260818 AND of the live lca_validation_report_view (033). Dropping
-- the snapshot view removes only its own trigger; this file checks the live one survives.
--
-- Phase F item 4 (reclaim the clean mitogenome_data index names) is not done here: V.6 does it,
-- because v2.mitogenome_data already carries the clean names and brings them into public, and
-- the _1-suffixed indexes leave with mitogenome_data_pre_v2 into pre_v2_archive.
--
-- Consequence, accepted in Phase F: sql/revert/027_reporting_views_live_tables_revert.sql reads
-- lca_validation_SS260818 and mitogenome_data_SS260818 and can no longer run.
--
-- Replay: the drops are IF EXISTS and the guard is skipped once the tables are gone, so a
-- crash-recovery replay is a no-op.
--
-- Revert: drop_ss260818_snapshots_revert.sql (sql/revert/NNN_... on the day). Structure only.

BEGIN;

DO $guard$
DECLARE
  n bigint;
BEGIN
  IF to_regclass('public."blast_filtered_lca_SS260818"') IS NULL THEN
    RETURN;  -- already dropped; replay
  END IF;
  SELECT count(*) INTO n FROM public."blast_filtered_lca_SS260818";
  IF coalesce(current_setting('oceanomics.blast_filtered_lca_ss260818_exported_rows', true), '')
       <> n::text THEN
    RAISE EXCEPTION 'blast_filtered_lca_SS260818 has % rows and is archived nowhere else. Export it, '
      'verify the export, then run with '
      'PGOPTIONS="-c oceanomics.blast_filtered_lca_ss260818_exported_rows=%" (docs/phase_v6_plan.md)', n, n;
  END IF;
END
$guard$;

DROP VIEW IF EXISTS public."lca_validation_report_view_SS260818";
DROP VIEW IF EXISTS public."lca_results_view_SS260818";
DROP VIEW IF EXISTS public."lca_pivot_view_SS260818";

DROP TABLE IF EXISTS public."lca_SS260818";
DROP TABLE IF EXISTS public."lca_raw_results_SS260818";
DROP TABLE IF EXISTS public."lca_validation_SS260818";
DROP TABLE IF EXISTS public."blast_filtered_lca_SS260818";
DROP TABLE IF EXISTS public."mitogenome_data_SS260818";

DO $verify$
DECLARE
  left_over text;
BEGIN
  SELECT string_agg(relname, ', ') INTO left_over
    FROM pg_class WHERE relname LIKE '%SS260818%' AND relkind IN ('r', 'v', 'm');
  IF left_over IS NOT NULL THEN
    RAISE EXCEPTION 'SS260818 objects still present: %', left_over;
  END IF;
  IF to_regprocedure('public.lca_validation_report_view_upd()') IS NULL THEN
    RAISE EXCEPTION 'lca_validation_report_view_upd() is gone; the live view needs it';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgrelid = 'public.lca_validation_report_view'::regclass
                    AND tgfoid = 'public.lca_validation_report_view_upd()'::regprocedure) THEN
    RAISE EXCEPTION 'lca_validation_report_view lost its INSTEAD OF UPDATE trigger';
  END IF;
END
$verify$;

COMMIT;
