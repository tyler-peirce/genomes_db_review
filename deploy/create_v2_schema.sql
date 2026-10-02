-- Deploy genomes_db:create_v2_schema to pg

-- Purpose: Create the `v2` schema that the redesigned lab tables are built in. Per decision 3
--   of docs/v2_scaffold_design_review.md, the `v2` schema and the `v2_` prefix are one and the
--   same thing: tables take their FINAL names inside this schema (v2.sample, v2.tissue, ...),
--   so cutover is a search_path / ALTER SCHEMA swap and no object is ever renamed.
-- Review source: docs/v2_scaffold_design_review.md §2 decision 3, §5 step 1.
-- Expected impact: Additive only. Creates one empty schema. Nothing in `public` is read,
--   written, or altered, and the nightly import is unaffected.

BEGIN;

CREATE SCHEMA v2;

COMMENT ON SCHEMA v2 IS
    'Redesigned lab workflow schema. Built empty and validated alongside the live public.* '
    'tables; at cutover the search_path is repointed here rather than tables being renamed. '
    'Design rationale: docs/v2_scaffold_design_review.md and docs/lab_key_strategy.md.';

COMMIT;
