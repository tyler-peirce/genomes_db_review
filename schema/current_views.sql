-- View: public.blast_filtered_lca
CREATE OR REPLACE VIEW public.blast_filtered_lca AS
 SELECT a.og_id,
    a.tech,
    a.seq_date,
    a.code,
    an.annotation,
    t.match_sequence_id,
    t.taxon_id,
    t.scientific_name,
    t.common_name,
    t.kingdoms,
    t.percent_identity,
    t.alignment_length,
    t.query_length,
    t.subject_length,
    t.mismatch,
    t.gap_open,
    t.gaps,
    t.query_start,
    t.query_end,
    t.subject_start,
    t.subject_end,
    t.subject_title,
    t.evalue,
    t.bit_score,
    t.query_coverage,
    t.subject_coverage,
    t.region,
    t.blast_run_date,
    t.annotation_id
   FROM mito_blast_hit t
     JOIN mito_annotation an ON an.annotation_id = t.annotation_id
     JOIN mito_assembly a ON a.assembly_id = an.assembly_id;;

-- View: public.coverage_summary
CREATE OR REPLACE VIEW public.coverage_summary AS
 WITH hifi_agg AS (
         SELECT hifi_reads_qc.og_id,
            sum(hifi_reads_qc.hifi_yield) AS total_hifi_yield_bp
           FROM hifi_reads_qc hifi_reads_qc
          GROUP BY hifi_reads_qc.og_id
        ), hic_agg AS (
         SELECT hic_reads_qc.og_id,
            sum(hic_reads_qc.yield_gb * 1000000000::numeric)::bigint AS total_hic_yield_bp
           FROM hic_reads_qc hic_reads_qc
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
    round(hic.total_hic_yield_bp::numeric / '1000000000'::numeric, 3) AS total_hic_yield_gb,
    round(hifi.total_hifi_yield_bp / '1000000000'::numeric, 3) AS total_hifi_yield_gb,
        CASE
            WHEN r.genomesize > 0 THEN round(hifi.total_hifi_yield_bp / r.genomesize::numeric, 2)
            ELSE NULL::numeric
        END AS hifi_coverage,
        CASE
            WHEN r.genomesize > 0 THEN round(hic.total_hic_yield_bp::numeric / r.genomesize::numeric, 2)
            ELSE NULL::numeric
        END AS hic_coverage
   FROM all_ogs a
     LEFT JOIN hifi_agg hifi ON hifi.og_id = a.og_id
     LEFT JOIN hic_agg hic ON hic.og_id = a.og_id
     LEFT JOIN raw_qc r ON r.og_id = a.og_id
  ORDER BY a.og_id;;

-- View: public.draft_genomes
CREATE OR REPLACE VIEW public.draft_genomes AS
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
   FROM draft_genome d
     JOIN sample s ON s.og_id = d.og_id
     LEFT JOIN draft_fastp f ON f.draft_id = d.draft_id
     LEFT JOIN draft_genomescope gs ON gs.draft_id = d.draft_id
     LEFT JOIN draft_tiara ti ON ti.draft_id = d.draft_id
     LEFT JOIN draft_contamination ct ON ct.draft_id = d.draft_id
     LEFT JOIN draft_busco b ON b.draft_id = d.draft_id
     LEFT JOIN draft_merqury mq ON mq.draft_id = d.draft_id
     LEFT JOIN draft_gfastats gf ON gf.draft_id = d.draft_id
     LEFT JOIN draft_submission su ON su.draft_id = d.draft_id;;

-- View: public.embargo_assignment_view
CREATE OR REPLACE VIEW public.embargo_assignment_view AS
 SELECT s.og_id,
    regexp_replace(s.og_id, 'OG'::text, ''::text, 'g'::text)::integer AS og_num,
    s.collector,
    s.embargo_status,
    lv1.validated_species_name,
    s.nominal_species_id,
    s.common_name,
    s.field_id,
    s.contact,
    s.date_collected
   FROM sample s
     LEFT JOIN LATERAL ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS validated_species_name
           FROM lca_validation lv
          WHERE lv.og_id = s.og_id) lv1 ON true;;

-- View: public.ena_submission_status
CREATE OR REPLACE VIEW public.ena_submission_status AS
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
           FROM ena_validation_attempts
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
   FROM latest v
     LEFT JOIN ena_submissions s ON s.full_seqid = v.full_seqid AND s.webin_mode = 'production'::text;;

-- View: public.ena_validation_latest
CREATE OR REPLACE VIEW public.ena_validation_latest AS
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
   FROM ena_validation_attempts
  ORDER BY ena_validation_attempts.full_seqid, ena_validation_attempts.recorded_at DESC, ena_validation_attempts.id DESC;;

-- View: public.filtered_lca_view
CREATE OR REPLACE VIEW public.filtered_lca_view AS
 SELECT b.og_id AS og_id_flv,
    b.tech,
    b.seq_date,
    b.code,
    b.annotation,
    string_agg(
        CASE
            WHEN b.region = '12s'::text AND b.scientific_name = lr.nominal_species_id THEN b.match_sequence_id
            ELSE NULL::text
        END, ', '::text ORDER BY b.match_sequence_id) AS filtered_12s,
    string_agg(
        CASE
            WHEN b.region = '16s'::text AND b.scientific_name = lr.nominal_species_id THEN b.match_sequence_id
            ELSE NULL::text
        END, ', '::text ORDER BY b.match_sequence_id) AS filtered_16s,
    string_agg(
        CASE
            WHEN b.region = 'CO1'::text AND b.scientific_name = lr.nominal_species_id THEN b.match_sequence_id
            ELSE NULL::text
        END, ', '::text ORDER BY b.match_sequence_id) AS filtered_co1
   FROM blast_filtered_lca b
     JOIN lca_results_view lr ON b.og_id = lr.og_id_lr AND b.tech = lr.tech AND b.seq_date = lr.seq_date AND b.code = lr.code AND b.annotation = lr.annotation
  GROUP BY b.og_id, b.tech, b.seq_date, b.code, b.annotation;;

-- View: public.goat_project_metadata_v1
CREATE OR REPLACE VIEW public.goat_project_metadata_v1 AS
 SELECT 'Ocean Genomes'::text AS project_name,
    'OG'::text AS project_acronym,
    NULL::text AS subproject_name,
    NULL::text AS bioproject_id,
    'Shannon Corrigan'::text AS primary_contact,
    'Ocean Genomes Minderoo OceanOmics Centre, The University of Western Australia'::text AS primary_contact_institution,
    'oceangenomes@uwa.edu.au'::text AS public_contact_email,
    CURRENT_DATE AS date_of_last_update,
    'ebp_species_goat_3.0'::text AS schema_version;;

