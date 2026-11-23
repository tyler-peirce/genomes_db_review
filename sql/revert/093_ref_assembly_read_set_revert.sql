-- 093_ref_assembly_read_set_revert.sql -- Undo 093: per-run HiFiAdapterFilt, ref_assembly.read_set_id,
-- read-set run links.
--
-- Restores 080's refresh_assembly_runs() and ref_assembly_runs_link(), the read sets and run links
-- 093 changed (inlined from sql/data/093_*.tsv), and the comments. Refuses if a read set 093 created
-- has since got GenomeScope or HiFiAdapterFilt rows: look at it first. Assemblies created after 093
-- keep the read sets their trigger made, without the column.

BEGIN;

DROP VIEW IF EXISTS public.v_ref_read_set_readiness;
DROP TRIGGER IF EXISTS ref_assembly_read_set_default ON public.ref_assembly;
DROP FUNCTION IF EXISTS public.ref_assembly_read_set_default();
DROP TRIGGER IF EXISTS ref_read_set_run_assembly_runs ON public.ref_read_set_run;
DROP FUNCTION IF EXISTS public.ref_read_set_run_assembly_runs();

-- 080's rule ---------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.refresh_assembly_runs(p_og_ids text[],
                                                        p_sequencing_ids text[] DEFAULT '{}')
