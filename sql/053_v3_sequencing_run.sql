-- 053_v3_sequencing_run.sql -- Phase R.4: the run entity, in schema v3, with no FK yet.
--
-- Why. sequencing names 211 distinct runs (live 2026-10-16, after the stale-row cleanup), and
-- raw_data, hifi_reads_qc and hic_reads_qc all key on the run, but the database has no run
-- entity to point at (docs/assembly_relations_plan.md §5). This creates v3.sequencing_run,
-- one row per distinct sequencing.run_id, and a view that says how ready each would-be FK is.
--
-- What is deliberately not done. No foreign key to or from sequencing_run. A public table must
-- not point into v3 before the R.6 merge, because nothing in public may depend on v3. The FKs
-- (sequencing, raw_data, hifi_reads_qc, hic_reads_qc -> sequencing_run) are R.7's, once
-- v3.v_sequencing_run_fk_readiness shows 0 failing rows or the R.0.5 triage is dealt with.
--
-- Columns. mach, run_seq_date and initial are parsed from run_id as MACH_YYMMDD_INITIAL where
-- it parses (mixed-case and hyphenated machines such as iSeq_230531_LP and
-- ISEQ-cDNA_250404_LA are accepted). Two IDs do not parse, 20230414_CSIRO_LMHH and the
-- truncated NEXT_, and keep NULL parts. instrument and run_date are filled only where
-- every sequencing row of the run agrees; 4 runs disagree and keep NULL. Both cases are listed
-- by v3.v_sequencing_run_issues for the lab, not guessed.
--
-- Sync: v3.sync_sequencing_run() (window-only) adds and updates runs and removes runs no
-- sequencing row names any more; scripts/sync_v3.sql runs it nightly.
--
-- Revert: sql/revert/053_v3_sequencing_run_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regnamespace('v3') IS NULL THEN
    RAISE EXCEPTION '053 needs schema v3 from 051';
  END IF;
END
$pre$;

CREATE TABLE IF NOT EXISTS v3.sequencing_run (
    run_id       text PRIMARY KEY,
    mach         text,          -- parsed from run_id
    run_seq_date text,          -- parsed from run_id: the YYMMDD component, not a date
    initial      text,          -- parsed from run_id
    instrument   text,          -- where every sequencing row of the run agrees
    run_date     date,          -- where every sequencing row of the run agrees
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE v3.sequencing_run IS
  'One sequencing run, seeded from the distinct sequencing.run_id. FKs to it arrive at R.7.';

CREATE OR REPLACE FUNCTION v3.sync_sequencing_run() RETURNS TABLE (step text, changed bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  n bigint;
BEGIN
  DELETE FROM v3.sequencing_run r
  WHERE NOT EXISTS (SELECT 1 FROM public.sequencing s WHERE s.run_id = r.run_id);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.sequencing_run AS t (run_id, mach, run_seq_date, initial, instrument, run_date)
  SELECT s.run_id,
         substring(s.run_id FROM '^([A-Za-z-]+)_[0-9]{6}_.+$'),
         substring(s.run_id FROM '^[A-Za-z-]+_([0-9]{6})_.+$'),
         substring(s.run_id FROM '^[A-Za-z-]+_[0-9]{6}_(.+)$'),
         CASE WHEN count(DISTINCT s.instrument) = 1 AND count(s.instrument) = count(*) THEN min(s.instrument) END,
         CASE WHEN count(DISTINCT s.run_date)   = 1 AND count(s.run_date)   = count(*) THEN min(s.run_date)   END
  FROM public.sequencing s
  WHERE s.run_id IS NOT NULL AND s.run_id <> ''
  GROUP BY s.run_id
  ON CONFLICT (run_id) DO UPDATE
    SET mach = EXCLUDED.mach, run_seq_date = EXCLUDED.run_seq_date, initial = EXCLUDED.initial,
        instrument = EXCLUDED.instrument, run_date = EXCLUDED.run_date, updated_at = now()
    WHERE (t.mach, t.run_seq_date, t.initial, t.instrument, t.run_date)
          IS DISTINCT FROM (EXCLUDED.mach, EXCLUDED.run_seq_date, EXCLUDED.initial,
                            EXCLUDED.instrument, EXCLUDED.run_date);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run upserted'; changed := n; RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v3.sync_sequencing_run() IS
  'Phase R window only: derive v3.sequencing_run from public.sequencing. Dropped at the R.6 merge.';

CREATE OR REPLACE VIEW v3.v_sequencing_run_issues AS
SELECT r.run_id,
       (r.mach IS NULL) AS run_id_unparsed,
       (r.instrument IS NULL) AS instrument_disagrees_or_missing,
       (r.run_date IS NULL) AS run_date_disagrees_or_missing,
       (SELECT string_agg(DISTINCT coalesce(s.instrument, '(null)'), ', ') FROM public.sequencing s WHERE s.run_id = r.run_id) AS instruments,
       (SELECT string_agg(DISTINCT coalesce(s.run_date::text, '(null)'), ', ') FROM public.sequencing s WHERE s.run_id = r.run_id) AS run_dates
FROM v3.sequencing_run r
WHERE r.mach IS NULL OR r.instrument IS NULL OR r.run_date IS NULL;
COMMENT ON VIEW v3.v_sequencing_run_issues IS
  'Runs whose ID does not parse, or whose sequencing rows disagree on instrument or run date. For the lab.';

CREATE OR REPLACE VIEW v3.v_sequencing_run_fk_readiness AS
SELECT 'sequencing' AS child, count(*) AS child_rows,
       count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
       string_agg(DISTINCT c.run_id, ', ') FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
FROM public.sequencing c LEFT JOIN v3.sequencing_run r ON r.run_id = c.run_id
UNION ALL
SELECT 'raw_data', count(*),
       count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL),
       string_agg(DISTINCT c.run_id, ', ') FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL)
FROM public.raw_data c LEFT JOIN v3.sequencing_run r ON r.run_id = c.run_id
UNION ALL
SELECT 'hifi_reads_qc', count(*),
       count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL),
       string_agg(DISTINCT c.run_id, ', ') FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL)
FROM public.hifi_reads_qc c LEFT JOIN v3.sequencing_run r ON r.run_id = c.run_id
UNION ALL
SELECT 'hic_reads_qc', count(*),
       count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL),
       string_agg(DISTINCT c.run_id, ', ') FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL)
FROM public.hic_reads_qc c LEFT JOIN v3.sequencing_run r ON r.run_id = c.run_id;
COMMENT ON VIEW v3.v_sequencing_run_fk_readiness IS
  'For each table R.7 will FK to sequencing_run: rows that would fail today, and their run IDs.';

SELECT * FROM v3.sync_sequencing_run();

DO $verify$
DECLARE
  n_runs int;
  n_seq  int;
BEGIN
  SELECT count(*) INTO n_runs FROM v3.sequencing_run;
  SELECT count(DISTINCT run_id) INTO n_seq FROM public.sequencing WHERE run_id IS NOT NULL AND run_id <> '';
  IF n_runs <> n_seq THEN
    RAISE EXCEPTION '053: % runs in v3.sequencing_run, % distinct in sequencing', n_runs, n_seq;
  END IF;
  IF (SELECT failing_rows FROM v3.v_sequencing_run_fk_readiness WHERE child = 'sequencing') <> 0 THEN
    RAISE EXCEPTION '053: a sequencing row has a run_id not in v3.sequencing_run';
  END IF;
END
$verify$;

GRANT SELECT ON v3.sequencing_run, v3.v_sequencing_run_issues, v3.v_sequencing_run_fk_readiness TO readonly;

COMMIT;