-- View: public.goat_species_v1
CREATE OR REPLACE VIEW public.goat_species_v1 AS
 SELECT s.ncbi_taxon_id,
    s.family,
    s.species,
    COALESCE(s.epithet, '-'::text) AS subspecies_epithet,
        CASE
            WHEN s.ncbi_taxon_id = ANY (ARRAY[215367, 182658, 163129, 7793, 582430]) THEN 'priority_target'::text
            ELSE 'potential_target'::text
        END AS target_list_status,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM sample samp
              WHERE samp.nominal_species_id = s.species)) THEN 'sample_collected'::text
            ELSE NULL::text
        END AS sampling_status,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM sample samp
              WHERE samp.nominal_species_id = s.species AND samp.ncbi_bioproject_id_lvl_3_hifi IS NOT NULL)) THEN 'submitted'::text
            WHEN (EXISTS ( SELECT 1
               FROM sample samp
                 JOIN ref_assembly rg ON rg.og_id = samp.og_id
              WHERE samp.nominal_species_id = s.species)) THEN 'in_assembly'::text
            WHEN (EXISTS ( SELECT 1
               FROM summary sm
              WHERE sm.nominal_species_id = s.species AND (sm.pacbio_status = ANY (ARRAY['Library Prep - PacBio SMRTbell'::text, 'QC - Femto'::text, 'Sequenced'::text, 'Sequenced, SRE'::text, 'Sequence - PacBio'::text, 'Shearing'::text, 'SRE'::text, 'SRE - ULI'::text, 'ULI'::text])))) THEN 'in_lab'::text
            ELSE NULL::text
        END AS sequencing_status,
    NULL::text AS genome_publication,
    'Ocean Genomes'::text AS primary_project,
    NULL::text AS ebp_collaborator_acronyms,
    NULL::text AS contributing_project_lab,
        CASE
            WHEN s.species = ANY (ARRAY['Neophoca cinerea'::text, 'Careproctus sp.'::text, 'Lethrinus punctulatus'::text, 'Siphonognathus radiatus'::text, 'Dascyllus aruanus'::text, 'Carcharhinus galapagensis'::text]) THEN 'data_conflict'::text
            ELSE ( SELECT samp.collector
               FROM sample samp
              WHERE samp.nominal_species_id = s.species AND samp.workflow = 'Reference'::text AND samp.collector IS NOT NULL
             LIMIT 1)
        END AS collected_by,
    NULL::text AS priority_flags,
    COALESCE(s.afd_common_name, '-'::text) AS common_name,
    COALESCE(s.synonym, '-'::text) AS synonym,
    NULL::text AS assigned_sequencing_center
   FROM master_species s
  ORDER BY s.family, s.species;;

-- View: public.hic_reads_qc
CREATE OR REPLACE VIEW public.hic_reads_qc AS
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
   FROM hic_read_qc;;

-- View: public.hifi_reads_qc
CREATE OR REPLACE VIEW public.hifi_reads_qc AS
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
   FROM hifi_read_qc;;

-- View: public.lca
CREATE OR REPLACE VIEW public.lca AS
 SELECT a.og_id,
    a.tech,
    a.seq_date,
    a.code,
    an.annotation,
    t.region,
    t.lca_run_date,
    t.species_in_lca,
    t.number_unq_blast_hits,
    t.domain,
    t.phylum,
    t.class,
    t."order",
    t.family,
    t.genus,
    t.specific_epiphet,
    t.species,
    t.scientific_name_authorship,
    t.taxon_rank,
    t.top_taxon_id,
    t.taxon_id_db,
    t.top_accession_id,
    t.accession_id_ref_db,
    t.top_percent_query_cover,
    t.top_percent_query_cover_hsp,
    t.alignment_length,
    t.subject_length,
    t.sequence_length,
    t.top_confidence_score,
    t.top_percent_match,
    t.taxon_rank_db,
    t.content_hash,
    t.annotation_id
   FROM mito_lca t
     JOIN mito_annotation an ON an.annotation_id = t.annotation_id
     JOIN mito_assembly a ON a.assembly_id = an.assembly_id;;

-- View: public.lca_pivot_view
CREATE OR REPLACE VIEW public.lca_pivot_view AS
 SELECT regexp_replace(lca.og_id, 'OG'::text, ''::text, 'g'::text)::integer AS og_num,
    lca.og_id AS og_id_lp,
    lca.tech,
    lca.seq_date,
    lca.code,
    lca.annotation,
    string_agg(DISTINCT t.sp, ', '::text ORDER BY t.sp) FILTER (WHERE lca.region = '12s'::text) COLLATE "default" AS s12_lca,
    string_agg(DISTINCT t.sp, ', '::text ORDER BY t.sp) FILTER (WHERE lca.region = '16s'::text) COLLATE "default" AS s16_lca,
    string_agg(DISTINCT t.sp, ', '::text ORDER BY t.sp) FILTER (WHERE lca.region = 'CO1'::text) COLLATE "default" AS co1_lca
   FROM lca
     LEFT JOIN LATERAL ( SELECT btrim(x.x) COLLATE "C" AS sp
           FROM unnest(string_to_array(lca.species_in_lca, ','::text)) x(x)
          WHERE btrim(x.x) <> ''::text) t ON true
  GROUP BY lca.og_id, lca.tech, lca.seq_date, lca.code, lca.annotation;;

-- View: public.lca_raw_results
CREATE OR REPLACE VIEW public.lca_raw_results AS
 SELECT a.og_id,
    a.tech,
    a.seq_date,
    a.code,
    an.annotation,
    t.sequence_region,
    t.lca_run_date,
    t.domain,
    t.phylum,
    t.class,
    t."order",
    t.family,
    t.genus,
    t.specific_epiphet,
    t.scientific_name,
    t.scientific_name_authorship,
    t.taxon_rank,
    t.taxon_id,
    t.taxon_id_db,
    t.verbatim_identification,
    t.accession_id,
    t.accession_id_ref_db,
    t.percent_match,
    t.percent_query_cover,
    t.percent_query_cover_hsp,
    t.alignment_length,
    t.subject_length,
    t.sequence_length,
    t.confidence_score,
    t.taxon_rank_db,
    t.content_hash,
    t.annotation_id
   FROM mito_lca_raw t
     JOIN mito_annotation an ON an.annotation_id = t.annotation_id
     JOIN mito_assembly a ON a.assembly_id = an.assembly_id;;

-- View: public.lca_results_view
CREATE OR REPLACE VIEW public.lca_results_view AS
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
            WHEN s.nominal_species_id IS NULL THEN 'MISSING NOMINAL ID'::text
            WHEN s.nominal_species_id = ANY ((ARRAY( SELECT split_part(btrim(t.t), ';'::text, 1) AS split_part
               FROM unnest(string_to_array(concat_ws(','::text, lp.s12_lca, lp.s16_lca, lp.co1_lca), ','::text)) t(t)))) THEN s.nominal_species_id
            ELSE 'INVESTIGATE'::text
        END AS validation_status
   FROM lca_pivot_view lp
     JOIN sample s ON lp.og_id_lp = s.og_id;;

