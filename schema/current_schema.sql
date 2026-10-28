--
-- PostgreSQL database dump
--

\restrict 2ucHcOK282bQ26ZUgfYpH6qXiJqFrt5w3cjQzrUahwfEchesNLI5bD7cp9vwudB

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

CREATE FUNCTION public.build_nfcore_samplesheet_rows(in_og_ids text[]) RETURNS TABLE(sample text, hifi_dir text, hic_dir text, assembly text, busco_genes text, bioproject_id text, version text, date text, tolid text, taxid bigint, species text)
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
smp AS (
  SELECT DISTINCT ON (s.og_id)
         s.og_id,
         s.nominal_species_id,
         s.tol_id,
         s.ncbi_bioproject_id_lvl_3_hifi
  FROM sample s
  JOIN p ON s.og_id = p.og_id
  ORDER BY s.og_id
)
SELECT DISTINCT ON (p.og_id)
  p.og_id AS sample,
  '/scratch/pawsey0964/lhuet/genomenotes/'||p.og_id||'/hifi'     AS hifi_dir,
  '/scratch/pawsey0964/lhuet/genomenotes/'||p.og_id||'/hic'      AS hic_dir,
  '/scratch/pawsey0964/lhuet/genomenotes/'||p.og_id||'/assembly' AS assembly,
  '/scratch/pawsey0964/lhuet/genomenotes/'||p.og_id||'/busco'    AS busco_genes,
  smp.ncbi_bioproject_id_lvl_3_hifi AS bioproject_id,
  CASE WHEN rg.og_id IS NOT NULL THEN 'hic2' ELSE 'hic1' END AS version,
  CASE WHEN ls.seq_date IS NOT NULL THEN 'v'||to_char(ls.seq_date,'YYMMDD') END AS date,
  smp.tol_id AS tolid,
  sp.ncbi_taxon_id AS taxid,
  sp.species
FROM p
LEFT JOIN ref_genomes rg ON rg.og_id = p.og_id
LEFT JOIN latest_seq ls  ON ls.og_id = p.og_id
LEFT JOIN smp ON smp.og_id = p.og_id
LEFT JOIN species sp ON sp.species = smp.nominal_species_id
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
latest_asm AS (
  SELECT DISTINCT ON (rg.og_id)
         rg.og_id,
         rg.version,
         rg.seq_date
  FROM ref_genomes rg
  JOIN p ON rg.og_id = p.og_id
  WHERE rg.version ~ '^hic[0-9]+$'
    AND rg.seq_date ~ '^[0-9]{6}$'
  ORDER BY rg.og_id,
           substring(rg.version from '[0-9]+')::int DESC,
           rg.seq_date DESC
),
gen_sz AS (
  SELECT rq.og_id, MAX(rq.genomesize) AS genome_size
  FROM raw_qc rq
  JOIN p ON rq.og_id = p.og_id
  GROUP BY rq.og_id
)
SELECT DISTINCT ON (p.og_id)
  p.og_id                                 AS sample,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/hic'      AS hic_dir,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/assembly' AS assembly,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/meryl'    AS meryldb,
  '/scratch/pawsey0964/lhuet/post_curation/' || p.og_id || '/agp'      AS agp,
  la.version                              AS version,
  CASE
    WHEN la.seq_date IS NOT NULL
    THEN 'v' || la.seq_date
  END                                     AS date,
  gs.genome_size                          AS genomesize
FROM p
LEFT JOIN latest_asm la ON la.og_id = p.og_id
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
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    NEW.content_hash := md5(
        (to_jsonb(NEW) - 'lca_run_date' - 'og_num' - 'content_hash')::text
    );
    RETURN NEW;
END $$;


