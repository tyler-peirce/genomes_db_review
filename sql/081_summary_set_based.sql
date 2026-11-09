-- 081_summary_set_based.sql -- Rebuild summary set-based; tied latest statuses all show.
--
-- Backlog Highest 10, Finding 8. summary took 1.75 s on 2026-11-09, and 1.2 s of that was JIT:
-- 18 per-sample subqueries and 8 LATERAL ... LIMIT 1 joins put the planner's cost estimate over
-- jit_above_cost (100,000), so every read compiled 290 functions. Set-based (one pass over the
-- extractions and libraries, ranked, then grouped by OG) it costs about 6,100 and runs in ~50 ms
-- on a restore of live, without JIT.
--
-- Backlog item 10 said the status_overwrite logic was dead. It is not: since the v2 cutover the
-- importer loads the lab's Status Overwrite marks (132 true on 2026-11-09), so it is kept. The
-- latest row is still chosen by status_overwrite, then the highest attempt number.
--
-- Changed on purpose: ties. 112 OG/technology pairs have several rows tied for latest, typically
-- attempt 1 on two tissues (OG1353: G Extracted, H Hold). The old view returned whichever row the
-- plan read first, which was not stable. Now every tied status shows, distinct, comma-joined in
-- name order ("Extracted, Hold"), a tied row with no status as 'Awaiting Status' (owner decision
-- 2026-11-09). Every other value is unchanged; the probe below checks it cell by cell.
--
-- goat_species_v1 (the GoaT API view, summary's only reader in the database) tested pacbio_status
-- with = ANY (list). A joined value would never match, and 3 species would have lost in_lab. It
-- now tests whether any listed status is in the list (string_to_array && ARRAY). Its output is
-- unchanged except one species: Forcipiger longirostris (OG1685, tied HOLD / Sequence - PacBio)
-- becomes in_lab, where the old arbitrary pick had landed on HOLD.
--
-- Columns, names, types and order are unchanged, so CREATE OR REPLACE keeps dependants.
-- Replay: both views are replaced again; the probes compare against what was there.
-- Revert: sql/revert/081_summary_set_based_revert.sql.

BEGIN;

CREATE TEMP TABLE summary_081_before ON COMMIT DROP AS SELECT * FROM public.summary;
CREATE TEMP TABLE goat_081_before ON COMMIT DROP AS SELECT * FROM public.goat_species_v1;

CREATE OR REPLACE VIEW public.summary AS
WITH dna AS (
  SELECT t.og_id, d.dna_id, d.status, d.status_overwrite, d.ext_num
    FROM dna_extraction d JOIN tissue t ON t.tissue_id = d.tissue_id
), rna AS (
  SELECT t.og_id, r.rna_id, r.status, r.status_overwrite, r.ext_num
    FROM rna_extraction r JOIN tissue t ON t.tissue_id = r.tissue_id
), stage AS (
  -- One row per extraction or library, with the ordering that picks the latest: the lab's
  -- Status Overwrite first, then the highest attempt number.
  SELECT 'dna' AS tech, og_id, status, status_overwrite, ext_num AS num FROM dna
  UNION ALL SELECT 'rna', og_id, status, status_overwrite, ext_num FROM rna
  UNION ALL SELECT 'ilmn', d.og_id, i.ilmn_status, i.status_overwrite, i.ilmn_num
              FROM illumina_library i JOIN dna d ON d.dna_id = i.dna_id
  UNION ALL SELECT 'pacb', d.og_id, p.pacb_status, p.status_overwrite, p.pacb_num
              FROM pacbio_library p JOIN dna d ON d.dna_id = p.dna_id
  UNION ALL SELECT 'ont', d.og_id, o.ont_status, o.status_overwrite, o.ont_num
              FROM ont_library o JOIN dna d ON d.dna_id = o.dna_id
  UNION ALL SELECT 'hic', t.og_id, h.hic_status, h.status_overwrite, h.hic_num
              FROM hic_library h JOIN hic_lysate y ON y.lysate_id = h.lysate_id
              JOIN tissue t ON t.tissue_id = y.tissue_id
  UNION ALL SELECT 'rilm', r.og_id, x.rna_status, x.status_overwrite, x.rna_num
              FROM rna_library_ilmn x JOIN rna r ON r.rna_id = x.rna_id
  UNION ALL SELECT 'rkin', r.og_id, k.rna_status, k.status_overwrite, k.rna_num
              FROM rna_library_kinx k JOIN rna r ON r.rna_id = k.rna_id
), ranked AS (
  SELECT tech, og_id, coalesce(status, 'Awaiting Status') AS status,
         rank() OVER (PARTITION BY tech, og_id ORDER BY status_overwrite DESC NULLS LAST, num DESC) AS rk
    FROM stage
), stage_og AS (
  -- Rows tied for latest (e.g. extraction 1 of two tissues) all show: their distinct statuses,
  -- comma-joined in name order (owner decision 2026-11-09).
  SELECT og_id,
         count(*) FILTER (WHERE tech = 'dna' AND status = 'Extracted') AS extracted,
         count(*) FILTER (WHERE tech = 'rna')  AS rna_n,
         count(*) FILTER (WHERE tech = 'ilmn') AS ilmn_n,
         count(*) FILTER (WHERE tech = 'pacb') AS pacb_n,
         count(*) FILTER (WHERE tech = 'ont')  AS ont_n,
         count(*) FILTER (WHERE tech = 'hic')  AS hic_n,
         count(*) FILTER (WHERE tech = 'rilm') AS rilm_n,
         count(*) FILTER (WHERE tech = 'rkin') AS rkin_n,
         string_agg(DISTINCT status, ', ' ORDER BY status) FILTER (WHERE rk = 1 AND tech = 'dna')  AS dna_status,
         string_agg(DISTINCT status, ', ' ORDER BY status) FILTER (WHERE rk = 1 AND tech = 'rna')  AS rna_status,
         string_agg(DISTINCT status, ', ' ORDER BY status) FILTER (WHERE rk = 1 AND tech = 'ilmn') AS ilmn_status,
         string_agg(DISTINCT status, ', ' ORDER BY status) FILTER (WHERE rk = 1 AND tech = 'pacb') AS pacb_status,
         string_agg(DISTINCT status, ', ' ORDER BY status) FILTER (WHERE rk = 1 AND tech = 'ont')  AS ont_status,
         string_agg(DISTINCT status, ', ' ORDER BY status) FILTER (WHERE rk = 1 AND tech = 'hic')  AS hic_status,
         string_agg(DISTINCT status, ', ' ORDER BY status) FILTER (WHERE rk = 1 AND tech = 'rilm') AS rilm_status,
         string_agg(DISTINCT status, ', ' ORDER BY status) FILTER (WHERE rk = 1 AND tech = 'rkin') AS rkin_status
    FROM ranked GROUP BY og_id
), tissues AS (
  SELECT og_id, count(*) AS n FROM tissue GROUP BY og_id
), lca_og AS (
  SELECT og_id,
         string_agg(DISTINCT validated_species_name, ', ' ORDER BY validated_species_name) FILTER (WHERE tech = 'ilmn') AS ilmn,
         string_agg(DISTINCT validated_species_name, ', ' ORDER BY validated_species_name) FILTER (WHERE tech = 'hifi') AS hifi,
         string_agg(DISTINCT validated_species_name, ', ' ORDER BY validated_species_name) FILTER (WHERE tech = 'hic') AS hic
    FROM lca_validation
   WHERE validated_species_name IS NOT NULL AND validated_species_name <> ''
   GROUP BY og_id
)
SELECT s.og_num, s.og_id, s.project_id, s.workflow, s.priority,
       coalesce(tissues.n, 0) AS tissues,
       coalesce(g.extracted, 0) AS extracted,
       coalesce(g.dna_status, 'Awaiting Status') AS dna_extraction_status,
       coalesce(g.ilmn_status, 'Awaiting Status') AS illumina_status,
       coalesce(g.pacb_status, 'Awaiting Status') AS pacbio_status,
       coalesce(g.hic_status, 'Awaiting Status') AS hic_status,
       coalesce(g.ont_status, 'Awaiting Status') AS nanopore_status,
       coalesce(g.rna_status, 'Awaiting Status') AS rna_extraction_status,
       coalesce(g.rilm_status, 'Awaiting Status') AS rna_ilmn_status,
       coalesce(g.rkin_status, 'Awaiting Status') AS rna_kinnex_status,
       s.ilmn AS illumina_planned, s.hifi AS hifi_planned, s.hic AS hic_planned,
       s.nano AS nanopore_planned, s.rna AS rna_planned, s.ilrna AS rna_ilmn_planned,
       coalesce(g.ilmn_n, 0) AS illumina_actual,
       coalesce(g.pacb_n, 0) AS hifi_actual,
       coalesce(g.hic_n, 0) AS hic_actual,
       coalesce(g.ont_n, 0) AS nanopore_actual,
       coalesce(g.rna_n, 0) AS rna_actual,
       coalesce(g.rilm_n, 0) AS rna_ilmn_actual,
       coalesce(g.rkin_n, 0) AS rna_kinnex_actual,
       lca_og.ilmn AS ilmn_validated_species_name,
       lca_og.hifi AS hifi_validated_species_name,
       lca_og.hic AS hic_validated_species_name,
       s.field_id, s.nominal_species_id, s.common_name, s.collector, s.contact, s.comments
  FROM sample s
  LEFT JOIN tissues    ON tissues.og_id = s.og_id
  LEFT JOIN stage_og g ON g.og_id = s.og_id
  LEFT JOIN lca_og     ON lca_og.og_id = s.og_id;

COMMENT ON VIEW public.summary IS
  'The workbook''s Summary sheet, computed from the child tables instead of copied from Excel (decision 5). '
  'One row per sample. Each technology reports planned (lab intent, from sample) against actual (counted) '
  'and the status of its latest extraction or library: Status Overwrite first, then the highest attempt '
  'number. Rows tied for latest all show, distinct and comma-joined in name order (081). Set-based since '
  '081: about 50 ms, no JIT.';

CREATE OR REPLACE VIEW public.goat_species_v1 AS
 SELECT s.ncbi_taxon_id,
    s.family,
    s.species,
    COALESCE(s.epithet, '-'::text) AS subspecies_epithet,
        CASE
            WHEN s.ncbi_taxon_id = ANY (ARRAY[215367, 182658, 163129, 7793, 582430]) THEN 'priority_target'::text
            ELSE 'potential_target'::text
        END AS target_list_status,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM sample samp
              WHERE samp.nominal_species_id = s.species)) THEN 'sample_collected'::text
            ELSE NULL::text
        END AS sampling_status,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM sample samp
              WHERE samp.nominal_species_id = s.species AND samp.ncbi_bioproject_id_lvl_3_hifi IS NOT NULL)) THEN 'submitted'::text
            WHEN (EXISTS ( SELECT 1
               FROM sample samp
                 JOIN ref_assembly rg ON rg.og_id = samp.og_id
              WHERE samp.nominal_species_id = s.species)) THEN 'in_assembly'::text
            WHEN (EXISTS ( SELECT 1
               FROM summary sm
              WHERE sm.nominal_species_id = s.species AND (string_to_array(sm.pacbio_status, ', '::text) && ARRAY['Library Prep - PacBio SMRTbell'::text, 'QC - Femto'::text, 'Sequenced'::text, 'Sequenced, SRE'::text, 'Sequence - PacBio'::text, 'Shearing'::text, 'SRE'::text, 'SRE - ULI'::text, 'ULI'::text]))) THEN 'in_lab'::text
            ELSE NULL::text
        END AS sequencing_status,
    NULL::text AS genome_publication,
    'Ocean Genomes'::text AS primary_project,
    NULL::text AS ebp_collaborator_acronyms,
    NULL::text AS contributing_project_lab,
        CASE
            WHEN s.species = ANY (ARRAY['Neophoca cinerea'::text, 'Careproctus sp.'::text, 'Lethrinus punctulatus'::text, 'Siphonognathus radiatus'::text, 'Dascyllus aruanus'::text, 'Carcharhinus galapagensis'::text]) THEN 'data_conflict'::text
            ELSE ( SELECT samp.collector
               FROM sample samp
              WHERE samp.nominal_species_id = s.species AND samp.workflow = 'Reference'::text AND samp.collector IS NOT NULL
             LIMIT 1)
        END AS collected_by,
    NULL::text AS priority_flags,
    COALESCE(s.afd_common_name, '-'::text) AS common_name,
    COALESCE(s.synonym, '-'::text) AS synonym,
    NULL::text AS assigned_sequencing_center
   FROM master_species s
  ORDER BY s.family, s.species;