-- View: public.lca_validation
CREATE OR REPLACE VIEW public.lca_validation AS
 SELECT a.og_id,
    a.tech,
    t.validated_species_name,
    t.validator,
    t.nominal_species_id_lca_comment,
    t.validator_2,
    t.data_release,
    t.validated_rank,
    t.lca_genus,
    a.seq_date,
    a.code,
    an.annotation,
    t.row_created_on,
    t.annotation_id
   FROM mito_lca_validation t
     JOIN mito_annotation an ON an.annotation_id = t.annotation_id
     JOIN mito_assembly a ON a.assembly_id = an.assembly_id;;

-- View: public.lca_validation_report_view
CREATE OR REPLACE VIEW public.lca_validation_report_view AS
 SELECT regexp_replace(lv.og_id, 'OG'::text, ''::text, 'g'::text)::integer AS og_num,
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
   FROM lca_validation lv
     LEFT JOIN lca_pivot_view lp ON lp.og_id_lp = lv.og_id AND lp.tech = lv.tech AND lp.seq_date = lv.seq_date AND lp.code = lv.code AND lp.annotation = lv.annotation
     LEFT JOIN lca_results_view lr ON lr.og_id_lr = lv.og_id AND lr.tech = lv.tech AND lr.seq_date = lv.seq_date AND lr.code = lv.code AND lr.annotation = lv.annotation
     LEFT JOIN filtered_lca_view flv ON flv.og_id_flv = lv.og_id AND flv.tech = lv.tech AND flv.seq_date = lv.seq_date AND flv.code = lv.code AND flv.annotation = lv.annotation
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
           FROM lca
          GROUP BY lca.og_id, lca.tech, lca.seq_date, lca.code, lca.annotation) lca_tax ON lca_tax.og_id = lv.og_id AND lca_tax.tech = lv.tech AND lca_tax.seq_date = lv.seq_date AND lca_tax.code = lv.code AND lca_tax.annotation = lv.annotation
     LEFT JOIN sample_view sv ON lv.og_id = sv.og_id_sv;;

-- View: public.mitogenome_data
CREATE OR REPLACE VIEW public.mitogenome_data AS
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
   FROM mito_assembly a
     JOIN sample s ON s.og_id = a.og_id
     LEFT JOIN mito_annotation n ON n.assembly_id = a.assembly_id
     LEFT JOIN mito_assembly_depth d ON d.assembly_id = a.assembly_id
     LEFT JOIN mito_assembly_qc q ON q.assembly_id = a.assembly_id
     LEFT JOIN ( SELECT mito_annotation_gene.annotation_id,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'rrna12s'::text) AS rrna12s,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'rrna16s'::text) AS rrna16s,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'atp6'::text) AS atp6,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'atp8'::text) AS atp8,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'cox1'::text) AS cox1,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'cox2'::text) AS cox2,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'cox3'::text) AS cox3,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'cytb'::text) AS cytb,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'nad1'::text) AS nad1,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'nad2'::text) AS nad2,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'nad3'::text) AS nad3,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'nad4'::text) AS nad4,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'nad4l'::text) AS nad4l,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'nad5'::text) AS nad5,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'nad6'::text) AS nad6,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_phe'::text) AS trna_phe,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_val'::text) AS trna_val,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_leuuag'::text) AS trna_leuuag,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_leuuaa'::text) AS trna_leuuaa,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_ile'::text) AS trna_ile,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_met'::text) AS trna_met,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_thr'::text) AS trna_thr,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_pro'::text) AS trna_pro,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_lys'::text) AS trna_lys,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_asp'::text) AS trna_asp,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_glu'::text) AS trna_glu,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_sergcu'::text) AS trna_sergcu,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_seruga'::text) AS trna_seruga,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_tyr'::text) AS trna_tyr,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_cys'::text) AS trna_cys,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_trp'::text) AS trna_trp,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_ala'::text) AS trna_ala,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_asn'::text) AS trna_asn,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_gly'::text) AS trna_gly,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_arg'::text) AS trna_arg,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_his'::text) AS trna_his,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'trna_gln'::text) AS trna_gln,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'atp9'::text) AS atp9,
            max(mito_annotation_gene.length) FILTER (WHERE mito_annotation_gene.gene = 'mtmuts'::text) AS mtmuts,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'atp6'::text) AS atp6_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'atp8'::text) AS atp8_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'cox1'::text) AS cox1_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'cox2'::text) AS cox2_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'cox3'::text) AS cox3_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'cytb'::text) AS cytb_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'nad1'::text) AS nad1_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'nad2'::text) AS nad2_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'nad3'::text) AS nad3_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'nad4'::text) AS nad4_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'nad4l'::text) AS nad4l_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'nad5'::text) AS nad5_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'nad6'::text) AS nad6_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'atp9'::text) AS atp9_trans,
            max(mito_annotation_gene.translated_length) FILTER (WHERE mito_annotation_gene.gene = 'mtmuts'::text) AS mtmuts_trans
           FROM mito_annotation_gene
          GROUP BY mito_annotation_gene.annotation_id) g ON g.annotation_id = n.annotation_id;;

-- View: public.mitogenome_submission_view
CREATE OR REPLACE VIEW public.mitogenome_submission_view AS
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
   FROM mito_assembly a
     JOIN sample s ON s.og_id = a.og_id
     LEFT JOIN mito_annotation n ON n.assembly_id = a.assembly_id
     LEFT JOIN ena_validation_attempts e ON e.og_id = a.og_id AND e.tech = a.tech AND e.seq_date = a.seq_date AND e.code = a.code AND e.annotation = n.annotation
     LEFT JOIN lca_validation l ON l.og_id = a.og_id AND l.tech = a.tech AND l.seq_date = a.seq_date AND l.code = a.code AND l.annotation = n.annotation;;

