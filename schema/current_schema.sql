--
-- PostgreSQL database dump
--

\restrict STZx71VRqY58TfCavK58QK80a7wFuDUEBxcrQ8Z9MmHRvEQNzjROurz1b8FqQrE

-- Dumped from database version 14.24 (Ubuntu 14.24-0ubuntu0.22.04.1)
-- Dumped by pg_dump version 14.24 (Ubuntu 14.24-0ubuntu0.22.04.1)

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
  '/scratch/pawsey0964/edejong/ref-gen/'||p.og_id||'/hifi' AS hifi_dir,
  '/scratch/pawsey0964/edejong/ref-gen/'||p.og_id||'/hic'                  AS hic_dir,
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
    AS $_$
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
),
-- Highest hic version recorded for each OG (hic2 beats hic1, hic10 beats hic9).
-- seq_date is carried along so date and version always come from the same assembly.
latest_hic AS (
  SELECT DISTINCT ON (rg.og_id)
         rg.og_id,
         rg.version,
         rg.seq_date
  FROM ref_genomes rg
  JOIN p ON rg.og_id = p.og_id
  WHERE rg.version ~ '^hic[0-9]+$'
  ORDER BY rg.og_id,
           substring(rg.version from '[0-9]+$')::int DESC,
           rg.seq_date DESC
)
SELECT DISTINCT ON (p.og_id)
  p.og_id                                 AS sample,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/hic'      AS hic_dir,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/assembly' AS assembly,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/meryl'    AS meryldb,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/agp'      AS agp,
  COALESCE(lh.version, 'hic1')            AS version,
  COALESCE(
    CASE
      WHEN lh.seq_date ~ '^[0-9]{6}$' THEN 'v' || lh.seq_date
    END,
    CASE
      WHEN ls.seq_date IS NOT NULL
      THEN 'v' || to_char(ls.seq_date, 'YYMMDD')
    END
  )                                       AS date,
  gs.genome_size                          AS genomesize
FROM p
LEFT JOIN latest_hic lh ON lh.og_id = p.og_id
LEFT JOIN latest_seq ls ON ls.og_id = p.og_id
LEFT JOIN gen_sz gs     ON gs.og_id = p.og_id
ORDER BY p.og_id;
$_$;


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
-- Name: lca_set_content_hash(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lca_set_content_hash() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.content_hash := md5(
        (to_jsonb(NEW) - 'lca_run_date' - 'og_num' - 'content_hash')::text
    );
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
    blast_run_date text
);


--
-- Name: COLUMN blast_filtered_lca.taxon_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.blast_filtered_lca.taxon_id IS 'BLAST staxids for the matched accession, verbatim. Usually a single NCBI taxon id, but a '';''-joined list when the accession is registered under more than one taxon -- cast it before using it as a number.';


--
-- Name: blast_filtered_lca_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."blast_filtered_lca_SS260818" (
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
-- Name: data_package_artifact; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_package_artifact (
    id bigint NOT NULL,
    delivery_id bigint NOT NULL,
    component_id bigint,
    batch_number integer,
    artifact_type text NOT NULL,
    filename text NOT NULL,
    local_path text,
    remote_path text,
    size_bytes bigint DEFAULT 0 NOT NULL,
    sha256 text,
    status text DEFAULT 'planned'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    uploaded_at timestamp with time zone,
    verified_at timestamp with time zone,
    error_text text,
    CONSTRAINT data_package_artifact_size_bytes_check CHECK ((size_bytes >= 0))
);


--
-- Name: data_package_artifact_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.data_package_artifact ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_artifact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_package_component; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_package_component (
    id bigint NOT NULL,
    delivery_id bigint NOT NULL,
    component_type text NOT NULL,
    status text NOT NULL,
    requested_count integer DEFAULT 0 NOT NULL,
    eligible_count integer DEFAULT 0 NOT NULL,
    included_count integer DEFAULT 0 NOT NULL,
    excluded_count integer DEFAULT 0 NOT NULL,
    warning_count integer DEFAULT 0 NOT NULL,
    validation_result text,
    validation_report text,
    inventory_digest text,
    approved_by text,
    approved_at timestamp with time zone,
    approval_note text,
    override_used boolean DEFAULT false NOT NULL,
    override_reason text,
    pending_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT data_package_component_check CHECK (((NOT override_used) OR (NULLIF(btrim(override_reason), ''::text) IS NOT NULL))),
    CONSTRAINT data_package_component_component_type_check CHECK ((component_type = ANY (ARRAY['reference'::text, 'draft'::text, 'mito'::text])))
);


--
-- Name: data_package_component_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.data_package_component ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_component_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_package_delivery; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_package_delivery (
    id bigint NOT NULL,
    project_id text NOT NULL,
    run_id text NOT NULL,
    delivery_version integer NOT NULL,
    status text NOT NULL,
    is_partial boolean DEFAULT false NOT NULL,
    created_by text NOT NULL,
    repository_revisions jsonb DEFAULT '{}'::jsonb NOT NULL,
    manifest_digest text,
    archive_count integer DEFAULT 0 NOT NULL,
    total_bytes bigint DEFAULT 0 NOT NULL,
    remote_prefix text,
    approved_at timestamp with time zone,
    packaged_at timestamp with time zone,
    uploaded_at timestamp with time zone,
    links_generated_at timestamp with time zone,
    email_accepted_at timestamp with time zone,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT data_package_delivery_archive_count_check CHECK ((archive_count >= 0)),
    CONSTRAINT data_package_delivery_delivery_version_check CHECK ((delivery_version > 0)),
    CONSTRAINT data_package_delivery_project_id_check CHECK ((project_id ~ '^OGP[0-9]+'::text)),
    CONSTRAINT data_package_delivery_total_bytes_check CHECK ((total_bytes >= 0))
);


--
-- Name: data_package_delivery_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.data_package_delivery ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_delivery_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_package_email; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_package_email (
    id bigint NOT NULL,
    delivery_id bigint NOT NULL,
    link_set_id bigint NOT NULL,
    preview_id text NOT NULL,
    content_digest text NOT NULL,
    status text NOT NULL,
    sender text NOT NULL,
    reply_to text,
    subject text NOT NULL,
    text_body text NOT NULL,
    html_body text,
    message_id text,
    previewed_by text NOT NULL,
    sent_by text,
    transport text,
    transport_exit_status integer,
    error_text text,
    previewed_at timestamp with time zone DEFAULT now() NOT NULL,
    confirmed_at timestamp with time zone,
    submitted_at timestamp with time zone,
    accepted_at timestamp with time zone
);


--
-- Name: data_package_email_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.data_package_email ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_email_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_package_email_recipient; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_package_email_recipient (
    id bigint NOT NULL,
    email_id bigint NOT NULL,
    contact_id bigint,
    recipient_role text NOT NULL,
    display_name text NOT NULL,
    organisation text,
    email text NOT NULL,
    CONSTRAINT data_package_email_recipient_recipient_role_check CHECK ((recipient_role = ANY (ARRAY['to'::text, 'cc'::text, 'bcc'::text])))
);


--
-- Name: data_package_email_recipient_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.data_package_email_recipient ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_email_recipient_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_package_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_package_item (
    id bigint NOT NULL,
    component_id bigint NOT NULL,
    og_id text NOT NULL,
    seq_id text DEFAULT ''::text NOT NULL,
    disposition text NOT NULL,
    validation_result text,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT data_package_item_disposition_check CHECK ((disposition = ANY (ARRAY['included'::text, 'excluded'::text, 'pending'::text])))
);


--
-- Name: data_package_item_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.data_package_item ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_package_link_set; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_package_link_set (
    id bigint NOT NULL,
    delivery_id bigint NOT NULL,
    previous_link_set_id bigint,
    status text NOT NULL,
    requested_expiry text NOT NULL,
    effective_expiry text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    links jsonb NOT NULL,
    manifest_path text NOT NULL,
    generated_by text NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    error_text text
);


--
-- Name: data_package_link_set_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.data_package_link_set ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_link_set_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
    homozygosity numeric(8,4),
    heterozygosity numeric(8,4),
    genomesize bigint,
    repeatsize bigint,
    uniquesize bigint,
    modelfit numeric(8,4),
    errorrate numeric(8,4),
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
    ena_analysis_accession text,
    assembly_accession text,
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
    genomesize_min bigint,
    repeatsize_min bigint,
    uniquesize_min bigint,
    homozygosity_min numeric(8,4),
    heterozygosity_min numeric(8,4),
    modelfit_allkmers numeric(8,4),
    genome_size_reliable boolean,
    genome_size_flags text,
    kmercov numeric(10,4),
    lambda_depth numeric(10,4),
    host_assembly_size bigint,
    host_assembly_fraction numeric
);