RETURNS void
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  -- Mito: every link is derived, so drop one the rule no longer gives.
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

  -- Ref: a link may have been chosen by hand, so drop only one its row can no longer have
  -- (what ref_assembly_run_genomic_only refuses, or another OG's row).
  DELETE FROM ref_assembly_run r
   USING ref_assembly a
   WHERE a.assembly_id = r.assembly_id
     AND (a.og_id = ANY (p_og_ids) OR r.sequencing_id = ANY (p_sequencing_ids))
     AND NOT EXISTS (SELECT 1 FROM v_sequencing_browse s
                      WHERE s.sequencing_id = r.sequencing_id AND s.og_id = a.og_id
                        AND s.technology IN ('PacBio HIFI', 'PacBio', 'ONT', 'Hi-C')
                        AND s.library_type IN ('pacbio', 'ont', 'hic')
                        AND s.status IS DISTINCT FROM 'Failed');

  -- 069: a failed run produced no reads to build from.
  INSERT INTO ref_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT a.assembly_id, s.sequencing_id
    FROM ref_assembly a
    JOIN v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
   WHERE a.og_id = ANY (p_og_ids)
     AND s.technology IN ('PacBio HIFI', 'PacBio', 'ONT') AND s.library_type IN ('pacbio', 'ont')
     AND s.status IS DISTINCT FROM 'Failed'
  ON CONFLICT DO NOTHING;
END
$fn$;
COMMENT ON FUNCTION public.refresh_assembly_runs(text[], text[]) IS
  'Re-derive mito_assembly_run and ref_assembly_run for the assemblies of the OGs given and the links '
  'of the sequencing rows given: the run-link rules of v3.sync_mito() (055) and v4.sync_ref() (069). '
  'Mito links the rule no longer gives are removed; a ref link only when its row can no longer have '
  'one, so links chosen by hand stay. Called by triggers on mito_assembly, ref_assembly, sequencing '
  'and library. 080.';

CREATE OR REPLACE FUNCTION public.ref_assembly_runs_link() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  -- The ref writers' upsert sets og_id = EXCLUDED.og_id on every push; that changes nothing.
  IF TG_OP = 'INSERT'
     OR (NEW.og_id, NEW.seq_date) IS DISTINCT FROM (OLD.og_id, OLD.seq_date) THEN
    PERFORM refresh_assembly_runs(ARRAY[NEW.og_id]);
  END IF;
  RETURN NULL;
END
$fn$;
COMMENT ON FUNCTION public.ref_assembly_runs_link() IS
  'Links a new or re-keyed reference assembly to its runs (refresh_assembly_runs). 080.';
DROP TRIGGER IF EXISTS ref_assembly_runs_link ON public.ref_assembly;
CREATE TRIGGER ref_assembly_runs_link AFTER INSERT OR UPDATE OF og_id, seq_date ON public.ref_assembly
  FOR EACH ROW EXECUTE FUNCTION public.ref_assembly_runs_link();

-- Data 093 changed ---------------------------------------------------------------------------------

CREATE TEMP TABLE d_read_set (
    og_id       text NOT NULL,
    seq_date    text NOT NULL,
    action      text NOT NULL,
    read_set_id bigint,
    runs_before text[] NOT NULL,
    runs_after  text[] NOT NULL,
    PRIMARY KEY (og_id, seq_date)
) ON COMMIT DROP;
INSERT INTO d_read_set VALUES
  ('OG2126', '260511', 'new', NULL, '{}'::text[], ARRAY['OG2126E_D_SBL_PACB_260511_AMD']::text[]),
  ('OG2145', '260522', 'new', NULL, '{}'::text[], ARRAY['OG2145G_D_SBL_PACB_260522_AMD']::text[]),
  ('OG39', '250331', 'new', NULL, '{}'::text[], ARRAY['OG39H_D_SBL_PACB_241018_LA', 'OG39H_D_SBL_PACB_250331_LA']::text[]),
  ('OG5', '240116', 'new', NULL, '{}'::text[], ARRAY['OG5G_D2_SBL_PACB_240116_LAAD']::text[]),
  ('OG54', '250331', 'new', NULL, '{}'::text[], ARRAY['OG54G_D_SBL2_PACB_250331_LA', 'OG54G_D_SBL_PACB_241004_LA']::text[]),
  ('OG56', '250704', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG62', '250307', 'new', NULL, '{}'::text[], ARRAY['OG62G_D_SBL2_PACB_250307_AD']::text[]),
  ('OG637', '241031', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG647', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG657', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG673', '240417', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG683', '240821', 'new', NULL, '{}'::text[], ARRAY['OG683H_D_SBL2_PACB_240821_AD']::text[]),
  ('OG683', '241023', 'correct', 27, ARRAY['OG683H_D_SBL2_PACB_241023_AD']::text[], ARRAY['OG683H_D_SBL2_PACB_240821_AD', 'OG683H_D_SBL2_PACB_241023_AD']::text[]),
  ('OG709', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG711', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG716', '250704', 'new', NULL, '{}'::text[], ARRAY['OG716O_D_SBL_PACB_250704_AD']::text[]),
  ('OG721', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG749', '241018', 'new', NULL, '{}'::text[], ARRAY['OG749H_D_SBL_PACB_241018_LA']::text[]),
  ('OG749', '250331', 'correct', 238, ARRAY['OG749H_D_SBL_PACB_250331_LA']::text[], ARRAY['OG749H_D_SBL_PACB_241018_LA', 'OG749H_D_SBL_PACB_250331_LA']::text[]),
  ('OG756', '250717', 'new', NULL, '{}'::text[], ARRAY['OG756G_D_SBL_PACB_250704_AD', 'OG756G_D_SBL_PACB_250717_AD']::text[]),
  ('OG778', '250331', 'new', NULL, '{}'::text[], ARRAY['OG778H_D_SBL_PACB_241018_LA', 'OG778H_D_SBL_PACB_250331_LA']::text[]),
  ('OG781', '250317', 'new', NULL, '{}'::text[], ARRAY['OG781G_D_SBL_PACB_250317_AD']::text[]),
  ('OG788', '250505', 'new', NULL, '{}'::text[], ARRAY['OG788G_D_SBL_PACB_240927_LA', 'OG788G_D_SBL_PACB_250505_LA']::text[]),
  ('OG804', '250717', 'new', NULL, '{}'::text[], ARRAY['OG804G_D_SBL_PACB_250717_AD']::text[]),
  ('OG804', '260227', 'new', NULL, '{}'::text[], ARRAY['OG804G_D_SBL_PACB_260227_AMD']::text[]),
  ('OG820', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG834', '250331', 'new', NULL, '{}'::text[], ARRAY['OG834H_D2_SBL_PACB_240927_LA', 'OG834H_D2_SBL_PACB_250331_LA']::text[]),
  ('OG838', '240520', 'new', NULL, '{}'::text[], ARRAY['OG838B_D_SBL_PACB_240520_LA']::text[]),
  ('OG838', '240813', 'correct', 206, ARRAY['OG838B2_D_SBL_PACB_240813_AD', 'OG838B_D_SBL_PACB_240520_LA']::text[], ARRAY['OG838B2_D_SBL_PACB_240813_AD']::text[]),
  ('OG844', '241023', 'new', NULL, '{}'::text[], ARRAY['OG844H_D4_SBL_PACB_241023_AD', 'OG844H_D5_SBL_PACB_241023_AD']::text[]),
  ('OG863', '250331', 'new', NULL, '{}'::text[], ARRAY['OG863G_D_SBL_PACB_250331_LA']::text[]),
  ('OG866', '250505', 'new', NULL, '{}'::text[], ARRAY['OG866G_D_SBL_PACB_241023_AD', 'OG866G_D_SBL_PACB_250505_LA']::text[]),
  ('OG869', '250307', 'new', NULL, '{}'::text[], ARRAY['OG869M_D_SBL_PACB_250307_AD']::text[])
;
CREATE TEMP TABLE d_link (
    change        text NOT NULL CHECK (change IN ('added', 'removed')),
    assembly_id   bigint NOT NULL,
    sequencing_id text NOT NULL,
    PRIMARY KEY (assembly_id, sequencing_id)
) ON COMMIT DROP;
INSERT INTO d_link (assembly_id, sequencing_id, change)
SELECT v.*, 'added' FROM (VALUES
  (3, 'OG781G_D_SBL_PACB_250317_AD'),
  (34, 'OG819H_D_SBL_PACB_250717_AD'),
  (43, 'OG848U_D_SBL2_PACB_241127_AD'),
  (54, 'OG749H_D_SBL_PACB_241018_LA'),
  (59, 'OG767G_D_SBL_PACB_241004_LA'),
  (73, 'OG866G_D_SBL_PACB_241023_AD'),
  (79, 'OG778H_D_SBL_PACB_241018_LA'),
  (85, 'OG13G_D_SBL_PACB_230209_LP'),
  (88, 'OG845H_D2_SBL_PACB_241018_LA'),
  (91, 'OG6G_D_SBL2_PACB_230628_AD'),
  (92, 'OG762H_D_SBL2_PACB_241018_LA'),
  (94, 'OG750G_D_SBL_PACB_241004_LA'),
  (104, 'OG804G_D_SBL_PACB_250717_AD'),
  (105, 'OG88G_D_SBL_PACB_230724_AD'),
  (108, 'OG759H_D_SBL_PACB_240520_LA'),
  (110, 'OG14G_D_SBL_PACB_230209_LP'),
  (113, 'OG13G_D_SBL_PACB_230209_LP'),
  (114, 'OG683H_D_SBL2_PACB_240821_AD'),
  (114, 'OG683H_D_SBL2_PACB_241023_AD'),
  (118, 'OG701H_D_SBL2_PACB_240427_LA'),
  (125, 'OG61W_D_SBL_PACB_250317_AD'),
  (126, 'OG820G_D_SBL_PACB_240501_AD'),
  (136, 'OG683H_D_SBL2_PACB_240821_AD'),
  (136, 'OG683H_D_SBL2_PACB_241023_AD'),
  (156, 'OG866G_D_SBL_PACB_241023_AD'),
  (164, 'OG2G_D_SBL_PACB_230413_AD'),
  (170, 'OG767G_D_SBL_PACB_241004_LA'),
  (173, 'OG704H_D_SBL2_PACB_240417_LA'),
  (175, 'OG788G_D_SBL_PACB_240927_LA'),
  (177, 'OG2126E_D_SBL_PACB_260511_AMD'),
  (182, 'OG39H_D_SBL_PACB_241018_LA'),
  (190, 'OG73W_D_SBL_PACB_250307_AD'),
  (192, 'OG749H_D_SBL_PACB_241018_LA'),
  (199, 'OG61W_D_SBL_PACB_250317_AD'),
  (210, 'OG5G_D_SBL_PACB_230609_AD'),
  (218, 'OG2145G_D_SBL_PACB_260522_AMD'),
  (229, 'OG113G_D_SBL_PACB_231027_ADLA'),
  (239, 'OG54G_D_SBL_PACB_241004_LA'),
  (241, 'OG637B_D3_SBL2_PACB_240206_AD'),
  (241, 'OG637B_D3_SBL_PACB_240206_AD'),
  (242, 'OG12G_D_SBL_PACB_230512_AD'),
  (259, 'OG6G_D_SBL2_PACB_230628_AD'),
  (266, 'OG637B_D3_SBL2_PACB_240206_AD'),
  (266, 'OG637B_D3_SBL_PACB_240206_AD'),
  (268, 'OG756G_D_SBL_PACB_250717_AD'),
  (270, 'OG64W_D_SBL_PACB_250307_AD'),
  (274, 'OG54G_D_SBL_PACB_241004_LA'),
  (282, 'OG39H_D_SBL_PACB_241018_LA'),
  (285, 'OG756G_D_SBL_PACB_250717_AD'),
  (286, 'OG804G_D_SBL_PACB_250717_AD'),
  (290, 'OG820G_D_SBL_PACB_240501_AD'),
  (293, 'OG104M_D_SBL2_PACB_241127_AD'),
  (300, 'OG95H_D_SBL_PACB_230525_AD'),
  (312, 'OG799H_D2_SBL_PACB_241018_LA'),
  (314, 'OG645H_D_SBL_PACB_240427_LA'),
  (324, 'OG12G_D_SBL_PACB_230512_AD'),
  (331, 'OG657H_D_SBL_PACB_240501_AD'),
  (338, 'OG804G_D_SBL_PACB_250717_AD'),
  (351, 'OG799H_D2_SBL_PACB_241018_LA'),
  (357, 'OG794G_D_SBL_PACB_250307_AD'),
  (363, 'OG16G_D_SBL_PACB_240427_LA'),
  (373, 'OG16G_D_SBL_PACB_240427_LA'),
  (379, 'OG845H_D2_SBL_PACB_241018_LA'),
  (381, 'OG649H_D2_SBL2_PACB_240427_LA'),
  (382, 'OG645H_D_SBL_PACB_240427_LA'),
  (387, 'OG781G_D_SBL_PACB_250317_AD'),
  (395, 'OG657H_D_SBL_PACB_240501_AD'),
  (398, 'OG701H_D_SBL2_PACB_240427_LA'),
  (411, 'OG759H_D_SBL_PACB_240520_LA'),
  (414, 'OG778H_D_SBL_PACB_241018_LA'),
  (419, 'OG113G_D_SBL_PACB_231027_ADLA'),
  (422, 'OG659H_D_SBL2_PACB_240427_LA'),
  (429, 'OG834H_D2_SBL_PACB_240927_LA'),
  (430, 'OG13G_D_SBL_PACB_230209_LP'),
  (433, 'OG64W_D_SBL_PACB_250307_AD'),
  (434, 'OG659H_D_SBL2_PACB_240427_LA'),
  (443, 'OG834H_D2_SBL_PACB_240927_LA'),
  (448, 'OG649H_D2_SBL2_PACB_240427_LA'),
  (449, 'OG88G_D_SBL_PACB_230724_AD'),
  (451, 'OG788G_D_SBL_PACB_240927_LA'),
  (457, 'OG95H_D_SBL_PACB_230525_AD'),
  (458, 'OG762H_D_SBL2_PACB_241018_LA'),
  (9849, 'OG2089G_D_SBL_PACB_260227_AMD'),
  (9852, 'OG2093E_D_SBL_PACB_260227_AMD'),
  (9861, 'OG2126E_D_SBL_PACB_260511_AMD'),
  (9864, 'OG2128E_D_SBL_PACB_260603_AMD'),
  (10088, 'OG2145G_D_SBL_PACB_260522_AMD')
) AS v (assembly_id, sequencing_id)
UNION ALL
SELECT v.*, 'removed' FROM (VALUES
  (11, 'OG836B_D_SBL2_PACB_240520_LA'),
  (59, 'OG767G_D_SBL_PACB_250331_LA'),
  (148, 'OG90H_D2_SBL3_PACB_240821_AD'),
  (170, 'OG767G_D_SBL_PACB_250331_LA'),
  (295, 'OG90H_D2_SBL3_PACB_240821_AD'),
  (315, 'OG836B_D_SBL2_PACB_240520_LA'),
  (357, 'OG794G_D_SBL_PACB_250317_AD')
) AS v (assembly_id, sequencing_id);

DO $revert$
DECLARE
  bad record;
BEGIN
  SELECT d.og_id, d.seq_date INTO bad
    FROM d_read_set d JOIN ref_read_set rs USING (og_id, seq_date)
   WHERE d.action = 'new'
     AND (EXISTS (SELECT 1 FROM ref_genomescope g WHERE g.read_set_id = rs.read_set_id)
          OR EXISTS (SELECT 1 FROM ref_hifi_adapter_filter f WHERE f.read_set_id = rs.read_set_id))
   LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION '093 revert: read set % % (made by 093) now has GenomeScope or HiFiAdapterFilt rows',
      bad.og_id, bad.seq_date;
  END IF;

  -- Run links as before 093.
  DELETE FROM ref_assembly_run r USING d_link l
   WHERE l.change = 'added' AND r.assembly_id = l.assembly_id AND r.sequencing_id = l.sequencing_id;
  INSERT INTO ref_assembly_run (assembly_id, sequencing_id)
  SELECT assembly_id, sequencing_id FROM d_link WHERE change = 'removed'
  ON CONFLICT DO NOTHING;

  -- Corrected read sets get their runs back.
  DELETE FROM ref_read_set_run r USING d_read_set d
   WHERE d.action = 'correct' AND r.read_set_id = d.read_set_id AND r.sequencing_id <> ALL (d.runs_before);
  INSERT INTO ref_read_set_run (read_set_id, sequencing_id)
  SELECT d.read_set_id, unnest(d.runs_before) FROM d_read_set d WHERE d.action = 'correct'
  ON CONFLICT DO NOTHING;

  ALTER TABLE ref_assembly DROP COLUMN IF EXISTS read_set_id;

  DELETE FROM ref_read_set rs USING d_read_set d
   WHERE d.action = 'new' AND rs.og_id = d.og_id AND rs.seq_date = d.seq_date;
END
$revert$;

DROP TABLE IF EXISTS public.ref_hifi_adapter_filter_run;
DROP FUNCTION IF EXISTS public.ref_hifi_adapter_filter_run_pacbio_only();

COMMENT ON TABLE public.ref_hifi_adapter_filter IS
  'HiFiAdapterFilt: reads removed as adapter-contaminated, per HiFi read set (ref_read_set). Written by 0a_push_hifiadapt_results_to_sqldb.py (ref repo).';
COMMENT ON TABLE public.ref_read_set IS
  'A HiFi read set: the PacBio reads one reference-pipeline run took in for an OG (the samplesheet''s date). seq_date is the latest seq_date of its sequencing rows, not the samplesheet date. NULL = unknown (before RG, or a public.raw_qc state no dated read set matches). Migration 062.';
COMMENT ON TABLE public.ref_assembly_run IS
  'The sequencing rows an assembly was built from: PacBio/ONT DNA, and Hi-C once writers record it '
  '(trigger). Links to the OG''s non-failed PacBio/ONT rows of the assembly''s seq_date are kept current '
  'by refresh_assembly_runs() from triggers on ref_assembly, sequencing and library (080). A link '
  'chosen by hand stays until its row can no longer have one.';
COMMENT ON VIEW public.v_ref_assembly_run_readiness IS
  'Assemblies with no run link, and the OG''s PacBio/ONT DNA rows to choose from. Their seq_date '
  'matches no run date (RG.0 §1.5), so refresh_assembly_runs() (080) cannot derive one: link them '
  'by hand, or fix the date.';

COMMIT;
