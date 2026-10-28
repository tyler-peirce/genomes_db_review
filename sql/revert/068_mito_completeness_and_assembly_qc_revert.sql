-- 068_mito_completeness_and_assembly_qc_revert.sql -- back to 067: v3.mitogenome_data,
-- sync_mito() and check_mito() as 056 and 055 left them, without completeness_profile and the
-- assembly QC verdict.
--
-- Drops the eight new public.mitogenome_data columns WITH THEIR VALUES, and v3.mito_assembly_qc;
-- restore them from the pre-068 dump if needed.
--
-- After running this, delete 068's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '068_mito_completeness_and_assembly_qc.sql';

BEGIN;

DROP VIEW IF EXISTS v3.mitogenome_data;

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
$fn$;

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
$fn$;
COMMENT ON FUNCTION v3.check_mito() IS
  'Phase R window only: v3 against public, by key and value. Every problems value must be 0, '
  'except selected annotations once someone has chosen one. Dropped at the R.6 merge.';

DROP TABLE IF EXISTS v3.mito_assembly_qc;
ALTER TABLE v3.mito_annotation DROP CONSTRAINT IF EXISTS mito_annotation_completeness_profile_check;
ALTER TABLE v3.mito_annotation DROP COLUMN IF EXISTS completeness_profile;

ALTER TABLE public.mitogenome_data DROP CONSTRAINT IF EXISTS mitogenome_data_completeness_profile_check;
ALTER TABLE public.mitogenome_data DROP CONSTRAINT IF EXISTS mitogenome_data_qc_status_check;
ALTER TABLE public.mitogenome_data
  DROP COLUMN IF EXISTS completeness_profile,
  DROP COLUMN IF EXISTS qc_status,
  DROP COLUMN IF EXISTS manual_review_reason,
  DROP COLUMN IF EXISTS numt_flag,
  DROP COLUMN IF EXISTS frameshift_flag,
  DROP COLUMN IF EXISTS reference_species,
  DROP COLUMN IF EXISTS reference_accession,
  DROP COLUMN IF EXISTS qc_updated_at;

CREATE VIEW v3.mitogenome_data AS
SELECT
       -- identification
       s.og_num,
       a.og_id,
       s.nominal_species_id,
       a.tech,
       a.seq_date,
       a.code,
       n.annotation,
       -- assembly
       a.stats,
       a.length,
       -- depth and coverage
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
       -- annotation summary
       n.length_emma,
       n.cds_no,
       n.trna_no,
       n.rrna_no,
       n.passed,
       -- gene content
       n.missing_genes,
       n.extra_genes,
       n.duplicate_loci,
       n.annotation_gaps,
       n.trna_advisory,
       -- gene order
       n.order_correct,
       n.order_status,
       n.order_variant,
       n.order_variant_taxon_check,
       n.order_deviation,
       n.order_deviation_detail,
       -- lineage
       n.expected_lineage_genes,
       n.missing_expected_lineage_genes,
       n.lineage_gene_advisories,
       -- MITOS features
       n.mitos_unmapped_features,
       n.mitos_known_auxiliary_features,
       -- integrity
       n.annotation_integrity_status,
       n.annotation_integrity_issues,
       -- curation and provenance
       n.manual_curation_notes,
       n.annotation_stats_version,
       n.annotation_updated_at,
       -- rRNA
       g.rrna12s,
       g.rrna16s,
       -- protein-coding, each beside its translated length
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
       -- tRNA
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
FROM v3.mito_assembly a
JOIN public.sample s ON s.og_id = a.og_id
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
  'Compatibility view: the 102 kept columns of the old mitogenome_data table plus og_num and '
  'nominal_species_id, grouped by output (056). Read by column name, not position. One row per '
  '(assembly, annotation), plus one per unannotated assembly. Not a write path.';
GRANT SELECT ON v3.mitogenome_data TO readonly;
GRANT SELECT ON v3.mitogenome_data TO oceangenom_web;

COMMIT;
