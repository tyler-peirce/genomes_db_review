--
-- PostgreSQL database dump
--

\restrict o92hsMyMKXkBS6pxj3IRvzvOTkP1QSatRtpbuR1Ho4NypNdrOi9M8XudYJ5MzPT

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
-- Name: draft_genome_run_illumina_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.draft_genome_run_illumina_only() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
DECLARE
  tech text;
BEGIN
  SELECT s.technology || ' / ' || coalesce(s.library_type, '?') INTO tech
  FROM public.v_sequencing_browse s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS DISTINCT FROM 'Illumina / illumina' THEN
    RAISE EXCEPTION 'draft_genome_run: % is % sequencing, not an Illumina DNA library; a draft '
      'genome is an Illumina DNA assembly', NEW.sequencing_id, coalesce(tech, 'unknown');
  END IF;
  RETURN NEW;
END
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
-- Name: rebuild_mito_gene_views(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rebuild_mito_gene_views() RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  genes text;
BEGIN
  SELECT string_agg(expr, E',\n       ' ORDER BY class_order, sort_order, sub_order)
    INTO genes
    FROM (SELECT CASE gene_class WHEN 'rrna' THEN 1 WHEN 'pcg' THEN 2 ELSE 3 END AS class_order,
                 sort_order, 1 AS sub_order,
                 format('max(g.length) FILTER (WHERE g.gene = %L) AS %I', gene, gene) AS expr
            FROM mito_gene
          UNION ALL
          SELECT CASE gene_class WHEN 'rrna' THEN 1 WHEN 'pcg' THEN 2 ELSE 3 END,
                 sort_order, 2,
                 format('max(g.translated_length) FILTER (WHERE g.gene = %L) AS %I', gene, gene || '_trans')
            FROM mito_gene WHERE has_translation) x;
  -- Dropped and recreated so a new gene can take its place in the column order. Nothing may be
  -- built on this view for that reason.
  DROP VIEW IF EXISTS v_mito_annotation_genes;
  EXECUTE format($v$
    CREATE VIEW v_mito_annotation_genes AS
    SELECT s.og_num, a.og_id, s.nominal_species_id, a.tech, a.seq_date, a.code,
       n.annotation, n.annotation_id, n.is_selected,
       %s
    FROM mito_annotation n
    JOIN mito_assembly a ON a.assembly_id = n.assembly_id
    JOIN sample s ON s.og_id = a.og_id
    LEFT JOIN mito_annotation_gene g ON g.annotation_id = n.annotation_id
    GROUP BY s.og_num, a.og_id, s.nominal_species_id, a.tech, a.seq_date, a.code,
             n.annotation, n.annotation_id, n.is_selected$v$,
    genes);
  COMMENT ON VIEW v_mito_annotation_genes IS
    'One row per annotation, gene lengths wide: rRNA, protein-coding (each beside its _trans), '
    'tRNA. Generated by rebuild_mito_gene_views() from mito_gene; is_selected is display only. '
    'Do not build other views on this one.';
  GRANT SELECT ON v_mito_annotation_genes TO readonly;
END
$_$;


--
-- Name: FUNCTION rebuild_mito_gene_views(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.rebuild_mito_gene_views() IS 'Regenerate v_mito_annotation_genes from mito_gene. Run after adding a gene.';


--
-- Name: ref_assembly_run_genomic_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ref_assembly_run_genomic_only() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
DECLARE
  tech  text;
  ltype text;
  st    text;
BEGIN
  SELECT s.technology, s.library_type, s.status INTO tech, ltype, st
  FROM public.v_sequencing_browse s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS NULL OR tech NOT IN ('PacBio HIFI', 'PacBio', 'ONT', 'Hi-C')
     OR ltype IS NULL OR ltype NOT IN ('pacbio', 'ont', 'hic') THEN
    RAISE EXCEPTION 'ref_assembly_run: % is % / % sequencing; a reference assembly is built from '
      'PacBio, ONT or Hi-C DNA libraries', NEW.sequencing_id, coalesce(tech, 'unknown'), coalesce(ltype, 'unknown');
  END IF;
  IF st = 'Failed' THEN  -- 069
    RAISE EXCEPTION 'ref_assembly_run: % is a failed run (sequencing.status); an assembly is not built from it',
      NEW.sequencing_id;
  END IF;
  RETURN NEW;
END
$$;


--
-- Name: ref_read_set_external_exclusive(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ref_read_set_external_exclusive() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
BEGIN
  IF TG_TABLE_NAME = 'ref_read_set_run' THEN
    IF EXISTS (SELECT 1 FROM public.ref_read_set_external x WHERE x.read_set_id = NEW.read_set_id) THEN
      RAISE EXCEPTION 'ref_read_set_run: read set % is external (ref_read_set_external); it has no sequencing rows',
        NEW.read_set_id;
    END IF;
  ELSIF EXISTS (SELECT 1 FROM public.ref_read_set_run r WHERE r.read_set_id = NEW.read_set_id) THEN
    RAISE EXCEPTION 'ref_read_set_external: read set % has sequencing rows (ref_read_set_run); it is not external',
      NEW.read_set_id;
  END IF;
  RETURN NEW;
END
$$;


--
-- Name: FUNCTION ref_read_set_external_exclusive(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.ref_read_set_external_exclusive() IS 'A read set is either external or linked to sequencing rows, not both (071).';


--
-- Name: ref_read_set_run_pacbio_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ref_read_set_run_pacbio_only() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
DECLARE
  tech  text;
  ltype text;
  st    text;
BEGIN
  SELECT s.technology, s.library_type, s.status INTO tech, ltype, st
  FROM public.v_sequencing_browse s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS NULL OR tech NOT IN ('PacBio HIFI', 'PacBio') OR ltype IS DISTINCT FROM 'pacbio' THEN
    RAISE EXCEPTION 'ref_read_set_run: % is % / % sequencing; a HiFi read set is PacBio DNA',
      NEW.sequencing_id, coalesce(tech, 'unknown'), coalesce(ltype, 'unknown');
  END IF;
  IF st = 'Failed' THEN  -- 069
    RAISE EXCEPTION 'ref_read_set_run: % is a failed run (sequencing.status); it has no reads', NEW.sequencing_id;
  END IF;
  RETURN NEW;
END
$$;


--
-- Name: ref_submission_assembly_to_haplotypes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ref_submission_assembly_to_haplotypes() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
BEGIN
  UPDATE public.ref_submission_haplotype h SET assembly_id = NEW.assembly_id
  WHERE h.submission_id = NEW.submission_id AND h.assembly_id IS DISTINCT FROM NEW.assembly_id;
  RETURN NULL;
END
$$;


--
-- Name: ref_submission_haplotype_assembly(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ref_submission_haplotype_assembly() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
BEGIN
  SELECT s.assembly_id INTO NEW.assembly_id FROM public.ref_submission s WHERE s.submission_id = NEW.submission_id;
  RETURN NEW;
END
$$;


--
-- Name: resolve_sra_upload_runs(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolve_sra_upload_runs(p_og_id text, p_data_type text, p_filenames text) RETURNS SETOF text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  -- File names call a tube's first Hi-C library HICL1; the workbook calls it HICL (065).
  files text[] := ARRAY(SELECT regexp_replace(btrim(f), '_HICL1(?=[_.])', '_HICL', 'g')
                        FROM unnest(string_to_array(coalesce(p_filenames, ''), ',')) f
                        WHERE btrim(f) <> '');
  kind  text;
  runs  text[];
  hit   text[];
BEGIN
  IF cardinality(files) = 0 OR p_og_id IS NULL THEN
    RETURN;
  END IF;

  IF p_data_type = 'hifi' THEN
    RETURN QUERY
    WITH f AS (
      SELECT substring(x from 'm[0-9]+[a-z]?_([0-9]{6})_[0-9]{6}') AS mdate,
             substring(x from '\.(bc[0-9]+)(?:--bc[0-9]+)?\.') AS bc
      FROM unnest(files) x
    ), ub AS (
      SELECT CASE WHEN count(DISTINCT bc) = 1 THEN min(bc) END AS bc FROM f
    ), mv AS (
      SELECT DISTINCT f.mdate, coalesce(f.bc, ub.bc) AS bc FROM f CROSS JOIN ub WHERE f.mdate IS NOT NULL
    ), cand AS (
      SELECT mv.mdate, mv.bc, s.sequencing_id, s.library_tube_id,
             abs(to_date(mv.mdate, 'YYMMDD') - to_date(s.seq_date, 'YYMMDD')) AS gap
      FROM mv JOIN v_sequencing_browse s
        ON s.og_id = p_og_id AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio'
       AND s.seq_date ~ '^[0-9]{6}$' AND s.status IS DISTINCT FROM 'Failed'
       AND abs(to_date(mv.mdate, 'YYMMDD') - to_date(s.seq_date, 'YYMMDD')) <= 21
    ), nearest AS (
      SELECT c.* FROM cand c
      WHERE c.gap = (SELECT min(c2.gap) FROM cand c2 WHERE c2.mdate = c.mdate AND c2.bc IS NOT DISTINCT FROM c.bc)
    ), narrowed AS (
      SELECT n.mdate, n.bc, n.sequencing_id FROM nearest n
      WHERE (SELECT count(*) FROM nearest n2 WHERE n2.mdate = n.mdate AND n2.bc IS NOT DISTINCT FROM n.bc) = 1
         OR EXISTS (SELECT 1 FROM hifi_read_qc q
                    WHERE q.og_id = p_og_id AND q.barcode = n.bc
                      AND (q.sequencing_id = n.sequencing_id
                           OR q.og_id || q.tissue || '_' || q.ext_type || '_' || q.lib_code = n.library_tube_id))
    ), one AS (
      SELECT mdate, bc FROM narrowed GROUP BY mdate, bc HAVING count(*) = 1
    )
    SELECT DISTINCT n.sequencing_id FROM narrowed n
    JOIN one o ON o.mdate = n.mdate AND o.bc IS NOT DISTINCT FROM n.bc;
    RETURN;
  END IF;

  kind := CASE p_data_type WHEN 'hic' THEN 'Hi-C' WHEN 'ont' THEN 'ONT' WHEN 'illumina' THEN 'Illumina' END;
  IF kind IS NULL THEN
    RETURN;
  END IF;
  runs := ARRAY(SELECT DISTINCT m[1] FROM unnest(files) x,
                regexp_matches(x, '(?:^|[._])((?:NOVA|NEXT|ISEQ|PACB|ONT)[A-Za-z-]*_[0-9]{6}_[A-Za-z0-9]+)(?=[._])', 'g') m);
  IF cardinality(runs) = 0 THEN
    RETURN;
  END IF;
  hit := ARRAY(SELECT s.sequencing_id FROM v_sequencing_browse s
               WHERE s.og_id = p_og_id AND s.technology = kind AND s.run_id = ANY (runs) AND s.status IS DISTINCT FROM 'Failed'
                 AND EXISTS (SELECT 1 FROM unnest(files) x
                             WHERE strpos(x, s.library_tube_id || '_') > 0 OR strpos(x, s.library_tube_id || '.') > 0));
  IF cardinality(hit) = 0 THEN
    hit := ARRAY(SELECT s.sequencing_id FROM v_sequencing_browse s
                 WHERE s.og_id = p_og_id AND s.technology = kind AND s.run_id = ANY (runs) AND s.status IS DISTINCT FROM 'Failed');
  END IF;
  IF cardinality(hit) = 0 THEN
    hit := ARRAY(SELECT s.sequencing_id FROM v_sequencing_browse s
                 WHERE s.og_id = p_og_id AND s.technology = kind AND s.status IS DISTINCT FROM 'Failed'
                   AND split_part(s.run_id, '_', 2) = ANY (ARRAY(SELECT split_part(r, '_', 2) FROM unnest(runs) r)));
  END IF;
  IF cardinality(hit) = 1 OR EXISTS (SELECT 1 FROM unnest(files) x, v_sequencing_browse s
                                     WHERE s.sequencing_id = ANY (hit)
                                       AND (strpos(x, s.library_tube_id || '_') > 0 OR strpos(x, s.library_tube_id || '.') > 0)) THEN
    RETURN QUERY SELECT unnest(hit);
  END IF;
END
$_$;


--
-- Name: FUNCTION resolve_sra_upload_runs(p_og_id text, p_data_type text, p_filenames text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.resolve_sra_upload_runs(p_og_id text, p_data_type text, p_filenames text) IS 'The sequencing rows an SRA upload''s file names point to (064''s forward rule; HICL1 = HICL, 065; failed runs skipped, 069). Used by ENA-ref-genomes step 09. search_path public since RG.6 (073).';


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
-- Name: hic_read_qc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hic_read_qc (
    hic_qc_id bigint NOT NULL,
    og_id text NOT NULL,
    tissue text,
    ext_type text,
    lib_code text,
    lane text,
    run_id text NOT NULL,
    sequencing_id text,
    datecreated date,
    isarchived boolean,
    isfiledeleted boolean,
    totalreadspf bigint,
    totalclusterspf bigint,
    read1length integer,
    read2length integer,
    ispairedend boolean,
    yield_gb numeric,
    totalsize_gb numeric,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT hic_read_qc_ext_type_check CHECK ((ext_type <> ''::text)),
    CONSTRAINT hic_read_qc_has_value CHECK ((num_nonnulls(datecreated, isarchived, isfiledeleted, totalreadspf, totalclusterspf, read1length, read2length, ispairedend, yield_gb, totalsize_gb) > 0)),
    CONSTRAINT hic_read_qc_lane_check CHECK ((lane <> ''::text)),
    CONSTRAINT hic_read_qc_lib_code_check CHECK ((lib_code <> ''::text)),
    CONSTRAINT hic_read_qc_run_id_check CHECK ((run_id <> ''::text)),
    CONSTRAINT hic_read_qc_tissue_check CHECK ((tissue <> ''::text))
);


--
-- Name: TABLE hic_read_qc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.hic_read_qc IS 'Illumina run statistics for Hi-C libraries, per library per run per lane. Writer: ref_genomes_hic_automation push_hic_yield.py (from poll-hic-multiqc.py). sequencing_id: the one Hi-C sequencing row of this OG and tissue on this run, NULL where none or several match (v_read_qc_sequencing_readiness).';


--
-- Name: hic_reads_qc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.hic_reads_qc AS
 SELECT hic_read_qc.og_id,
    COALESCE(hic_read_qc.tissue, ''::text) AS tissue,
    COALESCE(hic_read_qc.ext_type, ''::text) AS ext_type,
    COALESCE(hic_read_qc.lib_code, ''::text) AS lib_code,
    COALESCE(hic_read_qc.lane, ''::text) AS lane,
    hic_read_qc.run_id,
    hic_read_qc.datecreated,
    hic_read_qc.isarchived,
    hic_read_qc.isfiledeleted,
    hic_read_qc.totalreadspf,
    hic_read_qc.totalclusterspf,
    hic_read_qc.read1length,
    hic_read_qc.read2length,
    hic_read_qc.ispairedend,
    hic_read_qc.yield_gb,
    hic_read_qc.totalsize_gb
   FROM public.hic_read_qc;


--
-- Name: VIEW hic_reads_qc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.hic_reads_qc IS 'Compatibility view: public.hic_reads_qc''s columns in its order, NULL key parts shown as ''''. Not a write path: write hic_read_qc.';


--
-- Name: hifi_read_qc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hifi_read_qc (
    hifi_qc_id bigint NOT NULL,
    og_id text NOT NULL,
    tissue text NOT NULL,
    ext_type text NOT NULL,
    lib_code text NOT NULL,
    run_id text NOT NULL,
    sequencing_id text,
    barcode text,
    barcode_quality numeric,
    hifi_reads bigint,
    hifi_read_length numeric,
    hifi_read_quality text,
    hifi_yield bigint,
    polymerase_read_length numeric,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT hifi_read_qc_ext_type_check CHECK ((ext_type <> ''::text)),
    CONSTRAINT hifi_read_qc_has_value CHECK ((num_nonnulls(barcode, barcode_quality, hifi_reads, hifi_read_length, hifi_read_quality, hifi_yield, polymerase_read_length) > 0)),
    CONSTRAINT hifi_read_qc_lib_code_check CHECK ((lib_code <> ''::text)),
    CONSTRAINT hifi_read_qc_run_id_check CHECK ((run_id <> ''::text)),
    CONSTRAINT hifi_read_qc_tissue_check CHECK ((tissue <> ''::text))
);


--
-- Name: TABLE hifi_read_qc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.hifi_read_qc IS 'PacBio HiFi yield and quality per library per run, SMRT cells summed. Written by 0b_push_hifi_yield_results_to_sqldb.py (ref repo). sequencing_id: the one sequencing row of this library on this run, NULL where none or several match (v_read_qc_sequencing_readiness).';


--
-- Name: hifi_reads_qc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.hifi_reads_qc AS
 SELECT hifi_read_qc.og_id,
    hifi_read_qc.tissue,
    hifi_read_qc.ext_type,
    hifi_read_qc.lib_code,
    hifi_read_qc.run_id,
    hifi_read_qc.barcode,
    hifi_read_qc.barcode_quality,
    hifi_read_qc.hifi_reads,
    hifi_read_qc.hifi_read_length,
    hifi_read_qc.hifi_read_quality,
    hifi_read_qc.hifi_yield,
    hifi_read_qc.polymerase_read_length
   FROM public.hifi_read_qc;


--
-- Name: VIEW hifi_reads_qc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.hifi_reads_qc IS 'Compatibility view: public.hifi_reads_qc''s columns in its order. Not a write path: write hifi_read_qc.';


--
-- Name: ref_genomescope; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_genomescope (
    read_set_id bigint NOT NULL,
    homozygosity numeric(5,2),
    heterozygosity numeric(5,2),
    genomesize bigint,
    repeatsize bigint,
    uniquesize bigint,
    modelfit numeric(5,2),
    errorrate numeric(5,2),
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_genomescope_has_value CHECK ((num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate) > 0))
);


--
-- Name: TABLE ref_genomescope; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_genomescope IS 'GenomeScope2 k-mer profile of a HiFi read set (ref_read_set). Written by 01a_push_genomescope_comp_results_to_sqldb.py (ref repo). A fish whose model failed carries the 1 Gb default genomesize (the writer''s rule).';


--
-- Name: ref_hifi_adapter_filter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_hifi_adapter_filter (
    read_set_id bigint NOT NULL,
    contam_reads integer,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_hifi_adapter_filter_has_value CHECK ((num_nonnulls(contam_reads) > 0))
);


--
-- Name: TABLE ref_hifi_adapter_filter; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_hifi_adapter_filter IS 'HiFiAdapterFilt: reads removed as adapter-contaminated, per HiFi read set (ref_read_set). Written by 0a_push_hifiadapt_results_to_sqldb.py (ref repo).';


--
-- Name: ref_read_set; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_read_set (
    read_set_id bigint NOT NULL,
    og_id text NOT NULL,
    seq_date text,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_read_set_seq_date_check CHECK ((seq_date ~ '^[0-9]{6}$'::text))
);


--
-- Name: TABLE ref_read_set; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_read_set IS 'A HiFi read set: the PacBio reads one reference-pipeline run took in for an OG (the samplesheet''s date). seq_date is the latest seq_date of its sequencing rows, not the samplesheet date. NULL = unknown (before RG, or a public.raw_qc state no dated read set matches). Migration 062.';


--
-- Name: raw_qc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.raw_qc AS
 WITH pick AS (
         SELECT DISTINCT ON (rs.og_id) rs.og_id,
            rs.read_set_id
           FROM public.ref_read_set rs
          WHERE ((EXISTS ( SELECT 1
                   FROM public.ref_genomescope g_1
                  WHERE (g_1.read_set_id = rs.read_set_id))) OR (EXISTS ( SELECT 1
                   FROM public.ref_hifi_adapter_filter f_1
                  WHERE (f_1.read_set_id = rs.read_set_id))))
          ORDER BY rs.og_id, rs.seq_date DESC
        )
 SELECT p.og_id,
    g.homozygosity,
    g.heterozygosity,
    g.genomesize,
    g.repeatsize,
    g.uniquesize,
    g.modelfit,
    g.errorrate,
    f.contam_reads
   FROM ((pick p
     LEFT JOIN public.ref_genomescope g ON ((g.read_set_id = p.read_set_id)))
     LEFT JOIN public.ref_hifi_adapter_filter f ON ((f.read_set_id = p.read_set_id)));


--
-- Name: VIEW raw_qc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.raw_qc IS 'Compatibility view: public.raw_qc''s columns, one row per OG, from one read set: the undated one if any (it mirrors a public state no dated read set matches), else the latest dated. Not a write path: write ref_read_set with ref_genomescope / ref_hifi_adapter_filter (refdb.upsert_read_set).';


--
-- Name: coverage_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.coverage_summary AS
 WITH hifi_agg AS (
         SELECT hifi_reads_qc.og_id,
            sum(hifi_reads_qc.hifi_yield) AS total_hifi_yield_bp
           FROM public.hifi_reads_qc hifi_reads_qc
          GROUP BY hifi_reads_qc.og_id
        ), hic_agg AS (
         SELECT hic_reads_qc.og_id,
            (sum((hic_reads_qc.yield_gb * (1000000000)::numeric)))::bigint AS total_hic_yield_bp
           FROM public.hic_reads_qc hic_reads_qc
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
-- Name: VIEW coverage_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.coverage_summary IS 'Coverage per OG from raw_qc, hifi_reads_qc and hic_reads_qc (the compatibility views). Replaced the public view of the same name at RG.6 (073); the old one is in pre_v4_archive.';


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
-- Name: draft_busco; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_busco (
    draft_id bigint NOT NULL,
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
    internal_stop_codon_count bigint,
    internal_stop_codon_percent numeric(5,2),
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT draft_busco_has_value CHECK ((num_nonnulls(complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, internal_stop_codon_count, internal_stop_codon_percent) > 0))
);


--
-- Name: TABLE draft_busco; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_busco IS 'BUSCO, with BUSCO''s own assembly statistics and internal stop codons, from one short-summary JSON. Written by push_busco_results_to_sqldb.py.';


--
-- Name: COLUMN draft_busco.scaffold_n50; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_busco.scaffold_n50 IS 'NOT a reliable N50: on most rows it behaves as an L50 (a contig count). Use draft_gfastats.gfa_scaffold_n50. docs/assembly_relations_plan.md §4.2.';


--
-- Name: COLUMN draft_busco.contigs_n50; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_busco.contigs_n50 IS 'NOT a reliable N50; see scaffold_n50. Use draft_gfastats.gfa_contig_n50.';


--
-- Name: draft_contamination; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_contamination (
    draft_id bigint NOT NULL,
    num_contigs_exclude integer,
    num_contigs_trim integer,
    num_contigs_review integer,
    bp_exclude integer,
    bp_trim integer,
    bp_review integer,
    num_contigs_lt_500bp integer,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT draft_contamination_has_value CHECK ((num_nonnulls(num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, num_contigs_lt_500bp) > 0))
);


--
-- Name: TABLE draft_contamination; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_contamination IS 'FCS-GX contamination screen via BBMap filterbyname, and the count of contigs under 500 bp. Written by push_decontamination_results_to_sqldb.py.';


--
-- Name: COLUMN draft_contamination.num_contigs_lt_500bp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_contamination.num_contigs_lt_500bp IS 'Contigs under 500 bp (*contig_count_500bp.txt). Was draft_genomes.num_contigs.';


--
-- Name: draft_depthsizer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_depthsizer (
    draft_id bigint NOT NULL,
    depmethod text,
    adjust text,
    readbp bigint,
    mapadjust numeric(7,6),
    scdepth numeric(5,2),
    estgenomesize bigint,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT draft_depthsizer_has_value CHECK ((num_nonnulls(depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize) > 0))
);


--
-- Name: TABLE draft_depthsizer; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_depthsizer IS 'DepthSizer: RETIRED and CLOSED (owner decision 12, 2026-10-16). Loaded once from draft_genomes; no writer, no new rows.';


--
-- Name: draft_fastp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_fastp (
    draft_id bigint NOT NULL,
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
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT draft_fastp_has_value CHECK ((num_nonnulls(passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content) > 0))
);


--
-- Name: TABLE draft_fastp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_fastp IS 'fastp read QC. Written by push_fastp_to_sqldb.py.';


--
-- Name: draft_genome; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_genome (
    draft_id bigint NOT NULL,
    og_id text NOT NULL,
    seq_date text NOT NULL,
    mach text,
    initial text,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE draft_genome; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_genome IS 'One Illumina draft genome assembly. Written by OceanOmics-OceanGenomes-Draft-Genomes bin/draft_genome_stats.py.';


--
-- Name: draft_genome_draft_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.draft_genome ALTER COLUMN draft_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.draft_genome_draft_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: draft_genome_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_genome_run (
    draft_id bigint NOT NULL,
    sequencing_id text NOT NULL
);


--
-- Name: TABLE draft_genome_run; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_genome_run IS 'The Illumina sequencing rows a draft was built from. Illumina only (trigger).';


--
-- Name: draft_genomescope; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_genomescope (
    draft_id bigint NOT NULL,
    homozygosity numeric(8,4),
    heterozygosity numeric(8,4),
    genomesize bigint,
    repeatsize bigint,
    uniquesize bigint,
    modelfit numeric(8,4),
    errorrate numeric(8,4),
    homozygosity_min numeric(8,4),
    heterozygosity_min numeric(8,4),
    genomesize_min bigint,
    repeatsize_min bigint,
    uniquesize_min bigint,
    modelfit_allkmers numeric(8,4),
    genome_size_reliable boolean,
    genome_size_flags text,
    kmercov numeric(10,4),
    lambda_depth numeric(10,4),
    host_assembly_size bigint,
    host_assembly_fraction numeric,
    output_set text GENERATED ALWAYS AS (
CASE
    WHEN (num_nonnulls(homozygosity_min, heterozygosity_min, genomesize_min, repeatsize_min, uniquesize_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth) > 0) THEN 'extended'::text
    ELSE 'core'::text
END) STORED,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    host_haploid_size bigint,
    partition_confidence text,
    partition_note text,
    busco_regions integer,
    busco_read_depth numeric(10,4),
    genomescope_fit text,
    CONSTRAINT draft_genomescope_genomescope_fit_check CHECK ((genomescope_fit = ANY (ARRAY['original'::text, 'reseeded'::text]))),
    CONSTRAINT draft_genomescope_has_value CHECK ((num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, homozygosity_min, heterozygosity_min, genomesize_min, repeatsize_min, uniquesize_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit) > 0)),
    CONSTRAINT draft_genomescope_partition_confidence_check CHECK ((partition_confidence = ANY (ARRAY['high'::text, 'low'::text])))
);


--
-- Name: TABLE draft_genomescope; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_genomescope IS 'GenomeScope2 fit and the coverage-summary verdict. Written by push_assembly_results_to_sqldb.py. output_set: extended where the newer columns were computed; core rows have them NULL by design.';


--
-- Name: COLUMN draft_genomescope.host_haploid_size; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomescope.host_haploid_size IS 'Host assembly mass with haplotype-split contigs (those at about half the host depth) counted once. A lower bound, like host_assembly_size. From *_kmer_depth.json.';


--
-- Name: COLUMN draft_genomescope.partition_confidence; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomescope.partition_confidence IS 'high or low: whether the BUSCO depth anchor of the host partition can be trusted. Do not quote a host size from a low partition; partition_note says why it is low.';


--
-- Name: COLUMN draft_genomescope.partition_note; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomescope.partition_note IS 'Why partition_confidence is low: few_busco_regions, no_dominant_mode or anchor_off_mode. NULL when it is high.';


--
-- Name: COLUMN draft_genomescope.busco_regions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomescope.busco_regions IS 'Number of Complete BUSCO regions busco_read_depth and the host partition were measured over (busco_regions in *_kmer_depth.json).';


--
-- Name: COLUMN draft_genomescope.busco_read_depth; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomescope.busco_read_depth IS 'Mean per-base read depth over the Complete single-copy BUSCO genes (busco_mean_depth in *_kmer_depth.json, from MEASURE_KMER_COVERAGE). The sequencing depth of the host genome, and what ENA COVERAGE should carry; the successor to DepthSizer''s scdepth. Not lambda_depth, which is this halved and scaled into k-mer space.';


--
-- Name: COLUMN draft_genomescope.genomescope_fit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.draft_genomescope.genomescope_fit IS 'original or reseeded: which GenomeScope fit genomesize, kmercov and the model fit come from (genomescope_fit in *_coverage_summary.json; GENOMESCOPE_RESEED keeps the refit only when it wins). NULL before the reseed existed.';


--
-- Name: draft_gfastats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_gfastats (
    draft_id bigint NOT NULL,
    gfa_num_contigs bigint,
    gfa_contig_n50 bigint,
    gfa_num_scaffolds bigint,
    gfa_scaffold_n50 bigint,
    gfa_largest_scaffold bigint,
    gfa_total_scaffold_length bigint,
    gfa_gc_content_percent numeric(10,2),
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT draft_gfastats_has_value CHECK ((num_nonnulls(gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent) > 0))
);


--
-- Name: TABLE draft_gfastats; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_gfastats IS 'gfastats assembly statistics; the authoritative N50. Written by push_gfa_results_to_sqldb.py.';


--
-- Name: draft_merqury; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_merqury (
    draft_id bigint NOT NULL,
    unique_k_mers_assembly bigint,
    k_mers_total bigint,
    qv numeric(6,4),
    error numeric(12,11),
    k_mer_set text,
    solid_k_mers bigint,
    total_k_mers bigint,
    completeness numeric(7,4),
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT draft_merqury_has_value CHECK ((num_nonnulls(unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness) > 0))
);


--
-- Name: TABLE draft_merqury; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_merqury IS 'Merqury QV and k-mer completeness. Written by push_merqury_results_to_sqldb.py.';


--
-- Name: draft_submission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_submission (
    draft_id bigint NOT NULL,
    sra_accession character varying,
    biosample_accession character varying,
    study character varying,
    bioproject_accession character varying,
    ena_analysis_accession text,
    assembly_accession text,
    comment character varying,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT draft_submission_has_value CHECK ((num_nonnulls(sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment) > 0))
);


--
-- Name: TABLE draft_submission; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_submission IS 'Submission accessions. Written by ENA-draft-genomes steps 06-07.';


--
-- Name: draft_tiara; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.draft_tiara (
    draft_id bigint NOT NULL,
    num_contigs_mitochondrion integer,
    num_contigs_plastid integer,
    num_contigs_prokarya integer,
    bp_mitochondrion bigint,
    bp_plastid bigint,
    bp_prokarya bigint,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT draft_tiara_has_value CHECK ((num_nonnulls(num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya) > 0))
);


--
-- Name: TABLE draft_tiara; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.draft_tiara IS 'Tiara contig classification. Written by push_decontamination_results_to_sqldb.py.';


--
-- Name: draft_genomes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.draft_genomes AS
 SELECT d.og_num,
    d.og_id,
    s.nominal_species_id,
    d.seq_date,
    d.mach,
    d.initial,
    f.raw_total_reads,
    f.raw_total_bases,
    f.raw_q20_bases,
    f.raw_q30_bases,
    f.raw_q20_rate,
    f.raw_q30_rate,
    f.raw_read1_mean_length,
    f.raw_read2_mean_length,
    f.raw_gc_content,
    f.passed_filter_reads,
    f.low_quality_reads,
    f.too_many_n_reads,
    f.too_short_reads,
    f.too_long_reads,
    f.total_reads,
    f.total_bases,
    f.q20_bases,
    f.q30_bases,
    f.q20_rate,
    f.q30_rate,
    f.read1_mean_length,
    f.read2_mean_length,
    f.gc_content,
    gs.homozygosity,
    gs.homozygosity_min,
    gs.heterozygosity,
    gs.heterozygosity_min,
    gs.repeatsize,
    gs.repeatsize_min,
    gs.uniquesize,
    gs.uniquesize_min,
    gs.modelfit,
    gs.modelfit_allkmers,
    gs.errorrate,
    gs.kmercov,
    gs.lambda_depth,
    gs.busco_read_depth,
    gs.busco_regions,
    gs.genomesize,
    gs.genomesize_min,
    gs.genomescope_fit,
    gs.genome_size_reliable,
    gs.genome_size_flags,
    gs.host_assembly_size,
    gs.host_assembly_fraction,
    gs.host_haploid_size,
    gs.partition_confidence,
    gs.partition_note,
    ti.num_contigs_mitochondrion,
    ti.num_contigs_plastid,
    ti.num_contigs_prokarya,
    ti.bp_mitochondrion,
    ti.bp_plastid,
    ti.bp_prokarya,
    ct.num_contigs_exclude,
    ct.num_contigs_trim,
    ct.num_contigs_review,
    ct.bp_exclude,
    ct.bp_trim,
    ct.bp_review,
    ct.num_contigs_lt_500bp AS num_contigs,
    b.complete,
    b.single_copy,
    b.multi_copy,
    b.fragmented,
    b.missing,
    b.n_markers,
    b.domain,
    b.number_of_scaffolds,
    b.number_of_contigs,
    b.total_length,
    b.percent_gaps,
    b.scaffold_n50,
    b.contigs_n50,
    b.internal_stop_codon_count,
    b.internal_stop_codon_percent,
    mq.unique_k_mers_assembly,
    mq.k_mers_total,
    mq.qv,
    mq.error,
    mq.k_mer_set,
    mq.solid_k_mers,
    mq.total_k_mers,
    mq.completeness,
    gf.gfa_num_contigs,
    gf.gfa_contig_n50,
    gf.gfa_num_scaffolds,
    gf.gfa_scaffold_n50,
    gf.gfa_largest_scaffold,
    gf.gfa_total_scaffold_length,
    gf.gfa_gc_content_percent,
    su.sra_accession,
    su.biosample_accession,
    su.study,
    su.bioproject_accession,
    su.ena_analysis_accession,
    su.assembly_accession,
    su.comment
   FROM (((((((((public.draft_genome d
     JOIN public.sample s ON ((s.og_id = d.og_id)))
     LEFT JOIN public.draft_fastp f ON ((f.draft_id = d.draft_id)))
     LEFT JOIN public.draft_genomescope gs ON ((gs.draft_id = d.draft_id)))
     LEFT JOIN public.draft_tiara ti ON ((ti.draft_id = d.draft_id)))
     LEFT JOIN public.draft_contamination ct ON ((ct.draft_id = d.draft_id)))
     LEFT JOIN public.draft_busco b ON ((b.draft_id = d.draft_id)))
     LEFT JOIN public.draft_merqury mq ON ((mq.draft_id = d.draft_id)))
     LEFT JOIN public.draft_gfastats gf ON ((gf.draft_id = d.draft_id)))
     LEFT JOIN public.draft_submission su ON ((su.draft_id = d.draft_id)));


--
-- Name: VIEW draft_genomes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.draft_genomes IS 'Compatibility view: the kept columns of the old draft_genomes table plus nominal_species_id, grouped by process (056), plus the read depth and host partition columns (067). Read by column name, not position. DepthSizer (retired) is not shown; see v3.draft_depthsizer. Not a write path.';


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
-- Name: ref_assembly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_assembly (
    assembly_id bigint NOT NULL,
    og_id text NOT NULL,
    seq_date text NOT NULL,
    version text NOT NULL,
    strategy text GENERATED ALWAYS AS ("substring"(version, '^[a-z]+'::text)) STORED,
    attempt integer GENERATED ALWAYS AS (("substring"(version, '[0-9]+$'::text))::integer) STORED,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_assembly_seq_date_check CHECK ((seq_date ~ '^[0-9]{6}$'::text)),
    CONSTRAINT ref_assembly_version_check CHECK ((version ~ '^(hic|hifi|ont)[0-9]+$'::text))
);


--
-- Name: TABLE ref_assembly; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_assembly IS 'One reference-genome assembly attempt: hicN (HiFi + Hi-C), hifiN (HiFi only) or ontN. Written by OceanOmics-OceanGenomes-ref-genomes and -post-curation push scripts.';


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
                 JOIN public.ref_assembly rg ON ((rg.og_id = samp.og_id)))
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

COMMENT ON VIEW public.goat_species_v1 IS 'GoaT species submission view; in_assembly from ref_assembly. Replaced the public view of the same name at RG.6 (073); the old one is in pre_v4_archive.';


--
-- Name: hic_read_qc_hic_qc_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.hic_read_qc ALTER COLUMN hic_qc_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.hic_read_qc_hic_qc_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: hifi_read_qc_hifi_qc_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.hifi_read_qc ALTER COLUMN hifi_qc_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.hifi_read_qc_hifi_qc_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
-- Name: mito_annotation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mito_annotation (
    annotation_id bigint NOT NULL,
    assembly_id bigint NOT NULL,
    annotation text NOT NULL,
    is_selected boolean DEFAULT false NOT NULL,
    selected_by text,
    selected_at timestamp with time zone,
    length_emma integer,
    cds_no integer,
    trna_no integer,
    rrna_no integer,
    manual_curation_notes text,
    extra_genes text,
    missing_genes text,
    order_correct text,
    passed text,
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
    annotation_stats_version text,
    annotation_updated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    completeness_profile text,
    CONSTRAINT mito_annotation_completeness_profile_check CHECK ((completeness_profile = ANY (ARRAY['vertebrate'::text, 'core'::text]))),
    CONSTRAINT mito_annotation_selected_by_check CHECK (((NOT is_selected) OR (selected_by IS NOT NULL)))
);


--
-- Name: TABLE mito_annotation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mito_annotation IS 'One annotation of an assembly. All are kept. Written by push_emma_annotation_results.py.';


--
-- Name: COLUMN mito_annotation.is_selected; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mito_annotation.is_selected IS 'Optional: a person may mark one annotation per assembly as the one they chose. Set by hand only; no writer, view or pipeline reads it (owner decision 3, 2026-10-16).';


--
-- Name: COLUMN mito_annotation.completeness_profile; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mito_annotation.completeness_profile IS 'vertebrate or core: the gene-set standard passed and missing_genes were judged against (annotation_stats.completeness_profile(), from the genetic code and class). core is the reduced set for invertebrate classes.';


--
-- Name: mito_annotation_annotation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.mito_annotation ALTER COLUMN annotation_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.mito_annotation_annotation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: mito_annotation_gene; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mito_annotation_gene (
    annotation_id bigint NOT NULL,
    gene text NOT NULL,
    length integer,
    translated_length integer,
    CONSTRAINT mito_annotation_gene_has_value CHECK ((num_nonnulls(length, translated_length) > 0))
);


--
-- Name: TABLE mito_annotation_gene; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mito_annotation_gene IS 'Per-gene lengths of one annotation. No row: the annotation has no value for that gene.';


--
-- Name: mito_assembly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mito_assembly (
    assembly_id bigint NOT NULL,
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    stats text,
    length integer,
    avg_coverage real,
    avg_base_coverage real,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT mito_assembly_tech_check CHECK ((tech = ANY (ARRAY['ilmn'::text, 'hifi'::text, 'hic'::text])))
);


--
-- Name: TABLE mito_assembly; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mito_assembly IS 'One mitogenome assembly. Written by push_mtdna_assm_results.py (Oceanomics-OceanGenomes-Mitogenomes).';


--
-- Name: mito_assembly_assembly_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.mito_assembly ALTER COLUMN assembly_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.mito_assembly_assembly_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: mito_assembly_depth; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mito_assembly_depth (
    assembly_id bigint NOT NULL,
    depth_method text NOT NULL,
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
    depth_measured_at timestamp with time zone
);


--
-- Name: TABLE mito_assembly_depth; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mito_assembly_depth IS 'The remap depth step''s verdict for an assembly: a measurement (remap_full_v1), or not_measured with the time it was recorded. No row: the step never ran on it.';


--
-- Name: mito_assembly_qc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mito_assembly_qc (
    assembly_id bigint NOT NULL,
    qc_status text,
    manual_review_reason text,
    numt_flag boolean,
    frameshift_flag boolean,
    reference_species text,
    reference_accession text,
    qc_updated_at timestamp with time zone,
    CONSTRAINT mito_assembly_qc_has_value CHECK ((num_nonnulls(qc_status, manual_review_reason, numt_flag, frameshift_flag, reference_species, reference_accession) > 0)),
    CONSTRAINT mito_assembly_qc_qc_status_check CHECK ((qc_status = ANY (ARRAY['complete'::text, 'manual_review'::text, 'failed'::text, 'superseded'::text])))
);


--
-- Name: TABLE mito_assembly_qc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mito_assembly_qc IS 'Assembly-level QC verdict from mitogenome_assembly_summary.py, one row per assembly (068). Written by push_assembly_qc.py.';


--
-- Name: COLUMN mito_assembly_qc.qc_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mito_assembly_qc.qc_status IS 'Assembly QC verdict from mitogenome_assembly_summary.py: complete, manual_review, failed or superseded (a reseed or collapse replaced this assembly).';


--
-- Name: COLUMN mito_assembly_qc.manual_review_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mito_assembly_qc.manual_review_reason IS 'Why the assembly needs review, ;-separated, as mitogenome_assembly_summary.py writes it.';


--
-- Name: COLUMN mito_assembly_qc.numt_flag; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mito_assembly_qc.numt_flag IS 'True when the run carries a NUMT signal for this assembly.';


--
-- Name: COLUMN mito_assembly_qc.frameshift_flag; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mito_assembly_qc.frameshift_flag IS 'True when the assembler or annotation reported a frameshift.';


--
-- Name: COLUMN mito_assembly_qc.reference_species; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mito_assembly_qc.reference_species IS 'Species of the reference MitoHiFi or OATK assembled against.';


--
-- Name: COLUMN mito_assembly_qc.reference_accession; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mito_assembly_qc.reference_accession IS 'Accession of that reference.';


--
-- Name: COLUMN mito_assembly_qc.qc_updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.mito_assembly_qc.qc_updated_at IS 'When the verdict was last written (database clock).';


--
-- Name: mito_assembly_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mito_assembly_run (
    assembly_id bigint NOT NULL,
    sequencing_id text NOT NULL
);


--
-- Name: TABLE mito_assembly_run; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mito_assembly_run IS 'The sequencing rows (a library on a run) an assembly was built from, derived from (og_id, seq_date) and tech. ilmn excludes iSEQ QC runs.';


--
-- Name: mito_gene; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mito_gene (
    gene text NOT NULL,
    gene_class text NOT NULL,
    sort_order integer NOT NULL,
    has_translation boolean DEFAULT false NOT NULL,
    CONSTRAINT mito_gene_gene_class_check CHECK ((gene_class = ANY (ARRAY['pcg'::text, 'rrna'::text, 'trna'::text])))
);


--
-- Name: TABLE mito_gene; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mito_gene IS 'Mitochondrial gene names. A new gene is an INSERT here plus v3.rebuild_mito_gene_views(); gene is also the legacy length column name, and gene || ''_trans'' the translated-length one.';


--
-- Name: mitogenome_data; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.mitogenome_data AS
 SELECT s.og_num,
    a.og_id,
    s.nominal_species_id,
    a.tech,
    a.seq_date,
    a.code,
    n.annotation,
    a.stats,
    a.length,
    d.mean_depth,
    a.avg_coverage,
    a.avg_base_coverage,
    d.median_depth,
    d.depth_sd,
    d.depth_cv,
    d.breadth_1x,
    d.breadth_10x,
    d.mito_mapped_reads,
    d.total_reads,
    d.mito_read_fraction,
    d.depth_target_length_bp,
    d.depth_target_fasta,
    d.depth_method,
    d.depth_measured_at,
    q.qc_status,
    q.manual_review_reason,
    q.numt_flag,
    q.frameshift_flag,
    q.reference_species,
    q.reference_accession,
    q.qc_updated_at,
    n.length_emma,
    n.cds_no,
    n.trna_no,
    n.rrna_no,
    n.passed,
    n.completeness_profile,
    n.missing_genes,
    n.extra_genes,
    n.duplicate_loci,
    n.annotation_gaps,
    n.trna_advisory,
    n.order_correct,
    n.order_status,
    n.order_variant,
    n.order_variant_taxon_check,
    n.order_deviation,
    n.order_deviation_detail,
    n.expected_lineage_genes,
    n.missing_expected_lineage_genes,
    n.lineage_gene_advisories,
    n.mitos_unmapped_features,
    n.mitos_known_auxiliary_features,
    n.annotation_integrity_status,
    n.annotation_integrity_issues,
    n.manual_curation_notes,
    n.annotation_stats_version,
    n.annotation_updated_at,
    g.rrna12s,
    g.rrna16s,
    g.atp6,
    g.atp6_trans,
    g.atp8,
    g.atp8_trans,
    g.cox1,
    g.cox1_trans,
    g.cox2,
    g.cox2_trans,
    g.cox3,
    g.cox3_trans,
    g.cytb,
    g.cytb_trans,
    g.nad1,
    g.nad1_trans,
    g.nad2,
    g.nad2_trans,
    g.nad3,
    g.nad3_trans,
    g.nad4,
    g.nad4_trans,
    g.nad4l,
    g.nad4l_trans,
    g.nad5,
    g.nad5_trans,
    g.nad6,
    g.nad6_trans,
    g.atp9,
    g.atp9_trans,
    g.mtmuts,
    g.mtmuts_trans,
    g.trna_phe,
    g.trna_val,
    g.trna_leuuag,
    g.trna_leuuaa,
    g.trna_ile,
    g.trna_met,
    g.trna_thr,
    g.trna_pro,
    g.trna_lys,
    g.trna_asp,
    g.trna_glu,
    g.trna_sergcu,
    g.trna_seruga,
    g.trna_tyr,
    g.trna_cys,
    g.trna_trp,
    g.trna_ala,
    g.trna_asn,
    g.trna_gly,
    g.trna_arg,
    g.trna_his,
    g.trna_gln
   FROM (((((public.mito_assembly a
     JOIN public.sample s ON ((s.og_id = a.og_id)))
     LEFT JOIN public.mito_annotation n ON ((n.assembly_id = a.assembly_id)))
     LEFT JOIN public.mito_assembly_depth d ON ((d.assembly_id = a.assembly_id)))
     LEFT JOIN public.mito_assembly_qc q ON ((q.assembly_id = a.assembly_id)))
     LEFT JOIN ( SELECT mito_annotation_gene.annotation_id,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'rrna12s'::text)) AS rrna12s,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'rrna16s'::text)) AS rrna16s,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'atp6'::text)) AS atp6,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'atp8'::text)) AS atp8,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'cox1'::text)) AS cox1,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'cox2'::text)) AS cox2,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'cox3'::text)) AS cox3,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'cytb'::text)) AS cytb,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'nad1'::text)) AS nad1,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'nad2'::text)) AS nad2,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'nad3'::text)) AS nad3,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'nad4'::text)) AS nad4,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'nad4l'::text)) AS nad4l,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'nad5'::text)) AS nad5,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'nad6'::text)) AS nad6,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_phe'::text)) AS trna_phe,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_val'::text)) AS trna_val,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_leuuag'::text)) AS trna_leuuag,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_leuuaa'::text)) AS trna_leuuaa,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_ile'::text)) AS trna_ile,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_met'::text)) AS trna_met,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_thr'::text)) AS trna_thr,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_pro'::text)) AS trna_pro,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_lys'::text)) AS trna_lys,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_asp'::text)) AS trna_asp,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_glu'::text)) AS trna_glu,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_sergcu'::text)) AS trna_sergcu,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_seruga'::text)) AS trna_seruga,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_tyr'::text)) AS trna_tyr,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_cys'::text)) AS trna_cys,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_trp'::text)) AS trna_trp,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_ala'::text)) AS trna_ala,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_asn'::text)) AS trna_asn,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_gly'::text)) AS trna_gly,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_arg'::text)) AS trna_arg,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_his'::text)) AS trna_his,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'trna_gln'::text)) AS trna_gln,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'atp9'::text)) AS atp9,
            max(mito_annotation_gene.length) FILTER (WHERE (mito_annotation_gene.gene = 'mtmuts'::text)) AS mtmuts,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'atp6'::text)) AS atp6_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'atp8'::text)) AS atp8_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'cox1'::text)) AS cox1_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'cox2'::text)) AS cox2_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'cox3'::text)) AS cox3_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'cytb'::text)) AS cytb_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'nad1'::text)) AS nad1_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'nad2'::text)) AS nad2_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'nad3'::text)) AS nad3_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'nad4'::text)) AS nad4_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'nad4l'::text)) AS nad4l_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'nad5'::text)) AS nad5_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'nad6'::text)) AS nad6_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'atp9'::text)) AS atp9_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE (mito_annotation_gene.gene = 'mtmuts'::text)) AS mtmuts_trans
           FROM public.mito_annotation_gene
          GROUP BY mito_annotation_gene.annotation_id) g ON ((g.annotation_id = n.annotation_id)));


--
-- Name: VIEW mitogenome_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.mitogenome_data IS 'Compatibility view: the 102 kept columns of the old mitogenome_data table plus og_num and nominal_species_id, grouped by output (056), plus completeness_profile and the assembly QC verdict (068). Read by column name, not position. One row per (assembly, annotation), plus one per unannotated assembly. Not a write path.';


--
-- Name: mitogenome_submission_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.mitogenome_submission_view AS
 SELECT s.og_num,
    a.og_id,
    s.nominal_species_id,
    a.tech,
    a.seq_date,
    a.code,
    n.annotation,
    a.stats,
    a.length,
    n.length_emma,
    n.cds_no,
    n.trna_no,
    n.rrna_no,
    n.missing_genes,
    n.extra_genes,
    n.order_correct,
    e.table2asn_status,
    e.warning_codes,
    e.webin_status,
    e.webin_reason,
    e.submission_ready,
    l.validated_species_name,
    l.validator
   FROM ((((public.mito_assembly a
     JOIN public.sample s ON ((s.og_id = a.og_id)))
     LEFT JOIN public.mito_annotation n ON ((n.assembly_id = a.assembly_id)))
     LEFT JOIN public.ena_validation_attempts e ON (((e.og_id = a.og_id) AND (e.tech = a.tech) AND (e.seq_date = a.seq_date) AND (e.code = a.code) AND (e.annotation = n.annotation))))
     LEFT JOIN public.lca_validation l ON (((l.og_id = a.og_id) AND (l.tech = a.tech) AND (l.seq_date = a.seq_date) AND (l.code = a.code) AND (l.annotation = n.annotation))));


--
-- Name: VIEW mitogenome_submission_view; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.mitogenome_submission_view IS 'mitogenome_submission_view rebuilt on the v3 tables, grouped by output (056); avg_coverage and avg_base_coverage are not shown. The ENA and LCA joins move to annotation_id at R.7.';


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
-- Name: ref_assembly_assembly_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ref_assembly ALTER COLUMN assembly_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ref_assembly_assembly_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ref_assembly_part; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_assembly_part (
    part_id bigint NOT NULL,
    assembly_id bigint NOT NULL,
    stage integer NOT NULL,
    haplotype text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_assembly_part_haplotype_check CHECK ((haplotype = ANY (ARRAY['hap1'::text, 'hap2'::text, 'dual'::text, 'p_ctg'::text, 'a_ctg'::text])))
);


--
-- Name: TABLE ref_assembly_part; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_assembly_part IS 'One sequence set of an assembly at a stage: hap1, hap2, p_ctg/a_ctg (hifiasm primary/alternate contigs), or dual.';


--
-- Name: COLUMN ref_assembly_part.haplotype; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_assembly_part.haplotype IS 'dual = hap1 and hap2 together: Merqury on both haplotypes, or OMNIC on the combined scaffold set.';


--
-- Name: ref_assembly_part_part_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ref_assembly_part ALTER COLUMN part_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ref_assembly_part_part_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ref_assembly_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_assembly_run (
    assembly_id bigint NOT NULL,
    sequencing_id text NOT NULL
);


--
-- Name: TABLE ref_assembly_run; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_assembly_run IS 'The sequencing rows an assembly was built from: PacBio/ONT DNA, and Hi-C once writers record it (trigger).';


--
-- Name: ref_busco; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_busco (
    part_id bigint NOT NULL,
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
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_busco_has_value CHECK ((num_nonnulls(dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds) > 0))
);


--
-- Name: TABLE ref_busco; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_busco IS 'BUSCO completeness and BUSCO''s own assembly statistics. Written by 03a_push_busco_results_to_sqldb.py (ref repo and post-curation).';


--
-- Name: COLUMN ref_busco.scaffold_n50_bus; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_busco.scaffold_n50_bus IS 'BUSCO''s own scaffold N50; not reliable on every BUSCO version (see 052, draft_busco). Use ref_gfastats.scaffold_n50.';


--
-- Name: COLUMN ref_busco.contigs_n50_bus; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_busco.contigs_n50_bus IS 'BUSCO''s own contig N50; see scaffold_n50_bus. Use ref_gfastats.contig_n50.';


--
-- Name: ref_chromosome_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_chromosome_stats (
    part_id bigint NOT NULL,
    num_chromosomes integer,
    pct_assigned numeric(5,2),
    pct_no_super numeric(5,2),
    num_seq_no_super integer,
    max_len_no_super bigint,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_chromosome_stats_has_value CHECK ((num_nonnulls(num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super) > 0))
);


--
-- Name: TABLE ref_chromosome_stats; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_chromosome_stats IS 'Chromosome assignment of the curated assembly (SUPER_* scaffolds). Written by 06b_push_percentage_stats_to_sqldb.py (post-curation).';


--
-- Name: ref_gfastats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_gfastats (
    part_id bigint NOT NULL,
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
    num_gaps integer,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_gfastats_has_value CHECK ((num_nonnulls(num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, num_gaps) > 0))
);


--
-- Name: TABLE ref_gfastats; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_gfastats IS 'gfastats assembly statistics; the authoritative N50. Written by 04a/04b_*push_gfa* (ref repo) and 04a_push_gfa_results_to_sqldb.py (post-curation, which adds num_gaps). The *_size_mb columns are the tool''s own rounding, stored, not derived (RG.0 §1.6).';


--
-- Name: ref_merqury_completeness; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_merqury_completeness (
    part_id bigint NOT NULL,
    solid_k_mers bigint,
    total_k_mers bigint,
    completeness numeric(7,4),
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_merqury_completeness_has_value CHECK ((num_nonnulls(solid_k_mers, total_k_mers, completeness) > 0))
);


--
-- Name: TABLE ref_merqury_completeness; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_merqury_completeness IS 'Merqury k-mer completeness. Written by 02d_push_merqury_completeness_results_to_sqldb.py (ref repo and post-curation). public.ref_genomes.k_mer_set is not carried: it was never filled.';


--
-- Name: ref_merqury_qv; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_merqury_qv (
    part_id bigint NOT NULL,
    unique_k_mers_assembly bigint,
    k_mers_total bigint,
    qv numeric(6,4),
    error double precision,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_merqury_qv_has_value CHECK ((num_nonnulls(unique_k_mers_assembly, k_mers_total, qv, error) > 0))
);


--
-- Name: TABLE ref_merqury_qv; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_merqury_qv IS 'Merqury consensus QV. Written by 02b_push_merqury_qv_results_to_sqldb.py (ref repo and post-curation). On a dual part it is the value for hap1 and hap2 together.';


--
-- Name: ref_omnic; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_omnic (
    part_id bigint NOT NULL,
    total bigint,
    total_unmapped bigint,
    total_single_sided_mapped bigint,
    total_mapped bigint,
    total_dups bigint,
    total_nodups bigint,
    cis bigint,
    trans bigint,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_omnic_has_value CHECK ((num_nonnulls(total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans) > 0))
);


--
-- Name: TABLE ref_omnic; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_omnic IS 'Hi-C mapping QC (Dovetail OMNIC). Written by 05a_push_omnic_results_to_sqldb.py (ref repo). Also present on hifi1 stage-1 haplotypes: Hi-C mapped to the HiFi-only haplotypes before scaffolding (RG.0 §3).';


--
-- Name: ref_seqkit_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_seqkit_stats (
    part_id bigint NOT NULL,
    format text,
    type text,
    num_seqs integer,
    sum_len bigint,
    min_len bigint,
    avg_len numeric(20,2),
    max_len bigint,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_seqkit_stats_has_value CHECK ((num_nonnulls(format, type, num_seqs, sum_len, min_len, avg_len, max_len) > 0))
);


--
-- Name: TABLE ref_seqkit_stats; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_seqkit_stats IS 'seqkit stats of the curated FASTA. Written by 05a_push_stats_compiled_results_to_sql.py (post-curation).';


--
-- Name: ref_genomes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ref_genomes AS
 SELECT a.og_id,
    a.seq_date,
    p.stage,
    p.haplotype,
    gf.num_contigs,
    gf.contig_n50,
    gf.contig_n50_size_mb,
    gf.num_scaffolds,
    gf.scaffold_n50,
    gf.scaffold_n50_size_mb,
    gf.largest_scaffold,
    gf.largest_scaffold_size_mb,
    gf.total_scaffold_length,
    gf.total_scaffold_length_size_mb,
    gf.gc_content_percent,
    bu.dataset,
    bu.complete,
    bu.single_copy,
    bu.multi_copy,
    bu.fragmented,
    bu.missing,
    bu.n_markers,
    bu.internal_stop_codon_percent,
    bu.scaffold_n50_bus,
    bu.contigs_n50_bus,
    bu.percent_gaps,
    bu.number_of_scaffolds,
    mq.unique_k_mers_assembly,
    mq.k_mers_total,
    mq.qv,
    mq.error,
    NULL::text AS k_mer_set,
    mc.solid_k_mers,
    mc.total_k_mers,
    mc.completeness,
    om.total,
    om.total_unmapped,
    om.total_single_sided_mapped,
    om.total_mapped,
    om.total_dups,
    om.total_nodups,
    om.cis,
    om.trans,
    NULL::bigint AS hap2_chr_level_max_len,
    sk.format,
    sk.type,
    sk.num_seqs,
    sk.sum_len,
    sk.min_len,
    sk.avg_len,
    sk.max_len,
    ch.num_chromosomes,
    ch.pct_assigned,
    ch.pct_no_super,
    ch.num_seq_no_super,
    ch.max_len_no_super,
    a.version,
    gf.num_gaps
   FROM ((((((((public.ref_assembly_part p
     JOIN public.ref_assembly a ON ((a.assembly_id = p.assembly_id)))
     LEFT JOIN public.ref_gfastats gf ON ((gf.part_id = p.part_id)))
     LEFT JOIN public.ref_busco bu ON ((bu.part_id = p.part_id)))
     LEFT JOIN public.ref_merqury_qv mq ON ((mq.part_id = p.part_id)))
     LEFT JOIN public.ref_merqury_completeness mc ON ((mc.part_id = p.part_id)))
     LEFT JOIN public.ref_omnic om ON ((om.part_id = p.part_id)))
     LEFT JOIN public.ref_seqkit_stats sk ON ((sk.part_id = p.part_id)))
     LEFT JOIN public.ref_chromosome_stats ch ON ((ch.part_id = p.part_id)));


--
-- Name: VIEW ref_genomes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.ref_genomes IS 'Compatibility view: public.ref_genomes''s 58 columns in its order, one row per part. k_mer_set and hap2_chr_level_max_len are always NULL. Not a write path: write ref_assembly, ref_assembly_part, ref_assembly_run and the per-tool tables (ref_busco, ref_gfastats, ref_merqury_qv, ...).';


--
-- Name: ref_submission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_submission (
    submission_id bigint NOT NULL,
    og_id text NOT NULL,
    assembly_id bigint,
    biosample text,
    bioproject_umbrella text,
    bioproject_rawdata text,
    embargo_status text NOT NULL,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_submission_embargo_status_check CHECK ((embargo_status = ANY (ARRAY['Release'::text, 'Embargo'::text])))
);


--
-- Name: TABLE ref_submission; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_submission IS 'NCBI/ENA submission of a reference genome, one per OG. assembly_id: the OG''s one curated assembly, NULL where it has none or several. Writers: ENA-ref-genomes steps 09 (accessions) and 10 (GCA), and OcOm_B219 scripts/resolve_gca_accessions.py (GCA).';


--
-- Name: ref_submission_haplotype; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_submission_haplotype (
    submission_id bigint NOT NULL,
    haplotype text NOT NULL,
    bioproject text,
    assembly_accession text,
    gca_accession text,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    analysis_accession text,
    assembly_id bigint,
    stage integer DEFAULT 3 NOT NULL,
    CONSTRAINT ref_submission_haplotype_analysis_accession_shape CHECK ((analysis_accession ~ '^ERZ[0-9]+$'::text)),
    CONSTRAINT ref_submission_haplotype_assembly_accession_shape CHECK ((assembly_accession ~ '^[A-Z]{4}([A-Z]{2})?[0-9]{8,9}$'::text)),
    CONSTRAINT ref_submission_haplotype_gca_accession_shape CHECK ((gca_accession ~ '^GCA_[0-9]{9}\.[0-9]+$'::text)),
    CONSTRAINT ref_submission_haplotype_haplotype_check CHECK ((haplotype = ANY (ARRAY['hap1'::text, 'hap2'::text]))),
    CONSTRAINT ref_submission_haplotype_has_value CHECK ((num_nonnulls(bioproject, analysis_accession, assembly_accession, gca_accession) > 0)),
    CONSTRAINT ref_submission_haplotype_one_assembly_id CHECK ((num_nonnulls(analysis_accession, assembly_accession) <= 1)),
    CONSTRAINT ref_submission_haplotype_stage_check CHECK ((stage = 3))
);


--
-- Name: TABLE ref_submission_haplotype; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_submission_haplotype IS 'Per-haplotype BioProject and assembly accessions of a submission. Was the _hap1/_hap2 column pairs.';


--
-- Name: COLUMN ref_submission_haplotype.assembly_accession; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_submission_haplotype.assembly_accession IS 'WGS master record accession (e.g. JBLNKH000000000) of an NCBI-submitted assembly. ENA submissions carry analysis_accession instead. Migration 070.';


--
-- Name: COLUMN ref_submission_haplotype.gca_accession; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_submission_haplotype.gca_accession IS 'Public INSDC assembly accession (GCA_...), resolved after processing (step 10).';


--
-- Name: COLUMN ref_submission_haplotype.analysis_accession; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_submission_haplotype.analysis_accession IS 'ENA analysis accession (ERZ...) of the submitted assembly, from the Webin receipt (ENA-ref-genomes step 09). Not an assembly accession: step 10 resolves the GCA_ into gca_accession. Migration 070.';


--
-- Name: COLUMN ref_submission_haplotype.assembly_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_submission_haplotype.assembly_id IS 'The submission''s curated assembly (ref_submission.assembly_id, kept equal by trigger). With stage and haplotype it names the ref_assembly_part submitted. Migration 070.';


--
-- Name: COLUMN ref_submission_haplotype.stage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_submission_haplotype.stage IS 'Always 3 (curated): what is submitted. Migration 070.';


--
-- Name: ref_genomes_assembly_uploads; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ref_genomes_assembly_uploads AS
 SELECT s.og_id,
    s.biosample,
    s.bioproject_umbrella,
    h1.bioproject AS bioproject_hap1,
    h2.bioproject AS bioproject_hap2,
    s.bioproject_rawdata,
    COALESCE(h1.analysis_accession, h1.assembly_accession) AS assembly_accession_hap1,
    COALESCE(h2.analysis_accession, h2.assembly_accession) AS assembly_accession_hap2,
    s.embargo_status,
    h1.gca_accession AS gca_accession_hap1,
    h2.gca_accession AS gca_accession_hap2
   FROM ((public.ref_submission s
     LEFT JOIN public.ref_submission_haplotype h1 ON (((h1.submission_id = s.submission_id) AND (h1.haplotype = 'hap1'::text))))
     LEFT JOIN public.ref_submission_haplotype h2 ON (((h2.submission_id = s.submission_id) AND (h2.haplotype = 'hap2'::text))));


--
-- Name: VIEW ref_genomes_assembly_uploads; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.ref_genomes_assembly_uploads IS 'Compatibility view: public.ref_genomes_assembly_uploads''s columns in its order. assembly_accession_hapN shows coalesce(analysis_accession, assembly_accession): the ERZ, or the WGS master of older NCBI submissions (070). Not a write path: write ref_submission, and per haplotype ref_submission_haplotype (bioproject, analysis_accession, assembly_accession, gca_accession), as ENA-ref-genomes steps 09 and 10 do. OcOm_B219''s resolve_gca_accessions.py still updates gca_accession_hapN here and fails after RG.6 until ported (owner, 2026-11-02).';


--
-- Name: ref_sra_upload; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_sra_upload (
    srr_accession text NOT NULL,
    submission_id bigint NOT NULL,
    filenames text,
    data_type text,
    ncbi_status text,
    release_date date,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_sra_upload_data_type_check CHECK ((data_type = ANY (ARRAY['hifi'::text, 'hic'::text, 'ont'::text, 'illumina'::text]))),
    CONSTRAINT ref_sra_upload_ncbi_status_check CHECK ((ncbi_status = ANY (ARRAY['Released'::text, 'ToBeReleased'::text]))),
    CONSTRAINT ref_sra_upload_status_or_release_date CHECK ((num_nonnulls(ncbi_status, release_date) <= 1))
);


--
-- Name: TABLE ref_sra_upload; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_sra_upload IS 'Raw reads uploaded to the SRA/ENA for a submission, one row per run accession. Writer: ENA-ref-genomes workflow/09_push_submission_data_to_db.py.';


--
-- Name: COLUMN ref_sra_upload.release_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_sra_upload.release_date IS 'Scheduled public release (embargo end) of the run: ENA holdUntilDate, written by ENA-ref-genomes step 09. public.ref_genomes_sra_uploads keeps it in ncbi_status instead of a status.';


--
-- Name: ref_genomes_sra_uploads; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ref_genomes_sra_uploads AS
 SELECT u.srr_accession,
    s.og_id,
    u.filenames,
    u.data_type,
    COALESCE(u.ncbi_status, to_char((u.release_date)::timestamp with time zone, 'YYYY-MM-DD'::text)) AS ncbi_status
   FROM (public.ref_sra_upload u
     JOIN public.ref_submission s ON ((s.submission_id = u.submission_id)));


--
-- Name: VIEW ref_genomes_sra_uploads; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.ref_genomes_sra_uploads IS 'Compatibility view: public.ref_genomes_sra_uploads''s columns in its order, status and date recombined. Not a write path: write ref_sra_upload and its run links (ref_sra_upload_run, resolve_sra_upload_runs()), as ENA-ref-genomes step 09 does.';


--
-- Name: ref_read_set_external; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_read_set_external (
    read_set_id bigint NOT NULL,
    cells text[] NOT NULL,
    supplier text,
    note text,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ref_read_set_external_cells_check CHECK ((cardinality(cells) > 0))
);


--
-- Name: TABLE ref_read_set_external; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_read_set_external IS 'HiFi read sets whose reads are not OceanOmics sequencing, so have no sequencing row (071). Such a read set has no ref_read_set_run rows; its seq_date is the samplesheet date.';


--
-- Name: COLUMN ref_read_set_external.cells; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_read_set_external.cells IS 'The read files or cells, as staged in pacbio-sra/{OG}/.';


--
-- Name: COLUMN ref_read_set_external.supplier; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ref_read_set_external.supplier IS 'Who sequenced them, where known.';


--
-- Name: ref_read_set_read_set_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ref_read_set ALTER COLUMN read_set_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ref_read_set_read_set_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ref_read_set_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_read_set_run (
    read_set_id bigint NOT NULL,
    sequencing_id text NOT NULL
);


--
-- Name: TABLE ref_read_set_run; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_read_set_run IS 'The PacBio sequencing rows in a read set. PacBio DNA libraries only (trigger). Migration 062.';


--
-- Name: ref_sra_upload_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_sra_upload_run (
    srr_accession text NOT NULL,
    sequencing_id text NOT NULL
);


--
-- Name: TABLE ref_sra_upload_run; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_sra_upload_run IS 'The sequencing rows (library on a run) an SRA upload''s files came from. Several where one upload carries several libraries. Migration 064.';


--
-- Name: ref_sra_upload_unlinked; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_sra_upload_unlinked (
    srr_accession text NOT NULL,
    reason text NOT NULL,
    reviewed_on date DEFAULT CURRENT_DATE NOT NULL
);


--
-- Name: TABLE ref_sra_upload_unlinked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_sra_upload_unlinked IS 'SRA uploads reviewed and left with no sequencing link, and why (064''s evidence). The sync does not re-resolve these; delete a row once the lab has fixed the cause.';


--
-- Name: ref_stage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_stage (
    stage integer NOT NULL,
    name text NOT NULL,
    description text NOT NULL
);


--
-- Name: TABLE ref_stage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ref_stage IS 'Assembly stages, from the pipeline file names (<og>_v<date>.<version>.<stage>.<tool>...).';


--
-- Name: ref_submission_submission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ref_submission ALTER COLUMN submission_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ref_submission_submission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
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
-- Name: sequencing_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sequencing_run (
    run_id text NOT NULL,
    mach text,
    run_seq_date text,
    initial text,
    instrument text,
    run_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE sequencing_run; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.sequencing_run IS 'One sequencing run, seeded from the distinct sequencing.run_id. FKs to it arrive at R.7.';


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
-- Name: v_draft_genome_status; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_draft_genome_status AS
 SELECT d.og_num,
    d.og_id,
    s.nominal_species_id,
    d.seq_date,
    d.mach,
    (r.n_runs > 0) AS has_run_link,
    (f.draft_id IS NOT NULL) AS has_fastp,
    (gs.draft_id IS NOT NULL) AS has_genomescope,
    gs.output_set AS genomescope_output_set,
    (ti.draft_id IS NOT NULL) AS has_tiara,
    (ct.draft_id IS NOT NULL) AS has_contamination,
    (b.draft_id IS NOT NULL) AS has_busco,
    (mq.draft_id IS NOT NULL) AS has_merqury,
    (gf.draft_id IS NOT NULL) AS has_gfastats,
    (su.draft_id IS NOT NULL) AS has_submission,
    num_nonnulls(f.draft_id, gs.draft_id, ti.draft_id, ct.draft_id, b.draft_id, mq.draft_id, gf.draft_id) AS processes_done,
    ((f.draft_id IS NOT NULL) AND (num_nonnulls(gs.draft_id, ti.draft_id, ct.draft_id, b.draft_id, mq.draft_id, gf.draft_id) = 0)) AS reads_only
   FROM ((((((((((public.draft_genome d
     JOIN public.sample s ON ((s.og_id = d.og_id)))
     LEFT JOIN LATERAL ( SELECT count(*) AS n_runs
           FROM public.draft_genome_run x
          WHERE (x.draft_id = d.draft_id)) r ON (true))
     LEFT JOIN public.draft_fastp f ON ((f.draft_id = d.draft_id)))
     LEFT JOIN public.draft_genomescope gs ON ((gs.draft_id = d.draft_id)))
     LEFT JOIN public.draft_tiara ti ON ((ti.draft_id = d.draft_id)))
     LEFT JOIN public.draft_contamination ct ON ((ct.draft_id = d.draft_id)))
     LEFT JOIN public.draft_busco b ON ((b.draft_id = d.draft_id)))
     LEFT JOIN public.draft_merqury mq ON ((mq.draft_id = d.draft_id)))
     LEFT JOIN public.draft_gfastats gf ON ((gf.draft_id = d.draft_id)))
     LEFT JOIN public.draft_submission su ON ((su.draft_id = d.draft_id)));


--
-- Name: VIEW v_draft_genome_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_draft_genome_status IS 'One row per draft genome: which pipeline processes have results. processes_done counts the seven pipeline processes (fastp to gfastats); submission is shown but not counted; DepthSizer is retired and not shown.';


--
-- Name: v_genome_size_comparison; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_genome_size_comparison AS
 SELECT s.og_num,
    d.og_id,
    sp.species,
    sp.ncbi_taxon_id,
    d.seq_date,
    gs.genomesize AS estimated_bp,
    a.total_sequence_length AS ncbi_bp,
        CASE
            WHEN (a.total_sequence_length > 0) THEN round(((gs.genomesize)::numeric / (a.total_sequence_length)::numeric), 3)
            ELSE NULL::numeric
        END AS estimated_over_ncbi,
    a.assembly_accession,
    a.assembly_level,
    a.is_refseq,
    a.is_representative
   FROM ((((public.draft_genome d
     LEFT JOIN public.draft_genomescope gs ON ((gs.draft_id = d.draft_id)))
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
-- Name: v_mito_annotation_genes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_mito_annotation_genes AS
 SELECT s.og_num,
    a.og_id,
    s.nominal_species_id,
    a.tech,
    a.seq_date,
    a.code,
    n.annotation,
    n.annotation_id,
    n.is_selected,
    max(g.length) FILTER (WHERE (g.gene = 'rrna12s'::text)) AS rrna12s,
    max(g.length) FILTER (WHERE (g.gene = 'rrna16s'::text)) AS rrna16s,
    max(g.length) FILTER (WHERE (g.gene = 'atp6'::text)) AS atp6,
    max(g.translated_length) FILTER (WHERE (g.gene = 'atp6'::text)) AS atp6_trans,
    max(g.length) FILTER (WHERE (g.gene = 'atp8'::text)) AS atp8,
    max(g.translated_length) FILTER (WHERE (g.gene = 'atp8'::text)) AS atp8_trans,
    max(g.length) FILTER (WHERE (g.gene = 'cox1'::text)) AS cox1,
    max(g.translated_length) FILTER (WHERE (g.gene = 'cox1'::text)) AS cox1_trans,
    max(g.length) FILTER (WHERE (g.gene = 'cox2'::text)) AS cox2,
    max(g.translated_length) FILTER (WHERE (g.gene = 'cox2'::text)) AS cox2_trans,
    max(g.length) FILTER (WHERE (g.gene = 'cox3'::text)) AS cox3,
    max(g.translated_length) FILTER (WHERE (g.gene = 'cox3'::text)) AS cox3_trans,
    max(g.length) FILTER (WHERE (g.gene = 'cytb'::text)) AS cytb,
    max(g.translated_length) FILTER (WHERE (g.gene = 'cytb'::text)) AS cytb_trans,
    max(g.length) FILTER (WHERE (g.gene = 'nad1'::text)) AS nad1,
    max(g.translated_length) FILTER (WHERE (g.gene = 'nad1'::text)) AS nad1_trans,
    max(g.length) FILTER (WHERE (g.gene = 'nad2'::text)) AS nad2,
    max(g.translated_length) FILTER (WHERE (g.gene = 'nad2'::text)) AS nad2_trans,
    max(g.length) FILTER (WHERE (g.gene = 'nad3'::text)) AS nad3,
    max(g.translated_length) FILTER (WHERE (g.gene = 'nad3'::text)) AS nad3_trans,
    max(g.length) FILTER (WHERE (g.gene = 'nad4'::text)) AS nad4,
    max(g.translated_length) FILTER (WHERE (g.gene = 'nad4'::text)) AS nad4_trans,
    max(g.length) FILTER (WHERE (g.gene = 'nad4l'::text)) AS nad4l,
    max(g.translated_length) FILTER (WHERE (g.gene = 'nad4l'::text)) AS nad4l_trans,
    max(g.length) FILTER (WHERE (g.gene = 'nad5'::text)) AS nad5,
    max(g.translated_length) FILTER (WHERE (g.gene = 'nad5'::text)) AS nad5_trans,
    max(g.length) FILTER (WHERE (g.gene = 'nad6'::text)) AS nad6,
    max(g.translated_length) FILTER (WHERE (g.gene = 'nad6'::text)) AS nad6_trans,
    max(g.length) FILTER (WHERE (g.gene = 'atp9'::text)) AS atp9,
    max(g.translated_length) FILTER (WHERE (g.gene = 'atp9'::text)) AS atp9_trans,
    max(g.length) FILTER (WHERE (g.gene = 'mtmuts'::text)) AS mtmuts,
    max(g.translated_length) FILTER (WHERE (g.gene = 'mtmuts'::text)) AS mtmuts_trans,
    max(g.length) FILTER (WHERE (g.gene = 'trna_phe'::text)) AS trna_phe,
    max(g.length) FILTER (WHERE (g.gene = 'trna_val'::text)) AS trna_val,
    max(g.length) FILTER (WHERE (g.gene = 'trna_leuuag'::text)) AS trna_leuuag,
    max(g.length) FILTER (WHERE (g.gene = 'trna_leuuaa'::text)) AS trna_leuuaa,
    max(g.length) FILTER (WHERE (g.gene = 'trna_ile'::text)) AS trna_ile,
    max(g.length) FILTER (WHERE (g.gene = 'trna_met'::text)) AS trna_met,
    max(g.length) FILTER (WHERE (g.gene = 'trna_thr'::text)) AS trna_thr,
    max(g.length) FILTER (WHERE (g.gene = 'trna_pro'::text)) AS trna_pro,
    max(g.length) FILTER (WHERE (g.gene = 'trna_lys'::text)) AS trna_lys,
    max(g.length) FILTER (WHERE (g.gene = 'trna_asp'::text)) AS trna_asp,
    max(g.length) FILTER (WHERE (g.gene = 'trna_glu'::text)) AS trna_glu,
    max(g.length) FILTER (WHERE (g.gene = 'trna_sergcu'::text)) AS trna_sergcu,
    max(g.length) FILTER (WHERE (g.gene = 'trna_seruga'::text)) AS trna_seruga,
    max(g.length) FILTER (WHERE (g.gene = 'trna_tyr'::text)) AS trna_tyr,
    max(g.length) FILTER (WHERE (g.gene = 'trna_cys'::text)) AS trna_cys,
    max(g.length) FILTER (WHERE (g.gene = 'trna_trp'::text)) AS trna_trp,
    max(g.length) FILTER (WHERE (g.gene = 'trna_ala'::text)) AS trna_ala,
    max(g.length) FILTER (WHERE (g.gene = 'trna_asn'::text)) AS trna_asn,
    max(g.length) FILTER (WHERE (g.gene = 'trna_gly'::text)) AS trna_gly,
    max(g.length) FILTER (WHERE (g.gene = 'trna_arg'::text)) AS trna_arg,
    max(g.length) FILTER (WHERE (g.gene = 'trna_his'::text)) AS trna_his,
    max(g.length) FILTER (WHERE (g.gene = 'trna_gln'::text)) AS trna_gln
   FROM (((public.mito_annotation n
     JOIN public.mito_assembly a ON ((a.assembly_id = n.assembly_id)))
     JOIN public.sample s ON ((s.og_id = a.og_id)))
     LEFT JOIN public.mito_annotation_gene g ON ((g.annotation_id = n.annotation_id)))
  GROUP BY s.og_num, a.og_id, s.nominal_species_id, a.tech, a.seq_date, a.code, n.annotation, n.annotation_id, n.is_selected;


--
-- Name: VIEW v_mito_annotation_genes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_mito_annotation_genes IS 'One row per annotation, gene lengths wide: rRNA, protein-coding (each beside its _trans), tRNA. Generated by rebuild_mito_gene_views() from mito_gene; is_selected is display only. Do not build other views on this one.';


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
-- Name: v_read_qc_sequencing_readiness; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_read_qc_sequencing_readiness AS
 SELECT 'hifi'::text AS kind,
    q.og_id,
    q.tissue,
    q.ext_type,
    q.lib_code,
    NULL::text AS lane,
    q.run_id,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM public.sequencing s
              WHERE (s.run_id = q.run_id)))) THEN 'run not in sequencing'::text
            WHEN (NOT (EXISTS ( SELECT 1
               FROM public.library l
              WHERE (l.library_tube_id = (((((q.og_id || q.tissue) || '_'::text) || q.ext_type) || '_'::text) || q.lib_code))))) THEN 'library tube not in library'::text
            ELSE 'no single sequencing row for this tube on this run'::text
        END AS reason
   FROM public.hifi_read_qc q
  WHERE (q.sequencing_id IS NULL)
UNION ALL
 SELECT 'hic'::text AS kind,
    q.og_id,
    q.tissue,
    q.ext_type,
    q.lib_code,
    q.lane,
    q.run_id,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM public.sequencing s
              WHERE (s.run_id = q.run_id)))) THEN 'run not in sequencing'::text
            WHEN (( SELECT count(*) AS count
               FROM public.v_sequencing_browse s
              WHERE ((s.og_id = q.og_id) AND (s.run_id = q.run_id) AND (s.technology = 'Hi-C'::text) AND (s.tissue_id ~~ ((q.og_id || COALESCE(q.tissue, ''::text)) || '%'::text)))) > 1) THEN 'several Hi-C libraries of this OG and tissue on this run'::text
            ELSE 'no Hi-C library of this OG and tissue on this run'::text
        END AS reason
   FROM public.hic_read_qc q
  WHERE (q.sequencing_id IS NULL);


--
-- Name: VIEW v_read_qc_sequencing_readiness; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_read_qc_sequencing_readiness IS 'Read-QC rows with no sequencing link, and why. Fix at source (the workbook); the writers link new rows.';


--
-- Name: v_read_set_run_readiness; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_read_set_run_readiness AS
 SELECT rs.og_id,
    rs.seq_date,
    rs.read_set_id,
    ( SELECT string_agg(s.sequencing_id, ', '::text ORDER BY s.seq_date, s.sequencing_id) AS string_agg
           FROM public.v_sequencing_browse s
          WHERE ((s.og_id = rs.og_id) AND (s.technology = ANY (ARRAY['PacBio HIFI'::text, 'PacBio'::text])) AND (s.library_type = 'pacbio'::text) AND (s.status IS DISTINCT FROM 'Failed'::text))) AS pacbio_rows_for_og
   FROM public.ref_read_set rs
  WHERE ((NOT (EXISTS ( SELECT 1
           FROM public.ref_read_set_run r
          WHERE (r.read_set_id = rs.read_set_id)))) AND (NOT (EXISTS ( SELECT 1
           FROM public.ref_read_set_external x
          WHERE (x.read_set_id = rs.read_set_id)))));


--
-- Name: VIEW v_read_set_run_readiness; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_read_set_run_readiness IS 'Read sets with no run link that are not external, and the OG''s PacBio DNA rows to choose from. On 2026-11-02: OG763 (its DNA row is missing from the workbook, 071).';


--
-- Name: v_ref_assembly_run_readiness; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ref_assembly_run_readiness AS
 SELECT a.og_num,
    a.og_id,
    a.seq_date,
    a.version,
    ( SELECT string_agg(s.sequencing_id, ', '::text ORDER BY s.seq_date, s.sequencing_id) AS string_agg
           FROM public.v_sequencing_browse s
          WHERE ((s.og_id = a.og_id) AND (s.technology = ANY (ARRAY['PacBio HIFI'::text, 'PacBio'::text, 'ONT'::text])) AND (s.library_type = ANY (ARRAY['pacbio'::text, 'ont'::text])) AND (s.status IS DISTINCT FROM 'Failed'::text))) AS long_read_rows_for_og
   FROM public.ref_assembly a
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.ref_assembly_run r
          WHERE (r.assembly_id = a.assembly_id))));


--
-- Name: VIEW v_ref_assembly_run_readiness; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_ref_assembly_run_readiness IS 'Assemblies with no run link, and the OG''s PacBio/ONT DNA rows to choose from. Their seq_date matches no run date (RG.0 §1.5); the writers link new assemblies.';


--
-- Name: v_ref_assembly_status; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ref_assembly_status AS
SELECT
    NULL::integer AS og_num,
    NULL::text AS og_id,
    NULL::text AS seq_date,
    NULL::text AS version,
    NULL::text AS strategy,
    NULL::integer AS attempt,
    NULL::bigint AS run_links,
    NULL::bigint AS parts,
    NULL::text AS stages,
    NULL::boolean AS curated,
    NULL::text AS gfastats_stages,
    NULL::text AS busco_stages,
    NULL::text AS merqury_qv_stages,
    NULL::text AS merqury_completeness_stages,
    NULL::text AS omnic_stages,
    NULL::text AS seqkit_stats_stages,
    NULL::text AS chromosome_stats_stages;


--
-- Name: VIEW v_ref_assembly_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_ref_assembly_status IS 'One row per assembly: which stages exist, and at which stages each tool has results (e.g. busco_stages = ''0,2,3'').';


--
-- Name: v_ref_assembly_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ref_assembly_summary AS
 WITH final_part AS (
         SELECT DISTINCT ON (p.assembly_id, p.haplotype) p.part_id,
            p.assembly_id,
            p.stage,
            p.haplotype,
            p.created_at
           FROM public.ref_assembly_part p
          WHERE (p.haplotype <> 'dual'::text)
          ORDER BY p.assembly_id, p.haplotype, p.stage DESC
        )
 SELECT a.og_num,
    a.og_id,
    a.seq_date,
    a.version,
    f.haplotype,
    f.stage AS final_stage,
    st.name AS final_stage_name,
    gf.num_scaffolds,
    gf.scaffold_n50_size_mb,
    gf.total_scaffold_length_size_mb,
    gf.gc_content_percent,
    ch.num_chromosomes,
    ch.pct_assigned,
    bu.dataset AS busco_dataset,
    bu.complete AS busco_complete,
    bu.single_copy AS busco_single_copy,
    bu.multi_copy AS busco_multi_copy,
    bu.fragmented AS busco_fragmented,
    bu.missing AS busco_missing,
    mq.qv,
    mc.completeness AS kmer_completeness
   FROM (((((((final_part f
     JOIN public.ref_assembly a ON ((a.assembly_id = f.assembly_id)))
     JOIN public.ref_stage st ON ((st.stage = f.stage)))
     LEFT JOIN public.ref_gfastats gf ON ((gf.part_id = f.part_id)))
     LEFT JOIN public.ref_chromosome_stats ch ON ((ch.part_id = f.part_id)))
     LEFT JOIN public.ref_busco bu ON ((bu.part_id = f.part_id)))
     LEFT JOIN public.ref_merqury_qv mq ON ((mq.part_id = f.part_id)))
     LEFT JOIN public.ref_merqury_completeness mc ON ((mc.part_id = f.part_id)));


--
-- Name: VIEW v_ref_assembly_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_ref_assembly_summary IS 'One row per assembly and haplotype (not dual): the latest stage present and its headline metrics.';


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
-- Name: v_sequencing_run_fk_readiness; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sequencing_run_fk_readiness AS
 SELECT 'sequencing'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_run_ids
   FROM (public.sequencing c
     LEFT JOIN public.sequencing_run r ON ((r.run_id = c.run_id)))
UNION ALL
 SELECT 'raw_data'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_run_ids
   FROM (public.raw_data c
     LEFT JOIN public.sequencing_run r ON ((r.run_id = c.run_id)))
UNION ALL
 SELECT 'hifi_read_qc'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_run_ids
   FROM (public.hifi_read_qc c
     LEFT JOIN public.sequencing_run r ON ((r.run_id = c.run_id)))
UNION ALL
 SELECT 'hic_read_qc'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_run_ids
   FROM (public.hic_read_qc c
     LEFT JOIN public.sequencing_run r ON ((r.run_id = c.run_id)));


--
-- Name: VIEW v_sequencing_run_fk_readiness; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_sequencing_run_fk_readiness IS 'For each table R.7 will FK to sequencing_run: rows that would fail today, and their run IDs. The two read-QC rows read hifi_read_qc and hic_read_qc since RG.6 (073).';


--
-- Name: v_sequencing_run_issues; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sequencing_run_issues AS
 SELECT r.run_id,
    (r.mach IS NULL) AS run_id_unparsed,
    (r.instrument IS NULL) AS instrument_disagrees_or_missing,
    (r.run_date IS NULL) AS run_date_disagrees_or_missing,
    ( SELECT string_agg(DISTINCT COALESCE(s.instrument, '(null)'::text), ', '::text) AS string_agg
           FROM public.sequencing s
          WHERE (s.run_id = r.run_id)) AS instruments,
    ( SELECT string_agg(DISTINCT COALESCE((s.run_date)::text, '(null)'::text), ', '::text) AS string_agg
           FROM public.sequencing s
          WHERE (s.run_id = r.run_id)) AS run_dates
   FROM public.sequencing_run r
  WHERE ((r.mach IS NULL) OR (r.instrument IS NULL) OR (r.run_date IS NULL));


--
-- Name: VIEW v_sequencing_run_issues; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_sequencing_run_issues IS 'Runs whose ID does not parse, or whose sequencing rows disagree on instrument or run date. For the lab.';


--
-- Name: v_sra_upload_run_readiness; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sra_upload_run_readiness AS
 SELECT s.og_id,
    u.srr_accession,
    u.data_type,
    COALESCE(x.reason, 'not resolved by the forward rule'::text) AS reason,
    x.reviewed_on,
    "left"(u.filenames, 200) AS filenames
   FROM ((public.ref_sra_upload u
     JOIN public.ref_submission s USING (submission_id))
     LEFT JOIN public.ref_sra_upload_unlinked x USING (srr_accession))
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.ref_sra_upload_run r
          WHERE (r.srr_accession = u.srr_accession))));


--
-- Name: VIEW v_sra_upload_run_readiness; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_sra_upload_run_readiness IS 'SRA uploads with no sequencing link, and why. Most are run IDs the workbook has wrong (064''s header); fix at source, delete the ref_sra_upload_unlinked row, and insert the links resolve_sra_upload_runs() returns. Since RG.6 no nightly sync does this.';


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
-- Name: draft_busco draft_busco_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_busco
    ADD CONSTRAINT draft_busco_pkey PRIMARY KEY (draft_id);


--
-- Name: draft_contamination draft_contamination_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_contamination
    ADD CONSTRAINT draft_contamination_pkey PRIMARY KEY (draft_id);


--
-- Name: draft_depthsizer draft_depthsizer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_depthsizer
    ADD CONSTRAINT draft_depthsizer_pkey PRIMARY KEY (draft_id);


--
-- Name: draft_fastp draft_fastp_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_fastp
    ADD CONSTRAINT draft_fastp_pkey PRIMARY KEY (draft_id);


--
-- Name: draft_genome draft_genome_natural_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_genome
    ADD CONSTRAINT draft_genome_natural_key UNIQUE (og_id, seq_date);


--
-- Name: draft_genome draft_genome_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_genome
    ADD CONSTRAINT draft_genome_pkey PRIMARY KEY (draft_id);


--
-- Name: draft_genome_run draft_genome_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_genome_run
    ADD CONSTRAINT draft_genome_run_pkey PRIMARY KEY (draft_id, sequencing_id);


--
-- Name: draft_genomescope draft_genomescope_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_genomescope
    ADD CONSTRAINT draft_genomescope_pkey PRIMARY KEY (draft_id);


--
-- Name: draft_gfastats draft_gfastats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_gfastats
    ADD CONSTRAINT draft_gfastats_pkey PRIMARY KEY (draft_id);


--
-- Name: draft_merqury draft_merqury_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_merqury
    ADD CONSTRAINT draft_merqury_pkey PRIMARY KEY (draft_id);


--
-- Name: draft_submission draft_submission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_submission
    ADD CONSTRAINT draft_submission_pkey PRIMARY KEY (draft_id);


--
-- Name: draft_tiara draft_tiara_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_tiara
    ADD CONSTRAINT draft_tiara_pkey PRIMARY KEY (draft_id);


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
-- Name: hic_read_qc hic_read_qc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_read_qc
    ADD CONSTRAINT hic_read_qc_pkey PRIMARY KEY (hic_qc_id);


--
-- Name: hifi_read_qc hifi_read_qc_natural_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hifi_read_qc
    ADD CONSTRAINT hifi_read_qc_natural_key UNIQUE (og_id, tissue, ext_type, lib_code, run_id);


--
-- Name: hifi_read_qc hifi_read_qc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hifi_read_qc
    ADD CONSTRAINT hifi_read_qc_pkey PRIMARY KEY (hifi_qc_id);


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
-- Name: mito_annotation_gene mito_annotation_gene_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_annotation_gene
    ADD CONSTRAINT mito_annotation_gene_pkey PRIMARY KEY (annotation_id, gene);


--
-- Name: mito_annotation mito_annotation_natural_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_annotation
    ADD CONSTRAINT mito_annotation_natural_key UNIQUE (assembly_id, annotation);


--
-- Name: mito_annotation mito_annotation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_annotation
    ADD CONSTRAINT mito_annotation_pkey PRIMARY KEY (annotation_id);


--
-- Name: mito_assembly_depth mito_assembly_depth_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly_depth
    ADD CONSTRAINT mito_assembly_depth_pkey PRIMARY KEY (assembly_id);


--
-- Name: mito_assembly mito_assembly_natural_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly
    ADD CONSTRAINT mito_assembly_natural_key UNIQUE (og_id, tech, seq_date, code);


--
-- Name: mito_assembly mito_assembly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly
    ADD CONSTRAINT mito_assembly_pkey PRIMARY KEY (assembly_id);


--
-- Name: mito_assembly_qc mito_assembly_qc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly_qc
    ADD CONSTRAINT mito_assembly_qc_pkey PRIMARY KEY (assembly_id);


--
-- Name: mito_assembly_run mito_assembly_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly_run
    ADD CONSTRAINT mito_assembly_run_pkey PRIMARY KEY (assembly_id, sequencing_id);


--
-- Name: mito_gene mito_gene_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_gene
    ADD CONSTRAINT mito_gene_pkey PRIMARY KEY (gene);


--
-- Name: mito_gene mito_gene_sort_order_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_gene
    ADD CONSTRAINT mito_gene_sort_order_key UNIQUE (sort_order);


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
-- Name: ref_assembly ref_assembly_natural_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly
    ADD CONSTRAINT ref_assembly_natural_key UNIQUE (og_id, seq_date, version);


--
-- Name: ref_assembly_part ref_assembly_part_natural_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly_part
    ADD CONSTRAINT ref_assembly_part_natural_key UNIQUE (assembly_id, stage, haplotype);


--
-- Name: ref_assembly_part ref_assembly_part_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly_part
    ADD CONSTRAINT ref_assembly_part_pkey PRIMARY KEY (part_id);


--
-- Name: ref_assembly ref_assembly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly
    ADD CONSTRAINT ref_assembly_pkey PRIMARY KEY (assembly_id);


--
-- Name: ref_assembly_run ref_assembly_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly_run
    ADD CONSTRAINT ref_assembly_run_pkey PRIMARY KEY (assembly_id, sequencing_id);


--
-- Name: ref_busco ref_busco_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_busco
    ADD CONSTRAINT ref_busco_pkey PRIMARY KEY (part_id);


--
-- Name: ref_chromosome_stats ref_chromosome_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_chromosome_stats
    ADD CONSTRAINT ref_chromosome_stats_pkey PRIMARY KEY (part_id);


--
-- Name: ref_genomescope ref_genomescope_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_genomescope
    ADD CONSTRAINT ref_genomescope_pkey PRIMARY KEY (read_set_id);


--
-- Name: ref_gfastats ref_gfastats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_gfastats
    ADD CONSTRAINT ref_gfastats_pkey PRIMARY KEY (part_id);


--
-- Name: ref_hifi_adapter_filter ref_hifi_adapter_filter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_hifi_adapter_filter
    ADD CONSTRAINT ref_hifi_adapter_filter_pkey PRIMARY KEY (read_set_id);


--
-- Name: ref_merqury_completeness ref_merqury_completeness_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_merqury_completeness
    ADD CONSTRAINT ref_merqury_completeness_pkey PRIMARY KEY (part_id);


--
-- Name: ref_merqury_qv ref_merqury_qv_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_merqury_qv
    ADD CONSTRAINT ref_merqury_qv_pkey PRIMARY KEY (part_id);


--
-- Name: ref_omnic ref_omnic_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_omnic
    ADD CONSTRAINT ref_omnic_pkey PRIMARY KEY (part_id);


--
-- Name: ref_read_set_external ref_read_set_external_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_read_set_external
    ADD CONSTRAINT ref_read_set_external_pkey PRIMARY KEY (read_set_id);


--
-- Name: ref_read_set ref_read_set_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_read_set
    ADD CONSTRAINT ref_read_set_pkey PRIMARY KEY (read_set_id);


--
-- Name: ref_read_set_run ref_read_set_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_read_set_run
    ADD CONSTRAINT ref_read_set_run_pkey PRIMARY KEY (read_set_id, sequencing_id);


--
-- Name: ref_seqkit_stats ref_seqkit_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_seqkit_stats
    ADD CONSTRAINT ref_seqkit_stats_pkey PRIMARY KEY (part_id);


--
-- Name: ref_sra_upload ref_sra_upload_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_sra_upload
    ADD CONSTRAINT ref_sra_upload_pkey PRIMARY KEY (srr_accession);


--
-- Name: ref_sra_upload_run ref_sra_upload_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_sra_upload_run
    ADD CONSTRAINT ref_sra_upload_run_pkey PRIMARY KEY (srr_accession, sequencing_id);


--
-- Name: ref_sra_upload_unlinked ref_sra_upload_unlinked_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_sra_upload_unlinked
    ADD CONSTRAINT ref_sra_upload_unlinked_pkey PRIMARY KEY (srr_accession);


--
-- Name: ref_stage ref_stage_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_stage
    ADD CONSTRAINT ref_stage_name_key UNIQUE (name);


--
-- Name: ref_stage ref_stage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_stage
    ADD CONSTRAINT ref_stage_pkey PRIMARY KEY (stage);


--
-- Name: ref_submission_haplotype ref_submission_haplotype_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_submission_haplotype
    ADD CONSTRAINT ref_submission_haplotype_pkey PRIMARY KEY (submission_id, haplotype);


--
-- Name: ref_submission ref_submission_og_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_submission
    ADD CONSTRAINT ref_submission_og_id_key UNIQUE (og_id);


--
-- Name: ref_submission ref_submission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_submission
    ADD CONSTRAINT ref_submission_pkey PRIMARY KEY (submission_id);


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
-- Name: sequencing_run sequencing_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sequencing_run
    ADD CONSTRAINT sequencing_run_pkey PRIMARY KEY (run_id);


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
-- Name: draft_genome_run_sequencing_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX draft_genome_run_sequencing_id_idx ON public.draft_genome_run USING btree (sequencing_id);


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
-- Name: hic_read_qc_natural_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hic_read_qc_natural_key ON public.hic_read_qc USING btree (og_id, COALESCE(tissue, ''::text), COALESCE(ext_type, ''::text), COALESCE(lib_code, ''::text), COALESCE(lane, ''::text), run_id);


--
-- Name: hic_read_qc_sequencing_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hic_read_qc_sequencing_id_idx ON public.hic_read_qc USING btree (sequencing_id);


--
-- Name: hifi_read_qc_sequencing_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hifi_read_qc_sequencing_id_idx ON public.hifi_read_qc USING btree (sequencing_id);


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
-- Name: mito_annotation_one_selected; Type: INDEX; Schema: public; Owner: -
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
-- Name: ref_assembly_run_sequencing_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ref_assembly_run_sequencing_id_idx ON public.ref_assembly_run USING btree (sequencing_id);


--
-- Name: ref_read_set_natural_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ref_read_set_natural_key ON public.ref_read_set USING btree (og_id, COALESCE(seq_date, ''::text));


--
-- Name: ref_read_set_run_sequencing_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ref_read_set_run_sequencing_id_idx ON public.ref_read_set_run USING btree (sequencing_id);


--
-- Name: ref_sra_upload_run_sequencing_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ref_sra_upload_run_sequencing_id_idx ON public.ref_sra_upload_run USING btree (sequencing_id);


--
-- Name: ref_sra_upload_submission_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ref_sra_upload_submission_id_idx ON public.ref_sra_upload USING btree (submission_id);


--
-- Name: ref_submission_assembly_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ref_submission_assembly_id_idx ON public.ref_submission USING btree (assembly_id);


--
-- Name: ref_submission_haplotype_part_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ref_submission_haplotype_part_idx ON public.ref_submission_haplotype USING btree (assembly_id, stage, haplotype);


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
-- Name: v_ref_assembly_status _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.v_ref_assembly_status AS
 SELECT a.og_num,
    a.og_id,
    a.seq_date,
    a.version,
    a.strategy,
    a.attempt,
    ( SELECT count(*) AS count
           FROM public.ref_assembly_run r
          WHERE (r.assembly_id = a.assembly_id)) AS run_links,
    count(p.part_id) AS parts,
    string_agg(DISTINCT (p.stage)::text, ','::text ORDER BY (p.stage)::text) AS stages,
    COALESCE(bool_or((p.stage = 3)), false) AS curated,
    string_agg(DISTINCT (
        CASE
            WHEN (gf.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text, ','::text ORDER BY (
        CASE
            WHEN (gf.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text) AS gfastats_stages,
    string_agg(DISTINCT (
        CASE
            WHEN (bu.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text, ','::text ORDER BY (
        CASE
            WHEN (bu.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text) AS busco_stages,
    string_agg(DISTINCT (
        CASE
            WHEN (mq.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text, ','::text ORDER BY (
        CASE
            WHEN (mq.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text) AS merqury_qv_stages,
    string_agg(DISTINCT (
        CASE
            WHEN (mc.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text, ','::text ORDER BY (
        CASE
            WHEN (mc.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text) AS merqury_completeness_stages,
    string_agg(DISTINCT (
        CASE
            WHEN (om.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text, ','::text ORDER BY (
        CASE
            WHEN (om.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text) AS omnic_stages,
    string_agg(DISTINCT (
        CASE
            WHEN (sk.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text, ','::text ORDER BY (
        CASE
            WHEN (sk.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text) AS seqkit_stats_stages,
    string_agg(DISTINCT (
        CASE
            WHEN (ch.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text, ','::text ORDER BY (
        CASE
            WHEN (ch.part_id IS NOT NULL) THEN p.stage
            ELSE NULL::integer
        END)::text) AS chromosome_stats_stages
   FROM ((((((((public.ref_assembly a
     JOIN public.ref_assembly_part p ON ((p.assembly_id = a.assembly_id)))
     LEFT JOIN public.ref_gfastats gf ON ((gf.part_id = p.part_id)))
     LEFT JOIN public.ref_busco bu ON ((bu.part_id = p.part_id)))
     LEFT JOIN public.ref_merqury_qv mq ON ((mq.part_id = p.part_id)))
     LEFT JOIN public.ref_merqury_completeness mc ON ((mc.part_id = p.part_id)))
     LEFT JOIN public.ref_omnic om ON ((om.part_id = p.part_id)))
     LEFT JOIN public.ref_seqkit_stats sk ON ((sk.part_id = p.part_id)))
     LEFT JOIN public.ref_chromosome_stats ch ON ((ch.part_id = p.part_id)))
  GROUP BY a.assembly_id;


--
-- Name: draft_genome_run draft_genome_run_illumina_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER draft_genome_run_illumina_only BEFORE INSERT OR UPDATE ON public.draft_genome_run FOR EACH ROW EXECUTE FUNCTION public.draft_genome_run_illumina_only();


--
-- Name: lca lca_content_hash; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER lca_content_hash BEFORE INSERT OR UPDATE ON public.lca FOR EACH ROW EXECUTE FUNCTION public.lca_set_content_hash();


--
-- Name: lca_raw_results lca_raw_results_content_hash; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER lca_raw_results_content_hash BEFORE INSERT OR UPDATE ON public.lca_raw_results FOR EACH ROW EXECUTE FUNCTION public.lca_set_content_hash();


--
-- Name: ref_assembly_run ref_assembly_run_genomic_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ref_assembly_run_genomic_only BEFORE INSERT OR UPDATE ON public.ref_assembly_run FOR EACH ROW EXECUTE FUNCTION public.ref_assembly_run_genomic_only();


--
-- Name: ref_read_set_external ref_read_set_external_no_runs; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ref_read_set_external_no_runs BEFORE INSERT OR UPDATE ON public.ref_read_set_external FOR EACH ROW EXECUTE FUNCTION public.ref_read_set_external_exclusive();


--
-- Name: ref_read_set_run ref_read_set_run_not_external; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ref_read_set_run_not_external BEFORE INSERT OR UPDATE ON public.ref_read_set_run FOR EACH ROW EXECUTE FUNCTION public.ref_read_set_external_exclusive();


--
-- Name: ref_read_set_run ref_read_set_run_pacbio_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ref_read_set_run_pacbio_only BEFORE INSERT OR UPDATE ON public.ref_read_set_run FOR EACH ROW EXECUTE FUNCTION public.ref_read_set_run_pacbio_only();


--
-- Name: ref_submission ref_submission_assembly_to_haplotypes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ref_submission_assembly_to_haplotypes AFTER UPDATE OF assembly_id ON public.ref_submission FOR EACH ROW WHEN ((old.assembly_id IS DISTINCT FROM new.assembly_id)) EXECUTE FUNCTION public.ref_submission_assembly_to_haplotypes();


--
-- Name: ref_submission_haplotype ref_submission_haplotype_assembly; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ref_submission_haplotype_assembly BEFORE INSERT OR UPDATE ON public.ref_submission_haplotype FOR EACH ROW EXECUTE FUNCTION public.ref_submission_haplotype_assembly();


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
-- Name: draft_busco draft_busco_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_busco
    ADD CONSTRAINT draft_busco_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


--
-- Name: draft_contamination draft_contamination_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_contamination
    ADD CONSTRAINT draft_contamination_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


--
-- Name: draft_depthsizer draft_depthsizer_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_depthsizer
    ADD CONSTRAINT draft_depthsizer_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


--
-- Name: draft_fastp draft_fastp_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_fastp
    ADD CONSTRAINT draft_fastp_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


--
-- Name: draft_genome draft_genome_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_genome
    ADD CONSTRAINT draft_genome_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: draft_genome_run draft_genome_run_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_genome_run
    ADD CONSTRAINT draft_genome_run_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


--
-- Name: draft_genome_run draft_genome_run_sequencing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_genome_run
    ADD CONSTRAINT draft_genome_run_sequencing_id_fkey FOREIGN KEY (sequencing_id) REFERENCES public.sequencing(sequencing_id) ON DELETE CASCADE;


--
-- Name: draft_genomescope draft_genomescope_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_genomescope
    ADD CONSTRAINT draft_genomescope_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


--
-- Name: draft_gfastats draft_gfastats_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_gfastats
    ADD CONSTRAINT draft_gfastats_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


--
-- Name: draft_merqury draft_merqury_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_merqury
    ADD CONSTRAINT draft_merqury_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


--
-- Name: draft_submission draft_submission_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_submission
    ADD CONSTRAINT draft_submission_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


--
-- Name: draft_tiara draft_tiara_draft_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.draft_tiara
    ADD CONSTRAINT draft_tiara_draft_id_fkey FOREIGN KEY (draft_id) REFERENCES public.draft_genome(draft_id) ON DELETE CASCADE;


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
-- Name: hic_read_qc hic_read_qc_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_read_qc
    ADD CONSTRAINT hic_read_qc_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: hic_read_qc hic_read_qc_sequencing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hic_read_qc
    ADD CONSTRAINT hic_read_qc_sequencing_id_fkey FOREIGN KEY (sequencing_id) REFERENCES public.sequencing(sequencing_id) ON DELETE SET NULL;


--
-- Name: hifi_read_qc hifi_read_qc_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hifi_read_qc
    ADD CONSTRAINT hifi_read_qc_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: hifi_read_qc hifi_read_qc_sequencing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hifi_read_qc
    ADD CONSTRAINT hifi_read_qc_sequencing_id_fkey FOREIGN KEY (sequencing_id) REFERENCES public.sequencing(sequencing_id) ON DELETE SET NULL;


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
-- Name: lca lca_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT lca_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: lca_raw_results lca_raw_results_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT lca_raw_results_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


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
-- Name: mito_annotation mito_annotation_assembly_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_annotation
    ADD CONSTRAINT mito_annotation_assembly_id_fkey FOREIGN KEY (assembly_id) REFERENCES public.mito_assembly(assembly_id) ON DELETE CASCADE;


--
-- Name: mito_annotation_gene mito_annotation_gene_annotation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_annotation_gene
    ADD CONSTRAINT mito_annotation_gene_annotation_id_fkey FOREIGN KEY (annotation_id) REFERENCES public.mito_annotation(annotation_id) ON DELETE CASCADE;


--
-- Name: mito_annotation_gene mito_annotation_gene_gene_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_annotation_gene
    ADD CONSTRAINT mito_annotation_gene_gene_fkey FOREIGN KEY (gene) REFERENCES public.mito_gene(gene);


--
-- Name: mito_assembly_depth mito_assembly_depth_assembly_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly_depth
    ADD CONSTRAINT mito_assembly_depth_assembly_id_fkey FOREIGN KEY (assembly_id) REFERENCES public.mito_assembly(assembly_id) ON DELETE CASCADE;


--
-- Name: mito_assembly mito_assembly_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly
    ADD CONSTRAINT mito_assembly_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: mito_assembly_qc mito_assembly_qc_assembly_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly_qc
    ADD CONSTRAINT mito_assembly_qc_assembly_id_fkey FOREIGN KEY (assembly_id) REFERENCES public.mito_assembly(assembly_id) ON DELETE CASCADE;


--
-- Name: mito_assembly_run mito_assembly_run_assembly_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly_run
    ADD CONSTRAINT mito_assembly_run_assembly_id_fkey FOREIGN KEY (assembly_id) REFERENCES public.mito_assembly(assembly_id) ON DELETE CASCADE;


--
-- Name: mito_assembly_run mito_assembly_run_sequencing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mito_assembly_run
    ADD CONSTRAINT mito_assembly_run_sequencing_id_fkey FOREIGN KEY (sequencing_id) REFERENCES public.sequencing(sequencing_id) ON DELETE CASCADE;


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
-- Name: ref_assembly ref_assembly_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly
    ADD CONSTRAINT ref_assembly_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: ref_assembly_part ref_assembly_part_assembly_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly_part
    ADD CONSTRAINT ref_assembly_part_assembly_id_fkey FOREIGN KEY (assembly_id) REFERENCES public.ref_assembly(assembly_id) ON DELETE CASCADE;


--
-- Name: ref_assembly_part ref_assembly_part_stage_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly_part
    ADD CONSTRAINT ref_assembly_part_stage_fkey FOREIGN KEY (stage) REFERENCES public.ref_stage(stage);


--
-- Name: ref_assembly_run ref_assembly_run_assembly_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly_run
    ADD CONSTRAINT ref_assembly_run_assembly_id_fkey FOREIGN KEY (assembly_id) REFERENCES public.ref_assembly(assembly_id) ON DELETE CASCADE;


--
-- Name: ref_assembly_run ref_assembly_run_sequencing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_assembly_run
    ADD CONSTRAINT ref_assembly_run_sequencing_id_fkey FOREIGN KEY (sequencing_id) REFERENCES public.sequencing(sequencing_id) ON DELETE CASCADE;


--
-- Name: ref_busco ref_busco_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_busco
    ADD CONSTRAINT ref_busco_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.ref_assembly_part(part_id) ON DELETE CASCADE;


--
-- Name: ref_chromosome_stats ref_chromosome_stats_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_chromosome_stats
    ADD CONSTRAINT ref_chromosome_stats_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.ref_assembly_part(part_id) ON DELETE CASCADE;


--
-- Name: ref_genomescope ref_genomescope_read_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_genomescope
    ADD CONSTRAINT ref_genomescope_read_set_id_fkey FOREIGN KEY (read_set_id) REFERENCES public.ref_read_set(read_set_id) ON DELETE CASCADE;


--
-- Name: ref_gfastats ref_gfastats_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_gfastats
    ADD CONSTRAINT ref_gfastats_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.ref_assembly_part(part_id) ON DELETE CASCADE;


--
-- Name: ref_hifi_adapter_filter ref_hifi_adapter_filter_read_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_hifi_adapter_filter
    ADD CONSTRAINT ref_hifi_adapter_filter_read_set_id_fkey FOREIGN KEY (read_set_id) REFERENCES public.ref_read_set(read_set_id) ON DELETE CASCADE;


--
-- Name: ref_merqury_completeness ref_merqury_completeness_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_merqury_completeness
    ADD CONSTRAINT ref_merqury_completeness_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.ref_assembly_part(part_id) ON DELETE CASCADE;


--
-- Name: ref_merqury_qv ref_merqury_qv_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_merqury_qv
    ADD CONSTRAINT ref_merqury_qv_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.ref_assembly_part(part_id) ON DELETE CASCADE;


--
-- Name: ref_omnic ref_omnic_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_omnic
    ADD CONSTRAINT ref_omnic_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.ref_assembly_part(part_id) ON DELETE CASCADE;


--
-- Name: ref_read_set_external ref_read_set_external_read_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_read_set_external
    ADD CONSTRAINT ref_read_set_external_read_set_id_fkey FOREIGN KEY (read_set_id) REFERENCES public.ref_read_set(read_set_id) ON DELETE CASCADE;


--
-- Name: ref_read_set ref_read_set_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_read_set
    ADD CONSTRAINT ref_read_set_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: ref_read_set_run ref_read_set_run_read_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_read_set_run
    ADD CONSTRAINT ref_read_set_run_read_set_id_fkey FOREIGN KEY (read_set_id) REFERENCES public.ref_read_set(read_set_id) ON DELETE CASCADE;


--
-- Name: ref_read_set_run ref_read_set_run_sequencing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_read_set_run
    ADD CONSTRAINT ref_read_set_run_sequencing_id_fkey FOREIGN KEY (sequencing_id) REFERENCES public.sequencing(sequencing_id) ON DELETE CASCADE;


--
-- Name: ref_seqkit_stats ref_seqkit_stats_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_seqkit_stats
    ADD CONSTRAINT ref_seqkit_stats_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.ref_assembly_part(part_id) ON DELETE CASCADE;


--
-- Name: ref_sra_upload_run ref_sra_upload_run_sequencing_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_sra_upload_run
    ADD CONSTRAINT ref_sra_upload_run_sequencing_id_fkey FOREIGN KEY (sequencing_id) REFERENCES public.sequencing(sequencing_id) ON DELETE CASCADE;


--
-- Name: ref_sra_upload_run ref_sra_upload_run_srr_accession_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_sra_upload_run
    ADD CONSTRAINT ref_sra_upload_run_srr_accession_fkey FOREIGN KEY (srr_accession) REFERENCES public.ref_sra_upload(srr_accession) ON DELETE CASCADE;


--
-- Name: ref_sra_upload ref_sra_upload_submission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_sra_upload
    ADD CONSTRAINT ref_sra_upload_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES public.ref_submission(submission_id);


--
-- Name: ref_sra_upload_unlinked ref_sra_upload_unlinked_srr_accession_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_sra_upload_unlinked
    ADD CONSTRAINT ref_sra_upload_unlinked_srr_accession_fkey FOREIGN KEY (srr_accession) REFERENCES public.ref_sra_upload(srr_accession) ON DELETE CASCADE;


--
-- Name: ref_submission ref_submission_assembly_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_submission
    ADD CONSTRAINT ref_submission_assembly_id_fkey FOREIGN KEY (assembly_id) REFERENCES public.ref_assembly(assembly_id) ON DELETE SET NULL;


--
-- Name: ref_submission_haplotype ref_submission_haplotype_part_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_submission_haplotype
    ADD CONSTRAINT ref_submission_haplotype_part_fkey FOREIGN KEY (assembly_id, stage, haplotype) REFERENCES public.ref_assembly_part(assembly_id, stage, haplotype) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ref_submission_haplotype ref_submission_haplotype_submission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_submission_haplotype
    ADD CONSTRAINT ref_submission_haplotype_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES public.ref_submission(submission_id) ON DELETE CASCADE;


--
-- Name: ref_submission ref_submission_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_submission
    ADD CONSTRAINT ref_submission_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


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

\unrestrict o92hsMyMKXkBS6pxj3IRvzvOTkP1QSatRtpbuR1Ho4NypNdrOi9M8XudYJ5MzPT

