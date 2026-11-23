-- 089_drop_raw_data_specimen_view_revert.sql -- undo 089: restore raw_data and the
-- ena_specimen_accessions table (structure, comments, grants and rows) and the comments 089 changed.
--
-- Run from the repository root:  psql -f sql/revert/089_drop_raw_data_specimen_view_revert.sql
-- then delete 089's ledger row. The rows come from archive/dropped_261123/ through
-- \copy ... FROM PROGRAM 'gunzip -c ...', which reads the files on the client.
-- The final check compares each table's row fingerprint with the one 089's guard checked.

\set ON_ERROR_STOP on
BEGIN;

-- raw_data ---------------------------------------------------------------------------------------

CREATE TABLE public.raw_data (
    og_id text,
    run_id text NOT NULL,
    lane_id text NOT NULL,
    filename text NOT NULL,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED
);
ALTER TABLE public.raw_data OWNER TO postgres;
CREATE TEMP TABLE raw_data_089 (og_id text, run_id text, lane_id text, filename text, og_num text) ON COMMIT DROP;
\copy raw_data_089 FROM PROGRAM 'gunzip -c archive/dropped_261123/raw_data.csv.gz' WITH (FORMAT csv, HEADER true)
INSERT INTO public.raw_data (og_id, run_id, lane_id, filename) SELECT og_id, run_id, lane_id, filename FROM raw_data_089;
ALTER TABLE ONLY public.raw_data ADD CONSTRAINT raw_data_pkey PRIMARY KEY (run_id, lane_id, filename);
CREATE INDEX raw_data_og_id_idx ON public.raw_data USING btree (og_id);
ALTER TABLE ONLY public.raw_data ADD CONSTRAINT raw_data_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);
ALTER TABLE ONLY public.raw_data ADD CONSTRAINT raw_data_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.sequencing_run(run_id);
GRANT SELECT ON TABLE public.raw_data TO readonly;
COMMENT ON TABLE public.raw_data IS 'Raw sequencing files: one row per FASTQ file of an OG on a run and lane. No current writer found in the pipeline repositories; took no new rows Jul-Nov 2026 (§11 Q13). FK run_id to sequencing_run (075).';
COMMENT ON COLUMN public.raw_data.og_id IS 'The sample (FK to sample). NULL on 30 rows.';
COMMENT ON COLUMN public.raw_data.run_id IS 'The run (FK to sequencing_run).';
COMMENT ON COLUMN public.raw_data.lane_id IS 'Library and lane as the sequencer named them, e.g. F15-0238_L1.';
COMMENT ON COLUMN public.raw_data.filename IS 'The FASTQ file name.';
COMMENT ON COLUMN public.raw_data.og_num IS 'Numeric part of og_id, for sorting. Generated.';

CREATE OR REPLACE VIEW public.v_sequencing_run_fk_readiness AS
 SELECT 'sequencing'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
   FROM public.sequencing c
     LEFT JOIN public.sequencing_run r ON r.run_id = c.run_id
UNION ALL
 SELECT 'raw_data'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
   FROM public.raw_data c
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
COMMENT ON VIEW public.v_sequencing_run_fk_readiness IS 'Per table with an FK to sequencing_run (sequencing, raw_data: 075; hifi_read_qc, hic_read_qc: 077): rows whose run is not in sequencing_run. The FKs make this 0; kept as the check.';
COMMENT ON TABLE public.sequencing_run IS 'One sequencing run, derived from sequencing.run_id. Kept current by the sequencing_run_ensure and sequencing_run_refresh_* triggers on sequencing (075); sequencing, raw_data, rna_qc_kinnex (075), hifi_read_qc and hic_read_qc (077) have FKs to it.';

-- ena_specimen_accessions ------------------------------------------------------------------------

