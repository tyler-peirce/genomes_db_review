-- Repoint the three general-purpose reporting views off the frozen SS260818
-- snapshots and onto the live tables.
--
-- Background. The August 2026 rebuild of the LCA/mitogenome tables left frozen
-- copies behind as mitogenome_data_SS260818 / lca_validation_SS260818 (and
-- siblings). Three views that are NOT snapshot views kept reading them:
--
--   summary                      3 references to lca_validation_SS260818
--   embargo_assignment_view      1 reference  to lca_validation_SS260818
--   mitogenome_submission_view   mitogenome_data_SS260818 + lca_validation_SS260818
--
-- These are the surfaces humans read, so they have been wrong in both
-- directions since 2026-08-18: 61 og_ids that have live LCA validation did not
-- appear at all, and 39 og_ids appeared carrying validation the live pipeline no
-- longer holds. The divergence grew with every pipeline run.
--
-- The explicitly-named snapshot views (lca_pivot_view_SS260818,
-- lca_results_view_SS260818, lca_validation_report_view_SS260818) are left
-- alone: their names say what they read, which is the behaviour we want.
--
-- This migration changes ONLY the table names. Every referenced column exists on
-- the live tables with an identical type -- the live tables are strict supersets
-- (lca_validation gained lca_genus and validated_rank; mitogenome_data gained 21
-- columns across migrations 003/021/023/025/026) -- so the SELECT lists, the
-- join predicates and the output column types are untouched. Verified by diffing
-- pg_get_viewdef before and after: 5 changed lines across the three views, all
-- of them a table name.
--
-- CREATE OR REPLACE, deliberately, not DROP + CREATE. The readonly role holds
-- SELECT on all three views and a DROP would discard that silently -- the same
-- trap migration 018 had to work around when it rebuilt mitogenome_data. Neither
-- view has any dependent object, so replacement is safe.
--
-- KNOWN ISSUE, deliberately NOT fixed here. mitogenome_submission_view joins
-- ena_validation_attempts on the 4-field assembly prefix
-- (og_id, tech, seq_date, code). Migration 014 re-keyed that table on full_seqid
-- plus annotation, so the correct join now includes e.annotation = m.annotation.
-- The prefix-only join currently attaches ENA validation data to 2 rows whose
-- annotation does not actually match (1,182 joined rows vs 1,180 with an
-- annotation-aware join). It does not fan out TODAY only because every assembly
-- prefix in mitogenome_data carries at most one annotation (1,929 prefixes with
-- one, 372 with none) and ena_validation_attempts holds exactly one row per
-- prefix (1,185 rows / 1,185 prefixes). The first assembly to be annotated twice
-- and validated twice will silently duplicate rows in this view. Changing the
-- join changes what the view reports, which is a reporting decision rather than
-- a repoint, so it is left for its own migration.
--
-- Idempotent: CREATE OR REPLACE VIEW, and the definitions already name the live
-- tables after the first run.
--
-- Rollback: sql/revert/027_reporting_views_live_tables_revert.sql restores the
-- snapshot-reading definitions verbatim.
--
-- Applied by bin/apply_ena_migrations.py, or manually:
--
--   psql -h 146.118.120.134 -p 5432 -U postgres -d oceanomics_genomes \
--        -f sql/027_reporting_views_live_tables.sql

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
           FROM lca_validation lv
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
   FROM mitogenome_data m
     LEFT JOIN ena_validation_attempts e ON e.og_id = m.og_id AND e.tech = m.tech AND e.seq_date = m.seq_date AND e.code = m.code
     LEFT JOIN lca_validation l ON l.og_id = m.og_id AND l.tech = m.tech AND l.seq_date = m.seq_date AND l.code::text = m.code AND l.annotation::text = m.annotation::text;

COMMIT;