-- View: public.raw_qc
CREATE OR REPLACE VIEW public.raw_qc AS
 WITH pick AS (
         SELECT DISTINCT ON (rs.og_id) rs.og_id,
            rs.read_set_id
           FROM ref_read_set rs
          WHERE (EXISTS ( SELECT 1
                   FROM ref_genomescope g_1
                  WHERE g_1.read_set_id = rs.read_set_id)) OR (EXISTS ( SELECT 1
                   FROM ref_hifi_adapter_filter f_1
                  WHERE f_1.read_set_id = rs.read_set_id))
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
   FROM pick p
     LEFT JOIN ref_genomescope g ON g.read_set_id = p.read_set_id
     LEFT JOIN ref_hifi_adapter_filter f ON f.read_set_id = p.read_set_id;;

-- View: public.ref_genomes
CREATE OR REPLACE VIEW public.ref_genomes AS
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
   FROM ref_assembly_part p
     JOIN ref_assembly a ON a.assembly_id = p.assembly_id
     LEFT JOIN ref_gfastats gf ON gf.part_id = p.part_id
     LEFT JOIN ref_busco bu ON bu.part_id = p.part_id
     LEFT JOIN ref_merqury_qv mq ON mq.part_id = p.part_id
     LEFT JOIN ref_merqury_completeness mc ON mc.part_id = p.part_id
     LEFT JOIN ref_omnic om ON om.part_id = p.part_id
     LEFT JOIN ref_seqkit_stats sk ON sk.part_id = p.part_id
     LEFT JOIN ref_chromosome_stats ch ON ch.part_id = p.part_id;;

-- View: public.ref_genomes_assembly_uploads
CREATE OR REPLACE VIEW public.ref_genomes_assembly_uploads AS
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
   FROM ref_submission s
     LEFT JOIN ref_submission_haplotype h1 ON h1.submission_id = s.submission_id AND h1.haplotype = 'hap1'::text
     LEFT JOIN ref_submission_haplotype h2 ON h2.submission_id = s.submission_id AND h2.haplotype = 'hap2'::text;;

-- View: public.ref_genomes_sra_uploads
CREATE OR REPLACE VIEW public.ref_genomes_sra_uploads AS
 SELECT u.srr_accession,
    s.og_id,
    u.filenames,
    u.data_type,
    COALESCE(u.ncbi_status, to_char(u.release_date::timestamp with time zone, 'YYYY-MM-DD'::text)) AS ncbi_status
   FROM ref_sra_upload u
     JOIN ref_submission s ON s.submission_id = u.submission_id;;

-- View: public.sample_view
CREATE OR REPLACE VIEW public.sample_view AS
 SELECT s.og_id AS og_id_sv,
    s.project_id AS proj_id,
    s.nominal_species_id AS nom_id,
    s.photo_id AS photo_id_sv,
    s.photo_voucher AS photo_vouch_sv,
    s.specimen_voucher AS specimen_vouch_sv,
    s.voucher_id AS vouch_id_sv
   FROM sample s
  WHERE (EXISTS ( SELECT 1
           FROM lca_validation lv
          WHERE lv.og_id = s.og_id));;

-- View: public.summary
CREATE OR REPLACE VIEW public.summary AS
 SELECT s.og_num,
    s.og_id,
    s.project_id,
    s.workflow,
    s.priority,
    ( SELECT count(*) AS count
           FROM tissue t
          WHERE t.og_id = s.og_id) AS tissues,
    ( SELECT count(*) AS count
           FROM dna_extraction d
             JOIN tissue t ON t.tissue_id = d.tissue_id
          WHERE t.og_id = s.og_id AND d.status = 'Extracted'::text) AS extracted,
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
           FROM illumina_library i
             JOIN dna_extraction d ON d.dna_id = i.dna_id
             JOIN tissue t ON t.tissue_id = d.tissue_id
          WHERE t.og_id = s.og_id) AS illumina_actual,
    ( SELECT count(*) AS count
           FROM pacbio_library p
             JOIN dna_extraction d ON d.dna_id = p.dna_id
             JOIN tissue t ON t.tissue_id = d.tissue_id
          WHERE t.og_id = s.og_id) AS hifi_actual,
    ( SELECT count(*) AS count
           FROM hic_library h
             JOIN hic_lysate y ON y.lysate_id = h.lysate_id
             JOIN tissue t ON t.tissue_id = y.tissue_id
          WHERE t.og_id = s.og_id) AS hic_actual,
    ( SELECT count(*) AS count
           FROM ont_library o
             JOIN dna_extraction d ON d.dna_id = o.dna_id
             JOIN tissue t ON t.tissue_id = d.tissue_id
          WHERE t.og_id = s.og_id) AS nanopore_actual,
    ( SELECT count(*) AS count
           FROM rna_extraction r
             JOIN tissue t ON t.tissue_id = r.tissue_id
          WHERE t.og_id = s.og_id) AS rna_actual,
    ( SELECT count(*) AS count
           FROM rna_library_ilmn x
             JOIN rna_extraction r ON r.rna_id = x.rna_id
             JOIN tissue t ON t.tissue_id = r.tissue_id
          WHERE t.og_id = s.og_id) AS rna_ilmn_actual,
    ( SELECT count(*) AS count
           FROM rna_library_kinx k
             JOIN rna_extraction r ON r.rna_id = k.rna_id
             JOIN tissue t ON t.tissue_id = r.tissue_id
          WHERE t.og_id = s.og_id) AS rna_kinnex_actual,
    ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS string_agg
           FROM lca_validation lv
          WHERE lv.og_id = s.og_id AND lv.tech = 'ilmn'::text AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> ''::text) AS ilmn_validated_species_name,
    ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS string_agg
           FROM lca_validation lv
          WHERE lv.og_id = s.og_id AND lv.tech = 'hifi'::text AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> ''::text) AS hifi_validated_species_name,
    ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS string_agg
           FROM lca_validation lv
          WHERE lv.og_id = s.og_id AND lv.tech = 'hic'::text AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> ''::text) AS hic_validated_species_name,
    s.field_id,
    s.nominal_species_id,
    s.common_name,
    s.collector,
    s.contact,
    s.comments
   FROM sample s
     LEFT JOIN LATERAL ( SELECT d.status
           FROM dna_extraction d
             JOIN tissue t ON t.tissue_id = d.tissue_id
          WHERE t.og_id = s.og_id
          ORDER BY d.status_overwrite DESC NULLS LAST, d.ext_num DESC
         LIMIT 1) dna ON true
     LEFT JOIN LATERAL ( SELECT i.ilmn_status AS status
           FROM illumina_library i
             JOIN dna_extraction d ON d.dna_id = i.dna_id
             JOIN tissue t ON t.tissue_id = d.tissue_id
          WHERE t.og_id = s.og_id
          ORDER BY i.status_overwrite DESC NULLS LAST, i.ilmn_num DESC
         LIMIT 1) ilmn ON true
     LEFT JOIN LATERAL ( SELECT p.pacb_status AS status
           FROM pacbio_library p
             JOIN dna_extraction d ON d.dna_id = p.dna_id
             JOIN tissue t ON t.tissue_id = d.tissue_id
          WHERE t.og_id = s.og_id
          ORDER BY p.status_overwrite DESC NULLS LAST, p.pacb_num DESC
         LIMIT 1) pacb ON true
     LEFT JOIN LATERAL ( SELECT h.hic_status AS status
           FROM hic_library h
             JOIN hic_lysate y ON y.lysate_id = h.lysate_id
             JOIN tissue t ON t.tissue_id = y.tissue_id
          WHERE t.og_id = s.og_id
          ORDER BY h.status_overwrite DESC NULLS LAST, h.hic_num DESC
         LIMIT 1) hic ON true
     LEFT JOIN LATERAL ( SELECT o.ont_status AS status
           FROM ont_library o
             JOIN dna_extraction d ON d.dna_id = o.dna_id
             JOIN tissue t ON t.tissue_id = d.tissue_id
          WHERE t.og_id = s.og_id
          ORDER BY o.status_overwrite DESC NULLS LAST, o.ont_num DESC
         LIMIT 1) ont ON true
     LEFT JOIN LATERAL ( SELECT r.status
           FROM rna_extraction r
             JOIN tissue t ON t.tissue_id = r.tissue_id
          WHERE t.og_id = s.og_id
          ORDER BY r.status_overwrite DESC NULLS LAST, r.ext_num DESC
         LIMIT 1) rna ON true
     LEFT JOIN LATERAL ( SELECT x.rna_status AS status
           FROM rna_library_ilmn x
             JOIN rna_extraction r ON r.rna_id = x.rna_id
             JOIN tissue t ON t.tissue_id = r.tissue_id
          WHERE t.og_id = s.og_id
          ORDER BY x.status_overwrite DESC NULLS LAST, x.rna_num DESC
         LIMIT 1) rilm ON true
     LEFT JOIN LATERAL ( SELECT k.rna_status AS status
           FROM rna_library_kinx k
             JOIN rna_extraction r ON r.rna_id = k.rna_id
             JOIN tissue t ON t.tissue_id = r.tissue_id
          WHERE t.og_id = s.og_id
          ORDER BY k.status_overwrite DESC NULLS LAST, k.rna_num DESC
         LIMIT 1) rkin ON true;;

