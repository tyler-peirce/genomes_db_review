-- Deploy genomes_db:create_v2_summary_view to pg
-- requires: create_v2_browse_views

-- Purpose: Rebuild the workbook's Summary sheet as a database view (decision 5, §5 step 6),
--   replacing the nine derived columns removed from v2.sample, and rebuild the one other view
--   that reads a column v2 removed (§5 step 7).
--
--   Decision 5 was that the Summary sheet is a fully derived sheet and should not be copied
--   into the database. That decision is only safe if the database can produce the same
--   information, which is what this view is for. It is not optional.
--
-- Review source: docs/v2_scaffold_design_review.md decision 5, F5, §5 steps 6-7;
--   docs/v2_cutover_dependencies.md, which established that only `summary` and
--   `goat_species_v1` reference removed columns — the other nine views are cutover-neutral and
--   need no DDL because a search_path swap resolves them to v2 unchanged.
--
-- Expected impact: Additive only. Two views in the `v2` schema. Nothing in `public` changes;
--   the live `summary` view keeps working against the live tables until cutover.
--
-- Prerequisite outside this project: these views read four tables that are out of scope and
--   stay in `public` — `lca_validation`, `master_species`, `ref_genomes`. They are referenced
--   schema-qualified so the reference does not silently follow a changed search_path, and they
--   must exist for this change to deploy.

BEGIN;

-- ---------------------------------------------------------------------------------------
-- v2.summary
-- ---------------------------------------------------------------------------------------
--
-- Three deliberate differences from public.summary, each recorded because a reader comparing
-- the two will otherwise assume a mistake:
--
-- 1. STATUS SELECTION. The live view does
--        COALESCE((... WHERE status_overwrite = 'Y' ORDER BY num DESC LIMIT 1),
--                 (...                          ORDER BY num DESC LIMIT 1),
--                 'Awaiting Status')
--    i.e. two correlated subqueries per technology, fourteen in total. This uses one LATERAL
--    per technology, ordered so the lab's flagged row sorts first:
--        ORDER BY status_overwrite DESC NULLS LAST, <num> DESC
--    Same result, except where the flagged row's status is itself NULL: the live view then
--    falls through to the newest unflagged row, this one returns 'Awaiting Status'. Honouring
--    the lab's explicit flag seems the better reading of intent, and status_overwrite has been
--    unreachable in the database until now (F4a) so nothing depends on the old behaviour.
--
-- 2. THE DEAD GUARDS ARE GONE, NOT RESURRECTED. The live view wraps each status in
--        CASE WHEN s.illumina_sequencing = 'N' THEN '' ELSE ... END
--    against columns that are 0/2675 populated (F4). The comparison is always NULL, so the
--    ELSE branch always runs and the guard has never fired. Its intent is now recoverable:
--    the workbook's ilmn/hifi/hic/nano/rna/ilrna columns hold Y/N only, not counts, so the guard
--    was always meant to read "blank out technologies this sample is not slated for" and could
--    be written `WHEN s.ilmn IS NOT TRUE THEN ''`. It deliberately is NOT, because switching it
--    on is a live behaviour change on a lab-facing report — samples flagged N would start
--    showing blank instead of a status — and that is the lab's call, not a side effect of a
--    schema migration. Dropping a guard that never fired preserves observed behaviour exactly,
--    and the flags are exposed as their own columns so the lab can decide with them in view.
--
-- 3. PLANNED VS ACTUAL. Each technology gets both `*_planned` (the hand-entered Y/N intent
--    kept on v2.sample per decision 9) and `*_actual` (counted from the child tables). "Slated
--    for Illumina but no Illumina library exists" is the comparison the lab is currently doing
--    by eye, and it is the reason those columns were worth keeping rather than deriving.
--
-- Ancestor joins route through `tissue`, since the child tables no longer carry og_id (F1).

