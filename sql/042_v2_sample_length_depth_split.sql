-- 042_v2_sample_length_depth_split.sql -- length as TL / FL / unspecified, depth as a range.
--
-- Run after 041_v2_value_conversions.sql. Idempotent; its verification runs inside this
-- transaction.
--
-- Why (owner decision 2026-10-06): two v2.sample columns each held more than one thing.
--
--   lengthtl_and_lengthfl  The workbook's "Length (TL or FL mm)". On live it holds total
--                          length (131 values), fork length (59), BOTH in one cell (50, e.g.
--                          '120 TL, 105 FL'), and an unlabelled number (1,287). As one real
--                          column, the label was lost and a cell holding both could not be
--                          stored at all. Now: length_tl_mm, length_fl_mm, and
--                          length_unspecified_mm for an unlabelled number -- nothing is
--                          guessed, and the lab can relabel rows over time.
--   depth_collection       "Depth_Collection (m)". 73 values are ranges ('330-730',
--                          '5 to 15', '5.9 - 9.5'), which a single number cannot hold. Now:
--                          depth_min_m / depth_max_m (Darwin Core minimumDepthInMeters /
--                          maximumDepthInMeters). A single depth sets both.
--
-- The workbook keeps its single columns; import_v2.py parses them into these
-- (OceanOmics-Database/v2_value_rules.py, SPLITS). Every value that took parsing is logged in
-- v2.value_conversions under the new rules 'length_split' and 'depth_range'; the coordinate
-- rule 'dms_assumed_hemisphere' is added here too (owner decision: no-hemisphere coordinates
-- in the Australian range are taken as south / east).
--
-- The two old columns are DROPPED, not kept beside the new ones: two homes for one fact is the
-- defect being removed. Nothing in the database reads them (checked: no view or function), and
-- every value is recoverable -- the workbook holds the text, and so does public.sample until
-- V.6. Run import_v2.py straight after this to fill the new columns.

BEGIN;

ALTER TABLE v2.sample
    ADD COLUMN IF NOT EXISTS length_tl_mm          real,
    ADD COLUMN IF NOT EXISTS length_fl_mm          real,
    ADD COLUMN IF NOT EXISTS length_unspecified_mm real,
    ADD COLUMN IF NOT EXISTS depth_min_m           real,
    ADD COLUMN IF NOT EXISTS depth_max_m           real,
    DROP COLUMN IF EXISTS lengthtl_and_lengthfl,
    DROP COLUMN IF EXISTS depth_collection;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conrelid = 'v2.sample'::regclass AND conname = 'sample_depth_range_check') THEN
        ALTER TABLE v2.sample ADD CONSTRAINT sample_depth_range_check
            CHECK (depth_min_m IS NULL OR depth_max_m IS NULL OR depth_min_m <= depth_max_m);
    END IF;
END $$;

COMMENT ON COLUMN v2.sample.length_tl_mm IS
    'Total length, mm. From a TL-labelled value in the workbook''s "Length (TL or FL mm)".';
COMMENT ON COLUMN v2.sample.length_fl_mm IS
    'Fork length, mm. From an FL-labelled value in "Length (TL or FL mm)"; a cell can give both.';
COMMENT ON COLUMN v2.sample.length_unspecified_mm IS
    'A length the workbook gives without saying TL or FL, mm. Not guessed: relabel at source.';
COMMENT ON COLUMN v2.sample.depth_min_m IS
    'Collection depth, shallow end, metres (Darwin Core minimumDepthInMeters). Equals depth_max_m '
    'for a single depth; 0 for "<x" and for "Surface".';
COMMENT ON COLUMN v2.sample.depth_max_m IS
    'Collection depth, deep end, metres (Darwin Core maximumDepthInMeters). NULL for ">x".';

-- New rule names in the conversion log.
ALTER TABLE v2.value_conversions DROP CONSTRAINT IF EXISTS value_conversions_rule_check;
ALTER TABLE v2.value_conversions ADD CONSTRAINT value_conversions_rule_check CHECK (rule IN (
    'no_value', 'unit', 'bound', 'surface', 'length', 'dms', 'excel_serial_coordinate',
    'dms_assumed_hemisphere', 'length_split', 'depth_range'));

-- Log entries for the dropped columns describe cells that no longer exist.
DELETE FROM v2.value_conversions
 WHERE source_table = 'sample' AND column_name IN ('lengthtl_and_lengthfl', 'depth_collection');

-- ---------------------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------------------

DO $$
DECLARE
  col text;
BEGIN
  FOREACH col IN ARRAY ARRAY['length_tl_mm', 'length_fl_mm', 'length_unspecified_mm',
                             'depth_min_m', 'depth_max_m'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = 'sample' AND column_name = col
                     AND data_type = 'real') THEN
      RAISE EXCEPTION 'v2.sample.% is missing or not real', col;
    END IF;
    IF col_description('v2.sample'::regclass,
                       (SELECT attnum FROM pg_attribute
                         WHERE attrelid = 'v2.sample'::regclass AND attname = col)) IS NULL THEN
      RAISE EXCEPTION 'v2.sample.% has no COMMENT (Finding 9)', col;
    END IF;
  END LOOP;
  FOREACH col IN ARRAY ARRAY['lengthtl_and_lengthfl', 'depth_collection'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'v2' AND table_name = 'sample' AND column_name = col) THEN
      RAISE EXCEPTION 'v2.sample.% should have been dropped', col;
    END IF;
  END LOOP;
END $$;

COMMIT;