--
-- Name: COLUMN draft_genomes.ena_analysis_accession; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomes.ena_analysis_accession IS 'ENA analysis (ERZ) accession from the Webin-CLI assembly receipt; written by ENA-draft-genomes step 06';


--
-- Name: COLUMN draft_genomes.assembly_accession; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomes.assembly_accession IS 'Public INSDC assembly accession (GCA_...) assigned once the ERZ is processed; filled by ENA-draft-genomes workflow/07_resolve_gca_accessions.py. Previously held NCBI JB... accessions.';


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
    row_created_on timestamp with time zone DEFAULT now() NOT NULL,
    validated_rank text,
    lca_genus text
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
-- Name: ena_candidate_loci_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ena_candidate_loci_archive (
    full_seqid text,
    og_id text,
    gene_serial integer,
    locus_tag text,
    feature_key text,
    start_coordinate integer,
    end_coordinate integer,
    strand character(1),
    created_at timestamp with time zone
);


--
-- Name: TABLE ena_candidate_loci_archive; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ena_candidate_loci_archive IS 'Frozen copy of ena_candidate_loci as of migration 010. Records the per-candidate locus tags this pipeline submitted before locus-tag assignment moved to the downstream submission pipeline. Historical reference only.';


--
-- Name: ena_locus_registry_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ena_locus_registry_archive (
    og_id text,
    gene_serial integer,
    canonical_gene text,
    gene_occurrence integer,
    feature_type text,
    strand character(1),
    feature_sequence_sha256 character(64),
    coordinate_snapshot text,
    allocation_status text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


--
-- Name: TABLE ena_locus_registry_archive; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ena_locus_registry_archive IS 'Frozen copy of ena_locus_registry as of migration 010. Records the specimen gene serials this pipeline allocated before locus-tag assignment moved to the downstream submission pipeline. Historical reference only: do not write to it and do not treat it as the current tag assignment.';


--
-- Name: ena_related_assemblies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ena_related_assemblies (
    id bigint NOT NULL,
    og_id text NOT NULL,
    relationship_type text NOT NULL,
    archive text NOT NULL,
    accession text NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    accession_source text,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ena_related_archive_check CHECK ((archive = ANY (ARRAY['ENA'::text, 'NCBI'::text, 'OTHER'::text]))),
    CONSTRAINT ena_related_relationship_check CHECK ((relationship_type = ANY (ARRAY['reference'::text, 'draft'::text])))
);


--
-- Name: ena_related_assemblies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ena_related_assemblies ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ena_related_assemblies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ena_specimen_accessions; Type: TABLE; Schema: public; Owner: -
--

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


--
-- Name: ena_submissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ena_submissions (
    full_seqid text NOT NULL,
    webin_mode text DEFAULT 'production'::text NOT NULL,
    og_id text GENERATED ALWAYS AS (split_part(full_seqid, '.'::text, 1)) STORED,
    tech text GENERATED ALWAYS AS (split_part(full_seqid, '.'::text, 2)) STORED,
    seq_date text GENERATED ALWAYS AS (split_part(full_seqid, '.'::text, 3)) STORED,
    code text GENERATED ALWAYS AS (split_part(full_seqid, '.'::text, 4)) STORED,
    annotation text GENERATED ALWAYS AS ("substring"(full_seqid, '^(?:[^.]+[.]){4}(.+)$'::text)) STORED,
    submission_status text DEFAULT 'NOT_SUBMITTED'::text NOT NULL,
    submitted_at timestamp with time zone,
    submitted_by text,
    error_message text,
    receipt_path text,
    receipt_sha256 character(64),
    webin_cli_version text,
    ena_study_accession text,
    ena_sample_accession text,
    ena_analysis_accession text,
    ena_assembly_accession text,
    ena_sequence_accession text,
    biosample_accession text,
    biosample_source text,
    locus_tag_prefix text,
    run_accessions text[],
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ena_submissions_accession_presence_check CHECK (((submission_status <> 'ACCESSION_ASSIGNED'::text) OR (ena_analysis_accession IS NOT NULL))),
    CONSTRAINT ena_submissions_analysis_accession_check CHECK (((ena_analysis_accession IS NULL) OR (ena_analysis_accession ~ '^ERZ[0-9]+$'::text))),
    CONSTRAINT ena_submissions_assembly_accession_check CHECK (((ena_assembly_accession IS NULL) OR (ena_assembly_accession ~ '^GCA_[0-9]{9}[.][0-9]+$'::text))),
    CONSTRAINT ena_submissions_biosample_check CHECK (((biosample_accession IS NULL) OR (biosample_accession ~ '^SAM(EA|N|D)[0-9]+$'::text))),
    CONSTRAINT ena_submissions_failure_reason_check CHECK (((submission_status <> 'FAILED'::text) OR (error_message IS NOT NULL))),
    CONSTRAINT ena_submissions_full_seqid_check CHECK ((full_seqid ~ '^OG[0-9]+[.][A-Za-z0-9._-]+$'::text)),
    CONSTRAINT ena_submissions_locus_tag_prefix_check CHECK (((locus_tag_prefix IS NULL) OR (locus_tag_prefix ~ '^[A-Z][A-Z0-9]{2,11}$'::text))),
    CONSTRAINT ena_submissions_receipt_digest_check CHECK (((receipt_sha256 IS NULL) OR (receipt_sha256 ~ '^[0-9a-f]{64}$'::text))),
    CONSTRAINT ena_submissions_run_accessions_check CHECK (((run_accessions IS NULL) OR (array_to_string(run_accessions, ' '::text) ~ '^((ERR|SRR|DRR)[0-9]+( |$))*$'::text))),
    CONSTRAINT ena_submissions_sample_accession_check CHECK (((ena_sample_accession IS NULL) OR (ena_sample_accession ~ '^ERS[0-9]+$'::text))),
    CONSTRAINT ena_submissions_sequence_accession_check CHECK (((ena_sequence_accession IS NULL) OR (ena_sequence_accession ~ '^[A-Z]{2}[0-9]{6,8}([.][0-9]+)?$'::text))),
    CONSTRAINT ena_submissions_status_check CHECK ((submission_status = ANY (ARRAY['NOT_SUBMITTED'::text, 'SUBMITTED'::text, 'ACCESSION_ASSIGNED'::text, 'FAILED'::text]))),
    CONSTRAINT ena_submissions_study_accession_check CHECK (((ena_study_accession IS NULL) OR (ena_study_accession ~ '^PRJEB[0-9]+$'::text))),
    CONSTRAINT ena_submissions_submitted_at_check CHECK (((submission_status <> ALL (ARRAY['SUBMITTED'::text, 'ACCESSION_ASSIGNED'::text])) OR (submitted_at IS NOT NULL))),
    CONSTRAINT ena_submissions_webin_mode_check CHECK ((webin_mode = ANY (ARRAY['production'::text, 'test'::text])))
);


--
-- Name: TABLE ena_submissions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ena_submissions IS 'Submission ledger, written by the downstream ENA submission pipeline. This pipeline never writes or reads it: validation does not depend on submission state.';


--
-- Name: COLUMN ena_submissions.webin_mode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_submissions.webin_mode IS 'Which Webin service answered: production or test. Part of the key so a dry run cannot overwrite the production record.';


--
-- Name: COLUMN ena_submissions.biosample_accession; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_submissions.biosample_accession IS 'The BioSample the manifest actually carried. SAMN means the specimen is registered at NCBI only, which webin-cli cannot resolve (see sql/007).';


--
-- Name: COLUMN ena_submissions.biosample_source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_submissions.biosample_source IS 'Where that accession came from, e.g. sample.ncbi_biosample_id or webin_sample_receipt.';


--
-- Name: COLUMN ena_submissions.run_accessions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_submissions.run_accessions IS 'Raw-read runs the assembly came from, as ERR/SRR/DRR accessions.';


--
-- Name: ena_validation_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ena_validation_attempts (
    id bigint NOT NULL,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    full_seqid text NOT NULL,
    og_id text NOT NULL,
    tech text,
    seq_date text,
    code text,
    annotation text,
    ena_study text DEFAULT ''::text NOT NULL,
    validation_mode text NOT NULL,
    validation_attempt text NOT NULL,
    table2asn_status text NOT NULL,
    reject_count integer,
    error_count integer,
    warning_count integer,
    info_count integer,
    fatal_discrepancy_count integer,
    nostop_count integer,
    blocking_codes text,
    warning_codes text,
    conversion_status text NOT NULL,
    conversion_reason text,
    conversion_exit integer,
    preflight_status text NOT NULL,
    preflight_reason text,
    preflight_exit integer,
    webin_status text NOT NULL,
    webin_reason text,
    webin_exit integer,
    submission_ready boolean DEFAULT false NOT NULL,
    recorded_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    attempt_count integer DEFAULT 1 NOT NULL,
    CONSTRAINT ena_validation_submission_ready_check CHECK (((NOT submission_ready) OR (webin_status = 'PASS'::text)))
);


--
-- Name: COLUMN ena_validation_attempts.og_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_validation_attempts.og_num IS 'Numeric part of og_id, maintained by the database. Generated, not writable: do not include it in any INSERT or UPDATE column list.';


--
-- Name: ena_submission_status; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ena_submission_status AS
 WITH latest AS (
         SELECT DISTINCT ON (ena_validation_attempts.full_seqid) ena_validation_attempts.id,
            ena_validation_attempts.full_seqid,
            ena_validation_attempts.og_id,
            ena_validation_attempts.tech,
            ena_validation_attempts.seq_date,
            ena_validation_attempts.code,
            ena_validation_attempts.annotation,
            ena_validation_attempts.ena_study,
            ena_validation_attempts.validation_mode,
            ena_validation_attempts.validation_attempt,
            ena_validation_attempts.table2asn_status,
            ena_validation_attempts.reject_count,
            ena_validation_attempts.error_count,
            ena_validation_attempts.warning_count,
            ena_validation_attempts.info_count,
            ena_validation_attempts.fatal_discrepancy_count,
            ena_validation_attempts.nostop_count,
            ena_validation_attempts.blocking_codes,
            ena_validation_attempts.warning_codes,
            ena_validation_attempts.conversion_status,
            ena_validation_attempts.conversion_reason,
            ena_validation_attempts.conversion_exit,
            ena_validation_attempts.preflight_status,
            ena_validation_attempts.preflight_reason,
            ena_validation_attempts.preflight_exit,
            ena_validation_attempts.webin_status,
            ena_validation_attempts.webin_reason,
            ena_validation_attempts.webin_exit,
            ena_validation_attempts.submission_ready,
            ena_validation_attempts.recorded_at,
            ena_validation_attempts.attempt_count
           FROM public.ena_validation_attempts
          ORDER BY ena_validation_attempts.full_seqid, ena_validation_attempts.recorded_at DESC, ena_validation_attempts.id DESC
        )
 SELECT v.full_seqid,
    v.og_id,
    v.tech,
    v.seq_date,
    v.code,
    v.annotation,
    v.ena_study,
    v.webin_status,
    v.submission_ready,
    v.recorded_at AS validated_at,
    COALESCE(s.submission_status, 'NOT_SUBMITTED'::text) AS submission_status,
    s.ena_analysis_accession,
    s.ena_assembly_accession,
    s.ena_sequence_accession,
    s.biosample_accession,
    s.locus_tag_prefix,
    s.submitted_at,
    s.receipt_path
   FROM (latest v
     LEFT JOIN public.ena_submissions s ON (((s.full_seqid = v.full_seqid) AND (s.webin_mode = 'production'::text))));


--
-- Name: ena_validation_attempts_new_id_seq1; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ena_validation_attempts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ena_validation_attempts_new_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ena_validation_latest; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ena_validation_latest AS
 SELECT DISTINCT ON (ena_validation_attempts.full_seqid) ena_validation_attempts.id,
    ena_validation_attempts.og_num,
    ena_validation_attempts.full_seqid,
    ena_validation_attempts.og_id,
    ena_validation_attempts.tech,
    ena_validation_attempts.seq_date,
    ena_validation_attempts.code,
    ena_validation_attempts.annotation,
    ena_validation_attempts.ena_study,
    ena_validation_attempts.validation_mode,
    ena_validation_attempts.validation_attempt,
    ena_validation_attempts.table2asn_status,
    ena_validation_attempts.reject_count,
    ena_validation_attempts.error_count,
    ena_validation_attempts.warning_count,
    ena_validation_attempts.info_count,
    ena_validation_attempts.fatal_discrepancy_count,
    ena_validation_attempts.nostop_count,
    ena_validation_attempts.blocking_codes,
    ena_validation_attempts.warning_codes,
    ena_validation_attempts.conversion_status,
    ena_validation_attempts.conversion_reason,
    ena_validation_attempts.conversion_exit,
    ena_validation_attempts.preflight_status,
    ena_validation_attempts.preflight_reason,
    ena_validation_attempts.preflight_exit,
    ena_validation_attempts.webin_status,
    ena_validation_attempts.webin_reason,
    ena_validation_attempts.webin_exit,
    ena_validation_attempts.submission_ready,
    ena_validation_attempts.recorded_at,
    ena_validation_attempts.attempt_count
   FROM public.ena_validation_attempts
  ORDER BY ena_validation_attempts.full_seqid, ena_validation_attempts.recorded_at DESC, ena_validation_attempts.id DESC;


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
    top_confidence_score double precision,
    top_percent_match double precision,
    taxon_rank_db text,
    content_hash text NOT NULL
);


