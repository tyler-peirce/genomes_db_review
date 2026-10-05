-- 000_bootstrap_schema_migrations.sql
--
-- Purpose: create the migration ledger itself.
--
-- Review source: database_review.md Phase B.3, Finding 10.
--
-- Why this file exists
-- --------------------
-- `schema_migrations` has recorded every migration since 001, but nothing ever
-- recorded its own creation. It was created by hand in July 2026 and appeared in
-- `bin/check_drift.py --coverage` as "baseline-only": reproducible from the
-- pg_dump snapshot, described by no migration. A rebuild from sql/ alone would
-- fail on the first file, because `bin/apply_migrations.py` cannot write a
-- ledger row to a table that does not exist.
--
-- Numbered 000 so it sorts and applies ahead of 001. `MIGRATION_RE` in
-- bin/apply_migrations.py is ^(\d{3})_, which accepts it.
--
-- Why it does not ledger itself
-- -----------------------------
-- The ledger stores a SHA-256 of each file's contents. A file cannot contain its
-- own hash, so an `INSERT` here could never satisfy `--verify`. Instead this
-- file is idempotent and is ledgered through the normal path, like any other
-- migration:
--
--   * Against the live database, where the table already exists, running
--     `bin/apply_migrations.py` applies this as a no-op and writes its row.
--   * Against an empty database, run it once by hand first, because the apply
--     script has no ledger to read until it exists:
--
--         psql -f sql/000_bootstrap_schema_migrations.sql
--         bin/apply_migrations.py
--
-- That ordering is the one thing about this file worth remembering. It is also
-- printed by `bin/apply_migrations.py` when it finds the ledger missing.
--
-- Expected impact: none on the live database. The table and its primary key
-- already exist; both clauses are guarded.

BEGIN;

CREATE TABLE IF NOT EXISTS public.schema_migrations (
    filename   text        NOT NULL,
    sha256     text        NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now()
);

-- Separate from the CREATE so the constraint is also added on a database where
-- the table was created without it. ADD CONSTRAINT has no IF NOT EXISTS.
DO $$
BEGIN
    ALTER TABLE public.schema_migrations
        ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (filename);
EXCEPTION
    WHEN duplicate_table THEN NULL;  -- index name already taken
    WHEN invalid_table_definition THEN NULL;  -- already has a primary key
END $$;

COMMENT ON TABLE public.schema_migrations IS
    'Migration ledger for sql/. One row per applied file, with a SHA-256 of its '
    'contents so an applied migration cannot be edited unnoticed. Written by '
    'bin/apply_migrations.py; never populate it by hand. Created by '
    '000_bootstrap_schema_migrations.sql, which must be run with psql before the '
    'first apply_migrations.py invocation on an empty database.';

COMMIT;