--
-- Name: FUNCTION lca_set_content_hash(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.lca_set_content_hash() IS 'Maintains content_hash on v2.lca and v2.lca_raw_results. Pinned search_path so the hash cannot vary with the caller''s path.';


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
-- Name: quarantine(text, text, text, text, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.quarantine(p_source_table text, p_source_row_key text, p_violation_type text, p_violation_detail text, p_raw_row jsonb, p_source_sheet text DEFAULT NULL::text) RETURNS bigint
    LANGUAGE sql
    AS $$
    INSERT INTO public.import_quarantine AS q
        (source_table, source_sheet, source_row_key, violation_type, violation_detail, raw_row)
    VALUES
        (p_source_table, p_source_sheet, p_source_row_key, p_violation_type, p_violation_detail, p_raw_row)
    ON CONFLICT (source_table, coalesce(source_row_key, ''), violation_type)
        WHERE resolved_at IS NULL
    DO UPDATE SET last_seen         = now(),
                  violation_detail  = excluded.violation_detail,
                  raw_row           = excluded.raw_row,
                  source_sheet      = coalesce(excluded.source_sheet, q.source_sheet)
    RETURNING quarantine_id;
$$;


--
-- Name: FUNCTION quarantine(p_source_table text, p_source_row_key text, p_violation_type text, p_violation_detail text, p_raw_row jsonb, p_source_sheet text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.quarantine(p_source_table text, p_source_row_key text, p_violation_type text, p_violation_detail text, p_raw_row jsonb, p_source_sheet text) IS 'Record or refresh a quarantined row. Idempotent per (table, key, violation) while the violation is unresolved, so repeated nightly imports do not accumulate duplicates.';


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
    aus_status text,
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
-- Name: COLUMN master_species.aus_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.master_species.aus_status IS 'Australian occurrence status (native/endemic/introduced/etc.). Primary source: FishBase Australia checklist (https://www.fishbase.se), matched to master_species.species. Species not listed in FishBase are filled from WoRMS distribution records (https://www.marinespecies.org) where WoRMS gives an Australian establishment status (Native - Endemic -> endemic, Native -> native, Alien -> introduced); WoRMS never overwrites an existing value. Automatically update annually (2 January, 09:00).';


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
-- Name: TABLE blast_filtered_lca; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.blast_filtered_lca IS 'BLAST hits retained after LCA filtering, one row per matched sequence and region.';


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
-- Name: TABLE design_description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.design_description IS 'Illumina prep protocols, named by sequencing.design_no (FK, migration 063).';


--
-- Name: dna_extraction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dna_extraction (
    dna_id text NOT NULL,
    tissue_id text NOT NULL,
    ext_num integer,
    status text,
    extraction_method text,
    extraction_date date,
    extraction_batch_id text,
    final_buffer text,
    volume integer,
    qubit_conc real,
    nano_drop_conc real,
    ratio_260_280 real,
    ratio_260_230 real,
    ratioqubit_nanodrop real,
    total_yield real,
    gdna_femtol_id text,
    av_size real,
    extraction_qc text,
    comment text,
    dna_freezer text,
    dna_shelf integer,
    dna_rack integer,
    dna_level text,
    dna_box text,
    dna_notes text,
    status_overwrite boolean,
    extract_plate text,
    extract_plate_well text
);


--
-- Name: TABLE dna_extraction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.dna_extraction IS 'One row per DNA extraction attempt from a tissue. Source: the 3.DNAExtractions sheet.';


--
-- Name: COLUMN dna_extraction.status_overwrite; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.dna_extraction.status_overwrite IS 'Lab flag marking which extraction to report in the summary. Boolean because the workbook holds only Y here - 129 of them across all sheets, 36 on this one, and nothing else. It has never reached the database: neither spelling of the header ("Status Overwrite" / "Overwrite Status") is in name_convert.py, so the lab has been filling a field the import silently discards while summary reads a column that is always null. See v2_scaffold_design_review.md F4a.';


--
-- Name: COLUMN dna_extraction.extract_plate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.dna_extraction.extract_plate IS 'Spreadsheet header "Extract Plate name Or tube", added by the lab after 2026-08. Populated on 274 rows of OceanGenomes_Database_261006.xlsx.';


--
-- Name: COLUMN dna_extraction.extract_plate_well; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.dna_extraction.extract_plate_well IS 'Spreadsheet header "Extract Plate Well", added by the lab after 2026-08. Populated on 266 rows of OceanGenomes_Database_261006.xlsx.';


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
    host_assembly_fraction numeric,
    host_haploid_size bigint,
    partition_confidence text,
    busco_read_depth numeric(10,4),
    genomescope_fit text,
    busco_regions integer,
    partition_note text,
    CONSTRAINT draft_genomes_genomescope_fit_check CHECK ((genomescope_fit = ANY (ARRAY['original'::text, 'reseeded'::text]))),
    CONSTRAINT draft_genomes_partition_confidence_check CHECK ((partition_confidence = ANY (ARRAY['high'::text, 'low'::text])))
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
-- Name: COLUMN draft_genomes.host_haploid_size; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomes.host_haploid_size IS 'Host assembly mass with haplotype-split contigs (those at about half the host depth) counted once. A lower bound, like host_assembly_size. From *_kmer_depth.json.';


--
-- Name: COLUMN draft_genomes.partition_confidence; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomes.partition_confidence IS 'high or low: whether the BUSCO depth anchor of the host partition can be trusted. Do not quote a host size from a low partition; partition_note says why it is low.';


--
-- Name: COLUMN draft_genomes.busco_read_depth; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomes.busco_read_depth IS 'Mean per-base read depth over the Complete single-copy BUSCO genes (busco_mean_depth in *_kmer_depth.json, from MEASURE_KMER_COVERAGE). The sequencing depth of the host genome, and what ENA COVERAGE should carry; the successor to DepthSizer''s scdepth. Not lambda_depth, which is this halved and scaled into k-mer space.';


--
-- Name: COLUMN draft_genomes.genomescope_fit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomes.genomescope_fit IS 'original or reseeded: which GenomeScope fit genomesize, kmercov and the model fit come from (genomescope_fit in *_coverage_summary.json; GENOMESCOPE_RESEED keeps the refit only when it wins). NULL before the reseed existed.';


--
-- Name: COLUMN draft_genomes.busco_regions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomes.busco_regions IS 'Number of Complete BUSCO regions busco_read_depth and the host partition were measured over (busco_regions in *_kmer_depth.json).';


--
-- Name: COLUMN draft_genomes.partition_note; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomes.partition_note IS 'Why partition_confidence is low: few_busco_regions, no_dominant_mode or anchor_off_mode. NULL when it is high.';


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
    data_release text,
    validated_rank text,
    lca_genus text,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    row_created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE lca_validation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.lca_validation IS 'Human validation of LCA calls. Read by v2.summary and by the public reporting views.';


--
-- Name: sample; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sample (
    og_id text NOT NULL,
    og_num integer GENERATED ALWAYS AS ((NULLIF("substring"(og_id, '^OG([0-9]+)$'::text), ''::text))::integer) STORED,
    project_id text,
    field_id text,
    nominal_species_id text,
    common_name text,
    collector text,
    contact text,
    date_collected date,
    sex text,
    weight real,
    country text,
    state text,
    location text,
    latitude_collection double precision,
    longitude_collection double precision,
    collection_method text,
    preservation_method text,
    sample_condition text,
    sample_condition_upon_preservation text,
    photo_voucher text,
    photo_id text,
    specimen_voucher text,
    voucher_id text,
    ethics_permit text,
    collection_permit text,
    import_permit text,
    cultural_significance text,
    cites text,
    cms text,
    iucn text,
    epbc text,
    sample_receipt_date date,
    comments text,
    workflow text,
    priority text,
    ilmn boolean,
    hifi boolean,
    hic boolean,
    nano boolean,
    rna boolean,
    ilrna boolean,
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
    draft_sra_accessions text,
    draft_assembly_accession text,
    embargo_status text,
    length_tl_mm real,
    length_fl_mm real,
    length_unspecified_mm real,
    depth_min_m real,
    depth_max_m real,
    CONSTRAINT sample_depth_range_check CHECK (((depth_min_m IS NULL) OR (depth_max_m IS NULL) OR (depth_min_m <= depth_max_m)))
);


--
-- Name: TABLE sample; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.sample IS 'One row per specimen. Source: the 1.MetaData sheet, plus eight hand-entered planning columns from Summary.';


--
-- Name: COLUMN sample.og_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.og_num IS 'Numeric part of og_id, for sort order only. Null on any og_id not matching ^OG[0-9]+$ rather than raising, unlike the live column.';


--
-- Name: COLUMN sample.sample_receipt_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.sample_receipt_date IS 'Stored as an Excel date serial in the sheet, like Date_Collected; the importer needs the same serial-to-date handling.';


--
-- Name: COLUMN sample.ilmn; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.ilmn IS 'Is this sample slated for Illumina? Hand-entered lab intent (Y/N in the workbook). Compare against the actual library count in v2.summary.';


--
-- Name: COLUMN sample.hifi; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.hifi IS 'Is this sample slated for PacBio HiFi? Hand-entered lab intent.';


--
-- Name: COLUMN sample.hic; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.hic IS 'Is this sample slated for Hi-C? Hand-entered lab intent.';


--
-- Name: COLUMN sample.nano; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.nano IS 'Is this sample slated for ONT? Hand-entered lab intent.';


--
-- Name: COLUMN sample.rna; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.rna IS 'Is this sample slated for RNA extraction? Hand-entered lab intent.';


--
-- Name: COLUMN sample.ilrna; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.ilrna IS 'Is this sample slated for Illumina RNA? Hand-entered lab intent.';


--
-- Name: COLUMN sample.length_tl_mm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.length_tl_mm IS 'Total length, mm. From a TL-labelled value in the workbook''s "Length (TL or FL mm)".';


--
-- Name: COLUMN sample.length_fl_mm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.length_fl_mm IS 'Fork length, mm. From an FL-labelled value in "Length (TL or FL mm)"; a cell can give both.';


--
-- Name: COLUMN sample.length_unspecified_mm; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.length_unspecified_mm IS 'A length the workbook gives without saying TL or FL, mm. Not guessed: relabel at source.';


--
-- Name: COLUMN sample.depth_min_m; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.depth_min_m IS 'Collection depth, shallow end, metres (Darwin Core minimumDepthInMeters). Equals depth_max_m for a single depth; 0 for "<x" and for "Surface".';


--
-- Name: COLUMN sample.depth_max_m; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sample.depth_max_m IS 'Collection depth, deep end, metres (Darwin Core maximumDepthInMeters). NULL for ">x".';


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
    top_confidence_score double precision,
    top_percent_match double precision,
    taxon_rank_db text,
    content_hash text NOT NULL
);


--
-- Name: TABLE lca; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.lca IS 'Lowest common ancestor calls per marker region. Live carries this key as a UNIQUE constraint only; here it is the primary key.';


--
-- Name: COLUMN lca.lca_run_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lca.lca_run_date IS 'When the LCA pipeline ran. NOT NULL, but deliberately NOT part of the key -- row identity is the content hash (migration 017), so a re-run with a changed answer stores a new row rather than colliding with the old one.';


--
-- Name: COLUMN lca.content_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lca.content_hash IS 'md5 of the row content, maintained by the trigger below. Row identity for this table. Not comparable with public.lca.content_hash: the hash covers every column, and the two tables no longer have the same column set (og_num is gone, F2). Reconcile these tables on their business keys, never on this value.';


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
    (string_agg(DISTINCT t.sp, ', '::text ORDER BY t.sp) FILTER (WHERE (lca.region = '12s'::text)) COLLATE "default") AS s12_lca,
    (string_agg(DISTINCT t.sp, ', '::text ORDER BY t.sp) FILTER (WHERE (lca.region = '16s'::text)) COLLATE "default") AS s16_lca,
    (string_agg(DISTINCT t.sp, ', '::text ORDER BY t.sp) FILTER (WHERE (lca.region = 'CO1'::text)) COLLATE "default") AS co1_lca
   FROM (public.lca
     LEFT JOIN LATERAL ( SELECT (btrim(x.x) COLLATE "C") AS sp
           FROM unnest(string_to_array(lca.species_in_lca, ','::text)) x(x)
          WHERE (btrim(x.x) <> ''::text)) t ON (true))
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
            WHEN (s.nominal_species_id = ANY (ARRAY( SELECT split_part(btrim(t.t), ';'::text, 1) AS split_part
               FROM unnest(string_to_array(concat_ws(','::text, lp.s12_lca, lp.s16_lca, lp.co1_lca), ','::text)) t(t)))) THEN s.nominal_species_id
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
-- Name: hic_library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hic_library (
    hic_library_tube_id text NOT NULL,
    lysate_id text NOT NULL,
    hic_num integer,
    hic_status text,
    library_method text,
    processing_notes text,
    library_date date,
    library_id text,
    prox_ligation_conc real,
    purified_dna_total real,
    index_set text,
    index_i5 text,
    index_i7 text,
    library_conc real,
    library_yield real,
    library_size integer,
    pcr_dup_read_pairs real,
    nodup_cis_read_pairs_1kb real,
    expected_distinct_30m_reads bigint,
    hic_comments text,
    status_overwrite boolean
);


--
-- Name: TABLE hic_library; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.hic_library IS 'One row per Hi-C library. Source: the 4.HiCLibrary sheet.';


--
-- Name: COLUMN hic_library.prox_ligation_conc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.hic_library.prox_ligation_conc IS 'LEGACY. The intended home for this measurement is hic_lysate.prox_ligation_conc (decision 11, F13), but the lab still records it on 4.HiCLibrary - 264 numeric values in OceanGenomes_Database_261006.xlsx against 77 on 4.HiCLysate - so import_v2.py writes it here by owner decision 2026-10-06 rather than drop every new value. The 226 backfilled values cannot be migrated up because 10 of their lysates carry conflicting values across their libraries and no rule picks a winner. Retire this column once the lab records the measurement on 4.HiCLysate.';


--
-- Name: hic_lysate; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hic_lysate (
    lysate_id text NOT NULL,
    tissue_id text NOT NULL,
    lysate_num integer,
    lysate_status text,
    lysate_method text,
    lysate_prep_date date,
    lysate_batch_id text,
    lysate_conc real,
    total_lysate real,
    lysate_cde real,
    prox_ligation_date date,
    prox_ligation_conc real,
    prox_ligation_yield real GENERATED ALWAYS AS ((prox_ligation_conc * (40)::double precision)) STORED,
    lysate_comments text,
    status_overwrite boolean
);


--
-- Name: TABLE hic_lysate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.hic_lysate IS 'One row per Hi-C lysate prepared from a tissue. Source: the 4.HiCLysate sheet.';


--
-- Name: COLUMN hic_lysate.lysate_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.hic_lysate.lysate_method IS 'Spreadsheet header "Prep Method". Populated on 386 rows and dropped by the importer until now.';


--
-- Name: COLUMN hic_lysate.prox_ligation_conc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.hic_lysate.prox_ligation_conc IS 'Proximity ligation concentration - the LIVE home for this measurement (decision 11). Evidence: it agrees with hic_library.prox_ligation_conc 48 times out of 49 where both are present; all 19 multi-library conflicts predate this column; and 36 lysates carry a value while having zero or one Hi-C library, so it exists before any library does. The workbook contains the literal strings "NA" and "0" here, which will quarantine against this type.';


--
-- Name: COLUMN hic_lysate.prox_ligation_yield; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.hic_lysate.prox_ligation_yield IS 'Derived, matching the workbook formula IF(conc="NA","NA",conc*40) on 4.HiCLysate. The 40 is the elution volume in uL; if the protocol changes this expression must change with it.';


--
-- Name: illumina_library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.illumina_library (
    illumina_library_tube_id text NOT NULL,
    dna_id text NOT NULL,
    ilmn_num integer,
    ilmn_status text,
    library_method text,
    prep_automation text,
    library_date date,
    library_id text,
    library_plate_well text,
    index_plate text,
    index_set text,
    index_well text,
    index_idx text,
    library_qubit_conc real,
    il_comments text,
    status_overwrite boolean
);


--
-- Name: TABLE illumina_library; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.illumina_library IS 'One row per Illumina DNA library. Source: the 4.Illumina sheet.';


--
-- Name: COLUMN illumina_library.prep_automation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.illumina_library.prep_automation IS 'Spreadsheet header "Manual/ Automated Method", populated on 1,607 rows and dropped by the importer until now. 941 of them read "Auomated Biomek i7" and normalise to "Automated Biomek i7" at backfill.';


--
-- Name: COLUMN illumina_library.library_plate_well; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.illumina_library.library_plate_well IS 'Spreadsheet header "Final Library Plate Well", renamed by the lab from "Library Plate Well" between the 260804 and 261006 workbooks; name_convert_v2.py maps both. Populated on 1,523 rows in August and 1,078 in OceanGenomes_Database_261006.xlsx, and dropped by the live importer.';


--
-- Name: COLUMN illumina_library.index_plate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.illumina_library.index_plate IS 'Spreadsheet header "Index Plate". Populated on 1,297 rows and dropped by the importer until now.';


--
-- Name: ont_library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ont_library (
    ont_library_tube_id text NOT NULL,
    dna_id text NOT NULL,
    ont_num integer,
    ont_status text,
    library_method text,
    library_type text,
    library_date date,
    library_id text,
    est_loading_size integer,
    ont_comments text,
    status_overwrite boolean
);


--
-- Name: TABLE ont_library; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ont_library IS 'One row per Oxford Nanopore library. Source: the 4.ONT sheet.';


--
-- Name: COLUMN ont_library.library_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ont_library.library_type IS 'The ONT kit type from the "Library Type" header. Unrelated to library.library_type, which names the technology.';


--
-- Name: pacbio_library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pacbio_library (
    pacbio_library_tube_id text NOT NULL,
    dna_id text NOT NULL,
    pacb_num integer,
    pacb_status text,
    dna_treatment text,
    sre_kit text,
    post_sre_conc real,
    final_pre_library_conc real,
    shear_femtol_id text,
    shear_av_size integer,
    library_method text,
    prep_automation text,
    library_date date,
    library_id text,
    index_well text,
    barcode text,
    seq_femto_id text,
    seq_av_size real,
    library_conc real,
    comment text,
    status_overwrite boolean
);


--
-- Name: TABLE pacbio_library; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.pacbio_library IS 'One row per PacBio HiFi library. Source: the 4.PacBio sheet.';


--
-- Name: COLUMN pacbio_library.sre_kit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pacbio_library.sre_kit IS 'Short Read Eliminator kit. Populated on 394 rows and dropped by the importer until now.';


--
-- Name: COLUMN pacbio_library.post_sre_conc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pacbio_library.post_sre_conc IS 'Spreadsheet header "Post-SRE Conc. (ng/uL)". Populated on 191 rows and dropped by the importer until now.';


--
-- Name: COLUMN pacbio_library.final_pre_library_conc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pacbio_library.final_pre_library_conc IS 'Spreadsheet header "Final Pre-Library Prep Conc. (ng/uL)". Populated on 194 rows and dropped by the importer until now.';


--
-- Name: COLUMN pacbio_library.prep_automation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pacbio_library.prep_automation IS 'Spreadsheet header "Manual/ Automated Method". Populated on 365 rows and dropped by the importer until now.';


--
-- Name: rna_extraction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rna_extraction (
    rna_id text NOT NULL,
    tissue_id text NOT NULL,
    ext_num integer,
    status text,
    extraction_method text,
    extraction_date date,
    extraction_batch_id text,
    final_buffer text,
    volume integer,
    qubit_conc real,
    nano_drop_conc real,
    ratio_260_280 real,
    ratio_260_230 real,
    total_yield real,
    gdna_over_7kb_perc real,
    tapestation_id text,
    rna_dv200 real,
    rin real,
    extraction_qc text,
    comment text,
    rna_freezer text,
    rna_shelf integer,
    rna_rack integer,
    rna_level text,
    rna_box text,
    rna_notes text,
    status_overwrite boolean
);


--
-- Name: TABLE rna_extraction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.rna_extraction IS 'One row per RNA extraction attempt from a tissue. Source: the 3.RNAExtractions sheet.';


--
-- Name: COLUMN rna_extraction.gdna_over_7kb_perc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rna_extraction.gdna_over_7kb_perc IS 'Spreadsheet header "gDNA? >7,000bp %". Populated on 185 rows and dropped by the importer until now.';


--
-- Name: rna_library_ilmn; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rna_library_ilmn (
    rna_library_tube_id text NOT NULL,
    rna_id text NOT NULL,
    rna_num integer,
    rna_status text,
    library_method text,
    library_date date,
    library_id text,
    library_size integer,
    perc_product real,
    library_qubit_conc real,
    library_molarity real,
    index_set text,
    index_well text,
    index_inx text,
    comments text,
    status_overwrite boolean,
    final_plate_name text,
    final_plate_well text,
    well_position text
);


--
-- Name: TABLE rna_library_ilmn; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.rna_library_ilmn IS 'One row per Illumina RNA library. Source: the 4.RNAIllumina sheet.';


--
-- Name: COLUMN rna_library_ilmn.library_size; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rna_library_ilmn.library_size IS 'Historical values only. The "cDNA Library Size (bp)" header was removed from 4.RNAIllumina between the 260804 and 261006 workbooks, so nothing writes this column after the backfill.';


--
-- Name: COLUMN rna_library_ilmn.perc_product; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rna_library_ilmn.perc_product IS 'Mapped in name_convert.py to a "% Product" header that no longer exists on 4.RNAIllumina, so it has been silently NULL. Retained pending a mapping fix, not a schema fix.';


--
-- Name: COLUMN rna_library_ilmn.final_plate_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rna_library_ilmn.final_plate_name IS 'Spreadsheet header "Final Plate Name", added by the lab after 2026-08. Populated on 135 rows of OceanGenomes_Database_261006.xlsx.';


--
-- Name: COLUMN rna_library_ilmn.final_plate_well; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rna_library_ilmn.final_plate_well IS 'Spreadsheet header "Final Plate Well", added by the lab after 2026-08. Populated on 135 rows of OceanGenomes_Database_261006.xlsx.';


--
-- Name: COLUMN rna_library_ilmn.well_position; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rna_library_ilmn.well_position IS 'Spreadsheet header "Well Position". Populated on 63 rows of OceanGenomes_Database_261006.xlsx. Possibly the predecessor of final_plate_well; kept separate until the lab says so (owner decision 2026-10-06).';


--
-- Name: rna_library_kinx; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rna_library_kinx (
    rna_library_tube_id text NOT NULL,
    rna_id text NOT NULL,
    rna_num integer,
    rna_status text,
    library_method text,
    processing_comment text,
    synthesis_date date,
    part1_batch_id text,
    synthesis_conc real,
    part2_batch_id text,
    final_qubit_conc real,
    library_size integer,
    kinnex_primers text,
    kinnex_barcode text,
    pool_id text,
    plate integer,
    plate_location text,
    sequencing_sample_id text,
    comments text,
    status_overwrite boolean
);


--
-- Name: TABLE rna_library_kinx; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.rna_library_kinx IS 'One row per PacBio Kinnex RNA library. Source: the 4.RNAkinnex sheet.';


--
-- Name: COLUMN rna_library_kinx.synthesis_conc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rna_library_kinx.synthesis_conc IS 'Mapped in name_convert.py to a header without the embedded newline the real one has ("cDNA Concentration \n(end of section 1 conc)"), so it has been silently NULL. Fix is in the importer.';


--
-- Name: COLUMN rna_library_kinx.sequencing_sample_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rna_library_kinx.sequencing_sample_id IS 'Populated on 148 rows and dropped by the importer until now. Hand-entered here, unlike the same-named formula column on 4.RNAIllumina.';


--
-- Name: tissue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tissue (
    tissue_id text NOT NULL,
    og_id text NOT NULL,
    alt_id text,
    tissue text,
    extracted integer,
    preservation text,
    freezer text,
    shelf integer,
    rack integer,
    level text,
    box text,
    comment text
);


--
-- Name: TABLE tissue; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.tissue IS 'One row per tissue subsample taken from a specimen. Source: the 2.Tissue sheet.';


--
-- Name: COLUMN tissue.og_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tissue.og_id IS 'Parent specimen. The only ancestor stored here, per lab_key_strategy.md §6.0.';


--
-- Name: COLUMN tissue.preservation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tissue.preservation IS 'Tissue-level preservation. Distinct from sample.preservation_method, which is specimen-level.';


--
-- Name: summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.summary AS
 SELECT s.og_num,
    s.og_id,
    s.project_id,
    s.workflow,
    s.priority,
    ( SELECT count(*) AS count
           FROM public.tissue t
          WHERE (t.og_id = s.og_id)) AS tissues,
    ( SELECT count(*) AS count
           FROM (public.dna_extraction d
             JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
          WHERE ((t.og_id = s.og_id) AND (d.status = 'Extracted'::text))) AS extracted,
    COALESCE(dna.status, 'Awaiting Status'::text) AS dna_extraction_status,
    COALESCE(ilmn.status, 'Awaiting Status'::text) AS illumina_status,
    COALESCE(pacb.status, 'Awaiting Status'::text) AS pacbio_status,
    COALESCE(hic.status, 'Awaiting Status'::text) AS hic_status,
    COALESCE(ont.status, 'Awaiting Status'::text) AS nanopore_status,
    COALESCE(rna.status, 'Awaiting Status'::text) AS rna_extraction_status,
    COALESCE(rilm.status, 'Awaiting Status'::text) AS rna_ilmn_status,
    COALESCE(rkin.status, 'Awaiting Status'::text) AS rna_kinnex_status,
    s.ilmn AS illumina_planned,
    s.hifi AS hifi_planned,
    s.hic AS hic_planned,
    s.nano AS nanopore_planned,
    s.rna AS rna_planned,
    s.ilrna AS rna_ilmn_planned,
    ( SELECT count(*) AS count
           FROM ((public.illumina_library i
             JOIN public.dna_extraction d ON ((d.dna_id = i.dna_id)))
             JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
          WHERE (t.og_id = s.og_id)) AS illumina_actual,
    ( SELECT count(*) AS count
           FROM ((public.pacbio_library p
             JOIN public.dna_extraction d ON ((d.dna_id = p.dna_id)))
             JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
          WHERE (t.og_id = s.og_id)) AS hifi_actual,
    ( SELECT count(*) AS count
           FROM ((public.hic_library h
             JOIN public.hic_lysate y ON ((y.lysate_id = h.lysate_id)))
             JOIN public.tissue t ON ((t.tissue_id = y.tissue_id)))
          WHERE (t.og_id = s.og_id)) AS hic_actual,
    ( SELECT count(*) AS count
           FROM ((public.ont_library o
             JOIN public.dna_extraction d ON ((d.dna_id = o.dna_id)))
             JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
          WHERE (t.og_id = s.og_id)) AS nanopore_actual,
    ( SELECT count(*) AS count
           FROM (public.rna_extraction r
             JOIN public.tissue t ON ((t.tissue_id = r.tissue_id)))
          WHERE (t.og_id = s.og_id)) AS rna_actual,
    ( SELECT count(*) AS count
           FROM ((public.rna_library_ilmn x
             JOIN public.rna_extraction r ON ((r.rna_id = x.rna_id)))
             JOIN public.tissue t ON ((t.tissue_id = r.tissue_id)))
          WHERE (t.og_id = s.og_id)) AS rna_ilmn_actual,
    ( SELECT count(*) AS count
           FROM ((public.rna_library_kinx k
             JOIN public.rna_extraction r ON ((r.rna_id = k.rna_id)))
             JOIN public.tissue t ON ((t.tissue_id = r.tissue_id)))
          WHERE (t.og_id = s.og_id)) AS rna_kinnex_actual,
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
    s.comments
   FROM ((((((((public.sample s
     LEFT JOIN LATERAL ( SELECT d.status
           FROM (public.dna_extraction d
             JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
          WHERE (t.og_id = s.og_id)
          ORDER BY d.status_overwrite DESC NULLS LAST, d.ext_num DESC
         LIMIT 1) dna ON (true))
     LEFT JOIN LATERAL ( SELECT i.ilmn_status AS status
           FROM ((public.illumina_library i
             JOIN public.dna_extraction d ON ((d.dna_id = i.dna_id)))
             JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
          WHERE (t.og_id = s.og_id)
          ORDER BY i.status_overwrite DESC NULLS LAST, i.ilmn_num DESC
         LIMIT 1) ilmn ON (true))
     LEFT JOIN LATERAL ( SELECT p.pacb_status AS status
           FROM ((public.pacbio_library p
             JOIN public.dna_extraction d ON ((d.dna_id = p.dna_id)))
             JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
          WHERE (t.og_id = s.og_id)
          ORDER BY p.status_overwrite DESC NULLS LAST, p.pacb_num DESC
         LIMIT 1) pacb ON (true))
     LEFT JOIN LATERAL ( SELECT h.hic_status AS status
           FROM ((public.hic_library h
             JOIN public.hic_lysate y ON ((y.lysate_id = h.lysate_id)))
             JOIN public.tissue t ON ((t.tissue_id = y.tissue_id)))
          WHERE (t.og_id = s.og_id)
          ORDER BY h.status_overwrite DESC NULLS LAST, h.hic_num DESC
         LIMIT 1) hic ON (true))
     LEFT JOIN LATERAL ( SELECT o.ont_status AS status
           FROM ((public.ont_library o
             JOIN public.dna_extraction d ON ((d.dna_id = o.dna_id)))
             JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
          WHERE (t.og_id = s.og_id)
          ORDER BY o.status_overwrite DESC NULLS LAST, o.ont_num DESC
         LIMIT 1) ont ON (true))
     LEFT JOIN LATERAL ( SELECT r.status
           FROM (public.rna_extraction r
             JOIN public.tissue t ON ((t.tissue_id = r.tissue_id)))
          WHERE (t.og_id = s.og_id)
          ORDER BY r.status_overwrite DESC NULLS LAST, r.ext_num DESC
         LIMIT 1) rna ON (true))
     LEFT JOIN LATERAL ( SELECT x.rna_status AS status
           FROM ((public.rna_library_ilmn x
             JOIN public.rna_extraction r ON ((r.rna_id = x.rna_id)))
             JOIN public.tissue t ON ((t.tissue_id = r.tissue_id)))
          WHERE (t.og_id = s.og_id)
          ORDER BY x.status_overwrite DESC NULLS LAST, x.rna_num DESC
         LIMIT 1) rilm ON (true))
     LEFT JOIN LATERAL ( SELECT k.rna_status AS status
           FROM ((public.rna_library_kinx k
             JOIN public.rna_extraction r ON ((r.rna_id = k.rna_id)))
             JOIN public.tissue t ON ((t.tissue_id = r.tissue_id)))
          WHERE (t.og_id = s.og_id)
          ORDER BY k.status_overwrite DESC NULLS LAST, k.rna_num DESC
         LIMIT 1) rkin ON (true));


--
-- Name: VIEW summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.summary IS 'The workbook''s Summary sheet, computed from the child tables instead of copied from Excel (decision 5). This is what replaces the nine derived columns removed from v2.sample, and it is what fixes the status fragmentation of database_review.md Finding 7 at source: the 47 distinct rna_status values were Excel string concatenation being persisted. Each technology also reports planned (lab intent) against actual (counted).';


--
-- Name: COLUMN summary.illumina_planned; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.summary.illumina_planned IS 'Hand-entered lab intent from the Summary sheet''s "ilmn" column: is this sample slated for Illumina at all? Compare with illumina_actual.';


--
-- Name: COLUMN summary.illumina_actual; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.summary.illumina_actual IS 'Illumina libraries that actually exist for this sample, counted through tissue -> dna_extraction.';


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
               FROM public.summary sm
              WHERE ((sm.nominal_species_id = s.species) AND (sm.pacbio_status = ANY (ARRAY['Library Prep - PacBio SMRTbell'::text, 'QC - Femto'::text, 'Sequenced'::text, 'Sequenced, SRE'::text, 'Sequence - PacBio'::text, 'Shearing'::text, 'SRE'::text, 'SRE - ULI'::text, 'ULI'::text]))))) THEN 'in_lab'::text
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
              WHERE ((samp.nominal_species_id = s.species) AND (samp.workflow = 'Reference'::text) AND (samp.collector IS NOT NULL))
             LIMIT 1)
        END AS collected_by,
    NULL::text AS priority_flags,
    COALESCE(s.afd_common_name, '-'::text) AS common_name,
    COALESCE(s.synonym, '-'::text) AS synonym,
    NULL::text AS assigned_sequencing_center
   FROM public.master_species s
  ORDER BY s.family, s.species;


--
-- Name: VIEW goat_species_v1; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.goat_species_v1 IS 'GoaT species submission view. Differs from the public version only in reading pacbio status from v2.summary rather than sample.pb_status, which F5 removed. See docs/v2_cutover_dependencies.md.';


--
-- Name: import_quarantine; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_quarantine (
    quarantine_id bigint NOT NULL,
    source_table text NOT NULL,
    source_sheet text,
    source_row_key text,
    violation_type text NOT NULL,
    violation_detail text,
    raw_row jsonb NOT NULL,
    first_seen timestamp with time zone DEFAULT now() NOT NULL,
    last_seen timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    resolution_note text,
    CONSTRAINT import_quarantine_resolution_check CHECK (((resolution_note IS NULL) OR (resolved_at IS NOT NULL))),
    CONSTRAINT import_quarantine_violation_type_check CHECK ((violation_type = ANY (ARRAY['not_null'::text, 'foreign_key'::text, 'type_cast'::text, 'unique'::text, 'duplicate_source_row'::text, 'lookup'::text, 'conflicting_value'::text, 'check'::text, 'displaced'::text])))
);


--
-- Name: TABLE import_quarantine; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.import_quarantine IS 'Rows rejected by the v2 constraints, held for correction at source. Written by both the backfill (scripts/backfill_v2.sql) and the nightly import. See v2_scaffold_design_review.md decision 6.';


--
-- Name: COLUMN import_quarantine.source_table; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_quarantine.source_table IS 'Target v2 table the row was meant for, unqualified (e.g. "dna_extraction").';


--
-- Name: COLUMN import_quarantine.source_sheet; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_quarantine.source_sheet IS 'Originating workbook sheet, when known (e.g. "3.DNAExtractions"), so the lab can find the row to fix.';


--
-- Name: COLUMN import_quarantine.source_row_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_quarantine.source_row_key IS 'Business key of the rejected row - the tube ID, tissue ID, or og_id. Null when the row has no usable key, which is itself usually the violation.';


--
-- Name: COLUMN import_quarantine.raw_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_quarantine.raw_row IS 'The whole rejected row as jsonb, so nothing is lost and the row can be replayed after the source is fixed.';


--
-- Name: COLUMN import_quarantine.last_seen; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.import_quarantine.last_seen IS 'Bumped each time the same unresolved violation reappears. A stale last_seen means the source row is gone or fixed.';


--
-- Name: import_quarantine_quarantine_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.import_quarantine ALTER COLUMN quarantine_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.import_quarantine_quarantine_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: lca_raw_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lca_raw_results (
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
    confidence_score double precision,
    taxon_rank_db text,
    content_hash text NOT NULL
);


--
-- Name: TABLE lca_raw_results; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.lca_raw_results IS 'Unfiltered LCA output. lca_run_date is text here, matching v2.lca; the live tables disagree on its type while using it in equivalent uniqueness constraints. confidence_score is double precision, not real -- see the column note, and do not narrow it back.';


--
-- Name: COLUMN lca_raw_results.content_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lca_raw_results.content_hash IS 'See v2.lca.content_hash. Part of the key here because one BLAST accession can yield several HSPs in a single run, which share accession and run date but differ in percent_match -- 33 such rows exist in live today.';


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
     LEFT JOIN public.lca_pivot_view lp ON (((lp.og_id_lp = lv.og_id) AND (lp.tech = lv.tech) AND (lp.seq_date = lv.seq_date) AND (lp.code = lv.code) AND (lp.annotation = lv.annotation))))
     LEFT JOIN public.lca_results_view lr ON (((lr.og_id_lr = lv.og_id) AND (lr.tech = lv.tech) AND (lr.seq_date = lv.seq_date) AND (lr.code = lv.code) AND (lr.annotation = lv.annotation))))
     LEFT JOIN public.filtered_lca_view flv ON (((flv.og_id_flv = lv.og_id) AND (flv.tech = lv.tech) AND (flv.seq_date = lv.seq_date) AND (flv.code = lv.code) AND (flv.annotation = lv.annotation))))
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
          GROUP BY lca.og_id, lca.tech, lca.seq_date, lca.code, lca.annotation) lca_tax ON (((lca_tax.og_id = lv.og_id) AND (lca_tax.tech = lv.tech) AND (lca_tax.seq_date = lv.seq_date) AND (lca_tax.code = lv.code) AND (lca_tax.annotation = lv.annotation))))
     LEFT JOIN public.sample_view sv ON ((lv.og_id = sv.og_id_sv)));


--
-- Name: library; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.library (
    library_tube_id text NOT NULL,
    library_type text NOT NULL,
    dna_id text,
    rna_id text,
    lysate_id text,
    CONSTRAINT library_one_parent_check CHECK ((num_nonnulls(dna_id, rna_id, lysate_id) = 1)),
    CONSTRAINT library_type_check CHECK ((library_type = ANY (ARRAY['illumina'::text, 'pacbio'::text, 'ont'::text, 'hic'::text, 'rna_ilmn'::text, 'rna_kinx'::text])))
);


--
-- Name: TABLE library; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.library IS 'Identity registry giving every library, of any technology, one primary key so sequencing has a single FK target. It normalises nothing away: each technology table keeps all of its own columns and its own parent FK. Confirmed safe as a shared key - the two RNA library sheets have zero tube-ID overlap (312 distinct on 4.RNAIllumina with _IL/_dIL suffixes, 174 on 4.RNAkinnex with _KL). See lab_key_strategy.md §6.4.';


--
-- Name: COLUMN library.library_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.library.library_type IS 'Which technology table holds this library''s attributes. Replaces sequencing.seq_type, which import_data.py currently derives by testing for _D / _R substrings in the tube ID.';


--
-- Name: CONSTRAINT library_one_parent_check ON library; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT library_one_parent_check ON public.library IS 'Exactly one parent. Expressed as three typed nullable FK columns rather than a source_type/source_id pair, because a polymorphic reference cannot carry a real foreign key - which is the guarantee this whole design depends on.';


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
    annotation_updated_at timestamp with time zone
);


