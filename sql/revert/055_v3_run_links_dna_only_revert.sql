-- 055_v3_run_links_dna_only_revert.sql -- restore 051/052's run-link rules (technology only).
--
-- The function bodies are 051's and 052's, verbatim. The sync then re-adds any link the
-- looser rule allows (the RNA Kinnex link for one hifi assembly).
--
-- After running this, delete 055's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '055_v3_run_links_dna_only.sql';

BEGIN;

CREATE OR REPLACE FUNCTION v3.sync_mito() RETURNS TABLE (step text, changed bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
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

  -- Annotations: public holds at most one per assembly, so v3 mirrors exactly that one.
  DELETE FROM v3.mito_annotation n_
  USING v3.mito_assembly a
  WHERE n_.assembly_id = a.assembly_id
    AND NOT EXISTS (SELECT 1 FROM public.mitogenome_data m
                    WHERE (m.og_id, m.tech, m.seq_date, m.code, m.annotation)
                        = (a.og_id, a.tech, a.seq_date, a.code, n_.annotation));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'annotation deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_annotation AS t (assembly_id, annotation, length_emma, cds_no, trna_no, rrna_no, manual_curation_notes, extra_genes, missing_genes, order_correct, passed, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, annotation_stats_version, annotation_updated_at)
  SELECT a.assembly_id, m.annotation, m.length_emma, m.cds_no, m.trna_no, m.rrna_no, m.manual_curation_notes, m.extra_genes, m.missing_genes, m.order_correct, m.passed, m.trna_advisory, m.order_variant, m.order_deviation, m.annotation_gaps, m.order_variant_taxon_check, m.order_status, m.order_deviation_detail, m.expected_lineage_genes, m.missing_expected_lineage_genes, m.lineage_gene_advisories, m.mitos_unmapped_features, m.mitos_known_auxiliary_features, m.duplicate_loci, m.annotation_integrity_status, m.annotation_integrity_issues, m.annotation_stats_version, m.annotation_updated_at
  FROM public.mitogenome_data m JOIN v3.mito_assembly a USING (og_id, tech, seq_date, code)
  WHERE m.annotation IS NOT NULL
  ON CONFLICT (assembly_id, annotation) DO UPDATE SET length_emma = EXCLUDED.length_emma, cds_no = EXCLUDED.cds_no, trna_no = EXCLUDED.trna_no, rrna_no = EXCLUDED.rrna_no, manual_curation_notes = EXCLUDED.manual_curation_notes, extra_genes = EXCLUDED.extra_genes, missing_genes = EXCLUDED.missing_genes, order_correct = EXCLUDED.order_correct, passed = EXCLUDED.passed, trna_advisory = EXCLUDED.trna_advisory, order_variant = EXCLUDED.order_variant, order_deviation = EXCLUDED.order_deviation, annotation_gaps = EXCLUDED.annotation_gaps, order_variant_taxon_check = EXCLUDED.order_variant_taxon_check, order_status = EXCLUDED.order_status, order_deviation_detail = EXCLUDED.order_deviation_detail, expected_lineage_genes = EXCLUDED.expected_lineage_genes, missing_expected_lineage_genes = EXCLUDED.missing_expected_lineage_genes, lineage_gene_advisories = EXCLUDED.lineage_gene_advisories, mitos_unmapped_features = EXCLUDED.mitos_unmapped_features, mitos_known_auxiliary_features = EXCLUDED.mitos_known_auxiliary_features, duplicate_loci = EXCLUDED.duplicate_loci, annotation_integrity_status = EXCLUDED.annotation_integrity_status, annotation_integrity_issues = EXCLUDED.annotation_integrity_issues, annotation_stats_version = EXCLUDED.annotation_stats_version, annotation_updated_at = EXCLUDED.annotation_updated_at, updated_at = now()
    WHERE (t.length_emma, t.cds_no, t.trna_no, t.rrna_no, t.manual_curation_notes, t.extra_genes, t.missing_genes, t.order_correct, t.passed, t.trna_advisory, t.order_variant, t.order_deviation, t.annotation_gaps, t.order_variant_taxon_check, t.order_status, t.order_deviation_detail, t.expected_lineage_genes, t.missing_expected_lineage_genes, t.lineage_gene_advisories, t.mitos_unmapped_features, t.mitos_known_auxiliary_features, t.duplicate_loci, t.annotation_integrity_status, t.annotation_integrity_issues, t.annotation_stats_version, t.annotation_updated_at)
            IS DISTINCT FROM (EXCLUDED.length_emma, EXCLUDED.cds_no, EXCLUDED.trna_no, EXCLUDED.rrna_no, EXCLUDED.manual_curation_notes, EXCLUDED.extra_genes, EXCLUDED.missing_genes, EXCLUDED.order_correct, EXCLUDED.passed, EXCLUDED.trna_advisory, EXCLUDED.order_variant, EXCLUDED.order_deviation, EXCLUDED.annotation_gaps, EXCLUDED.order_variant_taxon_check, EXCLUDED.order_status, EXCLUDED.order_deviation_detail, EXCLUDED.expected_lineage_genes, EXCLUDED.missing_expected_lineage_genes, EXCLUDED.lineage_gene_advisories, EXCLUDED.mitos_unmapped_features, EXCLUDED.mitos_known_auxiliary_features, EXCLUDED.duplicate_loci, EXCLUDED.annotation_integrity_status, EXCLUDED.annotation_integrity_issues, EXCLUDED.annotation_stats_version, EXCLUDED.annotation_updated_at);
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
  WHERE (a.tech = 'ilmn' AND s.technology = 'Illumina' AND s.instrument IS DISTINCT FROM 'iSEQ')
     OR (a.tech = 'hic'  AND s.technology = 'Hi-C')
     OR (a.tech = 'hifi' AND s.technology LIKE 'PacBio%');

  DELETE FROM v3.mito_assembly_run r
  WHERE NOT EXISTS (SELECT 1 FROM sync_mito_run_want w
                    WHERE (w.assembly_id, w.sequencing_id) = (r.assembly_id, r.sequencing_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_assembly_run (assembly_id, sequencing_id)
  SELECT assembly_id, sequencing_id FROM sync_mito_run_want
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link inserted'; changed := n; RETURN NEXT;
END
$fn$;

CREATE OR REPLACE FUNCTION v3.sync_draft() RETURNS TABLE (step text, changed bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
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
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_genomescope deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_genomescope AS t (draft_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, homozygosity_min, heterozygosity_min, genomesize_min, repeatsize_min, uniquesize_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction)
  SELECT g.draft_id, p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction) > 0
  ON CONFLICT (draft_id) DO UPDATE SET homozygosity = EXCLUDED.homozygosity, heterozygosity = EXCLUDED.heterozygosity, genomesize = EXCLUDED.genomesize, repeatsize = EXCLUDED.repeatsize, uniquesize = EXCLUDED.uniquesize, modelfit = EXCLUDED.modelfit, errorrate = EXCLUDED.errorrate, homozygosity_min = EXCLUDED.homozygosity_min, heterozygosity_min = EXCLUDED.heterozygosity_min, genomesize_min = EXCLUDED.genomesize_min, repeatsize_min = EXCLUDED.repeatsize_min, uniquesize_min = EXCLUDED.uniquesize_min, modelfit_allkmers = EXCLUDED.modelfit_allkmers, genome_size_reliable = EXCLUDED.genome_size_reliable, genome_size_flags = EXCLUDED.genome_size_flags, kmercov = EXCLUDED.kmercov, lambda_depth = EXCLUDED.lambda_depth, host_assembly_size = EXCLUDED.host_assembly_size, host_assembly_fraction = EXCLUDED.host_assembly_fraction, loaded_at = now()
    WHERE (t.homozygosity, t.heterozygosity, t.genomesize, t.repeatsize, t.uniquesize, t.modelfit, t.errorrate, t.homozygosity_min, t.heterozygosity_min, t.genomesize_min, t.repeatsize_min, t.uniquesize_min, t.modelfit_allkmers, t.genome_size_reliable, t.genome_size_flags, t.kmercov, t.lambda_depth, t.host_assembly_size, t.host_assembly_fraction) IS DISTINCT FROM (EXCLUDED.homozygosity, EXCLUDED.heterozygosity, EXCLUDED.genomesize, EXCLUDED.repeatsize, EXCLUDED.uniquesize, EXCLUDED.modelfit, EXCLUDED.errorrate, EXCLUDED.homozygosity_min, EXCLUDED.heterozygosity_min, EXCLUDED.genomesize_min, EXCLUDED.repeatsize_min, EXCLUDED.uniquesize_min, EXCLUDED.modelfit_allkmers, EXCLUDED.genome_size_reliable, EXCLUDED.genome_size_flags, EXCLUDED.kmercov, EXCLUDED.lambda_depth, EXCLUDED.host_assembly_size, EXCLUDED.host_assembly_fraction);
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
  WHERE s.technology = 'Illumina'
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
$fn$;

CREATE OR REPLACE FUNCTION v3.draft_genome_run_illumina_only() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  tech text;
BEGIN
  SELECT s.technology INTO tech FROM public.sequencing s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS DISTINCT FROM 'Illumina' THEN
    RAISE EXCEPTION 'draft_genome_run: % is % sequencing, not Illumina; a draft genome is an '
      'Illumina assembly', NEW.sequencing_id, coalesce(tech, 'unknown');
  END IF;
  RETURN NEW;
END
$fn$;

SELECT * FROM v3.sync_mito() WHERE step LIKE 'run link%';

COMMIT;