-- View: public.v_dna_extraction_browse
CREATE OR REPLACE VIEW public.v_dna_extraction_browse AS
 SELECT s.og_num,
    t.og_id,
    d.tissue_id,
    d.dna_id,
    d.ext_num,
    d.ext_num = max(d.ext_num) OVER (PARTITION BY d.tissue_id) AS is_latest,
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
   FROM dna_extraction d
     JOIN tissue t ON t.tissue_id = d.tissue_id
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_draft_genome_status
CREATE OR REPLACE VIEW public.v_draft_genome_status AS
 SELECT d.og_num,
    d.og_id,
    s.nominal_species_id,
    d.seq_date,
    d.mach,
    r.n_runs > 0 AS has_run_link,
    f.draft_id IS NOT NULL AS has_fastp,
    gs.draft_id IS NOT NULL AS has_genomescope,
    gs.output_set AS genomescope_output_set,
    ti.draft_id IS NOT NULL AS has_tiara,
    ct.draft_id IS NOT NULL AS has_contamination,
    b.draft_id IS NOT NULL AS has_busco,
    mq.draft_id IS NOT NULL AS has_merqury,
    gf.draft_id IS NOT NULL AS has_gfastats,
    su.draft_id IS NOT NULL AS has_submission,
    num_nonnulls(f.draft_id, gs.draft_id, ti.draft_id, ct.draft_id, b.draft_id, mq.draft_id, gf.draft_id) AS processes_done,
    f.draft_id IS NOT NULL AND num_nonnulls(gs.draft_id, ti.draft_id, ct.draft_id, b.draft_id, mq.draft_id, gf.draft_id) = 0 AS reads_only
   FROM draft_genome d
     JOIN sample s ON s.og_id = d.og_id
     LEFT JOIN LATERAL ( SELECT count(*) AS n_runs
           FROM draft_genome_run x
          WHERE x.draft_id = d.draft_id) r ON true
     LEFT JOIN draft_fastp f ON f.draft_id = d.draft_id
     LEFT JOIN draft_genomescope gs ON gs.draft_id = d.draft_id
     LEFT JOIN draft_tiara ti ON ti.draft_id = d.draft_id
     LEFT JOIN draft_contamination ct ON ct.draft_id = d.draft_id
     LEFT JOIN draft_busco b ON b.draft_id = d.draft_id
     LEFT JOIN draft_merqury mq ON mq.draft_id = d.draft_id
     LEFT JOIN draft_gfastats gf ON gf.draft_id = d.draft_id
     LEFT JOIN draft_submission su ON su.draft_id = d.draft_id;;

-- View: public.v_genome_size_comparison
CREATE OR REPLACE VIEW public.v_genome_size_comparison AS
 SELECT s.og_num,
    d.og_id,
    sp.species,
    sp.ncbi_taxon_id,
    d.seq_date,
    gs.genomesize AS estimated_bp,
    a.total_sequence_length AS ncbi_bp,
        CASE
            WHEN a.total_sequence_length > 0 THEN round(gs.genomesize::numeric / a.total_sequence_length::numeric, 3)
            ELSE NULL::numeric
        END AS estimated_over_ncbi,
    a.assembly_accession,
    a.assembly_level,
    a.is_refseq,
    a.is_representative
   FROM draft_genome d
     LEFT JOIN draft_genomescope gs ON gs.draft_id = d.draft_id
     JOIN sample s ON s.og_id = d.og_id
     JOIN species sp ON s.nominal_species_id = sp.species
     LEFT JOIN species_ncbi_assembly a ON a.species = sp.species AND a.is_chosen;;

