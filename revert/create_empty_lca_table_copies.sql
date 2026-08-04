-- Revert genomes_db:create_empty_lca_table_copies from pg

-- Rollback notes: safe at any point since these tables hold no data until the
-- (future, separate) swap-in step.

BEGIN;

DROP TABLE IF EXISTS public.blast_filtered_lca_new;
DROP TABLE IF EXISTS public.lca_raw_results_new;
DROP TABLE IF EXISTS public.lca_validation_new;
DROP TABLE IF EXISTS public.lca_new;

COMMIT;
