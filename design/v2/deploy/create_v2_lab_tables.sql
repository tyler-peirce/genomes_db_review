-- Deploy genomes_db:create_v2_lab_tables to pg
-- requires: create_v2_schema

-- Purpose: Build the redesigned lab workflow tables in the `v2` schema, empty, ready to be
--   backfilled from the live public.* tables and validated before cutover. This REPLACES the
--   earlier structural-clone version of this change, which reproduced defects that
--   database_review.md and docs/lab_key_strategy.md had already identified.
--
-- Review source: docs/v2_scaffold_design_review.md (findings F1-F13, decisions 1-11, build
--   order §5 steps 2-4); docs/lab_key_strategy.md §6.0-§6.5; docs/spreadsheet_column_gap_analysis.md.
--
-- What changed relative to the live tables, and why:
--   F1  No derived `og_id` on any child table. Ancestors are reached through the parent FK,
--       or through the browse views in create_v2_browse_views. `og_num` survives only on
--       `sample`, where it is derived from that table's own primary key rather than from an
--       ancestor, and is null-safe rather than raising on non-matching IDs (F2).
--   F3  Dates are `date`, measurements are numeric. The live tables store these as text
--       because converting populated columns needs profiling; that cost does not exist here,
--       and bad values surface at backfill where they belong.
--   F4  Columns already confirmed dead are not carried forward (see the DROPPED notes below).
--   F4a `status_overwrite` is `boolean`. `latest` is NOT a column: the spreadsheet computes it
--       as MAX(#) per parent, so it is a window function and lives in the browse views.
--   F5  `sample` holds the 1.MetaData columns plus the eight hand-entered Summary columns
--       kept by decision 9. The derived Summary rollups are rebuilt as a view instead.
--   F6  `sequencing` points at ONE library via the `library` registry, replacing five nullable
--       polymorphic columns of which one could not carry a foreign key at all.
--   F7  Parent FKs are NOT NULL, `unique(parent_id, attempt_num)` is enforced, every FK column
--       is indexed, and every table and non-obvious column carries a COMMENT. 64 rows in the
--       current workbook violate that uniqueness - 53 of them on 4.RNAIllumina - and quarantine.
--   F8  `text` throughout; no `character varying(n)`.
--   F12 `Manual/ Automated Method` is a shared lookup across the two library tables that use it.
--   F13 Proximity ligation lives on `hic_lysate`; `hic_library.prox_ligation_conc` is retained
--       as a legacy read-only column.
--   §4.1 Fourteen columns of hand-entered lab data that the nightly import has been silently
--       dropping are added. They are marked `-- gap` below.
--
-- Expected impact: Additive only. Creates 14 empty tables in the `v2` schema — the 12 lab
--   workflow tables, the `library` identity registry, and the `prep_automation` lookup (which
--   is seeded with its two values). Nothing in
--   `public` is read, written, or altered, and the nightly import is unaffected until it is
--   repointed in a later change.
--
-- Deliberately deferred: the generated `tissue_type_code` / `tissue_index` columns of
--   lab_key_strategy.md §6.2, which should not be added until the naming grammar is enforced;
--   and `created_at`/`updated_at` audit columns, which per F8 should be all-or-nothing and are
--   currently on neither the live tables nor these.

BEGIN;

SET LOCAL search_path = v2, public;

-- ---------------------------------------------------------------------------------------
-- Lookup: shared prep-automation vocabulary (F12, decision 10)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.prep_automation (
    prep_automation text PRIMARY KEY,
    description     text
);

COMMENT ON TABLE v2.prep_automation IS
    'Controlled vocabulary for the spreadsheet''s "Manual/ Automated Method" column, shared by '
    'illumina_library and pacbio_library. 4.Illumina currently spells the automated value '
    '"Auomated Biomek i7" (missing t) in all 941 populated rows while 4.PacBio spells it '
    'correctly; a shared lookup makes that a backfill normalisation instead of two permanently '
    'divergent free-text columns. See v2_scaffold_design_review.md F12.';

INSERT INTO v2.prep_automation (prep_automation, description) VALUES
    ('Manual',              'Library prepared by hand at the bench.'),
    ('Automated Biomek i7', 'Library prepared on the Beckman Biomek i7 liquid handler.');

-- ---------------------------------------------------------------------------------------
-- sample  (spreadsheet: 1.MetaData, plus 8 hand-entered columns from Summary)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.sample (
    og_id                              text NOT NULL,
    og_num                             integer GENERATED ALWAYS AS
                                           (NULLIF(substring(og_id from '^OG([0-9]+)$'), '')::integer) STORED,
    project_id                         text,
    field_id                           text,
    nominal_species_id                 text,
    common_name                        text,
    collector                          text,
    contact                            text,
    date_collected                     date,
    sex                                text,
    weight                             real,
    lengthtl_and_lengthfl              real,
    country                            text,
    state                              text,
    location                           text,
    latitude_collection                double precision,
    longitude_collection               double precision,
    depth_collection                   real,
    collection_method                  text,
    preservation_method                text,
    sample_condition                   text,
    sample_condition_upon_preservation text,                                   -- gap
    photo_voucher                      text,
    photo_id                           text,
    specimen_voucher                   text,
    voucher_id                         text,
    ethics_permit                      text,                                   -- gap
    collection_permit                  text,                                   -- gap
    import_permit                      text,                                   -- gap
    cultural_significance              text,                                   -- gap
    cites                              text,                                   -- gap
    cms                                text,                                   -- gap
    iucn                               text,                                   -- gap
    epbc                               text,                                   -- gap
    sample_receipt_date                date,                                   -- gap
    comments                           text,

    -- Hand-entered planning columns from the Summary sheet (decision 9). These record the
    -- lab's INTENT for a sample, which cannot be derived from the child tables however
    -- complete they are. v2.summary shows each against what actually exists.
    --
    -- They are boolean, not integer. Measured against the workbook, all six hold exactly two
    -- values, Y and N — 'is this sample slated for this technology?' — not counts. That also
    -- explains the live summary view's CASE WHEN s.illumina_sequencing = 'N' guard: the
    -- intent was always a flag, the guard was simply pointed at a dead column.
    workflow                           text,
    priority                           text,
    ilmn                               boolean,
    hifi                               boolean,
    hic                                boolean,
    nano                               boolean,
    rna                                boolean,
    ilrna                              boolean,

    -- Downstream / submission columns. Not spreadsheet-sourced; written by other processes.
    assigned_species                   text,
    eschmeyer_id                       text,
    ncbi_sample_name                   text,
    ncbi_biosample_id                  text,
    hifi_lca_outcome                   text,
    ncbi_id                            text,
    tol_id                             text,
    ncbi_bioproject_id_lvl_3_hifi      text,
    bioproject_id_haplotype_1          text,
    bioproject_id_haplotype_2          text,
    bioproject_sequencing_data         text,
    ncbi_assembly_upload               text,
    ncbi_raw_reads_upload              text,
    hifi_public                        text,
    illumina_lca                       text,
    ncbi_bioproject_id_draft           text,
    draft_sra_accessions               text,
    draft_assembly_accession           text,
    embargo_status                     text,

    CONSTRAINT sample_pkey PRIMARY KEY (og_id)
);

-- DROPPED from the live sample, all sourced from the derived Summary sheet (F5, decision 5):
--   tissues, extracted, extraction_queue, il_status, pb_status, hic_status, ont_num,
--   rna_status, ilrna_status. These are Excel rollups of the child tables and are the root
--   cause of the status fragmentation in database_review.md Finding 7 (47 distinct rna_status
--   values, comma-combined statuses). v2.summary recomputes them from the child tables.
--   Note ont_num was never a number: it is mapped to the "NanoPore Status" header.
-- ALSO DROPPED, confirmed 0/2675 populated (F4): illumina_sequencing, hifi_sequencing,
--   hic_sequencing, nanopore_sequencing, rna_extraction, rna_ilmn_sequencing,
--   rna_kinnex_sequencing, illumina_public, summary_comments. `rna_extraction` in particular
--   was an empty text column whose name collided with the rna_extraction table.
-- NOT ADDED, though the previous scaffold proposed them: rna_processing_comment (duplicates
--   rna_library_kinx.processing_comment) and rna_kinnex_status (a rollup of
--   rna_library_kinx.rna_status). Both are Summary-sheet formulas.

COMMENT ON TABLE  v2.sample IS 'One row per specimen. Source: the 1.MetaData sheet, plus eight hand-entered planning columns from Summary.';
COMMENT ON COLUMN v2.sample.og_num IS 'Numeric part of og_id, for sort order only. Null on any og_id not matching ^OG[0-9]+$ rather than raising, unlike the live column.';
COMMENT ON COLUMN v2.sample.ilmn IS 'Is this sample slated for Illumina? Hand-entered lab intent (Y/N in the workbook). Compare against the actual library count in v2.summary.';
COMMENT ON COLUMN v2.sample.hifi IS 'Is this sample slated for PacBio HiFi? Hand-entered lab intent.';
COMMENT ON COLUMN v2.sample.hic IS 'Is this sample slated for Hi-C? Hand-entered lab intent.';
COMMENT ON COLUMN v2.sample.nano IS 'Is this sample slated for ONT? Hand-entered lab intent.';
COMMENT ON COLUMN v2.sample.rna IS 'Is this sample slated for RNA extraction? Hand-entered lab intent.';
COMMENT ON COLUMN v2.sample.ilrna IS 'Is this sample slated for Illumina RNA? Hand-entered lab intent.';
COMMENT ON COLUMN v2.sample.sample_receipt_date IS 'Stored as an Excel date serial in the sheet, like Date_Collected; the importer needs the same serial-to-date handling.';

-- ---------------------------------------------------------------------------------------
-- tissue  (spreadsheet: 2.Tissue)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.tissue (
    tissue_id    text NOT NULL,
    og_id        text NOT NULL,
    alt_id       text,
    tissue       text,
    extracted    integer,
    preservation text,                                                          -- gap
    freezer      text,
    shelf        integer,
    rack         integer,
    level        text,
    box          text,
    comment      text,

    CONSTRAINT tissue_pkey PRIMARY KEY (tissue_id),
    CONSTRAINT tissue_og_id_fkey FOREIGN KEY (og_id) REFERENCES v2.sample(og_id)
);

-- DROPPED: field_id. It is a ~100% formula lookup of sample.field_id on the 2.Tissue sheet,
--   and no view or script in this repo reads it.
-- DROPPED: og_num, which duplicated sample.og_num one level down.

COMMENT ON TABLE  v2.tissue IS 'One row per tissue subsample taken from a specimen. Source: the 2.Tissue sheet.';
COMMENT ON COLUMN v2.tissue.og_id IS 'Parent specimen. The only ancestor stored here, per lab_key_strategy.md §6.0.';
COMMENT ON COLUMN v2.tissue.preservation IS 'Tissue-level preservation. Distinct from sample.preservation_method, which is specimen-level.';

-- ---------------------------------------------------------------------------------------
-- dna_extraction  (spreadsheet: 3.DNAExtractions)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.dna_extraction (
    dna_id              text NOT NULL,
    tissue_id           text NOT NULL,
    ext_num             integer,
    status              text,
    extraction_method   text,
    extraction_date     date,
    extraction_batch_id text,
    final_buffer        text,
    volume              integer,
    qubit_conc          real,
    nano_drop_conc      real,
    ratio_260_280       real,
    ratio_260_230       real,
    total_yield         real,
    gdna_femtol_id      text,
    av_size             real,
    extraction_qc       text,
    comment             text,
    dna_freezer         text,
    dna_shelf           integer,
    dna_rack            integer,
    dna_level           text,
    dna_box             text,
    dna_notes           text,
    status_overwrite    boolean,

    CONSTRAINT dna_extraction_pkey PRIMARY KEY (dna_id),
    CONSTRAINT dna_extraction_tissue_id_fkey FOREIGN KEY (tissue_id) REFERENCES v2.tissue(tissue_id),
    CONSTRAINT dna_extraction_attempt_key UNIQUE (tissue_id, ext_num)
);

-- DROPPED: og_id and og_num (F1, F2). og_num in particular was computed by stripping every
--   non-digit from tissue_id, so OG123G2 yielded 1232 rather than 123.
-- DROPPED: ratioqubit_nanodrop (F4) — dead on both ends. The mapped spreadsheet header does
--   not exist AND queries.py's dna_extraction insert never referenced the field.

COMMENT ON TABLE  v2.dna_extraction IS 'One row per DNA extraction attempt from a tissue. Source: the 3.DNAExtractions sheet.';
COMMENT ON COLUMN v2.dna_extraction.status_overwrite IS
    'Lab flag marking which extraction to report in the summary. Boolean because the workbook '
    'holds only Y here - 129 of them across all sheets, 36 on this one, and nothing else. It '
    'has never reached the database: neither spelling of the header ("Status Overwrite" / '
    '"Overwrite Status") is in name_convert.py, so the lab has been filling a field the import '
    'silently discards while summary reads a column that is always null. See '
    'v2_scaffold_design_review.md F4a.';
COMMENT ON CONSTRAINT dna_extraction_attempt_key ON v2.dna_extraction IS
    'The spreadsheet''s own "Latest" formula, MAX(#) per parent, is only correct if this holds - '
    'a tie marks two rows as latest. It fails on 5 of 2,223 rows here (and on 53 of 321 on '
    '4.RNAIllumina, the worst case); those rows quarantine for the lab to renumber.';

-- ---------------------------------------------------------------------------------------
-- rna_extraction  (spreadsheet: 3.RNAExtractions)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.rna_extraction (
    rna_id              text NOT NULL,
    tissue_id           text NOT NULL,
    ext_num             integer,
    status              text,
    extraction_method   text,
    extraction_date     date,
    extraction_batch_id text,
    final_buffer        text,
    volume              integer,
    qubit_conc          real,
    nano_drop_conc      real,
    ratio_260_280       real,
    ratio_260_230       real,
    total_yield         real,
    gdna_over_7kb_perc  real,                                                   -- gap
    tapestation_id      text,
    rna_dv200           real,
    rin                 real,
    extraction_qc       text,
    comment             text,
    rna_freezer         text,
    rna_shelf           integer,
    rna_rack            integer,
    rna_level           text,
    rna_box             text,
    rna_notes           text,
    status_overwrite    boolean,

    CONSTRAINT rna_extraction_pkey PRIMARY KEY (rna_id),
    CONSTRAINT rna_extraction_tissue_id_fkey FOREIGN KEY (tissue_id) REFERENCES v2.tissue(tissue_id),
    CONSTRAINT rna_extraction_attempt_key UNIQUE (tissue_id, ext_num)
);

-- DROPPED: og_id (F1).
-- rna_shelf / rna_rack are integer here, matching dna_extraction. They are text on the live
--   table, which is type drift between two tables recording the same thing (F8).

COMMENT ON TABLE  v2.rna_extraction IS 'One row per RNA extraction attempt from a tissue. Source: the 3.RNAExtractions sheet.';
COMMENT ON COLUMN v2.rna_extraction.gdna_over_7kb_perc IS 'Spreadsheet header "gDNA? >7,000bp %". Populated on 185 rows and dropped by the importer until now.';

-- ---------------------------------------------------------------------------------------
-- hic_lysate  (spreadsheet: 4.HiCLysate)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.hic_lysate (
    lysate_id            text NOT NULL,
    tissue_id            text NOT NULL,
    lysate_num           integer,
    lysate_status        text,
    lysate_method        text,                                                  -- gap
    lysate_prep_date     date,
    lysate_batch_id      text,
    lysate_conc          real,
    total_lysate         real,
    lysate_cde           real,
    prox_ligation_date   date,                                                  -- gap
    prox_ligation_conc   real,                                                  -- gap
    prox_ligation_yield  real GENERATED ALWAYS AS (prox_ligation_conc * 40) STORED,
    lysate_comments      text,
    status_overwrite     boolean,

    CONSTRAINT hic_lysate_pkey PRIMARY KEY (lysate_id),
    CONSTRAINT hic_lysate_tissue_id_fkey FOREIGN KEY (tissue_id) REFERENCES v2.tissue(tissue_id),
    CONSTRAINT hic_lysate_attempt_key UNIQUE (tissue_id, lysate_num)
);

COMMENT ON TABLE  v2.hic_lysate IS 'One row per Hi-C lysate prepared from a tissue. Source: the 4.HiCLysate sheet.';
COMMENT ON COLUMN v2.hic_lysate.lysate_method IS 'Spreadsheet header "Prep Method". Populated on 386 rows and dropped by the importer until now.';
COMMENT ON COLUMN v2.hic_lysate.prox_ligation_conc IS
    'Proximity ligation concentration - the LIVE home for this measurement (decision 11). '
    'Evidence: it agrees with hic_library.prox_ligation_conc 48 times out of 49 where both are '
    'present; all 19 multi-library conflicts predate this column; and 36 lysates carry a value '
    'while having zero or one Hi-C library, so it exists before any library does. The workbook '
    'contains the literal strings "NA" and "0" here, which will quarantine against this type.';
COMMENT ON COLUMN v2.hic_lysate.prox_ligation_yield IS
    'Derived, matching the workbook formula IF(conc="NA","NA",conc*40) on 4.HiCLysate. The 40 is '
    'the elution volume in uL; if the protocol changes this expression must change with it.';

-- ---------------------------------------------------------------------------------------
-- library  — thin identity registry (F6, decision 4; lab_key_strategy.md §6.4)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.library (
    library_tube_id text NOT NULL,
    library_type    text NOT NULL,
    dna_id          text,
    rna_id          text,
    lysate_id       text,

    CONSTRAINT library_pkey PRIMARY KEY (library_tube_id),
    CONSTRAINT library_type_check CHECK (library_type IN
        ('illumina', 'pacbio', 'ont', 'hic', 'rna_ilmn', 'rna_kinx')),
    CONSTRAINT library_one_parent_check CHECK (num_nonnulls(dna_id, rna_id, lysate_id) = 1),
    CONSTRAINT library_dna_id_fkey    FOREIGN KEY (dna_id)    REFERENCES v2.dna_extraction(dna_id),
    CONSTRAINT library_rna_id_fkey    FOREIGN KEY (rna_id)    REFERENCES v2.rna_extraction(rna_id),
    CONSTRAINT library_lysate_id_fkey FOREIGN KEY (lysate_id) REFERENCES v2.hic_lysate(lysate_id),

    -- Referenced by the composite FKs on the technology tables below, which make each
    -- table's parent column provably agree with the registry's (§6.4 "open question:
    -- where parentage lives"). Trivially satisfied given library_tube_id is the PK.
    CONSTRAINT library_tube_dna_key    UNIQUE (library_tube_id, dna_id),
    CONSTRAINT library_tube_rna_key    UNIQUE (library_tube_id, rna_id),
    CONSTRAINT library_tube_lysate_key UNIQUE (library_tube_id, lysate_id)
);

COMMENT ON TABLE v2.library IS
    'Identity registry giving every library, of any technology, one primary key so sequencing '
    'has a single FK target. It normalises nothing away: each technology table keeps all of its '
    'own columns and its own parent FK. Confirmed safe as a shared key - the two RNA library '
    'sheets have zero tube-ID overlap (312 distinct on 4.RNAIllumina with _IL/_dIL suffixes, '
    '174 on 4.RNAkinnex with _KL). See lab_key_strategy.md §6.4.';
COMMENT ON COLUMN v2.library.library_type IS
    'Which technology table holds this library''s attributes. Replaces sequencing.seq_type, '
    'which import_data.py currently derives by testing for _D / _R substrings in the tube ID.';
COMMENT ON CONSTRAINT library_one_parent_check ON v2.library IS
    'Exactly one parent. Expressed as three typed nullable FK columns rather than a '
    'source_type/source_id pair, because a polymorphic reference cannot carry a real foreign '
    'key - which is the guarantee this whole design depends on.';

-- ---------------------------------------------------------------------------------------
-- illumina_library  (spreadsheet: 4.Illumina)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.illumina_library (
    illumina_library_tube_id text NOT NULL,
    dna_id                   text NOT NULL,
    ilmn_num                 integer,
    ilmn_status              text,
    library_method           text,
    prep_automation          text,                                             -- gap
    library_date             date,
    library_id               text,
    library_plate_well       text,                                             -- gap
    index_plate              text,                                             -- gap
    index_set                text,
    index_well               text,
    index_idx                text,
    library_qubit_conc       real,
    il_comments              text,
    status_overwrite         boolean,

    CONSTRAINT illumina_library_pkey PRIMARY KEY (illumina_library_tube_id),
    CONSTRAINT illumina_library_dna_id_fkey FOREIGN KEY (dna_id) REFERENCES v2.dna_extraction(dna_id),
    CONSTRAINT illumina_library_registry_fkey FOREIGN KEY (illumina_library_tube_id, dna_id)
        REFERENCES v2.library(library_tube_id, dna_id),
    CONSTRAINT illumina_library_prep_automation_fkey FOREIGN KEY (prep_automation)
        REFERENCES v2.prep_automation(prep_automation),
    CONSTRAINT illumina_library_attempt_key UNIQUE (dna_id, ilmn_num)
);

-- DROPPED: og_id (F1). library_qubit_conc is real here; it was text on the live table and
--   real on rna_library_ilmn, the exact drift §6.4 names as a blocker (F3, F8).

COMMENT ON TABLE  v2.illumina_library IS 'One row per Illumina DNA library. Source: the 4.Illumina sheet.';
COMMENT ON COLUMN v2.illumina_library.prep_automation IS 'Spreadsheet header "Manual/ Automated Method", populated on 1,607 rows and dropped by the importer until now. 941 of them read "Auomated Biomek i7" and normalise to "Automated Biomek i7" at backfill.';
COMMENT ON COLUMN v2.illumina_library.library_plate_well IS 'Spreadsheet header "Library Plate Well". Populated on 1,523 rows and dropped by the importer until now.';
COMMENT ON COLUMN v2.illumina_library.index_plate IS 'Spreadsheet header "Index Plate". Populated on 1,297 rows and dropped by the importer until now.';

-- ---------------------------------------------------------------------------------------
-- pacbio_library  (spreadsheet: 4.PacBio)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.pacbio_library (
    pacbio_library_tube_id text NOT NULL,
    dna_id                 text NOT NULL,
    pacb_num               integer,
    pacb_status            text,
    dna_treatment          text,
    sre_kit                text,                                               -- gap
    post_sre_conc          real,                                               -- gap
    final_pre_library_conc real,                                               -- gap
    shear_femtol_id        text,
    shear_av_size          integer,
    library_method         text,
    prep_automation        text,                                               -- gap
    library_date           date,
    library_id             text,
    index_well             text,
    barcode                text,
    seq_femto_id           text,
    seq_av_size            real,
    library_conc           real,
    comment                text,
    status_overwrite       boolean,

    CONSTRAINT pacbio_library_pkey PRIMARY KEY (pacbio_library_tube_id),
    CONSTRAINT pacbio_library_dna_id_fkey FOREIGN KEY (dna_id) REFERENCES v2.dna_extraction(dna_id),
    CONSTRAINT pacbio_library_registry_fkey FOREIGN KEY (pacbio_library_tube_id, dna_id)
        REFERENCES v2.library(library_tube_id, dna_id),
    CONSTRAINT pacbio_library_prep_automation_fkey FOREIGN KEY (prep_automation)
        REFERENCES v2.prep_automation(prep_automation),
    CONSTRAINT pacbio_library_attempt_key UNIQUE (dna_id, pacb_num)
);

COMMENT ON TABLE  v2.pacbio_library IS 'One row per PacBio HiFi library. Source: the 4.PacBio sheet.';
COMMENT ON COLUMN v2.pacbio_library.sre_kit IS 'Short Read Eliminator kit. Populated on 394 rows and dropped by the importer until now.';
COMMENT ON COLUMN v2.pacbio_library.post_sre_conc IS 'Spreadsheet header "Post-SRE Conc. (ng/uL)". Populated on 191 rows and dropped by the importer until now.';
COMMENT ON COLUMN v2.pacbio_library.final_pre_library_conc IS 'Spreadsheet header "Final Pre-Library Prep Conc. (ng/uL)". Populated on 194 rows and dropped by the importer until now.';
COMMENT ON COLUMN v2.pacbio_library.prep_automation IS 'Spreadsheet header "Manual/ Automated Method". Populated on 365 rows and dropped by the importer until now.';

-- ---------------------------------------------------------------------------------------
-- ont_library  (spreadsheet: 4.ONT)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.ont_library (
    ont_library_tube_id text NOT NULL,
    dna_id              text NOT NULL,
    ont_num             integer,
    ont_status          text,
    library_method      text,
    library_type        text,
    library_date        date,
    library_id          text,
    est_loading_size    integer,
    ont_comments        text,
    status_overwrite    boolean,

    CONSTRAINT ont_library_pkey PRIMARY KEY (ont_library_tube_id),
    CONSTRAINT ont_library_dna_id_fkey FOREIGN KEY (dna_id) REFERENCES v2.dna_extraction(dna_id),
    CONSTRAINT ont_library_registry_fkey FOREIGN KEY (ont_library_tube_id, dna_id)
        REFERENCES v2.library(library_tube_id, dna_id),
    CONSTRAINT ont_library_attempt_key UNIQUE (dna_id, ont_num)
);

COMMENT ON TABLE  v2.ont_library IS 'One row per Oxford Nanopore library. Source: the 4.ONT sheet.';
COMMENT ON COLUMN v2.ont_library.library_type IS 'The ONT kit type from the "Library Type" header. Unrelated to library.library_type, which names the technology.';

-- ---------------------------------------------------------------------------------------
-- hic_library  (spreadsheet: 4.HiCLibrary)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.hic_library (
    hic_library_tube_id         text NOT NULL,
    lysate_id                   text NOT NULL,
    hic_num                     integer,
    hic_status                  text,
    library_method              text,
    processing_notes            text,                                          -- gap
    library_date                date,
    library_id                  text,
    prox_ligation_conc          real,
    purified_dna_total          real,
    index_set                   text,
    index_i5                    text,                                          -- gap
    index_i7                    text,                                          -- gap
    library_conc                real,
    library_yield               real,                                          -- gap
    library_size                integer,
    pcr_dup_read_pairs          real,                                          -- gap
    nodup_cis_read_pairs_1kb    real,                                          -- gap
    expected_distinct_30m_reads bigint,                                        -- gap
    hic_comments                text,
    status_overwrite            boolean,

    CONSTRAINT hic_library_pkey PRIMARY KEY (hic_library_tube_id),
    CONSTRAINT hic_library_lysate_id_fkey FOREIGN KEY (lysate_id) REFERENCES v2.hic_lysate(lysate_id),
    CONSTRAINT hic_library_registry_fkey FOREIGN KEY (hic_library_tube_id, lysate_id)
        REFERENCES v2.library(library_tube_id, lysate_id),
    CONSTRAINT hic_library_attempt_key UNIQUE (lysate_id, hic_num)
);

COMMENT ON TABLE  v2.hic_library IS 'One row per Hi-C library. Source: the 4.HiCLibrary sheet.';
COMMENT ON COLUMN v2.hic_library.prox_ligation_conc IS
    'LEGACY, READ-ONLY. Retained to hold the 226 historical values that have no equivalent on '
    'their lysate row; the importer must not write here. The live home for this measurement is '
    'hic_lysate.prox_ligation_conc (decision 11, F13). These 226 cannot be migrated up because '
    '10 of their lysates carry conflicting values across their libraries and no rule picks a '
    'winner. Drop this column once the lab has resolved those or agreed the history is '
    'disposable.';

-- ---------------------------------------------------------------------------------------
-- rna_library_ilmn  (spreadsheet: 4.RNAIllumina)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.rna_library_ilmn (
    rna_library_tube_id text NOT NULL,
    rna_id              text NOT NULL,
    rna_num             integer,
    rna_status          text,
    library_method      text,
    library_date        date,
    library_id          text,
    library_size        integer,
    perc_product        real,
    library_qubit_conc  real,
    library_molarity    real,
    index_set           text,
    index_well          text,
    index_inx           text,
    comments            text,
    status_overwrite    boolean,

    CONSTRAINT rna_library_ilmn_pkey PRIMARY KEY (rna_library_tube_id),
    CONSTRAINT rna_library_ilmn_rna_id_fkey FOREIGN KEY (rna_id) REFERENCES v2.rna_extraction(rna_id),
    CONSTRAINT rna_library_ilmn_registry_fkey FOREIGN KEY (rna_library_tube_id, rna_id)
        REFERENCES v2.library(library_tube_id, rna_id),
    CONSTRAINT rna_library_ilmn_attempt_key UNIQUE (rna_id, rna_num)
);

-- DROPPED: og_id (F1); kinnex_primers and kinnex_barcode (F4, §6.4) — Kinnex protocol fields
--   on the Illumina RNA table, with no header on 4.RNAIllumina to populate them and no
--   consumer reading them. Confirm empty against live before backfill; if they hold values
--   that is misplaced Kinnex data and belongs in rna_library_kinx.

COMMENT ON TABLE  v2.rna_library_ilmn IS 'One row per Illumina RNA library. Source: the 4.RNAIllumina sheet.';
COMMENT ON COLUMN v2.rna_library_ilmn.perc_product IS 'Mapped in name_convert.py to a "% Product" header that no longer exists on 4.RNAIllumina, so it has been silently NULL. Retained pending a mapping fix, not a schema fix.';

-- ---------------------------------------------------------------------------------------
-- rna_library_kinx  (spreadsheet: 4.RNAkinnex)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.rna_library_kinx (
    rna_library_tube_id  text NOT NULL,
    rna_id               text NOT NULL,
    rna_num              integer,
    rna_status           text,
    library_method       text,
    processing_comment   text,
    synthesis_date       date,
    part1_batch_id       text,
    synthesis_conc       real,
    part2_batch_id       text,
    final_qubit_conc     real,
    library_size         integer,
    kinnex_primers       text,
    kinnex_barcode       text,
    pool_id              text,
    plate                integer,
    plate_location       text,
    sequencing_sample_id text,                                                 -- gap
    comments             text,
    status_overwrite     boolean,

    CONSTRAINT rna_library_kinx_pkey PRIMARY KEY (rna_library_tube_id),
    CONSTRAINT rna_library_kinx_rna_id_fkey FOREIGN KEY (rna_id) REFERENCES v2.rna_extraction(rna_id),
    CONSTRAINT rna_library_kinx_registry_fkey FOREIGN KEY (rna_library_tube_id, rna_id)
        REFERENCES v2.library(library_tube_id, rna_id),
    CONSTRAINT rna_library_kinx_attempt_key UNIQUE (rna_id, rna_num)
);

-- The FK to rna_extraction is present here, unlike on the live table (F7). The live table
--   lacks it because of unvalidated data; there is no data here to validate, and any bad row
--   surfaces at backfill, which is when it should.
-- All columns are `text` rather than character varying(n) (F8). The live table's
--   varchar(5) on plate_location and varchar(20) on kinnex_barcode were caps that break on the
--   first unanticipated value for no benefit.
-- created_at / updated_at are not carried forward: they existed on this table alone out of
--   twelve, which is worse than having them nowhere.

COMMENT ON TABLE  v2.rna_library_kinx IS 'One row per PacBio Kinnex RNA library. Source: the 4.RNAkinnex sheet.';
COMMENT ON COLUMN v2.rna_library_kinx.sequencing_sample_id IS 'Populated on 148 rows and dropped by the importer until now. Hand-entered here, unlike the same-named formula column on 4.RNAIllumina.';
COMMENT ON COLUMN v2.rna_library_kinx.synthesis_conc IS 'Mapped in name_convert.py to a header without the embedded newline the real one has ("cDNA Concentration \n(end of section 1 conc)"), so it has been silently NULL. Fix is in the importer.';

-- ---------------------------------------------------------------------------------------
-- sequencing  (spreadsheet: 5.Sequencing)
-- ---------------------------------------------------------------------------------------

CREATE TABLE v2.sequencing (
    sequencing_id   text NOT NULL,
    library_tube_id text NOT NULL,
    status          text,                                                      -- gap
    technology      text,
    instrument      text,
    run_date        date,
    run_id          text,
    seq_date        text GENERATED ALWAYS AS (split_part(run_id, '_', 2)) STORED,
    cell_id         text,
    smrt_num        integer,
    seq_type        text,
    design_no       integer,
    hic_depth       text,                                                      -- gap
    seq_comments    text,

    CONSTRAINT sequencing_pkey PRIMARY KEY (sequencing_id),
    CONSTRAINT sequencing_library_fkey FOREIGN KEY (library_tube_id) REFERENCES v2.library(library_tube_id)
);

-- REPLACED: the five nullable columns rna_library_tube_id / illumina_library_tube_id /
--   ont_library_tube_id / pacbio_library_tube_id / hic_library_tube_id, which carried only
--   four FKs between them and no constraint on how many could be non-null (so rows linked to
--   zero libraries were possible, and 40 existed). The 5.Sequencing sheet has ONE
--   "Library Tube ID" column; the fan-out is invented by import_data.py:129-167, which
--   branches on technology and tests for _D / _R substrings. This restores the source's shape.
-- DROPPED: og_id and og_num (F1, F2).
-- seq_date is retained as a generated column: it is parsed from this table's own run_id rather
--   than from an ancestor, and the LCA / mitogenome tables use it in composite keys.

COMMENT ON TABLE  v2.sequencing IS 'One row per sequencing record. Source: the 5.Sequencing sheet.';
COMMENT ON COLUMN v2.sequencing.library_tube_id IS 'The single library sequenced, via the registry. Replaces five nullable polymorphic columns, one of which could not carry a foreign key at all.';
COMMENT ON COLUMN v2.sequencing.status IS 'Spreadsheet header "Status". Populated on 4,004 of ~4,014 rows; the live sequencing table has no status column at all, so this has always been dropped.';
COMMENT ON COLUMN v2.sequencing.seq_type IS 'Retained for the existing consumers that filter on it. library.library_type is now the authoritative technology label; derive this from it at cutover rather than having the importer compute it.';

-- ---------------------------------------------------------------------------------------
-- Indexes on every foreign key column (F7 / database_review.md Finding 4)
-- ---------------------------------------------------------------------------------------

CREATE INDEX tissue_og_id_idx                ON v2.tissue            (og_id);
CREATE INDEX dna_extraction_tissue_id_idx    ON v2.dna_extraction    (tissue_id);
CREATE INDEX rna_extraction_tissue_id_idx    ON v2.rna_extraction    (tissue_id);
CREATE INDEX hic_lysate_tissue_id_idx        ON v2.hic_lysate        (tissue_id);
CREATE INDEX library_dna_id_idx              ON v2.library           (dna_id);
CREATE INDEX library_rna_id_idx              ON v2.library           (rna_id);
CREATE INDEX library_lysate_id_idx           ON v2.library           (lysate_id);
CREATE INDEX library_type_idx                ON v2.library           (library_type);
CREATE INDEX illumina_library_dna_id_idx     ON v2.illumina_library  (dna_id);
CREATE INDEX pacbio_library_dna_id_idx       ON v2.pacbio_library    (dna_id);
CREATE INDEX ont_library_dna_id_idx          ON v2.ont_library       (dna_id);
CREATE INDEX hic_library_lysate_id_idx       ON v2.hic_library       (lysate_id);
CREATE INDEX rna_library_ilmn_rna_id_idx     ON v2.rna_library_ilmn  (rna_id);
CREATE INDEX rna_library_kinx_rna_id_idx     ON v2.rna_library_kinx  (rna_id);
CREATE INDEX sequencing_library_tube_id_idx  ON v2.sequencing        (library_tube_id);

-- prep_automation FK columns: low cardinality (two values), so a btree index would not be
-- used for lookups. Indexed anyway only if the lookup table ever gains a cascade.

COMMIT;