CREATE VIEW v2.summary AS
SELECT s.og_num,
       s.og_id,
       s.project_id,
       s.workflow,
       s.priority,

       (SELECT count(*) FROM v2.tissue t WHERE t.og_id = s.og_id) AS tissues,

       (SELECT count(*)
          FROM v2.dna_extraction d
          JOIN v2.tissue t ON t.tissue_id = d.tissue_id
         WHERE t.og_id = s.og_id AND d.status = 'Extracted') AS extracted,

       coalesce(dna.status,  'Awaiting Status') AS dna_extraction_status,
       coalesce(ilmn.status, 'Awaiting Status') AS illumina_status,
       coalesce(pacb.status, 'Awaiting Status') AS pacbio_status,
       coalesce(hic.status,  'Awaiting Status') AS hic_status,
       coalesce(ont.status,  'Awaiting Status') AS nanopore_status,
       coalesce(rna.status,  'Awaiting Status') AS rna_extraction_status,
       coalesce(rilm.status, 'Awaiting Status') AS rna_ilmn_status,
       coalesce(rkin.status, 'Awaiting Status') AS rna_kinnex_status,

       -- Lab intent: is this sample slated for each technology? (hand-entered Y/N on the
       -- Summary sheet, kept per decision 9) ...
       s.ilmn  AS illumina_planned,
       s.hifi  AS hifi_planned,
       s.hic   AS hic_planned,
       s.nano  AS nanopore_planned,
       s.rna   AS rna_planned,
       s.ilrna AS rna_ilmn_planned,

       -- ... against what actually exists.
       (SELECT count(*) FROM v2.illumina_library i
          JOIN v2.dna_extraction d ON d.dna_id = i.dna_id
          JOIN v2.tissue t ON t.tissue_id = d.tissue_id
         WHERE t.og_id = s.og_id) AS illumina_actual,
       (SELECT count(*) FROM v2.pacbio_library p
          JOIN v2.dna_extraction d ON d.dna_id = p.dna_id
          JOIN v2.tissue t ON t.tissue_id = d.tissue_id
         WHERE t.og_id = s.og_id) AS hifi_actual,
       (SELECT count(*) FROM v2.hic_library h
          JOIN v2.hic_lysate y ON y.lysate_id = h.lysate_id
          JOIN v2.tissue t ON t.tissue_id = y.tissue_id
         WHERE t.og_id = s.og_id) AS hic_actual,
       (SELECT count(*) FROM v2.ont_library o
          JOIN v2.dna_extraction d ON d.dna_id = o.dna_id
          JOIN v2.tissue t ON t.tissue_id = d.tissue_id
         WHERE t.og_id = s.og_id) AS nanopore_actual,
       (SELECT count(*) FROM v2.rna_extraction r
          JOIN v2.tissue t ON t.tissue_id = r.tissue_id
         WHERE t.og_id = s.og_id) AS rna_actual,
       (SELECT count(*) FROM v2.rna_library_ilmn x
          JOIN v2.rna_extraction r ON r.rna_id = x.rna_id
          JOIN v2.tissue t ON t.tissue_id = r.tissue_id
         WHERE t.og_id = s.og_id) AS rna_ilmn_actual,
       (SELECT count(*) FROM v2.rna_library_kinx k
          JOIN v2.rna_extraction r ON r.rna_id = k.rna_id
          JOIN v2.tissue t ON t.tissue_id = r.tissue_id
         WHERE t.og_id = s.og_id) AS rna_kinnex_actual,

       -- LCA validation stays in public: those tables are out of scope per decision 1.
       (SELECT string_agg(DISTINCT lv.validated_species_name, ', ' ORDER BY lv.validated_species_name)
          FROM public.lca_validation lv
         WHERE lv.og_id = s.og_id AND lv.tech = 'ilmn'
           AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> '')
         AS ilmn_validated_species_name,
       (SELECT string_agg(DISTINCT lv.validated_species_name, ', ' ORDER BY lv.validated_species_name)
          FROM public.lca_validation lv
         WHERE lv.og_id = s.og_id AND lv.tech = 'hifi'
           AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> '')
         AS hifi_validated_species_name,
       (SELECT string_agg(DISTINCT lv.validated_species_name, ', ' ORDER BY lv.validated_species_name)
          FROM public.lca_validation lv
         WHERE lv.og_id = s.og_id AND lv.tech = 'hic'
           AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> '')
         AS hic_validated_species_name,

       s.field_id,
       s.nominal_species_id,
       s.common_name,
       s.collector,
       s.contact,
       s.comments