--
-- Name: COLUMN lca.top_confidence_score; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lca.top_confidence_score IS 'double precision, not real: LCA confidence values reach ~1e-163, far below the ~1.18e-38 floor of real.';


--
-- Name: COLUMN lca.taxon_rank_db; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lca.taxon_rank_db IS 'Taxonomic rank as reported by the reference database, as opposed to taxon_rank, which is the rank the LCA itself resolved to.';


--
-- Name: COLUMN lca.content_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lca.content_hash IS 'md5 of the row minus lca_run_date, og_num and content_hash, maintained by the lca_content_hash trigger. Do not include it in any INSERT or UPDATE column list.';


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
    synonym text,
    ncbi_name text,
    ncbi_taxon_id integer,
    class text,
    ordr text,
    family text,
    family_common_name text,
    genus text,
    epithet text,
    afd_common_name text,
    sequencing_status text,
    genome_available text,
    contig_n50 text,
    reference_workflow text,
    draft_workflow text,
    unnassigned_workflow text,
    og_count integer,
    flash_frozen_count integer,
    archival_count integer,
    aus_status_fishbase text,
    cites_listing text,
    iucn_code text,
    epbc text,
    internal_first_in_family text,
    internal_first_in_genus text,
    internal_conservation_value text,
    internal_research text,
    internal_endemic text,
    collaboration text,
    comments text
);


