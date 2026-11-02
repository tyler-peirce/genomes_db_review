-- Revert 073_rg6_swap_v4_into_public.sql: put v4 back beside public, exactly as before the swap.
--
-- Recreates v4 (comment, grants, default privileges), moves the 23 tables, 14 views and 6 functions
-- back into it, moves the archived tables and views back (the six old tables and two views to
-- public, ref_key_map and ref_excluded_rows to v4), restores the original function bodies and
-- comments, rebuilds R.6's run-FK readiness view on the old tables, and recreates what 073 dropped:
-- the seven sync_* source views and the six sync_ref_* / check_ref_* functions. Definitions
-- captured from live on 2026-11-02 by gen_073.py. Rehearsal proves the result schema-identical.
--
-- DATA WRITTEN AFTER THE SWAP. Between 073 and this revert, writers wrote only the new tables, so
-- the old tables coming back lack those writes. Do NOT re-add the 19:00 UTC sync_v4.sh cron line
-- until those pushes have been re-run with the old writers into public: the sync copies
-- public -> v4 and would overwrite the newer v4 rows. The final notice lists the differences.
--
-- Opt-in:  PGOPTIONS="-c oceanomics.rg6_revert=yes" psql -f sql/revert/073_rg6_swap_v4_into_public_revert.sql
-- then delete 073's ledger row.

BEGIN;

DO $rv$
BEGIN
  IF coalesce(current_setting('oceanomics.rg6_revert', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'Reverting RG.6 puts the old tables back in public. Run with PGOPTIONS="-c oceanomics.rg6_revert=yes"';
  END IF;
  IF to_regnamespace('v4') IS NOT NULL OR to_regnamespace('pre_v4_archive') IS NULL THEN
    RAISE EXCEPTION 'v4 exists or pre_v4_archive is missing: 073 is not applied, or was already reverted';
  END IF;
END
$rv$;

SET LOCAL search_path = public, pg_temp;

CREATE SCHEMA v4;
COMMENT ON SCHEMA v4 IS 'Phase RG: the reference-genome design, built beside public and kept in sync with it until the RG.6 swap. Nothing in public depends on it. docs/ref_genomes_runbook_rg0_rg5.md';
GRANT USAGE ON SCHEMA v4 TO readonly, oceangenom_web;
ALTER DEFAULT PRIVILEGES IN SCHEMA v4 GRANT SELECT ON TABLES TO readonly;

ALTER TABLE public.hic_read_qc SET SCHEMA v4;
ALTER TABLE public.hifi_read_qc SET SCHEMA v4;
ALTER TABLE public.ref_assembly SET SCHEMA v4;
ALTER TABLE public.ref_assembly_part SET SCHEMA v4;
ALTER TABLE public.ref_assembly_run SET SCHEMA v4;
ALTER TABLE public.ref_busco SET SCHEMA v4;
ALTER TABLE public.ref_chromosome_stats SET SCHEMA v4;
ALTER TABLE public.ref_genomescope SET SCHEMA v4;
ALTER TABLE public.ref_gfastats SET SCHEMA v4;
ALTER TABLE public.ref_hifi_adapter_filter SET SCHEMA v4;
ALTER TABLE public.ref_merqury_completeness SET SCHEMA v4;
ALTER TABLE public.ref_merqury_qv SET SCHEMA v4;
ALTER TABLE public.ref_omnic SET SCHEMA v4;
ALTER TABLE public.ref_read_set SET SCHEMA v4;
ALTER TABLE public.ref_read_set_external SET SCHEMA v4;
ALTER TABLE public.ref_read_set_run SET SCHEMA v4;
ALTER TABLE public.ref_seqkit_stats SET SCHEMA v4;
ALTER TABLE public.ref_sra_upload SET SCHEMA v4;
ALTER TABLE public.ref_sra_upload_run SET SCHEMA v4;
ALTER TABLE public.ref_sra_upload_unlinked SET SCHEMA v4;
ALTER TABLE public.ref_stage SET SCHEMA v4;
ALTER TABLE public.ref_submission SET SCHEMA v4;
ALTER TABLE public.ref_submission_haplotype SET SCHEMA v4;
ALTER VIEW public.coverage_summary SET SCHEMA v4;
ALTER VIEW public.goat_species_v1 SET SCHEMA v4;
ALTER VIEW public.hic_reads_qc SET SCHEMA v4;
ALTER VIEW public.hifi_reads_qc SET SCHEMA v4;
ALTER VIEW public.raw_qc SET SCHEMA v4;
ALTER VIEW public.ref_genomes SET SCHEMA v4;
ALTER VIEW public.ref_genomes_assembly_uploads SET SCHEMA v4;
ALTER VIEW public.ref_genomes_sra_uploads SET SCHEMA v4;
ALTER VIEW public.v_read_qc_sequencing_readiness SET SCHEMA v4;
ALTER VIEW public.v_read_set_run_readiness SET SCHEMA v4;
ALTER VIEW public.v_ref_assembly_run_readiness SET SCHEMA v4;
ALTER VIEW public.v_ref_assembly_status SET SCHEMA v4;
ALTER VIEW public.v_ref_assembly_summary SET SCHEMA v4;
ALTER VIEW public.v_sra_upload_run_readiness SET SCHEMA v4;
ALTER FUNCTION public.ref_assembly_run_genomic_only() SET SCHEMA v4;
ALTER FUNCTION public.ref_read_set_external_exclusive() SET SCHEMA v4;
ALTER FUNCTION public.ref_read_set_run_pacbio_only() SET SCHEMA v4;
ALTER FUNCTION public.ref_submission_assembly_to_haplotypes() SET SCHEMA v4;
ALTER FUNCTION public.ref_submission_haplotype_assembly() SET SCHEMA v4;
ALTER FUNCTION public.resolve_sra_upload_runs(text, text, text) SET SCHEMA v4;
ALTER TABLE pre_v4_archive.ref_excluded_rows SET SCHEMA v4;
ALTER TABLE pre_v4_archive.ref_key_map SET SCHEMA v4;
ALTER TABLE pre_v4_archive.hic_reads_qc SET SCHEMA public;
ALTER TABLE pre_v4_archive.hifi_reads_qc SET SCHEMA public;
ALTER TABLE pre_v4_archive.raw_qc SET SCHEMA public;
ALTER TABLE pre_v4_archive.ref_genomes SET SCHEMA public;
ALTER TABLE pre_v4_archive.ref_genomes_assembly_uploads SET SCHEMA public;
ALTER TABLE pre_v4_archive.ref_genomes_sra_uploads SET SCHEMA public;
ALTER VIEW pre_v4_archive.coverage_summary SET SCHEMA public;
ALTER VIEW pre_v4_archive.goat_species_v1 SET SCHEMA public;
DROP SCHEMA pre_v4_archive RESTRICT;

COMMENT ON TABLE public.hic_reads_qc IS NULL;
COMMENT ON TABLE public.hifi_reads_qc IS NULL;
COMMENT ON TABLE public.raw_qc IS NULL;
COMMENT ON TABLE public.ref_genomes IS NULL;
COMMENT ON TABLE public.ref_genomes_assembly_uploads IS NULL;
COMMENT ON TABLE public.ref_genomes_sra_uploads IS NULL;
COMMENT ON TABLE v4.ref_excluded_rows IS 'public rows that v4 does not carry; NULL columns match anything. Window-only: RG.6 archives the rows. Rows are added only through docs/ref_genomes_rg0_record.md.';
COMMENT ON TABLE v4.ref_key_map IS 'public assembly keys that v4 carries under a corrected key. Window-only: RG.6 rewrites the public rows or archives them. Rows are added only through docs/ref_genomes_rg0_record.md.';
COMMENT ON VIEW public.coverage_summary IS NULL;
COMMENT ON VIEW public.goat_species_v1 IS 'GoaT species submission view. Differs from the public version only in reading pacbio status from v2.summary rather than sample.pb_status, which F5 removed. See docs/v2_cutover_dependencies.md.';

-- Original function bodies.
CREATE OR REPLACE FUNCTION v4.ref_read_set_external_exclusive()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'ref_read_set_run' THEN
    IF EXISTS (SELECT 1 FROM v4.ref_read_set_external x WHERE x.read_set_id = NEW.read_set_id) THEN
      RAISE EXCEPTION 'ref_read_set_run: read set % is external (ref_read_set_external); it has no sequencing rows',
        NEW.read_set_id;
    END IF;
  ELSIF EXISTS (SELECT 1 FROM v4.ref_read_set_run r WHERE r.read_set_id = NEW.read_set_id) THEN
    RAISE EXCEPTION 'ref_read_set_external: read set % has sequencing rows (ref_read_set_run); it is not external',
      NEW.read_set_id;
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION v4.ref_submission_assembly_to_haplotypes()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  UPDATE v4.ref_submission_haplotype h SET assembly_id = NEW.assembly_id
  WHERE h.submission_id = NEW.submission_id AND h.assembly_id IS DISTINCT FROM NEW.assembly_id;
  RETURN NULL;
END
$function$;

CREATE OR REPLACE FUNCTION v4.ref_submission_haplotype_assembly()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  SELECT s.assembly_id INTO NEW.assembly_id FROM v4.ref_submission s WHERE s.submission_id = NEW.submission_id;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION v4.resolve_sra_upload_runs(p_og_id text, p_data_type text, p_filenames text)
 RETURNS SETOF text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'v4', 'public', 'pg_temp'
AS $function$
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
$function$;

COMMENT ON VIEW v4.coverage_summary IS 'public.coverage_summary on the v4 compatibility views. For the RG.5 reader test; replaces the public view at RG.6.';
COMMENT ON VIEW v4.goat_species_v1 IS 'public.goat_species_v1 with its in_assembly test on v4.ref_assembly. For the RG.5 reader test; replaces the public view at RG.6.';
COMMENT ON TABLE v4.hic_read_qc IS 'Illumina run statistics for Hi-C libraries, per library per run per lane. Writer: another repo, not yet identified (RG.0 §3). sequencing_id: the one Hi-C sequencing row of this OG and tissue on this run, NULL where none or several match (v_read_qc_sequencing_readiness).';
COMMENT ON VIEW v4.v_read_qc_sequencing_readiness IS 'Read-QC rows with no sequencing link, and why. Lab fixes or explicit links from RG.4 writers.';
COMMENT ON VIEW v4.v_ref_assembly_run_readiness IS 'Assemblies with no run link, and the OG''s PacBio/ONT DNA rows to choose from. Their seq_date matches no run date (RG.0 §1.5); writers link explicitly from RG.4.';
COMMENT ON VIEW v4.v_sra_upload_run_readiness IS 'SRA uploads with no sequencing link, and why. Most are run IDs the workbook has wrong (064''s header); fix at source, delete the ref_sra_upload_unlinked row, and the sync links them.';
COMMENT ON FUNCTION v4.resolve_sra_upload_runs(text, text, text) IS 'The sequencing rows an SRA upload''s file names point to (064''s forward rule; HICL1 = HICL, 065; failed runs skipped, 069). Used by the v4 sync and by ENA-ref-genomes step 09. Re-point search_path to public at RG.6.';
COMMENT ON FUNCTION v4.ref_read_set_external_exclusive() IS 'A read set is either external or linked to sequencing rows, not both (071). Outlives RG.6.';

CREATE OR REPLACE VIEW public.v_sequencing_run_fk_readiness AS  SELECT 'sequencing'::text AS child,
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
 SELECT 'hifi_reads_qc'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_run_ids
   FROM (public.hifi_reads_qc c
     LEFT JOIN public.sequencing_run r ON ((r.run_id = c.run_id)))
UNION ALL
 SELECT 'hic_reads_qc'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE ((c.run_id IS NOT NULL) AND (r.run_id IS NULL))) AS failing_run_ids
   FROM (public.hic_reads_qc c
     LEFT JOIN public.sequencing_run r ON ((r.run_id = c.run_id)));
COMMENT ON VIEW public.v_sequencing_run_fk_readiness IS 'For each table R.7 will FK to sequencing_run: rows that would fail today, and their run IDs.';

-- The window-only views and functions.
CREATE VIEW v4.sync_raw_qc_source AS  SELECT r.og_id,
    r.homozygosity,
    r.heterozygosity,
    r.genomesize,
    r.repeatsize,
    r.uniquesize,
    r.modelfit,
    r.errorrate,
    r.contam_reads,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM public.sample s
              WHERE (s.og_id = r.og_id)))) THEN 'og_id not in sample'::text
            ELSE NULL::text
        END AS key_problem
   FROM public.raw_qc r
  WHERE (NOT (EXISTS ( SELECT 1
           FROM v4.ref_excluded_rows x
          WHERE ((x.source_table = 'raw_qc'::text) AND (x.og_id = r.og_id)))));
