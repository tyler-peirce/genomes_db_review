-- 062_v4_ref_read_set_revert.sql -- back to 058's read-QC shape: ref_genomescope and
-- ref_hifi_adapter_filter with their own og_id and seq_date, no read sets, no run links.
--
-- Each OG keeps the one read set v4.raw_qc shows (the undated one if any, else the latest dated),
-- with seq_date NULL, which is what 058's sync owns. v4 holds only copies until RG.6; the dates
-- and run links are re-applied by re-running 062. The tables, views and functions below are 058's
-- text, copied unchanged.
--
-- After running this, delete 062's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '062_v4_ref_read_set.sql';

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_read_set') IS NULL THEN
    RAISE EXCEPTION 'v4.ref_read_set does not exist; 062 is not applied';
  END IF;
END
$pre$;

DROP VIEW IF EXISTS v4.coverage_summary;
DROP VIEW IF EXISTS v4.raw_qc;
DROP VIEW IF EXISTS v4.v_read_set_run_readiness;
DROP VIEW IF EXISTS v4.sync_read_set_source;

CREATE TEMP TABLE revert062 ON COMMIT DROP AS
WITH pick AS (
  SELECT DISTINCT ON (og_id) og_id, read_set_id
  FROM v4.ref_read_set ORDER BY og_id, seq_date DESC NULLS FIRST
)
SELECT p.og_id,
       g.read_set_id IS NOT NULL AS has_gs, g.homozygosity, g.heterozygosity, g.genomesize, g.repeatsize,
       g.uniquesize, g.modelfit, g.errorrate, g.loaded_at AS gs_loaded_at,
       f.read_set_id IS NOT NULL AS has_af, f.contam_reads, f.loaded_at AS af_loaded_at
FROM pick p
LEFT JOIN v4.ref_genomescope g ON g.read_set_id = p.read_set_id
LEFT JOIN v4.ref_hifi_adapter_filter f ON f.read_set_id = p.read_set_id;

DROP TABLE v4.ref_genomescope, v4.ref_hifi_adapter_filter, v4.ref_read_set_run, v4.ref_read_set;
DROP FUNCTION IF EXISTS v4.ref_read_set_run_pacbio_only();

