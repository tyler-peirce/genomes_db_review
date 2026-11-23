-- 094_ref_assembly_hic_runs.sql -- Reference assemblies' Hi-C runs, from the read names in their Hi-C BAMs.
--
-- Owner, 2026-11-23: link the Hi-C runs (backlog Medium 9; Finding 17.5). Before: ref_assembly_run
-- admitted Hi-C since 057, but no writer recorded one, so 0 of 201 hicN assemblies had a Hi-C run and
-- coverage_summary.hic_coverage counts all of an OG's Hi-C, whichever runs an assembly used.
--
-- Evidence (read-only, 2026-11-23; scripts in scripts/, results in sql/data/094_*):
--   - An Illumina read name starts instrument:run_number:flowcell:lane, and each Hi-C run on S3
--     (s3:ocom.oceangenomes/illumina-hic/<run>/) has one flowcell: every R1 FASTQ's first read agrees
--     within its run, and for the 31 runs with a saved BaseSpace run record it equals FlowcellBarcode
--     (scripts/s3_hic_run_flowcells.py; 37 runs, 534 FASTQs; the 6 newest runs have no saved record).
--   - The pipeline maps the fastp-filtered Hi-C reads with bwa mem and pairtools, which keep the read
--     names (the BAMs' @PG lines). The first ~50,000 records of an assembly's coordinate-sorted Hi-C
--     BAM on Acacia sample every input run (scripts/acacia_hic_flowcells.py): 193 of 201 assemblies
--     have one, and every flowcell in them is a run on S3 except one iSeq flowcell (OG88).
--   - scripts/build_094_data.py: an assembly's Hi-C rows are its OG's non-failed Hi-C sequencing rows
--     on those runs (every library of the OG on a run: the pipeline stages the OG's whole run folder,
--     and OMNIC's read-pair totals are ~97% of all those libraries' BaseSpace clusters, the fastp
--     loss). Fallback for an assembly with no BAM: OMNIC's total fits exactly one set of the OG's runs
--     in [0.95, 1.0005] of their clusters; on the 85 assemblies with both a BAM and a unique fit, the
--     two agree 85 times and disagree none.
-- Result: 191 assemblies linked, 239 links. 190 from their BAMs; OG863 v250331.hic1 from OMNIC; OG88
-- v230728.hic1's iSeq flowcell BSB09424-1410 (3% of its reads) is on no S3 run and is taken to be
-- ISEQ_230719_AD, the OG's only iSeq Hi-C row before the assembly (its flowcell is recorded as such).
-- 10 not linked, each with its reason in ref_assembly_hic_unlinked:
--   - OG79 v240427.hic2: 95% of its Hi-C reads are from NOVA_250312_LA, which has no OG79 library,
--     and OMNIC's total is 1.79 x OG79's own Hi-C. Scaffolded with another specimen's Hi-C?
--   - OG906 v250212.hic1: all of its Hi-C reads are from NOVA_240501_LA, which has no OG906 library;
--     OG906 has no Hi-C sequencing row at all.
--   - OG785 v241004.hic2: all from NOVA_250505_AD, where OG785G-2_HICL has FASTQs and hic_read_qc
--     rows but no sequencing row (the lab's workbook). It links itself when the row arrives.
--   - OG2088 v260414.hic2, OG749 v241018.hic1, OG804 v260522.hic2: no BAM; OMNIC fits two sets, which
--     differ by a small iSeq or NextSeq top-up. OG38 v230609.hic1, OG706 v240206.hic2, OG810
--     v241004.hic2, OG860 v240927.hic1: no BAM and no single OMNIC total.
-- Some hic2 assemblies used the same Hi-C as their hic1 (OG100, OG106, OG910): a new version is not
-- always new Hi-C.
--
-- Design. The evidence is stored, and the links derived from it, as PacBio links are from read sets
-- (093), so a status change or a workbook fix moves them without a re-push:
--   - sequencing_run.flowcell, unique: 38 runs (37 Hi-C runs on S3, ISEQ_230719_AD inferred). Writer
--     for new runs: ref_genomes_hic_automation push_hic_yield.py, from the BaseSpace run record that
--     generate_hic_yield.py already reads.
--   - ref_assembly_hic_flowcell: the flowcells an assembly's Hi-C reads came from. Writer:
--     set_ref_assembly_hic_flowcells(), called by ref-genomes 05b_push_hic_runs_to_sqldb.py with the
--     flowcells it reads from the assembly's Hi-C BAM, after the OMNIC push.
--   - v_ref_assembly_hic_rule: each flowcell's run and the OG's non-failed Hi-C rows on it. An
--     assembly is linked only when every one of its flowcells resolves (OG79 is not half-linked).
--   - refresh_assembly_runs(): Hi-C links are the rule's rows; it adds and removes them. Triggers on
--     ref_assembly_hic_flowcell and on sequencing_run.flowcell call it, besides the existing ones.
--   - ref_assembly_hic_unlinked and v_ref_assembly_hic_readiness: what is not linked, and why.
-- Not done here: coverage_summary.hic_coverage is still per OG. Rejected: inferring Hi-C runs from
-- dates, as stage_previous_hic.py stages them (every NOVA_/NEXT_ Hi-C run of the OG): OG2088
-- v260414.hic1 used NOVA_260605_AD only, though NOVA_260420_TW1 was there first.
--
-- Apply: guards refuse unless live has the counts the data was built from. Replay: objects are
-- replaced and the backfill is skipped once sequencing_run.flowcell exists.
-- Revert: sql/revert/094_ref_assembly_hic_runs_revert.sql.

BEGIN;

CREATE TEMP TABLE m094 ON COMMIT DROP AS
SELECT NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'sequencing_run' AND column_name = 'flowcell')
       AS first_apply;

-- Tables -----------------------------------------------------------------------------------------------

ALTER TABLE public.sequencing_run ADD COLUMN IF NOT EXISTS flowcell text;
DO $c$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sequencing_run_flowcell_check') THEN
    ALTER TABLE public.sequencing_run ADD CONSTRAINT sequencing_run_flowcell_check
      CHECK (flowcell ~ '^[A-Za-z0-9-]+$');
  END IF;
END
$c$;
CREATE UNIQUE INDEX IF NOT EXISTS sequencing_run_flowcell_key ON public.sequencing_run (flowcell);

CREATE TABLE IF NOT EXISTS public.ref_assembly_hic_flowcell (
    assembly_id bigint NOT NULL REFERENCES public.ref_assembly (assembly_id) ON DELETE CASCADE,
    flowcell    text   NOT NULL CHECK (flowcell ~ '^[A-Za-z0-9-]+$'),
    bam_records integer CHECK (bam_records > 0),
    source      text   NOT NULL CHECK (source IN ('bam', 'omnic')),
    loaded_at   timestamp with time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (assembly_id, flowcell)
);
CREATE INDEX IF NOT EXISTS ref_assembly_hic_flowcell_flowcell_idx ON public.ref_assembly_hic_flowcell (flowcell);

CREATE TABLE IF NOT EXISTS public.ref_assembly_hic_unlinked (
    assembly_id bigint PRIMARY KEY REFERENCES public.ref_assembly (assembly_id) ON DELETE CASCADE,
    reason      text NOT NULL CHECK (reason <> ''),
    reviewed_on date NOT NULL
);

-- The rule ---------------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_ref_assembly_hic_rule AS
WITH rows AS (
  SELECT f.assembly_id, a.og_id, f.flowcell, r.run_id, s.sequencing_id
    FROM ref_assembly_hic_flowcell f
    JOIN ref_assembly a ON a.assembly_id = f.assembly_id
    LEFT JOIN sequencing_run r ON r.flowcell = f.flowcell
    LEFT JOIN v_sequencing_browse s ON s.og_id = a.og_id AND s.run_id = r.run_id
         AND s.technology = 'Hi-C' AND s.library_type = 'hic' AND s.status IS DISTINCT FROM 'Failed'
)
SELECT assembly_id, og_id, flowcell, run_id, sequencing_id,
       bool_and(sequencing_id IS NOT NULL) OVER (PARTITION BY assembly_id) AS complete
  FROM rows;

CREATE OR REPLACE FUNCTION public.refresh_assembly_runs(p_og_ids text[],
                                                        p_sequencing_ids text[] DEFAULT '{}')
RETURNS void
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  -- Mito: every link is derived, so drop one the rule no longer gives (080, unchanged).
  DELETE FROM mito_assembly_run r
   USING mito_assembly a
   WHERE a.assembly_id = r.assembly_id
     AND (a.og_id = ANY (p_og_ids) OR r.sequencing_id = ANY (p_sequencing_ids))
     AND NOT EXISTS (SELECT 1 FROM v_sequencing_browse s
                      WHERE s.sequencing_id = r.sequencing_id
                        AND s.og_id = a.og_id AND s.seq_date = a.seq_date
                        AND mito_run_matches(a.tech, s.technology, s.library_type, s.instrument));

  INSERT INTO mito_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT a.assembly_id, s.sequencing_id
    FROM mito_assembly a
    JOIN v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
   WHERE a.og_id = ANY (p_og_ids)
     AND mito_run_matches(a.tech, s.technology, s.library_type, s.instrument)
  ON CONFLICT DO NOTHING;

  -- Ref: drop a link its row can no longer have (another OG, not PacBio/ONT/Hi-C DNA, failed: what
  -- ref_assembly_run_genomic_only refuses), a PacBio link that is not a run of the assembly's read set
  -- (093), and a Hi-C link the rule does not give (094). ONT links chosen by hand stay.
  DELETE FROM ref_assembly_run r
   USING ref_assembly a
   WHERE a.assembly_id = r.assembly_id
     AND (a.og_id = ANY (p_og_ids) OR r.sequencing_id = ANY (p_sequencing_ids))
     AND (NOT EXISTS (SELECT 1 FROM v_sequencing_browse s
                       WHERE s.sequencing_id = r.sequencing_id AND s.og_id = a.og_id
                         AND s.technology IN ('PacBio HIFI', 'PacBio', 'ONT', 'Hi-C')
                         AND s.library_type IN ('pacbio', 'ont', 'hic')
                         AND s.status IS DISTINCT FROM 'Failed')
          OR (EXISTS (SELECT 1 FROM v_sequencing_browse s
                       WHERE s.sequencing_id = r.sequencing_id
                         AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio')
              AND NOT EXISTS (SELECT 1 FROM ref_read_set_run rr
                               WHERE rr.read_set_id = a.read_set_id AND rr.sequencing_id = r.sequencing_id))
          OR (EXISTS (SELECT 1 FROM v_sequencing_browse s
                       WHERE s.sequencing_id = r.sequencing_id AND s.technology = 'Hi-C' AND s.library_type = 'hic')
              AND NOT EXISTS (SELECT 1 FROM v_ref_assembly_hic_rule h
                               WHERE h.assembly_id = r.assembly_id AND h.sequencing_id = r.sequencing_id
                                 AND h.complete)));

  -- PacBio: the read set's runs (093). A failed run produced no reads to build from (069).
  INSERT INTO ref_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT a.assembly_id, rr.sequencing_id
    FROM ref_assembly a
    JOIN ref_read_set_run rr ON rr.read_set_id = a.read_set_id
    JOIN v_sequencing_browse s ON s.sequencing_id = rr.sequencing_id AND s.og_id = a.og_id
   WHERE (a.og_id = ANY (p_og_ids) OR rr.sequencing_id = ANY (p_sequencing_ids))
     AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio'
     AND s.status IS DISTINCT FROM 'Failed'
  ON CONFLICT DO NOTHING;

  -- ONT: the OG's non-failed ONT DNA rows of the assembly's seq_date (080's rule).
  INSERT INTO ref_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT a.assembly_id, s.sequencing_id
    FROM ref_assembly a
    JOIN v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
   WHERE a.og_id = ANY (p_og_ids)
     AND s.technology = 'ONT' AND s.library_type = 'ont'
     AND s.status IS DISTINCT FROM 'Failed'
  ON CONFLICT DO NOTHING;

  -- Hi-C: the OG's non-failed Hi-C rows on the runs of the assembly's flowcells, when all resolve (094).
  INSERT INTO ref_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT h.assembly_id, h.sequencing_id
    FROM v_ref_assembly_hic_rule h
   WHERE h.complete
     AND (h.og_id = ANY (p_og_ids) OR h.sequencing_id = ANY (p_sequencing_ids))
  ON CONFLICT DO NOTHING;
END
$fn$;

CREATE OR REPLACE FUNCTION public.ref_assembly_hic_flowcell_runs() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  PERFORM refresh_assembly_runs(ARRAY(SELECT DISTINCT og_id FROM ref_assembly
                                        WHERE assembly_id IN (CASE WHEN TG_OP = 'DELETE' THEN OLD.assembly_id ELSE NEW.assembly_id END,
                                                              CASE WHEN TG_OP = 'UPDATE' THEN OLD.assembly_id END)));
  RETURN NULL;
END
$fn$;
DROP TRIGGER IF EXISTS ref_assembly_hic_flowcell_runs ON public.ref_assembly_hic_flowcell;
CREATE TRIGGER ref_assembly_hic_flowcell_runs AFTER INSERT OR UPDATE OR DELETE ON public.ref_assembly_hic_flowcell
  FOR EACH ROW EXECUTE FUNCTION public.ref_assembly_hic_flowcell_runs();

CREATE OR REPLACE FUNCTION public.sequencing_run_flowcell_runs() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  IF NEW.flowcell IS DISTINCT FROM OLD.flowcell THEN
    PERFORM refresh_assembly_runs(ARRAY(SELECT DISTINCT a.og_id
                                          FROM ref_assembly_hic_flowcell f JOIN ref_assembly a USING (assembly_id)
                                         WHERE f.flowcell IN (NEW.flowcell, OLD.flowcell)));
  END IF;
  RETURN NULL;
END
$fn$;
DROP TRIGGER IF EXISTS sequencing_run_flowcell_runs ON public.sequencing_run;
CREATE TRIGGER sequencing_run_flowcell_runs AFTER UPDATE OF flowcell ON public.sequencing_run
  FOR EACH ROW EXECUTE FUNCTION public.sequencing_run_flowcell_runs();

-- The writer's entry point -------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_ref_assembly_hic_flowcells(p_assembly_id bigint, p_flowcells text[],
                                                                 p_bam_records integer[] DEFAULT NULL,
                                                                 p_source text DEFAULT 'bam')
RETURNS text[]
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
DECLARE
  a        record;
  problems text[];
BEGIN
  SELECT assembly_id, og_id, seq_date, version INTO a FROM ref_assembly WHERE assembly_id = p_assembly_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'set_ref_assembly_hic_flowcells: no ref_assembly %', p_assembly_id;
  END IF;
  IF p_flowcells IS NULL OR cardinality(p_flowcells) = 0 THEN
    RAISE EXCEPTION 'set_ref_assembly_hic_flowcells: no flowcells given for % %.%', a.og_id, a.seq_date, a.version;
  END IF;
  IF p_bam_records IS NOT NULL AND cardinality(p_bam_records) <> cardinality(p_flowcells) THEN
    RAISE EXCEPTION 'set_ref_assembly_hic_flowcells: % flowcells but % record counts',
      cardinality(p_flowcells), cardinality(p_bam_records);
  END IF;

  DELETE FROM ref_assembly_hic_flowcell WHERE assembly_id = a.assembly_id AND flowcell <> ALL (p_flowcells);
  INSERT INTO ref_assembly_hic_flowcell AS t (assembly_id, flowcell, bam_records, source)
  SELECT a.assembly_id, f.flowcell, f.records, p_source
    FROM unnest(p_flowcells, coalesce(p_bam_records, array_fill(NULL::integer, ARRAY[cardinality(p_flowcells)])))
         AS f (flowcell, records)
  ON CONFLICT (assembly_id, flowcell) DO UPDATE
     SET bam_records = EXCLUDED.bam_records, source = EXCLUDED.source, loaded_at = now()
   WHERE (t.bam_records, t.source) IS DISTINCT FROM (EXCLUDED.bam_records, EXCLUDED.source);

  problems := ARRAY(SELECT CASE WHEN h.run_id IS NULL THEN format('flowcell %s: no sequencing_run has it', h.flowcell)
                                ELSE format('flowcell %s (%s): no non-failed Hi-C sequencing row of %s',
                                            h.flowcell, h.run_id, h.og_id) END
                      FROM v_ref_assembly_hic_rule h
                     WHERE h.assembly_id = a.assembly_id AND h.sequencing_id IS NULL
                     ORDER BY h.flowcell);
  IF cardinality(problems) = 0 THEN
    DELETE FROM ref_assembly_hic_unlinked WHERE assembly_id = a.assembly_id;
  END IF;
  RETURN problems;
END
$fn$;

CREATE OR REPLACE VIEW public.v_ref_assembly_hic_readiness AS
SELECT a.assembly_id,
       a.og_id,
       a.seq_date,
       a.version,
       (SELECT string_agg(h.flowcell || coalesce(' (' || h.run_id || ')', ' (no run)'), ', ' ORDER BY h.flowcell)
          FROM v_ref_assembly_hic_rule h WHERE h.assembly_id = a.assembly_id AND h.sequencing_id IS NULL) AS unresolved,
       u.reason,
       u.reviewed_on,
       (SELECT string_agg(s.sequencing_id, ', ' ORDER BY s.seq_date, s.sequencing_id)
          FROM v_sequencing_browse s
         WHERE s.og_id = a.og_id AND s.technology = 'Hi-C' AND s.library_type = 'hic'
           AND s.status IS DISTINCT FROM 'Failed') AS hic_rows_for_og
  FROM ref_assembly a
  LEFT JOIN ref_assembly_hic_unlinked u ON u.assembly_id = a.assembly_id
 WHERE a.strategy = 'hic'
   AND NOT EXISTS (SELECT 1 FROM ref_assembly_run l JOIN v_sequencing_browse s ON s.sequencing_id = l.sequencing_id
                    WHERE l.assembly_id = a.assembly_id AND s.technology = 'Hi-C' AND s.library_type = 'hic');

-- Data (sql/data/094_*.tsv, 2026-11-23) --------------------------------------------------------------

CREATE TEMP TABLE d_flowcell (run_id text PRIMARY KEY, flowcell text NOT NULL UNIQUE) ON COMMIT DROP;
INSERT INTO d_flowcell VALUES
  ('ISEQ_230719_AD', 'BSB09424-1410'),
  ('NEXT_230801_AD', 'AACHJC3M5'),
  ('NEXT_230912_AD', 'AAAWHNMHV'),
  ('NEXT_240207_AD', 'AAC3VGWHV'),
  ('NEXT_240301_AD', 'AAC3NKWHV'),
  ('NEXT_240405_AD', 'AAC3NM7HV'),
  ('NEXT_240423_AD', 'AAC3NMMHV'),
  ('NEXT_240705_AD', 'AAF5HLVM5'),
  ('NEXT_250325_AD', 'AAGGJWLM5'),
  ('NEXT_250613_LA', 'AAGTYJ5M5'),
  ('NEXT_251118_AD', 'AAHGH2WM5'),
  ('NOVA_240501_LA', 'HNGHVDRX3'),
  ('NOVA_240509_AD', 'HCGFGDRX5'),
  ('NOVA_240522_AD', 'HCJKHDRX5'),
  ('NOVA_240613_LA', 'HCCCGDRX5'),
  ('NOVA_240719_AD', 'HCGWCDRX5'),
  ('NOVA_240821_AD', 'HJTLGDRX5'),
  ('NOVA_241106_AD', 'HFYJJDRX5'),
  ('NOVA_241125_AD', 'HJT3WDRX5'),
  ('NOVA_241204_AD', 'HJTFWDRX5'),
  ('NOVA_250114_AD', 'HJTLKDRX5'),
  ('NOVA_250213_AD', 'HNTVWDRX5'),
  ('NOVA_250312_LA', 'HWM25DRX5'),
  ('NOVA_250505_AD', 'HWLY7DRX5'),
  ('NOVA_250522_AD', 'H3LTVDRX7'),
  ('NOVA_250624_LA', 'H5WFWDMX2'),
  ('NOVA_250626_LA', 'H73KYDRX7'),
  ('NOVA_250820_AD', 'HWFHKDRX5'),
  ('NOVA_251204_AD', 'H757YDRX7'),
  ('NOVA_251204_AD2', 'HWG32DRX5'),
  ('NOVA_260123_TWAD', 'H2MJJDRX7'),
  ('NOVA_260209_TW1', 'H3LWWDRX7'),
  ('NOVA_260209_TW2', 'H3HHJDRX7'),
  ('NOVA_260420_TW1', 'HGK2LDRX7'),
  ('NOVA_260420_TW2', 'HGK37DRX7'),
  ('NOVA_260605_AD', 'HNTVNDRX7'),
  ('NOVA_260605_AD2', 'HNVT7DRX7'),
  ('NOVA_260706_TW', 'HGYMYDMX2');

CREATE TEMP TABLE d_link (og_id text, seq_date text, version text, sequencing_id text, source text,
                          PRIMARY KEY (og_id, seq_date, version, sequencing_id)) ON COMMIT DROP;
INSERT INTO d_link VALUES
  ('OG1', '230525', 'hic1', 'OG1G-1_HICL_NEXT_240405_AD', 'bam'),
  ('OG10', '230209', 'hic2', 'OG10G-1_HICL_NEXT_230912_AD', 'bam'),
  ('OG100', '240116', 'hic1', 'OG100W-4_HICL_NOVA_260123_TWAD', 'bam'),
  ('OG100', '240116', 'hic2', 'OG100W-4_HICL_NOVA_260123_TWAD', 'bam'),
  ('OG101', '240206', 'hic1', 'OG101G-1_HICL_NEXT_240301_AD', 'bam'),
  ('OG105', '231027', 'hic1', 'OG105G-2_HICL_NOVA_240719_AD', 'bam'),
  ('OG106', '240927', 'hic1', 'OG106G-3_HICL_NOVA_260123_TWAD', 'bam'),
  ('OG106', '240927', 'hic2', 'OG106G-3_HICL_NOVA_260123_TWAD', 'bam'),
  ('OG107', '240125', 'hic1', 'OG107G-1_HICL_NOVA_240501_LA', 'bam'),
  ('OG107', '240125', 'hic1', 'OG107G-1_HICL_NOVA_250820_AD', 'bam'),
  ('OG108', '231027', 'hic1', 'OG108G-1_HICL_NOVA_240522_AD', 'bam'),
  ('OG11', '230825', 'hic1', 'OG11G-1_HICL_NEXT_240207_AD', 'bam'),
  ('OG111', '241018', 'hic1', 'OG111G-4_HICL_NOVA_260123_TWAD', 'bam'),
  ('OG113', '231027', 'hic1', 'OG113G-1_HICL_NOVA_240522_AD', 'bam'),
  ('OG113', '231028', 'hic1', 'OG113G-1_HICL_NOVA_240522_AD', 'bam'),
  ('OG114', '240116', 'hic2', 'OG114G-1_HICL_NOVA_240613_LA', 'bam'),
  ('OG114', '240116', 'hic2', 'OG114G-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG115', '240125', 'hic1', 'OG115L-1_HICL_NOVA_240613_LA', 'bam'),
  ('OG1161', '250113', 'hic2', 'OG1161B-5_HICL_NOVA_250624_LA', 'bam'),
  ('OG12', '230516', 'hic1', 'OG12G-1_HICL_NOVA_240509_AD', 'bam'),
  ('OG13', '230212', 'hic1', 'OG13G-1_HICL_NEXT_240423_AD', 'bam'),
  ('OG1326', '260730', 'hic1', 'OG1326L-1_HICL_NOVA_260605_AD2', 'bam'),
  ('OG14', '230209', 'hic1', 'OG14G-1_HICL_NEXT_240207_AD', 'bam'),
  ('OG15', '230413', 'hic1', 'OG15G-1_HICL_NEXT_240207_AD', 'bam'),
  ('OG1573', '260626', 'hic2', 'OG1573G-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG16', '240417', 'hic1', 'OG16G-1_HICL_NOVA_240509_AD', 'bam'),
  ('OG1613', '260603', 'hic2', 'OG1613G-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG1663', '260603', 'hic2', 'OG1663G-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG2', '230414', 'hic1', 'OG2G-2_HICL_NEXT_240405_AD', 'bam'),
  ('OG2088', '260414', 'hic1', 'OG2088G-1_HICL_NOVA_260605_AD', 'bam'),
  ('OG2089', '260721', 'hic1', 'OG2089G-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG2093', '260721', 'hic1', 'OG2093G-1_HICL_NOVA_260605_AD2', 'bam'),
  ('OG2104', '260414', 'hic2', 'OG2104G-1_HICL_NOVA_260420_TW1', 'bam'),
  ('OG2105', '260421', 'hic1', 'OG2105G-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG2105', '260421', 'hic1', 'OG2105G-3_HICL_NOVA_260706_TW', 'bam'),
  ('OG2112', '260603', 'hic1', 'OG2112L-1_HICL_NOVA_260420_TW1', 'bam'),
  ('OG2112', '260603', 'hic1', 'OG2112L-1_HICL_NOVA_260605_AD', 'bam'),
  ('OG2119', '260408', 'hic1', 'OG2119G-1_HICL_NOVA_260420_TW1', 'bam'),
  ('OG2119', '260408', 'hic1', 'OG2119G-1_HICL_NOVA_260605_AD', 'bam'),
  ('OG2119', '260408', 'hic2', 'OG2119G-1_HICL_NOVA_260420_TW1', 'bam'),
  ('OG2119', '260408', 'hic2', 'OG2119G-1_HICL_NOVA_260605_AD', 'bam'),
  ('OG2121', '260511', 'hic1', 'OG2121L-1_HICL_NOVA_260605_AD2', 'bam'),
  ('OG2122', '260511', 'hic1', 'OG2122G-1_HICL_NOVA_260605_AD2', 'bam'),
  ('OG2124', '260421', 'hic1', 'OG2124G-4_HICL_NOVA_260420_TW1', 'bam'),
  ('OG2124', '260421', 'hic1', 'OG2124G-4_HICL_NOVA_260605_AD', 'bam'),
  ('OG2126', '260730', 'hic1', 'OG2126G-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG2127', '260603', 'hic1', 'OG2127G-3_HICL_NOVA_260420_TW1', 'bam'),
  ('OG2127', '260603', 'hic1', 'OG2127G-3_HICL_NOVA_260605_AD', 'bam'),
  ('OG2127', '260603', 'hic2', 'OG2127G-3_HICL_NOVA_260420_TW1', 'bam'),
  ('OG2127', '260603', 'hic2', 'OG2127G-3_HICL_NOVA_260605_AD', 'bam'),
  ('OG2128', '260721', 'hic1', 'OG2128G-1_HICL_NOVA_260605_AD2', 'bam'),
  ('OG2128', '260721', 'hic1', 'OG2128G-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG2132', '260408', 'hic1', 'OG2132E-3_HICL_NOVA_260420_TW2', 'bam'),
  ('OG2132', '260408', 'hic1', 'OG2132E-3_HICL_NOVA_260605_AD', 'bam'),
  ('OG2145', '260730', 'hic1', 'OG2145G-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG2146', '260414', 'hic1', 'OG2146L-1_HICL_NOVA_260420_TW2', 'bam'),
  ('OG2146', '260414', 'hic1', 'OG2146L-1_HICL_NOVA_260605_AD', 'bam'),
  ('OG2156', '260408', 'hic1', 'OG2156L-1_HICL_NOVA_260420_TW2', 'bam'),
  ('OG2156', '260408', 'hic1', 'OG2156L-1_HICL_NOVA_260605_AD', 'bam'),
  ('OG2163', '260603', 'hic1', 'OG2163L-1_HICL_NOVA_260420_TW2', 'bam'),
  ('OG2163', '260603', 'hic1', 'OG2163L-1_HICL_NOVA_260605_AD', 'bam'),
  ('OG2164', '260331', 'hic1', 'OG2164L-1_HICL_NOVA_260420_TW2', 'bam'),
  ('OG2178', '260408', 'hic1', 'OG2178L-3_HICL_NOVA_260605_AD2', 'bam'),
  ('OG2188', '260408', 'hic1', 'OG2188L-1_HICL_NOVA_260420_TW2', 'bam'),
  ('OG2202', '260331', 'hic1', 'OG2202L-1_HICL_NOVA_260420_TW2', 'bam'),
  ('OG2202', '260331', 'hic2', 'OG2202L-1_HICL_NOVA_260420_TW2', 'bam'),
  ('OG2202', '260331', 'hic2', 'OG2202L-1_HICL_NOVA_260605_AD', 'bam'),
  ('OG2203', '260408', 'hic1', 'OG2203L-1_HICL_NOVA_260605_AD2', 'bam'),
  ('OG2203', '260408', 'hic1', 'OG2203L-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG2237', '260414', 'hic1', 'OG2237L-1_HICL_NOVA_260605_AD2', 'bam'),
  ('OG2242', '260414', 'hic1', 'OG2242L-1_HICL_NOVA_260605_AD2', 'bam'),
  ('OG28', '230811', 'hic1', 'OG28B-1_HICL_NEXT_230912_AD', 'bam'),
  ('OG3', '230825', 'hic1', 'OG3G-3_HICL_NEXT_240405_AD', 'bam'),
  ('OG35', '231027', 'hic1', 'OG35W-1_HICL_NEXT_240207_AD', 'bam'),
  ('OG36', '230724', 'hic1', 'OG36W-1_HICL_NEXT_240207_AD', 'bam'),
  ('OG37', '240116', 'hic2', 'OG37H-1_HICL_NOVA_250505_AD', 'bam'),
  ('OG39', '250331', 'hic1', 'OG39L-1_HICL_NOVA_241125_AD', 'bam'),
  ('OG40', '241004', 'hic1', 'OG40G-2_HICL_NOVA_251204_AD', 'bam'),
  ('OG46', '240215', 'hic1', 'OG46G-1_HICL_NEXT_240423_AD', 'bam'),
  ('OG47', '231115', 'hic1', 'OG47G-1_HICL_NEXT_240207_AD', 'bam'),
  ('OG5', '240116', 'hic2', 'OG5G-1_HICL_NEXT_230912_AD', 'bam'),
  ('OG5', '240116', 'hic2', 'OG5G-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG52', '230825', 'hic1', 'OG52G-1_HICL_NEXT_240207_AD', 'bam'),
  ('OG53', '230915', 'hic1', 'OG53G-1_HICL_NEXT_240301_AD', 'bam'),
  ('OG54', '250331', 'hic1', 'OG54G-3_HICL_NOVA_250624_LA', 'bam'),
  ('OG55', '231115', 'hic1', 'OG55G-2_HICL_NOVA_251204_AD', 'bam'),
  ('OG56', '250704', 'hic1', 'OG56G-1_HICL_NOVA_251204_AD', 'bam'),
  ('OG57', '231027', 'hic1', 'OG57M-4_HICL_NOVA_251204_AD2', 'bam'),
  ('OG58', '250704', 'hic1', 'OG58W-3_HICL_NOVA_251204_AD2', 'bam'),
  ('OG6', '230702', 'hic1', 'OG6G-1_HICL_NEXT_240405_AD', 'bam'),
  ('OG61', '250317', 'hic1', 'OG61W-3_HICL_NOVA_251204_AD2', 'bam'),
  ('OG61', '250318', 'hic1', 'OG61W-3_HICL_NOVA_251204_AD2', 'bam'),
  ('OG62', '250307', 'hic1', 'OG62G-1_HICL_NOVA_250505_AD', 'bam'),
  ('OG637', '240521', 'hic1', 'OG637B-1_HICL2_NEXT_240423_AD', 'bam'),
  ('OG637', '240521', 'hic1', 'OG637B-1_HICL3_NEXT_240423_AD', 'bam'),
  ('OG637', '240521', 'hic1', 'OG637B-1_HICL_NEXT_240423_AD', 'bam'),
  ('OG64', '250728', 'hic1', 'OG64W-1_HICL_NOVA_251204_AD', 'bam'),
  ('OG645', '240417', 'hic1', 'OG645L-1_HICL_NOVA_240613_LA', 'bam'),
  ('OG645', '240427', 'hic1', 'OG645L-1_HICL_NOVA_240613_LA', 'bam'),
  ('OG646', '240821', 'hic1', 'OG646L-1_HICL_NOVA_240613_LA', 'bam'),
  ('OG646', '240821', 'hic1', 'OG646L-2_HICL_NOVA_250312_LA', 'bam'),
  ('OG647', '240501', 'hic1', 'OG647G-1_HICL_NOVA_240613_LA', 'bam'),
  ('OG648', '250704', 'hic1', 'OG648G-1_HICL_NOVA_260209_TW1', 'bam'),
  ('OG649', '240417', 'hic1', 'OG649L-1_HICL_NOVA_250312_LA', 'bam'),
  ('OG65', '250704', 'hic1', 'OG65W-2_HICL_NOVA_260123_TWAD', 'bam'),
  ('OG650', '240327', 'hic1', 'OG650L-1_HICL_NOVA_240501_LA', 'bam'),
  ('OG651', '240327', 'hic1', 'OG651G-1_HICL_NOVA_240501_LA', 'bam'),
  ('OG652', '240327', 'hic1', 'OG652L-1_HICL_NOVA_260123_TWAD', 'bam'),
  ('OG654', '240327', 'hic1', 'OG654L-1_HICL_NOVA_240501_LA', 'bam'),
  ('OG657', '250110', 'hic1', 'OG657L-1_HICL_NOVA_240821_AD', 'bam'),
  ('OG658', '240327', 'hic1', 'OG658G-2_HICL_NOVA_260209_TW1', 'bam'),
  ('OG659', '240418', 'hic1', 'OG659L-1_HICL_NOVA_240509_AD', 'bam'),
  ('OG659', '240427', 'hic2', 'OG659L-1_HICL_NOVA_240509_AD', 'bam'),
  ('OG659', '240427', 'hic2', 'OG659L-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG660', '240228', 'hic1', 'OG660L-2_HICL_NEXT_240301_AD', 'bam'),
  ('OG662', '240327', 'hic1', 'OG662L-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG664', '241018', 'hic1', 'OG664G-1_HICL_NOVA_250505_AD', 'bam'),
  ('OG665', '240501', 'hic2', 'OG665L-1_HICL_NOVA_250114_AD', 'bam'),
  ('OG665', '240501', 'hic2', 'OG665L-2_HICL_NOVA_250505_AD', 'bam'),
  ('OG666', '241004', 'hic1', 'OG666L-1_HICL_NOVA_250312_LA', 'bam'),
  ('OG666', '241004', 'hic1', 'OG666L-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG67', '241127', 'hic1', 'OG67W-1_HICL_NOVA_260123_TWAD', 'bam'),
  ('OG672', '240215', 'hic1', 'OG672L-1_HICL_NEXT_240301_AD', 'bam'),
  ('OG673', '240427', 'hic1', 'OG673L-1_HICL_NOVA_250114_AD', 'bam'),
  ('OG675', '250828', 'hic1', 'OG675L-3_HICL_NOVA_260209_TW1', 'bam'),
  ('OG676', '240327', 'hic1', 'OG676G-1_HICL_NOVA_250114_AD', 'bam'),
  ('OG678', '240327', 'hic2', 'OG678G-1_HICL_NOVA_241125_AD', 'bam'),
  ('OG678', '240327', 'hic2', 'OG678G-1_HICL_NOVA_250114_AD', 'bam'),
  ('OG679', '250307', 'hic1', 'OG679L-2_HICL_NOVA_250624_LA', 'bam'),
  ('OG680', '241004', 'hic1', 'OG680L-2_HICL_NOVA_250312_LA', 'bam'),
  ('OG681', '250307', 'hic1', 'OG681L-2_HICL_NOVA_250624_LA', 'bam'),
  ('OG683', '241025', 'hic1', 'OG683L-1_HICL_NOVA_250114_AD', 'bam'),
  ('OG686', '241004', 'hic1', 'OG686G-1_HICL_NOVA_250624_LA', 'bam'),
  ('OG695', '240520', 'hic1', 'OG695L-1_HICL_NOVA_240821_AD', 'bam'),
  ('OG696', '240228', 'hic1', 'OG696L-1_HICL_NOVA_240509_AD', 'bam'),
  ('OG696', '240228', 'hic1', 'OG696L-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG696', '240228', 'hic2', 'OG696L-1_HICL_NOVA_240509_AD', 'bam'),
  ('OG696', '240228', 'hic2', 'OG696L-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG698', '241004', 'hic1', 'OG698L-1_HICL_NOVA_250624_LA', 'bam'),
  ('OG698', '241004', 'hic1', 'OG698L-1_HICL_NOVA_250820_AD', 'bam'),
  ('OG699', '250317', 'hic1', 'OG699L-2_HICL_NEXT_250613_LA', 'bam'),
  ('OG699', '250317', 'hic1', 'OG699L-2_HICL_NOVA_250624_LA', 'bam'),
  ('OG699', '250317', 'hic1', 'OG699L-2_HICL_NOVA_250820_AD', 'bam'),
  ('OG7', '230915', 'hic1', 'OG7G-1_HICL_NEXT_240423_AD', 'bam'),
  ('OG70', '250307', 'hic1', 'OG70W-3_HICL_NOVA_251204_AD2', 'bam'),
  ('OG701', '240509', 'hic1', 'OG701L-1_HICL_NOVA_240509_AD', 'bam'),
  ('OG702', '240501', 'hic2', 'OG702G-1_HICL_NOVA_250114_AD', 'bam'),
  ('OG702', '240501', 'hic2', 'OG702L-1_HICL_NEXT_240705_AD', 'bam'),
  ('OG704', '240427', 'hic1', 'OG704L-2_HICL_NOVA_260209_TW1', 'bam'),
  ('OG72', '241023', 'hic1', 'OG72G-2_HICL_NOVA_251204_AD', 'bam'),
  ('OG721', '240501', 'hic1', 'OG721G-1_HICL_NOVA_260209_TW1', 'bam'),
  ('OG73', '250704', 'hic1', 'OG73W-3_HICL_NOVA_260123_TWAD', 'bam'),
  ('OG748', '241018', 'hic1', 'OG748G-1_HICL_NOVA_250624_LA', 'bam'),
  ('OG749', '250331', 'hic2', 'OG749G-2_HICL_NOVA_250505_AD', 'bam'),
  ('OG750', '241004', 'hic1', 'OG750G-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG750', '241105', 'hic3', 'OG750G-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG751', '250317', 'hic1', 'OG751G-1_HICL_NOVA_260209_TW1', 'bam'),
  ('OG755', '240821', 'hic1', 'OG755G-2_HICL_NOVA_241204_AD', 'bam'),
  ('OG756', '250704', 'hic1', 'OG756G-1_HICL_NOVA_260209_TW1', 'bam'),
  ('OG757', '241018', 'hic1', 'OG757G-1_HICL_NOVA_241125_AD', 'bam'),
  ('OG758', '241127', 'hic1', 'OG758M-3_HICL_NOVA_251204_AD2', 'bam'),
  ('OG759', '250520', 'hic1', 'OG759G-1_HICL_NOVA_240719_AD', 'bam'),
  ('OG76', '230825', 'hic1', 'OG76G-1_HICL_NEXT_240301_AD', 'bam'),
  ('OG760', '240520', 'hic1', 'OG760L-1_HICL_NOVA_240821_AD', 'bam'),
  ('OG762', '241019', 'hic1', 'OG762G-1_HICL_NOVA_250312_LA', 'bam'),
  ('OG763', '251117', 'hic1', 'OG763H-1_HICL_NOVA_250213_AD', 'bam'),
  ('OG765', '240821', 'hic1', 'OG765W-3_HICL_NOVA_250626_LA', 'bam'),
  ('OG766', '241004', 'hic1', 'OG766L-2_HICL_NOVA_250624_LA', 'bam'),
  ('OG767', '250331', 'hic1', 'OG767G-1_HICL_NOVA_250626_LA', 'bam'),
  ('OG769', '250828', 'hic1', 'OG769G-1_HICL_NOVA_260209_TW1', 'bam'),
  ('OG770', '241127', 'hic1', 'OG770M2-1_HICL_NOVA_251204_AD', 'bam'),
  ('OG775', '241004', 'hic1', 'OG775G-1_HICL_NOVA_250626_LA', 'bam'),
  ('OG777', '240520', 'hic1', 'OG777G-1_HICL_NOVA_240719_AD', 'bam'),
  ('OG778', '250331', 'hic1', 'OG778G-2_HICL_NOVA_250624_LA', 'bam'),
  ('OG78', '260626', 'hic1', 'OG78W-1_HICL_NOVA_260706_TW', 'bam'),
  ('OG781', '260421', 'hic1', 'OG781L-1_HICL2_NEXT_250613_LA', 'bam'),
  ('OG781', '260421', 'hic1', 'OG781L-1_HICL2_NOVA_250624_LA', 'bam'),
  ('OG784', '241018', 'hic1', 'OG784G-1_HICL_NOVA_251204_AD2', 'bam'),
  ('OG787', '240927', 'hic1', 'OG787G-2_HICL_NOVA_241204_AD', 'bam'),
  ('OG788', '250505', 'hic1', 'OG788G-1_HICL_NOVA_241204_AD', 'bam'),
  ('OG79', '240427', 'hic1', 'OG79G-1_HICL2_NOVA_240522_AD', 'bam'),
  ('OG790', '250704', 'hic1', 'OG790G-1_HICL_NOVA_260209_TW1', 'bam'),
  ('OG790', '250704', 'hic1', 'OG790G-2_HICL_NOVA_260209_TW1', 'bam'),
  ('OG793', '250317', 'hic2', 'OG793G-1_HICL_NOVA_260209_TW2', 'bam'),
  ('OG794', '250317', 'hic2', 'OG794G-1_HICL_NOVA_260209_TW2', 'bam'),
  ('OG799', '241019', 'hic1', 'OG799L-1_HICL_NOVA_250312_LA', 'bam'),
  ('OG8', '230512', 'hic1', 'OG8G-1_HICL_NOVA_240719_AD', 'bam'),
  ('OG800', '241004', 'hic1', 'OG800L-1_HICL_NOVA_250312_LA', 'bam'),
  ('OG800', '241004', 'hic1', 'OG800L-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG801', '250828', 'hic1', 'OG801L-1_HICL_NOVA_260209_TW1', 'bam'),
  ('OG803', '240927', 'hic1', 'OG803G-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG804', '260522', 'hic1', 'OG804G-1_HICL_NOVA_260605_AD', 'bam'),
  ('OG808', '240520', 'hic2', 'OG808G-1_HICL_NOVA_240821_AD', 'bam'),
  ('OG808', '240520', 'hic2', 'OG808G-2_HICL_NOVA_250213_AD', 'bam'),
  ('OG808', '240520', 'hic2', 'OG808G-2_HICL_NOVA_250312_LA', 'bam'),
  ('OG81', '250704', 'hic1', 'OG81W-1_HICL_NOVA_251204_AD', 'bam'),
  ('OG810', '241004', 'hic1', 'OG810G-2_HICL_NOVA_260605_AD', 'bam'),
  ('OG811', '241004', 'hic1', 'OG811L-1_HICL_NOVA_250624_LA', 'bam'),
  ('OG813', '250704', 'hic2', 'OG813G-1_HICL_NOVA_260209_TW2', 'bam'),
  ('OG819', '250704', 'hic2', 'OG819G-2_HICL_NOVA_260209_TW2', 'bam'),
  ('OG820', '240501', 'hic1', 'OG820G-1_HICL2_NOVA_240719_AD', 'bam'),
  ('OG820', '240502', 'hic2', 'OG820M-1_HICL_NOVA_250626_LA', 'bam'),
  ('OG824', '241004', 'hic1', 'OG824G-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG829', '240927', 'hic1', 'OG829L-2_HICL_NOVA_250624_LA', 'bam'),
  ('OG834', '250331', 'hic1', 'OG834L-1_HICL_NOVA_251204_AD', 'bam'),
  ('OG836', '240520', 'hic1', 'OG836B-1_HICL2_NOVA_241106_AD', 'bam'),
  ('OG836', '240520', 'hic1', 'OG836B-1_HICL_NOVA_241106_AD', 'bam'),
  ('OG837', '240813', 'hic1', 'OG837B-1_HICL2_NOVA_241106_AD', 'bam'),
  ('OG837', '240813', 'hic1', 'OG837B-1_HICL_NOVA_241106_AD', 'bam'),
  ('OG838', '240813', 'hic1', 'OG838B-1_HICL2_NOVA_241106_AD', 'bam'),
  ('OG838', '240813', 'hic1', 'OG838B-1_HICL_NOVA_241106_AD', 'bam'),
  ('OG838', '240813', 'hic1', 'OG838B-1_HICL_NOVA_250522_AD', 'bam'),
  ('OG844', '241023', 'hic1', 'OG844H-1_HICL_NOVA_250213_AD', 'bam'),
  ('OG844', '241023', 'hic1', 'OG844H-4_HICL2_NOVA_250213_AD', 'bam'),
  ('OG844', '241023', 'hic1', 'OG844H-4_HICL_NOVA_250213_AD', 'bam'),
  ('OG845', '241023', 'hic1', 'OG845H-1_HICL_NOVA_250213_AD', 'bam'),
  ('OG845', '241023', 'hic1', 'OG845H-2_HICL2_NOVA_250213_AD', 'bam'),
  ('OG845', '241023', 'hic1', 'OG845H-2_HICL_NOVA_250213_AD', 'bam'),
  ('OG849', '241127', 'hic1', 'OG849M-1_HICL_NOVA_250626_LA', 'bam'),
  ('OG85', '240927', 'hic1', 'OG85G-1_HICL_NOVA_250312_LA', 'bam'),
  ('OG855', '240821', 'hic1', 'OG855L-2_HICL_NOVA_250505_AD', 'bam'),
  ('OG856', '240821', 'hic1', 'OG856L2-1_HICL_NOVA_241204_AD', 'bam'),
  ('OG856', '240821', 'hic1', 'OG856L2-1_HICL_NOVA_250505_AD', 'bam'),
  ('OG859', '241023', 'hic2', 'OG859O-1_HICL_NOVA_241125_AD', 'bam'),
  ('OG863', '241004', 'hic1', 'OG863G-2_HICL_NOVA_250312_LA', 'bam'),
  ('OG863', '241004', 'hic1', 'OG863G-2_HICL_NOVA_250522_AD', 'bam'),
  ('OG863', '250331', 'hic1', 'OG863G-2_HICL_NOVA_250312_LA', 'omnic'),
  ('OG863', '250331', 'hic1', 'OG863G-2_HICL_NOVA_250522_AD', 'omnic'),
  ('OG866', '250505', 'hic1', 'OG866G-3_HICL_NOVA_250505_AD', 'bam'),
  ('OG88', '230728', 'hic1', 'OG88L-1_HICL_ISEQ_230719_AD', 'iseq'),
  ('OG88', '230728', 'hic1', 'OG88L-1_HICL_NEXT_230801_AD', 'bam'),
  ('OG9', '240206', 'hic1', 'OG9G-2_HICL_NEXT_240301_AD', 'bam'),
  ('OG90', '240821', 'hic1', 'OG90M-4_HICL_NOVA_241106_AD', 'bam'),
  ('OG90', '240821', 'hic1', 'OG90M-4_HICL_NOVA_250522_AD', 'bam'),
  ('OG907', '250828', 'hic1', 'OG907L-1_HICL_NOVA_260209_TW2', 'bam'),
  ('OG910', '241127', 'hic1', 'OG910L-1_HICL_NOVA_241204_AD', 'bam'),
  ('OG910', '241127', 'hic2', 'OG910L-1_HICL_NOVA_241204_AD', 'bam'),
  ('OG95', '230529', 'hic1', 'OG95H-1_HICL_NEXT_230912_AD', 'bam'),
  ('OG99', '240215', 'hic1', 'OG99G-2_HICL_NOVA_240522_AD', 'bam');

CREATE TEMP TABLE d_evidence (og_id text, seq_date text, version text, flowcell text, bam_records integer,
                              source text, PRIMARY KEY (og_id, seq_date, version, flowcell)) ON COMMIT DROP;
INSERT INTO d_evidence VALUES
  ('OG1', '230525', 'hic1', 'AAC3NM7HV', 34899, 'bam'),
  ('OG10', '230209', 'hic2', 'AAAWHNMHV', 41962, 'bam'),
  ('OG100', '240116', 'hic1', 'H2MJJDRX7', 52156, 'bam'),
  ('OG100', '240116', 'hic2', 'H2MJJDRX7', 55636, 'bam'),
  ('OG101', '240206', 'hic1', 'AAC3NKWHV', 44107, 'bam'),
  ('OG105', '231027', 'hic1', 'HCGWCDRX5', 45720, 'bam'),
  ('OG106', '240927', 'hic1', 'H2MJJDRX7', 66144, 'bam'),
  ('OG106', '240927', 'hic2', 'H2MJJDRX7', 57211, 'bam'),
  ('OG107', '240125', 'hic1', 'HNGHVDRX3', 31183, 'bam'),
  ('OG107', '240125', 'hic1', 'HWFHKDRX5', 13946, 'bam'),
  ('OG108', '231027', 'hic1', 'HCJKHDRX5', 46470, 'bam'),
  ('OG11', '230825', 'hic1', 'AAC3VGWHV', 41386, 'bam'),
  ('OG111', '241018', 'hic1', 'H2MJJDRX7', 52660, 'bam'),
  ('OG113', '231027', 'hic1', 'HCJKHDRX5', 52044, 'bam'),
  ('OG113', '231028', 'hic1', 'HCJKHDRX5', 50327, 'bam'),
  ('OG114', '240116', 'hic2', 'HCCCGDRX5', 29540, 'bam'),
  ('OG114', '240116', 'hic2', 'H3LTVDRX7', 20706, 'bam'),
  ('OG115', '240125', 'hic1', 'HCCCGDRX5', 49688, 'bam'),
  ('OG1161', '250113', 'hic2', 'H5WFWDMX2', 52653, 'bam'),
  ('OG12', '230516', 'hic1', 'HCGFGDRX5', 46254, 'bam'),
  ('OG13', '230212', 'hic1', 'AAC3NMMHV', 44364, 'bam'),
  ('OG1326', '260730', 'hic1', 'HNVT7DRX7', 46546, 'bam'),
  ('OG14', '230209', 'hic1', 'AAC3VGWHV', 41103, 'bam'),
  ('OG15', '230413', 'hic1', 'AAC3VGWHV', 42139, 'bam'),
  ('OG1573', '260626', 'hic2', 'HGYMYDMX2', 50754, 'bam'),
  ('OG16', '240417', 'hic1', 'HCGFGDRX5', 39191, 'bam'),
  ('OG1613', '260603', 'hic2', 'HGYMYDMX2', 54091, 'bam'),
  ('OG1663', '260603', 'hic2', 'HGYMYDMX2', 53934, 'bam'),
  ('OG2', '230414', 'hic1', 'AAC3NM7HV', 37348, 'bam'),
  ('OG2088', '260414', 'hic1', 'HNTVNDRX7', 57480, 'bam'),
  ('OG2089', '260721', 'hic1', 'HGYMYDMX2', 49209, 'bam'),
  ('OG2093', '260721', 'hic1', 'HNVT7DRX7', 44458, 'bam'),
  ('OG2104', '260414', 'hic2', 'HGK2LDRX7', 44318, 'bam'),
  ('OG2105', '260421', 'hic1', 'HGYMYDMX2', 49968, 'bam'),
  ('OG2112', '260603', 'hic1', 'HGK2LDRX7', 33035, 'bam'),
  ('OG2112', '260603', 'hic1', 'HNTVNDRX7', 21710, 'bam'),
  ('OG2119', '260408', 'hic1', 'HGK2LDRX7', 26792, 'bam'),
  ('OG2119', '260408', 'hic1', 'HNTVNDRX7', 21483, 'bam'),
  ('OG2119', '260408', 'hic2', 'HGK2LDRX7', 29618, 'bam'),
  ('OG2119', '260408', 'hic2', 'HNTVNDRX7', 14321, 'bam'),
  ('OG2121', '260511', 'hic1', 'HNVT7DRX7', 52209, 'bam'),
  ('OG2122', '260511', 'hic1', 'HNVT7DRX7', 46669, 'bam'),
  ('OG2124', '260421', 'hic1', 'HGK2LDRX7', 20805, 'bam'),
  ('OG2124', '260421', 'hic1', 'HNTVNDRX7', 30906, 'bam'),
  ('OG2126', '260730', 'hic1', 'HGYMYDMX2', 56470, 'bam'),
  ('OG2127', '260603', 'hic1', 'HGK2LDRX7', 21015, 'bam'),
  ('OG2127', '260603', 'hic1', 'HNTVNDRX7', 24952, 'bam'),
  ('OG2127', '260603', 'hic2', 'HGK2LDRX7', 21001, 'bam'),
  ('OG2127', '260603', 'hic2', 'HNTVNDRX7', 24947, 'bam'),
  ('OG2128', '260721', 'hic1', 'HNVT7DRX7', 31108, 'bam'),
  ('OG2128', '260721', 'hic1', 'HGYMYDMX2', 13952, 'bam'),
  ('OG2132', '260408', 'hic1', 'HGK37DRX7', 36341, 'bam'),
  ('OG2132', '260408', 'hic1', 'HNTVNDRX7', 11574, 'bam'),
  ('OG2145', '260730', 'hic1', 'HGYMYDMX2', 40897, 'bam'),
  ('OG2146', '260414', 'hic1', 'HGK37DRX7', 26131, 'bam'),
  ('OG2146', '260414', 'hic1', 'HNTVNDRX7', 20601, 'bam'),
  ('OG2156', '260408', 'hic1', 'HGK37DRX7', 30460, 'bam'),
  ('OG2156', '260408', 'hic1', 'HNTVNDRX7', 20937, 'bam'),
  ('OG2163', '260603', 'hic1', 'HGK37DRX7', 33476, 'bam'),
  ('OG2163', '260603', 'hic1', 'HNTVNDRX7', 18895, 'bam'),
  ('OG2164', '260331', 'hic1', 'HGK37DRX7', 49380, 'bam'),
  ('OG2178', '260408', 'hic1', 'HNVT7DRX7', 53305, 'bam'),
  ('OG2188', '260408', 'hic1', 'HGK37DRX7', 49332, 'bam'),
  ('OG2202', '260331', 'hic1', 'HGK37DRX7', 46885, 'bam'),
  ('OG2202', '260331', 'hic2', 'HGK37DRX7', 35144, 'bam'),
  ('OG2202', '260331', 'hic2', 'HNTVNDRX7', 15332, 'bam'),
  ('OG2203', '260408', 'hic1', 'HNVT7DRX7', 28506, 'bam'),
  ('OG2203', '260408', 'hic1', 'HGYMYDMX2', 23188, 'bam'),
  ('OG2237', '260414', 'hic1', 'HNVT7DRX7', 53067, 'bam'),
  ('OG2242', '260414', 'hic1', 'HNVT7DRX7', 48391, 'bam'),
  ('OG28', '230811', 'hic1', 'AAAWHNMHV', 40001, 'bam'),
  ('OG3', '230825', 'hic1', 'AAC3NM7HV', 38901, 'bam'),
  ('OG35', '231027', 'hic1', 'AAC3VGWHV', 45187, 'bam'),
  ('OG36', '230724', 'hic1', 'AAC3VGWHV', 40645, 'bam'),
  ('OG37', '240116', 'hic2', 'HWLY7DRX5', 52592, 'bam'),
  ('OG39', '250331', 'hic1', 'HJT3WDRX5', 47255, 'bam'),
  ('OG40', '241004', 'hic1', 'H757YDRX7', 50139, 'bam'),
  ('OG46', '240215', 'hic1', 'AAC3NMMHV', 37036, 'bam'),
  ('OG47', '231115', 'hic1', 'AAC3VGWHV', 43724, 'bam'),
  ('OG5', '240116', 'hic2', 'H3LTVDRX7', 19744, 'bam'),
  ('OG5', '240116', 'hic2', 'AAAWHNMHV', 22815, 'bam'),
  ('OG52', '230825', 'hic1', 'AAC3VGWHV', 43072, 'bam'),
  ('OG53', '230915', 'hic1', 'AAC3NKWHV', 48810, 'bam'),
  ('OG54', '250331', 'hic1', 'H5WFWDMX2', 49329, 'bam'),
  ('OG55', '231115', 'hic1', 'H757YDRX7', 51909, 'bam'),
  ('OG56', '250704', 'hic1', 'H757YDRX7', 61951, 'bam'),
  ('OG57', '231027', 'hic1', 'HWG32DRX5', 49542, 'bam'),
  ('OG58', '250704', 'hic1', 'HWG32DRX5', 53042, 'bam'),
  ('OG6', '230702', 'hic1', 'AAC3NM7HV', 40588, 'bam'),
  ('OG61', '250317', 'hic1', 'HWG32DRX5', 45330, 'bam'),
  ('OG61', '250318', 'hic1', 'HWG32DRX5', 49413, 'bam'),
  ('OG62', '250307', 'hic1', 'HWLY7DRX5', 52754, 'bam'),
  ('OG637', '240521', 'hic1', 'AAC3NMMHV', 39246, 'bam'),
  ('OG64', '250728', 'hic1', 'H757YDRX7', 59875, 'bam'),
  ('OG645', '240417', 'hic1', 'HCCCGDRX5', 44468, 'bam'),
  ('OG645', '240427', 'hic1', 'HCCCGDRX5', 44468, 'bam'),
  ('OG646', '240821', 'hic1', 'HCCCGDRX5', 7723, 'bam'),
  ('OG646', '240821', 'hic1', 'HWM25DRX5', 36454, 'bam'),
  ('OG647', '240501', 'hic1', 'HCCCGDRX5', 42450, 'bam'),
  ('OG648', '250704', 'hic1', 'H3LWWDRX7', 47184, 'bam'),
  ('OG649', '240417', 'hic1', 'HWM25DRX5', 50007, 'bam'),
  ('OG65', '250704', 'hic1', 'H2MJJDRX7', 49471, 'bam'),
  ('OG650', '240327', 'hic1', 'HNGHVDRX3', 42735, 'bam'),
  ('OG651', '240327', 'hic1', 'HNGHVDRX3', 47314, 'bam'),
  ('OG652', '240327', 'hic1', 'H2MJJDRX7', 43652, 'bam'),
  ('OG654', '240327', 'hic1', 'HNGHVDRX3', 47437, 'bam'),
  ('OG657', '250110', 'hic1', 'HJTLGDRX5', 43589, 'bam'),
  ('OG658', '240327', 'hic1', 'H3LWWDRX7', 43979, 'bam'),
  ('OG659', '240418', 'hic1', 'HCGFGDRX5', 42503, 'bam'),
  ('OG659', '240427', 'hic2', 'HCGFGDRX5', 36832, 'bam'),
  ('OG659', '240427', 'hic2', 'H3LTVDRX7', 8540, 'bam'),
  ('OG660', '240228', 'hic1', 'AAC3NKWHV', 39192, 'bam'),
  ('OG662', '240327', 'hic1', 'H3LTVDRX7', 52093, 'bam'),
  ('OG664', '241018', 'hic1', 'HWLY7DRX5', 54940, 'bam'),
  ('OG665', '240501', 'hic2', 'HJTLKDRX5', 28426, 'bam'),
  ('OG665', '240501', 'hic2', 'HWLY7DRX5', 21975, 'bam'),
  ('OG666', '241004', 'hic1', 'HWM25DRX5', 33796, 'bam'),
  ('OG666', '241004', 'hic1', 'H3LTVDRX7', 14032, 'bam'),
  ('OG67', '241127', 'hic1', 'H2MJJDRX7', 60510, 'bam'),
  ('OG672', '240215', 'hic1', 'AAC3NKWHV', 36060, 'bam'),
  ('OG673', '240427', 'hic1', 'HJTLKDRX5', 52217, 'bam'),
  ('OG675', '250828', 'hic1', 'H3LWWDRX7', 47710, 'bam'),
  ('OG676', '240327', 'hic1', 'HJTLKDRX5', 55563, 'bam'),
  ('OG678', '240327', 'hic2', 'HJT3WDRX5', 43104, 'bam'),
  ('OG678', '240327', 'hic2', 'HJTLKDRX5', 9941, 'bam'),
  ('OG679', '250307', 'hic1', 'H5WFWDMX2', 44151, 'bam'),
  ('OG680', '241004', 'hic1', 'HWM25DRX5', 50331, 'bam'),
  ('OG681', '250307', 'hic1', 'H5WFWDMX2', 53191, 'bam'),
  ('OG683', '241025', 'hic1', 'HJTLKDRX5', 47010, 'bam'),
  ('OG686', '241004', 'hic1', 'H5WFWDMX2', 48182, 'bam'),
  ('OG695', '240520', 'hic1', 'HJTLGDRX5', 40448, 'bam'),
  ('OG696', '240228', 'hic1', 'HCGFGDRX5', 38910, 'bam'),
  ('OG696', '240228', 'hic1', 'H3LTVDRX7', 7028, 'bam'),
  ('OG696', '240228', 'hic2', 'HCGFGDRX5', 39207, 'bam'),
  ('OG696', '240228', 'hic2', 'H3LTVDRX7', 7068, 'bam'),
  ('OG698', '241004', 'hic1', 'H5WFWDMX2', 34480, 'bam'),
  ('OG698', '241004', 'hic1', 'HWFHKDRX5', 10766, 'bam'),
  ('OG699', '250317', 'hic1', 'H5WFWDMX2', 28300, 'bam'),
  ('OG699', '250317', 'hic1', 'HWFHKDRX5', 22881, 'bam'),
  ('OG699', '250317', 'hic1', 'AAGTYJ5M5', 966, 'bam'),
  ('OG7', '230915', 'hic1', 'AAC3NMMHV', 44815, 'bam'),
  ('OG70', '250307', 'hic1', 'HWG32DRX5', 51101, 'bam'),
  ('OG701', '240509', 'hic1', 'HCGFGDRX5', 40293, 'bam'),
  ('OG702', '240501', 'hic2', 'HJTLKDRX5', 37820, 'bam'),
  ('OG702', '240501', 'hic2', 'AAF5HLVM5', 3088, 'bam'),
  ('OG704', '240427', 'hic1', 'H3LWWDRX7', 48188, 'bam'),
  ('OG72', '241023', 'hic1', 'H757YDRX7', 53100, 'bam'),
  ('OG721', '240501', 'hic1', 'H3LWWDRX7', 56836, 'bam'),
  ('OG73', '250704', 'hic1', 'H2MJJDRX7', 50690, 'bam'),
  ('OG748', '241018', 'hic1', 'H5WFWDMX2', 53488, 'bam'),
  ('OG749', '250331', 'hic2', 'HWLY7DRX5', 53252, 'bam'),
  ('OG750', '241004', 'hic1', 'H3LTVDRX7', 47231, 'bam'),
  ('OG750', '241105', 'hic3', 'H3LTVDRX7', 47482, 'bam'),
  ('OG751', '250317', 'hic1', 'H3LWWDRX7', 50928, 'bam'),
  ('OG755', '240821', 'hic1', 'HJTFWDRX5', 48258, 'bam'),
  ('OG756', '250704', 'hic1', 'H3LWWDRX7', 51114, 'bam'),
  ('OG757', '241018', 'hic1', 'HJT3WDRX5', 55761, 'bam'),
  ('OG758', '241127', 'hic1', 'HWG32DRX5', 58266, 'bam'),
  ('OG759', '250520', 'hic1', 'HCGWCDRX5', 52449, 'bam'),
  ('OG76', '230825', 'hic1', 'AAC3NKWHV', 44305, 'bam'),
  ('OG760', '240520', 'hic1', 'HJTLGDRX5', 46631, 'bam'),
  ('OG762', '241019', 'hic1', 'HWM25DRX5', 53904, 'bam'),
  ('OG763', '251117', 'hic1', 'HNTVWDRX5', 44940, 'bam'),
  ('OG765', '240821', 'hic1', 'H73KYDRX7', 39660, 'bam'),
  ('OG766', '241004', 'hic1', 'H5WFWDMX2', 41286, 'bam'),
  ('OG767', '250331', 'hic1', 'H73KYDRX7', 46140, 'bam'),
  ('OG769', '250828', 'hic1', 'H3LWWDRX7', 45500, 'bam'),
  ('OG770', '241127', 'hic1', 'H757YDRX7', 49565, 'bam'),
  ('OG775', '241004', 'hic1', 'H73KYDRX7', 48268, 'bam'),
  ('OG777', '240520', 'hic1', 'HCGWCDRX5', 50585, 'bam'),
  ('OG778', '250331', 'hic1', 'H5WFWDMX2', 52812, 'bam'),
  ('OG78', '260626', 'hic1', 'HGYMYDMX2', 53478, 'bam'),
  ('OG781', '260421', 'hic1', 'H5WFWDMX2', 43745, 'bam'),
  ('OG781', '260421', 'hic1', 'AAGTYJ5M5', 1690, 'bam'),
  ('OG784', '241018', 'hic1', 'HWG32DRX5', 77556, 'bam'),
  ('OG785', '241004', 'hic2', 'HWLY7DRX5', 49780, 'bam'),
  ('OG787', '240927', 'hic1', 'HJTFWDRX5', 46441, 'bam'),
  ('OG788', '250505', 'hic1', 'HJTFWDRX5', 50722, 'bam'),
  ('OG79', '240427', 'hic1', 'HCJKHDRX5', 37299, 'bam'),
  ('OG79', '240427', 'hic2', 'HCJKHDRX5', 2021, 'bam'),
  ('OG79', '240427', 'hic2', 'HWM25DRX5', 40067, 'bam'),
  ('OG790', '250704', 'hic1', 'H3LWWDRX7', 48171, 'bam'),
  ('OG793', '250317', 'hic2', 'H3HHJDRX7', 46094, 'bam'),
  ('OG794', '250317', 'hic2', 'H3HHJDRX7', 50410, 'bam'),
  ('OG799', '241019', 'hic1', 'HWM25DRX5', 50501, 'bam'),
  ('OG8', '230512', 'hic1', 'HCGWCDRX5', 29685, 'bam'),
  ('OG800', '241004', 'hic1', 'HWM25DRX5', 25456, 'bam'),
  ('OG800', '241004', 'hic1', 'H3LTVDRX7', 20968, 'bam'),
  ('OG801', '250828', 'hic1', 'H3LWWDRX7', 52551, 'bam'),
  ('OG803', '240927', 'hic1', 'H3LTVDRX7', 39190, 'bam'),
  ('OG804', '260522', 'hic1', 'HNTVNDRX7', 48626, 'bam'),
  ('OG808', '240520', 'hic2', 'HJTLGDRX5', 25534, 'bam'),
  ('OG808', '240520', 'hic2', 'HNTVWDRX5', 944, 'bam'),
  ('OG808', '240520', 'hic2', 'HWM25DRX5', 22373, 'bam'),
  ('OG81', '250704', 'hic1', 'H757YDRX7', 56734, 'bam'),
  ('OG810', '241004', 'hic1', 'HNTVNDRX7', 48141, 'bam'),
  ('OG811', '241004', 'hic1', 'H5WFWDMX2', 58020, 'bam'),
  ('OG813', '250704', 'hic2', 'H3HHJDRX7', 48902, 'bam'),
  ('OG819', '250704', 'hic2', 'H3HHJDRX7', 53123, 'bam'),
  ('OG820', '240501', 'hic1', 'HCGWCDRX5', 42654, 'bam'),
  ('OG820', '240502', 'hic2', 'H73KYDRX7', 58370, 'bam'),
  ('OG824', '241004', 'hic1', 'H3LTVDRX7', 47293, 'bam'),
  ('OG829', '240927', 'hic1', 'H5WFWDMX2', 50496, 'bam'),
  ('OG834', '250331', 'hic1', 'H757YDRX7', 47995, 'bam'),
  ('OG836', '240520', 'hic1', 'HFYJJDRX5', 44532, 'bam'),
  ('OG837', '240813', 'hic1', 'HFYJJDRX5', 42042, 'bam'),
  ('OG838', '240813', 'hic1', 'HFYJJDRX5', 38558, 'bam'),
  ('OG838', '240813', 'hic1', 'H3LTVDRX7', 5867, 'bam'),
  ('OG844', '241023', 'hic1', 'HNTVWDRX5', 49248, 'bam'),
  ('OG845', '241023', 'hic1', 'HNTVWDRX5', 47189, 'bam'),
  ('OG849', '241127', 'hic1', 'H73KYDRX7', 56081, 'bam'),
  ('OG85', '240927', 'hic1', 'HWM25DRX5', 48440, 'bam'),
  ('OG855', '240821', 'hic1', 'HWLY7DRX5', 48556, 'bam'),
  ('OG856', '240821', 'hic1', 'HJTFWDRX5', 10341, 'bam'),
  ('OG856', '240821', 'hic1', 'HWLY7DRX5', 44283, 'bam'),
  ('OG859', '241023', 'hic2', 'HJT3WDRX5', 49725, 'bam'),
  ('OG863', '241004', 'hic1', 'HWM25DRX5', 26803, 'bam'),
  ('OG863', '241004', 'hic1', 'H3LTVDRX7', 19415, 'bam'),
  ('OG863', '250331', 'hic1', 'HWM25DRX5', NULL, 'omnic'),
  ('OG863', '250331', 'hic1', 'H3LTVDRX7', NULL, 'omnic'),
  ('OG866', '250505', 'hic1', 'HWLY7DRX5', 52443, 'bam'),
  ('OG88', '230728', 'hic1', 'BSB09424-1410', 1335, 'bam'),
  ('OG88', '230728', 'hic1', 'AACHJC3M5', 39005, 'bam'),
  ('OG9', '240206', 'hic1', 'AAC3NKWHV', 46558, 'bam'),
  ('OG90', '240821', 'hic1', 'HFYJJDRX5', 45568, 'bam'),
  ('OG90', '240821', 'hic1', 'H3LTVDRX7', 4298, 'bam'),
  ('OG906', '250212', 'hic1', 'HNGHVDRX3', 43470, 'bam'),
  ('OG907', '250828', 'hic1', 'H3HHJDRX7', 50321, 'bam'),
  ('OG910', '241127', 'hic1', 'HJTFWDRX5', 46607, 'bam'),
  ('OG910', '241127', 'hic2', 'HJTFWDRX5', 46199, 'bam'),
  ('OG95', '230529', 'hic1', 'AAAWHNMHV', 36887, 'bam'),
  ('OG99', '240215', 'hic1', 'HCJKHDRX5', 50009, 'bam');

CREATE TEMP TABLE d_unlinked (og_id text, seq_date text, version text, reason text,
                              PRIMARY KEY (og_id, seq_date, version)) ON COMMIT DROP;
INSERT INTO d_unlinked VALUES
  ('OG2088', '260414', 'hic2', 'no Hi-C BAM on Acacia; OMNIC''s 240,870,035 read pairs fit 2 sets of the OG''s runs: NOVA_260420_TW1+NOVA_260605_AD | ISEQ_260416_TW+NOVA_260420_TW1+NOVA_260605_AD'),
  ('OG38', '230609', 'hic1', 'no Hi-C BAM on Acacia and no single OMNIC total'),
  ('OG706', '240206', 'hic2', 'no Hi-C BAM on Acacia and no single OMNIC total'),
  ('OG749', '241018', 'hic1', 'no Hi-C BAM on Acacia; OMNIC''s 243,560,695 read pairs fit 2 sets of the OG''s runs: NOVA_250505_AD | NEXT_250325_AD+NOVA_250505_AD'),
  ('OG785', '241004', 'hic2', '100.0% of its Hi-C reads are from NOVA_250505_AD, which has no OG785 Hi-C sequencing row'),
  ('OG79', '240427', 'hic2', '95.2% of its Hi-C reads are from NOVA_250312_LA, which has no OG79 Hi-C sequencing row'),
  ('OG804', '260522', 'hic2', 'no Hi-C BAM on Acacia; OMNIC''s 221,756,607 read pairs fit 2 sets of the OG''s runs: NOVA_260420_TW1+NOVA_260605_AD | ISEQ_260416_TW+NOVA_260420_TW1+NOVA_260605_AD'),
  ('OG810', '241004', 'hic2', 'no Hi-C BAM on Acacia and no single OMNIC total'),
  ('OG860', '240927', 'hic1', 'no Hi-C BAM on Acacia and no single OMNIC total'),
  ('OG906', '250212', 'hic1', '100.0% of its Hi-C reads are from NOVA_240501_LA, which has no OG906 Hi-C sequencing row');

-- Backfill (first application only) -------------------------------------------------------------------

DO $backfill$
DECLARE
  n   bigint;
  bad record;
BEGIN
  IF NOT (SELECT first_apply FROM m094) THEN
    RETURN;
  END IF;

  IF (SELECT count(*) FROM ref_assembly WHERE strategy = 'hic') <> 201 THEN
    RAISE EXCEPTION '094: live has % Hi-C assemblies; the data was built from 201',
      (SELECT count(*) FROM ref_assembly WHERE strategy = 'hic');
  END IF;
  SELECT count(*) INTO n FROM ref_assembly_run l JOIN v_sequencing_browse s USING (sequencing_id)
   WHERE s.technology = 'Hi-C';
  IF n <> 0 THEN
    RAISE EXCEPTION '094: live already has % Hi-C assembly links; the data was built from none', n;
  END IF;
  SELECT d.* INTO bad FROM d_flowcell d LEFT JOIN sequencing_run r USING (run_id) WHERE r.run_id IS NULL LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION '094: run % is not in sequencing_run', bad.run_id;
  END IF;
  SELECT d.* INTO bad FROM (SELECT og_id, seq_date, version FROM d_evidence UNION SELECT og_id, seq_date, version FROM d_link
                            UNION SELECT og_id, seq_date, version FROM d_unlinked) d
    LEFT JOIN ref_assembly a USING (og_id, seq_date, version)
   WHERE a.assembly_id IS NULL OR a.strategy <> 'hic' LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION '094: % %.% is not a Hi-C assembly', bad.og_id, bad.seq_date, bad.version;
  END IF;
  IF (SELECT count(DISTINCT (og_id, seq_date, version)) FROM d_link) + (SELECT count(*) FROM d_unlinked) <> 201
     OR EXISTS (SELECT 1 FROM d_link JOIN d_unlinked USING (og_id, seq_date, version)) THEN
    RAISE EXCEPTION '094: the data does not cover each Hi-C assembly once (linked or unlinked)';
  END IF;

  UPDATE sequencing_run r SET flowcell = d.flowcell FROM d_flowcell d WHERE r.run_id = d.run_id;  -- a backfill: updated_at kept
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 38 THEN
    RAISE EXCEPTION '094: set % run flowcells, expected 38', n;
  END IF;

  -- The row trigger derives each assembly's Hi-C links from its flowcells.
  INSERT INTO ref_assembly_hic_flowcell (assembly_id, flowcell, bam_records, source)
  SELECT a.assembly_id, d.flowcell, d.bam_records, d.source
    FROM d_evidence d JOIN ref_assembly a USING (og_id, seq_date, version);
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 232 THEN
    RAISE EXCEPTION '094: stored % assembly flowcells, expected 232', n;
  END IF;

  INSERT INTO ref_assembly_hic_unlinked (assembly_id, reason, reviewed_on)
  SELECT a.assembly_id, d.reason, DATE '2026-11-23' FROM d_unlinked d JOIN ref_assembly a USING (og_id, seq_date, version);
END
$backfill$;

-- Checks and probes ------------------------------------------------------------------------------------

DO $check$
DECLARE
  n        bigint;
  before   text;
  after    text;
  problems text[];
  r        record;
BEGIN
  -- The derived links are exactly the data's.
  SELECT count(*) INTO n FROM (
    (SELECT l.assembly_id, l.sequencing_id FROM ref_assembly_run l JOIN v_sequencing_browse s USING (sequencing_id)
      WHERE s.technology = 'Hi-C' AND s.library_type = 'hic'
     EXCEPT SELECT a.assembly_id, d.sequencing_id FROM d_link d JOIN ref_assembly a USING (og_id, seq_date, version))
    UNION ALL
    (SELECT a.assembly_id, d.sequencing_id FROM d_link d JOIN ref_assembly a USING (og_id, seq_date, version)
     EXCEPT SELECT l.assembly_id, l.sequencing_id FROM ref_assembly_run l JOIN v_sequencing_browse s USING (sequencing_id)
      WHERE s.technology = 'Hi-C' AND s.library_type = 'hic')) x;
  IF n <> 0 AND (SELECT first_apply FROM m094) THEN
    RAISE EXCEPTION '094 check: % Hi-C links differ from the data', n;
  END IF;

  -- Every Hi-C assembly is linked or has a reviewed reason.
  IF (SELECT count(*) FROM v_ref_assembly_hic_readiness WHERE reason IS NULL) <> 0 THEN
    RAISE EXCEPTION '094 check: % Hi-C assemblies have neither a Hi-C link nor a reason',
      (SELECT count(*) FROM v_ref_assembly_hic_readiness WHERE reason IS NULL);
  END IF;

  -- refresh_assembly_runs() over every OG changes no link.
  SELECT md5(string_agg(assembly_id || ':' || sequencing_id, ',' ORDER BY assembly_id, sequencing_id)) INTO before FROM ref_assembly_run;
  PERFORM refresh_assembly_runs(ARRAY(SELECT og_id FROM sample));
  SELECT md5(string_agg(assembly_id || ':' || sequencing_id, ',' ORDER BY assembly_id, sequencing_id)) INTO after FROM ref_assembly_run;
  IF before IS DISTINCT FROM after THEN
    RAISE EXCEPTION '094 check: refresh_assembly_runs() changed ref_assembly_run';
  END IF;

  -- The writer's entry point, given each assembly's own BAM flowcells again, changes nothing and
  -- reports a problem exactly where the assembly is unlinked.
  FOR r IN SELECT a.assembly_id, array_agg(d.flowcell ORDER BY d.flowcell) AS fcs,
                  array_agg(d.bam_records ORDER BY d.flowcell) AS recs,
                  EXISTS (SELECT 1 FROM ref_assembly_hic_unlinked u WHERE u.assembly_id = a.assembly_id) AS unlinked
             FROM d_evidence d JOIN ref_assembly a USING (og_id, seq_date, version)
            WHERE d.source = 'bam' GROUP BY a.assembly_id LOOP
    SELECT string_agg(sequencing_id, ',' ORDER BY sequencing_id) INTO before FROM ref_assembly_run WHERE assembly_id = r.assembly_id;
    problems := set_ref_assembly_hic_flowcells(r.assembly_id, r.fcs, r.recs);
    SELECT string_agg(sequencing_id, ',' ORDER BY sequencing_id) INTO after FROM ref_assembly_run WHERE assembly_id = r.assembly_id;
    IF before IS DISTINCT FROM after THEN
      RAISE EXCEPTION '094 probe: set_ref_assembly_hic_flowcells(%) changed its links: % -> %', r.assembly_id, before, after;
    END IF;
    IF (cardinality(problems) > 0) <> r.unlinked THEN
      RAISE EXCEPTION '094 probe: set_ref_assembly_hic_flowcells(%) returned %', r.assembly_id, problems;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM ref_assembly_hic_unlinked) <> 10 THEN
    RAISE EXCEPTION '094 probe: % reviewed exceptions, expected 10', (SELECT count(*) FROM ref_assembly_hic_unlinked);
  END IF;
END
$check$;

-- Comments ---------------------------------------------------------------------------------------------

COMMENT ON COLUMN public.sequencing_run.flowcell IS
  'The flowcell barcode (BaseSpace FlowcellBarcode; the third field of the run''s Illumina read names). '
  'Unique: a read name''s flowcell names its run. Backfilled for the 37 Hi-C runs on S3 from their FASTQs '
  'and BaseSpace run records, and for ISEQ_230719_AD by inference from OG88''s BAM (094); written for new '
  'Hi-C runs by ref_genomes_hic_automation push_hic_yield.py. NULL: not recorded.';
COMMENT ON TABLE public.ref_assembly_run IS
  'The sequencing rows an assembly was built from: PacBio (the runs of its read set, 093), ONT (the OG''s '
  'non-failed ONT rows of its seq_date) and Hi-C (the OG''s non-failed Hi-C rows on the runs of the '
  'flowcells in its Hi-C BAM, ref_assembly_hic_flowcell, when all resolve: v_ref_assembly_hic_rule, 094). '
  'Kept current by refresh_assembly_runs() from triggers on ref_assembly, ref_read_set_run, '
  'ref_assembly_hic_flowcell, sequencing, sequencing_run.flowcell and library (080, 093, 094).';
COMMENT ON FUNCTION public.refresh_assembly_runs(text[], text[]) IS
  'Re-derive mito_assembly_run and ref_assembly_run for the assemblies of the OGs given and the links of the '
  'sequencing rows given. Mito: the rule of v3.sync_mito() (055); a link it no longer gives is removed. Ref: '
  'PacBio links are the runs of the assembly''s read set (093); ONT links the OG''s non-failed ONT rows of its '
  'seq_date (069); Hi-C links the complete rows of v_ref_assembly_hic_rule (094); a link its row can no longer '
  'have, a PacBio link outside the read set and a Hi-C link the rule does not give are removed. Called by '
  'triggers on mito_assembly, ref_assembly, ref_read_set_run, ref_assembly_hic_flowcell, sequencing, '
  'sequencing_run and library. 080, 093, 094.';
COMMENT ON TABLE public.ref_assembly_hic_flowcell IS
  'The flowcells an assembly''s Hi-C reads came from: the evidence its Hi-C links are derived from '
  '(v_ref_assembly_hic_rule). Writer: set_ref_assembly_hic_flowcells(), called by ref-genomes '
  '05b_push_hic_runs_to_sqldb.py with the flowcells in the assembly''s Hi-C BAM. Backfilled from the Acacia '
  'BAMs (094).';
COMMENT ON COLUMN public.ref_assembly_hic_flowcell.assembly_id IS 'The assembly (ref_assembly).';
COMMENT ON COLUMN public.ref_assembly_hic_flowcell.flowcell IS
  'A flowcell barcode from its Hi-C BAM''s read names; sequencing_run.flowcell names the run.';
COMMENT ON COLUMN public.ref_assembly_hic_flowcell.bam_records IS
  'How many of the BAM records sampled (its first ~4 MB, ~50,000 records) are from this flowcell. NULL for omnic.';
COMMENT ON COLUMN public.ref_assembly_hic_flowcell.source IS
  'bam: read from its Hi-C BAM. omnic: no BAM; the flowcells of the one set of runs its OMNIC read-pair total '
  'fits (094, OG863 v250331.hic1).';
COMMENT ON COLUMN public.ref_assembly_hic_flowcell.loaded_at IS 'When the row was written or last changed.';
COMMENT ON VIEW public.v_ref_assembly_hic_rule IS
  'For each assembly flowcell (ref_assembly_hic_flowcell): its run (sequencing_run.flowcell) and the OG''s '
  'non-failed Hi-C sequencing rows on it, one row each; sequencing_id NULL where none. complete: every '
  'flowcell of the assembly resolves. refresh_assembly_runs() links the complete rows. 094.';
COMMENT ON COLUMN public.v_ref_assembly_hic_rule.assembly_id IS 'ref_assembly_hic_flowcell.assembly_id.';
COMMENT ON COLUMN public.v_ref_assembly_hic_rule.og_id IS 'The assembly''s OG.';
COMMENT ON COLUMN public.v_ref_assembly_hic_rule.flowcell IS 'ref_assembly_hic_flowcell.flowcell.';
COMMENT ON COLUMN public.v_ref_assembly_hic_rule.run_id IS 'The run with that flowcell; NULL if none.';
COMMENT ON COLUMN public.v_ref_assembly_hic_rule.sequencing_id IS
  'A non-failed Hi-C sequencing row of the OG on that run; NULL if none.';
COMMENT ON COLUMN public.v_ref_assembly_hic_rule.complete IS 'Every flowcell of the assembly has a sequencing_id.';
COMMENT ON FUNCTION public.set_ref_assembly_hic_flowcells(bigint, text[], integer[], text) IS
  'Replace an assembly''s Hi-C flowcells (ref_assembly_hic_flowcell), which re-derives its Hi-C links, and '
  'return what does not resolve (a flowcell no run has; a run with no non-failed Hi-C row of the OG): the '
  'assembly is then not linked until it does. Clears its ref_assembly_hic_unlinked row when all resolve. '
  'Called by ref-genomes 05b_push_hic_runs_to_sqldb.py. 094.';
COMMENT ON FUNCTION public.ref_assembly_hic_flowcell_runs() IS
  'Re-derives the links of an assembly whose Hi-C flowcells changed (refresh_assembly_runs). 094.';
COMMENT ON FUNCTION public.sequencing_run_flowcell_runs() IS
  'Re-derives the links of the assemblies with a flowcell whose run changed (refresh_assembly_runs). 094.';
COMMENT ON TABLE public.ref_assembly_hic_unlinked IS
  'Hi-C assemblies reviewed and left with no Hi-C link, and why (094). set_ref_assembly_hic_flowcells() '
  'deletes the assembly''s row when its flowcells all resolve. Read by v_ref_assembly_hic_readiness.';
COMMENT ON COLUMN public.ref_assembly_hic_unlinked.assembly_id IS 'The assembly (ref_assembly).';
COMMENT ON COLUMN public.ref_assembly_hic_unlinked.reason IS 'Why it has no Hi-C link: what the evidence showed.';
COMMENT ON COLUMN public.ref_assembly_hic_unlinked.reviewed_on IS 'When the reason was recorded.';
COMMENT ON VIEW public.v_ref_assembly_hic_readiness IS
  'Hi-C assemblies (strategy hic) with no Hi-C run link: the flowcells that do not resolve, the reviewed '
  'reason (NULL: not yet pushed by 05b_push_hic_runs_to_sqldb.py, or pushed since the review), and the '
  'OG''s non-failed Hi-C rows to choose from. 094.';
COMMENT ON COLUMN public.v_ref_assembly_hic_readiness.assembly_id IS 'ref_assembly.assembly_id.';
COMMENT ON COLUMN public.v_ref_assembly_hic_readiness.og_id IS 'The specimen.';
COMMENT ON COLUMN public.v_ref_assembly_hic_readiness.seq_date IS 'ref_assembly.seq_date.';
COMMENT ON COLUMN public.v_ref_assembly_hic_readiness.version IS 'ref_assembly.version.';
COMMENT ON COLUMN public.v_ref_assembly_hic_readiness.unresolved IS
  'Its flowcells that do not resolve, with their run or "(no run)"; NULL when it has no flowcells.';
COMMENT ON COLUMN public.v_ref_assembly_hic_readiness.reason IS 'ref_assembly_hic_unlinked.reason; NULL where not reviewed.';
COMMENT ON COLUMN public.v_ref_assembly_hic_readiness.reviewed_on IS 'ref_assembly_hic_unlinked.reviewed_on.';
COMMENT ON COLUMN public.v_ref_assembly_hic_readiness.hic_rows_for_og IS
  'The OG''s non-failed Hi-C sequencing rows, '', ''-joined: the candidates.';

COMMIT;
