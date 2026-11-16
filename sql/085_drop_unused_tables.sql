-- 085_drop_unused_tables.sql -- drop species_ncbi_assembly, the two ENA archive tables, and
-- v_genome_size_comparison, which only read the first of them.
--
-- Why. Owner, 2026-11-13: remove them. Each was empty on live (2026-11-13) and has no writer and
-- no reader outside this repository (searched every checkout on this host: the pipelines,
-- OceanOmics-Database and the ENA repos):
--   - species_ncbi_assembly (0 rows since it was created). A planned NCBI assembly table, with
--     an FK to species and one chosen assembly per species. Never loaded; ncbi_genome_assemblies
--     (1,830 rows) is where NCBI assembly metadata actually landed. Backlog Medium 2-3, Lower 2.
--   - ena_locus_registry_archive, ena_candidate_loci_archive (0 rows each). 010 created them as
--     frozen copies of the locus-tag registry before dropping it; the registry was empty by then,
--     so they hold nothing. Locus tags belong to the downstream ENA submission pipeline.
--     Backlog Medium 5 (they had no PK) and Lower 3.
--   - v_genome_size_comparison: GenomeScope genome size per draft against the chosen
--     species_ncbi_assembly row. Its NCBI half (ncbi_bp and every column after it) has been NULL
--     on every row since it was created, and it cannot be repointed: ncbi_genome_assemblies has
--     no total sequence length. What remains (genome size per draft) is in draft_genomescope and
--     v_draft_genome_status. Nothing depends on the view.
--
-- Rejected: keeping v_genome_size_comparison without its NCBI columns. That changes its columns
-- anyway, so it breaks any reader just as a drop would, and leaves a view that adds nothing.
--
-- Guard: refuses to run if any of the three tables has a row, so this cannot drop data that
-- arrived after the review. Dropping species_ncbi_assembly also drops its FK onto species, its
-- partial unique index and its readonly grant.
--
-- Replay: every drop is IF EXISTS and the guard skips missing tables, so a replay is a no-op.
-- Revert: sql/revert/085_drop_unused_tables_revert.sql (structure, comments and grants; the
-- tables were empty).

BEGIN;

DO $guard$
DECLARE
  t text;
  n bigint;
BEGIN
  FOREACH t IN ARRAY ARRAY['species_ncbi_assembly', 'ena_locus_registry_archive',
                           'ena_candidate_loci_archive'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
      IF n > 0 THEN
        RAISE EXCEPTION '085: public.% has % rows; it was empty when this migration was written. '
          'Find out who writes it before dropping it.', t, n;
      END IF;
    END IF;
  END LOOP;
END
$guard$;

DROP VIEW IF EXISTS public.v_genome_size_comparison;
DROP TABLE IF EXISTS public.species_ncbi_assembly;
DROP TABLE IF EXISTS public.ena_locus_registry_archive;
DROP TABLE IF EXISTS public.ena_candidate_loci_archive;

COMMIT;
