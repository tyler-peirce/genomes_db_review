--
-- PostgreSQL database dump
--

\restrict CnAkqeSOaB5UHk0p9jwiSNKSbrHsGIOVfI41xmFhMJroxoABEdfkghLBYY9XV2V

-- Dumped from database version 14.23 (Ubuntu 14.23-0ubuntu0.22.04.1)
-- Dumped by pg_dump version 14.23 (Ubuntu 14.23-0ubuntu0.22.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: build_final_data_compile(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.build_final_data_compile(in_og_ids text[]) RETURNS TABLE("ID" text, "Assembly" text, "TOLID" text, date text, species text)
    LANGUAGE sql
    AS $$
SELECT DISTINCT
  s.og_id AS "ID",
  CONCAT(s.og_id, '_v', r.seq_date, '.hic1') AS "Assembly",
  s.tol_id AS "TOLID",
  CONCAT('20', r.seq_date) AS "date",
  REPLACE(l.validated_species_name, ' ', '_') AS "species"
FROM
  sample s
JOIN
  ref_genomes r ON s.og_id = r.og_id
JOIN
  lca_validation l ON s.og_id = l.og_id
WHERE
  s.ncbi_assembly_upload IS NOT NULL
  AND s.embargo_status = 'Release'
  AND r.stage = 3
  AND l.tech IN ('hic', 'hifi')
  AND NULLIF(TRIM(l.validated_species_name), '') IS NOT NULL
  AND (in_og_ids IS NULL OR s.og_id = ANY(in_og_ids))
ORDER BY s.og_id;
$$;


--
-- Name: build_hicpost_samplesheet_rows(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.build_hicpost_samplesheet_rows(in_og_ids text[]) RETURNS TABLE(sample text, hic_dir text, assembly text, meryldb text, agp text, version text, date text, genomesize numeric)
    LANGUAGE sql
    AS $$
WITH p AS (
  SELECT unnest(in_og_ids) AS og_id
),
latest_seq AS (
  SELECT DISTINCT ON (seq.og_id)
         seq.og_id,
         seq.seq_date::date AS seq_date
  FROM sequencing seq
  JOIN p ON seq.og_id = p.og_id
  WHERE seq.technology = 'PacBio'
  ORDER BY seq.og_id, seq.seq_date DESC
),
gen_sz AS (
  -- If your column is named differently (e.g., genomesize), change genome_size below.
  SELECT rq.og_id, MAX(rq.genomesize) AS genome_size
  FROM raw_qc rq
  JOIN p ON rq.og_id = p.og_id
  GROUP BY rq.og_id
)
SELECT DISTINCT ON (p.og_id)
  p.og_id                                                   AS sample,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/hic'                       AS hic_dir,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/assembly'                  AS assembly,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/meryl'                   AS meryl,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/agp'                       AS agp,
  CASE WHEN rg.og_id IS NOT NULL THEN 'hic2' ELSE 'hic1' END AS version,
  CASE WHEN ls.seq_date IS NOT NULL THEN 'v' || to_char(ls.seq_date, 'YYMMDD') END AS date,
  gs.genome_size                                            AS genomesize
FROM p
LEFT JOIN ref_genomes rg ON rg.og_id = p.og_id
LEFT JOIN latest_seq  ls ON ls.og_id = p.og_id
LEFT JOIN gen_sz      gs ON gs.og_id = p.og_id
ORDER BY p.og_id;
$$;


--
-- Name: build_nfcore_samplesheet_rows(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.build_nfcore_samplesheet_rows(in_og_ids text[]) RETURNS TABLE(sample text, hifi_dir text, hic_dir text, version text, date text, tolid text, taxid bigint, species text, primary_assembly text, hap1_assembly text, hap2_assembly text)
    LANGUAGE sql
    AS $$
WITH p AS (
  SELECT unnest(in_og_ids) AS og_id
),
latest_seq AS (
  SELECT DISTINCT ON (seq.og_id)
         seq.og_id,
         seq.seq_date::date AS seq_date
  FROM sequencing seq
  JOIN p ON seq.og_id = p.og_id
  WHERE seq.technology IN ('PacBio HIFI', 'PacBio')
  ORDER BY seq.og_id, seq.seq_date DESC
),
smp AS (
  SELECT DISTINCT ON (s.og_id)
         s.og_id,
         s.nominal_species_id,
         s.tol_id
  FROM sample s
  JOIN p ON s.og_id = p.og_id
  ORDER BY s.og_id
),
-- One representative taxid per genus (for species-level fallback)
genus_tax AS (
  SELECT DISTINCT ON (genus)
         genus,
         ncbi_taxon_id
  FROM species
  WHERE ncbi_taxon_id IS NOT NULL
    AND genus IS NOT NULL
  ORDER BY genus, ncbi_taxon_id
)
SELECT DISTINCT ON (p.og_id)
  p.og_id AS sample,
  '/scratch/pawsey0964/lhuet/ref-gen/'||p.og_id||'/hifi' AS hifi_dir,
  '/scratch/pawsey0964/lhuet/ref-gen/'||p.og_id||'/hic'                  AS hic_dir,
  CASE WHEN rg.og_id IS NOT NULL THEN 'hic2' ELSE 'hic1' END AS version,
  CASE WHEN ls.seq_date IS NOT NULL THEN 'v'||to_char(ls.seq_date,'YYMMDD') END AS date,
  COALESCE(smp.tol_id, p.og_id) AS tolid,
  COALESCE(sp.ncbi_taxon_id, gt.ncbi_taxon_id) AS taxid,
  smp.nominal_species_id AS species,
  '' AS primary_assembly,
  '' AS hap1_assembly,
  '' AS hap2_assembly
FROM p
LEFT JOIN ref_genomes rg ON rg.og_id = p.og_id AND rg.version LIKE 'hic%'
LEFT JOIN latest_seq ls  ON ls.og_id = p.og_id
LEFT JOIN smp ON smp.og_id = p.og_id
LEFT JOIN species sp ON sp.species = smp.nominal_species_id
LEFT JOIN genus_tax gt  ON gt.genus = split_part(smp.nominal_species_id, ' ', 1)
ORDER BY p.og_id;
$$;


--
-- Name: build_postcuration_samplesheet_rows(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.build_postcuration_samplesheet_rows(in_og_ids text[]) RETURNS TABLE(sample text, hic_dir text, assembly text, meryldb text, agp text, version text, date text, genomesize numeric)
    LANGUAGE sql
    AS $$
WITH p AS (
  SELECT unnest(in_og_ids) AS og_id
),
latest_seq AS (
  SELECT DISTINCT ON (seq.og_id)
         seq.og_id,
         seq.seq_date::date AS seq_date
  FROM sequencing seq
  JOIN p ON seq.og_id = p.og_id
  WHERE seq.seq_type = 'PacBio'
  ORDER BY seq.og_id, seq.seq_date DESC
),
gen_sz AS (
  SELECT rq.og_id, MAX(rq.genomesize) AS genome_size
  FROM raw_qc rq
  JOIN p ON rq.og_id = p.og_id
  GROUP BY rq.og_id
)
SELECT DISTINCT ON (p.og_id)
  p.og_id                                 AS sample,
  '/scratch/pawsey0964/edejong/post_curation/' || p.og_id || '/hic'      AS hic_dir,
  '/scratch/pawsey0964/edejong/post_curation/' || p.og_id || '/assembly' AS assembly,
  '/scratch/pawsey0964/edejong/post_curation/' || p.og_id || '/meryl'    AS meryldb,
  '/scratch/pawsey0964/edejong/post_curation/' || p.og_id || '/agp'      AS agp,
  'hic1'                                  AS version,
  CASE
    WHEN ls.seq_date IS NOT NULL
    THEN 'v' || to_char(ls.seq_date, 'YYMMDD')
  END                                     AS date,
  gs.genome_size                          AS genomesize
FROM p
LEFT JOIN latest_seq ls ON ls.og_id = p.og_id
LEFT JOIN gen_sz gs     ON gs.og_id = p.og_id
ORDER BY p.og_id;
$$;


--
-- Name: build_rna_kinx_samplesheet_from_run(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.build_rna_kinx_samplesheet_from_run(in_run_id text) RETURNS TABLE(plate_well text, sequencing_sample_id text, library_type text, kinnex_pool text, kinnex_adapter_bc text, samples_in_pool text, isoseq_primer_bc text)
    LANGUAGE sql
    AS $$
WITH tubes AS (
    SELECT DISTINCT rna_library_tube_id
    FROM sequencing
    WHERE run_id = in_run_id
),
matched AS (
    SELECT
        -- 1_A01, 1_B01, etc.
        concat(rlk.plate, '_', rlk.plate_location, '01') AS plate_well,
        s.run_id AS sequencing_sample_id,     
        replace(rlk.library_method, ' ', '_') AS library_type,
        rlk.pool_id      AS kinnex_pool,
        rlk.kinnex_barcode AS kinnex_adapter_bc,
        s.rna_library_tube_id   AS samples_in_pool,
        rlk.kinnex_primers AS isoseq_primer_bc

    FROM rna_library_kinx rlk
    JOIN tubes t
      ON t.rna_library_tube_id = rlk.rna_library_tube_id
    JOIN sequencing s
      ON s.rna_library_tube_id = rlk.rna_library_tube_id
     AND s.run_id = in_run_id
)
SELECT *
FROM matched
ORDER BY plate_well;
$$;


--
-- Name: build_rna_kinx_samplesheet_rows(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.build_rna_kinx_samplesheet_rows(in_rna_ids text[]) RETURNS TABLE(plate text, plate_location text, pool_id text, kinnex_primers text, kinnex_barcodes text, rna_id text)
    LANGUAGE sql
    AS $$
WITH p AS (
  SELECT unnest(in_rna_ids) AS rna_id
)
SELECT
  rlk.plate,
  rlk.plate_location,
  rlk.pool_id,
  rlk.kinnex_primers,
  rlk.kinnex_barcode,
  rlk.rna_id
FROM rna_library_kinx rlk
JOIN p ON rlk.rna_id = p.rna_id
ORDER BY rlk.rna_id;
$$;


--
-- Name: embargo_assignment_view_upd(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.embargo_assignment_view_upd() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE sample
    SET embargo_status = NEW.embargo_status
    WHERE og_id = NEW.og_id;

    RETURN NEW;
END;
$$;


--
-- Name: lca_validation_report_view_upd(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lca_validation_report_view_upd() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Optional safety: prevent attempts to change the identifying fields via the view
  IF NEW.og_id IS DISTINCT FROM OLD.og_id
     OR NEW.tech IS DISTINCT FROM OLD.tech
     OR NEW.seq_date IS DISTINCT FROM OLD.seq_date
     OR NEW.code IS DISTINCT FROM OLD.code
     OR NEW.annotation IS DISTINCT FROM OLD.annotation
  THEN
    RAISE EXCEPTION
      'Cannot change key fields (og_id, tech, seq_date, code, annotation) through lca_validation_report_view';
  END IF;

  -- Persist only the editable columns back to the base table.
  UPDATE lca_validation
  SET validated_species_name         = NEW.validated_species_name,
      validator                      = NEW.validator,
      validator_2                    = NEW.validator_2,
      nominal_species_id_lca_comment = NEW.comment
  WHERE og_id       = OLD.og_id
    AND tech        = OLD.tech
    AND seq_date    = OLD.seq_date
    AND code        = OLD.code
    AND annotation  = OLD.annotation;

  -- If no row was updated, something is off (missing row or key mismatch).
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Update failed: no matching row in lca_validation for (og_id=%, tech=%, seq_date=%, code=%, annotation=%)',
      OLD.og_id, OLD.tech, OLD.seq_date, OLD.code, OLD.annotation;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;


--
-- Name: test_embargo_assignment_view_upd(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.test_embargo_assignment_view_upd() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE sample
    SET embargo_status = NEW.embargo_status
    WHERE og_id = NEW.og_id;

    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: blast_filtered_lca; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blast_filtered_lca (
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
    blast_run_date text
);


--
-- Name: hic_reads_qc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hic_reads_qc (
    og_id text DEFAULT ''::text NOT NULL,
    tissue text DEFAULT ''::text NOT NULL,
    ext_type text DEFAULT ''::text NOT NULL,
    lib_code text DEFAULT ''::text NOT NULL,
    lane text DEFAULT ''::text NOT NULL,
    run_id text DEFAULT ''::text NOT NULL,
    datecreated date,
    isarchived boolean,
    isfiledeleted boolean,
    totalreadspf bigint,
    totalclusterspf bigint,
    read1length integer,
    read2length integer,
    ispairedend boolean,
    yield_gb numeric,
    totalsize_gb numeric
);


--
-- Name: hifi_reads_qc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hifi_reads_qc (
    og_id text NOT NULL,
    tissue text NOT NULL,
    ext_type text NOT NULL,
    lib_code text NOT NULL,
    run_id text DEFAULT ''::text NOT NULL,
    barcode text,
    barcode_quality numeric,
    hifi_reads bigint,
    hifi_read_length numeric,
    hifi_read_quality text,
    hifi_yield bigint,
    polymerase_read_length numeric
);


--
-- Name: raw_qc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.raw_qc (
    og_id text NOT NULL,
    homozygosity numeric(5,2),
    heterozygosity numeric(5,2),
    genomesize bigint,
    repeatsize bigint,
    uniquesize bigint,
    modelfit numeric(5,2),
    errorrate numeric(5,2),
    contam_reads integer
);


--
-- Name: coverage_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.coverage_summary AS
 WITH hifi_agg AS (
         SELECT hifi_reads_qc.og_id,
            sum(hifi_reads_qc.hifi_yield) AS total_hifi_yield_bp
           FROM public.hifi_reads_qc
          GROUP BY hifi_reads_qc.og_id
        ), hic_agg AS (
         SELECT hic_reads_qc.og_id,
            (sum((hic_reads_qc.yield_gb * (1000000000)::numeric)))::bigint AS total_hic_yield_bp
           FROM public.hic_reads_qc
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
    round(((hic.total_hic_yield_bp)::numeric / '1000000000'::numeric), 3) AS total_hic_yield_gb,
    round((hifi.total_hifi_yield_bp / '1000000000'::numeric), 3) AS total_hifi_yield_gb,
        CASE
            WHEN (r.genomesize > 0) THEN round((hifi.total_hifi_yield_bp / (r.genomesize)::numeric), 2)
            ELSE NULL::numeric
        END AS hifi_coverage,
        CASE
            WHEN (r.genomesize > 0) THEN round(((hic.total_hic_yield_bp)::numeric / (r.genomesize)::numeric), 2)
            ELSE NULL::numeric
        END AS hic_coverage
   FROM (((all_ogs a
     LEFT JOIN hifi_agg hifi ON ((hifi.og_id = a.og_id)))
     LEFT JOIN hic_agg hic ON ((hic.og_id = a.og_id)))
     LEFT JOIN public.raw_qc r ON ((r.og_id = a.og_id)))
  ORDER BY a.og_id;


--
-- Name: design_description; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.design_description (
    design_no integer NOT NULL,
    design_description character varying,
    comment character varying
);


--
-- Name: dna_extraction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dna_extraction (
    dna_id text NOT NULL,
    tissue_id text,
    ext_num integer,
    status text,
    extraction_method text,
    extraction_date text,
    extraction_batch_id text,
    final_buffer text,
    volume integer,
    qubit_conc real,
    nano_drop_conc real,
    ratio_260_280 text,
    ratio_260_230 text,
    ratioqubit_nanodrop real,
    total_yield text,
    gdna_femtol_id text,
    av_size text,
    extraction_qc text,
    comment text,
    dna_freezer text,
    dna_shelf integer,
    dna_rack integer,
    dna_level text,
    dna_box text,
    dna_notes text,
    og_num integer GENERATED ALWAYS AS ((regexp_replace(tissue_id, '[^0-9]'::text, ''::text, 'g'::text))::integer) STORED,
    og_id text GENERATED ALWAYS AS (regexp_replace(tissue_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)) STORED,
    status_overwrite character varying
);


--
-- Name: draft_genomes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_genomes (
    og_id text NOT NULL,
    mach text,
    seq_date text NOT NULL,
    initial text,
    passed_filter_reads bigint,
    low_quality_reads integer,
    too_many_n_reads integer,
    too_short_reads integer,
    too_long_reads integer,
    raw_total_reads bigint,
    raw_total_bases bigint,
    raw_q20_bases bigint,
    raw_q30_bases bigint,
    raw_q20_rate numeric(7,6),
    raw_q30_rate numeric(7,6),
    raw_read1_mean_length integer,
    raw_read2_mean_length integer,
    raw_gc_content numeric(7,6),
    total_reads bigint,
    total_bases bigint,
    q20_bases bigint,
    q30_bases bigint,
    q20_rate numeric(7,6),
    q30_rate numeric(7,6),
    read1_mean_length integer,
    read2_mean_length integer,
    gc_content numeric(7,6),
    homozygosity numeric(5,2),
    heterozygosity numeric(5,2),
    genomesize bigint,
    repeatsize bigint,
    uniquesize bigint,
    modelfit numeric(5,2),
    errorrate numeric(5,2),
    num_contigs integer,
    num_contigs_mitochondrion integer,
    num_contigs_plastid integer,
    num_contigs_prokarya integer,
    bp_mitochondrion bigint,
    bp_plastid bigint,
    bp_prokarya bigint,
    complete numeric(4,1),
    single_copy numeric(4,1),
    multi_copy numeric(4,1),
    fragmented numeric(4,1),
    missing numeric(4,1),
    n_markers integer,
    domain text,
    number_of_scaffolds integer,
    number_of_contigs integer,
    total_length bigint,
    percent_gaps numeric(5,2),
    scaffold_n50 integer,
    contigs_n50 integer,
    unique_k_mers_assembly bigint,
    k_mers_total bigint,
    qv numeric(6,4),
    error numeric(12,11),
    k_mer_set text,
    solid_k_mers bigint,
    total_k_mers bigint,
    completeness numeric(7,4),
    depmethod text,
    adjust text,
    readbp bigint,
    mapadjust numeric(7,6),
    scdepth numeric(5,2),
    estgenomesize bigint,
    aws_r1 text,
    aws_r1_size bigint,
    aws_r2 text,
    aws_r2_size bigint,
    aws_assm text,
    aws_assm_size bigint,
    sra_accession character varying,
    biosample_accession character varying,
    study character varying,
    bioproject_accession character varying,
    comment character varying,
    fastp_r1 text,
    fastp_r1_size bigint,
    fastp_r2 text,
    fastp_r2_size bigint,
    sra_r1 text,
    sra_r1_size bigint,
    sra_r2 text,
    sra_r2_size bigint,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    sra_date_submitted date,
    num_contigs_exclude integer,
    num_contigs_trim integer,
    num_contigs_review integer,
    bp_exclude integer,
    bp_trim integer,
    bp_review integer,
    gfa_num_contigs bigint,
    gfa_contig_n50 bigint,
    gfa_num_scaffolds bigint,
    gfa_scaffold_n50 bigint,
    gfa_largest_scaffold bigint,
    gfa_total_scaffold_length bigint,
    gfa_gc_content_percent numeric(10,2),
    internal_stop_codon_percent numeric(5,2),
    internal_stop_codon_count bigint,
    assembly_accession text
);


--
-- Name: lca_validation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lca_validation (
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
    row_created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sample; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sample (
    og_id text NOT NULL,
    field_id text,
    nominal_species_id text,
    common_name text,
    collector text,
    contact text,
    date_collected date,
    sex text,
    weight text,
    lengthtl_and_lengthfl text,
    country text,
    state text,
    location text,
    latitude_collection text,
    longitude_collection text,
    depth_collection text,
    collection_method text,
    preservation_method text,
    sample_condition text,
    photo_voucher text,
    photo_id text,
    specimen_voucher text,
    voucher_id text,
    comments text,
    priority text,
    tissues text,
    extracted text,
    extraction_queue text,
    ilmn text,
    il_status text,
    hifi text,
    pb_status text,
    hic text,
    hic_status text,
    nano text,
    ont_num text,
    rna text,
    rna_status text,
    ilrna text,
    ilrna_status text,
    assigned_species text,
    eschmeyer_id text,
    ncbi_sample_name text,
    ncbi_biosample_id text,
    hifi_lca_outcome text,
    ncbi_id text,
    tol_id text,
    ncbi_bioproject_id_lvl_3_hifi text,
    bioproject_id_haplotype_1 text,
    bioproject_id_haplotype_2 text,
    bioproject_sequencing_data text,
    ncbi_assembly_upload text,
    ncbi_raw_reads_upload text,
    hifi_public text,
    illumina_lca text,
    ncbi_bioproject_id_draft text,
    illumina_public text,
    draft_sra_accessions text,
    draft_assembly_accession text,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    project_id text,
    workflow character varying,
    illumina_sequencing text,
    hifi_sequencing text,
    hic_sequencing text,
    nanopore_sequencing text,
    rna_ilmn_sequencing text,
    rna_kinnex_sequencing text,
    rna_extraction text,
    summary_comments character varying,
    embargo_status character varying
);


--
-- Name: COLUMN sample.og_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.og_id IS 'Ocean Genomes sample number that links through the whole database.';


--
-- Name: COLUMN sample.hifi_lca_outcome; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.hifi_lca_outcome IS 'Not up to date - use lca_validation table';


--
-- Name: COLUMN sample.illumina_lca; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.illumina_lca IS 'Not up to date - use lca_validation table';


--
-- Name: COLUMN sample.illumina_sequencing; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.illumina_sequencing IS 'Require a Y for if this type of sequencing is to occur';


--
-- Name: COLUMN sample.hifi_sequencing; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.hifi_sequencing IS 'Require a Y for if this type of sequencing is to occur';


--
-- Name: COLUMN sample.hic_sequencing; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.hic_sequencing IS 'Require a Y for if this type of sequencing is to occur';


--
-- Name: COLUMN sample.nanopore_sequencing; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.nanopore_sequencing IS 'Require a Y for if this type of sequencing is to occur';


--
-- Name: COLUMN sample.rna_ilmn_sequencing; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.rna_ilmn_sequencing IS 'Require a Y for if this type of sequencing is to occur';


--
-- Name: COLUMN sample.rna_kinnex_sequencing; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.rna_kinnex_sequencing IS 'Require a Y for if this type of sequencing is to occur';


--
-- Name: COLUMN sample.rna_extraction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.rna_extraction IS 'Require a Y for if this type of sequencing is to occur';


--
-- Name: COLUMN sample.summary_comments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.summary_comments IS 'comments on the status of the samples, different to the metadata comments in the comment column';


--
-- Name: embargo_assignment_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.embargo_assignment_view AS
 SELECT s.og_id,
    (regexp_replace(s.og_id, 'OG'::text, ''::text, 'g'::text))::integer AS og_num,
    s.collector,
    s.embargo_status,
    lv1.validated_species_name,
    s.nominal_species_id,
    s.common_name,
    s.field_id,
    s.contact,
    s.date_collected
   FROM (public.sample s
     LEFT JOIN LATERAL ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS validated_species_name
           FROM public.lca_validation lv
          WHERE (lv.og_id = s.og_id)) lv1 ON (true));


--
-- Name: lca; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lca (
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
    top_percent_match double precision
);


--
-- Name: lca_pivot_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.lca_pivot_view AS
 SELECT (regexp_replace(lca.og_id, 'OG'::text, ''::text, 'g'::text))::integer AS og_num,
    lca.og_id AS og_id_lp,
    lca.tech,
    lca.seq_date,
    lca.code,
    lca.annotation,
    max(lca.species_in_lca) FILTER (WHERE (lca.region = '12s'::text)) AS s12_lca,
    max(lca.species_in_lca) FILTER (WHERE (lca.region = '16s'::text)) AS s16_lca,
    max(lca.species_in_lca) FILTER (WHERE (lca.region = 'CO1'::text)) AS co1_lca
   FROM public.lca
  GROUP BY lca.og_id, lca.tech, lca.seq_date, lca.code, lca.annotation;


--
-- Name: lca_results_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.lca_results_view AS
 SELECT lp.og_id_lp AS og_id_lr,
    lp.tech,
    lp.seq_date,
    lp.code,
    lp.annotation,
    s.nominal_species_id,
    lp.s12_lca,
    lp.s16_lca,
    lp.co1_lca,
        CASE
            WHEN (s.nominal_species_id IS NULL) THEN 'MISSING NOMINAL ID'::text
            WHEN (((s.nominal_species_id = lp.s12_lca) OR (s.nominal_species_id = lp.s16_lca)) OR (s.nominal_species_id = lp.co1_lca)) THEN s.nominal_species_id
            ELSE 'INVESTIGATE'::text
        END AS validation_status
   FROM (public.lca_pivot_view lp
     JOIN public.sample s ON ((lp.og_id_lp = s.og_id)));


--
-- Name: filtered_lca_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.filtered_lca_view AS
 SELECT b.og_id AS og_id_flv,
    b.tech,
    b.seq_date,
    b.code,
    b.annotation,
    string_agg(
        CASE
            WHEN ((b.region = '12s'::text) AND (b.scientific_name = lr.nominal_species_id)) THEN b.match_sequence_id
            ELSE NULL::text
        END, ', '::text ORDER BY b.match_sequence_id) AS filtered_12s,
    string_agg(
        CASE
            WHEN ((b.region = '16s'::text) AND (b.scientific_name = lr.nominal_species_id)) THEN b.match_sequence_id
            ELSE NULL::text
        END, ', '::text ORDER BY b.match_sequence_id) AS filtered_16s,
    string_agg(
        CASE
            WHEN ((b.region = 'CO1'::text) AND (b.scientific_name = lr.nominal_species_id)) THEN b.match_sequence_id
            ELSE NULL::text
        END, ', '::text ORDER BY b.match_sequence_id) AS filtered_co1
   FROM (public.blast_filtered_lca b
     JOIN public.lca_results_view lr ON (((b.og_id = lr.og_id_lr) AND (b.tech = lr.tech) AND (b.seq_date = lr.seq_date) AND (b.code = lr.code) AND (b.annotation = lr.annotation))))
  GROUP BY b.og_id, b.tech, b.seq_date, b.code, b.annotation;


--
-- Name: goat_project_metadata_v1; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.goat_project_metadata_v1 AS
 SELECT 'Ocean Genomes'::text AS project_name,
    'OG'::text AS project_acronym,
    NULL::text AS subproject_name,
    NULL::text AS bioproject_id,
    'Shannon Corrigan'::text AS primary_contact,
    'Ocean Genomes Minderoo OceanOmics Centre, The University of Western Australia'::text AS primary_contact_institution,
    'oceangenomes@uwa.edu.au'::text AS public_contact_email,
    CURRENT_DATE AS date_of_last_update,
    'ebp_species_goat_3.0'::text AS schema_version;


--
-- Name: master_species; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.master_species (
    species text NOT NULL,
    class text,
    ordr text,
    family text,
    genus text,
    epithet text,
    afd_common_name text,
    family_common_name text,
    ncbi_taxon_id integer,
    synonym text,
    specimen_tol_id text,
    sequencing_status text,
    ont text,
    hifi text,
    hic text,
    draft_sequencing_status text,
    illumina text,
    draft_genome_bioproject_id text,
    genome_available text,
    internal_aus_status_fishbase text,
    cites_listing text,
    iucn_code text,
    iucn_assessment text,
    iucn_dateassessed text,
    epbc text,
    internal_first_in_family text,
    internal_first_in_genus text,
    internal_conservation_value text,
    internal_research text,
    internal_endemic text,
    sequencing_priority text,
    collaboration text,
    comments text,
    lab_database_status text
);


--
-- Name: ref_genomes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_genomes (
    og_id text NOT NULL,
    seq_date text NOT NULL,
    stage integer NOT NULL,
    haplotype text NOT NULL,
    num_contigs integer,
    contig_n50 bigint,
    contig_n50_size_mb numeric(10,2),
    num_scaffolds integer,
    scaffold_n50 bigint,
    scaffold_n50_size_mb numeric(10,2),
    largest_scaffold bigint,
    largest_scaffold_size_mb numeric(10,2),
    total_scaffold_length bigint,
    total_scaffold_length_size_mb numeric(10,2),
    gc_content_percent numeric(5,2),
    dataset text,
    complete numeric(4,1),
    single_copy numeric(4,1),
    multi_copy numeric(4,1),
    fragmented numeric(4,1),
    missing numeric(4,1),
    n_markers integer,
    internal_stop_codon_percent numeric(5,2),
    scaffold_n50_bus bigint,
    contigs_n50_bus bigint,
    percent_gaps numeric(5,2),
    number_of_scaffolds integer,
    unique_k_mers_assembly bigint,
    k_mers_total bigint,
    qv numeric(6,4),
    error double precision,
    k_mer_set text,
    solid_k_mers bigint,
    total_k_mers bigint,
    completeness numeric(7,4),
    total bigint,
    total_unmapped bigint,
    total_single_sided_mapped bigint,
    total_mapped bigint,
    total_dups bigint,
    total_nodups bigint,
    cis bigint,
    trans bigint,
    hap2_chr_level_max_len bigint,
    format text,
    type text,
    num_seqs integer,
    sum_len bigint,
    min_len bigint,
    avg_len numeric(20,2),
    max_len bigint,
    num_chromosomes integer,
    pct_assigned numeric(5,2),
    pct_no_super numeric(5,2),
    num_seq_no_super integer,
    max_len_no_super bigint,
    version text NOT NULL,
    num_gaps integer
);


--
-- Name: COLUMN ref_genomes.stage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_genomes.stage IS 'Pulled from file names where 0=contig level, 1=scaffold level, 2=decontaminated scaffold, 3=curated final';


--
-- Name: goat_species_v1; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.goat_species_v1 AS
 SELECT s.ncbi_taxon_id,
    s.family,
    s.species,
    COALESCE(s.epithet, '-'::text) AS subspecies_epithet,
        CASE
            WHEN (s.ncbi_taxon_id = ANY (ARRAY[215367, 182658, 163129, 7793, 582430])) THEN 'priority_target'::text
            ELSE 'potential_target'::text
        END AS target_list_status,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM public.sample samp
              WHERE (samp.nominal_species_id = s.species))) THEN 'sample_collected'::text
            ELSE NULL::text
        END AS sampling_status,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM public.sample samp
              WHERE ((samp.nominal_species_id = s.species) AND (samp.ncbi_bioproject_id_lvl_3_hifi IS NOT NULL)))) THEN 'submitted'::text
            WHEN (EXISTS ( SELECT 1
               FROM (public.sample samp
                 JOIN public.ref_genomes rg ON ((rg.og_id = samp.og_id)))
              WHERE (samp.nominal_species_id = s.species))) THEN 'in_assembly'::text
            WHEN (EXISTS ( SELECT 1
               FROM public.sample samp
              WHERE ((samp.nominal_species_id = s.species) AND (samp.pb_status = ANY (ARRAY['Library Prep - PacBio SMRTbell'::text, 'QC - Femto'::text, 'Sequenced'::text, 'Sequenced, SRE'::text, 'Sequence - PacBio'::text, 'Shearing'::text, 'SRE'::text, 'SRE - ULI'::text, 'ULI'::text]))))) THEN 'in_lab'::text
            ELSE NULL::text
        END AS sequencing_status,
    NULL::text AS genome_publication,
    'Ocean Genomes'::text AS primary_project,
    NULL::text AS ebp_collaborator_acronyms,
    NULL::text AS contributing_project_lab,
        CASE
            WHEN (s.species = ANY (ARRAY['Neophoca cinerea'::text, 'Careproctus sp.'::text, 'Lethrinus punctulatus'::text, 'Siphonognathus radiatus'::text, 'Dascyllus aruanus'::text, 'Carcharhinus galapagensis'::text])) THEN 'data_conflict'::text
            ELSE ( SELECT samp.collector
               FROM public.sample samp
              WHERE ((samp.nominal_species_id = s.species) AND ((samp.workflow)::text = 'Reference'::text) AND (samp.collector IS NOT NULL))
             LIMIT 1)
        END AS collected_by,
    NULL::text AS priority_flags,
    COALESCE(s.afd_common_name, '-'::text) AS common_name,
    COALESCE(s.synonym, '-'::text) AS synonym,
    NULL::text AS assigned_sequencing_center
   FROM public.master_species s
  ORDER BY s.family, s.species;


--
-- Name: hic_library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hic_library (
    hic_library_tube_id text NOT NULL,
    lysate_id text,
    hic_num integer,
    hic_status text,
    library_method text,
    library_date text,
    library_id text,
    prox_ligation_conc real,
    purified_dna_total real,
    index_set text,
    library_conc real,
    library_size integer,
    hic_comments text,
    status_overwrite character varying,
    og_id text GENERATED ALWAYS AS (regexp_replace(lysate_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)) STORED
);


--
-- Name: hic_lysate; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hic_lysate (
    lysate_id text NOT NULL,
    tissue_id text,
    lysate_num integer,
    lysate_status text,
    lysate_prep_date date,
    lysate_batch_id text,
    lysate_conc real,
    total_lysate real,
    lysate_cde real,
    lysate_comments text
);


--
-- Name: illumina_library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.illumina_library (
    illumina_library_tube_id text NOT NULL,
    dna_id text,
    ilmn_num integer,
    ilmn_status text,
    library_method text,
    library_date text,
    library_id text,
    index_set text,
    index_well text,
    index_idx text,
    library_qubit_conc text,
    il_comments text,
    status_overwrite character varying,
    og_id text GENERATED ALWAYS AS (regexp_replace(dna_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)) STORED
);


--
-- Name: lca_old; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lca_old (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    taxonomy text,
    lca text,
    top_percent_match real,
    length integer,
    lca_run_date text,
    region text NOT NULL,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    class text,
    "order" text,
    family text,
    genus text,
    species text,
    coverage real,
    specific_epiphet text,
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
    species_in_lca text,
    number_unq_blast_hits integer,
    domain text,
    phylum text
);


--
-- Name: lca_raw_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lca_raw_results (
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
    confidence_score real
);


--
-- Name: sample_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.sample_view AS
 SELECT s.og_id AS og_id_sv,
    s.project_id AS proj_id,
    s.nominal_species_id AS nom_id,
    s.photo_id AS photo_id_sv,
    s.photo_voucher AS photo_vouch_sv,
    s.specimen_voucher AS specimen_vouch_sv,
    s.voucher_id AS vouch_id_sv
   FROM public.sample s
  WHERE (EXISTS ( SELECT 1
           FROM public.lca_validation lv
          WHERE (lv.og_id = s.og_id)));


--
-- Name: lca_validation_report_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.lca_validation_report_view AS
 SELECT (regexp_replace(lv.og_id, 'OG'::text, ''::text, 'g'::text))::integer AS og_num,
    sv.proj_id,
    lv.og_id,
    lv.tech,
    lv.seq_date,
    lv.code,
    lv.annotation,
    lp.s12_lca,
    lp.s16_lca,
    lp.co1_lca,
    lr.validation_status,
    sv.nom_id,
    lv.validated_species_name,
    lv.validator,
    lv.validator_2,
    lca_tax.lca_taxon_ranks,
    lca_tax.lca_orders,
    lca_tax.lca_families,
    lca_tax.lca_genera,
    lca_tax.lca_specific_epiphets,
        CASE
            WHEN ((flv.filtered_12s IS NOT NULL) OR (flv.filtered_16s IS NOT NULL) OR (flv.filtered_co1 IS NOT NULL)) THEN 'YES'::text
            ELSE NULL::text
        END AS nom_id_in_results,
    lv.nominal_species_id_lca_comment AS comment,
    lv.data_release,
    flv.filtered_12s,
    flv.filtered_16s,
    flv.filtered_co1,
    sv.photo_id_sv,
    sv.photo_vouch_sv,
    sv.specimen_vouch_sv,
    sv.vouch_id_sv
   FROM (((((public.lca_validation lv
     LEFT JOIN public.lca_pivot_view lp ON (((lp.og_id_lp = lv.og_id) AND (lp.tech = lv.tech) AND (lp.seq_date = lv.seq_date) AND (lp.code = (lv.code)::text) AND (lp.annotation = (lv.annotation)::text))))
     LEFT JOIN public.lca_results_view lr ON (((lr.og_id_lr = lv.og_id) AND (lr.tech = lv.tech) AND (lr.seq_date = lv.seq_date) AND (lr.code = (lv.code)::text) AND (lr.annotation = (lv.annotation)::text))))
     LEFT JOIN public.filtered_lca_view flv ON (((flv.og_id_flv = lv.og_id) AND (flv.tech = lv.tech) AND (flv.seq_date = lv.seq_date) AND (flv.code = (lv.code)::text) AND (flv.annotation = (lv.annotation)::text))))
     LEFT JOIN ( SELECT lca.og_id,
            lca.tech,
            lca.seq_date,
            lca.code,
            lca.annotation,
            string_agg(DISTINCT lca.taxon_rank, ', '::text ORDER BY lca.taxon_rank) AS lca_taxon_ranks,
            string_agg(DISTINCT lca."order", ', '::text ORDER BY lca."order") AS lca_orders,
            string_agg(DISTINCT lca.family, ', '::text ORDER BY lca.family) AS lca_families,
            string_agg(DISTINCT lca.genus, ', '::text ORDER BY lca.genus) AS lca_genera,
            string_agg(DISTINCT lca.specific_epiphet, ', '::text ORDER BY lca.specific_epiphet) AS lca_specific_epiphets
           FROM public.lca
          GROUP BY lca.og_id, lca.tech, lca.seq_date, lca.code, lca.annotation) lca_tax ON (((lca_tax.og_id = lv.og_id) AND (lca_tax.tech = lv.tech) AND (lca_tax.seq_date = lv.seq_date) AND (lca_tax.code = (lv.code)::text) AND (lca_tax.annotation = (lv.annotation)::text))))
     LEFT JOIN public.sample_view sv ON ((lv.og_id = sv.og_id_sv)));


--
-- Name: mitogenome_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mitogenome_data (
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
    bankit character varying,
    genbank_accession character varying,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    annotation character varying,
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
    extra_genes character varying,
    missing_genes character varying,
    order_correct character varying,
    passed character varying
);


--
-- Name: ont_library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ont_library (
    ont_library_tube_id text NOT NULL,
    dna_id text,
    ont_num integer,
    ont_status text,
    library_date text,
    library_id text,
    library_method text,
    library_type text,
    est_loading_size integer,
    ont_comments text,
    og_id text GENERATED ALWAYS AS (regexp_replace(dna_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)) STORED,
    status_overwrite character varying
);


--
-- Name: pacbio_library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pacbio_library (
    pacbio_library_tube_id text NOT NULL,
    dna_id text,
    pacb_num integer,
    pacb_status text,
    library_method text,
    library_date text,
    library_id text,
    dna_treatment text,
    index_well text,
    barcode text,
    shear_femtol_id text,
    shear_av_size integer,
    seq_femto_id text,
    seq_av_size real,
    library_conc real,
    comment text,
    status_overwrite character varying,
    og_id text GENERATED ALWAYS AS (regexp_replace(dna_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)) STORED
);


--
-- Name: raw_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.raw_data (
    og_id text,
    run_id text NOT NULL,
    lane_id text NOT NULL,
    filename text NOT NULL,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED
);


--
-- Name: ref_genomes_assembly_uploads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_genomes_assembly_uploads (
    og_id text NOT NULL,
    biosample text,
    bioproject_umbrella text,
    bioproject_hap1 text,
    bioproject_hap2 text,
    bioproject_rawdata text,
    assembly_accession_hap1 text,
    assembly_accession_hap2 text,
    embargo_status text
);


--
-- Name: ref_genomes_sra_uploads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_genomes_sra_uploads (
    srr_accession text NOT NULL,
    og_id text,
    filenames text,
    data_type text,
    ncbi_status text
);


--
-- Name: rna_extraction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rna_extraction (
    rna_id text NOT NULL,
    tissue_id text,
    ext_num integer,
    status text,
    extraction_method text,
    extraction_date date,
    extraction_batch_id text,
    final_buffer text,
    volume integer,
    qubit_conc real,
    nano_drop_conc real,
    ratio_260_280 text,
    ratio_260_230 text,
    total_yield integer,
    tapestation_id text,
    rna_dv200 real,
    rin text,
    extraction_qc text,
    comment text,
    rna_freezer text,
    rna_shelf text,
    rna_rack text,
    rna_level text,
    rna_box text,
    rna_notes text,
    og_id text GENERATED ALWAYS AS (regexp_replace(tissue_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)) STORED,
    status_overwrite character varying
);


--
-- Name: rna_library_ilmn; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rna_library_ilmn (
    rna_library_tube_id text NOT NULL,
    rna_id text,
    rna_num integer,
    rna_status text,
    library_method text,
    library_date text,
    library_id text,
    library_size integer,
    perc_product real,
    library_qubit_conc real,
    library_molarity text,
    index_set text,
    index_well text,
    index_inx text,
    kinnex_primers text,
    kinnex_barcode text,
    comments text,
    og_id text GENERATED ALWAYS AS (regexp_replace(rna_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)) STORED,
    status_overwrite character varying
);


--
-- Name: rna_library_kinx; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rna_library_kinx (
    rna_library_tube_id character varying(50) NOT NULL,
    rna_id character varying(50),
    rna_num integer,
    rna_status character varying(50),
    library_method character varying(100),
    processing_comment text,
    synthesis_date date,
    part1_batch_id character varying(50),
    synthesis_conc real,
    part2_batch_id character varying(50),
    final_qubit_conc real,
    library_size integer,
    kinnex_primers character varying(20),
    kinnex_barcode character varying(20),
    pool_id character varying(50),
    plate integer,
    plate_location character varying(5),
    comments text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    og_id text GENERATED ALWAYS AS (regexp_replace((rna_id)::text, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)) STORED,
    status_overwrite character varying
);


--
-- Name: rna_qc_kinnex; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rna_qc_kinnex (
    rna_tube_id text NOT NULL,
    rna_tube_id_2 text,
    read_count bigint,
    run_id text,
    read_length_mean integer,
    read_length_n50 integer
);


--
-- Name: sequencing; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sequencing (
    sequencing_id text NOT NULL,
    og_id text GENERATED ALWAYS AS ("substring"(sequencing_id, '([A-Z]{2}[0-9]+)'::text)) STORED,
    rna_library_tube_id text,
    illumina_library_tube_id text,
    ont_library_tube_id text,
    pacbio_library_tube_id text,
    hic_library_tube_id text,
    technology text,
    instrument text,
    run_date text,
    run_id text,
    seq_date text GENERATED ALWAYS AS (split_part(run_id, '_'::text, 2)) STORED,
    cell_id text,
    smrt_num integer,
    seq_comments text,
    seq_type text,
    design_no integer,
    og_num integer GENERATED ALWAYS AS (("substring"(sequencing_id, '^OG([0-9]+)'::text))::integer) STORED
);


--
-- Name: species; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.species (
    species text NOT NULL,
    class text,
    ordr text,
    family text,
    genus text,
    epithet text,
    afd_common_name text,
    family_common_name text,
    ncbi_taxon_id integer,
    synonym text,
    specimen_tol_id text,
    sequencing_status text,
    ont text,
    hifi text,
    hic text,
    draft_sequencing_status text,
    illumina text,
    draft_genome_bioproject_id text,
    genome_available text,
    internal_aus_status_fishbase text,
    cites_listing text,
    iucn_code text,
    iucn_assessment text,
    iucn_dateassessed text,
    epbc text,
    internal_first_in_family text,
    internal_first_in_genus text,
    internal_conservation_value text,
    internal_research text,
    internal_endemic text,
    sequencing_priority text,
    collaboration text,
    comments text,
    lab_database_status text
);


--
-- Name: species_ncbi_assembly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.species_ncbi_assembly (
    assembly_accession text NOT NULL,
    species text NOT NULL,
    ncbi_taxon_id integer NOT NULL,
    assembly_name text,
    assembly_level text,
    total_sequence_length bigint,
    is_refseq boolean DEFAULT false NOT NULL,
    is_representative boolean DEFAULT false NOT NULL,
    is_chosen boolean DEFAULT false NOT NULL,
    release_date date,
    retrieved_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: tissue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tissue (
    tissue_id text NOT NULL,
    og_id text,
    field_id text,
    alt_id text,
    tissue text,
    extracted integer,
    freezer text,
    shelf integer,
    rack integer,
    level text,
    box text,
    comment text,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED
);


--
-- Name: summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.summary AS
 SELECT (regexp_replace(s.og_id, 'OG'::text, ''::text, 'g'::text))::integer AS og_num,
    s.og_id,
    s.project_id,
    s.workflow,
    s.priority,
    ( SELECT count(*) AS count
           FROM public.tissue t
          WHERE (t.og_id = s.og_id)) AS tissues,
    ( SELECT count(*) AS count
           FROM public.dna_extraction d
          WHERE ((d.og_id = s.og_id) AND (d.status = 'Extracted'::text))) AS extracted,
    COALESCE(( SELECT d.status
           FROM public.dna_extraction d
          WHERE ((d.og_id = s.og_id) AND ((d.status_overwrite)::text = 'Y'::text))
          ORDER BY d.ext_num DESC
         LIMIT 1), ( SELECT d.status
           FROM public.dna_extraction d
          WHERE (d.og_id = s.og_id)
          ORDER BY d.ext_num DESC
         LIMIT 1), 'Awaiting Status'::text) AS dna_extraction_status,
    s.ilmn AS illumina_sequencing,
        CASE
            WHEN (s.illumina_sequencing = 'N'::text) THEN ''::text
            ELSE COALESCE(( SELECT i.ilmn_status
               FROM public.illumina_library i
              WHERE ((i.og_id = s.og_id) AND ((i.status_overwrite)::text = 'Y'::text))
              ORDER BY i.ilmn_num DESC
             LIMIT 1), ( SELECT i.ilmn_status
               FROM public.illumina_library i
              WHERE (i.og_id = s.og_id)
              ORDER BY i.ilmn_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS illumina_status,
    s.hifi AS hifi_sequencing,
        CASE
            WHEN (s.hifi_sequencing = 'N'::text) THEN ''::text
            ELSE COALESCE(( SELECT p.pacb_status
               FROM public.pacbio_library p
              WHERE ((p.og_id = s.og_id) AND ((p.status_overwrite)::text = 'Y'::text))
              ORDER BY p.pacb_num DESC
             LIMIT 1), ( SELECT p.pacb_status
               FROM public.pacbio_library p
              WHERE (p.og_id = s.og_id)
              ORDER BY p.pacb_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS pacbio_status,
    s.hic AS hic_sequencing,
        CASE
            WHEN (s.hic_sequencing = 'N'::text) THEN ''::text
            ELSE COALESCE(( SELECT h.hic_status
               FROM public.hic_library h
              WHERE ((h.og_id = s.og_id) AND ((h.status_overwrite)::text = 'Y'::text))
              ORDER BY h.hic_num DESC
             LIMIT 1), ( SELECT h.hic_status
               FROM public.hic_library h
              WHERE (h.og_id = s.og_id)
              ORDER BY h.hic_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS hic_status,
    s.nano AS nanopore_sequencing,
        CASE
            WHEN (s.nanopore_sequencing = 'N'::text) THEN ''::text
            ELSE COALESCE(( SELECT o.ont_status
               FROM public.ont_library o
              WHERE ((o.og_id = s.og_id) AND ((o.status_overwrite)::text = 'Y'::text))
              ORDER BY o.ont_num DESC
             LIMIT 1), ( SELECT o.ont_status
               FROM public.ont_library o
              WHERE (o.og_id = s.og_id)
              ORDER BY o.ont_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS nanopore_status,
    s.rna AS rna_extraction,
        CASE
            WHEN (s.rna_extraction = 'N'::text) THEN ''::text
            ELSE COALESCE(( SELECT r.status
               FROM public.rna_extraction r
              WHERE ((r.og_id = s.og_id) AND ((r.status_overwrite)::text = 'Y'::text))
              ORDER BY r.ext_num DESC
             LIMIT 1), ( SELECT r.status
               FROM public.rna_extraction r
              WHERE (r.og_id = s.og_id)
              ORDER BY r.ext_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS rna_extraction_status,
    s.ilrna AS rna_ilmn_sequencing,
        CASE
            WHEN (s.rna_ilmn_sequencing = 'N'::text) THEN ''::text
            ELSE COALESCE(( SELECT ri.rna_status
               FROM public.rna_library_ilmn ri
              WHERE ((ri.og_id = s.og_id) AND ((ri.status_overwrite)::text = 'Y'::text))
              ORDER BY ri.rna_num DESC
             LIMIT 1), ( SELECT ri.rna_status
               FROM public.rna_library_ilmn ri
              WHERE (ri.og_id = s.og_id)
              ORDER BY ri.rna_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS rna_ilmn_status,
    s.rna_kinnex_sequencing,
        CASE
            WHEN (s.rna_kinnex_sequencing = 'N'::text) THEN ''::character varying
            ELSE COALESCE(( SELECT rk.rna_status
               FROM public.rna_library_kinx rk
              WHERE ((rk.og_id = s.og_id) AND ((rk.status_overwrite)::text = 'Y'::text))
              ORDER BY rk.rna_num DESC
             LIMIT 1), ( SELECT rk.rna_status
               FROM public.rna_library_kinx rk
              WHERE (rk.og_id = s.og_id)
              ORDER BY rk.rna_num DESC
             LIMIT 1), 'Awaiting Status'::character varying)
        END AS rna_kinnex_status,
    ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS string_agg
           FROM public.lca_validation lv
          WHERE ((lv.og_id = s.og_id) AND (lv.tech = 'ilmn'::text) AND (lv.validated_species_name IS NOT NULL) AND (lv.validated_species_name <> ''::text))) AS ilmn_validated_species_name,
    ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS string_agg
           FROM public.lca_validation lv
          WHERE ((lv.og_id = s.og_id) AND (lv.tech = 'hifi'::text) AND (lv.validated_species_name IS NOT NULL) AND (lv.validated_species_name <> ''::text))) AS hifi_validated_species_name,
    ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS string_agg
           FROM public.lca_validation lv
          WHERE ((lv.og_id = s.og_id) AND (lv.tech = 'hic'::text) AND (lv.validated_species_name IS NOT NULL) AND (lv.validated_species_name <> ''::text))) AS hic_validated_species_name,
    s.field_id,
    s.nominal_species_id,
    s.common_name,
    s.collector,
    s.contact,
    s.summary_comments
   FROM public.sample s;


--
-- Name: v_genome_size_comparison; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_genome_size_comparison AS
 SELECT d.og_id,
    d.seq_date,
    sp.species,
    sp.ncbi_taxon_id,
    d.genomesize AS estimated_bp,
    a.total_sequence_length AS ncbi_bp,
        CASE
            WHEN (a.total_sequence_length > 0) THEN round(((d.genomesize)::numeric / (a.total_sequence_length)::numeric), 3)
            ELSE NULL::numeric
        END AS estimated_over_ncbi,
    a.assembly_accession,
    a.assembly_level,
    a.is_refseq,
    a.is_representative
   FROM (((public.draft_genomes d
     JOIN public.sample s ON ((s.og_id = d.og_id)))
     JOIN public.species sp ON ((s.nominal_species_id = sp.species)))
     LEFT JOIN public.species_ncbi_assembly a ON (((a.species = sp.species) AND a.is_chosen)));


--
-- Name: dna_extraction DNA_Extraction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dna_extraction
    ADD CONSTRAINT "DNA_Extraction_pkey" PRIMARY KEY (dna_id);


--
-- Name: hic_library HiC_Library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_library
    ADD CONSTRAINT "HiC_Library_pkey" PRIMARY KEY (hic_library_tube_id);


--
-- Name: hic_lysate HiC_Lysate_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_lysate
    ADD CONSTRAINT "HiC_Lysate_pkey" PRIMARY KEY (lysate_id);


--
-- Name: illumina_library Illumina_Library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.illumina_library
    ADD CONSTRAINT "Illumina_Library_pkey" PRIMARY KEY (illumina_library_tube_id);


--
-- Name: ont_library ONT_Library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ont_library
    ADD CONSTRAINT "ONT_Library_pkey" PRIMARY KEY (ont_library_tube_id);


--
-- Name: pacbio_library PacBio_Library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pacbio_library
    ADD CONSTRAINT "PacBio_Library_pkey" PRIMARY KEY (pacbio_library_tube_id);


--
-- Name: rna_extraction RNA_Extraction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_extraction
    ADD CONSTRAINT "RNA_Extraction_pkey" PRIMARY KEY (rna_id);


--
-- Name: rna_library_ilmn RNA_Library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_ilmn
    ADD CONSTRAINT "RNA_Library_pkey" PRIMARY KEY (rna_library_tube_id);


--
-- Name: sample Sample_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sample
    ADD CONSTRAINT "Sample_pkey" PRIMARY KEY (og_id);


--
-- Name: sequencing Sequencing_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sequencing
    ADD CONSTRAINT "Sequencing_pkey" PRIMARY KEY (sequencing_id);


--
-- Name: species Species_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.species
    ADD CONSTRAINT "Species_pkey" PRIMARY KEY (species);


--
-- Name: tissue Tissue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tissue
    ADD CONSTRAINT "Tissue_pkey" PRIMARY KEY (tissue_id);


--
-- Name: blast_filtered_lca blast_filtered_lca_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blast_filtered_lca
    ADD CONSTRAINT blast_filtered_lca_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation, match_sequence_id, region);


--
-- Name: design_description design_description_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.design_description
    ADD CONSTRAINT design_description_pk PRIMARY KEY (design_no);


--
-- Name: draft_genomes draft_genomes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_genomes
    ADD CONSTRAINT draft_genomes_pkey PRIMARY KEY (og_id, seq_date);


--
-- Name: hic_reads_qc hic_reads_qc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_reads_qc
    ADD CONSTRAINT hic_reads_qc_pkey PRIMARY KEY (og_id, tissue, ext_type, lib_code, lane, run_id);


--
-- Name: hifi_reads_qc hifi_reads_qc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hifi_reads_qc
    ADD CONSTRAINT hifi_reads_qc_pkey PRIMARY KEY (og_id, tissue, ext_type, lib_code, run_id);


--
-- Name: lca_raw_results lca_raw_results_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT lca_raw_results_unique UNIQUE (og_id, tech, seq_date, code, annotation, sequence_region, lca_run_date, accession_id);


--
-- Name: lca lca_results_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT lca_results_unique UNIQUE (og_id, tech, seq_date, code, annotation, region, lca_run_date);


--
-- Name: lca_old lca_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_old
    ADD CONSTRAINT lca_unique UNIQUE (og_id, tech, seq_date, code, annotation, region, lca_run_date);


--
-- Name: lca_validation lca_validation_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT lca_validation_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation);


--
-- Name: master_species master_species_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.master_species
    ADD CONSTRAINT master_species_pkey PRIMARY KEY (species);


--
-- Name: mitogenome_data mitogenome_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mitogenome_data
    ADD CONSTRAINT mitogenome_data_pkey PRIMARY KEY (og_id, tech, seq_date, code);


--
-- Name: mitogenome_data mitogenome_data_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mitogenome_data
    ADD CONSTRAINT mitogenome_data_unique UNIQUE (og_id, tech, seq_date, code, annotation);


--
-- Name: raw_data raw_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_data
    ADD CONSTRAINT raw_data_pkey PRIMARY KEY (run_id, lane_id, filename);


--
-- Name: raw_qc raw_qc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_qc
    ADD CONSTRAINT raw_qc_pkey PRIMARY KEY (og_id);


--
-- Name: ref_genomes ref_genomes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_genomes
    ADD CONSTRAINT ref_genomes_pkey PRIMARY KEY (og_id, seq_date, stage, haplotype, version);


--
-- Name: ref_genomes_sra_uploads ref_genomes_sra_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_genomes_sra_uploads
    ADD CONSTRAINT ref_genomes_sra_runs_pkey PRIMARY KEY (srr_accession);


--
-- Name: ref_genomes_assembly_uploads ref_genomes_uploads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_genomes_assembly_uploads
    ADD CONSTRAINT ref_genomes_uploads_pkey PRIMARY KEY (og_id);


--
-- Name: rna_library_kinx rna_library_kinx_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_kinx
    ADD CONSTRAINT rna_library_kinx_pkey PRIMARY KEY (rna_library_tube_id);


--
-- Name: rna_qc_kinnex rna_qc_run_id_tube_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_qc_kinnex
    ADD CONSTRAINT rna_qc_run_id_tube_uniq UNIQUE (run_id, rna_tube_id);


--
-- Name: species_ncbi_assembly species_ncbi_assembly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.species_ncbi_assembly
    ADD CONSTRAINT species_ncbi_assembly_pkey PRIMARY KEY (assembly_accession);


--
-- Name: raw_qc_og_id_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX raw_qc_og_id_uq ON public.raw_qc USING btree (og_id);


--
-- Name: species_ncbi_assembly_one_chosen_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX species_ncbi_assembly_one_chosen_idx ON public.species_ncbi_assembly USING btree (species) WHERE is_chosen;


--
-- Name: species_ncbi_assembly_species_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX species_ncbi_assembly_species_idx ON public.species_ncbi_assembly USING btree (species);


--
-- Name: rna_library_kinx set_updated_at_rna_library_kinx; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_rna_library_kinx BEFORE UPDATE ON public.rna_library_kinx FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: embargo_assignment_view trg_embargo_assignment_view_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_embargo_assignment_view_upd INSTEAD OF UPDATE ON public.embargo_assignment_view FOR EACH ROW EXECUTE FUNCTION public.embargo_assignment_view_upd();


--
-- Name: lca_validation_report_view trg_lca_validation_report_view_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lca_validation_report_view_upd INSTEAD OF UPDATE ON public.lca_validation_report_view FOR EACH ROW EXECUTE FUNCTION public.lca_validation_report_view_upd();


--
-- Name: illumina_library fk_dna_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.illumina_library
    ADD CONSTRAINT fk_dna_id FOREIGN KEY (dna_id) REFERENCES public.dna_extraction(dna_id);


--
-- Name: ont_library fk_dna_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ont_library
    ADD CONSTRAINT fk_dna_id FOREIGN KEY (dna_id) REFERENCES public.dna_extraction(dna_id);


--
-- Name: pacbio_library fk_dna_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pacbio_library
    ADD CONSTRAINT fk_dna_id FOREIGN KEY (dna_id) REFERENCES public.dna_extraction(dna_id);


--
-- Name: sequencing fk_hic_library; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sequencing
    ADD CONSTRAINT fk_hic_library FOREIGN KEY (hic_library_tube_id) REFERENCES public.hic_library(hic_library_tube_id);


--
-- Name: sequencing fk_illumina_library; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sequencing
    ADD CONSTRAINT fk_illumina_library FOREIGN KEY (illumina_library_tube_id) REFERENCES public.illumina_library(illumina_library_tube_id);


--
-- Name: hic_library fk_lysate_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_library
    ADD CONSTRAINT fk_lysate_id FOREIGN KEY (lysate_id) REFERENCES public.hic_lysate(lysate_id);


--
-- Name: lca fk_mitogenome; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


--
-- Name: lca_old fk_mitogenome; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_old
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


--
-- Name: lca_raw_results fk_mitogenome; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


--
-- Name: tissue fk_og_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tissue
    ADD CONSTRAINT fk_og_id FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: sequencing fk_ont_library; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sequencing
    ADD CONSTRAINT fk_ont_library FOREIGN KEY (ont_library_tube_id) REFERENCES public.ont_library(ont_library_tube_id);


--
-- Name: sequencing fk_pacbio_library; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sequencing
    ADD CONSTRAINT fk_pacbio_library FOREIGN KEY (pacbio_library_tube_id) REFERENCES public.pacbio_library(pacbio_library_tube_id);


--
-- Name: rna_library_ilmn fk_rna_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_ilmn
    ADD CONSTRAINT fk_rna_id FOREIGN KEY (rna_id) REFERENCES public.rna_extraction(rna_id);


--
-- Name: dna_extraction fk_tissue_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dna_extraction
    ADD CONSTRAINT fk_tissue_id FOREIGN KEY (tissue_id) REFERENCES public.tissue(tissue_id);


--
-- Name: hic_lysate fk_tissue_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_lysate
    ADD CONSTRAINT fk_tissue_id FOREIGN KEY (tissue_id) REFERENCES public.tissue(tissue_id);


--
-- Name: rna_extraction fk_tissue_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_extraction
    ADD CONSTRAINT fk_tissue_id FOREIGN KEY (tissue_id) REFERENCES public.tissue(tissue_id);


--
-- Name: lca_validation lca_validation_mitogenome_data_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT lca_validation_mitogenome_data_fk FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


--
-- Name: ref_genomes_sra_uploads ref_genomes_sra_runs_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_genomes_sra_uploads
    ADD CONSTRAINT ref_genomes_sra_runs_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.ref_genomes_assembly_uploads(og_id);


--
-- Name: species_ncbi_assembly species_ncbi_assembly_species_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.species_ncbi_assembly
    ADD CONSTRAINT species_ncbi_assembly_species_fkey FOREIGN KEY (species) REFERENCES public.species(species);


--
-- PostgreSQL database dump complete
--

\unrestrict CnAkqeSOaB5UHk0p9jwiSNKSbrHsGIOVfI41xmFhMJroxoABEdfkghLBYY9XV2V

