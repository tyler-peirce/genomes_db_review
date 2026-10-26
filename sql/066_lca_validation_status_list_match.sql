-- 066_lca_validation_status_list_match.sql -- validation_status looks for the nominal ID in the
-- LCA species lists; nom_id_in_results goes.
--
-- Why. Owner, 2026-10-26: every candidate species is in the LCA output, so the report's
-- nom_id_in_results (YES when blast_filtered_lca has a hit named as the nominal ID) says nothing
-- the LCA does not. The check belongs in validation_status. That already read s12_lca, s16_lca and
-- co1_lca, but with =, and each holds a comma-separated species list, so it passed only when the
-- LCA came down to one species. Live, 2026-10-26: 1,025 matched, 919 INVESTIGATE (15 of them
-- MISSING NOMINAL ID aside). Matching on list membership moves 396 to matched; 523 stay INVESTIGATE.
--
-- The filtered_12s/16s/co1 accession columns stay, and with them filtered_lca_view. They name the
-- BLAST hits to the nominal species, which is how a reviewer sees that the support is only our
-- own reference sequences, or the sample's own earlier run.
--
-- How.
--   1. lca_pivot_view: each region's list is the union of species over every LCA run. lca keeps
--      re-runs (its key includes content_hash): 66 key+region groups have two lca_run_dates, and in
--      9 the lists differ. max(species_in_lca) showed whichever list sorted last -- not the latest
--      run -- so OG3091's regions mixed two runs. Tokens are sorted COLLATE "C", which is how the
--      pipeline writes them: all 5,298 single-run groups rebuild to their current string, and only
--      OG2617, OG2618 and OG3091 change. The outer COLLATE "default" keeps the columns' collation,
--      which CREATE OR REPLACE would otherwise refuse to change.
--   2. lca_results_view: the nominal ID matches a whole list entry, trimmed, with any ';Genus'
--      suffix the LCA appends ('Favia fragum;Colpophyllia') cut off. So 'Inimicus sinensis' does
--      not match 'Inimicus sinensis?', and a genus-level nominal ID does not match the stray genus
--      after a ';' -- OG2940 (Neolithodes) and OG3090 (Cyrtomaia) stay INVESTIGATE for that reason.
--      The outputs are unchanged: the species name, 'INVESTIGATE' or 'MISSING NOMINAL ID'.
--   3. lca_validation_report_view without nom_id_in_results. A view cannot lose a column through
--      CREATE OR REPLACE, so it is dropped and created. It is a write path: the INSTEAD OF UPDATE
--      trigger (lca_validation_report_view_upd(), see 033) is recreated with it, and readonly's
--      SELECT is granted again. Nothing depends on the view. The drop is guarded on the column, so
--      a replay leaves the view, its trigger and its grants alone.
--
-- Rejected: keeping only the latest LCA run per region. The owner wants every run's species
-- considered.
--
-- Revert: sql/revert/066_lca_validation_status_list_match_revert.sql.

BEGIN;

CREATE OR REPLACE VIEW public.lca_pivot_view AS
 SELECT regexp_replace(lca.og_id, 'OG'::text, ''::text, 'g'::text)::integer AS og_num,
    lca.og_id AS og_id_lp,
    lca.tech,
    lca.seq_date,
    lca.code,
    lca.annotation,
    (string_agg(DISTINCT t.sp, ', '::text ORDER BY t.sp) FILTER (WHERE lca.region = '12s'::text)) COLLATE "default" AS s12_lca,
    (string_agg(DISTINCT t.sp, ', '::text ORDER BY t.sp) FILTER (WHERE lca.region = '16s'::text)) COLLATE "default" AS s16_lca,
    (string_agg(DISTINCT t.sp, ', '::text ORDER BY t.sp) FILTER (WHERE lca.region = 'CO1'::text)) COLLATE "default" AS co1_lca
   FROM lca
     LEFT JOIN LATERAL ( SELECT btrim(x.x) COLLATE "C" AS sp
           FROM unnest(string_to_array(lca.species_in_lca, ','::text)) x(x)
          WHERE btrim(x.x) <> ''::text) t ON true
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
            WHEN s.nominal_species_id = ANY (ARRAY( SELECT split_part(btrim(t.t), ';'::text, 1) AS split_part
               FROM unnest(string_to_array(concat_ws(','::text, lp.s12_lca, lp.s16_lca, lp.co1_lca), ','::text)) t(t))) THEN s.nominal_species_id
            ELSE 'INVESTIGATE'::text
        END AS validation_status
   FROM lca_pivot_view lp
     JOIN sample s ON lp.og_id_lp = s.og_id;

DO $report$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_attribute
                 WHERE attrelid = 'public.lca_validation_report_view'::regclass
                   AND attname = 'nom_id_in_results' AND NOT attisdropped) THEN
    RAISE NOTICE '066: lca_validation_report_view has no nom_id_in_results, leaving it alone';
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
END
$report$;

DO $check$
BEGIN
  RAISE NOTICE '066: lca_results_view validation_status: % matched, % INVESTIGATE, % MISSING NOMINAL ID',
    (SELECT count(*) FROM public.lca_results_view
      WHERE validation_status NOT IN ('INVESTIGATE', 'MISSING NOMINAL ID')),
    (SELECT count(*) FROM public.lca_results_view WHERE validation_status = 'INVESTIGATE'),
    (SELECT count(*) FROM public.lca_results_view WHERE validation_status = 'MISSING NOMINAL ID');
END
$check$;

COMMIT;