--
-- Name: COLUMN master_species.species; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.species IS 'Scientific species name. Master species identifier.';


--
-- Name: COLUMN master_species.synonym; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.synonym IS 'Known taxonomic synonym(s) previously used for this species.';


--
-- Name: COLUMN master_species.ncbi_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.ncbi_name IS 'Scientific name as recognised by NCBI Taxonomy for this species (may differ from species where naming diverges).';


--
-- Name: COLUMN master_species.ncbi_taxon_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.ncbi_taxon_id IS 'NCBI Taxonomy ID, looked up from NCBI Taxonomy (https://www.ncbi.nlm.nih.gov/taxonomy) by scientific name. Only fills NULL values - an existing ID is never overwritten automatically; a mismatch is reported for manual review (CSV + optional email) rather than changed. Automatically checked quarterly (1 Jan/Apr/Jul/Oct, 02:00).';


--
-- Name: COLUMN master_species.class; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.class IS 'Taxonomic class of the species.';


--
-- Name: COLUMN master_species.ordr; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.ordr IS 'Taxonomic order of the species (named "ordr" to avoid the reserved SQL keyword "order").';


--
-- Name: COLUMN master_species.family; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.family IS 'Taxonomic family of the species.';


--
-- Name: COLUMN master_species.family_common_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.family_common_name IS 'Common name at the family level (as distinct from afd_common_name, which is species-level).';


--
-- Name: COLUMN master_species.genus; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.genus IS 'Taxonomic genus of the species.';


--
-- Name: COLUMN master_species.epithet; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.epithet IS 'Specific epithet - the species part of the binomial scientific name.';


--
-- Name: COLUMN master_species.afd_common_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.afd_common_name IS 'Common name(s) for the species, from an Australian Faunal Directory (AFD) Common Names export (https://biodiversity.org.au/afd/, export tool: https://test-afd.biodiversity.org.au/nsl/services/export/index), matched to master_species.species after stripping taxonomic authority. Multiple names are joined with ''; ''. Need updated manually whenever a new AFD export is downloaded and processed.';


--
-- Name: COLUMN master_species.sequencing_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.sequencing_status IS 'Derived from OceanOmics DB tables sample and ref_genomes (matched via sample.nominal_species_id = master_species.species). Priority: ''submitted'' if sample.ncbi_bioproject_id_lvl_3_hifi is set; else ''in_assembly'' if a matching sample.og_id exists in ref_genomes; else ''in_lab'' if sample.pb_status is one of the defined PacBio lab statuses; else NULL. Automatically update quarterly (1 Jan/Apr/Jul/Oct, 02:00).';


--
-- Name: COLUMN master_species.genome_available; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.genome_available IS 'Best available NCBI genome assembly level for the species, from NCBI Datasets (https://www.ncbi.nlm.nih.gov/datasets/genome/), matched via NCBI TaxID. ''reference'' = Complete Genome/Chromosome; ''draft'' = Scaffold/Contig; NULL = no NCBI assembly. Automatically update monthly (1st of month, 06:00).';


--
-- Name: COLUMN master_species.contig_n50; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.contig_n50 IS 'Contig N50 assembly-quality metric (contig length at which 50% of the assembly is contained in contigs that size or longer - higher means a more contiguous assembly) for the same best NCBI assembly used for genome_available, from NCBI Datasets (https://www.ncbi.nlm.nih.gov/datasets/genome/). Shown as a human-readable value, e.g. "57.9 Mb". NULL if there is no NCBI assembly. Automatically update monthly (1st of month, 06:00).';


--
-- Name: COLUMN master_species.reference_workflow; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.reference_workflow IS 'Comma-separated list of OG IDs (sample.og_id) for this species'' samples currently at the ''Reference'' stage of the internal assembly workflow (sample.workflow = ''Reference''). Automatically update weekly (Saturday, 05:00).';


--
-- Name: COLUMN master_species.draft_workflow; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.draft_workflow IS 'Comma-separated list of OG IDs (sample.og_id) for this species'' samples at the ''Draft'' workflow stage (sample.workflow = ''Draft''). Automatically update weekly (Saturday, 05:00).';


--
-- Name: COLUMN master_species.unnassigned_workflow; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.unnassigned_workflow IS 'Comma-separated list of OG IDs (sample.og_id) for this species'' samples with no workflow stage assigned yet (sample.workflow = ''Not assigned''). Automatically update weekly (Saturday, 05:00).';


--
-- Name: COLUMN master_species.og_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.og_count IS 'Total number of unique OG (Ocean Genome) specimens for the species, from sample.og_id (sample.nominal_species_id = master_species.species). Automatically update weekly (Saturday, 05:00).';


--
-- Name: COLUMN master_species.flash_frozen_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.flash_frozen_count IS 'Number of unique OG specimens with sample.preservation_method in (''Flash Frozen'', ''Flash Frozen (-80C)'', ''Flash Frozen (LN2)'', ''Frozen -80'', ''Other preservation - Matt McGee'', ''Snap frozen''). Automatically update weekly (Saturday, 05:00).';


--
-- Name: COLUMN master_species.archival_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.archival_count IS 'Number of unique OG specimens with any preservation type other than the flash-frozen set used for flash_frozen_count (including NULL). Automatically update weekly (Saturday, 05:00).';


--
-- Name: COLUMN master_species.aus_status_fishbase; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.aus_status_fishbase IS 'Australian occurrence status (native/endemic/introduced/etc.), from the FishBase Australia checklist (https://www.fishbase.se), matched to master_species.species. Automatically update annually (2 January, 09:00).';


