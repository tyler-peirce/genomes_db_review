-- Verify genomes_db:create_v2_quarantine on pg

-- Beyond existence, this exercises the idempotency the nightly import depends on: the same
-- unresolved violation recorded twice must update one row, not create two.

BEGIN;

DO $$
DECLARE
  id1 bigint;
  id2 bigint;
  n   bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'v2' AND table_name = 'import_quarantine') THEN
    RAISE EXCEPTION 'Missing table v2.import_quarantine';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema = 'v2' AND table_name = 'v_quarantine_open') THEN
    RAISE EXCEPTION 'Missing view v2.v_quarantine_open';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.views
                 WHERE table_schema = 'v2' AND table_name = 'v_quarantine_displaced') THEN
    RAISE EXCEPTION 'Missing view v2.v_quarantine_displaced';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'v2' AND table_name = 'workbook_attempt_keys') THEN
    RAISE EXCEPTION 'Missing table v2.workbook_attempt_keys';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc p
                 JOIN pg_namespace n2 ON n2.oid = p.pronamespace
                 WHERE n2.nspname = 'v2' AND p.proname = 'quarantine') THEN
    RAISE EXCEPTION 'Missing function v2.quarantine()';
  END IF;

  -- Recording the same violation twice must collapse to one open row.
  SELECT v2.quarantine('dna_extraction', 'OG1G_D', 'type_cast',
                       'status_overwrite = 8621', '{"dna_id":"OG1G_D"}'::jsonb) INTO id1;
  SELECT v2.quarantine('dna_extraction', 'OG1G_D', 'type_cast',
                       'status_overwrite = 8621 (seen again)', '{"dna_id":"OG1G_D"}'::jsonb) INTO id2;

  IF id1 IS DISTINCT FROM id2 THEN
    RAISE EXCEPTION 'v2.quarantine() created a second row (% then %) for one unresolved violation', id1, id2;
  END IF;

  SELECT count(*) INTO n FROM v2.import_quarantine WHERE resolved_at IS NULL;
  IF n <> 1 THEN
    RAISE EXCEPTION 'Expected 1 open quarantine row, found %', n;
  END IF;

  -- A different violation on the same row is a separate record.
  PERFORM v2.quarantine('dna_extraction', 'OG1G_D', 'foreign_key',
                        'tissue_id not found', '{"dna_id":"OG1G_D"}'::jsonb);
  SELECT count(*) INTO n FROM v2.import_quarantine WHERE resolved_at IS NULL;
  IF n <> 2 THEN
    RAISE EXCEPTION 'Expected 2 open quarantine rows for two distinct violations, found %', n;
  END IF;

  -- Once resolved, the same violation recurring opens a fresh record rather than reviving one.
  UPDATE v2.import_quarantine SET resolved_at = now(), resolution_note = 'fixed in workbook'
   WHERE violation_type = 'type_cast';
  PERFORM v2.quarantine('dna_extraction', 'OG1G_D', 'type_cast',
                        'regressed', '{"dna_id":"OG1G_D"}'::jsonb);
  SELECT count(*) INTO n FROM v2.import_quarantine WHERE violation_type = 'type_cast';
  IF n <> 2 THEN
    RAISE EXCEPTION 'Expected a fresh record after resolution, found % type_cast rows', n;
  END IF;

  -- A resolution note without a resolution date must be rejected.
  BEGIN
    UPDATE v2.import_quarantine SET resolution_note = 'note with no date', resolved_at = NULL
     WHERE violation_type = 'foreign_key';
    RAISE EXCEPTION 'import_quarantine_resolution_check did not fire';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- A displaced row is a record, not a blocker: listed by v_quarantine_displaced and kept
  -- out of v_quarantine_open.
  PERFORM v2.quarantine('dna_extraction', 'OG2111E_D', 'displaced',
                        'replaced by workbook row OG2111G_D for (OG2111G, 1)',
                        '{"dna_id":"OG2111E_D"}'::jsonb);
  IF EXISTS (SELECT 1 FROM v2.v_quarantine_open WHERE violation_type = 'displaced') THEN
    RAISE EXCEPTION 'v_quarantine_open lists displaced rows';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM v2.v_quarantine_displaced WHERE displaced_key = 'OG2111E_D') THEN
    RAISE EXCEPTION 'v_quarantine_displaced does not list a displaced row';
  END IF;

  -- An unknown violation type must be rejected.
  BEGIN
    PERFORM v2.quarantine('dna_extraction', 'X', 'vibes', 'nope', '{}'::jsonb);
    RAISE EXCEPTION 'import_quarantine_violation_type_check did not fire';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END $$;

ROLLBACK;
