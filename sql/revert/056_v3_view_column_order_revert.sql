-- Revert 056_v3_view_column_order.sql.
--
-- Recreates the five hand-written v3 mito and draft views, rebuild_mito_gene_views(),
-- check_mito() and check_draft() as 051_v3_mitogenome.sql and 052_v3_draft_genome.sql wrote
-- them: the old tables' column order, no nominal_species_id, the DepthSizer columns back in
-- draft_genomes and the coverage columns back in mitogenome_submission_view. The bodies below
-- are 051's and 052's, unchanged. Like the other files in sql/revert/ this does not touch the
-- ledger; afterwards remove the row by hand:
--
--     DELETE FROM schema_migrations WHERE filename = '056_v3_view_column_order.sql';

BEGIN;

DROP VIEW IF EXISTS v3.mitogenome_data;
DROP VIEW IF EXISTS v3.mitogenome_submission_view;
DROP VIEW IF EXISTS v3.draft_genomes;
DROP VIEW IF EXISTS v3.v_genome_size_comparison;
DROP VIEW IF EXISTS v3.v_draft_genome_status;

-- 051 ---------------------------------------------------------------------------------------

CREATE VIEW v3.mitogenome_data AS
SELECT
       a.og_id,
       a.tech,
       a.seq_date,
       a.code,
       a.stats,
       a.length,
       n.length_emma,
       n.cds_no,
       n.trna_no,
       n.rrna_no,
       g.rrna12s,
       g.rrna16s,
       g.atp6,
       g.atp8,
       g.cox1,
       g.cox2,
       g.cox3,
       g.cytb,
       g.nad1,
       g.nad2,
       g.nad3,
       g.nad4,
       g.nad4l,
       g.nad5,
       g.nad6,
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
       g.trna_gln,
       n.manual_curation_notes,
       n.annotation,
       a.avg_coverage,
       a.avg_base_coverage,
       g.atp6_trans,
       g.atp8_trans,
       g.cox1_trans,
       g.cox2_trans,
       g.cox3_trans,
       g.cytb_trans,
       g.nad1_trans,
       g.nad2_trans,
       g.nad3_trans,
       g.nad4_trans,
       g.nad4l_trans,
       g.nad5_trans,
       g.nad6_trans,
       n.extra_genes,
       n.missing_genes,
       n.order_correct,
       n.passed,
       d.mean_depth,
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
       n.trna_advisory,
       n.order_variant,
       n.order_deviation,
       n.annotation_gaps,
       n.order_variant_taxon_check,
       n.order_status,
       n.order_deviation_detail,
       n.expected_lineage_genes,
       n.missing_expected_lineage_genes,
       n.lineage_gene_advisories,
       n.mitos_unmapped_features,
       n.mitos_known_auxiliary_features,
       n.duplicate_loci,
       n.annotation_integrity_status,
       n.annotation_integrity_issues,
       g.atp9,
       g.atp9_trans,
       g.mtmuts,
       g.mtmuts_trans,
       n.annotation_stats_version,
       n.annotation_updated_at
