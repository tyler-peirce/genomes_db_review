-- Revert 028_mitogenome_submission_view_annotation_key.sql.
--
-- Restores the definition captured from pg_get_viewdef immediately before 028
-- was applied on 2026-10-02 -- i.e. the ENA join back on the 4-field assembly
-- prefix (og_id, tech, seq_date, code) against the ena_validation_attempts base
-- table.
--
-- Restoring this re-introduces both problems 028 fixed: the ENA verdict is
-- attached to 2 rows whose annotation does not match (OG2951, OG3000), and the
-- view will silently duplicate rows once any sequence identity acquires a second
-- validation attempt or ena_study. Use only to undo a bad deploy.

BEGIN;

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
