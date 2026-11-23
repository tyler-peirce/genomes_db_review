-- 094_ref_assembly_hic_runs_revert.sql -- Undo 094: Hi-C assembly links and their evidence,
-- sequencing_run.flowcell.
--
-- Removes every Hi-C link in ref_assembly_run (there were none before 094; links derived since go
-- too), the assembly flowcells, the reviewed exceptions, the views, triggers and functions, and the
-- flowcell column, and restores 093's refresh_assembly_runs() and comments (inlined from
-- sql/093_ref_assembly_read_set.sql). Writers deployed for 094 (push_hic_yield.py's flowcell, ref-genomes
-- 05b) fail loudly against a reverted database: revert them first.

BEGIN;

DROP VIEW IF EXISTS public.v_ref_assembly_hic_readiness;
DROP FUNCTION IF EXISTS public.set_ref_assembly_hic_flowcells(bigint, text[], integer[], text);
DROP TRIGGER IF EXISTS sequencing_run_flowcell_runs ON public.sequencing_run;
DROP FUNCTION IF EXISTS public.sequencing_run_flowcell_runs();
DROP TRIGGER IF EXISTS ref_assembly_hic_flowcell_runs ON public.ref_assembly_hic_flowcell;
DROP FUNCTION IF EXISTS public.ref_assembly_hic_flowcell_runs();

-- 093's rule ---------------------------------------------------------------------------------------

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
  -- ref_assembly_run_genomic_only refuses), and a PacBio link that is not a run of the assembly's
  -- read set (093). ONT and Hi-C links chosen by hand stay.
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
                               WHERE rr.read_set_id = a.read_set_id AND rr.sequencing_id = r.sequencing_id)));

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
END
$fn$;
COMMENT ON FUNCTION public.refresh_assembly_runs(text[], text[]) IS
  'Re-derive mito_assembly_run and ref_assembly_run for the assemblies of the OGs given and the links '
  'of the sequencing rows given. Mito: the rule of v3.sync_mito() (055); a link it no longer gives is '
  'removed. Ref: PacBio links are the runs of the assembly''s read set (093); ONT links the OG''s '
  'non-failed ONT rows of its seq_date (069); a link its row can no longer have is removed, and Hi-C '
  'links chosen by hand stay. Called by triggers on mito_assembly, ref_assembly, ref_read_set_run, '
  'sequencing and library. 080, 093.';

DROP VIEW IF EXISTS public.v_ref_assembly_hic_rule;
DROP TABLE IF EXISTS public.ref_assembly_hic_flowcell;
DROP TABLE IF EXISTS public.ref_assembly_hic_unlinked;

DELETE FROM public.ref_assembly_run l
 USING public.v_sequencing_browse s
 WHERE s.sequencing_id = l.sequencing_id AND s.technology = 'Hi-C' AND s.library_type = 'hic';

DROP INDEX IF EXISTS public.sequencing_run_flowcell_key;
ALTER TABLE public.sequencing_run DROP CONSTRAINT IF EXISTS sequencing_run_flowcell_check;
ALTER TABLE public.sequencing_run DROP COLUMN IF EXISTS flowcell;

COMMENT ON TABLE public.ref_assembly_run IS
  'The sequencing rows an assembly was built from: PacBio (the runs of its read set, 093), ONT (the OG''s '
  'non-failed ONT rows of its seq_date) and Hi-C (by hand, until writers record it). Kept current '
  'by refresh_assembly_runs() from triggers on ref_assembly, ref_read_set_run, sequencing and library '
  '(080, 093).';

COMMIT;
