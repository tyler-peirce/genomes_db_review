-- Verify genomes_db:create_v2_schema on pg

BEGIN;

-- The schema exists.
SELECT 1/count(*) FROM pg_namespace WHERE nspname = 'v2';

ROLLBACK;
