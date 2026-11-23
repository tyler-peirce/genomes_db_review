-- 090_refresh_sequencing_run_without_raw_data.sql -- stop refresh_sequencing_run() reading raw_data,
-- which 089 dropped.
--
-- Why. 089 dropped raw_data, but refresh_sequencing_run() (075) still checked it before deleting
-- a run nothing uses. PL/pgSQL bodies are not dependency-tracked, so the drop did not refuse, and
-- 089's rehearsal selected every view but wrote to no table. The triggers on sequencing call this
-- function, so from 089 (2026-11-23 01:56 UTC) until this migration, any write to sequencing
-- failed with "relation raw_data does not exist". The nightly import runs at 18:00 UTC; no import
-- ran in between.
--
-- Change: the NOT EXISTS on raw_data is removed. Nothing else changes: the same upsert, and a run
-- is still kept while sequencing, rna_qc_kinnex, hifi_read_qc or hic_read_qc names it.
--
-- Must not be done later: drop a table without searching function bodies for it
-- (SELECT oid::regprocedure FROM pg_proc WHERE prosrc ~ '\m<table>\M'). Added to
-- docs/database_change_checklist.md.
--
-- Revert: sql/revert/090_refresh_sequencing_run_without_raw_data_revert.sql (the 075 body). Revert
-- 090 before 089 only, since the old body needs raw_data.
-- Replay: CREATE OR REPLACE with the same body is a no-op.

BEGIN;

CREATE OR REPLACE FUNCTION public.refresh_sequencing_run(p_runs text[])
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO sequencing_run AS t (run_id, mach, run_seq_date, initial, instrument, run_date)
  SELECT s.run_id,
         substring(s.run_id FROM '^([A-Za-z-]+)_[0-9]{6}_.+$'),
         substring(s.run_id FROM '^[A-Za-z-]+_([0-9]{6})_.+$'),
         substring(s.run_id FROM '^[A-Za-z-]+_[0-9]{6}_(.+)$'),
         CASE WHEN count(DISTINCT s.instrument) = 1 AND count(s.instrument) = count(*) THEN min(s.instrument) END,
         CASE WHEN count(DISTINCT s.run_date)   = 1 AND count(s.run_date)   = count(*) THEN min(s.run_date)   END
    FROM sequencing s
   WHERE s.run_id = ANY (p_runs) AND s.run_id <> ''
   GROUP BY s.run_id
  ON CONFLICT (run_id) DO UPDATE
    SET mach = EXCLUDED.mach, run_seq_date = EXCLUDED.run_seq_date, initial = EXCLUDED.initial,
        instrument = EXCLUDED.instrument, run_date = EXCLUDED.run_date, updated_at = now()
    WHERE (t.mach, t.run_seq_date, t.initial, t.instrument, t.run_date)
          IS DISTINCT FROM (EXCLUDED.mach, EXCLUDED.run_seq_date, EXCLUDED.initial,
                            EXCLUDED.instrument, EXCLUDED.run_date);

  DELETE FROM sequencing_run r
   WHERE r.run_id = ANY (p_runs)
     AND NOT EXISTS (SELECT 1 FROM sequencing s WHERE s.run_id = r.run_id)
     AND NOT EXISTS (SELECT 1 FROM rna_qc_kinnex k WHERE k.run_id = r.run_id)
     AND NOT EXISTS (SELECT 1 FROM hifi_read_qc h WHERE h.run_id = r.run_id)
     AND NOT EXISTS (SELECT 1 FROM hic_read_qc c WHERE c.run_id = r.run_id);
END
$function$;

COMMIT;
