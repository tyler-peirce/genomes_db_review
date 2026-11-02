-- 075_r7_run_fks.sql -- Phase R.7: keep sequencing_run current from sequencing, and FK
-- sequencing, raw_data and rna_qc_kinnex to it.
--
-- Plan: docs/r7_plan.md; design docs/assembly_relations_plan.md R.7.
--
-- sequencing_run is derived from sequencing.run_id: one row per run, with mach / run_seq_date /
-- initial parsed from the run name and instrument / run_date where every sequencing row of the run
-- agrees. Until 072 (R.6), v3.sync_sequencing_run() rebuilt it every night; 072 dropped that
-- window-only function, and the nightly import (OceanOmics-Database/import_v2.py) does not write
-- sequencing_run. Without this file a run first seen after 2026-11-02 would get no sequencing_run
-- row. So the upkeep moves onto sequencing itself:
--   - sequencing_run_ensure (BEFORE INSERT OR UPDATE OF run_id, per row) creates the run before the
--     sequencing row lands, so the FK below can stay immediate. The importer writes in batches with
--     a row-by-row retry under savepoints; an immediate FK keeps that per-row behaviour.
--   - sequencing_run_refresh_* (AFTER INSERT / UPDATE / DELETE, per statement, transition tables)
--     re-derive instrument and run_date for the runs a statement touched, and delete a run that no
--     longer has a sequencing row and that no raw_data or rna_qc_kinnex row references.
-- refresh_sequencing_run() is the old sync's logic, restricted to the runs given.
--
-- Then FKs from sequencing.run_id (NULL allowed: 12 rows), raw_data.run_id and rna_qc_kinnex.run_id
-- to sequencing_run, NOT VALID then VALIDATE. 0 unmatched on live 2026-11-02. raw_data and
-- rna_qc_kinnex have no live writer (the SS/ importers are decommissioned).
--
-- Replay: when the three FKs exist, the file does nothing.
-- Revert: sql/revert/075_r7_run_fks_revert.sql.

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
     AND NOT EXISTS (SELECT 1 FROM rna_qc_kinnex k WHERE k.run_id = r.run_id);
END
$fn$;
COMMENT ON FUNCTION public.refresh_sequencing_run(text[]) IS
  'Re-derive the given runs in sequencing_run from sequencing (the logic of the Phase R window''s '
  'v3.sync_sequencing_run, per run), and drop a run nothing uses any more. Called by the triggers on '
  'sequencing. 075, Phase R.7.';

CREATE OR REPLACE FUNCTION public.sequencing_run_ensure() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  IF NEW.run_id IS NOT NULL AND NEW.run_id <> '' THEN
    INSERT INTO sequencing_run (run_id, mach, run_seq_date, initial)
    VALUES (NEW.run_id,
            substring(NEW.run_id FROM '^([A-Za-z-]+)_[0-9]{6}_.+$'),
            substring(NEW.run_id FROM '^[A-Za-z-]+_([0-9]{6})_.+$'),
            substring(NEW.run_id FROM '^[A-Za-z-]+_[0-9]{6}_(.+)$'))
    ON CONFLICT (run_id) DO NOTHING;
  END IF;
  RETURN NEW;
END
$fn$;
COMMENT ON FUNCTION public.sequencing_run_ensure() IS
  'Creates the sequencing_run row for a sequencing row''s run_id before the row lands, so the FK '
  'from sequencing.run_id holds immediately. 075, Phase R.7.';

CREATE OR REPLACE FUNCTION public.sequencing_run_refresh() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  -- PL/pgSQL plans each statement when it first runs, so a branch naming a transition table this
  -- trigger does not have is never planned.
  IF TG_OP = 'INSERT' THEN
    PERFORM refresh_sequencing_run(ARRAY(SELECT DISTINCT run_id FROM new_rows WHERE run_id IS NOT NULL));
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM refresh_sequencing_run(ARRAY(SELECT run_id FROM new_rows WHERE run_id IS NOT NULL
                                         UNION SELECT run_id FROM old_rows WHERE run_id IS NOT NULL));
  ELSE
    PERFORM refresh_sequencing_run(ARRAY(SELECT DISTINCT run_id FROM old_rows WHERE run_id IS NOT NULL));
  END IF;
  RETURN NULL;
