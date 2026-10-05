-- Deploy genomes_db:create_v2_lca_tables to pg
-- requires: create_v2_lab_tables

-- Purpose: Build v2 equivalents of the LCA / mitogenome tables to the same design rules as the
--   lab tables (decision 1, §5 step 11). `lca_new` and its siblings in `public` are untouched:
--   they belong to concurrent work producing a fresh dataset and must not be modified.
--
-- Review source: docs/v2_scaffold_design_review.md decision 1, F9, §5 step 11;
--   docs/lab_key_strategy.md §6.0.
--
-- Column lists are transformed from schema/current_schema.sql rather than retyped —
--   mitogenome_data alone has ~80 columns and hand-transcription would introduce errors that
--   only surface at backfill. Three transformations were applied:
--
--   1. The generated `og_num` column is dropped from all five tables (F2). It used
--      SUBSTRING(og_id FROM 3)::integer, which raises rather than nulls on an og_id that does
--      not parse. og_num is available from v2.sample, one indexed join away.
--   2. `character varying` becomes `text` (F8).
--   3. Constraints are added rather than inherited — see below.
--
-- What is genuinely new here, beyond the two fixes above:
--   - A foreign key to v2.sample(og_id) on all five. None of the live tables has one, so
--     nothing today prevents an LCA row for a specimen that does not exist.
--   - Real primary keys on `lca` and `lca_raw_results`, which live carries only as UNIQUE
--     constraints, leaving both technically heap-addressable only.
--   - `lca_raw_results.lca_run_date` becomes `text`, matching `lca.lca_run_date`. The live
--     tables disagree — integer on one, text on the other — while both use the column in a
--     uniqueness constraint over otherwise identical key columns (F8).
--   - Indexes on every foreign key, and table comments (F7, Finding 9).
--
-- Expected impact: Additive only. Five empty tables in the `v2` schema. `public.lca_new`,
--   `public.lca`, and every other live table are untouched.

BEGIN;


CREATE TABLE v2.mitogenome_data (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    stats text,
    length integer,
    length_emma integer,
    seqlength_12s integer,
    seqlength_16s integer,
    seqlength_co1 integer,
    cds_no integer,
    trna_no integer,
    rrna_no integer,
    status text,
    genbank text,
    rrna12s integer,
    rrna16s integer,
    atp6 integer,
    atp8 integer,
    cox1 integer,
    cox2 integer,
    cox3 integer,
    cytb integer,
    nad1 integer,
    nad2 integer,
    nad3 integer,
    nad4 integer,
    nad4l integer,
    nad5 integer,
    nad6 integer,
    trna_phe integer,
    trna_val integer,
    trna_leuuag integer,
    trna_leuuaa integer,
    trna_ile integer,
    trna_met integer,
    trna_thr integer,
    trna_pro integer,
    trna_lys integer,
    trna_asp integer,
    trna_glu integer,
    trna_sergcu integer,
    trna_seruga integer,
    trna_tyr integer,
    trna_cys integer,
    trna_trp integer,
    trna_ala integer,
    trna_asn integer,
    trna_gly integer,
    trna_arg integer,
    trna_his integer,
    trna_gln integer,
    manual_curation_notes text,
    bankit text,
    genbank_accession text,
    annotation text NOT NULL,
    date_submitted_genbank date,
    avg_coverage real,
    avg_base_coverage real,
    atp6_trans integer,
    atp8_trans integer,
    cox1_trans integer,
    cox2_trans integer,
    cox3_trans integer,
    cytb_trans integer,
    nad1_trans integer,
    nad2_trans integer,
    nad3_trans integer,
    nad4_trans integer,
    nad4l_trans integer,
    nad5_trans integer,
    nad6_trans integer,
    extra_genes text,
    missing_genes text,
    order_correct text,
    passed text,

    CONSTRAINT mitogenome_data_pkey PRIMARY KEY (og_id, tech, seq_date, code),
    CONSTRAINT mitogenome_data_annotation_key UNIQUE (og_id, tech, seq_date, code, annotation),
    CONSTRAINT mitogenome_data_og_id_fkey FOREIGN KEY (og_id) REFERENCES v2.sample(og_id)
);

CREATE TABLE v2.lca (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    region text NOT NULL,
    lca_run_date text NOT NULL,
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
    scientific_name_authorship text,
    taxon_rank text,
    top_taxon_id text,
    taxon_id_db text,
    top_accession_id text,
    accession_id_ref_db text,
    top_percent_query_cover real,
    top_percent_query_cover_hsp real,
    alignment_length integer,
    subject_length integer,
    sequence_length integer,
    top_confidence_score real,
    top_percent_match double precision,

    CONSTRAINT lca_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, region, lca_run_date),
    CONSTRAINT lca_og_id_fkey FOREIGN KEY (og_id) REFERENCES v2.sample(og_id),
    CONSTRAINT lca_mitogenome_fkey FOREIGN KEY (og_id, tech, seq_date, code)
        REFERENCES v2.mitogenome_data(og_id, tech, seq_date, code)
);