FROM v3.mito_assembly a
LEFT JOIN v3.mito_annotation n ON n.assembly_id = a.assembly_id
LEFT JOIN v3.mito_assembly_depth d ON d.assembly_id = a.assembly_id
LEFT JOIN (
    SELECT annotation_id,
           max(length) FILTER (WHERE gene = 'rrna12s') AS rrna12s,
           max(length) FILTER (WHERE gene = 'rrna16s') AS rrna16s,
           max(length) FILTER (WHERE gene = 'atp6') AS atp6,
           max(length) FILTER (WHERE gene = 'atp8') AS atp8,
           max(length) FILTER (WHERE gene = 'cox1') AS cox1,
           max(length) FILTER (WHERE gene = 'cox2') AS cox2,
           max(length) FILTER (WHERE gene = 'cox3') AS cox3,
           max(length) FILTER (WHERE gene = 'cytb') AS cytb,
           max(length) FILTER (WHERE gene = 'nad1') AS nad1,
           max(length) FILTER (WHERE gene = 'nad2') AS nad2,
           max(length) FILTER (WHERE gene = 'nad3') AS nad3,
           max(length) FILTER (WHERE gene = 'nad4') AS nad4,
           max(length) FILTER (WHERE gene = 'nad4l') AS nad4l,
           max(length) FILTER (WHERE gene = 'nad5') AS nad5,
           max(length) FILTER (WHERE gene = 'nad6') AS nad6,
           max(length) FILTER (WHERE gene = 'trna_phe') AS trna_phe,
           max(length) FILTER (WHERE gene = 'trna_val') AS trna_val,
           max(length) FILTER (WHERE gene = 'trna_leuuag') AS trna_leuuag,
           max(length) FILTER (WHERE gene = 'trna_leuuaa') AS trna_leuuaa,
           max(length) FILTER (WHERE gene = 'trna_ile') AS trna_ile,
           max(length) FILTER (WHERE gene = 'trna_met') AS trna_met,
           max(length) FILTER (WHERE gene = 'trna_thr') AS trna_thr,
           max(length) FILTER (WHERE gene = 'trna_pro') AS trna_pro,
           max(length) FILTER (WHERE gene = 'trna_lys') AS trna_lys,
           max(length) FILTER (WHERE gene = 'trna_asp') AS trna_asp,
           max(length) FILTER (WHERE gene = 'trna_glu') AS trna_glu,
           max(length) FILTER (WHERE gene = 'trna_sergcu') AS trna_sergcu,
           max(length) FILTER (WHERE gene = 'trna_seruga') AS trna_seruga,
           max(length) FILTER (WHERE gene = 'trna_tyr') AS trna_tyr,
           max(length) FILTER (WHERE gene = 'trna_cys') AS trna_cys,
           max(length) FILTER (WHERE gene = 'trna_trp') AS trna_trp,
           max(length) FILTER (WHERE gene = 'trna_ala') AS trna_ala,
           max(length) FILTER (WHERE gene = 'trna_asn') AS trna_asn,
           max(length) FILTER (WHERE gene = 'trna_gly') AS trna_gly,
           max(length) FILTER (WHERE gene = 'trna_arg') AS trna_arg,
           max(length) FILTER (WHERE gene = 'trna_his') AS trna_his,
           max(length) FILTER (WHERE gene = 'trna_gln') AS trna_gln,
           max(length) FILTER (WHERE gene = 'atp9') AS atp9,
           max(length) FILTER (WHERE gene = 'mtmuts') AS mtmuts,
           max(translated_length) FILTER (WHERE gene = 'atp6') AS atp6_trans,
           max(translated_length) FILTER (WHERE gene = 'atp8') AS atp8_trans,
           max(translated_length) FILTER (WHERE gene = 'cox1') AS cox1_trans,
           max(translated_length) FILTER (WHERE gene = 'cox2') AS cox2_trans,
           max(translated_length) FILTER (WHERE gene = 'cox3') AS cox3_trans,
           max(translated_length) FILTER (WHERE gene = 'cytb') AS cytb_trans,
           max(translated_length) FILTER (WHERE gene = 'nad1') AS nad1_trans,
           max(translated_length) FILTER (WHERE gene = 'nad2') AS nad2_trans,
           max(translated_length) FILTER (WHERE gene = 'nad3') AS nad3_trans,
           max(translated_length) FILTER (WHERE gene = 'nad4') AS nad4_trans,
           max(translated_length) FILTER (WHERE gene = 'nad4l') AS nad4l_trans,
           max(translated_length) FILTER (WHERE gene = 'nad5') AS nad5_trans,
           max(translated_length) FILTER (WHERE gene = 'nad6') AS nad6_trans,
           max(translated_length) FILTER (WHERE gene = 'atp9') AS atp9_trans,
           max(translated_length) FILTER (WHERE gene = 'mtmuts') AS mtmuts_trans
    FROM v3.mito_annotation_gene
    GROUP BY annotation_id
) g ON g.annotation_id = n.annotation_id;
COMMENT ON VIEW v3.mitogenome_data IS
  'Compatibility view: the 102 kept columns of the old mitogenome_data table, in its order. One '
  'row per (assembly, annotation), plus one per unannotated assembly. Not a write path.';

CREATE VIEW v3.mitogenome_submission_view AS
SELECT s.og_num,
       a.og_id, a.tech, a.seq_date, a.code,
       n.annotation,
       a.stats, a.length,
       n.length_emma, n.cds_no, n.trna_no, n.rrna_no,
       a.avg_coverage, a.avg_base_coverage,
       n.extra_genes, n.missing_genes, n.order_correct,
       e.table2asn_status, e.warning_codes, e.webin_status, e.webin_reason, e.submission_ready,
       l.validated_species_name, l.validator
