-- 084_lca_validation_escalate_investigate.sql -- escalate and investigate flags on
-- mito_lca_validation; per-gene LCA results in lca_validation_report_view.
--
-- Why. Owner, 2026-11-11: curators need two yes/no flags on each validation row, escalate and
-- investigate, set in OceanGenom_Web through the report and shown right after validator_2. The
-- report's lca_taxon_ranks ('family, genus, species') named no gene, so a reader could not tell
-- which region stopped at which rank. It is replaced by one column per gene that gives the rank and
-- the taxon the LCA resolved to there: s12_lca_taxon, s16_lca_taxon, co1_lca_taxon, e.g. 'genus: Etelis'.
--
-- How.
--   1. mito_lca_validation gains escalate and investigate, boolean NOT NULL DEFAULT false, so all
--      2,056 existing rows (live, 2026-11-11) read 'no'. The writers push_species_validation.py
--      (INSERT with a column list) and push_qc_validator.py (UPDATE) name neither column and need
--      no change.
--   2. lca_validation (076's compatibility view) gets the two columns at the end. A view can gain
--      trailing columns through CREATE OR REPLACE, which keeps its grants and comment.
--   3. lca_validation_report_view_upd() writes escalate and investigate as well, so they can be
--      edited through the report.
--   4. lca_validation_report_view is dropped and created, because columns move: escalate and
--      investigate go after validator_2, and the three gene columns take lca_taxon_ranks' place.
--      Each gene column shows '<taxon_rank>: <name>'. The name comes from the mito_lca column for that
--      rank (species, genus, family, order, class, phylum), and any other rank ('not applicable:
--      domain level dropped') shows the rank alone. Re-runs are unioned, as in 066 (the owner
--      wants every run considered): 17 annotation+region groups have runs that differ in rank,
--      and they read e.g. 'family: Lutjanidae, genus: Etelis'. The trigger, readonly's SELECT and
--      079's comment are put back. Nothing depends on the view. The drop is guarded on escalate, so
--      a replay leaves the view, its trigger and its grants alone.
--
-- Rejected: showing the latest run only, for the reason in 066.
--
-- OceanGenom_Web reads this view. lca_taxon_ranks is gone and the later columns have moved.
--
-- Revert: sql/revert/084_lca_validation_escalate_investigate_revert.sql.

BEGIN;

ALTER TABLE public.mito_lca_validation
  ADD COLUMN IF NOT EXISTS escalate boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS investigate boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.mito_lca_validation.escalate IS
  'Curator flag: escalate this validation for a senior reviewer. Set through lca_validation_report_view in OceanGenom_Web. Default false (084).';
COMMENT ON COLUMN public.mito_lca_validation.investigate IS
  'Curator flag: this validation needs further investigation. Set through lca_validation_report_view in OceanGenom_Web. Default false (084).';

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
    t.escalate,
    t.investigate
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

    -- Persist only the editable columns back to the base table (mito_lca_validation since 076;
    -- escalate and investigate since 084).
    UPDATE mito_lca_validation
    SET validated_species_name         = NEW.validated_species_name,
        validator                      = NEW.validator,
        validator_2                    = NEW.validator_2,
        escalate                       = NEW.escalate,
        investigate                    = NEW.investigate,
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

DO $report$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_attribute
             WHERE attrelid = 'public.lca_validation_report_view'::regclass
               AND attname = 'escalate' AND NOT attisdropped) THEN
    RAISE NOTICE '084: lca_validation_report_view already has escalate, leaving it alone';
    RETURN;
  END IF;

  DROP VIEW public.lca_validation_report_view;

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
      lv.escalate,
      lv.investigate,
      lca_tax.s12_lca_taxon,
      lca_tax.s16_lca_taxon,
      lca_tax.co1_lca_taxon,
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
       LEFT JOIN ( SELECT l.og_id,
              l.tech,
              l.seq_date,
              l.code,
              l.annotation,
              string_agg(DISTINCT l.rank_taxon, ', '::text ORDER BY l.rank_taxon) FILTER (WHERE l.region = '12s'::text) AS s12_lca_taxon,
              string_agg(DISTINCT l.rank_taxon, ', '::text ORDER BY l.rank_taxon) FILTER (WHERE l.region = '16s'::text) AS s16_lca_taxon,
              string_agg(DISTINCT l.rank_taxon, ', '::text ORDER BY l.rank_taxon) FILTER (WHERE l.region = 'CO1'::text) AS co1_lca_taxon,
              string_agg(DISTINCT l."order", ', '::text ORDER BY l."order") AS lca_orders,
              string_agg(DISTINCT l.family, ', '::text ORDER BY l.family) AS lca_families,
              string_agg(DISTINCT l.genus, ', '::text ORDER BY l.genus) AS lca_genera,
              string_agg(DISTINCT l.specific_epiphet, ', '::text ORDER BY l.specific_epiphet) AS lca_specific_epiphets
             FROM ( SELECT lca.og_id,
                    lca.tech,
                    lca.seq_date,
                    lca.code,
                    lca.annotation,
                    lca.region,
                    lca."order",
                    lca.family,
                    lca.genus,
                    lca.specific_epiphet,
                    CASE
                        WHEN lca.taxon_rank IS NULL THEN NULL::text
                        ELSE concat_ws(': '::text, lca.taxon_rank,
                            CASE lca.taxon_rank
                                WHEN 'species'::text THEN lca.species
                                WHEN 'genus'::text THEN lca.genus
                                WHEN 'family'::text THEN lca.family
                                WHEN 'order'::text THEN lca."order"
                                WHEN 'class'::text THEN lca.class
                                WHEN 'phylum'::text THEN lca.phylum
                                ELSE NULL::text
                            END)
                    END AS rank_taxon
                   FROM lca) l
            GROUP BY l.og_id, l.tech, l.seq_date, l.code, l.annotation) lca_tax ON lca_tax.og_id = lv.og_id AND lca_tax.tech = lv.tech AND lca_tax.seq_date = lv.seq_date AND lca_tax.code = lv.code AND lca_tax.annotation = lv.annotation
       LEFT JOIN sample_view sv ON lv.og_id = sv.og_id_sv;

  CREATE TRIGGER trg_lca_validation_report_view_upd
    INSTEAD OF UPDATE ON public.lca_validation_report_view
    FOR EACH ROW EXECUTE FUNCTION public.lca_validation_report_view_upd();

  GRANT SELECT ON public.lca_validation_report_view TO readonly;

  COMMENT ON VIEW public.lca_validation_report_view IS
    'The LCA validation report, one row per mito_lca_validation row, for curators in OceanGenom_Web. Updatable through trigger trg_lca_validation_report_view_upd (the validation fields only; the key fields are refused).';