--
-- Name: TABLE mitogenome_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mitogenome_data IS 'Assembled mitogenome per (og_id, tech, seq_date, code). Parent of the LCA tables. Unlike the live table it has a foreign key to sample, so an assembly cannot reference a specimen that does not exist.';


--
-- Name: mitogenome_submission_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.mitogenome_submission_view AS
 SELECT s.og_num,
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
   FROM (((public.mitogenome_data m
     LEFT JOIN public.sample s ON ((s.og_id = m.og_id)))
     LEFT JOIN public.ena_validation_attempts e ON (((e.og_id = m.og_id) AND (e.tech = m.tech) AND (e.seq_date = m.seq_date) AND (e.code = m.code) AND (e.annotation = m.annotation))))
     LEFT JOIN public.lca_validation l ON (((l.og_id = m.og_id) AND (l.tech = m.tech) AND (l.seq_date = m.seq_date) AND (l.code = m.code) AND (l.annotation = m.annotation))));


--
-- Name: VIEW mitogenome_submission_view; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.mitogenome_submission_view IS 'One row per mitogenome assembly with its ENA validation result and validated species name, for ENA submission. v2 form of public.mitogenome_submission_view (029): og_num comes from v2.sample, because v2 drops it from mitogenome_data (F2). See migration 043.';


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
-- Name: og_workflow_assignment_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.og_workflow_assignment_log (
    id bigint NOT NULL,
    og_id text NOT NULL,
    workflow text NOT NULL,
    recommended_workflow text,
    note text,
    samples_updated integer NOT NULL,
    assigned_by text NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT og_workflow_assignment_log_workflow_check CHECK ((workflow = ANY (ARRAY['Reference'::text, 'Draft'::text])))
);


