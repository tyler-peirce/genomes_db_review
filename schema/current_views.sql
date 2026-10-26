-- View: public.coverage_summary
CREATE OR REPLACE VIEW public.coverage_summary AS
 WITH hifi_agg AS (
         SELECT hifi_reads_qc.og_id,
            sum(hifi_reads_qc.hifi_yield) AS total_hifi_yield_bp
           FROM hifi_reads_qc
          GROUP BY hifi_reads_qc.og_id
        ), hic_agg AS (
         SELECT hic_reads_qc.og_id,
            sum(hic_reads_qc.yield_gb * 1000000000::numeric)::bigint AS total_hic_yield_bp
           FROM hic_reads_qc
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
                 JOIN ref_genomes rg ON rg.og_id = samp.og_id
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

-- View: public.mitogenome_submission_view
CREATE OR REPLACE VIEW public.mitogenome_submission_view AS
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
     LEFT JOIN lca_validation l ON l.og_id = m.og_id AND l.tech = m.tech AND l.seq_date = m.seq_date AND l.code = m.code AND l.annotation = m.annotation;;

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

-- View: public.v_genome_size_comparison
CREATE OR REPLACE VIEW public.v_genome_size_comparison AS
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

