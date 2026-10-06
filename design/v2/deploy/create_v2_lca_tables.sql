-- Deploy genomes_db:create_v2_lca_tables to pg
-- requires: create_v2_lab_tables

-- Purpose: Build v2 equivalents of the LCA / mitogenome tables to the same design rules as the
--   lab tables (decision 1, §5 step 11).
--
-- SCOPE NOTE, CORRECTED 2026-10-05 (Phase V.1 item 1). This file used to say that
--   `lca_new` and its siblings were concurrent work and must not be modified. That was true
--   when it was written on 2026-08-05 and it is not true now. The LCA rebuild has landed:
--   those tables ARE the live `lca`, `lca_raw_results`, `lca_validation` and
--   `blast_filtered_lca` that this file builds v2 equivalents of. There is no `*_new` table
--   left to avoid. The re-diff that correction forced found four columns and one
--   unsatisfiable primary key; see the notes at each.
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
-- Expected impact: Additive only. Five empty tables, one function and two triggers in the
--   `v2` schema. Every live table is untouched.

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
    -- NULLABLE, corrected 2026-10-05 (Phase V.1). This said NOT NULL, which no finding
    -- asked for and which live does not enforce: live's primary key is
    -- (og_id, tech, seq_date, code) and annotation appears only in the secondary UNIQUE,
    -- exactly as reproduced below. The PK already forbids duplicate rows, so NOT NULL here
    -- bought nothing and would have rejected 374 of 2,349 live rows -- 16% of the table.
    --
    -- Those 374 are not defective. NULL annotation means "assembled, not yet annotated",
    -- and the data says so unambiguously: all 374 have cds_no, trna_no, passed and
    -- annotation_integrity_status null, while all 1,975 annotated rows have every one of
    -- them populated. They span 2022-11-15 to 2026-09-25 and all three techs, so this is
    -- the current state of the pipeline, not a legacy artefact.
    --
    -- Decision 6 says to quarantine rows rather than weaken the schema, and that is right
    -- when the schema encodes a real contract. It does not apply here: the constraint was
    -- never a decision, and there is no fix the lab could make -- an unannotated assembly
    -- has no annotation to supply. Quarantining 374 in-progress assemblies would also have
    -- swamped the 1,004-row quarantine baseline and hidden every other signal in it.
    annotation text,
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

    -- Restored by the Phase V.1 re-review (2026-10-05). The 34 columns below were
    -- added to live by migrations 003 (depth), 021 (trna_advisory), 023 and 025
    -- (order variant) and 026 (annotation integrity) AFTER this file was written on
    -- 2026-08-05. Omitting them is not a design decision -- it is this file being
    -- three months stale, and a cutover would have dropped every one of them.
    -- Types are carried over from live as the migrations typed them: these were
    -- written as real types, so Finding 7 does not apply.
    mean_depth double precision,
    median_depth double precision,
    depth_sd double precision,
    depth_cv double precision,
    breadth_1x double precision,
    breadth_10x double precision,
    mito_mapped_reads bigint,
    total_reads bigint,
    mito_read_fraction double precision,
    depth_target_length_bp integer,
    depth_target_fasta text,
    depth_method text,
    depth_measured_at timestamp with time zone,
    trna_advisory text,
    order_variant text,
    order_deviation text,
    annotation_gaps text,
    order_variant_taxon_check text,
    order_status text,
    order_deviation_detail text,
    expected_lineage_genes text,
    missing_expected_lineage_genes text,
    lineage_gene_advisories text,
    mitos_unmapped_features text,
    mitos_known_auxiliary_features text,
    duplicate_loci text,
    annotation_integrity_status text,
    annotation_integrity_issues text,
    atp9 integer,
    atp9_trans integer,
    mtmuts integer,
    mtmuts_trans integer,
    annotation_stats_version text,
    annotation_updated_at timestamp with time zone,

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
    -- double precision, not real. Migration 022 widened this on live precisely because
    -- real bottoms out near 1.18e-38 while HiFi hits produce values like 5.27e-163. This
    -- file predates 022 and still said `real`; 5 of 4,916 live rows raise
    -- "value out of range: underflow" on a ::real cast, so the backfill would have aborted
    -- rather than quietly rounding. Phase V.1 item 1, 2026-10-05.
    top_confidence_score double precision,
    top_percent_match double precision,

    -- Added by migration 017 (content-addressed rows) and 022, both after this file
    -- was written. taxon_rank_db records which reference database the rank came from.
    taxon_rank_db text,
    content_hash text NOT NULL,

    -- Keyed on content_hash, not lca_run_date. The August design keyed on
    -- (..., region, lca_run_date), which happens to hold on today's data -- but it
    -- encodes the wrong contract. Migration 017 made these rows CONTENT-addressed
    -- precisely so that re-running the pipeline and getting a different answer stores
    -- a new row instead of colliding with the old one. A run_date key reintroduces
    -- the collision that 017 removed, and the failure would arrive on the first
    -- same-day re-run rather than at cutover. This matches live's
    -- lca_content_unique exactly; verified 0 collisions on 4,916 live rows.
    CONSTRAINT lca_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, region, content_hash),
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
    -- Added by migration 024 after this file was written. validated_rank is load
    -- bearing beyond this table: Phase E.3 classifies the 892 invalid
    -- sample.nominal_species_id values with it.
    validated_rank text,
    lca_genus text,
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
    -- double precision; see v2.lca.top_confidence_score. 25 of 46,644 live rows underflow
    -- a ::real cast here, the smallest being 5.27e-163.
    confidence_score double precision,

    -- Migration 017 again; see v2.lca above.
    taxon_rank_db text,
    content_hash text NOT NULL,

    -- The August key -- (..., lca_run_date, accession_id) -- is NOT SATISFIABLE by
    -- live data: 33 rows of 46,644 collide under it. They are not duplicates. One
    -- BLAST accession legitimately yields several HSPs in one run, so the rows share
    -- an accession and a run date while differing in percent_match. Deploying the
    -- August key would have quarantined all 33 at backfill and then rejected every
    -- future multi-HSP hit, reading as a data defect rather than the key design
    -- error it is. Live's lca_raw_results_content_unique is the correct contract and
    -- has 0 collisions.
    CONSTRAINT lca_raw_results_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, sequence_region, accession_id, content_hash),
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
    -- text, not integer. Migration 022 made this text on live and the reason is visible in
    -- the data: 1,009 of 242,269 rows hold semicolon-separated lists of taxon ids
    -- ('104759;596308;627028') where one BLAST hit matches several taxa. An integer column
    -- rejects every one of them. Not an overflow -- the largest single value is 3,471,590,
    -- well inside int4 -- which is why this is easy to misread as safe.
    taxon_id text,
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
    'disagree on its type while using it in equivalent uniqueness constraints. '
    'confidence_score is double precision, not real -- see the column note, and do not '
    'narrow it back.';