--
-- Name: TABLE og_workflow_assignment_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.og_workflow_assignment_log IS 'Audit log of workflow assignments made with the Assign button in OceanGenom_Web: which OG, which workflow, the recommendation at the time, who and when.';


--
-- Name: og_workflow_assignment_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.og_workflow_assignment_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: og_workflow_assignment_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.og_workflow_assignment_log_id_seq OWNED BY public.og_workflow_assignment_log.id;


--
-- Name: og_workflow_notification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.og_workflow_notification (
    id bigint NOT NULL,
    kind text NOT NULL,
    og_id text NOT NULL,
    workflow text,
    recommended_workflow text,
    actor text,
    source text DEFAULT 'site'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT og_workflow_notification_kind_check CHECK ((kind = ANY (ARRAY['recommendation'::text, 'assigned'::text]))),
    CONSTRAINT og_workflow_notification_source_check CHECK ((source = ANY (ARRAY['site'::text, 'database'::text])))
);


--
-- Name: TABLE og_workflow_notification; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.og_workflow_notification IS 'Notification feed for OceanGenom_Web: new workflow recommendations and workflow assignments.';


--
-- Name: og_workflow_notification_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.og_workflow_notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: og_workflow_notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.og_workflow_notification_id_seq OWNED BY public.og_workflow_notification.id;


