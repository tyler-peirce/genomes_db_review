-- Deploy genomes_db:create_v2_quarantine to pg
-- requires: create_v2_lab_tables

-- Purpose: Give rows that violate the new NOT NULL / FK / type / uniqueness contracts somewhere
--   to go, so they can be fixed at source rather than silently dropped or silently weakening
--   the schema (decision 6, §5 step 9).
--
--   One jsonb-backed table rather than a shadow schema of twelve. Twelve typed quarantine
--   tables would have to be kept in step with twelve real ones forever, and could not hold the
--   rows that fail precisely because they will not cast into those types. A single table also
--   answers "what is currently blocked?" in one query, which is the question the lab will
--   actually ask.
--
-- Review source: docs/v2_scaffold_design_review.md decision 6, §5 step 9.
-- Expected impact: Additive only. One table, one function, one view, in the `v2` schema.

BEGIN;

CREATE TABLE v2.import_quarantine (
    quarantine_id    bigint GENERATED ALWAYS AS IDENTITY,
    source_table     text        NOT NULL,
    source_sheet     text,
    source_row_key   text,
    violation_type   text        NOT NULL,
    violation_detail text,
    raw_row          jsonb       NOT NULL,
    first_seen       timestamptz NOT NULL DEFAULT now(),
    last_seen        timestamptz NOT NULL DEFAULT now(),
    resolved_at      timestamptz,
    resolution_note  text,

    CONSTRAINT import_quarantine_pkey PRIMARY KEY (quarantine_id),
    CONSTRAINT import_quarantine_violation_type_check CHECK (violation_type IN (
        'not_null',              -- a required parent or field was empty
        'foreign_key',           -- parent ID does not exist
        'type_cast',             -- value will not convert to the column type
        'unique',                -- collides with an existing row
        'duplicate_source_row',  -- the SOURCE has the same key twice (see §4.4)
        'lookup',                -- value is outside a controlled vocabulary
        'conflicting_value'      -- same fact recorded twice with different values
    )),
    -- A resolution note without a resolution date is a half-finished record.
    CONSTRAINT import_quarantine_resolution_check CHECK (resolution_note IS NULL OR resolved_at IS NOT NULL)
);

-- One open row per (table, key, violation). A nightly import that keeps hitting the same bad
-- spreadsheet row bumps last_seen instead of adding 400 duplicates over a year. Resolved rows
-- are excluded so the same problem recurring after a fix opens a fresh record.
CREATE UNIQUE INDEX import_quarantine_open_key
    ON v2.import_quarantine (source_table, coalesce(source_row_key, ''), violation_type)
    WHERE resolved_at IS NULL;

CREATE INDEX import_quarantine_open_idx ON v2.import_quarantine (source_table, last_seen DESC)
    WHERE resolved_at IS NULL;

COMMENT ON TABLE v2.import_quarantine IS
    'Rows rejected by the v2 constraints, held for correction at source. Written by both the '
    'backfill (scripts/backfill_v2.sql) and the nightly import. See v2_scaffold_design_review.md '
    'decision 6.';
COMMENT ON COLUMN v2.import_quarantine.source_table IS 'Target v2 table the row was meant for, unqualified (e.g. "dna_extraction").';
COMMENT ON COLUMN v2.import_quarantine.source_sheet IS 'Originating workbook sheet, when known (e.g. "3.DNAExtractions"), so the lab can find the row to fix.';
COMMENT ON COLUMN v2.import_quarantine.source_row_key IS 'Business key of the rejected row - the tube ID, tissue ID, or og_id. Null when the row has no usable key, which is itself usually the violation.';
COMMENT ON COLUMN v2.import_quarantine.raw_row IS 'The whole rejected row as jsonb, so nothing is lost and the row can be replayed after the source is fixed.';
COMMENT ON COLUMN v2.import_quarantine.last_seen IS 'Bumped each time the same unresolved violation reappears. A stale last_seen means the source row is gone or fixed.';

-- ---------------------------------------------------------------------------------------
-- Recording helper — used by the backfill and by the importer so both behave identically
-- ---------------------------------------------------------------------------------------

CREATE FUNCTION v2.quarantine(
    p_source_table     text,
    p_source_row_key   text,
    p_violation_type   text,
    p_violation_detail text,
    p_raw_row          jsonb,
    p_source_sheet     text DEFAULT NULL
) RETURNS bigint
LANGUAGE sql
AS $$
    INSERT INTO v2.import_quarantine AS q
        (source_table, source_sheet, source_row_key, violation_type, violation_detail, raw_row)
    VALUES
        (p_source_table, p_source_sheet, p_source_row_key, p_violation_type, p_violation_detail, p_raw_row)
    ON CONFLICT (source_table, coalesce(source_row_key, ''), violation_type)
        WHERE resolved_at IS NULL
    DO UPDATE SET last_seen         = now(),
                  violation_detail  = excluded.violation_detail,
                  raw_row           = excluded.raw_row,
                  source_sheet      = coalesce(excluded.source_sheet, q.source_sheet)
    RETURNING quarantine_id;
$$;

COMMENT ON FUNCTION v2.quarantine(text, text, text, text, jsonb, text) IS
    'Record or refresh a quarantined row. Idempotent per (table, key, violation) while the '
    'violation is unresolved, so repeated nightly imports do not accumulate duplicates.';

-- ---------------------------------------------------------------------------------------
-- What is blocked right now
-- ---------------------------------------------------------------------------------------

CREATE VIEW v2.v_quarantine_open AS
SELECT source_table,
       violation_type,
       count(*)      AS rows_blocked,
       min(first_seen) AS oldest,
       max(last_seen)  AS most_recent
FROM v2.import_quarantine
WHERE resolved_at IS NULL
GROUP BY source_table, violation_type
ORDER BY count(*) DESC, source_table, violation_type;

COMMENT ON VIEW v2.v_quarantine_open IS 'One line per (table, violation) still blocking rows. The lab-facing summary of what needs fixing.';

COMMIT;