-- View: public.v_hic_library_browse
CREATE OR REPLACE VIEW public.v_hic_library_browse AS
 SELECT s.og_num,
    t.og_id,
    y.tissue_id,
    h.lysate_id,
    h.hic_library_tube_id,
    h.hic_num,
    h.hic_num = max(h.hic_num) OVER (PARTITION BY h.lysate_id) AS is_latest,
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
   FROM hic_library h
     JOIN hic_lysate y ON y.lysate_id = h.lysate_id
     JOIN tissue t ON t.tissue_id = y.tissue_id
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_hic_lysate_browse
CREATE OR REPLACE VIEW public.v_hic_lysate_browse AS
 SELECT s.og_num,
    t.og_id,
    y.tissue_id,
    y.lysate_id,
    y.lysate_num,
    y.lysate_num = max(y.lysate_num) OVER (PARTITION BY y.tissue_id) AS is_latest,
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
   FROM hic_lysate y
     JOIN tissue t ON t.tissue_id = y.tissue_id
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_illumina_library_browse
CREATE OR REPLACE VIEW public.v_illumina_library_browse AS
 SELECT s.og_num,
    t.og_id,
    d.tissue_id,
    i.dna_id,
    i.illumina_library_tube_id,
    i.ilmn_num,
    i.ilmn_num = max(i.ilmn_num) OVER (PARTITION BY i.dna_id) AS is_latest,
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
   FROM illumina_library i
     JOIN dna_extraction d ON d.dna_id = i.dna_id
     JOIN tissue t ON t.tissue_id = d.tissue_id
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_library_browse
CREATE OR REPLACE VIEW public.v_library_browse AS
 SELECT s.og_num,
    t.og_id,
    t.tissue_id,
    l.library_tube_id,
    l.library_type,
    COALESCE(l.dna_id, l.rna_id, l.lysate_id) AS parent_id,
    l.dna_id,
    l.rna_id,
    l.lysate_id
   FROM library l
     LEFT JOIN dna_extraction d ON d.dna_id = l.dna_id
     LEFT JOIN rna_extraction r ON r.rna_id = l.rna_id
     LEFT JOIN hic_lysate y ON y.lysate_id = l.lysate_id
     JOIN tissue t ON t.tissue_id = COALESCE(d.tissue_id, r.tissue_id, y.tissue_id)
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_mito_annotation_genes
CREATE OR REPLACE VIEW public.v_mito_annotation_genes AS
 SELECT s.og_num,
    a.og_id,
    s.nominal_species_id,
    a.tech,
    a.seq_date,
    a.code,
    n.annotation,
    n.annotation_id,
    n.is_selected,
    max(g.length) FILTER (WHERE g.gene = 'rrna12s'::text) AS rrna12s,
    max(g.length) FILTER (WHERE g.gene = 'rrna16s'::text) AS rrna16s,
    max(g.length) FILTER (WHERE g.gene = 'atp6'::text) AS atp6,
    max(g.translated_length) FILTER (WHERE g.gene = 'atp6'::text) AS atp6_trans,
    max(g.length) FILTER (WHERE g.gene = 'atp8'::text) AS atp8,
    max(g.translated_length) FILTER (WHERE g.gene = 'atp8'::text) AS atp8_trans,
    max(g.length) FILTER (WHERE g.gene = 'cox1'::text) AS cox1,
    max(g.translated_length) FILTER (WHERE g.gene = 'cox1'::text) AS cox1_trans,
    max(g.length) FILTER (WHERE g.gene = 'cox2'::text) AS cox2,
    max(g.translated_length) FILTER (WHERE g.gene = 'cox2'::text) AS cox2_trans,
    max(g.length) FILTER (WHERE g.gene = 'cox3'::text) AS cox3,
    max(g.translated_length) FILTER (WHERE g.gene = 'cox3'::text) AS cox3_trans,
    max(g.length) FILTER (WHERE g.gene = 'cytb'::text) AS cytb,
    max(g.translated_length) FILTER (WHERE g.gene = 'cytb'::text) AS cytb_trans,
    max(g.length) FILTER (WHERE g.gene = 'nad1'::text) AS nad1,
    max(g.translated_length) FILTER (WHERE g.gene = 'nad1'::text) AS nad1_trans,
    max(g.length) FILTER (WHERE g.gene = 'nad2'::text) AS nad2,
    max(g.translated_length) FILTER (WHERE g.gene = 'nad2'::text) AS nad2_trans,
    max(g.length) FILTER (WHERE g.gene = 'nad3'::text) AS nad3,
    max(g.translated_length) FILTER (WHERE g.gene = 'nad3'::text) AS nad3_trans,
    max(g.length) FILTER (WHERE g.gene = 'nad4'::text) AS nad4,
    max(g.translated_length) FILTER (WHERE g.gene = 'nad4'::text) AS nad4_trans,
    max(g.length) FILTER (WHERE g.gene = 'nad4l'::text) AS nad4l,
    max(g.translated_length) FILTER (WHERE g.gene = 'nad4l'::text) AS nad4l_trans,
    max(g.length) FILTER (WHERE g.gene = 'nad5'::text) AS nad5,
    max(g.translated_length) FILTER (WHERE g.gene = 'nad5'::text) AS nad5_trans,
    max(g.length) FILTER (WHERE g.gene = 'nad6'::text) AS nad6,
    max(g.translated_length) FILTER (WHERE g.gene = 'nad6'::text) AS nad6_trans,
    max(g.length) FILTER (WHERE g.gene = 'atp9'::text) AS atp9,
    max(g.translated_length) FILTER (WHERE g.gene = 'atp9'::text) AS atp9_trans,
    max(g.length) FILTER (WHERE g.gene = 'mtmuts'::text) AS mtmuts,
    max(g.translated_length) FILTER (WHERE g.gene = 'mtmuts'::text) AS mtmuts_trans,
    max(g.length) FILTER (WHERE g.gene = 'trna_phe'::text) AS trna_phe,
    max(g.length) FILTER (WHERE g.gene = 'trna_val'::text) AS trna_val,
    max(g.length) FILTER (WHERE g.gene = 'trna_leuuag'::text) AS trna_leuuag,
    max(g.length) FILTER (WHERE g.gene = 'trna_leuuaa'::text) AS trna_leuuaa,
    max(g.length) FILTER (WHERE g.gene = 'trna_ile'::text) AS trna_ile,
    max(g.length) FILTER (WHERE g.gene = 'trna_met'::text) AS trna_met,
    max(g.length) FILTER (WHERE g.gene = 'trna_thr'::text) AS trna_thr,
    max(g.length) FILTER (WHERE g.gene = 'trna_pro'::text) AS trna_pro,
    max(g.length) FILTER (WHERE g.gene = 'trna_lys'::text) AS trna_lys,
    max(g.length) FILTER (WHERE g.gene = 'trna_asp'::text) AS trna_asp,
    max(g.length) FILTER (WHERE g.gene = 'trna_glu'::text) AS trna_glu,
    max(g.length) FILTER (WHERE g.gene = 'trna_sergcu'::text) AS trna_sergcu,
    max(g.length) FILTER (WHERE g.gene = 'trna_seruga'::text) AS trna_seruga,
    max(g.length) FILTER (WHERE g.gene = 'trna_tyr'::text) AS trna_tyr,
    max(g.length) FILTER (WHERE g.gene = 'trna_cys'::text) AS trna_cys,
    max(g.length) FILTER (WHERE g.gene = 'trna_trp'::text) AS trna_trp,
    max(g.length) FILTER (WHERE g.gene = 'trna_ala'::text) AS trna_ala,
    max(g.length) FILTER (WHERE g.gene = 'trna_asn'::text) AS trna_asn,
    max(g.length) FILTER (WHERE g.gene = 'trna_gly'::text) AS trna_gly,
    max(g.length) FILTER (WHERE g.gene = 'trna_arg'::text) AS trna_arg,
    max(g.length) FILTER (WHERE g.gene = 'trna_his'::text) AS trna_his,
    max(g.length) FILTER (WHERE g.gene = 'trna_gln'::text) AS trna_gln
   FROM mito_annotation n
     JOIN mito_assembly a ON a.assembly_id = n.assembly_id
     JOIN sample s ON s.og_id = a.og_id
     LEFT JOIN mito_annotation_gene g ON g.annotation_id = n.annotation_id
  GROUP BY s.og_num, a.og_id, s.nominal_species_id, a.tech, a.seq_date, a.code, n.annotation, n.annotation_id, n.is_selected;;