END
$report$;

COMMENT ON COLUMN public.lca_validation_report_view.escalate IS
  'mito_lca_validation.escalate. Editable through this view.';
COMMENT ON COLUMN public.lca_validation_report_view.investigate IS
  'mito_lca_validation.investigate. Editable through this view.';
COMMENT ON COLUMN public.lca_validation_report_view.s12_lca_taxon IS
  '12S LCA result as ''<taxon_rank>: <taxon>'' (e.g. ''genus: Etelis''), every LCA run unioned, '', ''-joined.';
COMMENT ON COLUMN public.lca_validation_report_view.s16_lca_taxon IS
  '16S LCA result as ''<taxon_rank>: <taxon>'', every LCA run unioned, '', ''-joined.';
COMMENT ON COLUMN public.lca_validation_report_view.co1_lca_taxon IS
  'CO1 LCA result as ''<taxon_rank>: <taxon>'', every LCA run unioned, '', ''-joined.';

DO $check$
DECLARE
  n_base bigint := (SELECT count(*) FROM public.mito_lca_validation);
  n_view bigint := (SELECT count(*) FROM public.lca_validation_report_view);
BEGIN
  IF n_view <> n_base THEN
    RAISE EXCEPTION '084: lca_validation_report_view has % rows, mito_lca_validation has %', n_view, n_base;
  END IF;
  RAISE NOTICE '084: % rows; escalate true %, investigate true %; 12S % / 16S % / CO1 % with an LCA result',
    n_view,
    (SELECT count(*) FROM public.mito_lca_validation WHERE escalate),
    (SELECT count(*) FROM public.mito_lca_validation WHERE investigate),
    (SELECT count(s12_lca_taxon) FROM public.lca_validation_report_view),
    (SELECT count(s16_lca_taxon) FROM public.lca_validation_report_view),
    (SELECT count(co1_lca_taxon) FROM public.lca_validation_report_view);
END
$check$;

COMMIT;
