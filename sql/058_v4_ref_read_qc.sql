-- 058_v4_ref_read_qc.sql -- Phase RG.2: read-level QC for the reference pipeline, in schema v4.
--
-- Why. public.raw_qc holds two tools in one row keyed on og_id alone, GenomeScope2 (written by
-- 01a_push_genomescope_comp_results_to_sqldb.py) and HiFiAdapterFilt's contaminated-read count
-- (0a_push_hifiadapt_results_to_sqldb.py), so a re-sequenced OG overwrites its older result and a
-- tool that did not run leaves NULLs (docs/ref_genomes_runbook_rg0_rg5.md §2). hifi_reads_qc and
-- hic_reads_qc are per library per run (per lane for Hi-C), with no FK to sample or sequencing.
-- This builds:
--   ref_genomescope          one per (og_id, seq_date): GenomeScope2 on a HiFi read set
--   ref_hifi_adapter_filter  one per (og_id, seq_date): HiFiAdapterFilt contaminated reads
--   hifi_read_qc             one per (og_id, tissue, ext_type, lib_code, run_id) -> sequencing
--   hic_read_qc              one per (og_id, tissue, ext_type, lib_code, lane, run_id) -> sequencing
-- and views:
--   v4.raw_qc, v4.hifi_reads_qc, v4.hic_reads_qc   compatibility: public's columns, in order
--   v4.coverage_summary                            today's definition, on the v4 views
--   v4.v_read_qc_sequencing_readiness              read-QC rows with no sequencing link, and why
--
-- Read sets (owner decision, 2026-10-19). seq_date is the HiFi read set's date. public never kept
-- it, so every backfilled row has seq_date NULL, meaning "unknown, from before RG". The RG.4
-- writers fill it from the samplesheet. v4.raw_qc shows the latest read set per OG, dated rows
-- before NULL ones. Unique on (og_id, coalesce(seq_date, '')): PostgreSQL 14 has no NULLS NOT
-- DISTINCT.
--
-- Sequencing links. hifi_read_qc: the tube rebuilt as og_id||tissue||'_'||ext_type||'_'||lib_code,
-- with run_id, matching exactly one sequencing row (262 of 277). hic_read_qc: exactly one Hi-C row
-- of the same OG and tissue on the run (475 of 552); its lib_code (HICL) does not rebuild the
-- tube, and HICL/HICL2 on one run are ambiguous (51). The rest stay NULL and are listed by the
-- readiness view. 7 HiFi and 22 Hi-C rows are on runs absent from sequencing (lab, as in R.0).
-- ON DELETE SET NULL: import_v2.py removing a stale sequencing row drops the link, never the QC.
-- No FK to v3.sequencing_run: v4 does not depend on v3. The run_id FK arrives at RG.6, after R.6
-- has put sequencing_run in public. These two tables moved here from R.7 (owner, 2026-10-19).
--
-- Blank key parts. hic_reads_qc uses '' for unknown (tissue 2, ext_type 8, lib_code 1, lane 26 on
-- 2026-10-19). v4 stores NULL; v4.hic_reads_qc shows ''. The natural key is a unique index on
-- coalesce(..., ''). hifi_reads_qc has no blanks.
--
-- Triage (docs/ref_genomes_rg0_record.md §3). public is not changed. Not carried from raw_qc:
-- OG750_PD, OG90_bc2008 and OG90ULI (og_id not in sample; the parent OG has its own row) and OG760
-- (no value). A public row with no value is never carried.
--
-- The hic_reads_qc writer and the upload tables' writers are in another repo, not yet identified
-- (RG.0 §3). The nightly sync copies whatever they write.
--
-- Sync and checks follow 057: v4.sync_ref_read_qc(), v4.check_ref_read_qc(), window-only (dropped
-- at RG.6). Check names starting 'note:' are informational.
--
-- Guards: needs 057 (v4.ref_excluded_rows); asserts before COMMIT that exactly 4 raw_qc rows are
-- excluded, and that every check is 0.
--
-- Revert: sql/revert/058_v4_ref_read_qc_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_excluded_rows') IS NULL THEN
    RAISE EXCEPTION '058 needs schema v4 from 057';
  END IF;
