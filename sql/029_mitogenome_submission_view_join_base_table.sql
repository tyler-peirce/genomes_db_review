-- Join ena_validation_attempts directly instead of ena_validation_latest.
-- Corrects the rationale in 028_mitogenome_submission_view_annotation_key.sql.
--
-- 028 got the fix right and the reason wrong. Keying the ENA join on the full
-- sequence identity (assembly prefix + annotation) rather than the 4-field
-- assembly prefix was correct and is retained unchanged. But 028 routed the join
-- through ena_validation_latest on the grounds that ena_validation_attempts
-- "PERMITS several rows per sequence identity", so a re-validation or a second
-- ena_study would duplicate rows in this view. That is wrong: a rerun overwrites
-- its row, it does not append one.
--
-- The overwrite is the documented design.
-- 002_ena_validation_attempts_single_row_per_attempt.sql exists precisely to
-- collapse the table to one row per (full_seqid, ena_study, validation_attempt)
-- "so pipeline reruns overwrite the previous attempt instead of appending a new
-- history row every time", and it added attempt_count to carry the rerun tally
-- inside the surviving row. 015's header states the writer's side of the same
-- contract: bin/push_ena_validation_results.py upserts "with DO UPDATE SET
-- across every non-key column", which is why 015 put the submission ledger in
-- its own table rather than adding accession columns here.
--
-- The data confirms it. attempt_count reaches 6, and 739 of 1,185 rows sit above
-- 1:
--
--   attempt_count   rows
--               1    446
--               2    385
--               3    321
--               4     28
--               5      2
--               6      3
--
-- Those 739 rows are reruns that overwrote in place. Had reruns appended, the
-- table would hold several thousand rows and attempt_count would be 1
-- everywhere. The 2026-09-30 batch is the clearest case: 5 rows recorded that
-- day with attempt_count between 4 and 6.
--
-- The other two key columns do not vary either -- ena_study is PRJEB110568 on
-- all 1,185 rows, validation_attempt is 'initial' on all 1,185, validation_mode
-- is 'pipeline' on all 1,185 -- so in practice the unique key is full_seqid
-- alone, and the 5-field identity join already selects exactly one row.
--
-- So DISTINCT ON bought nothing, and it was not merely redundant. Fan-out, had
-- it ever been possible, is VISIBLE: duplicate rows in a report get noticed.
-- DISTINCT ON (full_seqid) instead picks one row by recorded_at and silently
-- discards the rest, which is the worse failure mode of the two -- and it
-- discards on full_seqid, ignoring the ena_study and validation_attempt that
-- would have been the only reason a second row existed. Guarding against an
-- impossible duplicate by installing a silent row-selector is a bad trade.
--
-- Cost. The DISTINCT ON forced a Sort + Unique over all 1,185 rows on every
-- execution of the view. Removing it drops the plan from 486.17 to 412.50 and
-- leaves two hash joins over sequential scans, which is the right plan at this
-- size. The identity index ena_validation_attempts_identity_idx
-- (og_id, tech, seq_date, code, annotation) remains available for single-sequence
-- lookups against the view.
--
-- Results are unchanged: 2,301 rows, 1,180 matched ENA rows, verified as 0
-- differing rows across all 2,301 against the 028 definition before applying.
-- This migration is a simplification and a correction of the written reasoning,
-- not a change in output.
--
-- CREATE OR REPLACE, not DROP + CREATE: the readonly role holds SELECT on this
-- view and a DROP would discard it silently (the trap 018 worked around).
--
-- Idempotent: CREATE OR REPLACE VIEW.
--
-- Rollback: sql/revert/029_mitogenome_submission_view_join_base_table_revert.sql
-- restores the 028 definition.
--
--   psql -h 146.118.120.134 -p 5432 -U postgres -d oceanomics_genomes \
--        -f sql/029_mitogenome_submission_view_join_base_table.sql

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
     LEFT JOIN ena_validation_attempts e
       ON e.og_id = m.og_id
      AND e.tech = m.tech
      AND e.seq_date = m.seq_date
      AND e.code = m.code
      AND e.annotation::text = m.annotation::text
     LEFT JOIN lca_validation l
       ON l.og_id = m.og_id
      AND l.tech = m.tech
      AND l.seq_date = m.seq_date
      AND l.code::text = m.code
      AND l.annotation::text = m.annotation::text;

COMMIT;
