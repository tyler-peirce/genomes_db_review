-- 089_drop_raw_data_specimen_view.sql -- drop raw_data; replace ena_specimen_accessions with a
-- view over sample; answer §11 Q4, Q5, Q12, Q13 and Q14 in the comments that pointed at them.
--
-- Why. Owner, 2026-11-23, on the evidence in database_review.md §11 (checked on live, read-only):
--   - raw_data (Q13): drop it, because nobody maintains it. 8,010 FASTQ file names (og_id, run_id,
--     lane_id, filename) for 28 runs, the last NOVA_250520_AD; 194 later runs are not in it.
--     No writer at the remote default branch of any repository on this host (OceanOmics-Database
--     45abf6d, Mitogenomes 85ffa32, Draft-Genomes 9bfec88, ref-genomes fb128b3, post-curation
--     2d700cf, ref_gen_automation fc75e7f, ref_genomes_hic_automation 4180383, ENA-draft f5e403e,
--     ENA-mito 3d9d35a, ENA-ref 2551f18). Only OceanOmics-Database SS/create_database.py, the
--     retired creator, names it. No inserts since the statistics reset on 2026-05-11. Its one
--     reader is v_sequencing_run_fk_readiness, recreated below without it. The read-set
--     inventories on Acacia and S3 now list raw reads. OceanGenom_Web's source is not on this
--     host; the web login has no grant on raw_data, so the app cannot read it.
--   - ena_specimen_accessions (Q14): make it a view over sample. Last written 2026-08-13 by a
--     one-off backfill (Mitogenomes bin/backfill_ena_specimen_accessions.py); 1 of 2,848 rows had
--     an accession, and that one (OG111 SAMEA132129018) disagrees with sample.ncbi_biosample_id
--     (SAMEA123401071); 874 samples had no row. Every one of the 539 ENA submissions used the
--     BioSample in sample.ncbi_biosample_id, and the mito pipeline's metadata step has a test
--     asserting it does not read this table. Its only reader is a count in Mitogenomes
--     bin/audit_ena_readiness.py, which keeps working against the view.
--   - ena_related_assemblies (planned, 0 rows, no writer) had its og_id FK on the table. It now
--     references sample(og_id), the same OGs by the same key.
--
-- Comments. Q4 and Q5: a sequencing row is one library on one run, with no exceptions (4,677
-- rows, 4,677 distinct pairs; PacBio cells share the row). Q12: the missing ERS accessions are
-- expected where a SAMN BioSample was reused (166 of 172). sample.nominal_species_id and species
-- still pointed at the species question that 2026-11-13 closed. Not changed, by owner decision:
-- sample.workflow and sample.priority (Q2 is left to the colleague who owns OceanGenom_Web) and
-- sample.assigned_species. No UNIQUE (library_tube_id, run_id) on sequencing (owner).
--
-- Rejected:
--   - Keeping raw_data frozen with a comment: it would still read as a source of raw files.
--   - Dropping ena_specimen_accessions outright: it would break the audit script in a pipeline repo
--     this project does not own, for no gain.
--   - Writing the backfill's lone OG111 accession into sample: it was never submitted and nothing
--     shows it is right. It is kept in the archive.
--
-- Archive: archive/dropped_261123/ has both tables as gzipped CSV, their DDL and SHA256SUMS. The
-- guards below check the same row fingerprints, so this refuses to drop anything that changed
-- after the export.
-- Revert: sql/revert/089_drop_raw_data_specimen_view_revert.sql (structure, comments, grants and
-- rows from the archive; run from the repository root).
-- Replay: guarded on to_regclass and relkind, so a replay changes nothing.

BEGIN;

DO $guard$
DECLARE
  n bigint;
  fp text;
BEGIN
  IF to_regclass('public.raw_data') IS NOT NULL THEN
    SELECT count(*), md5(string_agg(to_jsonb(t)::text, E'\n' ORDER BY run_id, lane_id, filename))
      INTO n, fp FROM public.raw_data t;
    IF n <> 8010 OR fp IS DISTINCT FROM '5cee43e79ea3960a70eb7de0e7043cae' THEN
      RAISE EXCEPTION '089: public.raw_data has changed since the 2026-11-23 export (% rows, md5 %). '
        'Re-export it to archive/ before dropping it.', n, fp;
    END IF;
  END IF;

  IF (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.ena_specimen_accessions')) = 'r' THEN
    SELECT count(*), md5(string_agg(to_jsonb(t)::text, E'\n' ORDER BY og_id))
      INTO n, fp FROM public.ena_specimen_accessions t;
    IF n <> 2848 OR fp IS DISTINCT FROM 'bb17327c6b962bf76dd898aa5777d2b0' THEN
      RAISE EXCEPTION '089: public.ena_specimen_accessions has changed since the 2026-11-23 export '
        '(% rows, md5 %). Find out who writes it, and re-export it.', n, fp;
    END IF;
    IF EXISTS (SELECT 1 FROM public.ena_related_assemblies) THEN
      RAISE EXCEPTION '089: ena_related_assemblies has rows; it was empty when this was written.';
    END IF;
  END IF;
END
$guard$;

-- raw_data and its one reader --------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_sequencing_run_fk_readiness AS
 SELECT 'sequencing'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
   FROM public.sequencing c
     LEFT JOIN public.sequencing_run r ON r.run_id = c.run_id
UNION ALL
 SELECT 'hifi_read_qc'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
   FROM public.hifi_read_qc c
     LEFT JOIN public.sequencing_run r ON r.run_id = c.run_id
UNION ALL
 SELECT 'hic_read_qc'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
   FROM public.hic_read_qc c
     LEFT JOIN public.sequencing_run r ON r.run_id = c.run_id;

COMMENT ON VIEW public.v_sequencing_run_fk_readiness IS
  'Per table with an FK to sequencing_run (sequencing: 075; hifi_read_qc, hic_read_qc: 077): rows whose run is not in sequencing_run. The FKs make this 0; kept as the check. raw_data was dropped by 089.';

DROP TABLE IF EXISTS public.raw_data;

COMMENT ON TABLE public.sequencing_run IS
  'One sequencing run, derived from sequencing.run_id. Kept current by the sequencing_run_ensure and sequencing_run_refresh_* triggers on sequencing (075); sequencing, rna_qc_kinnex (075), hifi_read_qc and hic_read_qc (077) have FKs to it.';

-- ena_specimen_accessions: table to view ---------------------------------------------------------

DO $swap$
BEGIN
  IF (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.ena_specimen_accessions')) = 'r' THEN
    ALTER TABLE public.ena_related_assemblies DROP CONSTRAINT IF EXISTS ena_related_assemblies_og_id_fkey;
    DROP TABLE public.ena_specimen_accessions;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'public.ena_related_assemblies'::regclass
                   AND conname = 'ena_related_assemblies_og_id_fkey') THEN
    ALTER TABLE public.ena_related_assemblies
      ADD CONSTRAINT ena_related_assemblies_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);
  END IF;