COMMENT ON VIEW v4.sync_raw_qc_source IS 'Phase RG window only: public.raw_qc after ref_excluded_rows. Dropped at RG.6.';
CREATE VIEW v4.sync_read_qc_hic_source AS  SELECT h.og_id,
    NULLIF(h.tissue, ''::text) AS tissue,
    NULLIF(h.ext_type, ''::text) AS ext_type,
    NULLIF(h.lib_code, ''::text) AS lib_code,
    NULLIF(h.lane, ''::text) AS lane,
    h.run_id,
    h.datecreated,
    h.isarchived,
    h.isfiledeleted,
    h.totalreadspf,
    h.totalclusterspf,
    h.read1length,
    h.read2length,
    h.ispairedend,
    h.yield_gb,
    h.totalsize_gb,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM public.sample s
              WHERE (s.og_id = h.og_id)))) THEN 'og_id not in sample'::text
            WHEN (h.run_id = ''::text) THEN 'blank run_id'::text
            ELSE NULL::text
        END AS key_problem,
    ( SELECT
                CASE
                    WHEN (count(*) = 1) THEN min(s.sequencing_id)
                    ELSE NULL::text
                END AS "case"
           FROM public.v_sequencing_browse s
          WHERE ((s.og_id = h.og_id) AND (s.run_id = h.run_id) AND (s.technology = 'Hi-C'::text) AND (s.tissue_id ~~ ((h.og_id || h.tissue) || '%'::text)))) AS resolved_sequencing_id
   FROM public.hic_reads_qc h
  WHERE (NOT (EXISTS ( SELECT 1
           FROM v4.ref_excluded_rows x
          WHERE ((x.source_table = 'hic_reads_qc'::text) AND (x.og_id = h.og_id)))));
COMMENT ON VIEW v4.sync_read_qc_hic_source IS 'Phase RG window only: public.hic_reads_qc as the sync reads it, blanks as NULL. Dropped at RG.6.';
CREATE VIEW v4.sync_read_qc_hifi_source AS  SELECT h.og_id,
    h.tissue,
    h.ext_type,
    h.lib_code,
    h.run_id,
    h.barcode,
    h.barcode_quality,
    h.hifi_reads,
    h.hifi_read_length,
    h.hifi_read_quality,
    h.hifi_yield,
    h.polymerase_read_length,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM public.sample s
              WHERE (s.og_id = h.og_id)))) THEN 'og_id not in sample'::text
            WHEN ((((''::text = h.tissue) OR (''::text = h.ext_type)) OR (''::text = h.lib_code)) OR (''::text = h.run_id)) THEN 'blank key part'::text
            ELSE NULL::text
        END AS key_problem,
    ( SELECT
                CASE
                    WHEN (count(*) = 1) THEN min(s.sequencing_id)
                    ELSE NULL::text
                END AS "case"
           FROM public.sequencing s
          WHERE ((s.library_tube_id = (((((h.og_id || h.tissue) || '_'::text) || h.ext_type) || '_'::text) || h.lib_code)) AND (s.run_id = h.run_id))) AS resolved_sequencing_id
   FROM public.hifi_reads_qc h
  WHERE (NOT (EXISTS ( SELECT 1
           FROM v4.ref_excluded_rows x
          WHERE ((x.source_table = 'hifi_reads_qc'::text) AND (x.og_id = h.og_id)))));