DO $p$
DECLARE
  bad bigint;
  cost numeric;
  plan json;
BEGIN
  -- Every cell matches the old view, except a status that became a list of tied statuses, which
  -- must contain the old value (the one the old plan happened to pick).
  SELECT count(*) INTO bad
    FROM summary_081_before o
    FULL JOIN public.summary n USING (og_id)
    CROSS JOIN LATERAL (
      SELECT a.k, a.v AS ov, b.v AS nv
        FROM jsonb_each_text(to_jsonb(o)) a(k, v)
        FULL JOIN jsonb_each_text(to_jsonb(n)) b(k, v) USING (k)) c
   WHERE c.ov IS DISTINCT FROM c.nv
     AND NOT (c.k LIKE '%\_status' AND position(', ' IN c.nv) > 0
              AND (', ' || c.nv || ', ') LIKE ('%, ' || c.ov || ', %'));
  IF bad > 0 THEN
    RAISE EXCEPTION '081: % summary value(s) changed other than a tie becoming a list', bad;
  END IF;

  -- goat_species_v1 changes only for species with a tied PacBio status.
  SELECT count(*) INTO bad
    FROM ((SELECT * FROM goat_081_before EXCEPT ALL SELECT * FROM public.goat_species_v1)
          UNION ALL
          (SELECT * FROM public.goat_species_v1 EXCEPT ALL SELECT * FROM goat_081_before)) d
   WHERE NOT EXISTS (SELECT 1 FROM public.summary s
                      WHERE s.nominal_species_id = d.species AND position(', ' IN s.pacbio_status) > 0);
  IF bad > 0 THEN
    RAISE EXCEPTION '081: % goat_species_v1 row(s) changed for a species with no tied PacBio status', bad;
  END IF;

  -- Below the JIT threshold, so a read does not compile.
  EXECUTE 'EXPLAIN (FORMAT JSON) SELECT * FROM public.summary' INTO plan;
  cost := (plan -> 0 -> 'Plan' ->> 'Total Cost')::numeric;
  IF cost >= current_setting('jit_above_cost')::numeric THEN
    RAISE EXCEPTION '081: summary plan cost % is not below jit_above_cost %', cost, current_setting('jit_above_cost');
  END IF;

  RAISE NOTICE '081: summary rebuilt (plan cost %); probes passed', round(cost);
END
$p$;

COMMIT;
