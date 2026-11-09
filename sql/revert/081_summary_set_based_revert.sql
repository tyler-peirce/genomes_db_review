-- Revert 081_summary_set_based.sql: restore summary and goat_species_v1 as they were before 081,
-- and summary's comment.
--     psql -f sql/revert/081_summary_set_based_revert.sql   then delete 081's ledger row.

BEGIN;

-- goat_species_v1 as before 081 (pg_get_viewdef of live, 2026-11-09).
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
  ORDER BY s.family, s.species;

-- summary as before 081 (pg_get_viewdef of live, 2026-11-09).
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
         LIMIT 1) rkin ON true;

COMMENT ON VIEW public.summary IS 'The workbook''s Summary sheet, computed from the child tables instead of copied from Excel (decision 5). This replaces the nine derived columns removed from sample, and fixes the status fragmentation of database_review.md Finding 7 at source: the 47 distinct rna_status values were Excel string concatenation being persisted. Each technology also reports planned (lab intent) against actual (counted). Takes about 2 s (backlog item 10).';

COMMIT;