FROM v2.sample s

LEFT JOIN LATERAL (
    SELECT d.status FROM v2.dna_extraction d
      JOIN v2.tissue t ON t.tissue_id = d.tissue_id
     WHERE t.og_id = s.og_id
     ORDER BY d.status_overwrite DESC NULLS LAST, d.ext_num DESC
     LIMIT 1) dna ON true

LEFT JOIN LATERAL (
    SELECT i.ilmn_status AS status FROM v2.illumina_library i
      JOIN v2.dna_extraction d ON d.dna_id = i.dna_id
      JOIN v2.tissue t ON t.tissue_id = d.tissue_id
     WHERE t.og_id = s.og_id
     ORDER BY i.status_overwrite DESC NULLS LAST, i.ilmn_num DESC
     LIMIT 1) ilmn ON true

LEFT JOIN LATERAL (
    SELECT p.pacb_status AS status FROM v2.pacbio_library p
      JOIN v2.dna_extraction d ON d.dna_id = p.dna_id
      JOIN v2.tissue t ON t.tissue_id = d.tissue_id
     WHERE t.og_id = s.og_id
     ORDER BY p.status_overwrite DESC NULLS LAST, p.pacb_num DESC
     LIMIT 1) pacb ON true

LEFT JOIN LATERAL (
    SELECT h.hic_status AS status FROM v2.hic_library h
      JOIN v2.hic_lysate y ON y.lysate_id = h.lysate_id
      JOIN v2.tissue t ON t.tissue_id = y.tissue_id
     WHERE t.og_id = s.og_id
     ORDER BY h.status_overwrite DESC NULLS LAST, h.hic_num DESC
     LIMIT 1) hic ON true

LEFT JOIN LATERAL (
    SELECT o.ont_status AS status FROM v2.ont_library o
      JOIN v2.dna_extraction d ON d.dna_id = o.dna_id
      JOIN v2.tissue t ON t.tissue_id = d.tissue_id
     WHERE t.og_id = s.og_id
     ORDER BY o.status_overwrite DESC NULLS LAST, o.ont_num DESC
     LIMIT 1) ont ON true

LEFT JOIN LATERAL (
    SELECT r.status FROM v2.rna_extraction r
      JOIN v2.tissue t ON t.tissue_id = r.tissue_id
     WHERE t.og_id = s.og_id
     ORDER BY r.status_overwrite DESC NULLS LAST, r.ext_num DESC
     LIMIT 1) rna ON true

LEFT JOIN LATERAL (
    SELECT x.rna_status AS status FROM v2.rna_library_ilmn x
      JOIN v2.rna_extraction r ON r.rna_id = x.rna_id
      JOIN v2.tissue t ON t.tissue_id = r.tissue_id
     WHERE t.og_id = s.og_id
     ORDER BY x.status_overwrite DESC NULLS LAST, x.rna_num DESC
     LIMIT 1) rilm ON true

LEFT JOIN LATERAL (
    SELECT k.rna_status AS status FROM v2.rna_library_kinx k
      JOIN v2.rna_extraction r ON r.rna_id = k.rna_id
      JOIN v2.tissue t ON t.tissue_id = r.tissue_id
     WHERE t.og_id = s.og_id
     ORDER BY k.status_overwrite DESC NULLS LAST, k.rna_num DESC
     LIMIT 1) rkin ON true;

COMMENT ON VIEW v2.summary IS
    'The workbook''s Summary sheet, computed from the child tables instead of copied from Excel '
    '(decision 5). This is what replaces the nine derived columns removed from v2.sample, and '
    'it is what fixes the status fragmentation of database_review.md Finding 7 at source: the '
    '47 distinct rna_status values were Excel string concatenation being persisted. Each '
    'technology also reports planned (lab intent) against actual (counted).';

