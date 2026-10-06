-- Revert 039_v2_lca_tables.sql.
--
-- Ported from design/v2/revert/create_v2_lca_tables.sql. Run the v2 reverts in reverse order, 040 down
-- to 035. Like the other files in sql/revert/ this does not touch the ledger; afterwards
-- remove the row by hand:
--
--     DELETE FROM schema_migrations WHERE filename = '039_v2_lca_tables.sql';
--
-- mitogenome_data is the parent of the other three, so it goes last.

BEGIN;

DROP TABLE v2.blast_filtered_lca;
DROP TABLE v2.lca_raw_results;
DROP TABLE v2.lca_validation;
DROP TABLE v2.lca;
DROP TABLE v2.mitogenome_data;

-- The triggers went with their tables; the function did not.
DROP FUNCTION v2.lca_set_content_hash();

COMMIT;