CREATE TABLE IF NOT EXISTS v4.ref_genomescope (
    read_set_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id           text NOT NULL REFERENCES public.sample (og_id),
    seq_date        text CHECK (seq_date ~ '^[0-9]{6}$'),  -- HiFi read set; NULL = unknown
    homozygosity    numeric(5,2),
    heterozygosity  numeric(5,2),
    genomesize      bigint,
    repeatsize      bigint,
    uniquesize      bigint,
    modelfit        numeric(5,2),
    errorrate       numeric(5,2),
    loaded_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_genomescope_has_value CHECK (num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate) > 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS ref_genomescope_natural_key ON v4.ref_genomescope (og_id, (coalesce(seq_date, '')));
COMMENT ON TABLE v4.ref_genomescope IS
  'GenomeScope2 k-mer profile of a HiFi read set. Written by 01a_push_genomescope_comp_results_to_sqldb.py (ref repo). seq_date NULL = before RG, read set unknown. A fish whose model failed carries the 1 Gb default genomesize (the writer''s rule).';

CREATE TABLE IF NOT EXISTS v4.ref_hifi_adapter_filter (
    read_set_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id         text NOT NULL REFERENCES public.sample (og_id),
    seq_date      text CHECK (seq_date ~ '^[0-9]{6}$'),  -- HiFi read set; NULL = unknown
    contam_reads  integer,
    loaded_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_hifi_adapter_filter_has_value CHECK (num_nonnulls(contam_reads) > 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS ref_hifi_adapter_filter_natural_key ON v4.ref_hifi_adapter_filter (og_id, (coalesce(seq_date, '')));
COMMENT ON TABLE v4.ref_hifi_adapter_filter IS
  'HiFiAdapterFilt: reads removed as adapter-contaminated, per HiFi read set. Written by 0a_push_hifiadapt_results_to_sqldb.py (ref repo). seq_date NULL = before RG, read set unknown.';

INSERT INTO v4.ref_genomescope (og_id, seq_date, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, loaded_at)
SELECT og_id, NULL, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, gs_loaded_at
FROM revert062 WHERE has_gs;
INSERT INTO v4.ref_hifi_adapter_filter (og_id, seq_date, contam_reads, loaded_at)
SELECT og_id, NULL, contam_reads, af_loaded_at FROM revert062 WHERE has_af;

CREATE OR REPLACE FUNCTION v4.sync_ref_read_qc() RETURNS TABLE (step text, changed bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp SET client_min_messages = warning AS $fn$
DECLARE
  n bigint;
BEGIN
  -- GenomeScope: public carries no read-set date, so the sync owns the seq_date IS NULL rows only.
  DELETE FROM v4.ref_genomescope t
  WHERE t.seq_date IS NULL
    AND NOT EXISTS (SELECT 1 FROM v4.sync_raw_qc_source s
                    WHERE s.og_id = t.og_id AND s.key_problem IS NULL AND num_nonnulls(s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_genomescope deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_genomescope AS t (og_id, seq_date, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate)
  SELECT s.og_id, NULL, s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate FROM v4.sync_raw_qc_source s
  WHERE s.key_problem IS NULL AND num_nonnulls(s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate) > 0
  ON CONFLICT (og_id, (coalesce(seq_date, ''))) DO UPDATE SET homozygosity = EXCLUDED.homozygosity, heterozygosity = EXCLUDED.heterozygosity, genomesize = EXCLUDED.genomesize, repeatsize = EXCLUDED.repeatsize, uniquesize = EXCLUDED.uniquesize, modelfit = EXCLUDED.modelfit, errorrate = EXCLUDED.errorrate, loaded_at = now()
    WHERE (t.homozygosity, t.heterozygosity, t.genomesize, t.repeatsize, t.uniquesize, t.modelfit, t.errorrate) IS DISTINCT FROM (EXCLUDED.homozygosity, EXCLUDED.heterozygosity, EXCLUDED.genomesize, EXCLUDED.repeatsize, EXCLUDED.uniquesize, EXCLUDED.modelfit, EXCLUDED.errorrate);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_genomescope upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_hifi_adapter_filter t
  WHERE t.seq_date IS NULL
    AND NOT EXISTS (SELECT 1 FROM v4.sync_raw_qc_source s
                    WHERE s.og_id = t.og_id AND s.key_problem IS NULL AND s.contam_reads IS NOT NULL);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_hifi_adapter_filter deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_hifi_adapter_filter AS t (og_id, seq_date, contam_reads)
  SELECT s.og_id, NULL, s.contam_reads FROM v4.sync_raw_qc_source s
  WHERE s.key_problem IS NULL AND s.contam_reads IS NOT NULL
  ON CONFLICT (og_id, (coalesce(seq_date, ''))) DO UPDATE SET contam_reads = EXCLUDED.contam_reads, loaded_at = now()
    WHERE t.contam_reads IS DISTINCT FROM EXCLUDED.contam_reads;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_hifi_adapter_filter upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.hifi_read_qc t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_read_qc_hifi_source s
                    WHERE s.key_problem IS NULL AND (s.og_id, s.tissue, s.ext_type, s.lib_code, s.run_id) = (t.og_id, t.tissue, t.ext_type, t.lib_code, t.run_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hifi_read_qc deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.hifi_read_qc AS t (og_id, tissue, ext_type, lib_code, run_id, sequencing_id, barcode, barcode_quality, hifi_reads, hifi_read_length, hifi_read_quality, hifi_yield, polymerase_read_length)
  SELECT s.og_id, s.tissue, s.ext_type, s.lib_code, s.run_id, s.resolved_sequencing_id, s.barcode, s.barcode_quality, s.hifi_reads, s.hifi_read_length, s.hifi_read_quality, s.hifi_yield, s.polymerase_read_length
  FROM v4.sync_read_qc_hifi_source s WHERE s.key_problem IS NULL
  ON CONFLICT (og_id, tissue, ext_type, lib_code, run_id) DO UPDATE SET sequencing_id = EXCLUDED.sequencing_id, barcode = EXCLUDED.barcode, barcode_quality = EXCLUDED.barcode_quality, hifi_reads = EXCLUDED.hifi_reads, hifi_read_length = EXCLUDED.hifi_read_length, hifi_read_quality = EXCLUDED.hifi_read_quality, hifi_yield = EXCLUDED.hifi_yield, polymerase_read_length = EXCLUDED.polymerase_read_length, loaded_at = now()
    WHERE (t.sequencing_id, t.barcode, t.barcode_quality, t.hifi_reads, t.hifi_read_length, t.hifi_read_quality, t.hifi_yield, t.polymerase_read_length) IS DISTINCT FROM (EXCLUDED.sequencing_id, EXCLUDED.barcode, EXCLUDED.barcode_quality, EXCLUDED.hifi_reads, EXCLUDED.hifi_read_length, EXCLUDED.hifi_read_quality, EXCLUDED.hifi_yield, EXCLUDED.polymerase_read_length);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hifi_read_qc upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.hic_read_qc t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_read_qc_hic_source s
                    WHERE s.key_problem IS NULL AND s.og_id = t.og_id AND s.run_id = t.run_id
                      AND s.tissue IS NOT DISTINCT FROM t.tissue AND s.ext_type IS NOT DISTINCT FROM t.ext_type AND s.lib_code IS NOT DISTINCT FROM t.lib_code AND s.lane IS NOT DISTINCT FROM t.lane);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hic_read_qc deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.hic_read_qc AS t (og_id, tissue, ext_type, lib_code, lane, run_id, sequencing_id, datecreated, isarchived, isfiledeleted, totalreadspf, totalclusterspf, read1length, read2length, ispairedend, yield_gb, totalsize_gb)
  SELECT s.og_id, s.tissue, s.ext_type, s.lib_code, s.lane, s.run_id, s.resolved_sequencing_id, s.datecreated, s.isarchived, s.isfiledeleted, s.totalreadspf, s.totalclusterspf, s.read1length, s.read2length, s.ispairedend, s.yield_gb, s.totalsize_gb
  FROM v4.sync_read_qc_hic_source s WHERE s.key_problem IS NULL
  ON CONFLICT (og_id, (coalesce(tissue, '')), (coalesce(ext_type, '')), (coalesce(lib_code, '')), (coalesce(lane, '')), run_id) DO UPDATE SET sequencing_id = EXCLUDED.sequencing_id, datecreated = EXCLUDED.datecreated, isarchived = EXCLUDED.isarchived, isfiledeleted = EXCLUDED.isfiledeleted, totalreadspf = EXCLUDED.totalreadspf, totalclusterspf = EXCLUDED.totalclusterspf, read1length = EXCLUDED.read1length, read2length = EXCLUDED.read2length, ispairedend = EXCLUDED.ispairedend, yield_gb = EXCLUDED.yield_gb, totalsize_gb = EXCLUDED.totalsize_gb, loaded_at = now()
    WHERE (t.sequencing_id, t.datecreated, t.isarchived, t.isfiledeleted, t.totalreadspf, t.totalclusterspf, t.read1length, t.read2length, t.ispairedend, t.yield_gb, t.totalsize_gb) IS DISTINCT FROM (EXCLUDED.sequencing_id, EXCLUDED.datecreated, EXCLUDED.isarchived, EXCLUDED.isfiledeleted, EXCLUDED.totalreadspf, EXCLUDED.totalclusterspf, EXCLUDED.read1length, EXCLUDED.read2length, EXCLUDED.ispairedend, EXCLUDED.yield_gb, EXCLUDED.totalsize_gb);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hic_read_qc upserted'; changed := n; RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v4.sync_ref_read_qc() IS
  'Phase RG window only: copy public.raw_qc, hifi_reads_qc and hic_reads_qc into v4. Skips rows with '
  'a key_problem (check_ref_read_qc then fails). Dropped at RG.6.';

CREATE OR REPLACE VIEW v4.raw_qc AS
WITH gs AS (
  SELECT DISTINCT ON (og_id) * FROM v4.ref_genomescope ORDER BY og_id, seq_date DESC NULLS LAST
), af AS (
  SELECT DISTINCT ON (og_id) * FROM v4.ref_hifi_adapter_filter ORDER BY og_id, seq_date DESC NULLS LAST
)
SELECT coalesce(gs.og_id, af.og_id) AS og_id,
       gs.homozygosity, gs.heterozygosity, gs.genomesize, gs.repeatsize, gs.uniquesize, gs.modelfit, gs.errorrate,
       af.contam_reads
FROM gs FULL JOIN af ON af.og_id = gs.og_id;
COMMENT ON VIEW v4.raw_qc IS
  'Compatibility view: public.raw_qc''s columns, one row per OG, from the latest read set of each tool '
  '(dated before undated). Not a write path.';

CREATE OR REPLACE VIEW v4.coverage_summary AS
WITH hifi_agg AS (
         SELECT hifi_reads_qc.og_id,
            sum(hifi_reads_qc.hifi_yield) AS total_hifi_yield_bp
           FROM v4.hifi_reads_qc hifi_reads_qc
          GROUP BY hifi_reads_qc.og_id
        ), hic_agg AS (
         SELECT hic_reads_qc.og_id,
            sum(hic_reads_qc.yield_gb * 1000000000::numeric)::bigint AS total_hic_yield_bp
           FROM v4.hic_reads_qc hic_reads_qc
          GROUP BY hic_reads_qc.og_id
        ), all_ogs AS (
         SELECT hifi_agg.og_id
           FROM hifi_agg
        UNION
         SELECT hic_agg.og_id
           FROM hic_agg
        )
 SELECT a.og_id,
    r.genomesize,
    round(hic.total_hic_yield_bp::numeric / '1000000000'::numeric, 3) AS total_hic_yield_gb,
    round(hifi.total_hifi_yield_bp / '1000000000'::numeric, 3) AS total_hifi_yield_gb,
        CASE
            WHEN r.genomesize > 0 THEN round(hifi.total_hifi_yield_bp / r.genomesize::numeric, 2)
            ELSE NULL::numeric
        END AS hifi_coverage,
        CASE
            WHEN r.genomesize > 0 THEN round(hic.total_hic_yield_bp::numeric / r.genomesize::numeric, 2)
            ELSE NULL::numeric
        END AS hic_coverage
   FROM all_ogs a
     LEFT JOIN hifi_agg hifi ON hifi.og_id = a.og_id
     LEFT JOIN hic_agg hic ON hic.og_id = a.og_id
     LEFT JOIN v4.raw_qc r ON r.og_id = a.og_id
  ORDER BY a.og_id;
COMMENT ON VIEW v4.coverage_summary IS
  'public.coverage_summary on the v4 compatibility views. For the RG.5 reader test; replaces the '
  'public view at RG.6.';

CREATE OR REPLACE FUNCTION v4.check_ref_read_qc() RETURNS TABLE (check_name text, problems bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  check_name := 'raw_qc: differs from public (after triage, either way)';
  SELECT (SELECT count(*) FROM (SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.raw_qc
                                EXCEPT ALL SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.sync_raw_qc_source
                                           WHERE key_problem IS NULL AND num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads) > 0) x)
       + (SELECT count(*) FROM (SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.sync_raw_qc_source
                                WHERE key_problem IS NULL AND num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads) > 0
                                EXCEPT ALL SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.raw_qc) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'hifi_reads_qc: differs from public (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v4.hifi_reads_qc EXCEPT ALL SELECT * FROM public.hifi_reads_qc) x)
       + (SELECT count(*) FROM (SELECT * FROM public.hifi_reads_qc EXCEPT ALL SELECT * FROM v4.hifi_reads_qc) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'hic_reads_qc: differs from public (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v4.hic_reads_qc EXCEPT ALL SELECT * FROM public.hic_reads_qc) x)
       + (SELECT count(*) FROM (SELECT * FROM public.hic_reads_qc EXCEPT ALL SELECT * FROM v4.hic_reads_qc) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'coverage_summary: differs from public (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v4.coverage_summary EXCEPT ALL SELECT * FROM public.coverage_summary) x)
       + (SELECT count(*) FROM (SELECT * FROM public.coverage_summary EXCEPT ALL SELECT * FROM v4.coverage_summary) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'read QC: public rows with an untriaged key problem';
  SELECT (SELECT count(*) FROM v4.sync_raw_qc_source WHERE key_problem IS NOT NULL)
       + (SELECT count(*) FROM v4.sync_read_qc_hifi_source WHERE key_problem IS NOT NULL)
       + (SELECT count(*) FROM v4.sync_read_qc_hic_source WHERE key_problem IS NOT NULL)
    INTO problems;
  RETURN NEXT;

  check_name := 'note: hifi_read_qc rows with no sequencing link';
  SELECT count(*) INTO problems FROM v4.hifi_read_qc WHERE sequencing_id IS NULL;
  RETURN NEXT;

  check_name := 'note: hic_read_qc rows with no sequencing link';
  SELECT count(*) INTO problems FROM v4.hic_read_qc WHERE sequencing_id IS NULL;
  RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v4.check_ref_read_qc() IS
  'Phase RG window only: v4 read-QC tables against public after triage. Every problems value must '
  'be 0 except checks named note:. Dropped at RG.6.';

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v4.check_ref_read_qc() LOOP
    IF r.check_name NOT LIKE 'note:%' AND r.problems <> 0 THEN
      RAISE EXCEPTION '062 revert check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
END
$verify$;

GRANT SELECT ON ALL TABLES IN SCHEMA v4 TO readonly;

COMMIT;