END
$pre$;

-- Read sets -----------------------------------------------------------------------------------

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

-- Read QC per library per run ----------------------------------------------------------------

CREATE TABLE IF NOT EXISTS v4.hifi_read_qc (
    hifi_qc_id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id                   text NOT NULL REFERENCES public.sample (og_id),
    tissue                  text NOT NULL CHECK (tissue <> ''),
    ext_type                text NOT NULL CHECK (ext_type <> ''),
    lib_code                text NOT NULL CHECK (lib_code <> ''),
    run_id                  text NOT NULL CHECK (run_id <> ''),
    sequencing_id           text REFERENCES public.sequencing (sequencing_id) ON DELETE SET NULL,
    barcode                 text,
    barcode_quality         numeric,
    hifi_reads              bigint,
    hifi_read_length        numeric,
    hifi_read_quality       text,
    hifi_yield              bigint,
    polymerase_read_length  numeric,
    loaded_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT hifi_read_qc_natural_key UNIQUE (og_id, tissue, ext_type, lib_code, run_id),
    CONSTRAINT hifi_read_qc_has_value CHECK (num_nonnulls(barcode, barcode_quality, hifi_reads, hifi_read_length, hifi_read_quality, hifi_yield, polymerase_read_length) > 0)
);
CREATE INDEX IF NOT EXISTS hifi_read_qc_sequencing_id_idx ON v4.hifi_read_qc (sequencing_id);
COMMENT ON TABLE v4.hifi_read_qc IS
  'PacBio HiFi yield and quality per library per run, SMRT cells summed. Written by '
  '0b_push_hifi_yield_results_to_sqldb.py (ref repo). sequencing_id: the one sequencing row of this '
  'library on this run, NULL where none or several match (v_read_qc_sequencing_readiness).';

CREATE TABLE IF NOT EXISTS v4.hic_read_qc (
    hic_qc_id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id                   text NOT NULL REFERENCES public.sample (og_id),
    tissue                  text CHECK (tissue <> ''),  -- NULL = not recorded
    ext_type                text CHECK (ext_type <> ''),  -- NULL = not recorded
    lib_code                text CHECK (lib_code <> ''),  -- NULL = not recorded
    lane                    text CHECK (lane <> ''),  -- NULL = not recorded
    run_id                  text NOT NULL CHECK (run_id <> ''),
    sequencing_id           text REFERENCES public.sequencing (sequencing_id) ON DELETE SET NULL,
    datecreated             date,
    isarchived              boolean,
    isfiledeleted           boolean,
    totalreadspf            bigint,
    totalclusterspf         bigint,
    read1length             integer,
    read2length             integer,
    ispairedend             boolean,
    yield_gb                numeric,
    totalsize_gb            numeric,
    loaded_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT hic_read_qc_has_value CHECK (num_nonnulls(datecreated, isarchived, isfiledeleted, totalreadspf, totalclusterspf, read1length, read2length, ispairedend, yield_gb, totalsize_gb) > 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS hic_read_qc_natural_key ON v4.hic_read_qc (og_id, (coalesce(tissue, '')), (coalesce(ext_type, '')), (coalesce(lib_code, '')), (coalesce(lane, '')), run_id);
CREATE INDEX IF NOT EXISTS hic_read_qc_sequencing_id_idx ON v4.hic_read_qc (sequencing_id);
COMMENT ON TABLE v4.hic_read_qc IS
  'Illumina run statistics for Hi-C libraries, per library per run per lane. Writer: another repo, '
  'not yet identified (RG.0 §3). sequencing_id: the one Hi-C sequencing row of this OG and tissue on '
  'this run, NULL where none or several match (v_read_qc_sequencing_readiness).';

-- Triage list (RG.0 §3) -----------------------------------------------------------------------

INSERT INTO v4.ref_excluded_rows (source_table, og_id, reason)
SELECT * FROM (VALUES
  ('raw_qc', 'OG750_PD',    'og_id not in sample; OG750 has its own row (RG.0)'),
  ('raw_qc', 'OG90_bc2008', 'barcode variant; og_id not in sample (owner, RG.0)'),
  ('raw_qc', 'OG90ULI',     'og_id not in sample; OG90 has its own row (RG.0)'),
  ('raw_qc', 'OG760',       'no value in any column (owner, RG.0)')
) v (source_table, og_id, reason)
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_excluded_rows x
                  WHERE (x.source_table, x.og_id) = (v.source_table, v.og_id) AND x.seq_date IS NULL
                    AND x.version IS NULL AND x.stage IS NULL AND x.haplotype IS NULL);

-- Sync (window-only: dropped at RG.6) -------------------------------------------------------

CREATE OR REPLACE VIEW v4.sync_read_qc_hifi_source AS
SELECT h.*,
       CASE WHEN NOT EXISTS (SELECT 1 FROM public.sample s WHERE s.og_id = h.og_id) THEN 'og_id not in sample'
            WHEN '' IN (h.tissue, h.ext_type, h.lib_code, h.run_id) THEN 'blank key part'
       END AS key_problem,
       (SELECT CASE WHEN count(*) = 1 THEN min(s.sequencing_id) END
        FROM public.sequencing s
        WHERE s.library_tube_id = h.og_id || h.tissue || '_' || h.ext_type || '_' || h.lib_code
          AND s.run_id = h.run_id) AS resolved_sequencing_id
FROM public.hifi_reads_qc h
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_excluded_rows x WHERE x.source_table = 'hifi_reads_qc' AND x.og_id = h.og_id);