--
-- Name: COLUMN master_species.cites_listing; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.cites_listing IS 'Current CITES Appendix listing, from CITES Species+ (https://speciesplus.net/), matched to master_species.species by scientific name. The CITES Trade Database is deliberately not used, as trade records do not reflect current legal listing status. Automatically update monthly (1st of month, 02:00).';


--
-- Name: COLUMN master_species.iucn_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.iucn_code IS 'IUCN Red List conservation category, from the IUCN Red List API (https://api.iucnredlist.org/), matched on taxon_scientific_name = master_species.species using each species'' latest assessment. Automatically update annually (2 January, 15:00).';


--
-- Name: COLUMN master_species.epbc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.epbc IS 'Not yet implemented. Intended to hold the Australian Government EPBC Act conservation listing. Source and update method not yet finalised.';


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
-- Name: lca_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."lca_SS260818" (
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
-- Name: lca_pivot_view_SS260818; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public."lca_pivot_view_SS260818" AS
 SELECT (regexp_replace("lca_SS260818".og_id, 'OG'::text, ''::text, 'g'::text))::integer AS og_num,
    "lca_SS260818".og_id AS og_id_lp,
    "lca_SS260818".tech,
    "lca_SS260818".seq_date,
    "lca_SS260818".code,
    "lca_SS260818".annotation,
    max("lca_SS260818".species_in_lca) FILTER (WHERE ("lca_SS260818".region = '12s'::text)) AS s12_lca,
    max("lca_SS260818".species_in_lca) FILTER (WHERE ("lca_SS260818".region = '16s'::text)) AS s16_lca,
    max("lca_SS260818".species_in_lca) FILTER (WHERE ("lca_SS260818".region = 'CO1'::text)) AS co1_lca
   FROM public."lca_SS260818"
  GROUP BY "lca_SS260818".og_id, "lca_SS260818".tech, "lca_SS260818".seq_date, "lca_SS260818".code, "lca_SS260818".annotation;


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
    confidence_score double precision,
    taxon_rank_db text,
    content_hash text NOT NULL
);


--
-- Name: COLUMN lca_raw_results.confidence_score; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lca_raw_results.confidence_score IS 'double precision, not real: LCA confidence values reach ~1e-163, far below the ~1.18e-38 floor of real.';


--
-- Name: COLUMN lca_raw_results.taxon_rank_db; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lca_raw_results.taxon_rank_db IS 'Taxonomic rank as reported by the reference database for this hit.';


--
-- Name: COLUMN lca_raw_results.content_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lca_raw_results.content_hash IS 'md5 of the row minus lca_run_date, og_num and content_hash, maintained by the lca_raw_results_content_hash trigger. Do not include it in any INSERT or UPDATE column list.';


