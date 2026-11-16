-- Revert 087_v_genome_size_comparison_ncbi.sql: drop v_genome_size_comparison (nothing depends on it).
-- To restore the pre-085 view as well, run 085's revert after this one.
--     psql -f sql/revert/087_v_genome_size_comparison_ncbi_revert.sql   then delete 087's ledger row.

BEGIN;

DROP VIEW public.v_genome_size_comparison;

COMMIT;