END
$swap$;

CREATE OR REPLACE VIEW public.ena_specimen_accessions AS
SELECT s.og_id,
       s.og_num                                     AS og_numeric,
       b.accession                                  AS ena_biosample_accession,
       CASE WHEN b.accession IS NOT NULL THEN 'sample.ncbi_biosample_id' END AS accession_source,
       NULL::timestamptz                            AS verified_at,
       NULL::timestamptz                            AS updated_at
  FROM public.sample s
  CROSS JOIN LATERAL (
    SELECT NULLIF(btrim(s.ncbi_biosample_id), '') AS accession
  ) b0
  CROSS JOIN LATERAL (
    SELECT CASE WHEN b0.accession ~ '^SAM(EA|N|D)[0-9]+$' THEN b0.accession END AS accession
  ) b
 WHERE s.og_id ~ '^OG[0-9]+$';

GRANT SELECT ON public.ena_specimen_accessions TO readonly;

COMMENT ON VIEW public.ena_specimen_accessions IS
  'Compatibility view (089): one row per sample, with its BioSample from sample.ncbi_biosample_id, the accession every ENA submission used. Was a table filled once, in August 2026, by the mito pipeline''s backfill_ena_specimen_accessions.py; archived in archive/dropped_261123/. Read by Mitogenomes bin/audit_ena_readiness.py. Not a write path: write sample.ncbi_biosample_id.';
COMMENT ON COLUMN public.ena_specimen_accessions.og_id IS 'The sample.';
COMMENT ON COLUMN public.ena_specimen_accessions.og_numeric IS 'Numeric part of og_id (sample.og_num).';
COMMENT ON COLUMN public.ena_specimen_accessions.ena_biosample_accession IS 'sample.ncbi_biosample_id when it is a SAMEA/SAMN/SAMD accession, else NULL. A SAMN is NCBI-registered and webin-cli cannot resolve it (007).';
COMMENT ON COLUMN public.ena_specimen_accessions.accession_source IS 'Always sample.ncbi_biosample_id where there is an accession.';
COMMENT ON COLUMN public.ena_specimen_accessions.verified_at IS 'Always NULL; kept so the table''s readers see the same columns.';
COMMENT ON COLUMN public.ena_specimen_accessions.updated_at IS 'Always NULL; kept so the table''s readers see the same columns.';

COMMENT ON COLUMN public.ena_related_assemblies.og_id IS 'The sample (FK to sample; to ena_specimen_accessions before 089).';

-- Answers in the comments that pointed at §11 ----------------------------------------------------

COMMENT ON TABLE public.sequencing IS
  'One row per library on a run. Source: the 5.Sequencing sheet (import_v2.py). Each row names one library (library_tube_id) and one run (run_id); no pair repeats (4,677 of 4,677 on 2026-11-23). PacBio SMRT cells share the row (cell_id lists them, smrt_num counts them); Illumina lanes are not rows here (hic_read_qc keeps them). §11 Q5, answered 2026-11-23.';

COMMENT ON COLUMN public.ena_submissions.ena_sample_accession IS
  'ENA sample (ERS...). Empty where the submission reused an NCBI BioSample (SAMN...), which has no ERS: 166 of the 172 empty on 2026-11-23. The other 5 reused a SAMEA sample, whose ERS exists at ENA but is not in a receipt, so it was not recorded; and OG25 ilmn 230814 carries a SAMN under biosample_source ''webin_registered''. §11 Q12.';
COMMENT ON COLUMN public.ena_submissions.ena_sequence_accession IS
  'Always empty, as expected: genome-context submissions return analysis (ERZ) and assembly (GCA) accessions, not sequence ones. §11 Q12.';

COMMENT ON COLUMN public.sample.nominal_species_id IS
  'The species name the specimen arrived as. 1.MetaData "Nominal Species ID". Free text and deliberately not validated: master_species, the name authority, is the vertebrate GoaT list and does not cover every sample (owner, 2026-11-13). The LCA checks it later (mito_lca_validation).';

COMMENT ON TABLE public.species IS
  'Species names with their lineage, one row per name. Loaded from NCBI rankedlineage.dmp by OceanOmics-OceanGenomes-Draft-Genomes scripts/taxonomy/load_taxonomy.py (insert-only, existing rows never touched), plus earlier AFD-sourced rows. The draft pipeline routes BUSCO lineages on class. Not the name authority: that is master_species (§11 Q1, 2026-11-13).';

COMMIT;