--
-- Name: lca_raw_results_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."lca_raw_results_SS260818" (
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
-- Name: lca_results_view_SS260818; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public."lca_results_view_SS260818" AS
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
   FROM (public."lca_pivot_view_SS260818" lp
     JOIN public.sample s ON ((lp.og_id_lp = s.og_id)));


--
-- Name: lca_validation_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."lca_validation_SS260818" (
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
-- Name: lca_validation_report_view_SS260818; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public."lca_validation_report_view_SS260818" AS
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
   FROM (((((public."lca_validation_SS260818" lv
     LEFT JOIN public."lca_pivot_view_SS260818" lp ON (((lp.og_id_lp = lv.og_id) AND (lp.tech = lv.tech) AND (lp.seq_date = lv.seq_date) AND (lp.code = (lv.code)::text) AND (lp.annotation = (lv.annotation)::text))))
     LEFT JOIN public."lca_results_view_SS260818" lr ON (((lr.og_id_lr = lv.og_id) AND (lr.tech = lv.tech) AND (lr.seq_date = lv.seq_date) AND (lr.code = (lv.code)::text) AND (lr.annotation = (lv.annotation)::text))))
     LEFT JOIN public.filtered_lca_view flv ON (((flv.og_id_flv = lv.og_id) AND (flv.tech = lv.tech) AND (flv.seq_date = lv.seq_date) AND (flv.code = (lv.code)::text) AND (flv.annotation = (lv.annotation)::text))))
     LEFT JOIN ( SELECT "lca_SS260818".og_id,
            "lca_SS260818".tech,
            "lca_SS260818".seq_date,
            "lca_SS260818".code,
            "lca_SS260818".annotation,
            string_agg(DISTINCT "lca_SS260818".taxon_rank, ', '::text ORDER BY "lca_SS260818".taxon_rank) AS lca_taxon_ranks,
            string_agg(DISTINCT "lca_SS260818"."order", ', '::text ORDER BY "lca_SS260818"."order") AS lca_orders,
            string_agg(DISTINCT "lca_SS260818".family, ', '::text ORDER BY "lca_SS260818".family) AS lca_families,
            string_agg(DISTINCT "lca_SS260818".genus, ', '::text ORDER BY "lca_SS260818".genus) AS lca_genera,
            string_agg(DISTINCT "lca_SS260818".specific_epiphet, ', '::text ORDER BY "lca_SS260818".specific_epiphet) AS lca_specific_epiphets
           FROM public."lca_SS260818"
          GROUP BY "lca_SS260818".og_id, "lca_SS260818".tech, "lca_SS260818".seq_date, "lca_SS260818".code, "lca_SS260818".annotation) lca_tax ON (((lca_tax.og_id = lv.og_id) AND (lca_tax.tech = lv.tech) AND (lca_tax.seq_date = lv.seq_date) AND (lca_tax.code = (lv.code)::text) AND (lca_tax.annotation = (lv.annotation)::text))))
     LEFT JOIN public.sample_view sv ON ((lv.og_id = sv.og_id_sv)));


--
-- Name: master_species_genome; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.master_species_genome (
    species text NOT NULL,
    high_quality_reference_genome_bioproject_id text,
    high_quality_genome_assembly_id text,
    draft_genome_bioproject_id text,
    draft_genome_assembly_id text,
    ncbi_private_public text,
    draft_sequencing_status text
);


--
-- Name: mitogenome_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mitogenome_data (
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation character varying,
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
    date_submitted_genbank date,
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
    passed character varying,
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
    avg_coverage real,
    avg_base_coverage real,
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
    annotation_updated_at timestamp with time zone
);


--
-- Name: COLUMN mitogenome_data.og_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mitogenome_data.og_num IS 'Numeric part of og_id, maintained by the database. Generated, not writable: do not include it in any INSERT or UPDATE column list.';


--
-- Name: COLUMN mitogenome_data.mean_depth; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mitogenome_data.mean_depth IS 'Mean per-base read depth of the sample''s own reads remapped to this assembly. Comparable across GetOrganelle / MitoHiFi / Oatk and across Illumina / HiC / HiFi. Use this, not avg_coverage, for any cross-platform comparison.';


--
-- Name: COLUMN mitogenome_data.depth_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mitogenome_data.depth_method IS 'remap_full_v1  = mean_depth measured by remapping the full post-QC read set to this assembly (circular molecules folded on a doubled reference). not_measured   = this assembly never reached annotation (failed, under-length, or a discarded assembly variant), or the depth step was skipped. legacy_*       = pre-dates the uniform measurement; only the assembler-specific avg_coverage / avg_base_coverage values exist for this row.';


--
-- Name: COLUMN mitogenome_data.avg_coverage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mitogenome_data.avg_coverage IS 'LEGACY, assembler-specific and NOT comparable across assemblers: k-mer coverage for GetOrganelle rows, reference-recruited read depth for MitoHiFi rows, NULL for Oatk. Retained for provenance. See mean_depth.';


--
-- Name: COLUMN mitogenome_data.order_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mitogenome_data.order_status IS 'reference | trna_displacement | rearranged_block | rearranged_major | not_evaluated.';


--
-- Name: COLUMN mitogenome_data.annotation_integrity_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mitogenome_data.annotation_integrity_status IS 'ok | advisory | broken | not_evaluated. Computed on the published annotation after all repair branches merge.';


--
-- Name: COLUMN mitogenome_data.mtmuts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mitogenome_data.mtmuts IS 'Octocoral mitochondrial mismatch-repair gene (INSDC /gene=mtMutS). Expected in Malacalcyonacea/Scleralcyonacea, absent in Hexacorallia.';


--
-- Name: mitogenome_data_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."mitogenome_data_SS260818" (
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
    passed character varying,
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
    depth_measured_at timestamp with time zone
);


--
-- Name: COLUMN "mitogenome_data_SS260818".avg_coverage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."mitogenome_data_SS260818".avg_coverage IS 'LEGACY, assembler-specific and NOT comparable across assemblers: k-mer coverage for GetOrganelle rows, reference-recruited read depth for MitoHiFi rows, NULL for Oatk. Retained for provenance. See mean_depth.';


--
-- Name: COLUMN "mitogenome_data_SS260818".mean_depth; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."mitogenome_data_SS260818".mean_depth IS 'Mean per-base read depth of the sample''s own reads remapped to this assembly. Comparable across GetOrganelle / MitoHiFi / Oatk and across Illumina / HiC / HiFi. Use this, not avg_coverage, for any cross-platform comparison.';


--
-- Name: COLUMN "mitogenome_data_SS260818".depth_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."mitogenome_data_SS260818".depth_method IS 'remap_full_v1  = mean_depth measured by remapping the full post-QC read set to this assembly (circular molecules folded on a doubled reference). not_measured   = this assembly never reached annotation (failed, under-length, or a discarded assembly variant), or the depth step was skipped. legacy_*       = pre-dates the uniform measurement; only the assembler-specific avg_coverage / avg_base_coverage values exist for this row.';


--
-- Name: mitogenome_submission_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.mitogenome_submission_view AS
 SELECT m.og_num,
    m.og_id,
    m.tech,
    m.seq_date,
    m.code,
    m.annotation,
    m.stats,
    m.length,
    m.length_emma,
    m.cds_no,
    m.trna_no,
    m.rrna_no,
    m.avg_coverage,
    m.avg_base_coverage,
    m.extra_genes,
    m.missing_genes,
    m.order_correct,
    e.table2asn_status,
    e.warning_codes,
    e.webin_status,
    e.webin_reason,
    e.submission_ready,
    l.validated_species_name,
    l.validator
   FROM ((public.mitogenome_data m
     LEFT JOIN public.ena_validation_attempts e ON (((e.og_id = m.og_id) AND (e.tech = m.tech) AND (e.seq_date = m.seq_date) AND (e.code = m.code) AND (e.annotation = (m.annotation)::text))))
     LEFT JOIN public.lca_validation l ON (((l.og_id = m.og_id) AND (l.tech = m.tech) AND (l.seq_date = m.seq_date) AND ((l.code)::text = m.code) AND ((l.annotation)::text = (m.annotation)::text))));


--
-- Name: ncbi_genome_assemblies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ncbi_genome_assemblies (
    assembly_accession text,
    assembly_name text,
    assembly_level text,
    assembly_bioproject_accession text,
    organism_name text,
    organism_taxonomic_id integer,
    assembly_refseq_category text,
    assembly_release_date date,
    contig_n50 integer
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
-- Name: project_delivery_contact; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_delivery_contact (
    id bigint NOT NULL,
    project_id text NOT NULL,
    display_name text NOT NULL,
    organisation text,
    email text NOT NULL,
    recipient_role text NOT NULL,
    component_types text[] DEFAULT ARRAY['reference'::text, 'draft'::text, 'mito'::text] NOT NULL,
    active boolean DEFAULT true NOT NULL,
    effective_from timestamp with time zone DEFAULT now() NOT NULL,
    effective_until timestamp with time zone,
    created_by text DEFAULT CURRENT_USER NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT project_delivery_contact_recipient_role_check CHECK ((recipient_role = ANY (ARRAY['to'::text, 'cc'::text, 'bcc'::text])))
);


--
-- Name: project_delivery_contact_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.project_delivery_contact ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.project_delivery_contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
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
    embargo_status text,
    gca_accession_hap1 text,
    gca_accession_hap2 text
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
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    filename text NOT NULL,
    sha256 text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
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
    synonym text
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
-- Name: blast_filtered_lca blast_filtered_lca_new_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blast_filtered_lca
    ADD CONSTRAINT blast_filtered_lca_new_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation, match_sequence_id, region);


--
-- Name: blast_filtered_lca_SS260818 blast_filtered_lca_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."blast_filtered_lca_SS260818"
    ADD CONSTRAINT blast_filtered_lca_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation, match_sequence_id, region);


--
-- Name: data_package_artifact data_package_artifact_delivery_id_component_id_artifact_typ_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_artifact
    ADD CONSTRAINT data_package_artifact_delivery_id_component_id_artifact_typ_key UNIQUE (delivery_id, component_id, artifact_type, batch_number, filename);


--
-- Name: data_package_artifact data_package_artifact_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_artifact
    ADD CONSTRAINT data_package_artifact_pkey PRIMARY KEY (id);


--
-- Name: data_package_component data_package_component_delivery_id_component_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_component
    ADD CONSTRAINT data_package_component_delivery_id_component_type_key UNIQUE (delivery_id, component_type);


--
-- Name: data_package_component data_package_component_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_component
    ADD CONSTRAINT data_package_component_pkey PRIMARY KEY (id);


--
-- Name: data_package_delivery data_package_delivery_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_delivery
    ADD CONSTRAINT data_package_delivery_pkey PRIMARY KEY (id);


--
-- Name: data_package_delivery data_package_delivery_project_id_delivery_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_delivery
    ADD CONSTRAINT data_package_delivery_project_id_delivery_version_key UNIQUE (project_id, delivery_version);


--
-- Name: data_package_delivery data_package_delivery_run_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_delivery
    ADD CONSTRAINT data_package_delivery_run_id_key UNIQUE (run_id);


--
-- Name: data_package_email data_package_email_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_email
    ADD CONSTRAINT data_package_email_pkey PRIMARY KEY (id);


--
-- Name: data_package_email data_package_email_preview_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_email
    ADD CONSTRAINT data_package_email_preview_id_key UNIQUE (preview_id);


--
-- Name: data_package_email_recipient data_package_email_recipient_email_id_recipient_role_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_email_recipient
    ADD CONSTRAINT data_package_email_recipient_email_id_recipient_role_email_key UNIQUE (email_id, recipient_role, email);


--
-- Name: data_package_email_recipient data_package_email_recipient_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_email_recipient
    ADD CONSTRAINT data_package_email_recipient_pkey PRIMARY KEY (id);


--
-- Name: data_package_item data_package_item_component_id_og_id_seq_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_item
    ADD CONSTRAINT data_package_item_component_id_og_id_seq_id_key UNIQUE (component_id, og_id, seq_id);


--
-- Name: data_package_item data_package_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_item
    ADD CONSTRAINT data_package_item_pkey PRIMARY KEY (id);


--
-- Name: data_package_link_set data_package_link_set_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_link_set
    ADD CONSTRAINT data_package_link_set_pkey PRIMARY KEY (id);


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
-- Name: ena_related_assemblies ena_related_assemblies_og_id_relationship_type_archive_acce_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_related_assemblies
    ADD CONSTRAINT ena_related_assemblies_og_id_relationship_type_archive_acce_key UNIQUE (og_id, relationship_type, archive, accession);


--
-- Name: ena_related_assemblies ena_related_assemblies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_related_assemblies
    ADD CONSTRAINT ena_related_assemblies_pkey PRIMARY KEY (id);


--
-- Name: ena_specimen_accessions ena_specimen_accessions_ena_biosample_accession_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_specimen_accessions
    ADD CONSTRAINT ena_specimen_accessions_ena_biosample_accession_key UNIQUE (ena_biosample_accession);


--
-- Name: ena_specimen_accessions ena_specimen_accessions_og_numeric_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_specimen_accessions
    ADD CONSTRAINT ena_specimen_accessions_og_numeric_key UNIQUE (og_numeric);


--
-- Name: ena_specimen_accessions ena_specimen_accessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_specimen_accessions
    ADD CONSTRAINT ena_specimen_accessions_pkey PRIMARY KEY (og_id);


--
-- Name: ena_submissions ena_submissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_submissions
    ADD CONSTRAINT ena_submissions_pkey PRIMARY KEY (full_seqid, webin_mode);


--
-- Name: ena_validation_attempts ena_validation_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_validation_attempts
    ADD CONSTRAINT ena_validation_attempts_pkey PRIMARY KEY (id);


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
-- Name: lca lca_content_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT lca_content_unique UNIQUE (og_id, tech, seq_date, code, annotation, region, content_hash);


--
-- Name: lca_raw_results lca_raw_results_content_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT lca_raw_results_content_unique UNIQUE (og_id, tech, seq_date, code, annotation, sequence_region, accession_id, content_hash);


--
-- Name: lca_raw_results_SS260818 lca_raw_results_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_raw_results_SS260818"
    ADD CONSTRAINT lca_raw_results_unique UNIQUE (og_id, tech, seq_date, code, annotation, sequence_region, lca_run_date, accession_id);


--
-- Name: lca_SS260818 lca_results_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_SS260818"
    ADD CONSTRAINT lca_results_unique UNIQUE (og_id, tech, seq_date, code, annotation, region, lca_run_date);


--
-- Name: lca_old lca_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_old
    ADD CONSTRAINT lca_unique UNIQUE (og_id, tech, seq_date, code, annotation, region, lca_run_date);


--
-- Name: lca_validation lca_validation_new_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT lca_validation_new_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation);


