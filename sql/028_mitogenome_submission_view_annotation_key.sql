-- Key mitogenome_submission_view's ENA join on the full sequence identity
-- (assembly prefix + annotation) instead of the 4-field assembly prefix.
--
-- Background. Migration 014 re-keyed ena_validation_attempts from
-- assembly_prefix to full_seqid plus a separate annotation column, because what
-- the pipeline validates is a flatfile built from ONE ANNOTATION of one
-- assembly: OG82.ilmn.240313.getorg1770.emma102, not
-- OG82.ilmn.240313.getorg1770. mitogenome_submission_view was not updated with
-- it and kept joining on (og_id, tech, seq_date, code), which is the assembly
-- prefix -- one level coarser than either table's actual grain.
--
-- full_seqid is exactly og_id.tech.seq_date.code.annotation, verified on all
-- 1,185 rows, and mitogenome_data has no full_seqid column. So "key on
-- full_seqid" is implemented as component-wise equality including annotation,
-- which is equivalent to matching full_seqid and, unlike string concatenation,
-- can use an index. Note full_seqid already CONTAINS the annotation, so
-- "full_seqid + annotation" is one condition, not two.
--
-- The index for this join shape already exists.
-- ena_validation_attempts_identity_idx is on
-- (og_id, tech, seq_date, code, annotation) -- all five columns. The index was
-- built for the corrected grain; only the view had not caught up.
--
-- Joined to ena_validation_latest rather than ena_validation_attempts.
-- ena_validation_attempts_key_idx is UNIQUE on
-- (full_seqid, ena_study, validation_attempt), so the base table PERMITS several
-- rows per sequence identity -- a second ena_study or a re-validation attempt
-- would duplicate rows in this view. It does not happen today (1,185 rows across
-- 1,185 distinct identities, all PRJEB110568/initial), which is precisely why it
-- would not be noticed until it did. ena_validation_latest is DISTINCT ON
-- (full_seqid) ORDER BY recorded_at DESC, id DESC, so one row per sequence is
-- structurally guaranteed rather than dependent on current data. Verified the
-- two forms agree on every row today: 0 differing rows across all 2,301.
--
-- Effect. Row count is unchanged at 2,301 (this is a LEFT JOIN on the
-- mitogenome_data side). Matched ENA rows go from 1,182 to 1,180. The two rows
-- that lose their ENA columns are:
--
--   OG2951.ilmn.260909.getorg1770   mitogenome_data.annotation IS NULL
--   OG3000.ilmn.260909.getorg1770   mitogenome_data.annotation IS NULL
--
-- Both samples are reseed cases, and they are worth setting out in full because
-- they show exactly what the prefix-only join was getting wrong. Each sample has
-- two assemblies and two validation rows:
--
--   mitogenome_data                                 annotation   stats
--     OG2951.ilmn.260909.getorg1770                 NULL         1 scaffold(s)
--     OG2951.ilmn.260909.getorg1770reseed           mitos2110    circular genome
--
--   ena_validation_attempts                                      webin / table2asn
--     OG2951.ilmn.260909.getorg1770.mitos2110                    NOT_RUN / FAIL_TABLE2ASN
--     OG2951.ilmn.260909.getorg1770reseed.mitos2110              NOT_RUN / FAIL_TABLE2ASN
--
-- The first assembly came out as a single linear scaffold and was never
-- annotated, which is why it was reseeded; the reseed produced the circular
-- genome that carries the mitos2110 annotation. Because `code` differs between
-- them (getorg1770 vs getorg1770reseed), the 4-field join paired each
-- mitogenome_data row with its own ENA row and so matched both -- including
-- pairing the un-annotated row with a verdict for an annotation it does not
-- have. The 5-field join keeps the reseed pairing and drops the other, which is
-- the correct outcome: a row with no annotation has nothing for ENA to have
-- validated. The reseed rows keep their real verdicts (OG2951 NOT_RUN/FAIL,
-- OG3000 PASS/PASS), so no genuine validation result is lost.
--
-- Note what this leaves visible rather than hidden: ENA holds a validation row
-- for getorg1770.mitos2110 on both samples, an assembly/annotation pair
-- mitogenome_data has no annotated row for. That inconsistency between the two
-- tables was previously masked by the coarse join. It is not this migration's to
-- fix, but it should be looked at -- most likely the un-annotated assemblies were
-- validated before the reseed superseded them, and their ENA rows were never
-- retired.
--
-- Rows where mitogenome_data.annotation IS NULL (372 assembly prefixes) now
-- correctly match nothing, since NULL = 'x' is never true. That is the intended
-- behaviour, not an oversight.
--
-- The lca_validation join is NOT changed: it already included annotation.
--
-- CREATE OR REPLACE, not DROP + CREATE: the readonly role holds SELECT on this
-- view and a DROP would discard it silently (the trap migration 018 worked
-- around). The view has no dependent objects.
--
-- Follows 027_reporting_views_live_tables.sql, which repointed this view off the
-- SS260818 snapshot onto live mitogenome_data; that repoint is what made this
-- join's grain mismatch worth fixing rather than academic.
--
-- Idempotent: CREATE OR REPLACE VIEW.
--
-- Rollback: sql/revert/028_mitogenome_submission_view_annotation_key_revert.sql
--
--   psql -h 146.118.120.134 -p 5432 -U postgres -d oceanomics_genomes \
--        -f sql/028_mitogenome_submission_view_annotation_key.sql

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
     LEFT JOIN ena_validation_latest e
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
