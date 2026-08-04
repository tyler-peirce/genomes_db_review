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
               FROM sample samp
              WHERE samp.nominal_species_id = s.species AND (samp.pb_status = ANY (ARRAY['Library Prep - PacBio SMRTbell'::text, 'QC - Femto'::text, 'Sequenced'::text, 'Sequenced, SRE'::text, 'Sequence - PacBio'::text, 'Shearing'::text, 'SRE'::text, 'SRE - ULI'::text, 'ULI'::text])))) THEN 'in_lab'::text
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
              WHERE samp.nominal_species_id = s.species AND samp.workflow::text = 'Reference'::text AND samp.collector IS NOT NULL
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
    max(lca.species_in_lca) FILTER (WHERE lca.region = '12s'::text) AS s12_lca,
    max(lca.species_in_lca) FILTER (WHERE lca.region = '16s'::text) AS s16_lca,
    max(lca.species_in_lca) FILTER (WHERE lca.region = 'CO1'::text) AS co1_lca
   FROM lca
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
            WHEN s.nominal_species_id = lp.s12_lca OR s.nominal_species_id = lp.s16_lca OR s.nominal_species_id = lp.co1_lca THEN s.nominal_species_id
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
        CASE
            WHEN flv.filtered_12s IS NOT NULL OR flv.filtered_16s IS NOT NULL OR flv.filtered_co1 IS NOT NULL THEN 'YES'::text
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
   FROM lca_validation lv
     LEFT JOIN lca_pivot_view lp ON lp.og_id_lp = lv.og_id AND lp.tech = lv.tech AND lp.seq_date = lv.seq_date AND lp.code = lv.code::text AND lp.annotation = lv.annotation::text
     LEFT JOIN lca_results_view lr ON lr.og_id_lr = lv.og_id AND lr.tech = lv.tech AND lr.seq_date = lv.seq_date AND lr.code = lv.code::text AND lr.annotation = lv.annotation::text
     LEFT JOIN filtered_lca_view flv ON flv.og_id_flv = lv.og_id AND flv.tech = lv.tech AND flv.seq_date = lv.seq_date AND flv.code = lv.code::text AND flv.annotation = lv.annotation::text
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
          GROUP BY lca.og_id, lca.tech, lca.seq_date, lca.code, lca.annotation) lca_tax ON lca_tax.og_id = lv.og_id AND lca_tax.tech = lv.tech AND lca_tax.seq_date = lv.seq_date AND lca_tax.code = lv.code::text AND lca_tax.annotation = lv.annotation::text
     LEFT JOIN sample_view sv ON lv.og_id = sv.og_id_sv;;

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
 SELECT regexp_replace(s.og_id, 'OG'::text, ''::text, 'g'::text)::integer AS og_num,
    s.og_id,
    s.project_id,
    s.workflow,
    s.priority,
    ( SELECT count(*) AS count
           FROM tissue t
          WHERE t.og_id = s.og_id) AS tissues,
    ( SELECT count(*) AS count
           FROM dna_extraction d
          WHERE d.og_id = s.og_id AND d.status = 'Extracted'::text) AS extracted,
    COALESCE(( SELECT d.status
           FROM dna_extraction d
          WHERE d.og_id = s.og_id AND d.status_overwrite::text = 'Y'::text
          ORDER BY d.ext_num DESC
         LIMIT 1), ( SELECT d.status
           FROM dna_extraction d
          WHERE d.og_id = s.og_id
          ORDER BY d.ext_num DESC
         LIMIT 1), 'Awaiting Status'::text) AS dna_extraction_status,
    s.ilmn AS illumina_sequencing,
        CASE
            WHEN s.illumina_sequencing = 'N'::text THEN ''::text
            ELSE COALESCE(( SELECT i.ilmn_status
               FROM illumina_library i
              WHERE i.og_id = s.og_id AND i.status_overwrite::text = 'Y'::text
              ORDER BY i.ilmn_num DESC
             LIMIT 1), ( SELECT i.ilmn_status
               FROM illumina_library i
              WHERE i.og_id = s.og_id
              ORDER BY i.ilmn_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS illumina_status,
    s.hifi AS hifi_sequencing,
        CASE
            WHEN s.hifi_sequencing = 'N'::text THEN ''::text
            ELSE COALESCE(( SELECT p.pacb_status
               FROM pacbio_library p
              WHERE p.og_id = s.og_id AND p.status_overwrite::text = 'Y'::text
              ORDER BY p.pacb_num DESC
             LIMIT 1), ( SELECT p.pacb_status
               FROM pacbio_library p
              WHERE p.og_id = s.og_id
              ORDER BY p.pacb_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS pacbio_status,
    s.hic AS hic_sequencing,
        CASE
            WHEN s.hic_sequencing = 'N'::text THEN ''::text
            ELSE COALESCE(( SELECT h.hic_status
               FROM hic_library h
              WHERE h.og_id = s.og_id AND h.status_overwrite::text = 'Y'::text
              ORDER BY h.hic_num DESC
             LIMIT 1), ( SELECT h.hic_status
               FROM hic_library h
              WHERE h.og_id = s.og_id
              ORDER BY h.hic_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS hic_status,
    s.nano AS nanopore_sequencing,
        CASE
            WHEN s.nanopore_sequencing = 'N'::text THEN ''::text
            ELSE COALESCE(( SELECT o.ont_status
               FROM ont_library o
              WHERE o.og_id = s.og_id AND o.status_overwrite::text = 'Y'::text
              ORDER BY o.ont_num DESC
             LIMIT 1), ( SELECT o.ont_status
               FROM ont_library o
              WHERE o.og_id = s.og_id
              ORDER BY o.ont_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS nanopore_status,
    s.rna AS rna_extraction,
        CASE
            WHEN s.rna_extraction = 'N'::text THEN ''::text
            ELSE COALESCE(( SELECT r.status
               FROM rna_extraction r
              WHERE r.og_id = s.og_id AND r.status_overwrite::text = 'Y'::text
              ORDER BY r.ext_num DESC
             LIMIT 1), ( SELECT r.status
               FROM rna_extraction r
              WHERE r.og_id = s.og_id
              ORDER BY r.ext_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS rna_extraction_status,
    s.ilrna AS rna_ilmn_sequencing,
        CASE
            WHEN s.rna_ilmn_sequencing = 'N'::text THEN ''::text
            ELSE COALESCE(( SELECT ri.rna_status
               FROM rna_library_ilmn ri
              WHERE ri.og_id = s.og_id AND ri.status_overwrite::text = 'Y'::text
              ORDER BY ri.rna_num DESC
             LIMIT 1), ( SELECT ri.rna_status
               FROM rna_library_ilmn ri
              WHERE ri.og_id = s.og_id
              ORDER BY ri.rna_num DESC
             LIMIT 1), 'Awaiting Status'::text)
        END AS rna_ilmn_status,
    s.rna_kinnex_sequencing,
        CASE
            WHEN s.rna_kinnex_sequencing = 'N'::text THEN ''::character varying
            ELSE COALESCE(( SELECT rk.rna_status
               FROM rna_library_kinx rk
              WHERE rk.og_id = s.og_id AND rk.status_overwrite::text = 'Y'::text
              ORDER BY rk.rna_num DESC
             LIMIT 1), ( SELECT rk.rna_status
               FROM rna_library_kinx rk
              WHERE rk.og_id = s.og_id
              ORDER BY rk.rna_num DESC
             LIMIT 1), 'Awaiting Status'::character varying)
        END AS rna_kinnex_status,
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
    s.summary_comments
   FROM sample s;;

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

