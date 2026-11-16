-- Revert 086_ncbi_genome_assemblies_comment.sql: put back 079's table comment on ncbi_genome_assemblies.
--     psql -f sql/revert/086_ncbi_genome_assemblies_comment_revert.sql   then delete 086's ledger row.

BEGIN;

COMMENT ON TABLE public.ncbi_genome_assemblies IS 'NCBI genome assembly metadata (1,830 rows): what is already assembled for a species. No writer and no reading view found; no FK to species. The empty species_ncbi_assembly was meant to hold the same and is what v_genome_size_comparison reads; consolidating them is a backlog item.';

COMMIT;