FROM v3.mito_assembly a
LEFT JOIN v3.mito_annotation n ON n.assembly_id = a.assembly_id
LEFT JOIN public.sample s ON s.og_id = a.og_id
LEFT JOIN public.ena_validation_attempts e
       ON e.og_id = a.og_id AND e.tech = a.tech AND e.seq_date = a.seq_date AND e.code = a.code
      AND e.annotation = n.annotation
LEFT JOIN public.lca_validation l
       ON l.og_id = a.og_id AND l.tech = a.tech AND l.seq_date = a.seq_date AND l.code = a.code
      AND l.annotation = n.annotation;
COMMENT ON VIEW v3.mitogenome_submission_view IS
  'mitogenome_submission_view rebuilt on the v3 tables. The ENA and LCA joins move to '
  'annotation_id at R.7.';

CREATE OR REPLACE FUNCTION v3.rebuild_mito_gene_views() RETURNS void
LANGUAGE plpgsql SET search_path = v3, public, pg_temp AS $fn$
DECLARE
  lens  text;
  trans text;
BEGIN
  SELECT string_agg(format('max(g.length) FILTER (WHERE g.gene = %L) AS %I', gene, gene), E',\n       '
                    ORDER BY sort_order)
    INTO lens FROM mito_gene;
  SELECT string_agg(format('max(g.translated_length) FILTER (WHERE g.gene = %L) AS %I', gene, gene || '_trans'),
                    E',\n       ' ORDER BY sort_order)
    INTO trans FROM mito_gene WHERE has_translation;
  -- Dropped and recreated so a new gene can take its place in the column order. Nothing may be
  -- built on this view for that reason.
  DROP VIEW IF EXISTS v_mito_annotation_genes;
  EXECUTE format($v$
    CREATE VIEW v_mito_annotation_genes AS
    SELECT a.og_id, a.tech, a.seq_date, a.code, n.annotation, n.annotation_id, n.is_selected,
       %s,
       %s
    FROM mito_annotation n
    JOIN mito_assembly a ON a.assembly_id = n.assembly_id
    LEFT JOIN mito_annotation_gene g ON g.annotation_id = n.annotation_id
    GROUP BY a.og_id, a.tech, a.seq_date, a.code, n.annotation, n.annotation_id, n.is_selected$v$,
    lens, trans);
  COMMENT ON VIEW v_mito_annotation_genes IS
    'One row per annotation, gene lengths wide. Generated by rebuild_mito_gene_views() from '
    'mito_gene; is_selected is display only. Do not build other views on this one.';
  GRANT SELECT ON v_mito_annotation_genes TO readonly;
END
$fn$;
COMMENT ON FUNCTION v3.rebuild_mito_gene_views() IS
  'Regenerate v_mito_annotation_genes from mito_gene. Run after adding a gene.';

SELECT v3.rebuild_mito_gene_views();

CREATE OR REPLACE FUNCTION v3.check_mito() RETURNS TABLE (check_name text, problems bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  check_name := 'mitogenome_data: v3 rows not in public';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at FROM v3.mitogenome_data
    EXCEPT ALL
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at FROM public.mitogenome_data) x;
  RETURN NEXT;

  check_name := 'mitogenome_data: public rows not in v3';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at FROM public.mitogenome_data
    EXCEPT ALL
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at FROM v3.mitogenome_data) x;
  RETURN NEXT;

  check_name := 'mitogenome_submission_view: differs (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v3.mitogenome_submission_view
                                EXCEPT ALL SELECT * FROM public.mitogenome_submission_view) x)
       + (SELECT count(*) FROM (SELECT * FROM public.mitogenome_submission_view
                                EXCEPT ALL SELECT * FROM v3.mitogenome_submission_view) x)
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
$fn$;
COMMENT ON FUNCTION v3.check_mito() IS
  'Phase R window only: v3 against public, by key and value. Every problems value must be 0, '
  'except selected annotations once someone has chosen one. Dropped at the R.6 merge.';

-- 052 ---------------------------------------------------------------------------------------