-- View: public.v_ont_library_browse
CREATE OR REPLACE VIEW public.v_ont_library_browse AS
 SELECT s.og_num,
    t.og_id,
    d.tissue_id,
    o.dna_id,
    o.ont_library_tube_id,
    o.ont_num,
    o.ont_num = max(o.ont_num) OVER (PARTITION BY o.dna_id, o.library_method) AS is_latest,
    o.ont_status,
    o.status_overwrite,
    o.library_method,
    o.library_type,
    o.library_date,
    o.library_id,
    o.est_loading_size,
    o.ont_comments
   FROM ont_library o
     JOIN dna_extraction d ON d.dna_id = o.dna_id
     JOIN tissue t ON t.tissue_id = d.tissue_id
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_pacbio_library_browse
CREATE OR REPLACE VIEW public.v_pacbio_library_browse AS
 SELECT s.og_num,
    t.og_id,
    d.tissue_id,
    p.dna_id,
    p.pacbio_library_tube_id,
    p.pacb_num,
    p.pacb_num = max(p.pacb_num) OVER (PARTITION BY p.dna_id) AS is_latest,
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
   FROM pacbio_library p
     JOIN dna_extraction d ON d.dna_id = p.dna_id
     JOIN tissue t ON t.tissue_id = d.tissue_id
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_quarantine_displaced
CREATE OR REPLACE VIEW public.v_quarantine_displaced AS
 SELECT import_quarantine.source_table,
    import_quarantine.source_row_key AS displaced_key,
    import_quarantine.violation_detail AS replaced_by,
    import_quarantine.first_seen AS displaced_at,
    import_quarantine.raw_row
   FROM import_quarantine
  WHERE import_quarantine.resolved_at IS NULL AND import_quarantine.violation_type = 'displaced'::text
  ORDER BY import_quarantine.first_seen DESC, import_quarantine.source_table, import_quarantine.source_row_key;;

-- View: public.v_quarantine_open
CREATE OR REPLACE VIEW public.v_quarantine_open AS
 SELECT import_quarantine.source_table,
    import_quarantine.violation_type,
    count(*) AS rows_blocked,
    min(import_quarantine.first_seen) AS oldest,
    max(import_quarantine.last_seen) AS most_recent
   FROM import_quarantine
  WHERE import_quarantine.resolved_at IS NULL AND import_quarantine.violation_type <> 'displaced'::text
  GROUP BY import_quarantine.source_table, import_quarantine.violation_type
  ORDER BY (count(*)) DESC, import_quarantine.source_table, import_quarantine.violation_type;;

-- View: public.v_read_qc_sequencing_readiness
CREATE OR REPLACE VIEW public.v_read_qc_sequencing_readiness AS
 SELECT 'hifi'::text AS kind,
    q.og_id,
    q.tissue,
    q.ext_type,
    q.lib_code,
    NULL::text AS lane,
    q.run_id,
        CASE
            WHEN NOT (EXISTS ( SELECT 1
               FROM sequencing s
              WHERE s.run_id = q.run_id)) THEN 'run not in sequencing'::text
            WHEN NOT (EXISTS ( SELECT 1
               FROM library l
              WHERE l.library_tube_id = (((((q.og_id || q.tissue) || '_'::text) || q.ext_type) || '_'::text) || q.lib_code))) THEN 'library tube not in library'::text
            ELSE 'no single sequencing row for this tube on this run'::text
        END AS reason
   FROM hifi_read_qc q
  WHERE q.sequencing_id IS NULL
UNION ALL
 SELECT 'hic'::text AS kind,
    q.og_id,
    q.tissue,
    q.ext_type,
    q.lib_code,
    q.lane,
    q.run_id,
        CASE
            WHEN NOT (EXISTS ( SELECT 1
               FROM sequencing s
              WHERE s.run_id = q.run_id)) THEN 'run not in sequencing'::text
            WHEN (( SELECT count(*) AS count
               FROM v_sequencing_browse s
              WHERE s.og_id = q.og_id AND s.run_id = q.run_id AND s.technology = 'Hi-C'::text AND s.tissue_id ~~ ((q.og_id || COALESCE(q.tissue, ''::text)) || '%'::text))) > 1 THEN 'several Hi-C libraries of this OG and tissue on this run'::text
            ELSE 'no Hi-C library of this OG and tissue on this run'::text
        END AS reason
   FROM hic_read_qc q
  WHERE q.sequencing_id IS NULL;;

-- View: public.v_read_set_run_readiness
CREATE OR REPLACE VIEW public.v_read_set_run_readiness AS
 SELECT rs.og_id,
    rs.seq_date,
    rs.read_set_id,
    ( SELECT string_agg(s.sequencing_id, ', '::text ORDER BY s.seq_date, s.sequencing_id) AS string_agg
           FROM v_sequencing_browse s
          WHERE s.og_id = rs.og_id AND (s.technology = ANY (ARRAY['PacBio HIFI'::text, 'PacBio'::text])) AND s.library_type = 'pacbio'::text AND s.status IS DISTINCT FROM 'Failed'::text) AS pacbio_rows_for_og
   FROM ref_read_set rs
  WHERE NOT (EXISTS ( SELECT 1
           FROM ref_read_set_run r
          WHERE r.read_set_id = rs.read_set_id)) AND NOT (EXISTS ( SELECT 1
           FROM ref_read_set_external x
          WHERE x.read_set_id = rs.read_set_id));;

-- View: public.v_ref_assembly_run_readiness
CREATE OR REPLACE VIEW public.v_ref_assembly_run_readiness AS
 SELECT a.og_num,
    a.og_id,
    a.seq_date,
    a.version,
    ( SELECT string_agg(s.sequencing_id, ', '::text ORDER BY s.seq_date, s.sequencing_id) AS string_agg
           FROM v_sequencing_browse s
          WHERE s.og_id = a.og_id AND (s.technology = ANY (ARRAY['PacBio HIFI'::text, 'PacBio'::text, 'ONT'::text])) AND (s.library_type = ANY (ARRAY['pacbio'::text, 'ont'::text])) AND s.status IS DISTINCT FROM 'Failed'::text) AS long_read_rows_for_og
   FROM ref_assembly a
  WHERE NOT (EXISTS ( SELECT 1
           FROM ref_assembly_run r
          WHERE r.assembly_id = a.assembly_id));;

-- View: public.v_ref_assembly_status
CREATE OR REPLACE VIEW public.v_ref_assembly_status AS
 SELECT a.og_num,
    a.og_id,
    a.seq_date,
    a.version,
    a.strategy,
    a.attempt,
    ( SELECT count(*) AS count
           FROM ref_assembly_run r
          WHERE r.assembly_id = a.assembly_id) AS run_links,
    count(p.part_id) AS parts,
    string_agg(DISTINCT p.stage::text, ','::text ORDER BY (p.stage::text)) AS stages,
    COALESCE(bool_or(p.stage = 3), false) AS curated,
    string_agg(DISTINCT
        CASE
            WHEN gf.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text, ','::text ORDER BY (
        CASE
            WHEN gf.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text)) AS gfastats_stages,
    string_agg(DISTINCT
        CASE
            WHEN bu.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text, ','::text ORDER BY (
        CASE
            WHEN bu.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text)) AS busco_stages,
    string_agg(DISTINCT
        CASE
            WHEN mq.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text, ','::text ORDER BY (
        CASE
            WHEN mq.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text)) AS merqury_qv_stages,
    string_agg(DISTINCT
        CASE
            WHEN mc.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text, ','::text ORDER BY (
        CASE
            WHEN mc.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text)) AS merqury_completeness_stages,
    string_agg(DISTINCT
        CASE
            WHEN om.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text, ','::text ORDER BY (
        CASE
            WHEN om.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text)) AS omnic_stages,
    string_agg(DISTINCT
        CASE
            WHEN sk.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text, ','::text ORDER BY (
        CASE
            WHEN sk.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text)) AS seqkit_stats_stages,
    string_agg(DISTINCT
        CASE
            WHEN ch.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text, ','::text ORDER BY (
        CASE
            WHEN ch.part_id IS NOT NULL THEN p.stage
            ELSE NULL::integer
        END::text)) AS chromosome_stats_stages
   FROM ref_assembly a
     JOIN ref_assembly_part p ON p.assembly_id = a.assembly_id
     LEFT JOIN ref_gfastats gf ON gf.part_id = p.part_id
     LEFT JOIN ref_busco bu ON bu.part_id = p.part_id
     LEFT JOIN ref_merqury_qv mq ON mq.part_id = p.part_id
     LEFT JOIN ref_merqury_completeness mc ON mc.part_id = p.part_id
     LEFT JOIN ref_omnic om ON om.part_id = p.part_id
     LEFT JOIN ref_seqkit_stats sk ON sk.part_id = p.part_id
     LEFT JOIN ref_chromosome_stats ch ON ch.part_id = p.part_id
  GROUP BY a.assembly_id;;

