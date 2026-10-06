-- Revert 038_v2_quarantine.sql.
--
-- Ported from design/v2/revert/create_v2_quarantine.sql. Run the v2 reverts in reverse order, 040 down
-- to 035. Like the other files in sql/revert/ this does not touch the ledger; afterwards
-- remove the row by hand:
--
--     DELETE FROM schema_migrations WHERE filename = '038_v2_quarantine.sql';
--
BEGIN;

DROP TABLE v2.workbook_attempt_keys;
DROP VIEW v2.v_quarantine_displaced;
DROP VIEW v2.v_quarantine_open;
DROP FUNCTION v2.quarantine(text, text, text, text, jsonb, text);
DROP TABLE v2.import_quarantine;

COMMIT;