ALTER TABLE public.ena_related_assemblies DROP CONSTRAINT IF EXISTS ena_related_assemblies_og_id_fkey;
DROP VIEW IF EXISTS public.ena_specimen_accessions;
CREATE TABLE public.ena_specimen_accessions (
    og_id text NOT NULL,
    og_numeric integer NOT NULL,
    ena_biosample_accession text,
    accession_source text,
    verified_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ena_specimen_biosample_check CHECK (((ena_biosample_accession IS NULL) OR (ena_biosample_accession ~ '^SAM(EA|N|D)[0-9]+$'::text))),
    CONSTRAINT ena_specimen_og_id_check CHECK ((og_id ~ '^OG[0-9]+$'::text)),
    CONSTRAINT ena_specimen_og_numeric_check CHECK (((og_numeric >= 0) AND (og_numeric <= 999999))),
    CONSTRAINT ena_specimen_og_numeric_matches_check CHECK ((og_numeric = (SUBSTRING(og_id FROM 3))::integer))
);
ALTER TABLE public.ena_specimen_accessions OWNER TO postgres;
\copy public.ena_specimen_accessions FROM PROGRAM 'gunzip -c archive/dropped_261123/ena_specimen_accessions.csv.gz' WITH (FORMAT csv, HEADER true)
ALTER TABLE ONLY public.ena_specimen_accessions ADD CONSTRAINT ena_specimen_accessions_ena_biosample_accession_key UNIQUE (ena_biosample_accession);
ALTER TABLE ONLY public.ena_specimen_accessions ADD CONSTRAINT ena_specimen_accessions_og_numeric_key UNIQUE (og_numeric);
ALTER TABLE ONLY public.ena_specimen_accessions ADD CONSTRAINT ena_specimen_accessions_pkey PRIMARY KEY (og_id);
ALTER TABLE ONLY public.ena_specimen_accessions ADD CONSTRAINT ena_specimen_accessions_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);
ALTER TABLE ONLY public.ena_related_assemblies ADD CONSTRAINT ena_related_assemblies_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.ena_specimen_accessions(og_id);
GRANT SELECT ON TABLE public.ena_specimen_accessions TO readonly;
COMMENT ON TABLE public.ena_specimen_accessions IS 'Specimen registry for ENA: one row per OG with an ENA-referenceable BioSample, where one is known. Filled by the mito pipeline bin/backfill_ena_specimen_accessions.py; 1 of 2,848 rows has an accession. Whether to keep it or make it a view over sample is open (§11 Q14).';
COMMENT ON COLUMN public.ena_specimen_accessions.og_id IS 'The sample (FK to sample).';
COMMENT ON COLUMN public.ena_specimen_accessions.og_numeric IS 'Numeric part of og_id (checked to match).';
COMMENT ON COLUMN public.ena_specimen_accessions.ena_biosample_accession IS 'SAMEA/SAMN/SAMD accession. A SAMN is NCBI-registered and webin-cli cannot resolve it (007).';
COMMENT ON COLUMN public.ena_specimen_accessions.accession_source IS 'Where the accession came from, e.g. sample,draft_genomes.';
COMMENT ON COLUMN public.ena_specimen_accessions.verified_at IS 'When the accession was last checked.';
COMMENT ON COLUMN public.ena_specimen_accessions.updated_at IS 'When the row was last written.';
COMMENT ON COLUMN public.ena_related_assemblies.og_id IS 'The sample.';

-- Comments 089 changed ---------------------------------------------------------------------------

COMMENT ON TABLE public.sequencing IS 'One row per sequencing record. Source: the 5.Sequencing sheet (import_v2.py). Each row names one library (library_tube_id) and one run (run_id). Grain undecided: a library on a run in most rows, but see §11 Q5.';
COMMENT ON COLUMN public.ena_submissions.ena_sample_accession IS 'ENA sample (ERS...). Missing on 172 of 539 (§11 Q12).';
COMMENT ON COLUMN public.ena_submissions.ena_sequence_accession IS 'Empty on every row: genome-context submissions return analysis and assembly accessions, not sequence ones (§11 Q12).';
COMMENT ON COLUMN public.sample.nominal_species_id IS 'The species name the specimen arrived as. 1.MetaData "Nominal Species ID". Free text, not validated against species on import (backlog item 8); the LCA validates it later (mito_lca_validation). Meaning undecided: §11 Q1 (which species table it should match).';
COMMENT ON TABLE public.species IS 'Species names with their lineage, one row per name. Loaded from NCBI rankedlineage.dmp by OceanOmics-OceanGenomes-Draft-Genomes scripts/taxonomy/load_taxonomy.py (insert-only, existing rows never touched), plus earlier AFD-sourced rows. The draft pipeline routes BUSCO lineages on class. One of several species sources: which is authoritative is undecided (§11 Q1).';

DO $check$
DECLARE fp text;
BEGIN
  SELECT md5(string_agg(to_jsonb(t)::text, E'\n' ORDER BY run_id, lane_id, filename)) INTO fp FROM public.raw_data t;
  IF fp IS DISTINCT FROM '5cee43e79ea3960a70eb7de0e7043cae' THEN
    RAISE EXCEPTION '089 revert: raw_data fingerprint % is not the archived one', fp;
  END IF;
  SELECT md5(string_agg(to_jsonb(t)::text, E'\n' ORDER BY og_id)) INTO fp FROM public.ena_specimen_accessions t;
  IF fp IS DISTINCT FROM 'bb17327c6b962bf76dd898aa5777d2b0' THEN
    RAISE EXCEPTION '089 revert: ena_specimen_accessions fingerprint % is not the archived one', fp;
  END IF;
END
$check$;

COMMIT;