CREATE TABLE v2.lca_validation (
    og_id text NOT NULL,
    tech text NOT NULL,
    validated_species_name text,
    validator text,
    nominal_species_id_lca_comment text,
    validator_2 text,
    data_release text,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    row_created_on timestamp with time zone DEFAULT now() NOT NULL,

    CONSTRAINT lca_validation_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation),
    CONSTRAINT lca_validation_og_id_fkey FOREIGN KEY (og_id) REFERENCES v2.sample(og_id),
    CONSTRAINT lca_validation_mitogenome_fkey FOREIGN KEY (og_id, tech, seq_date, code)
        REFERENCES v2.mitogenome_data(og_id, tech, seq_date, code)
);

CREATE TABLE v2.lca_raw_results (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    sequence_region text NOT NULL,
    lca_run_date text NOT NULL,
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
    taxon_id text,
    taxon_id_db text,
    verbatim_identification text,
    accession_id text NOT NULL,
    accession_id_ref_db text,
    percent_match real,
    percent_query_cover real,
    percent_query_cover_hsp real,
    alignment_length integer,
    subject_length integer,
    sequence_length integer,
    confidence_score real,

    CONSTRAINT lca_raw_results_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, sequence_region, lca_run_date, accession_id),
    CONSTRAINT lca_raw_results_og_id_fkey FOREIGN KEY (og_id) REFERENCES v2.sample(og_id),
    CONSTRAINT lca_raw_results_mitogenome_fkey FOREIGN KEY (og_id, tech, seq_date, code)
        REFERENCES v2.mitogenome_data(og_id, tech, seq_date, code)
);

CREATE TABLE v2.blast_filtered_lca (
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

    CONSTRAINT blast_filtered_lca_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, match_sequence_id, region),
    CONSTRAINT blast_filtered_lca_og_id_fkey FOREIGN KEY (og_id) REFERENCES v2.sample(og_id)
);
-- ---------------------------------------------------------------------------------------
-- Indexes on the foreign keys (F7 / database_review.md Finding 4)
-- ---------------------------------------------------------------------------------------

CREATE INDEX mitogenome_data_og_id_idx   ON v2.mitogenome_data   (og_id);
CREATE INDEX lca_og_id_idx               ON v2.lca               (og_id);
CREATE INDEX lca_mitogenome_idx          ON v2.lca               (og_id, tech, seq_date, code);
CREATE INDEX lca_validation_og_id_idx    ON v2.lca_validation    (og_id);
CREATE INDEX lca_raw_results_og_id_idx   ON v2.lca_raw_results   (og_id);
CREATE INDEX lca_raw_results_mito_idx    ON v2.lca_raw_results   (og_id, tech, seq_date, code);
CREATE INDEX blast_filtered_lca_og_id_idx ON v2.blast_filtered_lca (og_id);

-- ---------------------------------------------------------------------------------------
-- Documentation (Finding 9: 0 of 42 live objects carried a comment)
-- ---------------------------------------------------------------------------------------

COMMENT ON TABLE v2.mitogenome_data IS
    'Assembled mitogenome per (og_id, tech, seq_date, code). Parent of the LCA tables. Unlike '
    'the live table it has a foreign key to sample, so an assembly cannot reference a specimen '
    'that does not exist.';
COMMENT ON TABLE v2.lca IS
    'Lowest common ancestor calls per marker region. Live carries this key as a UNIQUE '
    'constraint only; here it is the primary key.';
COMMENT ON TABLE v2.lca_validation IS
    'Human validation of LCA calls. Read by v2.summary and by the public reporting views.';
COMMENT ON TABLE v2.lca_raw_results IS
    'Unfiltered LCA output. lca_run_date is text here, matching v2.lca; the live tables '
    'disagree on its type while using it in equivalent uniqueness constraints.';
COMMENT ON TABLE v2.blast_filtered_lca IS
    'BLAST hits retained after LCA filtering, one row per matched sequence and region.';

COMMENT ON COLUMN v2.lca.lca_run_date IS
    'Part of the primary key, so NOT NULL here. Live allows null in the equivalent UNIQUE '
    'constraint, where nulls compare as distinct and silently permit duplicate LCA runs.';

COMMIT;