CREATE OR REPLACE VIEW v4.sync_read_qc_hic_source AS
SELECT h.og_id, nullif(h.tissue, '') AS tissue, nullif(h.ext_type, '') AS ext_type, nullif(h.lib_code, '') AS lib_code, nullif(h.lane, '') AS lane, h.run_id, h.datecreated, h.isarchived, h.isfiledeleted, h.totalreadspf, h.totalclusterspf, h.read1length, h.read2length, h.ispairedend, h.yield_gb, h.totalsize_gb,
       CASE WHEN NOT EXISTS (SELECT 1 FROM public.sample s WHERE s.og_id = h.og_id) THEN 'og_id not in sample'
            WHEN h.run_id = '' THEN 'blank run_id'
       END AS key_problem,
       (SELECT CASE WHEN count(*) = 1 THEN min(s.sequencing_id) END
        FROM public.v_sequencing_browse s
        WHERE s.og_id = h.og_id AND s.run_id = h.run_id AND s.technology = 'Hi-C'
          AND s.tissue_id LIKE h.og_id || h.tissue || '%') AS resolved_sequencing_id
FROM public.hic_reads_qc h
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_excluded_rows x WHERE x.source_table = 'hic_reads_qc' AND x.og_id = h.og_id);

CREATE OR REPLACE VIEW v4.sync_raw_qc_source AS
SELECT r.*,
       CASE WHEN NOT EXISTS (SELECT 1 FROM public.sample s WHERE s.og_id = r.og_id) THEN 'og_id not in sample' END AS key_problem
FROM public.raw_qc r
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_excluded_rows x WHERE x.source_table = 'raw_qc' AND x.og_id = r.og_id);

COMMENT ON VIEW v4.sync_read_qc_hifi_source IS 'Phase RG window only: public.hifi_reads_qc as the sync reads it. Dropped at RG.6.';
COMMENT ON VIEW v4.sync_read_qc_hic_source IS 'Phase RG window only: public.hic_reads_qc as the sync reads it, blanks as NULL. Dropped at RG.6.';
COMMENT ON VIEW v4.sync_raw_qc_source IS 'Phase RG window only: public.raw_qc after ref_excluded_rows. Dropped at RG.6.';

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

-- Views ---------------------------------------------------------------------------------------

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

