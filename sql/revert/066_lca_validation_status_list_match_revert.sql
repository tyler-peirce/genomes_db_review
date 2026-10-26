-- 066_lca_validation_status_list_match_revert.sql -- back to 065: lca_pivot_view takes
-- max(species_in_lca) per region, validation_status needs the nominal ID to equal a whole list,
-- and lca_validation_report_view has nom_id_in_results again (with its trigger and readonly grant).
--
-- After running this, delete 066's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '066_lca_validation_status_list_match.sql';

BEGIN;

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

COMMIT;
