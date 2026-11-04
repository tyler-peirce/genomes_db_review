-- 077_read_qc_run_fks.sql -- FK hifi_read_qc.run_id and hic_read_qc.run_id to sequencing_run.
--
-- Plan: docs/next_steps_plan.md, part A (owner decision 2026-11-04: strict).
--
-- RG.6 (073) left these two FKs for "once something maintains sequencing_run"; 075 added that
-- upkeep (triggers on sequencing) and FK'd sequencing, raw_data and rna_qc_kinnex, but not the
-- read-QC tables. Strict: a read-QC push for a run the lab workbook does not list yet is refused.
-- Both writers report it and exit 1 -- 0b_push_hifi_yield_results_to_sqldb.py (one transaction)
-- and push_hic_yield.py (per row) -- and the row lands once the run is imported and the push is
-- re-run. RG.0 found 29 such rows; 069 resolved them, and on 2026-11-04 every run_id in both
-- tables (279 and 552 rows, none NULL) is in sequencing_run.
--
-- refresh_sequencing_run() also learns to keep a run that read QC still uses, so removing a
-- run's last sequencing row leaves the run in place instead of failing on these FKs.
--
-- Replay: when both FKs exist, the file does nothing.
-- Revert: sql/revert/077_read_qc_run_fks_revert.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.refresh_sequencing_run(p_runs text[]) RETURNS void
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
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
     AND NOT EXISTS (SELECT 1 FROM rna_qc_kinnex k WHERE k.run_id = r.run_id)
     AND NOT EXISTS (SELECT 1 FROM hifi_read_qc h WHERE h.run_id = r.run_id)
     AND NOT EXISTS (SELECT 1 FROM hic_read_qc c WHERE c.run_id = r.run_id);
END
$fn$;

DO $a$
DECLARE
  n bigint;
BEGIN
  IF (SELECT count(*) FROM pg_constraint
       WHERE conname IN ('hifi_read_qc_run_id_fkey', 'hic_read_qc_run_id_fkey') AND contype = 'f') = 2 THEN
    RAISE NOTICE '077: both read-QC run FKs exist; nothing to do';
    RETURN;
  END IF;

  SELECT (SELECT count(*) FROM hifi_read_qc q WHERE NOT EXISTS (SELECT 1 FROM sequencing_run r WHERE r.run_id = q.run_id))
       + (SELECT count(*) FROM hic_read_qc q WHERE NOT EXISTS (SELECT 1 FROM sequencing_run r WHERE r.run_id = q.run_id))
    INTO n;
  IF n <> 0 THEN
    RAISE EXCEPTION '077: % read-QC row(s) name a run that is not in sequencing_run; fix them in the '
      'workbook (or the row) first', n;
  END IF;

  CREATE INDEX hifi_read_qc_run_id_idx ON hifi_read_qc (run_id);
  CREATE INDEX hic_read_qc_run_id_idx ON hic_read_qc (run_id);
  ALTER TABLE hifi_read_qc ADD CONSTRAINT hifi_read_qc_run_id_fkey
    FOREIGN KEY (run_id) REFERENCES sequencing_run (run_id) NOT VALID;
  ALTER TABLE hic_read_qc ADD CONSTRAINT hic_read_qc_run_id_fkey
    FOREIGN KEY (run_id) REFERENCES sequencing_run (run_id) NOT VALID;
  ALTER TABLE hifi_read_qc VALIDATE CONSTRAINT hifi_read_qc_run_id_fkey;
  ALTER TABLE hic_read_qc VALIDATE CONSTRAINT hic_read_qc_run_id_fkey;

  COMMENT ON TABLE sequencing_run IS
    'One sequencing run, derived from sequencing.run_id. Kept current by the sequencing_run_ensure and '
    'sequencing_run_refresh_* triggers on sequencing (075); sequencing, raw_data, rna_qc_kinnex (075), '
    'hifi_read_qc and hic_read_qc (077) have FKs to it.';

  -- A read-QC row for a run the lab has not recorded is refused. Copy a real row onto an unknown
  -- run, inside a sub-block that is always rolled back.
  BEGIN
    -- The whole row (it must satisfy hic_read_qc_has_value), with only run_id changed.
    EXECUTE (
      SELECT format('INSERT INTO hic_read_qc (%s) SELECT %s FROM hic_read_qc LIMIT 1',
                    string_agg(format('%I', column_name), ', ' ORDER BY ordinal_position),
                    string_agg(CASE WHEN column_name = 'run_id' THEN quote_literal('NOVA_000000_PROBE077')
                                    ELSE format('%I', column_name) END, ', ' ORDER BY ordinal_position))
        FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'hic_read_qc'
         AND is_identity = 'NO' AND is_generated = 'NEVER');
    RAISE EXCEPTION USING ERRCODE = 'P0077', MESSAGE = 'probe insert succeeded';
  EXCEPTION
    WHEN SQLSTATE 'P0077' THEN
      RAISE EXCEPTION '077: a hic_read_qc row on an unknown run was accepted';
    WHEN foreign_key_violation THEN
      NULL;
  END;

  RAISE NOTICE '077: hifi_read_qc and hic_read_qc run_id FKs validated';
END
$a$;

COMMIT;