--
-- Name: lca_validation_SS260818 lca_validation_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_validation_SS260818"
    ADD CONSTRAINT lca_validation_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation);


--
-- Name: master_species_genome master_species_genome_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.master_species_genome
    ADD CONSTRAINT master_species_genome_pkey PRIMARY KEY (species);


--
-- Name: master_species master_species_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.master_species
    ADD CONSTRAINT master_species_pkey PRIMARY KEY (species);


--
-- Name: mitogenome_data_SS260818 mitogenome_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."mitogenome_data_SS260818"
    ADD CONSTRAINT mitogenome_data_pkey PRIMARY KEY (og_id, tech, seq_date, code);


--
-- Name: mitogenome_data mitogenome_data_pkey_1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mitogenome_data
    ADD CONSTRAINT mitogenome_data_pkey_1 PRIMARY KEY (og_id, tech, seq_date, code);


--
-- Name: mitogenome_data_SS260818 mitogenome_data_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."mitogenome_data_SS260818"
    ADD CONSTRAINT mitogenome_data_unique UNIQUE (og_id, tech, seq_date, code, annotation);


--
-- Name: mitogenome_data mitogenome_data_unique_1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mitogenome_data
    ADD CONSTRAINT mitogenome_data_unique_1 UNIQUE (og_id, tech, seq_date, code, annotation);


--
-- Name: ncbi_genome_assemblies ncbi_genome_assemblies_assembly_accession_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ncbi_genome_assemblies
    ADD CONSTRAINT ncbi_genome_assemblies_assembly_accession_key UNIQUE (assembly_accession);


--
-- Name: project_delivery_contact project_delivery_contact_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_delivery_contact
    ADD CONSTRAINT project_delivery_contact_pkey PRIMARY KEY (id);


--
-- Name: project_delivery_contact project_delivery_contact_project_id_email_recipient_role_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_delivery_contact
    ADD CONSTRAINT project_delivery_contact_project_id_email_recipient_role_key UNIQUE (project_id, email, recipient_role);


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
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (filename);


--
-- Name: species_ncbi_assembly species_ncbi_assembly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.species_ncbi_assembly
    ADD CONSTRAINT species_ncbi_assembly_pkey PRIMARY KEY (assembly_accession);


--
-- Name: data_package_artifact_remote_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_package_artifact_remote_idx ON public.data_package_artifact USING btree (remote_path);


--
-- Name: data_package_delivery_project_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_package_delivery_project_status_idx ON public.data_package_delivery USING btree (project_id, status, created_at DESC);


--
-- Name: data_package_item_og_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_package_item_og_idx ON public.data_package_item USING btree (og_id);


--
-- Name: data_package_link_expiry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_package_link_expiry_idx ON public.data_package_link_set USING btree (delivery_id, expires_at DESC);


--
-- Name: ena_related_one_primary_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ena_related_one_primary_idx ON public.ena_related_assemblies USING btree (og_id, relationship_type) WHERE is_primary;


--
-- Name: ena_submissions_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ena_submissions_identity_idx ON public.ena_submissions USING btree (og_id, tech, seq_date, code, annotation);


--
-- Name: ena_submissions_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ena_submissions_status_idx ON public.ena_submissions USING btree (submission_status);


--
-- Name: ena_validation_attempts_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ena_validation_attempts_identity_idx ON public.ena_validation_attempts USING btree (og_id, tech, seq_date, code, annotation);


--
-- Name: ena_validation_attempts_key_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ena_validation_attempts_key_idx ON public.ena_validation_attempts USING btree (full_seqid, ena_study, validation_attempt);


--
-- Name: ena_validation_attempts_recorded_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ena_validation_attempts_recorded_at_idx ON public.ena_validation_attempts USING btree (recorded_at DESC);


--
-- Name: idx_dna_extraction_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dna_extraction_og_id ON public.dna_extraction USING btree (og_id);


--
-- Name: idx_dna_extraction_tissue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dna_extraction_tissue_id ON public.dna_extraction USING btree (tissue_id);


--
-- Name: idx_hic_library_lysate_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hic_library_lysate_id ON public.hic_library USING btree (lysate_id);


--
-- Name: idx_hic_library_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hic_library_og_id ON public.hic_library USING btree (og_id);


--
-- Name: idx_hic_lysate_tissue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hic_lysate_tissue_id ON public.hic_lysate USING btree (tissue_id);


--
-- Name: idx_illumina_library_dna_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_illumina_library_dna_id ON public.illumina_library USING btree (dna_id);


