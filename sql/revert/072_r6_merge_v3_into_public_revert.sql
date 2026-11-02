-- Revert 072_r6_merge_v3_into_public.sql: put v3 back beside public, exactly as before the merge.
--
-- Recreates v3 (same comment and grants), moves the 19 tables, 8 views and 2 functions back
-- into it, moves the archived mitogenome_data and draft_genomes back into public, and recreates
-- what 072 dropped: the old mitogenome_submission_view and v_genome_size_comparison, the three
-- LCA FKs and the five window functions. The definitions were captured from live on 2026-11-02
-- just before 072 was applied. Rehearsal proves the result schema-identical to before 072.
--
-- After it, the phase-r-v3 writers fail (their tables are in v3 again, off the search_path) and
-- the production writers that write public work again.
--
-- DATA WRITTEN AFTER THE MERGE. Between 072 and this revert, writers wrote only the new tables, so
-- the old tables coming back lack those writes; the warnings at the end list how many rows differ.
-- Do NOT re-add the 18:30 UTC sync_v3.sh cron line until those uploads have been re-run with the
-- old writers into public: the sync copies public -> v3 and would overwrite the newer v3 rows.
--
-- Opt-in:  PGOPTIONS="-c oceanomics.r6_revert=yes" psql -f sql/revert/072_r6_merge_v3_into_public_revert.sql
-- then delete 072's ledger row.

BEGIN;

