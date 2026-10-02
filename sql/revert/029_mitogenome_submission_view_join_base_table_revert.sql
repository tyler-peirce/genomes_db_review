-- Revert 029_mitogenome_submission_view_join_base_table.sql.
--
-- Restores the 028 definition, i.e. the ENA join routed through
-- ena_validation_latest. That reinstates a Sort + Unique over all 1,185
-- ena_validation_attempts rows on every execution, and a silent
-- DISTINCT ON (full_seqid) row-selector guarding against a duplicate the
-- upsert design does not produce. See 029's header. Use only to undo a bad
-- deploy.

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
     LEFT JOIN ena_validation_latest e ON e.og_id = m.og_id AND e.tech = m.tech AND e.seq_date = m.seq_date AND e.code = m.code AND e.annotation = m.annotation::text
     LEFT JOIN lca_validation l ON l.og_id = m.og_id AND l.tech = m.tech AND l.seq_date = m.seq_date AND l.code::text = m.code AND l.annotation::text = m.annotation::text;

COMMIT;