COMMENT ON VIEW v4.sync_read_qc_hifi_source IS 'Phase RG window only: public.hifi_reads_qc as the sync reads it. Dropped at RG.6.';
CREATE VIEW v4.sync_ref_genomes_source AS  SELECT COALESCE(m.to_og_id, r.og_id) AS og_id,
    COALESCE(m.to_seq_date, r.seq_date) AS seq_date,
    r.stage,
    r.haplotype,
    COALESCE(m.to_version, r.version) AS version,
    r.num_contigs,
    r.contig_n50,
    r.contig_n50_size_mb,
    r.num_scaffolds,
    r.scaffold_n50,
    r.scaffold_n50_size_mb,
    r.largest_scaffold,
    r.largest_scaffold_size_mb,
    r.total_scaffold_length,
    r.total_scaffold_length_size_mb,
    r.gc_content_percent,
    r.dataset,
    r.complete,
    r.single_copy,
    r.multi_copy,
    r.fragmented,
    r.missing,
    r.n_markers,
    r.internal_stop_codon_percent,
    r.scaffold_n50_bus,
    r.contigs_n50_bus,
    r.percent_gaps,
    r.number_of_scaffolds,
    r.unique_k_mers_assembly,
    r.k_mers_total,
    r.qv,
    r.error,
    r.k_mer_set,
    r.solid_k_mers,
    r.total_k_mers,
    r.completeness,
    r.total,
    r.total_unmapped,
    r.total_single_sided_mapped,
    r.total_mapped,
    r.total_dups,
    r.total_nodups,
    r.cis,
    r.trans,
    r.hap2_chr_level_max_len,
    r.format,
    r.type,
    r.num_seqs,
    r.sum_len,
    r.min_len,
    r.avg_len,
    r.max_len,
    r.num_chromosomes,
    r.pct_assigned,
    r.pct_no_super,
    r.num_seq_no_super,
    r.max_len_no_super,
    r.num_gaps,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM public.sample s
              WHERE (s.og_id = COALESCE(m.to_og_id, r.og_id))))) THEN 'og_id not in sample'::text
            WHEN (COALESCE(m.to_seq_date, r.seq_date) !~ '^[0-9]{6}$'::text) THEN 'seq_date not YYMMDD'::text
            WHEN (COALESCE(m.to_version, r.version) !~ '^(hic|hifi|ont)[0-9]+$'::text) THEN 'version not hicN/hifiN/ontN'::text
            WHEN (r.haplotype <> ALL (ARRAY['hap1'::text, 'hap2'::text, 'dual'::text, 'p_ctg'::text, 'a_ctg'::text])) THEN 'unknown haplotype'::text
            WHEN (NOT (EXISTS ( SELECT 1
               FROM v4.ref_stage st
              WHERE (st.stage = r.stage)))) THEN 'unknown stage'::text
            WHEN (num_nonnulls(r.k_mer_set, r.hap2_chr_level_max_len) > 0) THEN 'value in a column v4 does not carry'::text
            ELSE NULL::text
        END AS key_problem,
    (num_nonnulls(r.num_contigs, r.contig_n50, r.contig_n50_size_mb, r.num_scaffolds, r.scaffold_n50, r.scaffold_n50_size_mb, r.largest_scaffold, r.largest_scaffold_size_mb, r.total_scaffold_length, r.total_scaffold_length_size_mb, r.gc_content_percent, r.dataset, r.complete, r.single_copy, r.multi_copy, r.fragmented, r.missing, r.n_markers, r.internal_stop_codon_percent, r.scaffold_n50_bus, r.contigs_n50_bus, r.percent_gaps, r.number_of_scaffolds, r.unique_k_mers_assembly, r.k_mers_total, r.qv, r.error, r.k_mer_set, r.solid_k_mers, r.total_k_mers, r.completeness, r.total, r.total_unmapped, r.total_single_sided_mapped, r.total_mapped, r.total_dups, r.total_nodups, r.cis, r.trans, r.hap2_chr_level_max_len, r.format, r.type, r.num_seqs, r.sum_len, r.min_len, r.avg_len, r.max_len, r.num_chromosomes, r.pct_assigned, r.pct_no_super, r.num_seq_no_super, r.max_len_no_super, r.num_gaps) = 0) AS is_empty,
    (m.from_og_id IS NOT NULL) AS is_remapped
   FROM (public.ref_genomes r
     LEFT JOIN v4.ref_key_map m ON (((m.from_og_id = r.og_id) AND (m.from_seq_date = r.seq_date) AND (m.from_version = r.version))))
  WHERE (NOT (EXISTS ( SELECT 1
           FROM v4.ref_excluded_rows x
          WHERE ((x.source_table = 'ref_genomes'::text) AND (x.og_id = r.og_id) AND ((x.seq_date IS NULL) OR (x.seq_date = r.seq_date)) AND ((x.version IS NULL) OR (x.version = r.version)) AND ((x.stage IS NULL) OR (x.stage = r.stage)) AND ((x.haplotype IS NULL) OR (x.haplotype = r.haplotype))))));
COMMENT ON VIEW v4.sync_ref_genomes_source IS 'Phase RG window only: public.ref_genomes after ref_excluded_rows and ref_key_map, with a key_problem verdict. What the sync copies and the check compares against. Dropped at RG.6.';
CREATE VIEW v4.sync_ref_submission_source AS  SELECT u.og_id,
    u.biosample,
    u.bioproject_umbrella,
    u.bioproject_hap1,
    u.bioproject_hap2,
    u.bioproject_rawdata,
    u.assembly_accession_hap1,
    u.assembly_accession_hap2,
    u.embargo_status,
    u.gca_accession_hap1,
    u.gca_accession_hap2,
        CASE
            WHEN (NOT (EXISTS ( SELECT 1
               FROM public.sample s
              WHERE (s.og_id = u.og_id)))) THEN 'og_id not in sample'::text
            WHEN ((u.embargo_status IS NULL) OR (u.embargo_status <> ALL (ARRAY['Release'::text, 'Embargo'::text]))) THEN 'embargo_status not Release/Embargo'::text
            ELSE NULL::text
        END AS key_problem
   FROM public.ref_genomes_assembly_uploads u
  WHERE (NOT (EXISTS ( SELECT 1
           FROM v4.ref_excluded_rows x
          WHERE ((x.source_table = 'ref_genomes_assembly_uploads'::text) AND (x.og_id = u.og_id)))));
COMMENT ON VIEW v4.sync_ref_submission_source IS 'Phase RG window only: public.ref_genomes_assembly_uploads as the sync reads it. Dropped at RG.6.';
CREATE VIEW v4.sync_read_set_source AS  SELECT s.og_id,
    s.homozygosity,
    s.heterozygosity,
    s.genomesize,
    s.repeatsize,
    s.uniquesize,
    s.modelfit,
    s.errorrate,
    s.contam_reads,
    (num_nonnulls(s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate) > 0) AS has_gs,
    (s.contam_reads IS NOT NULL) AS has_af,
    COALESCE(( SELECT ((NOT (((((((g.homozygosity IS DISTINCT FROM s.homozygosity) OR (g.heterozygosity IS DISTINCT FROM s.heterozygosity)) OR (g.genomesize IS DISTINCT FROM s.genomesize)) OR (g.repeatsize IS DISTINCT FROM s.repeatsize)) OR (g.uniquesize IS DISTINCT FROM s.uniquesize)) OR (g.modelfit IS DISTINCT FROM s.modelfit)) OR (g.errorrate IS DISTINCT FROM s.errorrate))) AND (NOT (f.contam_reads IS DISTINCT FROM s.contam_reads)))
           FROM ((( SELECT r.read_set_id
                   FROM v4.ref_read_set r
                  WHERE ((r.og_id = s.og_id) AND (r.seq_date IS NOT NULL))
                  ORDER BY r.seq_date DESC
                 LIMIT 1) d
             LEFT JOIN v4.ref_genomescope g ON ((g.read_set_id = d.read_set_id)))
             LEFT JOIN v4.ref_hifi_adapter_filter f ON ((f.read_set_id = d.read_set_id)))), false) AS matches_dated
   FROM v4.sync_raw_qc_source s
  WHERE ((s.key_problem IS NULL) AND (num_nonnulls(s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate, s.contam_reads) > 0));
