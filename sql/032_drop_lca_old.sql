-- Drop lca_old.
--
-- Read the numbers before judging this one -- out of context they look like a
-- mistake. lca_old holds 2,895 rows across 649 og_ids. Compared against the
-- live lca table (4,784 rows, 1,406 og_ids) on the natural key
-- (og_id, tech, seq_date, code):
--
--     446 key combinations appear in both
--     468 appear in lca_old and NOT in live lca
--       9 og_ids appear in lca_old with no row at all in live lca
--
-- It also carries four columns the live table no longer has -- taxonomy, lca
-- and length are populated on all 2,895 rows; coverage is empty on all of them.
--
-- So this is not a redundant copy, and that is exactly why it needed a decision
-- rather than a quiet drop. The decision: the LCA pipeline was re-run from
-- scratch, so those 468 rows are superseded output, not missing data. They
-- should not be re-ingested into lca. A live table full of results that must
-- not be used is a trap -- sooner or later somebody joins to it.
--
-- Archived first. archive/snapshots_SS260818/lca_old.csv.gz holds every row,
-- verified to reload EXCEPT-identical against this table. Dropping it loses
-- nothing that is not on disk in this repo.
--
-- Two consequences worth knowing:
--
-- 1. This takes constraint fk_mitogenome with it. Four foreign keys point into
--    mitogenome_data_SS260818; this is the only one from OUTSIDE the snapshot
--    set. The other three come from lca_SS260818, lca_raw_results_SS260818 and
--    lca_validation_SS260818, which will be dropped alongside it whenever the
--    snapshots go. After this migration the SS260818 group is self-contained
--    and removable as a unit: drop the three snapshot views, then the five
--    tables. Keep lca_validation_report_view_upd() -- that trigger function is
--    shared with the LIVE lca_validation_report_view.
--
-- 2. It closes Phase F item 1 of database_review.md, which listed lca_old's
--    undecided fate as blocking the snapshot cleanup.
--
-- Safety. No view depends on lca_old and no application code anywhere under
-- /home/tyler references it. It is not in any migration -- it reached this
-- database by direct DDL, like the snapshots it points at.
--
-- Reverting. revert/032_drop_lca_old_revert.sql recreates the table structure
-- but NOT the data; reload the CSV from archive/snapshots_SS260818/ if the rows
-- are ever genuinely wanted. Note that the revert also restores fk_mitogenome,
-- so it will only succeed while mitogenome_data_SS260818 still exists.

BEGIN;

DROP TABLE IF EXISTS lca_old;

DO $$
BEGIN
    IF to_regclass('public.lca_old') IS NOT NULL THEN
        RAISE EXCEPTION 'lca_old still present after drop';
    END IF;
END $$;

COMMIT;
