-- sync_v3.sql -- Phase R window only: copy public into v3, then prove they are equal.
--
-- Runs every sync function the v3 migrations have created (051: v3.sync_mito; 052:
-- v3.sync_draft; 053: v3.sync_sequencing_run), then every check function, in one transaction.
-- Any check that finds a problem raises, so the whole sync rolls back and v3 stays as it was
-- after the last good night. Run by scripts/sync_v3.sh from cron. Retired at the R.6 merge,
-- together with the functions. docs/assembly_relations_runbook_r0_r5.md R.2.

\set ON_ERROR_STOP 1
BEGIN;

DO $sync$
DECLARE
  fn text;
  r  record;
BEGIN
  FOREACH fn IN ARRAY ARRAY['sync_mito', 'sync_draft', 'sync_sequencing_run'] LOOP
    IF to_regprocedure('v3.' || fn || '()') IS NULL THEN
      CONTINUE;
    END IF;
    FOR r IN EXECUTE format('SELECT * FROM v3.%I()', fn) LOOP
      IF r.changed <> 0 THEN
        RAISE NOTICE '%: % %', fn, r.step, r.changed;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH fn IN ARRAY ARRAY['check_mito', 'check_draft'] LOOP
    IF to_regprocedure('v3.' || fn || '()') IS NULL THEN
      CONTINUE;
    END IF;
    FOR r IN EXECUTE format('SELECT * FROM v3.%I()', fn) LOOP
      IF r.problems <> 0 AND r.check_name NOT LIKE 'annotations selected%' THEN
        RAISE EXCEPTION 'sync_v3 check failed after sync: %: % (%)', fn, r.check_name, r.problems;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'sync_v3 ok';
END
$sync$;

COMMIT;
