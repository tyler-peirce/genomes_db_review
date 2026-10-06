-- Revert 041_v2_value_conversions.sql.
--
-- Drops the conversion log. The converted values themselves stay in the v2 tables; without
-- this table they can no longer be told apart from typed ones, so export it first if any
-- rule's effect might need undoing. Does not touch the ledger; afterwards:
--
--     DELETE FROM schema_migrations WHERE filename = '041_v2_value_conversions.sql';

BEGIN;

DROP TABLE v2.value_conversions;

COMMIT;
