-- 033_catchup_core_views.sql
--
-- Purpose: bring the eight cutover-neutral reporting views under migration
-- management, plus the trigger that makes one of them writable.
--
-- Review source: database_review.md Phase B.3, Finding 1, Finding 10.
--
-- What this is and is not
-- -----------------------
-- This is a catch-up migration. It creates nothing new: all eight views have
-- been running for months, created by direct DDL, described by no migration and
-- reproducible only from the pg_dump snapshot in schema/current_views.sql.
-- `bin/check_drift.py --coverage` listed them as "baseline-only" -- rebuildable
-- as a point-in-time dump with no history and no rationale.
--
-- Catch-up migrations are normally a bad trade: writing one that describes the
-- status quo, then a second that changes it, produces two migrations where one
-- would do, and the first carries no rationale because there is none to record.
-- Phase B.3 therefore routed 39 of the 49 uncovered objects into the phases that
-- already rework them, so their CREATE ships alongside the change that explains
-- it. These eight are the exception: nothing in the plan rewrites them.
-- `docs/v2_cutover_dependencies.md` audited all eleven views column by column
-- and found these eight cutover-neutral -- every column they read survives into
-- v2, so a search_path swap is sufficient and no DDL is needed. Capturing them
-- now is therefore not wasted work even if the v2 cutover later proceeds. The
-- two views that are NOT neutral -- summary and goat_species_v1 -- are
-- deliberately absent; they are rebuilt by the v2 scaffold and by Phase D.
--
-- Definitions are taken verbatim from pg_get_viewdef(oid, true) against the live
-- database, not from the baseline file, so the text matches what is actually
-- running. Names are left unqualified on purpose: that is what makes the v2
-- cutover a search_path swap rather than an edit of every view.
--
-- Order
-- -----
-- Emitted in topological order, read from pg_rewrite/pg_depend rather than
-- guessed:
--
--     lca_pivot_view
--       -> lca_results_view
--            -> filtered_lca_view
--     sample_view
--       -> lca_validation_report_view  (also reads the three above)
--     coverage_summary, goat_project_metadata_v1, v_genome_size_comparison
--       (no view dependencies)
--
-- lca_validation_report_view is updatable
-- ---------------------------------------
-- It is not a read-only report. An INSTEAD OF UPDATE trigger routes writes
-- through lca_validation_report_view_upd(), so the view is a write path for
-- validation decisions. A catch-up migration that captured only the view
-- definition would silently drop that path on any rebuild, so the function and
-- trigger are included below.
--
-- That same function is also the trigger body for
-- lca_validation_report_view_SS260818. Phase F drops the snapshot views but
-- must KEEP this function -- it is shared, not snapshot-specific. CREATE OR
-- REPLACE FUNCTION here does not disturb the snapshot's trigger.
--
-- Known limitation -- read before relying on this
-- -----------------------------------------------
-- This makes these objects *described*, not yet *rebuildable from an empty
-- database*. Every one of them reads base tables that are still themselves
-- baseline-only: sample, tissue, the lab tables, lca, raw_qc and the rest get
-- their own CREATEs in Phase C, Phase E, or the v2 cutover. Run against an
-- empty database, this file fails on a missing relation, by design. The success
-- criterion "the schema can be recreated from source-controlled migrations"
-- stays NO until those phases land. What this file buys is history and
-- rationale for the eight objects, and --coverage moving 12 -> 22 of 64.
--
-- Rejected: dropping and recreating each view instead of CREATE OR REPLACE.
-- DROP would cascade to the trigger on lca_validation_report_view and to any
-- dependent view, and would briefly remove reporting objects that external
-- DBeaver users query directly. CREATE OR REPLACE cannot change a view's column
-- names or types, which means a definition that has drifted from this file
-- surfaces as an error rather than as a silent rewrite. That is the safer
-- failure mode for a file whose whole purpose is to match what is already there.
--
-- Expected impact: none. Every statement is a no-op against the live database.
-- Verified by diffing pg_get_viewdef for all eight views before and after, and
-- by comparing per-view row counts.

BEGIN;