CREATE OR REPLACE VIEW v4.hifi_reads_qc AS
SELECT og_id, tissue, ext_type, lib_code, run_id, barcode, barcode_quality, hifi_reads, hifi_read_length, hifi_read_quality, hifi_yield, polymerase_read_length
FROM v4.hifi_read_qc;
COMMENT ON VIEW v4.hifi_reads_qc IS 'Compatibility view: public.hifi_reads_qc''s columns in its order. Not a write path.';

CREATE OR REPLACE VIEW v4.hic_reads_qc AS
SELECT og_id, coalesce(tissue, '') AS tissue, coalesce(ext_type, '') AS ext_type, coalesce(lib_code, '') AS lib_code, coalesce(lane, '') AS lane, run_id, datecreated, isarchived, isfiledeleted, totalreadspf, totalclusterspf, read1length, read2length, ispairedend, yield_gb, totalsize_gb
FROM v4.hic_read_qc;
COMMENT ON VIEW v4.hic_reads_qc IS
  'Compatibility view: public.hic_reads_qc''s columns in its order, NULL key parts shown as ''''. '
  'Not a write path.';

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

CREATE OR REPLACE VIEW v4.v_read_qc_sequencing_readiness AS
SELECT 'hifi' AS kind, q.og_id, q.tissue, q.ext_type, q.lib_code, NULL::text AS lane, q.run_id,
       CASE WHEN NOT EXISTS (SELECT 1 FROM public.sequencing s WHERE s.run_id = q.run_id) THEN 'run not in sequencing'
            WHEN NOT EXISTS (SELECT 1 FROM public.library l
                             WHERE l.library_tube_id = q.og_id || q.tissue || '_' || q.ext_type || '_' || q.lib_code)
              THEN 'library tube not in library'
            ELSE 'no single sequencing row for this tube on this run' END AS reason
FROM v4.hifi_read_qc q WHERE q.sequencing_id IS NULL
UNION ALL
SELECT 'hic', q.og_id, q.tissue, q.ext_type, q.lib_code, q.lane, q.run_id,
       CASE WHEN NOT EXISTS (SELECT 1 FROM public.sequencing s WHERE s.run_id = q.run_id) THEN 'run not in sequencing'
            WHEN (SELECT count(*) FROM public.v_sequencing_browse s
                  WHERE s.og_id = q.og_id AND s.run_id = q.run_id AND s.technology = 'Hi-C'
                    AND s.tissue_id LIKE q.og_id || coalesce(q.tissue, '') || '%') > 1
              THEN 'several Hi-C libraries of this OG and tissue on this run'
            ELSE 'no Hi-C library of this OG and tissue on this run' END
FROM v4.hic_read_qc q WHERE q.sequencing_id IS NULL;
COMMENT ON VIEW v4.v_read_qc_sequencing_readiness IS
  'Read-QC rows with no sequencing link, and why. Lab fixes or explicit links from RG.4 writers.';

-- Checks (window-only: dropped at RG.6) ------------------------------------------------------

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

-- Backfill and verify -----------------------------------------------------------------------

SELECT * FROM v4.sync_ref_read_qc();

DO $verify$
DECLARE
  r        record;
  excluded bigint;
BEGIN
  SELECT (SELECT count(*) FROM public.raw_qc) - (SELECT count(*) FROM v4.sync_raw_qc_source) INTO excluded;
  IF excluded <> 4 THEN
    RAISE EXCEPTION '058: triage list excluded % raw_qc rows (expected 4); re-measure '
      '(docs/ref_genomes_rg0_record.md §4)', excluded;
  END IF;
  FOR r IN SELECT * FROM v4.check_ref_read_qc() LOOP
    IF r.check_name LIKE 'note:%' THEN
      RAISE NOTICE '058 %: %', r.check_name, r.problems;
    ELSIF r.problems <> 0 THEN
      RAISE EXCEPTION '058 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
END
$verify$;

GRANT SELECT ON ALL TABLES IN SCHEMA v4 TO readonly;

COMMIT;
