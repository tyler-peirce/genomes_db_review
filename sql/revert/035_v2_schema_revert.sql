-- Revert 035_v2_schema.sql.
--
-- Ported from design/v2/revert/create_v2_schema.sql. Run the v2 reverts in reverse order, 040 down
-- to 035. Like the other files in sql/revert/ this does not touch the ledger; afterwards
-- remove the row by hand:
--
--     DELETE FROM schema_migrations WHERE filename = '035_v2_schema.sql';
--
-- Deliberately NOT `DROP SCHEMA v2 CASCADE`. If a later change has created objects in v2 and
-- has not itself been reverted first, this should fail loudly rather than silently destroy
-- them. Reverting 040 down to 035 in order, so a clean revert leaves the schema empty.

BEGIN;

DROP SCHEMA v2 RESTRICT;

COMMIT;
