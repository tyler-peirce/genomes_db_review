-- 040_v2_summary_view.sql -- Phase V.3: v2.summary and v2.goat_species_v1.
--
-- Ported 2026-10-06 from design/v2/deploy/create_v2_summary_view.sql, re-reviewed in Phase V.1 and
-- rehearsed on a restore of live in V.2. Run after 039_v2_lca_tables.sql. Idempotent: every CREATE
-- is guarded (IF NOT EXISTS / OR REPLACE; triggers by a pg_trigger check), so the
-- crash-recovery replay in bin/apply_migrations.py is a no-op. The former Sqitch verify
-- script runs at the end INSIDE this transaction: a failed check rolls the whole
-- migration back, which Sqitch (verify after commit) could not do.
--
-- BUILD ORDER CHANGED 2026-10-05. This change used to come fifth, before create_v2_lca_tables,
-- which was only valid while v2.summary read public.lca_validation. Repointing it at
-- v2.lca_validation (Phase V.1 item 3) inverts the last two steps: the LCA tables must exist
-- first. The order in design/v2/README.md and in Phase V.3 of database_review.md is updated to
-- match. Deploying in the old order now fails outright, which is the good outcome -- it fails
-- at deploy rather than resolving to the wrong schema.

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
--   `goat_species_v1` reference removed columns.
--
--   CORRECTED 2026-10-05: this used to add "the other nine views are cutover-neutral and need
--   no DDL because a search_path swap resolves them to v2 unchanged". The last clause is
--   wrong and it is the kind of wrong someone acts on. Views bind to table OIDs at creation,
--   not to names, so an existing view ignores the search_path entirely and keeps reading
--   `public` — and it survives a rename of its base table too, silently following the OID.
--   The nine need no EDIT to their SQL; they must still be recreated (CREATE OR REPLACE VIEW
--   is enough and preserves grants and INSTEAD OF triggers). Same correction is recorded in
--   docs/v2_cutover_dependencies.md and in sql/033's header.
--
-- Expected impact: Additive only. Two views in the `v2` schema. Nothing in `public` changes;
--   the live `summary` view keeps working against the live tables until cutover.
--
-- Prerequisite outside this project: these views read two tables that are out of scope and
--   stay in `public` — `master_species` and `ref_genomes`. They are referenced
--   schema-qualified so the reference does not silently follow a changed search_path, and they
--   must exist for this change to deploy.
--
--   `lca_validation` was on that list until 2026-10-05 and is not any more: v2 builds it, so
--   this view reads `v2.lca_validation`. See the note at the column.

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

CREATE OR REPLACE VIEW v2.summary AS
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

       -- Reads v2.lca_validation. This said public.lca_validation until 2026-10-05, and the
       -- qualification WAS deliberate -- decision 1 put the LCA tables out of scope, and the
       -- file header documented it alongside master_species and ref_genomes. Phase V.1 item 3
       -- allows for that case and says to leave it commented if so.
       --
       -- It is repointed anyway, because the premise expired rather than the reasoning being
       -- wrong: create_v2_lca_tables.sql now builds v2.lca_validation, so "out of scope" is
       -- no longer true of this table. Left pointing at public it would have been the exact
       -- Finding 11 failure mode -- v2.summary silently reading a superseded table after
       -- cutover and returning plausible, stale validation names. master_species and
       -- ref_genomes stay public-qualified: those really are out of scope.
       (SELECT string_agg(DISTINCT lv.validated_species_name, ', ' ORDER BY lv.validated_species_name)
          FROM v2.lca_validation lv
         WHERE lv.og_id = s.og_id AND lv.tech = 'ilmn'
           AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> '')
         AS ilmn_validated_species_name,
       (SELECT string_agg(DISTINCT lv.validated_species_name, ', ' ORDER BY lv.validated_species_name)
          FROM v2.lca_validation lv
         WHERE lv.og_id = s.og_id AND lv.tech = 'hifi'
           AND lv.validated_species_name IS NOT NULL AND lv.validated_species_name <> '')
         AS hifi_validated_species_name,
       (SELECT string_agg(DISTINCT lv.validated_species_name, ', ' ORDER BY lv.validated_species_name)
          FROM v2.lca_validation lv
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

CREATE OR REPLACE VIEW v2.goat_species_v1 AS
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

-- ---------------------------------------------------------------------------------------
-- Verification (ported from design/v2/verify/create_v2_summary_view.sql)
-- ---------------------------------------------------------------------------------------
-- The point of this view is that it replaces columns removed from v2.sample. So the useful
-- assertion is not "it exists" but "it produces every rollup that was removed", plus the
-- planned/actual pairs decision 9 exists to enable.

DO $$
DECLARE
  col text;
BEGIN
  FOREACH col IN ARRAY ARRAY['summary', 'goat_species_v1'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.views
                   WHERE table_schema = 'v2' AND table_name = col) THEN
      RAISE EXCEPTION 'Missing expected view: v2.%', col;
    END IF;
    EXECUTE format('SELECT 1 FROM v2.%I LIMIT 1', col);   -- executes it, so a bad column fails here
  END LOOP;

  -- Every rollup removed from v2.sample must be recoverable here (decision 5, F5).
  FOREACH col IN ARRAY ARRAY[
    'tissues', 'extracted', 'dna_extraction_status', 'illumina_status', 'pacbio_status',
    'hic_status', 'nanopore_status', 'rna_extraction_status', 'rna_ilmn_status',
    'rna_kinnex_status'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = 'summary' AND column_name = col) THEN
      RAISE EXCEPTION 'v2.summary does not replace the removed sample column "%" (decision 5)', col;
    END IF;
  END LOOP;

  -- Planned/actual pairs (F5, decision 9).
  FOREACH col IN ARRAY ARRAY[
    'illumina_planned', 'illumina_actual', 'hifi_planned', 'hifi_actual',
    'hic_planned', 'hic_actual', 'nanopore_planned', 'nanopore_actual',
    'rna_planned', 'rna_actual', 'rna_ilmn_planned', 'rna_ilmn_actual'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = 'summary' AND column_name = col) THEN
      RAISE EXCEPTION 'v2.summary is missing % (F5 planned-vs-actual)', col;
    END IF;
  END LOOP;

  -- The dead Summary-sheet columns must not have reappeared under their old names.
  FOREACH col IN ARRAY ARRAY['summary_comments', 'illumina_sequencing', 'rna_kinnex_sequencing'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'v2' AND table_name = 'summary' AND column_name = col) THEN
      RAISE EXCEPTION 'v2.summary.% is a dead column that should not have been carried over (F4)', col;
    END IF;
  END LOOP;
END $$;

COMMIT;
