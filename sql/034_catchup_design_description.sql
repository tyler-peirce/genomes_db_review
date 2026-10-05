-- 034_catchup_design_description.sql
--
-- Purpose: bring the design_description lookup table under migration
-- management.
--
-- Review source: database_review.md Phase B.3, Finding 1, Finding 10.
--
-- Why this one is here and most catch-up work is not
-- -------------------------------------------------
-- Phase B.3 routed 39 of the 49 uncovered objects into the phases that already
-- rework them, on the principle that a catch-up CREATE belongs in the same
-- migration as the change it precedes. design_description is one of the ten
-- that stayed: nothing anywhere in the plan touches it, so there is no later
-- change to attach it to, and leaving it would mean carrying a one-table
-- worklist indefinitely.
--
-- What it is -- and the open question about it
-- --------------------------------------------
-- A three-column lookup with two rows, a primary key on design_no, and no
-- foreign keys in either direction. Nothing in genomes_db_review or
-- OceanOmics-Database references it -- not a view, not a script, not a
-- migration. It predates the review.
--
-- Dropping it was considered and rejected for now. The precedent exists (031
-- and 032 removed nine objects rather than describing them), but those were
-- provably dead: data_package_* was abandoned work with no code references, and
-- lca_old was investigated row by row. Here, "no code references" only covers
-- the two repositories. Open question 7 -- which clients query this database
-- from outside them -- is unanswered, and pg_stat_activity shows at least two
-- DBeaver users connecting directly as postgres. A two-row lookup is exactly
-- the kind of thing a saved GUI query joins against.
--
-- So: captured now, flagged for removal once question 7 can confirm nobody
-- outside the repositories reads it. Recorded as open question 15.
--
-- Expected impact: none. The table and its primary key already exist; both
-- clauses are guarded. Column types are taken from the live catalog --
-- character varying with no length limit, as created, not narrowed here.

BEGIN;

CREATE TABLE IF NOT EXISTS public.design_description (
    design_no          integer NOT NULL,
    design_description character varying,
    comment            character varying
);

-- Separate from the CREATE so the constraint is also added on a database where
-- the table exists without it. ADD CONSTRAINT has no IF NOT EXISTS.
DO $$
BEGIN
    ALTER TABLE public.design_description
        ADD CONSTRAINT design_description_pk PRIMARY KEY (design_no);
EXCEPTION
    WHEN duplicate_table THEN NULL;  -- index name already taken
    WHEN invalid_table_definition THEN NULL;  -- already has a primary key
END $$;

COMMENT ON TABLE public.design_description IS
    'Lookup of sequencing design numbers to descriptions. Two rows, no foreign '
    'keys in or out, and no reference from either repository. Captured by '
    '034_catchup_design_description.sql so it is not lost on a rebuild; a '
    'candidate for removal once open question 15 confirms no external consumer.';

COMMIT;
