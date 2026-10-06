-- 041_v2_value_conversions.sql -- log of values converted by rule instead of as typed.
--
-- Run after 040_v2_summary_view.sql. Idempotent: guarded like 035-040, and its verification
-- runs inside this transaction.
--
-- Why: v2 stores measurements and coordinates as real types. About 1,900 values the lab typed
-- would not convert ('3.44g', '23°09''06"S', '>1.8', decimal latitudes that Excel formatted
-- as dates), and sat NULL with a type_cast quarantine record after Phase V.4. Owner decision
-- 2026-10-06: convert the mechanical ones by rule -- OceanOmics-Database/v2_value_rules.py,
-- applied by import_v2.py nightly and once by scripts/apply_value_rules.py.
--
-- Some of those rules change meaning, by decision: a bound such as '>1.8' is stored as 1.8.
-- This table keeps every conversion with its raw text and the rule that made it, so:
--   - "which of these numbers was a bound, or came from DMS?" is one query;
--   - the bounds decision is reversible:
--       UPDATE v2.dna_extraction d SET ratio_260_280 = NULL
--         FROM v2.value_conversions c
--        WHERE c.rule = 'bound' AND c.source_table = 'dna_extraction'
--          AND c.column_name = 'ratio_260_280' AND c.row_key = d.dna_id;
--
-- One row per (table, key, column), describing the CURRENT cell: last_seen moves on each
-- import that repeats a conversion, and import_v2.py removes the entry once the workbook holds
-- a value that converts cleanly (or no longer converts at all), because it has just rewritten
-- that cell. 'no_value' conversions (Unknown, TBA, ...) are logged too, stored_value NULL.

BEGIN;

CREATE TABLE IF NOT EXISTS v2.value_conversions (
    source_table  text        NOT NULL,
    row_key       text        NOT NULL,
    column_name   text        NOT NULL,
    raw_value     text        NOT NULL,
    stored_value  text,
    rule          text        NOT NULL,
    converted_by  text        NOT NULL,
    first_seen    timestamptz NOT NULL DEFAULT now(),
    last_seen     timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT value_conversions_pkey PRIMARY KEY (source_table, row_key, column_name),
    CONSTRAINT value_conversions_rule_check CHECK (rule IN (
        'no_value', 'unit', 'bound', 'surface', 'length', 'dms', 'excel_serial_coordinate'))
);

CREATE INDEX IF NOT EXISTS value_conversions_rule_idx ON v2.value_conversions (rule);

COMMENT ON TABLE v2.value_conversions IS
    'Values stored by a conversion rule (OceanOmics-Database/v2_value_rules.py) rather than as '
    'typed, with the raw text. Lets a rule''s effect be audited or undone, e.g. bounds stored '
    'as numbers. Written by import_v2.py and scripts/apply_value_rules.py. See migration 041.';
COMMENT ON COLUMN v2.value_conversions.stored_value IS
    'What was stored, as text; NULL for rule no_value.';
COMMENT ON COLUMN v2.value_conversions.converted_by IS
    'import_v2.py or apply_value_rules.py.';

-- ---------------------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------------------

DO $$
BEGIN
  IF to_regclass('v2.value_conversions') IS NULL THEN
    RAISE EXCEPTION 'Missing table v2.value_conversions';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'v2.value_conversions'::regclass AND contype = 'p') THEN
    RAISE EXCEPTION 'v2.value_conversions has no primary key';
  END IF;
  IF obj_description('v2.value_conversions'::regclass, 'pg_class') IS NULL THEN
    RAISE EXCEPTION 'v2.value_conversions has no COMMENT (Finding 9)';
  END IF;
END $$;

COMMIT;
