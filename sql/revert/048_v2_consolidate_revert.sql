-- Revert v2_consolidate.sql (Phase V.6). Back to the state 045 left: v2 holds the new schema,
-- the database search_path is "v2, public", and the twenty replaced objects are public.*_pre_v2.
--
-- Driven entirely by pre_v2_archive.v6_moved, which the forward migration wrote: what it
-- archived, what it moved, and every original value it overwrote (v2's schema comment, the
-- archived objects' comments, rewritten function definitions, function search_path settings).
-- Nothing was dropped, so this is exact; the rehearsal checks it against a pg_dump -s taken
-- before the apply.
--
-- Order matters. Moved relations go back to v2 first, then moved functions (a rewritten body
-- names v2 relations and is checked at CREATE), and only then do the archived objects return to
-- public, because lca_set_content_hash() and rna_library_kinx_pkey exist on both sides.
--
-- Data written after V.6 stays with the tables, which simply move back: nothing to carry over.
-- But code that started writing "public.sample" after V.6 breaks again, exactly as it did
-- after 045.
--
-- After this, sql/revert/NNN_v2_cutover_revert.sql (045's) can run again, and not before.

BEGIN;

DO $revert$
DECLARE
  r record;
  ledger record;
BEGIN
  IF to_regclass('pre_v2_archive.v6_moved') IS NULL OR to_regnamespace('v2') IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation revert: expects pre_v2_archive.v6_moved and no schema v2';
  END IF;

  -- Schema v2, as 045 left it: USAGE for every role that has it on public, readonly's default
  -- SELECT, and its comment from 035.
  CREATE SCHEMA v2;
  SELECT orig_comment INTO ledger FROM pre_v2_archive.v6_moved WHERE kind = 'v2_schema';
  IF ledger.orig_comment IS NOT NULL THEN
    EXECUTE format('COMMENT ON SCHEMA v2 IS %L', ledger.orig_comment);
  END IF;
  FOR r IN
    SELECT pg_get_userbyid(a.grantee) AS grantee
      FROM pg_namespace n, aclexplode(n.nspacl) a
     WHERE n.nspname = 'public' AND a.privilege_type = 'USAGE'
       AND a.grantee <> 0 AND a.grantee <> n.nspowner
  LOOP
    EXECUTE format('GRANT USAGE ON SCHEMA v2 TO %I', r.grantee);
  END LOOP;
  IF to_regrole('readonly') IS NOT NULL THEN
    ALTER DEFAULT PRIVILEGES IN SCHEMA v2 GRANT SELECT ON TABLES TO readonly;
  END IF;

  -- Moved relations back: tables (with their owned sequences), free sequences, views.
  FOR r IN SELECT * FROM pre_v2_archive.v6_moved WHERE kind = 'moved_rel'
            ORDER BY CASE relkind WHEN 'r' THEN 1 WHEN 'p' THEN 1 WHEN 'S' THEN 2 ELSE 3 END, name
  LOOP
    EXECUTE format('ALTER %s public.%I SET SCHEMA v2',
      CASE r.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW'
                     WHEN 'S' THEN 'SEQUENCE' ELSE 'TABLE' END, r.name);
  END LOOP;

  -- Moved functions back, with their original definition and search_path. After the relations:
  -- a LANGUAGE sql body is checked at CREATE, and quarantine()'s names v2.import_quarantine.
  FOR r IN SELECT * FROM pre_v2_archive.v6_moved WHERE kind = 'moved_fn' ORDER BY name LOOP
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET SCHEMA v2', r.name, r.identity);
    IF r.orig_def IS NOT NULL THEN
      EXECUTE r.orig_def;
    END IF;
    IF r.orig_config IS NOT NULL THEN
      FOR ledger IN SELECT cfg FROM unnest(r.orig_config) cfg WHERE cfg ~ '^search_path=' LOOP
        EXECUTE format('ALTER FUNCTION v2.%I(%s) SET search_path = %s', r.name, r.identity,
          substr(ledger.cfg, length('search_path=') + 1));
      END LOOP;
    END IF;
  END LOOP;

  -- Archived objects back to public, with the comments they had.
  FOR r IN SELECT * FROM pre_v2_archive.v6_moved WHERE kind = 'archived_fn' LOOP
    EXECUTE format('ALTER FUNCTION pre_v2_archive.%I(%s) SET SCHEMA public', r.name, r.identity);
  END LOOP;
  FOR r IN SELECT * FROM pre_v2_archive.v6_moved WHERE kind = 'archived_rel' ORDER BY relkind, name LOOP
    EXECUTE format('ALTER %s pre_v2_archive.%I SET SCHEMA public',
      CASE r.relkind WHEN 'v' THEN 'VIEW' ELSE 'TABLE' END, r.name);
    EXECUTE format('COMMENT ON %s public.%I IS %L',
      CASE r.relkind WHEN 'v' THEN 'VIEW' ELSE 'TABLE' END, r.name, r.orig_comment);
  END LOOP;

  DROP TABLE pre_v2_archive.v6_moved;
  DROP SCHEMA pre_v2_archive;   -- RESTRICT: fails if anything was added to it since

  EXECUTE format('ALTER DATABASE %I SET search_path = v2, public', current_database());

  IF to_regclass('v2.sample') IS NULL OR to_regclass('public.sample_pre_v2') IS NULL
     OR to_regclass('public.sample') IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation revert: v2.sample / public.sample_pre_v2 not back in place';
  END IF;
  RAISE NOTICE 'v2 consolidation revert: complete; database search_path is v2, public for new sessions';
END
$revert$;

COMMIT;
