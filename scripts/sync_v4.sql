-- sync_v4.sql -- Phase RG window only: copy public into v4, then prove they are equal.
--
-- Runs every sync function the v4 migrations have created (057: v4.sync_ref_assembly; 058:
-- v4.sync_ref_read_qc; 059: v4.sync_ref_submission), then every check function, in one
-- transaction. Any check that finds a problem raises, so the whole sync rolls back and v4 stays as
-- it was after the last good night. Checks named 'note: ...' are informational. Run by
-- scripts/sync_v4.sh from cron. Kept separate from sync_v3.sql so v4 stands alone. Retired at the
-- RG.6 swap, together with the functions. docs/ref_genomes_runbook_rg0_rg5.md RG.1.

\set ON_ERROR_STOP 1
BEGIN;

DO $sync$
DECLARE
  fn text;
  r  record;
BEGIN
  FOREACH fn IN ARRAY ARRAY['sync_ref_assembly', 'sync_ref_read_qc', 'sync_ref_submission'] LOOP
    IF to_regprocedure('v4.' || fn || '()') IS NULL THEN
      CONTINUE;
    END IF;
    FOR r IN EXECUTE format('SELECT * FROM v4.%I()', fn) LOOP
      IF r.changed <> 0 THEN
        RAISE NOTICE '%: % %', fn, r.step, r.changed;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH fn IN ARRAY ARRAY['check_ref_assembly', 'check_ref_read_qc', 'check_ref_submission'] LOOP
    IF to_regprocedure('v4.' || fn || '()') IS NULL THEN
      CONTINUE;
    END IF;
    FOR r IN EXECUTE format('SELECT * FROM v4.%I()', fn) LOOP
      CONTINUE WHEN r.problems = 0;
      IF r.check_name LIKE 'note:%' THEN
        RAISE NOTICE 'sync_v4 %: %: %', fn, r.check_name, r.problems;
      ELSE
        RAISE EXCEPTION 'sync_v4 check failed after sync: %: % (%)', fn, r.check_name, r.problems;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'sync_v4 ok';
END
$sync$;

COMMIT;