CREATE VIEW v3.draft_genomes AS
SELECT
       d.og_id,
       d.mach,
       d.seq_date,
       d.initial,
       f.passed_filter_reads,
       f.low_quality_reads,
       f.too_many_n_reads,
       f.too_short_reads,
       f.too_long_reads,
       f.raw_total_reads,
       f.raw_total_bases,
       f.raw_q20_bases,
       f.raw_q30_bases,
       f.raw_q20_rate,
       f.raw_q30_rate,
       f.raw_read1_mean_length,
       f.raw_read2_mean_length,
       f.raw_gc_content,
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
       gs.heterozygosity,
       gs.genomesize,
       gs.repeatsize,
       gs.uniquesize,
       gs.modelfit,
       gs.errorrate,
       ct.num_contigs_lt_500bp AS num_contigs,
       ti.num_contigs_mitochondrion,
       ti.num_contigs_plastid,
       ti.num_contigs_prokarya,
       ti.bp_mitochondrion,
       ti.bp_plastid,
       ti.bp_prokarya,
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
       mq.unique_k_mers_assembly,
       mq.k_mers_total,
       mq.qv,
       mq.error,
       mq.k_mer_set,
       mq.solid_k_mers,
       mq.total_k_mers,
       mq.completeness,
       ds.depmethod,
       ds.adjust,
       ds.readbp,
       ds.mapadjust,
       ds.scdepth,
       ds.estgenomesize,
       su.sra_accession,
       su.biosample_accession,
       su.study,
       su.bioproject_accession,
       su.ena_analysis_accession,
       su.assembly_accession,
       su.comment,
       d.og_num,
       ct.num_contigs_exclude,
       ct.num_contigs_trim,
       ct.num_contigs_review,
       ct.bp_exclude,
       ct.bp_trim,
       ct.bp_review,
       gf.gfa_num_contigs,
       gf.gfa_contig_n50,
       gf.gfa_num_scaffolds,
       gf.gfa_scaffold_n50,
       gf.gfa_largest_scaffold,
       gf.gfa_total_scaffold_length,
       gf.gfa_gc_content_percent,
       b.internal_stop_codon_percent,
       b.internal_stop_codon_count,
       gs.genomesize_min,
       gs.repeatsize_min,
       gs.uniquesize_min,
       gs.homozygosity_min,
       gs.heterozygosity_min,
       gs.modelfit_allkmers,
       gs.genome_size_reliable,
       gs.genome_size_flags,
       gs.kmercov,
       gs.lambda_depth,
       gs.host_assembly_size,
       gs.host_assembly_fraction
FROM v3.draft_genome d
LEFT JOIN v3.draft_fastp f ON f.draft_id = d.draft_id
LEFT JOIN v3.draft_genomescope gs ON gs.draft_id = d.draft_id
LEFT JOIN v3.draft_tiara ti ON ti.draft_id = d.draft_id
LEFT JOIN v3.draft_contamination ct ON ct.draft_id = d.draft_id
LEFT JOIN v3.draft_busco b ON b.draft_id = d.draft_id
LEFT JOIN v3.draft_merqury mq ON mq.draft_id = d.draft_id
LEFT JOIN v3.draft_gfastats gf ON gf.draft_id = d.draft_id
LEFT JOIN v3.draft_depthsizer ds ON ds.draft_id = d.draft_id
LEFT JOIN v3.draft_submission su ON su.draft_id = d.draft_id;
COMMENT ON VIEW v3.draft_genomes IS
  'Compatibility view: the 103 kept columns of the old draft_genomes table, in its order. '
  'Not a write path.';

CREATE VIEW v3.v_genome_size_comparison AS
SELECT d.og_id,
       d.seq_date,
       sp.species,
       sp.ncbi_taxon_id,
       gs.genomesize AS estimated_bp,
       a.total_sequence_length AS ncbi_bp,
       CASE WHEN a.total_sequence_length > 0
            THEN round(gs.genomesize::numeric / a.total_sequence_length::numeric, 3)
            ELSE NULL::numeric END AS estimated_over_ncbi,
       a.assembly_accession,
       a.assembly_level,
       a.is_refseq,
       a.is_representative
