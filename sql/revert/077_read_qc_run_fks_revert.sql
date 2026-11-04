-- Revert 077_read_qc_run_fks.sql: drop the two read-QC run FKs and their indexes, and restore
-- refresh_sequencing_run() and sequencing_run's comment as 075 left them.
--     psql -f sql/revert/077_read_qc_run_fks_revert.sql   then delete 077's ledger row.

BEGIN;

ALTER TABLE hifi_read_qc DROP CONSTRAINT hifi_read_qc_run_id_fkey;
ALTER TABLE hic_read_qc  DROP CONSTRAINT hic_read_qc_run_id_fkey;
DROP INDEX public.hifi_read_qc_run_id_idx;
DROP INDEX public.hic_read_qc_run_id_idx;

-- refresh_sequencing_run() as it was before 077 (pg_get_functiondef of live, 2026-11-04).
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
     AND NOT EXISTS (SELECT 1 FROM raw_data d WHERE d.run_id = r.run_id)
     AND NOT EXISTS (SELECT 1 FROM rna_qc_kinnex k WHERE k.run_id = r.run_id);
END
$function$

;

COMMENT ON TABLE sequencing_run IS 'One sequencing run, derived from sequencing.run_id. Kept current by the sequencing_run_ensure and sequencing_run_refresh_* triggers on sequencing (075); sequencing, raw_data and rna_qc_kinnex have FKs to it.';

COMMIT;
