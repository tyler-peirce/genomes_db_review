-- Purpose: Create empty structural copies of lca, lca_validation, lca_raw_results, and
--   blast_filtered_lca ahead of re-running every mitogenome through the LCA/BLAST pipeline,
--   so a clean set of tables is ready to populate once the current tables are archived.
-- Review source: database_review.md "LCA tables" section; schema/current_schema.sql baseline
--   (verified against live \d output on 2026-08-04).
-- Expected impact: Adds 4 new empty tables (lca_new, lca_validation_new, lca_raw_results_new,
--   blast_filtered_lca_new). No changes to existing tables, views, or data.
-- Rollback notes: DROP TABLE lca_new, lca_validation_new, lca_raw_results_new,
--   blast_filtered_lca_new; safe at any point since these tables hold no data until the
--   (future, separate) swap-in step.
-- Verification: \d each new table and confirm 0 rows; confirm the 4 original tables and
--   dependent views (lca_pivot_view, lca_results_view, filtered_lca_view, etc.) are unaffected.
--
-- Status: Draft. Naming: swap-in of these tables to replace the live ones, and archiving of
--   the current tables, is deliberately out of scope here and will be a separate migration.

CREATE TABLE public.lca_new (
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    region text NOT NULL,
    lca_run_date text,
    species_in_lca text,
    number_unq_blast_hits integer,
    domain text,
    phylum text,
    class text,
    "order" text,
    family text,
    genus text,
    specific_epiphet text,
    species text,
    scientific_name_authorship character varying,
    taxon_rank text,
    top_taxon_id character varying,
    taxon_id_db character varying,
    top_accession_id character varying,
    accession_id_ref_db character varying,
    top_percent_query_cover real,
    top_percent_query_cover_hsp real,
    alignment_length integer,
    subject_length integer,
    sequence_length integer,
    top_confidence_score real,
    top_percent_match double precision,
    CONSTRAINT lca_new_unique UNIQUE (og_id, tech, seq_date, code, annotation, region, lca_run_date),
    CONSTRAINT fk_mitogenome_lca_new FOREIGN KEY (og_id, tech, seq_date, code)
        REFERENCES public.mitogenome_data(og_id, tech, seq_date, code)
);

CREATE TABLE public.lca_validation_new (
    og_id text NOT NULL,
    tech text NOT NULL,
    validated_species_name text,
    validator text,
    nominal_species_id_lca_comment text,
    validator_2 text,
    data_release character varying,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    seq_date text NOT NULL,
    code character varying NOT NULL,
    annotation character varying NOT NULL,
    row_created_on timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lca_validation_new_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation),
    CONSTRAINT fk_mitogenome_lca_validation_new FOREIGN KEY (og_id, tech, seq_date, code)
        REFERENCES public.mitogenome_data(og_id, tech, seq_date, code)
);

CREATE TABLE public.lca_raw_results_new (
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    sequence_region text,
    lca_run_date integer,
    domain text,
    phylum text,
    class text,
    "order" text,
    family text,
    genus text,
    specific_epiphet text,
    scientific_name text,
    scientific_name_authorship text,
    taxon_rank text,
    taxon_id character varying,
    taxon_id_db character varying,
    verbatim_identification text,
    accession_id character varying,
    accession_id_ref_db text,
    percent_match real,
    percent_query_cover real,
    percent_query_cover_hsp real,
    alignment_length integer,
    subject_length integer,
    sequence_length integer,
    confidence_score real,
    CONSTRAINT lca_raw_results_new_unique UNIQUE (og_id, tech, seq_date, code, annotation, sequence_region, lca_run_date, accession_id),
    CONSTRAINT fk_mitogenome_lca_raw_results_new FOREIGN KEY (og_id, tech, seq_date, code)
        REFERENCES public.mitogenome_data(og_id, tech, seq_date, code)
);

CREATE TABLE public.blast_filtered_lca_new (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    match_sequence_id text NOT NULL,
    taxon_id integer,
    scientific_name text,
    common_name text,
    kingdoms text,
    percent_identity double precision,
    alignment_length integer,
    query_length integer,
    subject_length integer,
    mismatch integer,
    gap_open integer,
    gaps integer,
    query_start integer,
    query_end integer,
    subject_start integer,
    subject_end integer,
    subject_title text,
    evalue double precision,
    bit_score double precision,
    query_coverage double precision,
    subject_coverage double precision,
    region text NOT NULL,
    blast_run_date text,
    CONSTRAINT blast_filtered_lca_new_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation, match_sequence_id, region)
);