COMMENT ON COLUMN v2.summary.illumina_planned IS 'Hand-entered lab intent from the Summary sheet''s "ilmn" column: is this sample slated for Illumina at all? Compare with illumina_actual.';
COMMENT ON COLUMN v2.summary.illumina_actual  IS 'Illumina libraries that actually exist for this sample, counted through tissue -> dna_extraction.';

-- ---------------------------------------------------------------------------------------
-- v2.goat_species_v1
-- ---------------------------------------------------------------------------------------
--
-- Identical to public.goat_species_v1 except for the `sequencing_status` branch, which reads
-- `samp.pb_status` — a Summary-sheet rollup removed by F5. It now reads the same information
-- from v2.summary.pacbio_status, which is where that value legitimately comes from.
--
-- master_species, ref_genomes and species stay in public: they are outside the twelve.

CREATE VIEW v2.goat_species_v1 AS
SELECT s.ncbi_taxon_id,
       s.family,
       s.species,
       COALESCE(s.epithet, '-') AS subspecies_epithet,
       CASE WHEN s.ncbi_taxon_id = ANY (ARRAY[215367, 182658, 163129, 7793, 582430])
            THEN 'priority_target' ELSE 'potential_target' END AS target_list_status,
       CASE WHEN EXISTS (SELECT 1 FROM v2.sample samp WHERE samp.nominal_species_id = s.species)
            THEN 'sample_collected' ELSE NULL END AS sampling_status,
       CASE
           WHEN EXISTS (SELECT 1 FROM v2.sample samp
                         WHERE samp.nominal_species_id = s.species
                           AND samp.ncbi_bioproject_id_lvl_3_hifi IS NOT NULL) THEN 'submitted'
           WHEN EXISTS (SELECT 1 FROM v2.sample samp
                          JOIN public.ref_genomes rg ON rg.og_id = samp.og_id
                         WHERE samp.nominal_species_id = s.species) THEN 'in_assembly'
           -- was: samp.pb_status = ANY (...) — that column was a Summary-sheet rollup (F5).
           WHEN EXISTS (SELECT 1 FROM v2.summary sm
                         WHERE sm.nominal_species_id = s.species
                           AND sm.pacbio_status = ANY (ARRAY[
                                 'Library Prep - PacBio SMRTbell', 'QC - Femto', 'Sequenced',
                                 'Sequenced, SRE', 'Sequence - PacBio', 'Shearing', 'SRE',
                                 'SRE - ULI', 'ULI'])) THEN 'in_lab'
           ELSE NULL
       END AS sequencing_status,
       NULL::text AS genome_publication,
       'Ocean Genomes'::text AS primary_project,
       NULL::text AS ebp_collaborator_acronyms,
       NULL::text AS contributing_project_lab,
       CASE WHEN s.species = ANY (ARRAY['Neophoca cinerea', 'Careproctus sp.',
                                        'Lethrinus punctulatus', 'Siphonognathus radiatus',
                                        'Dascyllus aruanus', 'Carcharhinus galapagensis'])
            THEN 'data_conflict'
            ELSE (SELECT samp.collector FROM v2.sample samp
                   WHERE samp.nominal_species_id = s.species
                     AND samp.workflow = 'Reference'
                     AND samp.collector IS NOT NULL
                   LIMIT 1)
       END AS collected_by,
       NULL::text AS priority_flags,
       COALESCE(s.afd_common_name, '-') AS common_name,
       COALESCE(s.synonym, '-') AS synonym,
       NULL::text AS assigned_sequencing_center
FROM public.master_species s
ORDER BY s.family, s.species;

COMMENT ON VIEW v2.goat_species_v1 IS
    'GoaT species submission view. Differs from the public version only in reading pacbio '
    'status from v2.summary rather than sample.pb_status, which F5 removed. See '
    'docs/v2_cutover_dependencies.md.';

COMMIT;