--
-- Name: og_workflow_recommendation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.og_workflow_recommendation (
    og_id text NOT NULL,
    recommended_workflow text,
    note text,
    updated_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT og_workflow_recommendation_recommended_workflow_check CHECK ((recommended_workflow = ANY (ARRAY['Reference'::text, 'Draft'::text])))
);


--
-- Name: TABLE og_workflow_recommendation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.og_workflow_recommendation IS 'Recommended sequencing workflow for OGs whose public.sample.workflow is still ''Not assigned''. Edited in the OceanGenom_Web Unassigned Workflows tab; a row is deleted when the workflow is assigned.';


--
-- Name: prep_automation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prep_automation (
    prep_automation text NOT NULL,
    description text
);


--
-- Name: TABLE prep_automation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.prep_automation IS 'Controlled vocabulary for the spreadsheet''s "Manual/ Automated Method" column, shared by illumina_library and pacbio_library. 4.Illumina currently spells the automated value "Auomated Biomek i7" (missing t) in all 941 populated rows while 4.PacBio spells it correctly; a shared lookup makes that a backfill normalisation instead of two permanently divergent free-text columns. See v2_scaffold_design_review.md F12.';


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
-- Name: rna_qc_kinnex; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rna_qc_kinnex (
    rna_tube_id text NOT NULL,
    rna_tube_id_2 text,
    read_count bigint,
    run_id text NOT NULL,
    read_length_mean integer,
    read_length_n50 integer
);


--
-- Name: TABLE rna_qc_kinnex; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.rna_qc_kinnex IS 'Kinnex RNA read QC: one row per library (rna_tube_id) per sequencing run (run_id). rna_tube_id_2 is a second library pooled into the same QC row. Keys and FKs: migration 061.';


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    filename text NOT NULL,
    sha256 text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.schema_migrations IS 'Migration ledger for sql/. One row per applied file, with a SHA-256 of its contents so an applied migration cannot be edited unnoticed. Written by bin/apply_migrations.py; never populate it by hand. Created by 000_bootstrap_schema_migrations.sql, which must be run with psql before the first apply_migrations.py invocation on an empty database.';


--
-- Name: sequencing; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sequencing (
    sequencing_id text NOT NULL,
    library_tube_id text NOT NULL,
    status text,
    technology text,
    instrument text,
    run_date date,
    run_id text,
    seq_date text GENERATED ALWAYS AS (split_part(run_id, '_'::text, 2)) STORED,
    cell_id text,
    smrt_num integer,
    seq_type text,
    design_no integer,
    hic_depth text,
    seq_comments text
);


--
-- Name: TABLE sequencing; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.sequencing IS 'One row per sequencing record. Source: the 5.Sequencing sheet.';


--
-- Name: COLUMN sequencing.library_tube_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sequencing.library_tube_id IS 'The single library sequenced, via the registry. Replaces five nullable polymorphic columns, one of which could not carry a foreign key at all.';


--
-- Name: COLUMN sequencing.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sequencing.status IS 'Spreadsheet header "Status". Populated on 4,004 of ~4,014 rows; the live sequencing table has no status column at all, so this has always been dropped.';


