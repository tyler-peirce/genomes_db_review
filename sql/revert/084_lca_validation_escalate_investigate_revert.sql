-- 084_lca_validation_escalate_investigate_revert.sql -- undo 084.
--
-- Puts back lca_validation_report_view as it was after 076 (lca_taxon_ranks, no flags), along with
-- its trigger, grant and comment, and the 076 trigger function. lca_validation cannot lose its two
-- trailing columns: CREATE OR REPLACE cannot remove columns, and the view cannot be dropped
-- because embargo_assignment_view, mitogenome_submission_view, sample_view and summary (and
-- goat_species_v1 through summary) depend on it. So the revert keeps escalate and investigate on
-- the view as NULL::boolean placeholders, which no longer reference the table, and then drops the
-- columns from mito_lca_validation. Re-applying 084 points them back at the table.
-- **Any escalate/investigate values curators have set are lost.** Export them first if they matter.

BEGIN;

DROP VIEW IF EXISTS public.lca_validation_report_view;

CREATE OR REPLACE VIEW public.lca_validation AS
 SELECT a.og_id,
    a.tech,
    t.validated_species_name,
    t.validator,
    t.nominal_species_id_lca_comment,
    t.validator_2,
    t.data_release,
    t.validated_rank,
    t.lca_genus,
    a.seq_date,
    a.code,
    an.annotation,
    t.row_created_on,
    t.annotation_id,
    NULL::boolean AS escalate,
    NULL::boolean AS investigate
   FROM mito_lca_validation t
     JOIN mito_annotation an ON an.annotation_id = t.annotation_id
     JOIN mito_assembly a ON a.assembly_id = an.assembly_id;

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

    -- Persist only the editable columns back to the base table (mito_lca_validation since 076).
    UPDATE mito_lca_validation
    SET validated_species_name         = NEW.validated_species_name,
        validator                      = NEW.validator,
        validator_2                    = NEW.validator_2,
        nominal_species_id_lca_comment = NEW.comment
    WHERE annotation_id = mito_annotation_id(OLD.og_id, OLD.tech, OLD.seq_date, OLD.code, OLD.annotation, false);

    -- If no row was updated, something is off (missing row or key mismatch).
    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Update failed: no matching row in lca_validation for (og_id=%, tech=%, seq_date=%, code=%, annotation=%)',
        OLD.og_id, OLD.tech, OLD.seq_date, OLD.code, OLD.annotation;
    END IF;

    RETURN NEW;
  END;
  $function$;

CREATE VIEW public.lca_validation_report_view AS
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
     LEFT JOIN sample_view sv ON lv.og_id = sv.og_id_sv;

CREATE TRIGGER trg_lca_validation_report_view_upd
  INSTEAD OF UPDATE ON public.lca_validation_report_view
  FOR EACH ROW EXECUTE FUNCTION public.lca_validation_report_view_upd();
GRANT SELECT ON public.lca_validation_report_view TO readonly;
COMMENT ON VIEW public.lca_validation_report_view IS
  'The LCA validation report, one row per mito_lca_validation row, for curators in OceanGenom_Web. Updatable through trigger trg_lca_validation_report_view_upd (the validation fields only; the key fields are refused).';

ALTER TABLE public.mito_lca_validation
  DROP COLUMN IF EXISTS escalate,
  DROP COLUMN IF EXISTS investigate;

COMMIT;
