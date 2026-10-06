-- 035_v2_schema.sql -- Phase V.3: Create the empty `v2` schema.
--
-- Ported 2026-10-06 from design/v2/deploy/create_v2_schema.sql, re-reviewed in Phase V.1 and
-- rehearsed on a restore of live in V.2. Idempotent: every CREATE
-- is guarded (IF NOT EXISTS / OR REPLACE; triggers by a pg_trigger check), so the
-- crash-recovery replay in bin/apply_migrations.py is a no-op. The former Sqitch verify
-- script runs at the end INSIDE this transaction: a failed check rolls the whole
-- migration back, which Sqitch (verify after commit) could not do.
--
-- Purpose: Create the `v2` schema that the redesigned lab tables are built in. Per decision 3
--   of docs/v2_scaffold_design_review.md, the `v2` schema and the `v2_` prefix are one and the
--   same thing: tables take their FINAL names inside this schema (v2.sample, v2.tissue, ...),
--   so cutover is a search_path / ALTER SCHEMA swap and no object is ever renamed.
-- Review source: docs/v2_scaffold_design_review.md §2 decision 3, §5 step 1.
-- Expected impact: Additive only. Creates one empty schema. Nothing in `public` is read,
--   written, or altered, and the nightly import is unaffected.

BEGIN;

CREATE SCHEMA IF NOT EXISTS v2;

COMMENT ON SCHEMA v2 IS
    'Redesigned lab workflow schema. Built empty and validated alongside the live public.* '
    'tables; at cutover the search_path is repointed here rather than tables being renamed. '
    'Design rationale: docs/v2_scaffold_design_review.md and docs/lab_key_strategy.md.';

-- ---------------------------------------------------------------------------------------
-- Verification (ported from design/v2/verify/create_v2_schema.sql)
-- ---------------------------------------------------------------------------------------

-- The schema exists.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'v2') THEN
    RAISE EXCEPTION 'Missing schema v2';
  END IF;
END $$;

COMMIT;