--
-- Name: idx_illumina_library_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_illumina_library_og_id ON public.illumina_library USING btree (og_id);


--
-- Name: idx_ont_library_dna_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ont_library_dna_id ON public.ont_library USING btree (dna_id);


--
-- Name: idx_ont_library_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ont_library_og_id ON public.ont_library USING btree (og_id);


--
-- Name: idx_pacbio_library_dna_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pacbio_library_dna_id ON public.pacbio_library USING btree (dna_id);


--
-- Name: idx_pacbio_library_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pacbio_library_og_id ON public.pacbio_library USING btree (og_id);


--
-- Name: idx_ref_genomes_sra_uploads_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ref_genomes_sra_uploads_og_id ON public.ref_genomes_sra_uploads USING btree (og_id);


--
-- Name: idx_rna_extraction_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rna_extraction_og_id ON public.rna_extraction USING btree (og_id);


--
-- Name: idx_rna_extraction_tissue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rna_extraction_tissue_id ON public.rna_extraction USING btree (tissue_id);


--
-- Name: idx_rna_library_ilmn_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rna_library_ilmn_og_id ON public.rna_library_ilmn USING btree (og_id);


--
-- Name: idx_rna_library_ilmn_rna_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rna_library_ilmn_rna_id ON public.rna_library_ilmn USING btree (rna_id);


--
-- Name: idx_rna_library_kinx_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rna_library_kinx_og_id ON public.rna_library_kinx USING btree (og_id);


--
-- Name: idx_rna_library_kinx_rna_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rna_library_kinx_rna_id ON public.rna_library_kinx USING btree (rna_id);


--
-- Name: idx_sequencing_hic_library_tube_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sequencing_hic_library_tube_id ON public.sequencing USING btree (hic_library_tube_id);


--
-- Name: idx_sequencing_illumina_library_tube_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sequencing_illumina_library_tube_id ON public.sequencing USING btree (illumina_library_tube_id);


--
-- Name: idx_sequencing_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sequencing_og_id ON public.sequencing USING btree (og_id);


--
-- Name: idx_sequencing_ont_library_tube_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sequencing_ont_library_tube_id ON public.sequencing USING btree (ont_library_tube_id);


--
-- Name: idx_sequencing_pacbio_library_tube_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sequencing_pacbio_library_tube_id ON public.sequencing USING btree (pacbio_library_tube_id);


--
-- Name: idx_tissue_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tissue_og_id ON public.tissue USING btree (og_id);


--
-- Name: mitogenome_data_depth_method_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mitogenome_data_depth_method_idx ON public."mitogenome_data_SS260818" USING btree (depth_method);


--
-- Name: mitogenome_data_depth_method_idx_1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mitogenome_data_depth_method_idx_1 ON public.mitogenome_data USING btree (depth_method);


--
-- Name: project_delivery_contact_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_delivery_contact_active_idx ON public.project_delivery_contact USING btree (project_id, active);


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
-- Name: lca lca_content_hash; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER lca_content_hash BEFORE INSERT OR UPDATE ON public.lca FOR EACH ROW EXECUTE FUNCTION public.lca_set_content_hash();


--
-- Name: lca_raw_results lca_raw_results_content_hash; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER lca_raw_results_content_hash BEFORE INSERT OR UPDATE ON public.lca_raw_results FOR EACH ROW EXECUTE FUNCTION public.lca_set_content_hash();


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
-- Name: lca_validation_report_view_SS260818 trg_lca_validation_report_view_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lca_validation_report_view_upd INSTEAD OF UPDATE ON public."lca_validation_report_view_SS260818" FOR EACH ROW EXECUTE FUNCTION public.lca_validation_report_view_upd();


--
-- Name: data_package_artifact data_package_artifact_component_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_artifact
    ADD CONSTRAINT data_package_artifact_component_id_fkey FOREIGN KEY (component_id) REFERENCES public.data_package_component(id) ON DELETE CASCADE;


--
-- Name: data_package_artifact data_package_artifact_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_artifact
    ADD CONSTRAINT data_package_artifact_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.data_package_delivery(id) ON DELETE CASCADE;


--
-- Name: data_package_component data_package_component_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_component
    ADD CONSTRAINT data_package_component_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.data_package_delivery(id) ON DELETE CASCADE;


--
-- Name: data_package_email data_package_email_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_email
    ADD CONSTRAINT data_package_email_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.data_package_delivery(id) ON DELETE CASCADE;


--
-- Name: data_package_email data_package_email_link_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_email
    ADD CONSTRAINT data_package_email_link_set_id_fkey FOREIGN KEY (link_set_id) REFERENCES public.data_package_link_set(id);


--
-- Name: data_package_email_recipient data_package_email_recipient_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_email_recipient
    ADD CONSTRAINT data_package_email_recipient_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.project_delivery_contact(id);


--
-- Name: data_package_email_recipient data_package_email_recipient_email_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_email_recipient
    ADD CONSTRAINT data_package_email_recipient_email_id_fkey FOREIGN KEY (email_id) REFERENCES public.data_package_email(id) ON DELETE CASCADE;


--
-- Name: data_package_item data_package_item_component_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_item
    ADD CONSTRAINT data_package_item_component_id_fkey FOREIGN KEY (component_id) REFERENCES public.data_package_component(id) ON DELETE CASCADE;


--
-- Name: data_package_link_set data_package_link_set_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_link_set
    ADD CONSTRAINT data_package_link_set_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.data_package_delivery(id) ON DELETE CASCADE;


--
-- Name: data_package_link_set data_package_link_set_previous_link_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_package_link_set
    ADD CONSTRAINT data_package_link_set_previous_link_set_id_fkey FOREIGN KEY (previous_link_set_id) REFERENCES public.data_package_link_set(id);


--
-- Name: ena_related_assemblies ena_related_assemblies_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_related_assemblies
    ADD CONSTRAINT ena_related_assemblies_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.ena_specimen_accessions(og_id);


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
-- Name: master_species_genome fk_master_species_genome_species; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.master_species_genome
    ADD CONSTRAINT fk_master_species_genome_species FOREIGN KEY (species) REFERENCES public.master_species(species) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lca_SS260818 fk_mitogenome; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_SS260818"
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public."mitogenome_data_SS260818"(og_id, tech, seq_date, code);


--
-- Name: lca_old fk_mitogenome; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_old
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public."mitogenome_data_SS260818"(og_id, tech, seq_date, code);


--
-- Name: lca_raw_results_SS260818 fk_mitogenome; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_raw_results_SS260818"
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public."mitogenome_data_SS260818"(og_id, tech, seq_date, code);


--
-- Name: lca fk_mitogenome_lca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT fk_mitogenome_lca FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


--
-- Name: lca_raw_results fk_mitogenome_lca_raw_results; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT fk_mitogenome_lca_raw_results FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


--
-- Name: lca_validation fk_mitogenome_lca_validation; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT fk_mitogenome_lca_validation FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


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
-- Name: lca_validation_SS260818 lca_validation_mitogenome_data_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_validation_SS260818"
    ADD CONSTRAINT lca_validation_mitogenome_data_fk FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public."mitogenome_data_SS260818"(og_id, tech, seq_date, code);


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

\unrestrict STZx71VRqY58TfCavK58QK80a7wFuDUEBxcrQ8Z9MmHRvEQNzjROurz1b8FqQrE