-- lca_pivot_view: Pivots lca into one row per og_id. Read by lca_results_view.
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
  GROUP BY lca.og_id, lca.tech, lca.seq_date, lca.code, lca.annotation;

-- lca_results_view: LCA results joined to sample/species. Reads lca_pivot_view.
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
     JOIN sample s ON lp.og_id_lp = s.og_id;

-- filtered_lca_view: Confidence-filtered subset of lca_results_view.
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
  GROUP BY b.og_id, b.tech, b.seq_date, b.code, b.annotation;

-- sample_view: Sample identifiers and voucher fields. Read by lca_validation_report_view.
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
          WHERE lv.og_id = s.og_id));

-- lca_validation_report_view: Species-ID validation report. UPDATABLE -- see the trigger below.
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
     LEFT JOIN sample_view sv ON lv.og_id = sv.og_id_sv;

-- coverage_summary: Per-sample read coverage across hifi_reads_qc, hic_reads_qc and raw_qc.
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
  ORDER BY a.og_id;

-- goat_project_metadata_v1: Static project metadata for the GoaT API. Constants only.
CREATE OR REPLACE VIEW public.goat_project_metadata_v1 AS
 SELECT 'Ocean Genomes'::text AS project_name,
    'OG'::text AS project_acronym,
    NULL::text AS subproject_name,
    NULL::text AS bioproject_id,
    'Shannon Corrigan'::text AS primary_contact,
    'Ocean Genomes Minderoo OceanOmics Centre, The University of Western Australia'::text AS primary_contact_institution,
    'oceangenomes@uwa.edu.au'::text AS public_contact_email,
    CURRENT_DATE AS date_of_last_update,
    'ebp_species_goat_3.0'::text AS schema_version;

-- v_genome_size_comparison: Assembly size vs expected genome size per species.
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
     LEFT JOIN species_ncbi_assembly a ON a.species = sp.species AND a.is_chosen;

-- ---------------------------------------------------------------------------
-- The INSTEAD OF UPDATE write path on lca_validation_report_view.
-- Shared with lca_validation_report_view_SS260818's trigger -- Phase F drops
-- that view but must not drop this function.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.lca_validation_report_view_upd()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Optional safety: prevent attempts to change the identifying fields via the view
  IF NEW.og_id IS DISTINCT FROM OLD.og_id
     OR NEW.tech IS DISTINCT FROM OLD.tech
     OR NEW.seq_date IS DISTINCT FROM OLD.seq_date
     OR NEW.code IS DISTINCT FROM OLD.code
     OR NEW.annotation IS DISTINCT FROM OLD.annotation
  THEN
    RAISE EXCEPTION
      'Cannot change key fields (og_id, tech, seq_date, code, annotation) through lca_validation_report_view';
  END IF;

  -- Persist only the editable columns back to the base table.
  UPDATE lca_validation
  SET validated_species_name         = NEW.validated_species_name,
      validator                      = NEW.validator,
      validator_2                    = NEW.validator_2,
      nominal_species_id_lca_comment = NEW.comment
  WHERE og_id       = OLD.og_id
    AND tech        = OLD.tech
    AND seq_date    = OLD.seq_date
    AND code        = OLD.code
    AND annotation  = OLD.annotation;

  -- If no row was updated, something is off (missing row or key mismatch).
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Update failed: no matching row in lca_validation for (og_id=%, tech=%, seq_date=%, code=%, annotation=%)',
      OLD.og_id, OLD.tech, OLD.seq_date, OLD.code, OLD.annotation;
  END IF;

  RETURN NEW;
END;
$function$;

-- CREATE TRIGGER has no IF NOT EXISTS and no OR REPLACE on PostgreSQL 14.
-- Drop-then-create keeps the file idempotent; inside this transaction the view
-- is never visible without its trigger.
DROP TRIGGER IF EXISTS trg_lca_validation_report_view_upd
    ON public.lca_validation_report_view;

CREATE TRIGGER trg_lca_validation_report_view_upd
    INSTEAD OF UPDATE ON public.lca_validation_report_view
    FOR EACH ROW EXECUTE FUNCTION lca_validation_report_view_upd();

COMMIT;