-- ---------------------------------------------------------------------------------------
-- content_hash maintenance (migration 017, carried forward)
-- ---------------------------------------------------------------------------------------
--
-- content_hash is NOT NULL and part of two primary keys, so it needs a source. Live
-- maintains it with public.lca_set_content_hash(); this is the same logic in the v2
-- schema. It is duplicated rather than reused deliberately: the public function is
-- unqualified and unpinned, so pointing v2 triggers at it would make the hash depend
-- on the caller's search_path.
--
-- Note the function hashes to_jsonb(NEW) minus three keys. Subtracting a key a row
-- does not have is a no-op in jsonb, so dropping og_num (F2) needs no change here.

CREATE FUNCTION v2.lca_set_content_hash() RETURNS trigger
LANGUAGE plpgsql
SET search_path = v2, pg_temp
AS $$
BEGIN
    NEW.content_hash := md5(
        (to_jsonb(NEW) - 'lca_run_date' - 'og_num' - 'content_hash')::text
    );
    RETURN NEW;
END $$;

CREATE TRIGGER lca_content_hash
    BEFORE INSERT OR UPDATE ON v2.lca
    FOR EACH ROW EXECUTE FUNCTION v2.lca_set_content_hash();

CREATE TRIGGER lca_raw_results_content_hash
    BEFORE INSERT OR UPDATE ON v2.lca_raw_results
    FOR EACH ROW EXECUTE FUNCTION v2.lca_set_content_hash();

COMMENT ON FUNCTION v2.lca_set_content_hash() IS
    'Maintains content_hash on v2.lca and v2.lca_raw_results. Pinned search_path so the '
    'hash cannot vary with the caller''s path.';

COMMENT ON TABLE v2.blast_filtered_lca IS
    'BLAST hits retained after LCA filtering, one row per matched sequence and region.';

COMMENT ON COLUMN v2.lca.lca_run_date IS
    'When the LCA pipeline ran. NOT NULL, but deliberately NOT part of the key -- row '
    'identity is the content hash (migration 017), so a re-run with a changed answer '
    'stores a new row rather than colliding with the old one.';
COMMENT ON COLUMN v2.lca.content_hash IS
    'md5 of the row content, maintained by the trigger below. Row identity for this table. '
    'Not comparable with public.lca.content_hash: the hash covers every column, and the two '
    'tables no longer have the same column set (og_num is gone, F2). Reconcile these tables '
    'on their business keys, never on this value.';
COMMENT ON COLUMN v2.lca_raw_results.content_hash IS
    'See v2.lca.content_hash. Part of the key here because one BLAST accession can yield '
    'several HSPs in a single run, which share accession and run date but differ in '
    'percent_match -- 33 such rows exist in live today.';

COMMIT;