END
$fn$;
COMMENT ON FUNCTION public.sequencing_run_refresh() IS
  'Statement-level: re-derives the runs a statement on sequencing touched. 075, Phase R.7.';

DO $r7b$
DECLARE
  n bigint;
BEGIN
  IF (SELECT count(*) FROM pg_constraint
       WHERE conname IN ('sequencing_run_id_fkey','raw_data_run_id_fkey','rna_qc_kinnex_run_id_fkey')
         AND contype = 'f' AND convalidated) = 3 THEN
    RAISE NOTICE '075: the three run FKs exist; nothing to do';
    RETURN;
  END IF;

  -- Bring every run up to date once (a no-op on 2026-11-02: 0 runs missing, 0 extra).
  PERFORM refresh_sequencing_run(ARRAY(SELECT DISTINCT run_id FROM sequencing WHERE run_id IS NOT NULL
                                       UNION SELECT run_id FROM sequencing_run));

  CREATE TRIGGER sequencing_run_ensure BEFORE INSERT OR UPDATE OF run_id ON sequencing
    FOR EACH ROW EXECUTE FUNCTION sequencing_run_ensure();
  CREATE TRIGGER sequencing_run_refresh_ins AFTER INSERT ON sequencing
    REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION sequencing_run_refresh();
  CREATE TRIGGER sequencing_run_refresh_upd AFTER UPDATE ON sequencing
    REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION sequencing_run_refresh();
  CREATE TRIGGER sequencing_run_refresh_del AFTER DELETE ON sequencing
    REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION sequencing_run_refresh();

  CREATE INDEX sequencing_run_id_idx ON sequencing (run_id);

  ALTER TABLE sequencing ADD CONSTRAINT sequencing_run_id_fkey
    FOREIGN KEY (run_id) REFERENCES sequencing_run (run_id) NOT VALID;
  ALTER TABLE raw_data ADD CONSTRAINT raw_data_run_id_fkey
    FOREIGN KEY (run_id) REFERENCES sequencing_run (run_id) NOT VALID;
  ALTER TABLE rna_qc_kinnex ADD CONSTRAINT rna_qc_kinnex_run_id_fkey
    FOREIGN KEY (run_id) REFERENCES sequencing_run (run_id) NOT VALID;
  ALTER TABLE sequencing VALIDATE CONSTRAINT sequencing_run_id_fkey;
  ALTER TABLE raw_data VALIDATE CONSTRAINT raw_data_run_id_fkey;
  ALTER TABLE rna_qc_kinnex VALIDATE CONSTRAINT rna_qc_kinnex_run_id_fkey;

  COMMENT ON TABLE sequencing_run IS
    'One sequencing run, derived from sequencing.run_id. Kept current by the sequencing_run_ensure and '
    'sequencing_run_refresh_* triggers on sequencing (075); sequencing, raw_data and rna_qc_kinnex '
    'have FKs to it.';

  -- Verify: every run is present, none is extra.
  SELECT count(DISTINCT run_id) INTO n FROM sequencing s
   WHERE run_id <> '' AND NOT EXISTS (SELECT 1 FROM sequencing_run r WHERE r.run_id = s.run_id);
  IF n <> 0 THEN RAISE EXCEPTION '075: % sequencing run(s) missing from sequencing_run', n; END IF;
  SELECT count(*) INTO n FROM sequencing_run r
   WHERE NOT EXISTS (SELECT 1 FROM sequencing s WHERE s.run_id = r.run_id)
     AND NOT EXISTS (SELECT 1 FROM raw_data d WHERE d.run_id = r.run_id)
     AND NOT EXISTS (SELECT 1 FROM rna_qc_kinnex k WHERE k.run_id = r.run_id);
  IF n <> 0 THEN RAISE EXCEPTION '075: % sequencing_run row(s) used by nothing', n; END IF;

  RAISE NOTICE '075: sequencing_run kept by triggers; three run FKs validated';
END
$r7b$;

COMMIT;
