-- Revert 027_reporting_views_live_tables.sql.
--
-- Restores summary, embargo_assignment_view and mitogenome_submission_view to
-- the snapshot-reading definitions captured from pg_get_viewdef immediately
-- before 027 was applied on 2026-10-02.
--
-- Restoring these re-introduces the staleness 027 fixed (61 og_ids missing, 39
-- stale). Use only to undo a bad deploy, not as a steady state.

BEGIN;

CREATE OR REPLACE VIEW summary AS
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
           FROM "lca_validation_SS260818" lv
          WHERE lv.og_id = s.og_id AND lv.tech = 'ilmn'::text AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> ''::text) AS ilmn_validated_species_name,
    ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS string_agg
           FROM "lca_validation_SS260818" lv
          WHERE lv.og_id = s.og_id AND lv.tech = 'hifi'::text AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> ''::text) AS hifi_validated_species_name,
    ( SELECT string_agg(DISTINCT lv.validated_species_name, ', '::text ORDER BY lv.validated_species_name) AS string_agg
           FROM "lca_validation_SS260818" lv
          WHERE lv.og_id = s.og_id AND lv.tech = 'hic'::text AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> ''::text) AS hic_validated_species_name,
    s.field_id,
    s.nominal_species_id,
    s.common_name,
    s.collector,
    s.contact,
    s.summary_comments
   FROM sample s;

CREATE OR REPLACE VIEW embargo_assignment_view AS
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
           FROM "lca_validation_SS260818" lv
          WHERE lv.og_id = s.og_id) lv1 ON true;

CREATE OR REPLACE VIEW mitogenome_submission_view AS
 SELECT m.og_num,
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
   FROM "mitogenome_data_SS260818" m
     LEFT JOIN ena_validation_attempts e ON e.og_id = m.og_id AND e.tech = m.tech AND e.seq_date = m.seq_date AND e.code = m.code
     LEFT JOIN "lca_validation_SS260818" l ON l.og_id = m.og_id AND l.tech = m.tech AND l.seq_date = m.seq_date AND l.code::text = m.code AND l.annotation::text = m.annotation::text;

COMMIT;