--
-- Name: COLUMN sequencing.seq_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sequencing.seq_type IS 'Retained for the existing consumers that filter on it. library.library_type is now the authoritative technology label; derive this from it at cutover rather than having the importer compute it.';


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
-- Name: v_dna_extraction_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_dna_extraction_browse AS
 SELECT s.og_num,
    t.og_id,
    d.tissue_id,
    d.dna_id,
    d.ext_num,
    (d.ext_num = max(d.ext_num) OVER (PARTITION BY d.tissue_id)) AS is_latest,
    d.status,
    d.status_overwrite,
    d.extraction_method,
    d.extraction_date,
    d.extraction_batch_id,
    d.qubit_conc,
    d.total_yield,
    d.av_size,
    d.extraction_qc,
    d.extract_plate,
    d.extract_plate_well,
    d.comment
   FROM ((public.dna_extraction d
     JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_dna_extraction_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_dna_extraction_browse IS 'DNA extractions with og_id and is_latest, neither of which is stored on the base table.';


--
-- Name: COLUMN v_dna_extraction_browse.is_latest; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.v_dna_extraction_browse.is_latest IS 'True when this row has the highest ext_num for its tissue. A faithful translation of the workbook''s Latest formula, MAX(#) per parent — including its behaviour on ties, which is why unique(tissue_id, ext_num) matters.';


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
-- Name: v_hic_library_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_hic_library_browse AS
 SELECT s.og_num,
    t.og_id,
    y.tissue_id,
    h.lysate_id,
    h.hic_library_tube_id,
    h.hic_num,
    (h.hic_num = max(h.hic_num) OVER (PARTITION BY h.lysate_id)) AS is_latest,
    h.hic_status,
    h.status_overwrite,
    h.library_method,
    h.processing_notes,
    h.library_date,
    h.library_id,
    y.prox_ligation_conc,
    h.prox_ligation_conc AS prox_ligation_conc_legacy,
    h.purified_dna_total,
    h.index_set,
    h.index_i5,
    h.index_i7,
    h.library_conc,
    h.library_yield,
    h.library_size,
    h.pcr_dup_read_pairs,
    h.nodup_cis_read_pairs_1kb,
    h.expected_distinct_30m_reads,
    h.hic_comments
   FROM (((public.hic_library h
     JOIN public.hic_lysate y ON ((y.lysate_id = h.lysate_id)))
     JOIN public.tissue t ON ((t.tissue_id = y.tissue_id)))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_hic_library_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_hic_library_browse IS 'Hi-C libraries with og_id and is_latest. Exposes the lysate proximity-ligation value as prox_ligation_conc and the legacy library-level one separately.';


--
-- Name: v_hic_lysate_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_hic_lysate_browse AS
 SELECT s.og_num,
    t.og_id,
    y.tissue_id,
    y.lysate_id,
    y.lysate_num,
    (y.lysate_num = max(y.lysate_num) OVER (PARTITION BY y.tissue_id)) AS is_latest,
    y.lysate_status,
    y.status_overwrite,
    y.lysate_method,
    y.lysate_prep_date,
    y.lysate_batch_id,
    y.lysate_conc,
    y.total_lysate,
    y.lysate_cde,
    y.prox_ligation_date,
    y.prox_ligation_conc,
    y.prox_ligation_yield,
    y.lysate_comments
   FROM ((public.hic_lysate y
     JOIN public.tissue t ON ((t.tissue_id = y.tissue_id)))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_hic_lysate_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_hic_lysate_browse IS 'Hi-C lysates with og_id and is_latest, including the live proximity-ligation columns.';


--
-- Name: v_illumina_library_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_illumina_library_browse AS
 SELECT s.og_num,
    t.og_id,
    d.tissue_id,
    i.dna_id,
    i.illumina_library_tube_id,
    i.ilmn_num,
    (i.ilmn_num = max(i.ilmn_num) OVER (PARTITION BY i.dna_id)) AS is_latest,
    i.ilmn_status,
    i.status_overwrite,
    i.library_method,
    i.prep_automation,
    i.library_date,
    i.library_id,
    i.library_plate_well,
    i.index_plate,
    i.index_set,
    i.index_well,
    i.index_idx,
    i.library_qubit_conc,
    i.il_comments
   FROM (((public.illumina_library i
     JOIN public.dna_extraction d ON ((d.dna_id = i.dna_id)))
     JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_illumina_library_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_illumina_library_browse IS 'Illumina DNA libraries with og_id and is_latest.';


--
-- Name: v_library_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_library_browse AS
 SELECT s.og_num,
    t.og_id,
    t.tissue_id,
    l.library_tube_id,
    l.library_type,
    COALESCE(l.dna_id, l.rna_id, l.lysate_id) AS parent_id,
    l.dna_id,
    l.rna_id,
    l.lysate_id
   FROM (((((public.library l
     LEFT JOIN public.dna_extraction d ON ((d.dna_id = l.dna_id)))
     LEFT JOIN public.rna_extraction r ON ((r.rna_id = l.rna_id)))
     LEFT JOIN public.hic_lysate y ON ((y.lysate_id = l.lysate_id)))
     JOIN public.tissue t ON ((t.tissue_id = COALESCE(d.tissue_id, r.tissue_id, y.tissue_id))))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_library_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_library_browse IS 'All libraries of every technology, one row each, with og_id resolved through whichever parent chain applies. The registry made browsable.';


--
-- Name: v_ont_library_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ont_library_browse AS
 SELECT s.og_num,
    t.og_id,
    d.tissue_id,
    o.dna_id,
    o.ont_library_tube_id,
    o.ont_num,
    (o.ont_num = max(o.ont_num) OVER (PARTITION BY o.dna_id, o.library_method)) AS is_latest,
    o.ont_status,
    o.status_overwrite,
    o.library_method,
    o.library_type,
    o.library_date,
    o.library_id,
    o.est_loading_size,
    o.ont_comments
   FROM (((public.ont_library o
     JOIN public.dna_extraction d ON ((d.dna_id = o.dna_id)))
     JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_ont_library_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_ont_library_browse IS 'ONT libraries with og_id and is_latest. is_latest is per kit (library_method), because the lab numbers attempts per kit.';


--
-- Name: v_pacbio_library_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_pacbio_library_browse AS
 SELECT s.og_num,
    t.og_id,
    d.tissue_id,
    p.dna_id,
    p.pacbio_library_tube_id,
    p.pacb_num,
    (p.pacb_num = max(p.pacb_num) OVER (PARTITION BY p.dna_id)) AS is_latest,
    p.pacb_status,
    p.status_overwrite,
    p.dna_treatment,
    p.sre_kit,
    p.post_sre_conc,
    p.final_pre_library_conc,
    p.shear_femtol_id,
    p.shear_av_size,
    p.library_method,
    p.prep_automation,
    p.library_date,
    p.library_id,
    p.index_well,
    p.barcode,
    p.seq_femto_id,
    p.seq_av_size,
    p.library_conc,
    p.comment
   FROM (((public.pacbio_library p
     JOIN public.dna_extraction d ON ((d.dna_id = p.dna_id)))
     JOIN public.tissue t ON ((t.tissue_id = d.tissue_id)))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_pacbio_library_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_pacbio_library_browse IS 'PacBio HiFi libraries with og_id and is_latest.';


--
-- Name: v_quarantine_displaced; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_quarantine_displaced AS
 SELECT import_quarantine.source_table,
    import_quarantine.source_row_key AS displaced_key,
    import_quarantine.violation_detail AS replaced_by,
    import_quarantine.first_seen AS displaced_at,
    import_quarantine.raw_row
   FROM public.import_quarantine
  WHERE ((import_quarantine.resolved_at IS NULL) AND (import_quarantine.violation_type = 'displaced'::text))
  ORDER BY import_quarantine.first_seen DESC, import_quarantine.source_table, import_quarantine.source_row_key;


--
-- Name: VIEW v_quarantine_displaced; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_quarantine_displaced IS 'Seated rows import_v2.py deleted because the workbook assigned their attempt slot to another tube ID. raw_row holds the deleted row in full.';


--
-- Name: v_quarantine_open; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_quarantine_open AS
 SELECT import_quarantine.source_table,
    import_quarantine.violation_type,
    count(*) AS rows_blocked,
    min(import_quarantine.first_seen) AS oldest,
    max(import_quarantine.last_seen) AS most_recent
   FROM public.import_quarantine
  WHERE ((import_quarantine.resolved_at IS NULL) AND (import_quarantine.violation_type <> 'displaced'::text))
  GROUP BY import_quarantine.source_table, import_quarantine.violation_type
  ORDER BY (count(*)) DESC, import_quarantine.source_table, import_quarantine.violation_type;


--
-- Name: VIEW v_quarantine_open; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_quarantine_open IS 'One line per (table, violation) still blocking rows. The lab-facing summary of what needs fixing. Excludes displaced rows, which block nothing; see v_quarantine_displaced.';


--
-- Name: v_rna_extraction_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_rna_extraction_browse AS
 SELECT s.og_num,
    t.og_id,
    r.tissue_id,
    r.rna_id,
    r.ext_num,
    (r.ext_num = max(r.ext_num) OVER (PARTITION BY r.tissue_id)) AS is_latest,
    r.status,
    r.status_overwrite,
    r.extraction_method,
    r.extraction_date,
    r.extraction_batch_id,
    r.qubit_conc,
    r.total_yield,
    r.rna_dv200,
    r.rin,
    r.gdna_over_7kb_perc,
    r.extraction_qc,
    r.comment
   FROM ((public.rna_extraction r
     JOIN public.tissue t ON ((t.tissue_id = r.tissue_id)))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_rna_extraction_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_rna_extraction_browse IS 'RNA extractions with og_id and is_latest.';


--
-- Name: v_rna_library_ilmn_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_rna_library_ilmn_browse AS
 SELECT s.og_num,
    t.og_id,
    r.tissue_id,
    x.rna_id,
    x.rna_library_tube_id,
    x.rna_num,
    (x.rna_num = max(x.rna_num) OVER (PARTITION BY x.rna_id, x.library_method)) AS is_latest,
    x.rna_status,
    x.status_overwrite,
    x.library_method,
    x.library_date,
    x.library_id,
    x.library_size,
    x.perc_product,
    x.library_qubit_conc,
    x.library_molarity,
    x.index_set,
    x.index_well,
    x.index_inx,
    x.final_plate_name,
    x.final_plate_well,
    x.well_position,
    x.comments
   FROM (((public.rna_library_ilmn x
     JOIN public.rna_extraction r ON ((r.rna_id = x.rna_id)))
     JOIN public.tissue t ON ((t.tissue_id = r.tissue_id)))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_rna_library_ilmn_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_rna_library_ilmn_browse IS 'Illumina RNA libraries with og_id and is_latest. is_latest is per library_method, because the lab numbers attempts per method (mRNA _IL and ribosomal-depletion _dIL each start at #1).';


--
-- Name: v_rna_library_kinx_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_rna_library_kinx_browse AS
 SELECT s.og_num,
    t.og_id,
    r.tissue_id,
    k.rna_id,
    k.rna_library_tube_id,
    k.rna_num,
    (k.rna_num = max(k.rna_num) OVER (PARTITION BY k.rna_id)) AS is_latest,
    k.rna_status,
    k.status_overwrite,
    k.library_method,
    k.processing_comment,
    k.synthesis_date,
    k.part1_batch_id,
    k.synthesis_conc,
    k.part2_batch_id,
    k.final_qubit_conc,
    k.library_size,
    k.kinnex_primers,
    k.kinnex_barcode,
    k.pool_id,
    k.plate,
    k.plate_location,
    k.sequencing_sample_id,
    k.comments
   FROM (((public.rna_library_kinx k
     JOIN public.rna_extraction r ON ((r.rna_id = k.rna_id)))
     JOIN public.tissue t ON ((t.tissue_id = r.tissue_id)))
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_rna_library_kinx_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_rna_library_kinx_browse IS 'PacBio Kinnex RNA libraries with og_id and is_latest.';


--
-- Name: v_sequencing_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sequencing_browse AS
 SELECT b.og_num,
    b.og_id,
    b.tissue_id,
    b.parent_id,
    b.library_tube_id,
    b.library_type,
    q.sequencing_id,
    q.status,
    q.technology,
    q.instrument,
    q.run_date,
    q.run_id,
    q.seq_date,
    q.cell_id,
    q.smrt_num,
    q.seq_type,
    q.design_no,
    q.hic_depth,
    q.seq_comments
   FROM (public.sequencing q
     JOIN public.v_library_browse b ON ((b.library_tube_id = q.library_tube_id)));


--
-- Name: VIEW v_sequencing_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_sequencing_browse IS 'Sequencing records with the full ancestor chain, through the library registry.';


--
-- Name: v_tissue_browse; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_tissue_browse AS
 SELECT s.og_num,
    s.og_id,
    s.nominal_species_id,
    t.tissue_id,
    t.tissue,
    t.preservation,
    t.extracted,
    t.freezer,
    t.shelf,
    t.rack,
    t.level,
    t.box,
    t.comment
   FROM (public.tissue t
     JOIN public.sample s ON ((s.og_id = t.og_id)));


--
-- Name: VIEW v_tissue_browse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_tissue_browse IS 'Tissues with specimen context. Read-only; import against v2.tissue.';


--
-- Name: value_conversions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.value_conversions (
    source_table text NOT NULL,
    row_key text NOT NULL,
    column_name text NOT NULL,
    raw_value text NOT NULL,
    stored_value text,
    rule text NOT NULL,
    converted_by text NOT NULL,
    first_seen timestamp with time zone DEFAULT now() NOT NULL,
    last_seen timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT value_conversions_rule_check CHECK ((rule = ANY (ARRAY['no_value'::text, 'unit'::text, 'bound'::text, 'surface'::text, 'length'::text, 'dms'::text, 'excel_serial_coordinate'::text, 'dms_assumed_hemisphere'::text, 'length_split'::text, 'depth_range'::text])))
);


--
-- Name: TABLE value_conversions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.value_conversions IS 'Values stored by a conversion rule (OceanOmics-Database/v2_value_rules.py) rather than as typed, with the raw text. Lets a rule''s effect be audited or undone, e.g. bounds stored as numbers. Written by import_v2.py and scripts/apply_value_rules.py. See migration 041.';


--
-- Name: COLUMN value_conversions.stored_value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.value_conversions.stored_value IS 'What was stored, as text; NULL for rule no_value.';


--
-- Name: COLUMN value_conversions.converted_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.value_conversions.converted_by IS 'import_v2.py or apply_value_rules.py.';


--
-- Name: workbook_attempt_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workbook_attempt_keys (
    source_table text NOT NULL,
    row_key text NOT NULL,
    parent_key text,
    attempt_scope text,
    attempt_num integer,
    workbook_file text NOT NULL,
    staged_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE workbook_attempt_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.workbook_attempt_keys IS 'Attempt-keyed rows of the lab workbook, staged by import_v2.py --stage-attempt-keys so backfill_v2.sql can prefer the workbook''s side of a tie. Replaced wholesale on each staging run; workbook_file records which workbook.';


--
-- Name: og_workflow_assignment_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.og_workflow_assignment_log ALTER COLUMN id SET DEFAULT nextval('public.og_workflow_assignment_log_id_seq'::regclass);


--
-- Name: og_workflow_notification id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.og_workflow_notification ALTER COLUMN id SET DEFAULT nextval('public.og_workflow_notification_id_seq'::regclass);


--
-- Name: species Species_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.species
    ADD CONSTRAINT "Species_pkey" PRIMARY KEY (species);


--
-- Name: blast_filtered_lca blast_filtered_lca_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blast_filtered_lca
    ADD CONSTRAINT blast_filtered_lca_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, match_sequence_id, region);


--
-- Name: design_description design_description_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.design_description
    ADD CONSTRAINT design_description_pk PRIMARY KEY (design_no);


--
-- Name: dna_extraction dna_extraction_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dna_extraction
    ADD CONSTRAINT dna_extraction_attempt_key UNIQUE (tissue_id, ext_num) DEFERRABLE;


--
-- Name: CONSTRAINT dna_extraction_attempt_key ON dna_extraction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT dna_extraction_attempt_key ON public.dna_extraction IS 'The spreadsheet''s own "Latest" formula, MAX(#) per parent, is only correct if this holds - a tie marks two rows as latest. It fails on 5 of 2,223 rows here; those rows quarantine for the lab to renumber. (The "53 of 321 on 4.RNAIllumina" once cited as the worst case were not ties: that sheet numbers attempts per library method -- see rna_library_ilmn_attempt_key.) DEFERRABLE INITIALLY IMMEDIATE, as are all nine attempt keys: every statement still checks it, but import_v2.py defers it within one table step so that a renumber or a swap of two attempt numbers -- legitimate edits -- can land in a single upsert.';


--
-- Name: dna_extraction dna_extraction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dna_extraction
    ADD CONSTRAINT dna_extraction_pkey PRIMARY KEY (dna_id);


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
-- Name: hic_library hic_library_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_library
    ADD CONSTRAINT hic_library_attempt_key UNIQUE (lysate_id, hic_num) DEFERRABLE;


--
-- Name: hic_library hic_library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_library
    ADD CONSTRAINT hic_library_pkey PRIMARY KEY (hic_library_tube_id);


--
-- Name: hic_lysate hic_lysate_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_lysate
    ADD CONSTRAINT hic_lysate_attempt_key UNIQUE (tissue_id, lysate_num) DEFERRABLE;


--
-- Name: hic_lysate hic_lysate_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_lysate
    ADD CONSTRAINT hic_lysate_pkey PRIMARY KEY (lysate_id);


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
-- Name: illumina_library illumina_library_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.illumina_library
    ADD CONSTRAINT illumina_library_attempt_key UNIQUE (dna_id, ilmn_num) DEFERRABLE;


--
-- Name: illumina_library illumina_library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.illumina_library
    ADD CONSTRAINT illumina_library_pkey PRIMARY KEY (illumina_library_tube_id);


--
-- Name: import_quarantine import_quarantine_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_quarantine
    ADD CONSTRAINT import_quarantine_pkey PRIMARY KEY (quarantine_id);


--
-- Name: lca lca_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT lca_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, region, content_hash);


--
-- Name: lca_raw_results lca_raw_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT lca_raw_results_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, sequence_region, accession_id, content_hash);


--
-- Name: lca_validation lca_validation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT lca_validation_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation);


--
-- Name: library library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library
    ADD CONSTRAINT library_pkey PRIMARY KEY (library_tube_id);


--
-- Name: library library_tube_dna_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library
    ADD CONSTRAINT library_tube_dna_key UNIQUE (library_tube_id, dna_id);


--
-- Name: library library_tube_lysate_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library
    ADD CONSTRAINT library_tube_lysate_key UNIQUE (library_tube_id, lysate_id);


--
-- Name: library library_tube_rna_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library
    ADD CONSTRAINT library_tube_rna_key UNIQUE (library_tube_id, rna_id);


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
-- Name: mitogenome_data mitogenome_data_annotation_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mitogenome_data
    ADD CONSTRAINT mitogenome_data_annotation_key UNIQUE (og_id, tech, seq_date, code, annotation);


--
-- Name: mitogenome_data mitogenome_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mitogenome_data
    ADD CONSTRAINT mitogenome_data_pkey PRIMARY KEY (og_id, tech, seq_date, code);


--
-- Name: ncbi_genome_assemblies ncbi_genome_assemblies_assembly_accession_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ncbi_genome_assemblies
    ADD CONSTRAINT ncbi_genome_assemblies_assembly_accession_key UNIQUE (assembly_accession);


--
-- Name: og_workflow_assignment_log og_workflow_assignment_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.og_workflow_assignment_log
    ADD CONSTRAINT og_workflow_assignment_log_pkey PRIMARY KEY (id);


--
-- Name: og_workflow_notification og_workflow_notification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.og_workflow_notification
    ADD CONSTRAINT og_workflow_notification_pkey PRIMARY KEY (id);


--
-- Name: og_workflow_recommendation og_workflow_recommendation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.og_workflow_recommendation
    ADD CONSTRAINT og_workflow_recommendation_pkey PRIMARY KEY (og_id);


--
-- Name: ont_library ont_library_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ont_library
    ADD CONSTRAINT ont_library_attempt_key UNIQUE (dna_id, library_method, ont_num) DEFERRABLE;


--
-- Name: CONSTRAINT ont_library_attempt_key ON ont_library; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT ont_library_attempt_key ON public.ont_library IS 'Per method, not per DNA: the lab numbers each kit separately (Ligation Kit LSK, Ultra Long Kit ULK), so both are #1. True of all 3 DNAs with both in OceanGenomes_Database_261006.xlsx (Phase V.2, 2026-10-06). A NULL library_method never collides.';


--
-- Name: ont_library ont_library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ont_library
    ADD CONSTRAINT ont_library_pkey PRIMARY KEY (ont_library_tube_id);


--
-- Name: pacbio_library pacbio_library_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pacbio_library
    ADD CONSTRAINT pacbio_library_attempt_key UNIQUE (dna_id, pacb_num) DEFERRABLE;


--
-- Name: pacbio_library pacbio_library_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pacbio_library
    ADD CONSTRAINT pacbio_library_pkey PRIMARY KEY (pacbio_library_tube_id);


--
-- Name: prep_automation prep_automation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prep_automation
    ADD CONSTRAINT prep_automation_pkey PRIMARY KEY (prep_automation);


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
-- Name: rna_extraction rna_extraction_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_extraction
    ADD CONSTRAINT rna_extraction_attempt_key UNIQUE (tissue_id, ext_num) DEFERRABLE;


--
-- Name: rna_extraction rna_extraction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_extraction
    ADD CONSTRAINT rna_extraction_pkey PRIMARY KEY (rna_id);


--
-- Name: rna_library_ilmn rna_library_ilmn_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_ilmn
    ADD CONSTRAINT rna_library_ilmn_attempt_key UNIQUE (rna_id, library_method, rna_num) DEFERRABLE;


--
-- Name: CONSTRAINT rna_library_ilmn_attempt_key ON rna_library_ilmn; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT rna_library_ilmn_attempt_key ON public.rna_library_ilmn IS 'Per method, not per RNA: the lab restarts # at 1 for each library method, so the first stranded-mRNA library (_IL) and the first ribosomal-depletion library (_dIL) from one RNA are both #1. True of all 51 RNAs with both in OceanGenomes_Database_261006.xlsx (Phase V.2, 2026-10-06). Keyed on (rna_id, rna_num) those were 56 false ties, and in 31 of the 59 across this table and ont_library the import kept a failed library over a sequenced one. A NULL library_method never collides.';


--
-- Name: rna_library_ilmn rna_library_ilmn_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_ilmn
    ADD CONSTRAINT rna_library_ilmn_pkey PRIMARY KEY (rna_library_tube_id);


--
-- Name: rna_library_kinx rna_library_kinx_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_kinx
    ADD CONSTRAINT rna_library_kinx_attempt_key UNIQUE (rna_id, rna_num) DEFERRABLE;


--
-- Name: rna_library_kinx rna_library_kinx_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_kinx
    ADD CONSTRAINT rna_library_kinx_pkey PRIMARY KEY (rna_library_tube_id);


--
-- Name: rna_qc_kinnex rna_qc_kinnex_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_qc_kinnex
    ADD CONSTRAINT rna_qc_kinnex_pkey PRIMARY KEY (run_id, rna_tube_id);


--
-- Name: sample sample_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sample
    ADD CONSTRAINT sample_pkey PRIMARY KEY (og_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (filename);


--
-- Name: sequencing sequencing_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sequencing
    ADD CONSTRAINT sequencing_pkey PRIMARY KEY (sequencing_id);


--
-- Name: species_ncbi_assembly species_ncbi_assembly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.species_ncbi_assembly
    ADD CONSTRAINT species_ncbi_assembly_pkey PRIMARY KEY (assembly_accession);


--
-- Name: tissue tissue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tissue
    ADD CONSTRAINT tissue_pkey PRIMARY KEY (tissue_id);


--
-- Name: value_conversions value_conversions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.value_conversions
    ADD CONSTRAINT value_conversions_pkey PRIMARY KEY (source_table, row_key, column_name);


--
-- Name: workbook_attempt_keys workbook_attempt_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workbook_attempt_keys
    ADD CONSTRAINT workbook_attempt_keys_pkey PRIMARY KEY (source_table, row_key);


--
-- Name: blast_filtered_lca_og_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX blast_filtered_lca_og_id_idx ON public.blast_filtered_lca USING btree (og_id);


--
-- Name: dna_extraction_tissue_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dna_extraction_tissue_id_idx ON public.dna_extraction USING btree (tissue_id);


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
-- Name: hic_library_lysate_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hic_library_lysate_id_idx ON public.hic_library USING btree (lysate_id);


--
-- Name: hic_lysate_tissue_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hic_lysate_tissue_id_idx ON public.hic_lysate USING btree (tissue_id);


--
-- Name: idx_ref_genomes_sra_uploads_og_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ref_genomes_sra_uploads_og_id ON public.ref_genomes_sra_uploads USING btree (og_id);


--
-- Name: illumina_library_dna_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX illumina_library_dna_id_idx ON public.illumina_library USING btree (dna_id);


--
-- Name: import_quarantine_open_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX import_quarantine_open_idx ON public.import_quarantine USING btree (source_table, last_seen DESC) WHERE (resolved_at IS NULL);


--
-- Name: import_quarantine_open_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX import_quarantine_open_key ON public.import_quarantine USING btree (source_table, COALESCE(source_row_key, ''::text), violation_type) WHERE (resolved_at IS NULL);


--
-- Name: lca_mitogenome_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lca_mitogenome_idx ON public.lca USING btree (og_id, tech, seq_date, code);


--
-- Name: lca_og_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lca_og_id_idx ON public.lca USING btree (og_id);


--
-- Name: lca_raw_results_mito_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lca_raw_results_mito_idx ON public.lca_raw_results USING btree (og_id, tech, seq_date, code);


--
-- Name: lca_raw_results_og_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lca_raw_results_og_id_idx ON public.lca_raw_results USING btree (og_id);


--
-- Name: lca_validation_og_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX lca_validation_og_id_idx ON public.lca_validation USING btree (og_id);


--
-- Name: library_dna_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX library_dna_id_idx ON public.library USING btree (dna_id);


--
-- Name: library_lysate_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX library_lysate_id_idx ON public.library USING btree (lysate_id);


--
-- Name: library_rna_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX library_rna_id_idx ON public.library USING btree (rna_id);


--
-- Name: library_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX library_type_idx ON public.library USING btree (library_type);


--
-- Name: mitogenome_data_og_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mitogenome_data_og_id_idx ON public.mitogenome_data USING btree (og_id);


--
-- Name: og_workflow_assignment_log_assigned_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX og_workflow_assignment_log_assigned_at_idx ON public.og_workflow_assignment_log USING btree (assigned_at);


--
-- Name: og_workflow_assignment_log_og_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX og_workflow_assignment_log_og_id_idx ON public.og_workflow_assignment_log USING btree (og_id);


--
-- Name: og_workflow_notification_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX og_workflow_notification_created_at_idx ON public.og_workflow_notification USING btree (created_at DESC);


--
-- Name: og_workflow_notification_og_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX og_workflow_notification_og_id_idx ON public.og_workflow_notification USING btree (og_id);


--
-- Name: ont_library_dna_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ont_library_dna_id_idx ON public.ont_library USING btree (dna_id);


--
-- Name: pacbio_library_dna_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pacbio_library_dna_id_idx ON public.pacbio_library USING btree (dna_id);


--
-- Name: raw_data_og_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX raw_data_og_id_idx ON public.raw_data USING btree (og_id);


--
-- Name: raw_qc_og_id_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX raw_qc_og_id_uq ON public.raw_qc USING btree (og_id);


--
-- Name: rna_extraction_tissue_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rna_extraction_tissue_id_idx ON public.rna_extraction USING btree (tissue_id);


--
-- Name: rna_library_ilmn_rna_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rna_library_ilmn_rna_id_idx ON public.rna_library_ilmn USING btree (rna_id);


--
-- Name: rna_library_kinx_rna_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rna_library_kinx_rna_id_idx ON public.rna_library_kinx USING btree (rna_id);


--
-- Name: rna_qc_kinnex_rna_tube_id_2_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rna_qc_kinnex_rna_tube_id_2_idx ON public.rna_qc_kinnex USING btree (rna_tube_id_2);


--
-- Name: rna_qc_kinnex_rna_tube_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rna_qc_kinnex_rna_tube_id_idx ON public.rna_qc_kinnex USING btree (rna_tube_id);


--
-- Name: sequencing_library_tube_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sequencing_library_tube_id_idx ON public.sequencing USING btree (library_tube_id);


--
-- Name: species_ncbi_assembly_one_chosen_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX species_ncbi_assembly_one_chosen_idx ON public.species_ncbi_assembly USING btree (species) WHERE is_chosen;


--
-- Name: species_ncbi_assembly_species_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX species_ncbi_assembly_species_idx ON public.species_ncbi_assembly USING btree (species);


--
-- Name: tissue_og_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tissue_og_id_idx ON public.tissue USING btree (og_id);


--
-- Name: value_conversions_rule_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX value_conversions_rule_idx ON public.value_conversions USING btree (rule);


--
-- Name: lca lca_content_hash; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER lca_content_hash BEFORE INSERT OR UPDATE ON public.lca FOR EACH ROW EXECUTE FUNCTION public.lca_set_content_hash();


--
-- Name: lca_raw_results lca_raw_results_content_hash; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER lca_raw_results_content_hash BEFORE INSERT OR UPDATE ON public.lca_raw_results FOR EACH ROW EXECUTE FUNCTION public.lca_set_content_hash();


--
-- Name: embargo_assignment_view trg_embargo_assignment_view_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_embargo_assignment_view_upd INSTEAD OF UPDATE ON public.embargo_assignment_view FOR EACH ROW EXECUTE FUNCTION public.embargo_assignment_view_upd();


--
-- Name: lca_validation_report_view trg_lca_validation_report_view_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lca_validation_report_view_upd INSTEAD OF UPDATE ON public.lca_validation_report_view FOR EACH ROW EXECUTE FUNCTION public.lca_validation_report_view_upd();


--
-- Name: blast_filtered_lca blast_filtered_lca_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blast_filtered_lca
    ADD CONSTRAINT blast_filtered_lca_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: dna_extraction dna_extraction_tissue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dna_extraction
    ADD CONSTRAINT dna_extraction_tissue_id_fkey FOREIGN KEY (tissue_id) REFERENCES public.tissue(tissue_id);


--
-- Name: ena_related_assemblies ena_related_assemblies_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_related_assemblies
    ADD CONSTRAINT ena_related_assemblies_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.ena_specimen_accessions(og_id);


--
-- Name: ena_specimen_accessions ena_specimen_accessions_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ena_specimen_accessions
    ADD CONSTRAINT ena_specimen_accessions_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: master_species_genome fk_master_species_genome_species; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.master_species_genome
    ADD CONSTRAINT fk_master_species_genome_species FOREIGN KEY (species) REFERENCES public.master_species(species) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: hic_library hic_library_lysate_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_library
    ADD CONSTRAINT hic_library_lysate_id_fkey FOREIGN KEY (lysate_id) REFERENCES public.hic_lysate(lysate_id);


--
-- Name: hic_library hic_library_registry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_library
    ADD CONSTRAINT hic_library_registry_fkey FOREIGN KEY (hic_library_tube_id, lysate_id) REFERENCES public.library(library_tube_id, lysate_id);


--
-- Name: hic_lysate hic_lysate_tissue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_lysate
    ADD CONSTRAINT hic_lysate_tissue_id_fkey FOREIGN KEY (tissue_id) REFERENCES public.tissue(tissue_id);


--
-- Name: illumina_library illumina_library_dna_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.illumina_library
    ADD CONSTRAINT illumina_library_dna_id_fkey FOREIGN KEY (dna_id) REFERENCES public.dna_extraction(dna_id);


--
-- Name: illumina_library illumina_library_prep_automation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.illumina_library
    ADD CONSTRAINT illumina_library_prep_automation_fkey FOREIGN KEY (prep_automation) REFERENCES public.prep_automation(prep_automation);


--
-- Name: illumina_library illumina_library_registry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.illumina_library
    ADD CONSTRAINT illumina_library_registry_fkey FOREIGN KEY (illumina_library_tube_id, dna_id) REFERENCES public.library(library_tube_id, dna_id);


--
-- Name: lca lca_mitogenome_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT lca_mitogenome_fkey FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


--
-- Name: lca lca_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT lca_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: lca_raw_results lca_raw_results_mitogenome_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT lca_raw_results_mitogenome_fkey FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


--
-- Name: lca_raw_results lca_raw_results_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT lca_raw_results_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: lca_validation lca_validation_mitogenome_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT lca_validation_mitogenome_fkey FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public.mitogenome_data(og_id, tech, seq_date, code);


--
-- Name: lca_validation lca_validation_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT lca_validation_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: library library_dna_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library
    ADD CONSTRAINT library_dna_id_fkey FOREIGN KEY (dna_id) REFERENCES public.dna_extraction(dna_id);


--
-- Name: library library_lysate_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library
    ADD CONSTRAINT library_lysate_id_fkey FOREIGN KEY (lysate_id) REFERENCES public.hic_lysate(lysate_id);


--
-- Name: library library_rna_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.library
    ADD CONSTRAINT library_rna_id_fkey FOREIGN KEY (rna_id) REFERENCES public.rna_extraction(rna_id);


--
-- Name: mitogenome_data mitogenome_data_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mitogenome_data
    ADD CONSTRAINT mitogenome_data_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: og_workflow_assignment_log og_workflow_assignment_log_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.og_workflow_assignment_log
    ADD CONSTRAINT og_workflow_assignment_log_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: og_workflow_notification og_workflow_notification_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.og_workflow_notification
    ADD CONSTRAINT og_workflow_notification_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: og_workflow_recommendation og_workflow_recommendation_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.og_workflow_recommendation
    ADD CONSTRAINT og_workflow_recommendation_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: ont_library ont_library_dna_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ont_library
    ADD CONSTRAINT ont_library_dna_id_fkey FOREIGN KEY (dna_id) REFERENCES public.dna_extraction(dna_id);


--
-- Name: ont_library ont_library_registry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ont_library
    ADD CONSTRAINT ont_library_registry_fkey FOREIGN KEY (ont_library_tube_id, dna_id) REFERENCES public.library(library_tube_id, dna_id);


--
-- Name: pacbio_library pacbio_library_dna_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pacbio_library
    ADD CONSTRAINT pacbio_library_dna_id_fkey FOREIGN KEY (dna_id) REFERENCES public.dna_extraction(dna_id);


--
-- Name: pacbio_library pacbio_library_prep_automation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pacbio_library
    ADD CONSTRAINT pacbio_library_prep_automation_fkey FOREIGN KEY (prep_automation) REFERENCES public.prep_automation(prep_automation);


--
-- Name: pacbio_library pacbio_library_registry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pacbio_library
    ADD CONSTRAINT pacbio_library_registry_fkey FOREIGN KEY (pacbio_library_tube_id, dna_id) REFERENCES public.library(library_tube_id, dna_id);


--
-- Name: raw_data raw_data_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_data
    ADD CONSTRAINT raw_data_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: ref_genomes_sra_uploads ref_genomes_sra_runs_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_genomes_sra_uploads
    ADD CONSTRAINT ref_genomes_sra_runs_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.ref_genomes_assembly_uploads(og_id);


--
-- Name: rna_extraction rna_extraction_tissue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_extraction
    ADD CONSTRAINT rna_extraction_tissue_id_fkey FOREIGN KEY (tissue_id) REFERENCES public.tissue(tissue_id);


--
-- Name: rna_library_ilmn rna_library_ilmn_registry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_ilmn
    ADD CONSTRAINT rna_library_ilmn_registry_fkey FOREIGN KEY (rna_library_tube_id, rna_id) REFERENCES public.library(library_tube_id, rna_id);


--
-- Name: rna_library_ilmn rna_library_ilmn_rna_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_ilmn
    ADD CONSTRAINT rna_library_ilmn_rna_id_fkey FOREIGN KEY (rna_id) REFERENCES public.rna_extraction(rna_id);


--
-- Name: rna_library_kinx rna_library_kinx_registry_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_kinx
    ADD CONSTRAINT rna_library_kinx_registry_fkey FOREIGN KEY (rna_library_tube_id, rna_id) REFERENCES public.library(library_tube_id, rna_id);


--
-- Name: rna_library_kinx rna_library_kinx_rna_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_library_kinx
    ADD CONSTRAINT rna_library_kinx_rna_id_fkey FOREIGN KEY (rna_id) REFERENCES public.rna_extraction(rna_id);


--
-- Name: rna_qc_kinnex rna_qc_kinnex_rna_tube_id_2_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_qc_kinnex
    ADD CONSTRAINT rna_qc_kinnex_rna_tube_id_2_fkey FOREIGN KEY (rna_tube_id_2) REFERENCES public.rna_library_kinx(rna_library_tube_id);


--
-- Name: rna_qc_kinnex rna_qc_kinnex_rna_tube_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rna_qc_kinnex
    ADD CONSTRAINT rna_qc_kinnex_rna_tube_id_fkey FOREIGN KEY (rna_tube_id) REFERENCES public.rna_library_kinx(rna_library_tube_id);


--
-- Name: sequencing sequencing_design_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sequencing
    ADD CONSTRAINT sequencing_design_no_fkey FOREIGN KEY (design_no) REFERENCES public.design_description(design_no);


--
-- Name: sequencing sequencing_library_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sequencing
    ADD CONSTRAINT sequencing_library_fkey FOREIGN KEY (library_tube_id) REFERENCES public.library(library_tube_id);


--
-- Name: species_ncbi_assembly species_ncbi_assembly_species_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.species_ncbi_assembly
    ADD CONSTRAINT species_ncbi_assembly_species_fkey FOREIGN KEY (species) REFERENCES public.species(species);


--
-- Name: tissue tissue_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tissue
    ADD CONSTRAINT tissue_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- PostgreSQL database dump complete
--

\unrestrict 2ucHcOK282bQ26ZUgfYpH6qXiJqFrt5w3cjQzrUahwfEchesNLI5bD7cp9vwudB