DO $rv$
BEGIN
  IF coalesce(current_setting('oceanomics.r6_revert', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'Reverting R.6 puts the old tables back in public. Run with PGOPTIONS="-c oceanomics.r6_revert=yes"';
  END IF;
  IF to_regnamespace('v3') IS NOT NULL THEN
    RAISE EXCEPTION 'v3 already exists: 072 is not applied, or was already reverted';
  END IF;
END
$rv$;

SET LOCAL search_path = public, pg_temp;

CREATE SCHEMA v3;
COMMENT ON SCHEMA v3 IS 'Phase R: the new mitogenome and draft-genome design, built beside public and kept in sync with it until the R.6 merge. Nothing in public depends on it. docs/assembly_relations_plan.md';
GRANT USAGE ON SCHEMA v3 TO readonly, oceangenom_web;

ALTER TABLE public.draft_busco SET SCHEMA v3;
ALTER TABLE public.draft_contamination SET SCHEMA v3;
ALTER TABLE public.draft_depthsizer SET SCHEMA v3;
ALTER TABLE public.draft_fastp SET SCHEMA v3;
ALTER TABLE public.draft_genome SET SCHEMA v3;
ALTER TABLE public.draft_genome_run SET SCHEMA v3;
ALTER TABLE public.draft_genomescope SET SCHEMA v3;
ALTER TABLE public.draft_gfastats SET SCHEMA v3;
ALTER TABLE public.draft_merqury SET SCHEMA v3;
ALTER TABLE public.draft_submission SET SCHEMA v3;
ALTER TABLE public.draft_tiara SET SCHEMA v3;
ALTER TABLE public.mito_annotation SET SCHEMA v3;
ALTER TABLE public.mito_annotation_gene SET SCHEMA v3;
ALTER TABLE public.mito_assembly SET SCHEMA v3;
ALTER TABLE public.mito_assembly_depth SET SCHEMA v3;
ALTER TABLE public.mito_assembly_qc SET SCHEMA v3;
ALTER TABLE public.mito_assembly_run SET SCHEMA v3;
ALTER TABLE public.mito_gene SET SCHEMA v3;
ALTER TABLE public.sequencing_run SET SCHEMA v3;
ALTER VIEW public.draft_genomes SET SCHEMA v3;
ALTER VIEW public.mitogenome_data SET SCHEMA v3;
ALTER VIEW public.mitogenome_submission_view SET SCHEMA v3;
ALTER VIEW public.v_draft_genome_status SET SCHEMA v3;
ALTER VIEW public.v_genome_size_comparison SET SCHEMA v3;
ALTER VIEW public.v_mito_annotation_genes SET SCHEMA v3;
ALTER VIEW public.v_sequencing_run_fk_readiness SET SCHEMA v3;
ALTER VIEW public.v_sequencing_run_issues SET SCHEMA v3;
ALTER FUNCTION public.draft_genome_run_illumina_only() SET SCHEMA v3;
ALTER FUNCTION public.rebuild_mito_gene_views() SET SCHEMA v3;
ALTER FUNCTION v3.rebuild_mito_gene_views() SET search_path = v3, public, pg_temp;

ALTER TABLE pre_v3_archive.mitogenome_data SET SCHEMA public;
ALTER TABLE pre_v3_archive.draft_genomes   SET SCHEMA public;
COMMENT ON TABLE public.mitogenome_data IS 'Assembled mitogenome per (og_id, tech, seq_date, code). Parent of the LCA tables. Unlike the live table it has a foreign key to sample, so an assembly cannot reference a specimen that does not exist.';
COMMENT ON TABLE public.draft_genomes IS NULL;

-- The two views 072 dropped, as they were on live (pg_get_viewdef, search_path public).
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
   FROM mitogenome_data m
     LEFT JOIN sample s ON s.og_id = m.og_id
     LEFT JOIN ena_validation_attempts e ON e.og_id = m.og_id AND e.tech = m.tech AND e.seq_date = m.seq_date AND e.code = m.code AND e.annotation = m.annotation
     LEFT JOIN lca_validation l ON l.og_id = m.og_id AND l.tech = m.tech AND l.seq_date = m.seq_date AND l.code = m.code AND l.annotation = m.annotation;
COMMENT ON VIEW public.mitogenome_submission_view IS 'One row per mitogenome assembly with its ENA validation result and validated species name, for ENA submission. v2 form of public.mitogenome_submission_view (029): og_num comes from v2.sample, because v2 drops it from mitogenome_data (F2). See migration 043.';

CREATE VIEW public.v_genome_size_comparison AS
 SELECT d.og_id,
    d.seq_date,
    sp.species,
    sp.ncbi_taxon_id,
    d.genomesize AS estimated_bp,
    a.total_sequence_length AS ncbi_bp,
        CASE
            WHEN a.total_sequence_length > 0 THEN round(d.genomesize::numeric / a.total_sequence_length::numeric, 3)
            ELSE NULL::numeric
        END AS estimated_over_ncbi,
    a.assembly_accession,
    a.assembly_level,
    a.is_refseq,
    a.is_representative
   FROM draft_genomes d
     JOIN sample s ON s.og_id = d.og_id
     JOIN species sp ON s.nominal_species_id = sp.species
     LEFT JOIN species_ncbi_assembly a ON a.species = sp.species AND a.is_chosen;

GRANT SELECT ON public.mitogenome_submission_view, public.v_genome_size_comparison TO readonly;

-- The LCA FKs 072 dropped.
ALTER TABLE public.lca ADD CONSTRAINT lca_mitogenome_fkey FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES mitogenome_data(og_id, tech, seq_date, code);
ALTER TABLE public.lca_raw_results ADD CONSTRAINT lca_raw_results_mitogenome_fkey FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES mitogenome_data(og_id, tech, seq_date, code);
ALTER TABLE public.lca_validation ADD CONSTRAINT lca_validation_mitogenome_fkey FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES mitogenome_data(og_id, tech, seq_date, code);

-- The window-only functions 072 dropped (pg_get_functiondef from live).
CREATE OR REPLACE FUNCTION v3.check_draft()
 RETURNS TABLE(check_name text, problems bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  check_name := 'draft_genomes: v3 rows not in public';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit FROM v3.draft_genomes
    EXCEPT ALL
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit FROM public.draft_genomes) x;
  RETURN NEXT;

  check_name := 'draft_genomes: public rows not in v3';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit FROM public.draft_genomes
    EXCEPT ALL
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit FROM v3.draft_genomes) x;
  RETURN NEXT;

  check_name := 'v_genome_size_comparison: differs (either way)';
  SELECT (SELECT count(*) FROM (SELECT og_id, seq_date, species, ncbi_taxon_id, estimated_bp, ncbi_bp, estimated_over_ncbi, assembly_accession, assembly_level, is_refseq, is_representative FROM v3.v_genome_size_comparison
                                EXCEPT ALL SELECT og_id, seq_date, species, ncbi_taxon_id, estimated_bp, ncbi_bp, estimated_over_ncbi, assembly_accession, assembly_level, is_refseq, is_representative FROM public.v_genome_size_comparison) x)
       + (SELECT count(*) FROM (SELECT og_id, seq_date, species, ncbi_taxon_id, estimated_bp, ncbi_bp, estimated_over_ncbi, assembly_accession, assembly_level, is_refseq, is_representative FROM public.v_genome_size_comparison
                                EXCEPT ALL SELECT og_id, seq_date, species, ncbi_taxon_id, estimated_bp, ncbi_bp, estimated_over_ncbi, assembly_accession, assembly_level, is_refseq, is_representative FROM v3.v_genome_size_comparison) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'drafts with no Illumina run link';
  SELECT count(*) INTO problems FROM v3.draft_genome g
  WHERE NOT EXISTS (SELECT 1 FROM v3.draft_genome_run r WHERE r.draft_id = g.draft_id);
  RETURN NEXT;

  check_name := 'draft_depthsizer rows beyond the 701 loaded on 2026-10-16 (it is frozen)';
  SELECT greatest(count(*) - 701, 0) INTO problems FROM v3.draft_depthsizer;
  RETURN NEXT;
END
$function$
;

CREATE OR REPLACE FUNCTION v3.check_mito()
 RETURNS TABLE(check_name text, problems bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  check_name := 'mitogenome_data: v3 rows not in public';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at, completeness_profile, qc_status, manual_review_reason, numt_flag, frameshift_flag, reference_species, reference_accession, qc_updated_at FROM v3.mitogenome_data
    EXCEPT ALL
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at, completeness_profile, qc_status, manual_review_reason, numt_flag, frameshift_flag, reference_species, reference_accession, qc_updated_at FROM public.mitogenome_data) x;
  RETURN NEXT;

  check_name := 'mitogenome_data: public rows not in v3';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at, completeness_profile, qc_status, manual_review_reason, numt_flag, frameshift_flag, reference_species, reference_accession, qc_updated_at FROM public.mitogenome_data
    EXCEPT ALL
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at, completeness_profile, qc_status, manual_review_reason, numt_flag, frameshift_flag, reference_species, reference_accession, qc_updated_at FROM v3.mitogenome_data) x;
  RETURN NEXT;

  check_name := 'mitogenome_submission_view: differs (either way)';
  SELECT (SELECT count(*) FROM (SELECT og_num, og_id, tech, seq_date, code, annotation, stats, length, length_emma, cds_no, trna_no, rrna_no, extra_genes, missing_genes, order_correct, table2asn_status, warning_codes, webin_status, webin_reason, submission_ready, validated_species_name, validator FROM v3.mitogenome_submission_view
                                EXCEPT ALL SELECT og_num, og_id, tech, seq_date, code, annotation, stats, length, length_emma, cds_no, trna_no, rrna_no, extra_genes, missing_genes, order_correct, table2asn_status, warning_codes, webin_status, webin_reason, submission_ready, validated_species_name, validator FROM public.mitogenome_submission_view) x)
       + (SELECT count(*) FROM (SELECT og_num, og_id, tech, seq_date, code, annotation, stats, length, length_emma, cds_no, trna_no, rrna_no, extra_genes, missing_genes, order_correct, table2asn_status, warning_codes, webin_status, webin_reason, submission_ready, validated_species_name, validator FROM public.mitogenome_submission_view
                                EXCEPT ALL SELECT og_num, og_id, tech, seq_date, code, annotation, stats, length, length_emma, cds_no, trna_no, rrna_no, extra_genes, missing_genes, order_correct, table2asn_status, warning_codes, webin_status, webin_reason, submission_ready, validated_species_name, validator FROM v3.mitogenome_submission_view) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'child rows not resolving to exactly one v3 annotation';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, tech, seq_date, code, annotation FROM public.lca_validation
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.lca
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.lca_raw_results
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.blast_filtered_lca
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.ena_validation_attempts
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.ena_submissions) c
  WHERE (SELECT count(*) FROM v3.mito_annotation n JOIN v3.mito_assembly a USING (assembly_id)
         WHERE (a.og_id, a.tech, a.seq_date, a.code, n.annotation)
             = (c.og_id, c.tech, c.seq_date, c.code, c.annotation)) <> 1;
  RETURN NEXT;

  check_name := 'annotations selected (none expected before a person chooses)';
  SELECT count(*) INTO problems FROM v3.mito_annotation WHERE is_selected;
  RETURN NEXT;
END
$function$
;

CREATE OR REPLACE FUNCTION v3.sync_draft()
 RETURNS TABLE(step text, changed bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  n             bigint;
  depthsizer_on boolean := NOT EXISTS (SELECT 1 FROM v3.draft_depthsizer);
BEGIN
  DELETE FROM v3.draft_genome g
  WHERE NOT EXISTS (SELECT 1 FROM public.draft_genomes p WHERE (p.og_id, p.seq_date) = (g.og_id, g.seq_date));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.draft_genome AS t (og_id, seq_date, mach, initial)
  SELECT og_id, seq_date, mach, initial FROM public.draft_genomes
  ON CONFLICT (og_id, seq_date) DO UPDATE SET mach = EXCLUDED.mach, initial = EXCLUDED.initial
    WHERE (t.mach, t.initial) IS DISTINCT FROM (EXCLUDED.mach, EXCLUDED.initial);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_fastp x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.passed_filter_reads, p.low_quality_reads, p.too_many_n_reads, p.too_short_reads, p.too_long_reads, p.raw_total_reads, p.raw_total_bases, p.raw_q20_bases, p.raw_q30_bases, p.raw_q20_rate, p.raw_q30_rate, p.raw_read1_mean_length, p.raw_read2_mean_length, p.raw_gc_content, p.total_reads, p.total_bases, p.q20_bases, p.q30_bases, p.q20_rate, p.q30_rate, p.read1_mean_length, p.read2_mean_length, p.gc_content) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_fastp deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_fastp AS t (draft_id, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content)
  SELECT g.draft_id, p.passed_filter_reads, p.low_quality_reads, p.too_many_n_reads, p.too_short_reads, p.too_long_reads, p.raw_total_reads, p.raw_total_bases, p.raw_q20_bases, p.raw_q30_bases, p.raw_q20_rate, p.raw_q30_rate, p.raw_read1_mean_length, p.raw_read2_mean_length, p.raw_gc_content, p.total_reads, p.total_bases, p.q20_bases, p.q30_bases, p.q20_rate, p.q30_rate, p.read1_mean_length, p.read2_mean_length, p.gc_content
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.passed_filter_reads, p.low_quality_reads, p.too_many_n_reads, p.too_short_reads, p.too_long_reads, p.raw_total_reads, p.raw_total_bases, p.raw_q20_bases, p.raw_q30_bases, p.raw_q20_rate, p.raw_q30_rate, p.raw_read1_mean_length, p.raw_read2_mean_length, p.raw_gc_content, p.total_reads, p.total_bases, p.q20_bases, p.q30_bases, p.q20_rate, p.q30_rate, p.read1_mean_length, p.read2_mean_length, p.gc_content) > 0
  ON CONFLICT (draft_id) DO UPDATE SET passed_filter_reads = EXCLUDED.passed_filter_reads, low_quality_reads = EXCLUDED.low_quality_reads, too_many_n_reads = EXCLUDED.too_many_n_reads, too_short_reads = EXCLUDED.too_short_reads, too_long_reads = EXCLUDED.too_long_reads, raw_total_reads = EXCLUDED.raw_total_reads, raw_total_bases = EXCLUDED.raw_total_bases, raw_q20_bases = EXCLUDED.raw_q20_bases, raw_q30_bases = EXCLUDED.raw_q30_bases, raw_q20_rate = EXCLUDED.raw_q20_rate, raw_q30_rate = EXCLUDED.raw_q30_rate, raw_read1_mean_length = EXCLUDED.raw_read1_mean_length, raw_read2_mean_length = EXCLUDED.raw_read2_mean_length, raw_gc_content = EXCLUDED.raw_gc_content, total_reads = EXCLUDED.total_reads, total_bases = EXCLUDED.total_bases, q20_bases = EXCLUDED.q20_bases, q30_bases = EXCLUDED.q30_bases, q20_rate = EXCLUDED.q20_rate, q30_rate = EXCLUDED.q30_rate, read1_mean_length = EXCLUDED.read1_mean_length, read2_mean_length = EXCLUDED.read2_mean_length, gc_content = EXCLUDED.gc_content, loaded_at = now()
    WHERE (t.passed_filter_reads, t.low_quality_reads, t.too_many_n_reads, t.too_short_reads, t.too_long_reads, t.raw_total_reads, t.raw_total_bases, t.raw_q20_bases, t.raw_q30_bases, t.raw_q20_rate, t.raw_q30_rate, t.raw_read1_mean_length, t.raw_read2_mean_length, t.raw_gc_content, t.total_reads, t.total_bases, t.q20_bases, t.q30_bases, t.q20_rate, t.q30_rate, t.read1_mean_length, t.read2_mean_length, t.gc_content) IS DISTINCT FROM (EXCLUDED.passed_filter_reads, EXCLUDED.low_quality_reads, EXCLUDED.too_many_n_reads, EXCLUDED.too_short_reads, EXCLUDED.too_long_reads, EXCLUDED.raw_total_reads, EXCLUDED.raw_total_bases, EXCLUDED.raw_q20_bases, EXCLUDED.raw_q30_bases, EXCLUDED.raw_q20_rate, EXCLUDED.raw_q30_rate, EXCLUDED.raw_read1_mean_length, EXCLUDED.raw_read2_mean_length, EXCLUDED.raw_gc_content, EXCLUDED.total_reads, EXCLUDED.total_bases, EXCLUDED.q20_bases, EXCLUDED.q30_bases, EXCLUDED.q20_rate, EXCLUDED.q30_rate, EXCLUDED.read1_mean_length, EXCLUDED.read2_mean_length, EXCLUDED.gc_content);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_fastp upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_genomescope x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction, p.host_haploid_size, p.partition_confidence, p.partition_note, p.busco_regions, p.busco_read_depth, p.genomescope_fit) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_genomescope deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_genomescope AS t (draft_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, homozygosity_min, heterozygosity_min, genomesize_min, repeatsize_min, uniquesize_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit)
  SELECT g.draft_id, p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction, p.host_haploid_size, p.partition_confidence, p.partition_note, p.busco_regions, p.busco_read_depth, p.genomescope_fit
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction, p.host_haploid_size, p.partition_confidence, p.partition_note, p.busco_regions, p.busco_read_depth, p.genomescope_fit) > 0
  ON CONFLICT (draft_id) DO UPDATE SET homozygosity = EXCLUDED.homozygosity, heterozygosity = EXCLUDED.heterozygosity, genomesize = EXCLUDED.genomesize, repeatsize = EXCLUDED.repeatsize, uniquesize = EXCLUDED.uniquesize, modelfit = EXCLUDED.modelfit, errorrate = EXCLUDED.errorrate, homozygosity_min = EXCLUDED.homozygosity_min, heterozygosity_min = EXCLUDED.heterozygosity_min, genomesize_min = EXCLUDED.genomesize_min, repeatsize_min = EXCLUDED.repeatsize_min, uniquesize_min = EXCLUDED.uniquesize_min, modelfit_allkmers = EXCLUDED.modelfit_allkmers, genome_size_reliable = EXCLUDED.genome_size_reliable, genome_size_flags = EXCLUDED.genome_size_flags, kmercov = EXCLUDED.kmercov, lambda_depth = EXCLUDED.lambda_depth, host_assembly_size = EXCLUDED.host_assembly_size, host_assembly_fraction = EXCLUDED.host_assembly_fraction, host_haploid_size = EXCLUDED.host_haploid_size, partition_confidence = EXCLUDED.partition_confidence, partition_note = EXCLUDED.partition_note, busco_regions = EXCLUDED.busco_regions, busco_read_depth = EXCLUDED.busco_read_depth, genomescope_fit = EXCLUDED.genomescope_fit, loaded_at = now()
    WHERE (t.homozygosity, t.heterozygosity, t.genomesize, t.repeatsize, t.uniquesize, t.modelfit, t.errorrate, t.homozygosity_min, t.heterozygosity_min, t.genomesize_min, t.repeatsize_min, t.uniquesize_min, t.modelfit_allkmers, t.genome_size_reliable, t.genome_size_flags, t.kmercov, t.lambda_depth, t.host_assembly_size, t.host_assembly_fraction, t.host_haploid_size, t.partition_confidence, t.partition_note, t.busco_regions, t.busco_read_depth, t.genomescope_fit) IS DISTINCT FROM (EXCLUDED.homozygosity, EXCLUDED.heterozygosity, EXCLUDED.genomesize, EXCLUDED.repeatsize, EXCLUDED.uniquesize, EXCLUDED.modelfit, EXCLUDED.errorrate, EXCLUDED.homozygosity_min, EXCLUDED.heterozygosity_min, EXCLUDED.genomesize_min, EXCLUDED.repeatsize_min, EXCLUDED.uniquesize_min, EXCLUDED.modelfit_allkmers, EXCLUDED.genome_size_reliable, EXCLUDED.genome_size_flags, EXCLUDED.kmercov, EXCLUDED.lambda_depth, EXCLUDED.host_assembly_size, EXCLUDED.host_assembly_fraction, EXCLUDED.host_haploid_size, EXCLUDED.partition_confidence, EXCLUDED.partition_note, EXCLUDED.busco_regions, EXCLUDED.busco_read_depth, EXCLUDED.genomescope_fit);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_genomescope upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_tiara x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.num_contigs_mitochondrion, p.num_contigs_plastid, p.num_contigs_prokarya, p.bp_mitochondrion, p.bp_plastid, p.bp_prokarya) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_tiara deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_tiara AS t (draft_id, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya)
  SELECT g.draft_id, p.num_contigs_mitochondrion, p.num_contigs_plastid, p.num_contigs_prokarya, p.bp_mitochondrion, p.bp_plastid, p.bp_prokarya
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.num_contigs_mitochondrion, p.num_contigs_plastid, p.num_contigs_prokarya, p.bp_mitochondrion, p.bp_plastid, p.bp_prokarya) > 0
  ON CONFLICT (draft_id) DO UPDATE SET num_contigs_mitochondrion = EXCLUDED.num_contigs_mitochondrion, num_contigs_plastid = EXCLUDED.num_contigs_plastid, num_contigs_prokarya = EXCLUDED.num_contigs_prokarya, bp_mitochondrion = EXCLUDED.bp_mitochondrion, bp_plastid = EXCLUDED.bp_plastid, bp_prokarya = EXCLUDED.bp_prokarya, loaded_at = now()
    WHERE (t.num_contigs_mitochondrion, t.num_contigs_plastid, t.num_contigs_prokarya, t.bp_mitochondrion, t.bp_plastid, t.bp_prokarya) IS DISTINCT FROM (EXCLUDED.num_contigs_mitochondrion, EXCLUDED.num_contigs_plastid, EXCLUDED.num_contigs_prokarya, EXCLUDED.bp_mitochondrion, EXCLUDED.bp_plastid, EXCLUDED.bp_prokarya);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_tiara upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_contamination x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.num_contigs_exclude, p.num_contigs_trim, p.num_contigs_review, p.bp_exclude, p.bp_trim, p.bp_review, p.num_contigs) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_contamination deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_contamination AS t (draft_id, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, num_contigs_lt_500bp)
  SELECT g.draft_id, p.num_contigs_exclude, p.num_contigs_trim, p.num_contigs_review, p.bp_exclude, p.bp_trim, p.bp_review, p.num_contigs
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.num_contigs_exclude, p.num_contigs_trim, p.num_contigs_review, p.bp_exclude, p.bp_trim, p.bp_review, p.num_contigs) > 0
  ON CONFLICT (draft_id) DO UPDATE SET num_contigs_exclude = EXCLUDED.num_contigs_exclude, num_contigs_trim = EXCLUDED.num_contigs_trim, num_contigs_review = EXCLUDED.num_contigs_review, bp_exclude = EXCLUDED.bp_exclude, bp_trim = EXCLUDED.bp_trim, bp_review = EXCLUDED.bp_review, num_contigs_lt_500bp = EXCLUDED.num_contigs_lt_500bp, loaded_at = now()
    WHERE (t.num_contigs_exclude, t.num_contigs_trim, t.num_contigs_review, t.bp_exclude, t.bp_trim, t.bp_review, t.num_contigs_lt_500bp) IS DISTINCT FROM (EXCLUDED.num_contigs_exclude, EXCLUDED.num_contigs_trim, EXCLUDED.num_contigs_review, EXCLUDED.bp_exclude, EXCLUDED.bp_trim, EXCLUDED.bp_review, EXCLUDED.num_contigs_lt_500bp);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_contamination upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_busco x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.complete, p.single_copy, p.multi_copy, p.fragmented, p.missing, p.n_markers, p.domain, p.number_of_scaffolds, p.number_of_contigs, p.total_length, p.percent_gaps, p.scaffold_n50, p.contigs_n50, p.internal_stop_codon_count, p.internal_stop_codon_percent) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_busco deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_busco AS t (draft_id, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, internal_stop_codon_count, internal_stop_codon_percent)
  SELECT g.draft_id, p.complete, p.single_copy, p.multi_copy, p.fragmented, p.missing, p.n_markers, p.domain, p.number_of_scaffolds, p.number_of_contigs, p.total_length, p.percent_gaps, p.scaffold_n50, p.contigs_n50, p.internal_stop_codon_count, p.internal_stop_codon_percent
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.complete, p.single_copy, p.multi_copy, p.fragmented, p.missing, p.n_markers, p.domain, p.number_of_scaffolds, p.number_of_contigs, p.total_length, p.percent_gaps, p.scaffold_n50, p.contigs_n50, p.internal_stop_codon_count, p.internal_stop_codon_percent) > 0
  ON CONFLICT (draft_id) DO UPDATE SET complete = EXCLUDED.complete, single_copy = EXCLUDED.single_copy, multi_copy = EXCLUDED.multi_copy, fragmented = EXCLUDED.fragmented, missing = EXCLUDED.missing, n_markers = EXCLUDED.n_markers, domain = EXCLUDED.domain, number_of_scaffolds = EXCLUDED.number_of_scaffolds, number_of_contigs = EXCLUDED.number_of_contigs, total_length = EXCLUDED.total_length, percent_gaps = EXCLUDED.percent_gaps, scaffold_n50 = EXCLUDED.scaffold_n50, contigs_n50 = EXCLUDED.contigs_n50, internal_stop_codon_count = EXCLUDED.internal_stop_codon_count, internal_stop_codon_percent = EXCLUDED.internal_stop_codon_percent, loaded_at = now()
    WHERE (t.complete, t.single_copy, t.multi_copy, t.fragmented, t.missing, t.n_markers, t.domain, t.number_of_scaffolds, t.number_of_contigs, t.total_length, t.percent_gaps, t.scaffold_n50, t.contigs_n50, t.internal_stop_codon_count, t.internal_stop_codon_percent) IS DISTINCT FROM (EXCLUDED.complete, EXCLUDED.single_copy, EXCLUDED.multi_copy, EXCLUDED.fragmented, EXCLUDED.missing, EXCLUDED.n_markers, EXCLUDED.domain, EXCLUDED.number_of_scaffolds, EXCLUDED.number_of_contigs, EXCLUDED.total_length, EXCLUDED.percent_gaps, EXCLUDED.scaffold_n50, EXCLUDED.contigs_n50, EXCLUDED.internal_stop_codon_count, EXCLUDED.internal_stop_codon_percent);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_busco upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_merqury x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.unique_k_mers_assembly, p.k_mers_total, p.qv, p.error, p.k_mer_set, p.solid_k_mers, p.total_k_mers, p.completeness) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_merqury deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_merqury AS t (draft_id, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness)
  SELECT g.draft_id, p.unique_k_mers_assembly, p.k_mers_total, p.qv, p.error, p.k_mer_set, p.solid_k_mers, p.total_k_mers, p.completeness
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.unique_k_mers_assembly, p.k_mers_total, p.qv, p.error, p.k_mer_set, p.solid_k_mers, p.total_k_mers, p.completeness) > 0
  ON CONFLICT (draft_id) DO UPDATE SET unique_k_mers_assembly = EXCLUDED.unique_k_mers_assembly, k_mers_total = EXCLUDED.k_mers_total, qv = EXCLUDED.qv, error = EXCLUDED.error, k_mer_set = EXCLUDED.k_mer_set, solid_k_mers = EXCLUDED.solid_k_mers, total_k_mers = EXCLUDED.total_k_mers, completeness = EXCLUDED.completeness, loaded_at = now()
    WHERE (t.unique_k_mers_assembly, t.k_mers_total, t.qv, t.error, t.k_mer_set, t.solid_k_mers, t.total_k_mers, t.completeness) IS DISTINCT FROM (EXCLUDED.unique_k_mers_assembly, EXCLUDED.k_mers_total, EXCLUDED.qv, EXCLUDED.error, EXCLUDED.k_mer_set, EXCLUDED.solid_k_mers, EXCLUDED.total_k_mers, EXCLUDED.completeness);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_merqury upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_gfastats x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.gfa_num_contigs, p.gfa_contig_n50, p.gfa_num_scaffolds, p.gfa_scaffold_n50, p.gfa_largest_scaffold, p.gfa_total_scaffold_length, p.gfa_gc_content_percent) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_gfastats deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_gfastats AS t (draft_id, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent)
  SELECT g.draft_id, p.gfa_num_contigs, p.gfa_contig_n50, p.gfa_num_scaffolds, p.gfa_scaffold_n50, p.gfa_largest_scaffold, p.gfa_total_scaffold_length, p.gfa_gc_content_percent
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.gfa_num_contigs, p.gfa_contig_n50, p.gfa_num_scaffolds, p.gfa_scaffold_n50, p.gfa_largest_scaffold, p.gfa_total_scaffold_length, p.gfa_gc_content_percent) > 0
  ON CONFLICT (draft_id) DO UPDATE SET gfa_num_contigs = EXCLUDED.gfa_num_contigs, gfa_contig_n50 = EXCLUDED.gfa_contig_n50, gfa_num_scaffolds = EXCLUDED.gfa_num_scaffolds, gfa_scaffold_n50 = EXCLUDED.gfa_scaffold_n50, gfa_largest_scaffold = EXCLUDED.gfa_largest_scaffold, gfa_total_scaffold_length = EXCLUDED.gfa_total_scaffold_length, gfa_gc_content_percent = EXCLUDED.gfa_gc_content_percent, loaded_at = now()
    WHERE (t.gfa_num_contigs, t.gfa_contig_n50, t.gfa_num_scaffolds, t.gfa_scaffold_n50, t.gfa_largest_scaffold, t.gfa_total_scaffold_length, t.gfa_gc_content_percent) IS DISTINCT FROM (EXCLUDED.gfa_num_contigs, EXCLUDED.gfa_contig_n50, EXCLUDED.gfa_num_scaffolds, EXCLUDED.gfa_scaffold_n50, EXCLUDED.gfa_largest_scaffold, EXCLUDED.gfa_total_scaffold_length, EXCLUDED.gfa_gc_content_percent);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_gfastats upserted'; changed := n; RETURN NEXT;

  -- Frozen after the first load (owner decision 12).
  IF depthsizer_on THEN
  DELETE FROM v3.draft_depthsizer x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.depmethod, p.adjust, p.readbp, p.mapadjust, p.scdepth, p.estgenomesize) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_depthsizer deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_depthsizer AS t (draft_id, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize)
  SELECT g.draft_id, p.depmethod, p.adjust, p.readbp, p.mapadjust, p.scdepth, p.estgenomesize
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.depmethod, p.adjust, p.readbp, p.mapadjust, p.scdepth, p.estgenomesize) > 0
  ON CONFLICT (draft_id) DO UPDATE SET depmethod = EXCLUDED.depmethod, adjust = EXCLUDED.adjust, readbp = EXCLUDED.readbp, mapadjust = EXCLUDED.mapadjust, scdepth = EXCLUDED.scdepth, estgenomesize = EXCLUDED.estgenomesize, loaded_at = now()
    WHERE (t.depmethod, t.adjust, t.readbp, t.mapadjust, t.scdepth, t.estgenomesize) IS DISTINCT FROM (EXCLUDED.depmethod, EXCLUDED.adjust, EXCLUDED.readbp, EXCLUDED.mapadjust, EXCLUDED.scdepth, EXCLUDED.estgenomesize);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_depthsizer upserted'; changed := n; RETURN NEXT;
  END IF;

  DELETE FROM v3.draft_submission x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.sra_accession, p.biosample_accession, p.study, p.bioproject_accession, p.ena_analysis_accession, p.assembly_accession, p.comment) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_submission deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_submission AS t (draft_id, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment)
  SELECT g.draft_id, p.sra_accession, p.biosample_accession, p.study, p.bioproject_accession, p.ena_analysis_accession, p.assembly_accession, p.comment
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.sra_accession, p.biosample_accession, p.study, p.bioproject_accession, p.ena_analysis_accession, p.assembly_accession, p.comment) > 0
  ON CONFLICT (draft_id) DO UPDATE SET sra_accession = EXCLUDED.sra_accession, biosample_accession = EXCLUDED.biosample_accession, study = EXCLUDED.study, bioproject_accession = EXCLUDED.bioproject_accession, ena_analysis_accession = EXCLUDED.ena_analysis_accession, assembly_accession = EXCLUDED.assembly_accession, comment = EXCLUDED.comment, loaded_at = now()
    WHERE (t.sra_accession, t.biosample_accession, t.study, t.bioproject_accession, t.ena_analysis_accession, t.assembly_accession, t.comment) IS DISTINCT FROM (EXCLUDED.sra_accession, EXCLUDED.biosample_accession, EXCLUDED.study, EXCLUDED.bioproject_accession, EXCLUDED.ena_analysis_accession, EXCLUDED.assembly_accession, EXCLUDED.comment);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_submission upserted'; changed := n; RETURN NEXT;

  -- Run links: derived, so replace what differs.
  CREATE TEMP TABLE IF NOT EXISTS sync_draft_run_want (draft_id bigint, sequencing_id text) ON COMMIT DROP;
  TRUNCATE sync_draft_run_want;
  INSERT INTO sync_draft_run_want
  SELECT DISTINCT g.draft_id, s.sequencing_id
  FROM v3.draft_genome g
  JOIN public.v_sequencing_browse s ON s.og_id = g.og_id AND s.seq_date = g.seq_date
  WHERE s.technology = 'Illumina' AND s.library_type = 'illumina'   -- DNA libraries only (055)
    AND s.instrument = CASE g.mach WHEN 'NOVA' THEN 'NovaSeq' WHEN 'NEXT' THEN 'NextSeq' END;

  DELETE FROM v3.draft_genome_run r
  WHERE NOT EXISTS (SELECT 1 FROM sync_draft_run_want w
                    WHERE (w.draft_id, w.sequencing_id) = (r.draft_id, r.sequencing_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.draft_genome_run (draft_id, sequencing_id)
  SELECT draft_id, sequencing_id FROM sync_draft_run_want
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link inserted'; changed := n; RETURN NEXT;
END
$function$
;

CREATE OR REPLACE FUNCTION v3.sync_mito()
 RETURNS TABLE(step text, changed bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  n       bigint;
  unpivot text;
BEGIN
  -- Assemblies: delete what public no longer has (cascades), upsert the rest.
  DELETE FROM v3.mito_assembly a
  WHERE NOT EXISTS (SELECT 1 FROM public.mitogenome_data m
                    WHERE (m.og_id, m.tech, m.seq_date, m.code) = (a.og_id, a.tech, a.seq_date, a.code));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_assembly AS t (og_id, tech, seq_date, code, stats, length, avg_coverage, avg_base_coverage)
  SELECT og_id, tech, seq_date, code, stats, length, avg_coverage, avg_base_coverage
  FROM public.mitogenome_data
  ON CONFLICT (og_id, tech, seq_date, code) DO UPDATE
    SET stats = EXCLUDED.stats, length = EXCLUDED.length, avg_coverage = EXCLUDED.avg_coverage,
        avg_base_coverage = EXCLUDED.avg_base_coverage, updated_at = now()
    WHERE (t.stats, t.length, t.avg_coverage, t.avg_base_coverage)
          IS DISTINCT FROM (EXCLUDED.stats, EXCLUDED.length, EXCLUDED.avg_coverage, EXCLUDED.avg_base_coverage);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly upserted'; changed := n; RETURN NEXT;

  -- Depth: a row wherever public has a depth_method.
  DELETE FROM v3.mito_assembly_depth d
  USING v3.mito_assembly a JOIN public.mitogenome_data m USING (og_id, tech, seq_date, code)
  WHERE d.assembly_id = a.assembly_id AND m.depth_method IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'depth deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_assembly_depth AS t (assembly_id, depth_method, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_measured_at)
  SELECT a.assembly_id, m.depth_method, m.mean_depth, m.median_depth, m.depth_sd, m.depth_cv, m.breadth_1x, m.breadth_10x, m.mito_mapped_reads, m.total_reads, m.mito_read_fraction, m.depth_target_length_bp, m.depth_target_fasta, m.depth_measured_at
  FROM public.mitogenome_data m JOIN v3.mito_assembly a USING (og_id, tech, seq_date, code)
  WHERE m.depth_method IS NOT NULL
  ON CONFLICT (assembly_id) DO UPDATE SET depth_method = EXCLUDED.depth_method, mean_depth = EXCLUDED.mean_depth, median_depth = EXCLUDED.median_depth, depth_sd = EXCLUDED.depth_sd, depth_cv = EXCLUDED.depth_cv, breadth_1x = EXCLUDED.breadth_1x, breadth_10x = EXCLUDED.breadth_10x, mito_mapped_reads = EXCLUDED.mito_mapped_reads, total_reads = EXCLUDED.total_reads, mito_read_fraction = EXCLUDED.mito_read_fraction, depth_target_length_bp = EXCLUDED.depth_target_length_bp, depth_target_fasta = EXCLUDED.depth_target_fasta, depth_measured_at = EXCLUDED.depth_measured_at
    WHERE (t.depth_method, t.mean_depth, t.median_depth, t.depth_sd, t.depth_cv, t.breadth_1x, t.breadth_10x, t.mito_mapped_reads, t.total_reads, t.mito_read_fraction, t.depth_target_length_bp, t.depth_target_fasta, t.depth_measured_at)
            IS DISTINCT FROM (EXCLUDED.depth_method, EXCLUDED.mean_depth, EXCLUDED.median_depth, EXCLUDED.depth_sd, EXCLUDED.depth_cv, EXCLUDED.breadth_1x, EXCLUDED.breadth_10x, EXCLUDED.mito_mapped_reads, EXCLUDED.total_reads, EXCLUDED.mito_read_fraction, EXCLUDED.depth_target_length_bp, EXCLUDED.depth_target_fasta, EXCLUDED.depth_measured_at);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'depth upserted'; changed := n; RETURN NEXT;

  -- Assembly QC verdict (068): a row wherever public has any part of it.
  DELETE FROM v3.mito_assembly_qc q
  USING v3.mito_assembly a JOIN public.mitogenome_data m USING (og_id, tech, seq_date, code)
  WHERE q.assembly_id = a.assembly_id AND num_nonnulls(m.qc_status, m.manual_review_reason, m.numt_flag, m.frameshift_flag, m.reference_species, m.reference_accession) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly qc deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_assembly_qc AS t (assembly_id, qc_status, manual_review_reason, numt_flag, frameshift_flag, reference_species, reference_accession, qc_updated_at)
  SELECT a.assembly_id, m.qc_status, m.manual_review_reason, m.numt_flag, m.frameshift_flag, m.reference_species, m.reference_accession, m.qc_updated_at
  FROM public.mitogenome_data m JOIN v3.mito_assembly a USING (og_id, tech, seq_date, code)
  WHERE num_nonnulls(m.qc_status, m.manual_review_reason, m.numt_flag, m.frameshift_flag, m.reference_species, m.reference_accession) > 0
  ON CONFLICT (assembly_id) DO UPDATE SET qc_status = EXCLUDED.qc_status, manual_review_reason = EXCLUDED.manual_review_reason, numt_flag = EXCLUDED.numt_flag, frameshift_flag = EXCLUDED.frameshift_flag, reference_species = EXCLUDED.reference_species, reference_accession = EXCLUDED.reference_accession, qc_updated_at = EXCLUDED.qc_updated_at
    WHERE (t.qc_status, t.manual_review_reason, t.numt_flag, t.frameshift_flag, t.reference_species, t.reference_accession, t.qc_updated_at)
          IS DISTINCT FROM (EXCLUDED.qc_status, EXCLUDED.manual_review_reason, EXCLUDED.numt_flag, EXCLUDED.frameshift_flag, EXCLUDED.reference_species, EXCLUDED.reference_accession, EXCLUDED.qc_updated_at);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly qc upserted'; changed := n; RETURN NEXT;

  -- Annotations: public holds at most one per assembly, so v3 mirrors exactly that one.
  DELETE FROM v3.mito_annotation n_
  USING v3.mito_assembly a
  WHERE n_.assembly_id = a.assembly_id
    AND NOT EXISTS (SELECT 1 FROM public.mitogenome_data m
                    WHERE (m.og_id, m.tech, m.seq_date, m.code, m.annotation)
                        = (a.og_id, a.tech, a.seq_date, a.code, n_.annotation));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'annotation deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_annotation AS t (assembly_id, annotation, length_emma, cds_no, trna_no, rrna_no, manual_curation_notes, extra_genes, missing_genes, order_correct, passed, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, annotation_stats_version, annotation_updated_at, completeness_profile)
  SELECT a.assembly_id, m.annotation, m.length_emma, m.cds_no, m.trna_no, m.rrna_no, m.manual_curation_notes, m.extra_genes, m.missing_genes, m.order_correct, m.passed, m.trna_advisory, m.order_variant, m.order_deviation, m.annotation_gaps, m.order_variant_taxon_check, m.order_status, m.order_deviation_detail, m.expected_lineage_genes, m.missing_expected_lineage_genes, m.lineage_gene_advisories, m.mitos_unmapped_features, m.mitos_known_auxiliary_features, m.duplicate_loci, m.annotation_integrity_status, m.annotation_integrity_issues, m.annotation_stats_version, m.annotation_updated_at, m.completeness_profile
  FROM public.mitogenome_data m JOIN v3.mito_assembly a USING (og_id, tech, seq_date, code)
  WHERE m.annotation IS NOT NULL
  ON CONFLICT (assembly_id, annotation) DO UPDATE SET length_emma = EXCLUDED.length_emma, cds_no = EXCLUDED.cds_no, trna_no = EXCLUDED.trna_no, rrna_no = EXCLUDED.rrna_no, manual_curation_notes = EXCLUDED.manual_curation_notes, extra_genes = EXCLUDED.extra_genes, missing_genes = EXCLUDED.missing_genes, order_correct = EXCLUDED.order_correct, passed = EXCLUDED.passed, trna_advisory = EXCLUDED.trna_advisory, order_variant = EXCLUDED.order_variant, order_deviation = EXCLUDED.order_deviation, annotation_gaps = EXCLUDED.annotation_gaps, order_variant_taxon_check = EXCLUDED.order_variant_taxon_check, order_status = EXCLUDED.order_status, order_deviation_detail = EXCLUDED.order_deviation_detail, expected_lineage_genes = EXCLUDED.expected_lineage_genes, missing_expected_lineage_genes = EXCLUDED.missing_expected_lineage_genes, lineage_gene_advisories = EXCLUDED.lineage_gene_advisories, mitos_unmapped_features = EXCLUDED.mitos_unmapped_features, mitos_known_auxiliary_features = EXCLUDED.mitos_known_auxiliary_features, duplicate_loci = EXCLUDED.duplicate_loci, annotation_integrity_status = EXCLUDED.annotation_integrity_status, annotation_integrity_issues = EXCLUDED.annotation_integrity_issues, annotation_stats_version = EXCLUDED.annotation_stats_version, annotation_updated_at = EXCLUDED.annotation_updated_at, completeness_profile = EXCLUDED.completeness_profile, updated_at = now()
    WHERE (t.length_emma, t.cds_no, t.trna_no, t.rrna_no, t.manual_curation_notes, t.extra_genes, t.missing_genes, t.order_correct, t.passed, t.trna_advisory, t.order_variant, t.order_deviation, t.annotation_gaps, t.order_variant_taxon_check, t.order_status, t.order_deviation_detail, t.expected_lineage_genes, t.missing_expected_lineage_genes, t.lineage_gene_advisories, t.mitos_unmapped_features, t.mitos_known_auxiliary_features, t.duplicate_loci, t.annotation_integrity_status, t.annotation_integrity_issues, t.annotation_stats_version, t.annotation_updated_at, t.completeness_profile)
            IS DISTINCT FROM (EXCLUDED.length_emma, EXCLUDED.cds_no, EXCLUDED.trna_no, EXCLUDED.rrna_no, EXCLUDED.manual_curation_notes, EXCLUDED.extra_genes, EXCLUDED.missing_genes, EXCLUDED.order_correct, EXCLUDED.passed, EXCLUDED.trna_advisory, EXCLUDED.order_variant, EXCLUDED.order_deviation, EXCLUDED.annotation_gaps, EXCLUDED.order_variant_taxon_check, EXCLUDED.order_status, EXCLUDED.order_deviation_detail, EXCLUDED.expected_lineage_genes, EXCLUDED.missing_expected_lineage_genes, EXCLUDED.lineage_gene_advisories, EXCLUDED.mitos_unmapped_features, EXCLUDED.mitos_known_auxiliary_features, EXCLUDED.duplicate_loci, EXCLUDED.annotation_integrity_status, EXCLUDED.annotation_integrity_issues, EXCLUDED.annotation_stats_version, EXCLUDED.annotation_updated_at, EXCLUDED.completeness_profile);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'annotation upserted'; changed := n; RETURN NEXT;

  -- Genes: unpivot the legacy columns. The list is fixed: the 39 genes public has columns for.
  CREATE TEMP TABLE IF NOT EXISTS sync_mito_gene_want
    (annotation_id bigint, gene text, length integer, translated_length integer) ON COMMIT DROP;
  TRUNCATE sync_mito_gene_want;
  INSERT INTO sync_mito_gene_want
  SELECT n_.annotation_id, x.gene, x.len, x.tlen
  FROM public.mitogenome_data m
  JOIN v3.mito_assembly a USING (og_id, tech, seq_date, code)
  JOIN v3.mito_annotation n_ ON n_.assembly_id = a.assembly_id AND n_.annotation = m.annotation
  CROSS JOIN LATERAL (VALUES
        ('rrna12s', m.rrna12s, NULL::integer),
        ('rrna16s', m.rrna16s, NULL::integer),
        ('atp6', m.atp6, m.atp6_trans),
        ('atp8', m.atp8, m.atp8_trans),
        ('cox1', m.cox1, m.cox1_trans),
        ('cox2', m.cox2, m.cox2_trans),
        ('cox3', m.cox3, m.cox3_trans),
        ('cytb', m.cytb, m.cytb_trans),
        ('nad1', m.nad1, m.nad1_trans),
        ('nad2', m.nad2, m.nad2_trans),
        ('nad3', m.nad3, m.nad3_trans),
        ('nad4', m.nad4, m.nad4_trans),
        ('nad4l', m.nad4l, m.nad4l_trans),
        ('nad5', m.nad5, m.nad5_trans),
        ('nad6', m.nad6, m.nad6_trans),
        ('trna_phe', m.trna_phe, NULL::integer),
        ('trna_val', m.trna_val, NULL::integer),
        ('trna_leuuag', m.trna_leuuag, NULL::integer),
        ('trna_leuuaa', m.trna_leuuaa, NULL::integer),
        ('trna_ile', m.trna_ile, NULL::integer),
        ('trna_met', m.trna_met, NULL::integer),
        ('trna_thr', m.trna_thr, NULL::integer),
        ('trna_pro', m.trna_pro, NULL::integer),
        ('trna_lys', m.trna_lys, NULL::integer),
        ('trna_asp', m.trna_asp, NULL::integer),
        ('trna_glu', m.trna_glu, NULL::integer),
        ('trna_sergcu', m.trna_sergcu, NULL::integer),
        ('trna_seruga', m.trna_seruga, NULL::integer),
        ('trna_tyr', m.trna_tyr, NULL::integer),
        ('trna_cys', m.trna_cys, NULL::integer),
        ('trna_trp', m.trna_trp, NULL::integer),
        ('trna_ala', m.trna_ala, NULL::integer),
        ('trna_asn', m.trna_asn, NULL::integer),
        ('trna_gly', m.trna_gly, NULL::integer),
        ('trna_arg', m.trna_arg, NULL::integer),
        ('trna_his', m.trna_his, NULL::integer),
        ('trna_gln', m.trna_gln, NULL::integer),
        ('atp9', m.atp9, m.atp9_trans),
        ('mtmuts', m.mtmuts, m.mtmuts_trans)
  ) AS x (gene, len, tlen)
  WHERE num_nonnulls(x.len, x.tlen) > 0;

  DELETE FROM v3.mito_annotation_gene g
  WHERE NOT EXISTS (SELECT 1 FROM sync_mito_gene_want w
                    WHERE (w.annotation_id, w.gene) = (g.annotation_id, g.gene));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'gene deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_annotation_gene AS t (annotation_id, gene, length, translated_length)
  SELECT annotation_id, gene, length, translated_length FROM sync_mito_gene_want
  ON CONFLICT (annotation_id, gene) DO UPDATE
    SET length = EXCLUDED.length, translated_length = EXCLUDED.translated_length
    WHERE (t.length, t.translated_length) IS DISTINCT FROM (EXCLUDED.length, EXCLUDED.translated_length);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'gene upserted'; changed := n; RETURN NEXT;

  -- Run links: derived, so replace what differs.
  CREATE TEMP TABLE IF NOT EXISTS sync_mito_run_want (assembly_id bigint, sequencing_id text) ON COMMIT DROP;
  TRUNCATE sync_mito_run_want;
  INSERT INTO sync_mito_run_want
  SELECT DISTINCT a.assembly_id, s.sequencing_id
  FROM v3.mito_assembly a
  JOIN public.v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
  -- DNA libraries only (055): technology alone let an RNA Kinnex library through for hifi.
  WHERE (a.tech = 'ilmn' AND s.technology = 'Illumina' AND s.library_type = 'illumina'
                         AND s.instrument IS DISTINCT FROM 'iSEQ')
     OR (a.tech = 'hic'  AND s.technology = 'Hi-C' AND s.library_type = 'hic')
     OR (a.tech = 'hifi' AND s.technology LIKE 'PacBio%' AND s.library_type = 'pacbio');

  DELETE FROM v3.mito_assembly_run r
  WHERE NOT EXISTS (SELECT 1 FROM sync_mito_run_want w
                    WHERE (w.assembly_id, w.sequencing_id) = (r.assembly_id, r.sequencing_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_assembly_run (assembly_id, sequencing_id)
  SELECT assembly_id, sequencing_id FROM sync_mito_run_want
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link inserted'; changed := n; RETURN NEXT;
END
$function$
;

CREATE OR REPLACE FUNCTION v3.sync_sequencing_run()
 RETURNS TABLE(step text, changed bigint)
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  n bigint;
BEGIN
  DELETE FROM v3.sequencing_run r
  WHERE NOT EXISTS (SELECT 1 FROM public.sequencing s WHERE s.run_id = r.run_id);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.sequencing_run AS t (run_id, mach, run_seq_date, initial, instrument, run_date)
  SELECT s.run_id,
         substring(s.run_id FROM '^([A-Za-z-]+)_[0-9]{6}_.+$'),
         substring(s.run_id FROM '^[A-Za-z-]+_([0-9]{6})_.+$'),
         substring(s.run_id FROM '^[A-Za-z-]+_[0-9]{6}_(.+)$'),
         CASE WHEN count(DISTINCT s.instrument) = 1 AND count(s.instrument) = count(*) THEN min(s.instrument) END,
         CASE WHEN count(DISTINCT s.run_date)   = 1 AND count(s.run_date)   = count(*) THEN min(s.run_date)   END
  FROM public.sequencing s
  WHERE s.run_id IS NOT NULL AND s.run_id <> ''
  GROUP BY s.run_id
  ON CONFLICT (run_id) DO UPDATE
    SET mach = EXCLUDED.mach, run_seq_date = EXCLUDED.run_seq_date, initial = EXCLUDED.initial,
        instrument = EXCLUDED.instrument, run_date = EXCLUDED.run_date, updated_at = now()
    WHERE (t.mach, t.run_seq_date, t.initial, t.instrument, t.run_date)
          IS DISTINCT FROM (EXCLUDED.mach, EXCLUDED.run_seq_date, EXCLUDED.initial,
                            EXCLUDED.instrument, EXCLUDED.run_date);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run upserted'; changed := n; RETURN NEXT;
END
$function$
;

COMMENT ON FUNCTION v3.check_draft() IS 'Phase R window only: v3 draft tables against public, by key and value. Every problems value must be 0. Dropped at the R.6 merge.';
COMMENT ON FUNCTION v3.check_mito() IS 'Phase R window only: v3 against public, by key and value. Every problems value must be 0, except selected annotations once someone has chosen one. Dropped at the R.6 merge.';
COMMENT ON FUNCTION v3.sync_draft() IS 'Phase R window only: copy public.draft_genomes into the v3 tables, keyed on (og_id, seq_date). Loads draft_depthsizer only while it is empty. Dropped at the R.6 merge.';
COMMENT ON FUNCTION v3.sync_mito() IS 'Phase R window only: copy public.mitogenome_data into the v3 tables, keyed on natural keys. Run nightly by scripts/sync_v3.sh. Dropped at the R.6 merge.';
COMMENT ON FUNCTION v3.sync_sequencing_run() IS 'Phase R window only: derive v3.sequencing_run from public.sequencing. Dropped at the R.6 merge.';

-- Anything written after 072 went to the new tables only, so after a revert they differ from
-- the old tables by exactly those writes. Report it; do not fail.
DO $chk$
DECLARE r record;
BEGIN
  FOR r IN SELECT 'mito' AS side, * FROM v3.check_mito() WHERE problems <> 0
           UNION ALL SELECT 'draft', * FROM v3.check_draft() WHERE problems <> 0 LOOP
    RAISE WARNING 'revert 072: %: % row(s) in "%": writes made after the merge, held only in v3',
      r.side, r.problems, r.check_name;
  END LOOP;
END
$chk$;

COMMIT;