FROM v3.draft_genome d
LEFT JOIN v3.draft_genomescope gs ON gs.draft_id = d.draft_id
JOIN public.sample s ON s.og_id = d.og_id
JOIN public.species sp ON s.nominal_species_id = sp.species
LEFT JOIN public.species_ncbi_assembly a ON a.species = sp.species AND a.is_chosen;

CREATE VIEW v3.v_draft_genome_status AS
SELECT d.og_num, d.og_id, d.seq_date, d.mach,
       (r.n_runs > 0)               AS has_run_link,
       (f.draft_id  IS NOT NULL)    AS has_fastp,
       (gs.draft_id IS NOT NULL)    AS has_genomescope,
       gs.output_set                AS genomescope_output_set,
       (ti.draft_id IS NOT NULL)    AS has_tiara,
       (ct.draft_id IS NOT NULL)    AS has_contamination,
       (b.draft_id  IS NOT NULL)    AS has_busco,
       (mq.draft_id IS NOT NULL)    AS has_merqury,
       (gf.draft_id IS NOT NULL)    AS has_gfastats,
       (su.draft_id IS NOT NULL)    AS has_submission,
       num_nonnulls(f.draft_id, gs.draft_id, ti.draft_id, ct.draft_id, b.draft_id, mq.draft_id,
                    gf.draft_id) AS processes_done,
       (f.draft_id IS NOT NULL AND num_nonnulls(gs.draft_id, ti.draft_id, ct.draft_id, b.draft_id,
                                                mq.draft_id, gf.draft_id) = 0) AS reads_only
FROM v3.draft_genome d
LEFT JOIN LATERAL (SELECT count(*) AS n_runs FROM v3.draft_genome_run x WHERE x.draft_id = d.draft_id) r ON true
LEFT JOIN v3.draft_fastp f          ON f.draft_id  = d.draft_id
LEFT JOIN v3.draft_genomescope gs   ON gs.draft_id = d.draft_id
LEFT JOIN v3.draft_tiara ti         ON ti.draft_id = d.draft_id
LEFT JOIN v3.draft_contamination ct ON ct.draft_id = d.draft_id
LEFT JOIN v3.draft_busco b          ON b.draft_id  = d.draft_id
LEFT JOIN v3.draft_merqury mq       ON mq.draft_id = d.draft_id
LEFT JOIN v3.draft_gfastats gf      ON gf.draft_id = d.draft_id
LEFT JOIN v3.draft_submission su    ON su.draft_id = d.draft_id;
COMMENT ON VIEW v3.v_draft_genome_status IS
  'One row per draft genome: which pipeline processes have results. processes_done counts the '
  'seven pipeline processes (fastp to gfastats); submission is shown but not counted; DepthSizer '
  'is retired and not shown.';

CREATE OR REPLACE FUNCTION v3.check_draft() RETURNS TABLE (check_name text, problems bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  check_name := 'draft_genomes: v3 rows not in public';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction FROM v3.draft_genomes
    EXCEPT ALL
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction FROM public.draft_genomes) x;
  RETURN NEXT;

  check_name := 'draft_genomes: public rows not in v3';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction FROM public.draft_genomes
    EXCEPT ALL
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction FROM v3.draft_genomes) x;
  RETURN NEXT;

  check_name := 'v_genome_size_comparison: differs (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v3.v_genome_size_comparison
                                EXCEPT ALL SELECT * FROM public.v_genome_size_comparison) x)
       + (SELECT count(*) FROM (SELECT * FROM public.v_genome_size_comparison
                                EXCEPT ALL SELECT * FROM v3.v_genome_size_comparison) x)
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
$fn$;
COMMENT ON FUNCTION v3.check_draft() IS
  'Phase R window only: v3 draft tables against public, by key and value. Every problems value '
  'must be 0. Dropped at the R.6 merge.';

GRANT SELECT ON v3.mitogenome_data, v3.mitogenome_submission_view, v3.v_mito_annotation_genes,
                v3.draft_genomes, v3.v_genome_size_comparison, v3.v_draft_genome_status TO readonly;
GRANT SELECT ON v3.mitogenome_data, v3.draft_genomes TO oceangenom_web;

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v3.check_mito() UNION ALL SELECT * FROM v3.check_draft() LOOP
    IF r.problems <> 0 THEN
      RAISE EXCEPTION '056 revert check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
END
$verify$;

COMMIT;
