-- Revert 040_v2_summary_view.sql.
--
-- Ported from design/v2/revert/create_v2_summary_view.sql. Run the v2 reverts in reverse order, 040 down
-- to 035. Like the other files in sql/revert/ this does not touch the ledger; afterwards
-- remove the row by hand:
--
--     DELETE FROM schema_migrations WHERE filename = '040_v2_summary_view.sql';
--
-- goat_species_v1 reads summary, so it goes first.

BEGIN;

DROP VIEW v2.goat_species_v1;
DROP VIEW v2.summary;

COMMIT;
