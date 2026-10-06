-- Revert 042_v2_sample_length_depth_split.sql.
--
-- Restores the two single columns, EMPTY, and drops the five split columns with their values.
-- Re-running the previous import_v2.py (before the split) refills the old columns from the
-- workbook. The rule check on v2.value_conversions is put back to 041's list, so first delete
-- any rows logged under the three rules 042 added, or this fails -- deliberately loudly.
-- Does not touch the ledger; afterwards:
--
--     DELETE FROM schema_migrations WHERE filename = '042_v2_sample_length_depth_split.sql';

BEGIN;

ALTER TABLE v2.sample
    DROP CONSTRAINT sample_depth_range_check,
    DROP COLUMN length_tl_mm,
    DROP COLUMN length_fl_mm,
    DROP COLUMN length_unspecified_mm,
    DROP COLUMN depth_min_m,
    DROP COLUMN depth_max_m,
    ADD COLUMN lengthtl_and_lengthfl real,
    ADD COLUMN depth_collection real;

ALTER TABLE v2.value_conversions DROP CONSTRAINT value_conversions_rule_check;
ALTER TABLE v2.value_conversions ADD CONSTRAINT value_conversions_rule_check CHECK (rule IN (
    'no_value', 'unit', 'bound', 'surface', 'length', 'dms', 'excel_serial_coordinate'));

COMMIT;