-- View: public.v_ref_assembly_summary
CREATE OR REPLACE VIEW public.v_ref_assembly_summary AS
 WITH final_part AS (
         SELECT DISTINCT ON (p.assembly_id, p.haplotype) p.part_id,
            p.assembly_id,
            p.stage,
            p.haplotype,
            p.created_at
           FROM ref_assembly_part p
          WHERE p.haplotype <> 'dual'::text
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
   FROM final_part f
     JOIN ref_assembly a ON a.assembly_id = f.assembly_id
     JOIN ref_stage st ON st.stage = f.stage
     LEFT JOIN ref_gfastats gf ON gf.part_id = f.part_id
     LEFT JOIN ref_chromosome_stats ch ON ch.part_id = f.part_id
     LEFT JOIN ref_busco bu ON bu.part_id = f.part_id
     LEFT JOIN ref_merqury_qv mq ON mq.part_id = f.part_id
     LEFT JOIN ref_merqury_completeness mc ON mc.part_id = f.part_id;;

-- View: public.v_rna_extraction_browse
CREATE OR REPLACE VIEW public.v_rna_extraction_browse AS
 SELECT s.og_num,
    t.og_id,
    r.tissue_id,
    r.rna_id,
    r.ext_num,
    r.ext_num = max(r.ext_num) OVER (PARTITION BY r.tissue_id) AS is_latest,
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
   FROM rna_extraction r
     JOIN tissue t ON t.tissue_id = r.tissue_id
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_rna_library_ilmn_browse
CREATE OR REPLACE VIEW public.v_rna_library_ilmn_browse AS
 SELECT s.og_num,
    t.og_id,
    r.tissue_id,
    x.rna_id,
    x.rna_library_tube_id,
    x.rna_num,
    x.rna_num = max(x.rna_num) OVER (PARTITION BY x.rna_id, x.library_method) AS is_latest,
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
   FROM rna_library_ilmn x
     JOIN rna_extraction r ON r.rna_id = x.rna_id
     JOIN tissue t ON t.tissue_id = r.tissue_id
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_rna_library_kinx_browse
CREATE OR REPLACE VIEW public.v_rna_library_kinx_browse AS
 SELECT s.og_num,
    t.og_id,
    r.tissue_id,
    k.rna_id,
    k.rna_library_tube_id,
    k.rna_num,
    k.rna_num = max(k.rna_num) OVER (PARTITION BY k.rna_id) AS is_latest,
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
   FROM rna_library_kinx k
     JOIN rna_extraction r ON r.rna_id = k.rna_id
     JOIN tissue t ON t.tissue_id = r.tissue_id
     JOIN sample s ON s.og_id = t.og_id;;

-- View: public.v_sequencing_browse
CREATE OR REPLACE VIEW public.v_sequencing_browse AS
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
   FROM sequencing q
     JOIN v_library_browse b ON b.library_tube_id = q.library_tube_id;;

-- View: public.v_sequencing_run_fk_readiness
CREATE OR REPLACE VIEW public.v_sequencing_run_fk_readiness AS
 SELECT 'sequencing'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
   FROM sequencing c
     LEFT JOIN sequencing_run r ON r.run_id = c.run_id
UNION ALL
 SELECT 'raw_data'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
   FROM raw_data c
     LEFT JOIN sequencing_run r ON r.run_id = c.run_id
UNION ALL
 SELECT 'hifi_read_qc'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
   FROM hifi_read_qc c
     LEFT JOIN sequencing_run r ON r.run_id = c.run_id
UNION ALL
 SELECT 'hic_read_qc'::text AS child,
    count(*) AS child_rows,
    count(*) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_rows,
    string_agg(DISTINCT c.run_id, ', '::text) FILTER (WHERE c.run_id IS NOT NULL AND r.run_id IS NULL) AS failing_run_ids
   FROM hic_read_qc c
     LEFT JOIN sequencing_run r ON r.run_id = c.run_id;;

-- View: public.v_sequencing_run_issues
CREATE OR REPLACE VIEW public.v_sequencing_run_issues AS
 SELECT r.run_id,
    r.mach IS NULL AS run_id_unparsed,
    r.instrument IS NULL AS instrument_disagrees_or_missing,
    r.run_date IS NULL AS run_date_disagrees_or_missing,
    ( SELECT string_agg(DISTINCT COALESCE(s.instrument, '(null)'::text), ', '::text) AS string_agg
           FROM sequencing s
          WHERE s.run_id = r.run_id) AS instruments,
    ( SELECT string_agg(DISTINCT COALESCE(s.run_date::text, '(null)'::text), ', '::text) AS string_agg
           FROM sequencing s
          WHERE s.run_id = r.run_id) AS run_dates
   FROM sequencing_run r
  WHERE r.mach IS NULL OR r.instrument IS NULL OR r.run_date IS NULL;;

-- View: public.v_sra_upload_run_readiness
CREATE OR REPLACE VIEW public.v_sra_upload_run_readiness AS
 SELECT s.og_id,
    u.srr_accession,
    u.data_type,
    COALESCE(x.reason, 'not resolved by the forward rule'::text) AS reason,
    x.reviewed_on,
    "left"(u.filenames, 200) AS filenames
   FROM ref_sra_upload u
     JOIN ref_submission s USING (submission_id)
     LEFT JOIN ref_sra_upload_unlinked x USING (srr_accession)
  WHERE NOT (EXISTS ( SELECT 1
           FROM ref_sra_upload_run r
          WHERE r.srr_accession = u.srr_accession));;

-- View: public.v_tissue_browse
CREATE OR REPLACE VIEW public.v_tissue_browse AS
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
   FROM tissue t
     JOIN sample s ON s.og_id = t.og_id;;