COMMENT ON VIEW v4.sync_read_set_source IS 'Phase RG window only: public.raw_qc as the sync reads it, and whether it equals the OG''s latest dated read set. Dropped at RG.6.';
CREATE VIEW v4.sync_ref_sra_source AS  SELECT s.srr_accession,
    s.og_id,
    s.filenames,
    s.data_type,
    s.ncbi_status,
        CASE
            WHEN (s.ncbi_status = ANY (ARRAY['Released'::text, 'ToBeReleased'::text])) THEN s.ncbi_status
            ELSE NULL::text
        END AS status_value,
        CASE
            WHEN (s.ncbi_status ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'::text) THEN (s.ncbi_status)::date
            ELSE NULL::date
        END AS release_date,
        CASE
            WHEN ((s.og_id IS NULL) OR (NOT (EXISTS ( SELECT 1
               FROM v4.sync_ref_submission_source u
              WHERE ((u.og_id = s.og_id) AND (u.key_problem IS NULL)))))) THEN 'og_id has no carried submission'::text
            WHEN ((s.data_type IS NOT NULL) AND (s.data_type <> ALL (ARRAY['hifi'::text, 'hic'::text, 'ont'::text, 'illumina'::text]))) THEN 'unknown data_type'::text
            WHEN ((s.ncbi_status IS NOT NULL) AND (s.ncbi_status <> ALL (ARRAY['Released'::text, 'ToBeReleased'::text])) AND (s.ncbi_status !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'::text)) THEN 'ncbi_status neither a status nor an ISO date'::text
            ELSE NULL::text
        END AS key_problem
   FROM public.ref_genomes_sra_uploads s
  WHERE (NOT (EXISTS ( SELECT 1
           FROM v4.ref_excluded_rows x
          WHERE ((x.source_table = 'ref_genomes_sra_uploads'::text) AND (x.og_id = s.og_id)))));
COMMENT ON VIEW v4.sync_ref_sra_source IS 'Phase RG window only: public.ref_genomes_sra_uploads as the sync reads it, status split. Dropped at RG.6.';

CREATE OR REPLACE FUNCTION v4.check_ref_assembly()
 RETURNS TABLE(check_name text, problems bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  check_name := 'ref_genomes: v4 rows not in public (after triage)';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, seq_date, stage, haplotype, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans, hap2_chr_level_max_len, format, "type", num_seqs, sum_len, min_len, avg_len, max_len, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super, version, num_gaps FROM v4.ref_genomes
    EXCEPT ALL
    SELECT og_id, seq_date, stage, haplotype, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans, hap2_chr_level_max_len, format, "type", num_seqs, sum_len, min_len, avg_len, max_len, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super, version, num_gaps FROM v4.sync_ref_genomes_source WHERE key_problem IS NULL AND NOT is_empty) x;
  RETURN NEXT;

  check_name := 'ref_genomes: public rows not in v4 (after triage)';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, seq_date, stage, haplotype, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans, hap2_chr_level_max_len, format, "type", num_seqs, sum_len, min_len, avg_len, max_len, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super, version, num_gaps FROM v4.sync_ref_genomes_source WHERE key_problem IS NULL AND NOT is_empty
    EXCEPT ALL
    SELECT og_id, seq_date, stage, haplotype, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans, hap2_chr_level_max_len, format, "type", num_seqs, sum_len, min_len, avg_len, max_len, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super, version, num_gaps FROM v4.ref_genomes) x;
  RETURN NEXT;

  check_name := 'ref_genomes: public rows with an untriaged key problem';
  SELECT count(*) INTO problems FROM v4.sync_ref_genomes_source WHERE key_problem IS NOT NULL;
  RETURN NEXT;

  check_name := 'goat_species_v1: in_assembly species differ';
  SELECT (SELECT count(*) FROM (SELECT samp.nominal_species_id FROM public.sample samp JOIN public.ref_genomes rg ON rg.og_id = samp.og_id
                                EXCEPT SELECT samp.nominal_species_id FROM public.sample samp JOIN v4.ref_assembly rg ON rg.og_id = samp.og_id) x)
       + (SELECT count(*) FROM (SELECT samp.nominal_species_id FROM public.sample samp JOIN v4.ref_assembly rg ON rg.og_id = samp.og_id
                                EXCEPT SELECT samp.nominal_species_id FROM public.sample samp JOIN public.ref_genomes rg ON rg.og_id = samp.og_id) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'parts with no tool row';
  SELECT count(*) INTO problems FROM v4.ref_assembly_part p
  WHERE NOT (EXISTS (SELECT 1 FROM v4.ref_gfastats x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_busco x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_merqury_qv x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_merqury_completeness x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_omnic x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_seqkit_stats x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_chromosome_stats x WHERE x.part_id = p.part_id));
  RETURN NEXT;

  check_name := 'note: public rows with no value (not carried)';
  SELECT count(*) INTO problems FROM v4.sync_ref_genomes_source WHERE key_problem IS NULL AND is_empty;
  RETURN NEXT;

  check_name := 'note: assemblies with no run link';
  SELECT count(*) INTO problems FROM v4.v_ref_assembly_run_readiness;
  RETURN NEXT;
END
$function$;
COMMENT ON FUNCTION v4.check_ref_assembly() IS 'Phase RG window only: v4 assembly tables against public.ref_genomes after triage, by key and value. Every problems value must be 0 except checks named note:. Dropped at RG.6.';

CREATE OR REPLACE FUNCTION v4.check_ref_read_qc()
 RETURNS TABLE(check_name text, problems bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  check_name := 'raw_qc: differs from public (after triage, either way)';
  SELECT (SELECT count(*) FROM (SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.raw_qc
                                EXCEPT ALL SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.sync_raw_qc_source
                                           WHERE key_problem IS NULL AND num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads) > 0) x)
       + (SELECT count(*) FROM (SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.sync_raw_qc_source
                                WHERE key_problem IS NULL AND num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads) > 0
                                EXCEPT ALL SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.raw_qc) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'hifi_reads_qc: differs from public (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v4.hifi_reads_qc EXCEPT ALL SELECT * FROM public.hifi_reads_qc) x)
       + (SELECT count(*) FROM (SELECT * FROM public.hifi_reads_qc EXCEPT ALL SELECT * FROM v4.hifi_reads_qc) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'hic_reads_qc: differs from public (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v4.hic_reads_qc EXCEPT ALL SELECT * FROM public.hic_reads_qc) x)
       + (SELECT count(*) FROM (SELECT * FROM public.hic_reads_qc EXCEPT ALL SELECT * FROM v4.hic_reads_qc) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'coverage_summary: differs from public (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v4.coverage_summary EXCEPT ALL SELECT * FROM public.coverage_summary) x)
       + (SELECT count(*) FROM (SELECT * FROM public.coverage_summary EXCEPT ALL SELECT * FROM v4.coverage_summary) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'read QC: public rows with an untriaged key problem';
  SELECT (SELECT count(*) FROM v4.sync_raw_qc_source WHERE key_problem IS NOT NULL)
       + (SELECT count(*) FROM v4.sync_read_qc_hifi_source WHERE key_problem IS NOT NULL)
       + (SELECT count(*) FROM v4.sync_read_qc_hic_source WHERE key_problem IS NOT NULL)
    INTO problems;
  RETURN NEXT;

  check_name := 'read sets with no QC row';
  SELECT count(*) INTO problems FROM v4.ref_read_set rs
  WHERE NOT EXISTS (SELECT 1 FROM v4.ref_genomescope g WHERE g.read_set_id = rs.read_set_id)
    AND NOT EXISTS (SELECT 1 FROM v4.ref_hifi_adapter_filter f WHERE f.read_set_id = rs.read_set_id);
  RETURN NEXT;

  check_name := 'note: read sets with no sequencing link';
  SELECT count(*) INTO problems FROM v4.v_read_set_run_readiness;
  RETURN NEXT;

  check_name := 'note: undated read sets';
  SELECT count(*) INTO problems FROM v4.ref_read_set WHERE seq_date IS NULL;
  RETURN NEXT;

  check_name := 'note: hifi_read_qc rows with no sequencing link';
  SELECT count(*) INTO problems FROM v4.hifi_read_qc WHERE sequencing_id IS NULL;
  RETURN NEXT;

  check_name := 'note: hic_read_qc rows with no sequencing link';
  SELECT count(*) INTO problems FROM v4.hic_read_qc WHERE sequencing_id IS NULL;
  RETURN NEXT;
END
$function$;
COMMENT ON FUNCTION v4.check_ref_read_qc() IS 'Phase RG window only: v4 read-QC tables against public after triage. Every problems value must be 0 except checks named note:. Dropped at RG.6.';

CREATE OR REPLACE FUNCTION v4.check_ref_submission()
 RETURNS TABLE(check_name text, problems bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  check_name := 'ref_genomes_assembly_uploads: differs from public (after triage, either way)';
  SELECT (SELECT count(*) FROM (SELECT og_id, biosample, bioproject_umbrella, bioproject_hap1, bioproject_hap2, bioproject_rawdata, assembly_accession_hap1, assembly_accession_hap2, embargo_status, gca_accession_hap1, gca_accession_hap2 FROM v4.ref_genomes_assembly_uploads
                                EXCEPT ALL SELECT og_id, biosample, bioproject_umbrella, bioproject_hap1, bioproject_hap2, bioproject_rawdata, assembly_accession_hap1, assembly_accession_hap2, embargo_status, gca_accession_hap1, gca_accession_hap2 FROM v4.sync_ref_submission_source WHERE key_problem IS NULL) x)
       + (SELECT count(*) FROM (SELECT og_id, biosample, bioproject_umbrella, bioproject_hap1, bioproject_hap2, bioproject_rawdata, assembly_accession_hap1, assembly_accession_hap2, embargo_status, gca_accession_hap1, gca_accession_hap2 FROM v4.sync_ref_submission_source WHERE key_problem IS NULL
                                EXCEPT ALL SELECT og_id, biosample, bioproject_umbrella, bioproject_hap1, bioproject_hap2, bioproject_rawdata, assembly_accession_hap1, assembly_accession_hap2, embargo_status, gca_accession_hap1, gca_accession_hap2 FROM v4.ref_genomes_assembly_uploads) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'ref_genomes_sra_uploads: differs from public (after triage, either way)';
  SELECT (SELECT count(*) FROM (SELECT srr_accession, og_id, filenames, data_type, ncbi_status FROM v4.ref_genomes_sra_uploads
                                EXCEPT ALL SELECT srr_accession, og_id, filenames, data_type, ncbi_status FROM v4.sync_ref_sra_source WHERE key_problem IS NULL) x)
       + (SELECT count(*) FROM (SELECT srr_accession, og_id, filenames, data_type, ncbi_status FROM v4.sync_ref_sra_source WHERE key_problem IS NULL
                                EXCEPT ALL SELECT srr_accession, og_id, filenames, data_type, ncbi_status FROM v4.ref_genomes_sra_uploads) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'uploads: public rows with an untriaged key problem';
  SELECT (SELECT count(*) FROM v4.sync_ref_submission_source WHERE key_problem IS NOT NULL)
       + (SELECT count(*) FROM v4.sync_ref_sra_source WHERE key_problem IS NOT NULL)
    INTO problems;
  RETURN NEXT;

  check_name := 'ref_submission_haplotype: assembly_id differs from its submission (070)';
  SELECT count(*) INTO problems FROM v4.ref_submission_haplotype h JOIN v4.ref_submission s USING (submission_id)
  WHERE h.assembly_id IS DISTINCT FROM s.assembly_id;
  RETURN NEXT;

  check_name := 'note: submissions with no single curated assembly';
  SELECT count(*) INTO problems FROM v4.ref_submission WHERE assembly_id IS NULL;
  RETURN NEXT;

  check_name := 'note: SRA uploads with no sequencing link';
  SELECT count(*) INTO problems FROM v4.v_sra_upload_run_readiness;
  RETURN NEXT;
END
$function$;
COMMENT ON FUNCTION v4.check_ref_submission() IS 'Phase RG window only: v4 submission tables against public. Every problems value must be 0 except checks named note:. Dropped at RG.6.';

CREATE OR REPLACE FUNCTION v4.sync_ref_assembly()
 RETURNS TABLE(step text, changed bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
 SET client_min_messages TO 'warning'
AS $function$
DECLARE
  n bigint;
BEGIN
  DROP TABLE IF EXISTS pg_temp.sync_ref_src, pg_temp.sync_ref_src_k, pg_temp.sync_ref_run_want;
  CREATE TEMP TABLE sync_ref_src ON COMMIT DROP AS
    SELECT * FROM v4.sync_ref_genomes_source WHERE key_problem IS NULL AND NOT is_empty;

  DELETE FROM v4.ref_assembly a
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src s WHERE (s.og_id, s.seq_date, s.version) = (a.og_id, a.seq_date, a.version));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_assembly (og_id, seq_date, version)
  SELECT DISTINCT og_id, seq_date, version FROM sync_ref_src
  ON CONFLICT (og_id, seq_date, version) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly inserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_assembly_part p USING v4.ref_assembly a
  WHERE p.assembly_id = a.assembly_id
    AND NOT EXISTS (SELECT 1 FROM sync_ref_src s
                    WHERE (s.og_id, s.seq_date, s.version, s.stage, s.haplotype) = (a.og_id, a.seq_date, a.version, p.stage, p.haplotype));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'part deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_assembly_part (assembly_id, stage, haplotype)
  SELECT a.assembly_id, s.stage, s.haplotype FROM sync_ref_src s JOIN v4.ref_assembly a USING (og_id, seq_date, version)
  ON CONFLICT (assembly_id, stage, haplotype) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'part inserted'; changed := n; RETURN NEXT;

  CREATE TEMP TABLE sync_ref_src_k ON COMMIT DROP AS
    SELECT p.part_id, s.* FROM sync_ref_src s
    JOIN v4.ref_assembly a USING (og_id, seq_date, version)
    JOIN v4.ref_assembly_part p ON (p.assembly_id, p.stage, p.haplotype) = (a.assembly_id, s.stage, s.haplotype);

  DELETE FROM v4.ref_gfastats t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.num_contigs, s.contig_n50, s.contig_n50_size_mb, s.num_scaffolds, s.scaffold_n50, s.scaffold_n50_size_mb, s.largest_scaffold, s.largest_scaffold_size_mb, s.total_scaffold_length, s.total_scaffold_length_size_mb, s.gc_content_percent, s.num_gaps) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_gfastats deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_gfastats AS t (part_id, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, num_gaps)
  SELECT s.part_id, s.num_contigs, s.contig_n50, s.contig_n50_size_mb, s.num_scaffolds, s.scaffold_n50, s.scaffold_n50_size_mb, s.largest_scaffold, s.largest_scaffold_size_mb, s.total_scaffold_length, s.total_scaffold_length_size_mb, s.gc_content_percent, s.num_gaps FROM sync_ref_src_k s WHERE num_nonnulls(s.num_contigs, s.contig_n50, s.contig_n50_size_mb, s.num_scaffolds, s.scaffold_n50, s.scaffold_n50_size_mb, s.largest_scaffold, s.largest_scaffold_size_mb, s.total_scaffold_length, s.total_scaffold_length_size_mb, s.gc_content_percent, s.num_gaps) > 0
  ON CONFLICT (part_id) DO UPDATE SET num_contigs = EXCLUDED.num_contigs, contig_n50 = EXCLUDED.contig_n50, contig_n50_size_mb = EXCLUDED.contig_n50_size_mb, num_scaffolds = EXCLUDED.num_scaffolds, scaffold_n50 = EXCLUDED.scaffold_n50, scaffold_n50_size_mb = EXCLUDED.scaffold_n50_size_mb, largest_scaffold = EXCLUDED.largest_scaffold, largest_scaffold_size_mb = EXCLUDED.largest_scaffold_size_mb, total_scaffold_length = EXCLUDED.total_scaffold_length, total_scaffold_length_size_mb = EXCLUDED.total_scaffold_length_size_mb, gc_content_percent = EXCLUDED.gc_content_percent, num_gaps = EXCLUDED.num_gaps, loaded_at = now()
    WHERE (t.num_contigs, t.contig_n50, t.contig_n50_size_mb, t.num_scaffolds, t.scaffold_n50, t.scaffold_n50_size_mb, t.largest_scaffold, t.largest_scaffold_size_mb, t.total_scaffold_length, t.total_scaffold_length_size_mb, t.gc_content_percent, t.num_gaps) IS DISTINCT FROM (EXCLUDED.num_contigs, EXCLUDED.contig_n50, EXCLUDED.contig_n50_size_mb, EXCLUDED.num_scaffolds, EXCLUDED.scaffold_n50, EXCLUDED.scaffold_n50_size_mb, EXCLUDED.largest_scaffold, EXCLUDED.largest_scaffold_size_mb, EXCLUDED.total_scaffold_length, EXCLUDED.total_scaffold_length_size_mb, EXCLUDED.gc_content_percent, EXCLUDED.num_gaps);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_gfastats upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_busco t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.dataset, s.complete, s.single_copy, s.multi_copy, s.fragmented, s.missing, s.n_markers, s.internal_stop_codon_percent, s.scaffold_n50_bus, s.contigs_n50_bus, s.percent_gaps, s.number_of_scaffolds) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_busco deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_busco AS t (part_id, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds)
  SELECT s.part_id, s.dataset, s.complete, s.single_copy, s.multi_copy, s.fragmented, s.missing, s.n_markers, s.internal_stop_codon_percent, s.scaffold_n50_bus, s.contigs_n50_bus, s.percent_gaps, s.number_of_scaffolds FROM sync_ref_src_k s WHERE num_nonnulls(s.dataset, s.complete, s.single_copy, s.multi_copy, s.fragmented, s.missing, s.n_markers, s.internal_stop_codon_percent, s.scaffold_n50_bus, s.contigs_n50_bus, s.percent_gaps, s.number_of_scaffolds) > 0
  ON CONFLICT (part_id) DO UPDATE SET dataset = EXCLUDED.dataset, complete = EXCLUDED.complete, single_copy = EXCLUDED.single_copy, multi_copy = EXCLUDED.multi_copy, fragmented = EXCLUDED.fragmented, missing = EXCLUDED.missing, n_markers = EXCLUDED.n_markers, internal_stop_codon_percent = EXCLUDED.internal_stop_codon_percent, scaffold_n50_bus = EXCLUDED.scaffold_n50_bus, contigs_n50_bus = EXCLUDED.contigs_n50_bus, percent_gaps = EXCLUDED.percent_gaps, number_of_scaffolds = EXCLUDED.number_of_scaffolds, loaded_at = now()
    WHERE (t.dataset, t.complete, t.single_copy, t.multi_copy, t.fragmented, t.missing, t.n_markers, t.internal_stop_codon_percent, t.scaffold_n50_bus, t.contigs_n50_bus, t.percent_gaps, t.number_of_scaffolds) IS DISTINCT FROM (EXCLUDED.dataset, EXCLUDED.complete, EXCLUDED.single_copy, EXCLUDED.multi_copy, EXCLUDED.fragmented, EXCLUDED.missing, EXCLUDED.n_markers, EXCLUDED.internal_stop_codon_percent, EXCLUDED.scaffold_n50_bus, EXCLUDED.contigs_n50_bus, EXCLUDED.percent_gaps, EXCLUDED.number_of_scaffolds);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_busco upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_merqury_qv t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.unique_k_mers_assembly, s.k_mers_total, s.qv, s.error) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_merqury_qv deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_merqury_qv AS t (part_id, unique_k_mers_assembly, k_mers_total, qv, error)
  SELECT s.part_id, s.unique_k_mers_assembly, s.k_mers_total, s.qv, s.error FROM sync_ref_src_k s WHERE num_nonnulls(s.unique_k_mers_assembly, s.k_mers_total, s.qv, s.error) > 0
  ON CONFLICT (part_id) DO UPDATE SET unique_k_mers_assembly = EXCLUDED.unique_k_mers_assembly, k_mers_total = EXCLUDED.k_mers_total, qv = EXCLUDED.qv, error = EXCLUDED.error, loaded_at = now()
    WHERE (t.unique_k_mers_assembly, t.k_mers_total, t.qv, t.error) IS DISTINCT FROM (EXCLUDED.unique_k_mers_assembly, EXCLUDED.k_mers_total, EXCLUDED.qv, EXCLUDED.error);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_merqury_qv upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_merqury_completeness t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.solid_k_mers, s.total_k_mers, s.completeness) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_merqury_completeness deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_merqury_completeness AS t (part_id, solid_k_mers, total_k_mers, completeness)
  SELECT s.part_id, s.solid_k_mers, s.total_k_mers, s.completeness FROM sync_ref_src_k s WHERE num_nonnulls(s.solid_k_mers, s.total_k_mers, s.completeness) > 0
  ON CONFLICT (part_id) DO UPDATE SET solid_k_mers = EXCLUDED.solid_k_mers, total_k_mers = EXCLUDED.total_k_mers, completeness = EXCLUDED.completeness, loaded_at = now()
    WHERE (t.solid_k_mers, t.total_k_mers, t.completeness) IS DISTINCT FROM (EXCLUDED.solid_k_mers, EXCLUDED.total_k_mers, EXCLUDED.completeness);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_merqury_completeness upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_omnic t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.total, s.total_unmapped, s.total_single_sided_mapped, s.total_mapped, s.total_dups, s.total_nodups, s.cis, s.trans) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_omnic deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_omnic AS t (part_id, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans)
  SELECT s.part_id, s.total, s.total_unmapped, s.total_single_sided_mapped, s.total_mapped, s.total_dups, s.total_nodups, s.cis, s.trans FROM sync_ref_src_k s WHERE num_nonnulls(s.total, s.total_unmapped, s.total_single_sided_mapped, s.total_mapped, s.total_dups, s.total_nodups, s.cis, s.trans) > 0
  ON CONFLICT (part_id) DO UPDATE SET total = EXCLUDED.total, total_unmapped = EXCLUDED.total_unmapped, total_single_sided_mapped = EXCLUDED.total_single_sided_mapped, total_mapped = EXCLUDED.total_mapped, total_dups = EXCLUDED.total_dups, total_nodups = EXCLUDED.total_nodups, cis = EXCLUDED.cis, trans = EXCLUDED.trans, loaded_at = now()
    WHERE (t.total, t.total_unmapped, t.total_single_sided_mapped, t.total_mapped, t.total_dups, t.total_nodups, t.cis, t.trans) IS DISTINCT FROM (EXCLUDED.total, EXCLUDED.total_unmapped, EXCLUDED.total_single_sided_mapped, EXCLUDED.total_mapped, EXCLUDED.total_dups, EXCLUDED.total_nodups, EXCLUDED.cis, EXCLUDED.trans);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_omnic upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_seqkit_stats t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.format, s."type", s.num_seqs, s.sum_len, s.min_len, s.avg_len, s.max_len) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_seqkit_stats deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_seqkit_stats AS t (part_id, format, "type", num_seqs, sum_len, min_len, avg_len, max_len)
  SELECT s.part_id, s.format, s."type", s.num_seqs, s.sum_len, s.min_len, s.avg_len, s.max_len FROM sync_ref_src_k s WHERE num_nonnulls(s.format, s."type", s.num_seqs, s.sum_len, s.min_len, s.avg_len, s.max_len) > 0
  ON CONFLICT (part_id) DO UPDATE SET format = EXCLUDED.format, "type" = EXCLUDED."type", num_seqs = EXCLUDED.num_seqs, sum_len = EXCLUDED.sum_len, min_len = EXCLUDED.min_len, avg_len = EXCLUDED.avg_len, max_len = EXCLUDED.max_len, loaded_at = now()
    WHERE (t.format, t."type", t.num_seqs, t.sum_len, t.min_len, t.avg_len, t.max_len) IS DISTINCT FROM (EXCLUDED.format, EXCLUDED."type", EXCLUDED.num_seqs, EXCLUDED.sum_len, EXCLUDED.min_len, EXCLUDED.avg_len, EXCLUDED.max_len);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_seqkit_stats upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_chromosome_stats t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.num_chromosomes, s.pct_assigned, s.pct_no_super, s.num_seq_no_super, s.max_len_no_super) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_chromosome_stats deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_chromosome_stats AS t (part_id, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super)
  SELECT s.part_id, s.num_chromosomes, s.pct_assigned, s.pct_no_super, s.num_seq_no_super, s.max_len_no_super FROM sync_ref_src_k s WHERE num_nonnulls(s.num_chromosomes, s.pct_assigned, s.pct_no_super, s.num_seq_no_super, s.max_len_no_super) > 0
  ON CONFLICT (part_id) DO UPDATE SET num_chromosomes = EXCLUDED.num_chromosomes, pct_assigned = EXCLUDED.pct_assigned, pct_no_super = EXCLUDED.pct_no_super, num_seq_no_super = EXCLUDED.num_seq_no_super, max_len_no_super = EXCLUDED.max_len_no_super, loaded_at = now()
    WHERE (t.num_chromosomes, t.pct_assigned, t.pct_no_super, t.num_seq_no_super, t.max_len_no_super) IS DISTINCT FROM (EXCLUDED.num_chromosomes, EXCLUDED.pct_assigned, EXCLUDED.pct_no_super, EXCLUDED.num_seq_no_super, EXCLUDED.max_len_no_super);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_chromosome_stats upserted'; changed := n; RETURN NEXT;

  CREATE TEMP TABLE sync_ref_run_want ON COMMIT DROP AS
    SELECT DISTINCT a.assembly_id, s.sequencing_id
    FROM v4.ref_assembly a
    JOIN public.v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
    WHERE s.technology IN ('PacBio HIFI', 'PacBio', 'ONT') AND s.library_type IN ('pacbio', 'ont')
      AND s.status IS DISTINCT FROM 'Failed';  -- 069: a failed run produced no reads to build from
  DELETE FROM v4.ref_assembly_run r
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_run_want w WHERE (w.assembly_id, w.sequencing_id) = (r.assembly_id, r.sequencing_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_assembly_run (assembly_id, sequencing_id)
  SELECT assembly_id, sequencing_id FROM sync_ref_run_want
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link inserted'; changed := n; RETURN NEXT;
END
$function$;
COMMENT ON FUNCTION v4.sync_ref_assembly() IS 'Phase RG window only: copy public.ref_genomes into the v4 assembly tables, keyed on natural keys so ids stay stable. Skips rows with a key_problem (check_ref_assembly then fails). Dropped at RG.6.';

CREATE OR REPLACE FUNCTION v4.sync_ref_read_qc()
 RETURNS TABLE(step text, changed bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
 SET client_min_messages TO 'warning'
AS $function$
DECLARE
  n bigint;
BEGIN
  -- Read sets (062): an OG gone from public loses its read sets; an undated read set exists only
  -- while public differs from the OG's latest dated one.
  DELETE FROM v4.ref_read_set rs
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_read_set_source s WHERE s.og_id = rs.og_id)
     OR (rs.seq_date IS NULL AND EXISTS (SELECT 1 FROM v4.sync_read_set_source s WHERE s.og_id = rs.og_id AND s.matches_dated));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_read_set deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_read_set (og_id, seq_date)
  SELECT s.og_id, NULL FROM v4.sync_read_set_source s WHERE NOT s.matches_dated
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_read_set inserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_genomescope g
  USING v4.ref_read_set rs, v4.sync_read_set_source s
  WHERE g.read_set_id = rs.read_set_id AND rs.seq_date IS NULL AND s.og_id = rs.og_id AND NOT s.has_gs;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_genomescope deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_genomescope AS t (read_set_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate)
  SELECT rs.read_set_id, s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate
  FROM v4.sync_read_set_source s JOIN v4.ref_read_set rs ON rs.og_id = s.og_id AND rs.seq_date IS NULL
  WHERE s.has_gs AND NOT s.matches_dated
  ON CONFLICT (read_set_id) DO UPDATE SET homozygosity = EXCLUDED.homozygosity, heterozygosity = EXCLUDED.heterozygosity, genomesize = EXCLUDED.genomesize, repeatsize = EXCLUDED.repeatsize, uniquesize = EXCLUDED.uniquesize, modelfit = EXCLUDED.modelfit, errorrate = EXCLUDED.errorrate, loaded_at = now()
    WHERE (t.homozygosity, t.heterozygosity, t.genomesize, t.repeatsize, t.uniquesize, t.modelfit, t.errorrate) IS DISTINCT FROM (EXCLUDED.homozygosity, EXCLUDED.heterozygosity, EXCLUDED.genomesize, EXCLUDED.repeatsize, EXCLUDED.uniquesize, EXCLUDED.modelfit, EXCLUDED.errorrate);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_genomescope upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_hifi_adapter_filter f
  USING v4.ref_read_set rs, v4.sync_read_set_source s
  WHERE f.read_set_id = rs.read_set_id AND rs.seq_date IS NULL AND s.og_id = rs.og_id AND NOT s.has_af;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_hifi_adapter_filter deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_hifi_adapter_filter AS t (read_set_id, contam_reads)
  SELECT rs.read_set_id, s.contam_reads
  FROM v4.sync_read_set_source s JOIN v4.ref_read_set rs ON rs.og_id = s.og_id AND rs.seq_date IS NULL
  WHERE s.has_af AND NOT s.matches_dated
  ON CONFLICT (read_set_id) DO UPDATE SET contam_reads = EXCLUDED.contam_reads, loaded_at = now()
    WHERE t.contam_reads IS DISTINCT FROM EXCLUDED.contam_reads;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_hifi_adapter_filter upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.hifi_read_qc t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_read_qc_hifi_source s
                    WHERE s.key_problem IS NULL AND (s.og_id, s.tissue, s.ext_type, s.lib_code, s.run_id) = (t.og_id, t.tissue, t.ext_type, t.lib_code, t.run_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hifi_read_qc deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.hifi_read_qc AS t (og_id, tissue, ext_type, lib_code, run_id, sequencing_id, barcode, barcode_quality, hifi_reads, hifi_read_length, hifi_read_quality, hifi_yield, polymerase_read_length)
  SELECT s.og_id, s.tissue, s.ext_type, s.lib_code, s.run_id, s.resolved_sequencing_id, s.barcode, s.barcode_quality, s.hifi_reads, s.hifi_read_length, s.hifi_read_quality, s.hifi_yield, s.polymerase_read_length
  FROM v4.sync_read_qc_hifi_source s WHERE s.key_problem IS NULL
  ON CONFLICT (og_id, tissue, ext_type, lib_code, run_id) DO UPDATE SET sequencing_id = EXCLUDED.sequencing_id, barcode = EXCLUDED.barcode, barcode_quality = EXCLUDED.barcode_quality, hifi_reads = EXCLUDED.hifi_reads, hifi_read_length = EXCLUDED.hifi_read_length, hifi_read_quality = EXCLUDED.hifi_read_quality, hifi_yield = EXCLUDED.hifi_yield, polymerase_read_length = EXCLUDED.polymerase_read_length, loaded_at = now()
    WHERE (t.sequencing_id, t.barcode, t.barcode_quality, t.hifi_reads, t.hifi_read_length, t.hifi_read_quality, t.hifi_yield, t.polymerase_read_length) IS DISTINCT FROM (EXCLUDED.sequencing_id, EXCLUDED.barcode, EXCLUDED.barcode_quality, EXCLUDED.hifi_reads, EXCLUDED.hifi_read_length, EXCLUDED.hifi_read_quality, EXCLUDED.hifi_yield, EXCLUDED.polymerase_read_length);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hifi_read_qc upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.hic_read_qc t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_read_qc_hic_source s
                    WHERE s.key_problem IS NULL AND s.og_id = t.og_id AND s.run_id = t.run_id
                      AND s.tissue IS NOT DISTINCT FROM t.tissue AND s.ext_type IS NOT DISTINCT FROM t.ext_type AND s.lib_code IS NOT DISTINCT FROM t.lib_code AND s.lane IS NOT DISTINCT FROM t.lane);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hic_read_qc deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.hic_read_qc AS t (og_id, tissue, ext_type, lib_code, lane, run_id, sequencing_id, datecreated, isarchived, isfiledeleted, totalreadspf, totalclusterspf, read1length, read2length, ispairedend, yield_gb, totalsize_gb)
  SELECT s.og_id, s.tissue, s.ext_type, s.lib_code, s.lane, s.run_id, s.resolved_sequencing_id, s.datecreated, s.isarchived, s.isfiledeleted, s.totalreadspf, s.totalclusterspf, s.read1length, s.read2length, s.ispairedend, s.yield_gb, s.totalsize_gb
  FROM v4.sync_read_qc_hic_source s WHERE s.key_problem IS NULL
  ON CONFLICT (og_id, (coalesce(tissue, '')), (coalesce(ext_type, '')), (coalesce(lib_code, '')), (coalesce(lane, '')), run_id) DO UPDATE SET sequencing_id = EXCLUDED.sequencing_id, datecreated = EXCLUDED.datecreated, isarchived = EXCLUDED.isarchived, isfiledeleted = EXCLUDED.isfiledeleted, totalreadspf = EXCLUDED.totalreadspf, totalclusterspf = EXCLUDED.totalclusterspf, read1length = EXCLUDED.read1length, read2length = EXCLUDED.read2length, ispairedend = EXCLUDED.ispairedend, yield_gb = EXCLUDED.yield_gb, totalsize_gb = EXCLUDED.totalsize_gb, loaded_at = now()
    WHERE (t.sequencing_id, t.datecreated, t.isarchived, t.isfiledeleted, t.totalreadspf, t.totalclusterspf, t.read1length, t.read2length, t.ispairedend, t.yield_gb, t.totalsize_gb) IS DISTINCT FROM (EXCLUDED.sequencing_id, EXCLUDED.datecreated, EXCLUDED.isarchived, EXCLUDED.isfiledeleted, EXCLUDED.totalreadspf, EXCLUDED.totalclusterspf, EXCLUDED.read1length, EXCLUDED.read2length, EXCLUDED.ispairedend, EXCLUDED.yield_gb, EXCLUDED.totalsize_gb);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hic_read_qc upserted'; changed := n; RETURN NEXT;
END
$function$;
COMMENT ON FUNCTION v4.sync_ref_read_qc() IS 'Phase RG window only: copy public.raw_qc (into read sets, 062), hifi_reads_qc and hic_reads_qc into v4. Skips rows with a key_problem (check_ref_read_qc then fails). Dropped at RG.6.';

CREATE OR REPLACE FUNCTION v4.sync_ref_submission()
 RETURNS TABLE(step text, changed bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
 SET client_min_messages TO 'warning'
AS $function$
DECLARE
  n bigint;
BEGIN
  DELETE FROM v4.ref_sra_upload t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_ref_sra_source s WHERE s.key_problem IS NULL AND s.srr_accession = t.srr_accession);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_sra_upload deleted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_submission t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_ref_submission_source s WHERE s.key_problem IS NULL AND s.og_id = t.og_id);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_submission AS t (og_id, biosample, bioproject_umbrella, bioproject_rawdata, embargo_status)
  SELECT s.og_id, s.biosample, s.bioproject_umbrella, s.bioproject_rawdata, s.embargo_status FROM v4.sync_ref_submission_source s WHERE s.key_problem IS NULL
  ON CONFLICT (og_id) DO UPDATE SET biosample = EXCLUDED.biosample, bioproject_umbrella = EXCLUDED.bioproject_umbrella, bioproject_rawdata = EXCLUDED.bioproject_rawdata, embargo_status = EXCLUDED.embargo_status, loaded_at = now()
    WHERE (t.biosample, t.bioproject_umbrella, t.bioproject_rawdata, t.embargo_status) IS DISTINCT FROM (EXCLUDED.biosample, EXCLUDED.bioproject_umbrella, EXCLUDED.bioproject_rawdata, EXCLUDED.embargo_status);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission upserted'; changed := n; RETURN NEXT;

  UPDATE v4.ref_submission t SET assembly_id = c.assembly_id
  FROM (SELECT sub.submission_id,
               (SELECT CASE WHEN count(DISTINCT a.assembly_id) = 1 THEN min(a.assembly_id) END
                FROM v4.ref_assembly a JOIN v4.ref_assembly_part p ON p.assembly_id = a.assembly_id
                WHERE a.og_id = sub.og_id AND p.stage = 3) AS assembly_id
        FROM v4.ref_submission sub) c
  WHERE c.submission_id = t.submission_id AND t.assembly_id IS DISTINCT FROM c.assembly_id;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission assembly linked'; changed := n; RETURN NEXT;

  DROP TABLE IF EXISTS pg_temp.sync_ref_hap;
  CREATE TEMP TABLE sync_ref_hap ON COMMIT DROP AS
    -- 070: public keeps ERZ (ENA analysis) and WGS master accessions in one column; v4 splits them.
    SELECT sub.submission_id, h.haplotype, h.bioproject,
           CASE WHEN h.assembly_accession ~ '^ERZ' THEN h.assembly_accession END AS analysis_accession,
           CASE WHEN h.assembly_accession !~ '^ERZ' THEN h.assembly_accession END AS assembly_accession,
           h.gca_accession
    FROM v4.sync_ref_submission_source s
    JOIN v4.ref_submission sub ON sub.og_id = s.og_id
    CROSS JOIN LATERAL (VALUES ('hap1', s.bioproject_hap1, s.assembly_accession_hap1, s.gca_accession_hap1),
                               ('hap2', s.bioproject_hap2, s.assembly_accession_hap2, s.gca_accession_hap2)) h (haplotype, bioproject, assembly_accession, gca_accession)
    WHERE s.key_problem IS NULL AND num_nonnulls(h.bioproject, h.assembly_accession, h.gca_accession) > 0;
  DELETE FROM v4.ref_submission_haplotype t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_hap h WHERE (h.submission_id, h.haplotype) = (t.submission_id, t.haplotype));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission_haplotype deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_submission_haplotype AS t (submission_id, haplotype, bioproject, analysis_accession, assembly_accession, gca_accession)
  SELECT submission_id, haplotype, bioproject, analysis_accession, assembly_accession, gca_accession FROM sync_ref_hap
  ON CONFLICT (submission_id, haplotype) DO UPDATE SET bioproject = EXCLUDED.bioproject, analysis_accession = EXCLUDED.analysis_accession, assembly_accession = EXCLUDED.assembly_accession, gca_accession = EXCLUDED.gca_accession, loaded_at = now()
    WHERE (t.bioproject, t.analysis_accession, t.assembly_accession, t.gca_accession) IS DISTINCT FROM (EXCLUDED.bioproject, EXCLUDED.analysis_accession, EXCLUDED.assembly_accession, EXCLUDED.gca_accession);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission_haplotype upserted'; changed := n; RETURN NEXT;

  INSERT INTO v4.ref_sra_upload AS t (srr_accession, submission_id, filenames, data_type, ncbi_status, release_date)
  SELECT s.srr_accession, sub.submission_id, s.filenames, s.data_type, s.status_value, s.release_date
  FROM v4.sync_ref_sra_source s JOIN v4.ref_submission sub ON sub.og_id = s.og_id
  WHERE s.key_problem IS NULL
  ON CONFLICT (srr_accession) DO UPDATE SET submission_id = EXCLUDED.submission_id, filenames = EXCLUDED.filenames,
    data_type = EXCLUDED.data_type, ncbi_status = EXCLUDED.ncbi_status, release_date = EXCLUDED.release_date, loaded_at = now()
    WHERE (t.submission_id, t.filenames, t.data_type, t.ncbi_status, t.release_date)
          IS DISTINCT FROM (EXCLUDED.submission_id, EXCLUDED.filenames, EXCLUDED.data_type, EXCLUDED.ncbi_status, EXCLUDED.release_date);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_sra_upload upserted'; changed := n; RETURN NEXT;

  -- SRA run links (064): an upload with none, not reviewed and left unlinked, gets what the
  -- forward rule finds.
  INSERT INTO v4.ref_sra_upload_run (srr_accession, sequencing_id)
  SELECT u.srr_accession, r.sequencing_id
  FROM v4.ref_sra_upload u
  JOIN v4.ref_submission s ON s.submission_id = u.submission_id
  CROSS JOIN LATERAL v4.resolve_sra_upload_runs(s.og_id, u.data_type, u.filenames) AS r (sequencing_id)
  WHERE NOT EXISTS (SELECT 1 FROM v4.ref_sra_upload_run x WHERE x.srr_accession = u.srr_accession)
    AND NOT EXISTS (SELECT 1 FROM v4.ref_sra_upload_unlinked x WHERE x.srr_accession = u.srr_accession)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_sra_upload_run linked'; changed := n; RETURN NEXT;
END
$function$;
COMMENT ON FUNCTION v4.sync_ref_submission() IS 'Phase RG window only: copy the two public upload tables into v4, link each submission to its one curated assembly, and link new SRA uploads to sequencing (064). Skips rows with a key_problem (check_ref_submission then fails). Dropped at RG.6.';

DO $warn$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT 'assembly' AS side, * FROM v4.check_ref_assembly()
           UNION ALL SELECT 'read_qc', * FROM v4.check_ref_read_qc()
           UNION ALL SELECT 'submission', * FROM v4.check_ref_submission() LOOP
    IF r.problems <> 0 AND r.check_name NOT LIKE 'note:%' THEN
      RAISE WARNING 'revert 073: %: "%" = % (writes made after the swap, missing from the old tables)',
        r.side, r.check_name, r.problems;
    END IF;
  END LOOP;
END
$warn$;

COMMIT;
