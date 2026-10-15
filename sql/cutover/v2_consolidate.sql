-- sql/cutover/v2_consolidate.sql -- Phase V.6: move v2 into public and retire the parallel schema.
--
-- Kept OUTSIDE the numbered sequence until the day, like 045: bin/apply_migrations.py applies
-- pending files in order, so a numbered file waiting for its window would block every migration
-- after it. On the day it becomes sql/NNN_v2_consolidate.sql. Read docs/phase_v6_plan.md first.
--
-- After 045 (V.5), unqualified names reach v2 through the database search_path "v2, public" and
-- the twenty replaced public objects are *_pre_v2. This file finishes the job: FROM sample and
-- FROM public.sample reach the same table, and the search_path stops mattering. Objects are
-- MOVED, by OID, not renamed and not copied -- their names are already final (decision 3), and
-- every view, trigger, FK and grant that points at them follows the OID.
--
-- What it does, in order, in one transaction:
--
--   1. Refuses to run unless v2 holds every object 035-046 created, the SS260818 snapshots are
--      gone (Phase F; lca_results_view_SS260818 read sample_pre_v2), and nothing outside the
--      _pre_v2 set reads a _pre_v2 relation. Objects in v2 that no migration created are moved
--      too, and named in a NOTICE: since 045, anything created unqualified lands in v2 -- the
--      post-curation script's build_postcuration_samplesheet_rows() did.
--   2. Archives the twenty _pre_v2 objects, with public.lca_set_content_hash() and
--      public.set_updated_at(), into a new schema pre_v2_archive. Owner decision 2026-10-15:
--      archive, do not drop, so V.5 stays reversible until V.7 drops the archive. This frees
--      the names v2 brings: rna_library_kinx_pkey (held by rna_library_kinx_pre_v2) and the
--      function lca_set_content_hash (whose only users are triggers on lca_pre_v2 and
--      lca_raw_results_pre_v2; set_updated_at's only user is rna_library_kinx_pre_v2). Only
--      readonly gets USAGE on the archive; the objects keep the grants they had.
--   3. Moves every v2 relation and function into public: tables (their indexes, constraints,
--      triggers and owned sequences move with them), then free sequences, views and functions.
--   4. Fixes the two things that bind to the schema by TEXT, not OID:
--      - function bodies that name v2. (v2.quarantine() inserts into v2.import_quarantine;
--        LANGUAGE sql resolves that at call time) are re-created with public. instead;
--      - function search_path settings that name v2 (v2.lca_set_content_hash is pinned to
--        "v2, pg_temp") are re-pinned with public in its place.
--      The original definition and setting are kept in pre_v2_archive.v6_moved for the revert.
--   5. RESETs the database search_path. Before 045 there was none; pg_db_role_setting then holds
--      only oceangenom_web's statement_timeout again. Sessions still open with "v2, public" are
--      unaffected: a schema on the path that does not exist is skipped.
--   6. Revokes the default privilege 045 added on v2, and DROPs schema v2 -- RESTRICT, not
--      CASCADE, so anything left behind stops the migration instead of vanishing.
--   7. Verifies, before COMMIT: v2 is gone; every expected object is in public; no function body
--      or setting names v2; the seven 045-rebound views kept their grants and the two write
--      paths their triggers; readonly reads sample, summary and v_sequencing_browse;
--      oceangenom_web can UPDATE sample.workflow and nothing else on sample; nothing in public
--      depends on pre_v2_archive.
--
-- What it does not fix: contracts. The columns v2 removed stay removed wherever the table sits
-- (database_review.md, V.6). And code that started writing "v2.sample" after 045 breaks here;
-- unqualified names, which is what everything was told to use, are unaffected. The nightly
-- importer was made unqualified before this file was written (OceanOmics-Database/import_v2.py).
--
-- Replay: returns at once if v2 is gone and pre_v2_archive exists, so the crash-recovery replay
-- in bin/apply_migrations.py is a no-op. One transaction, so no half-applied state.
--
-- Opt-in: refuses unless PGOPTIONS="-c oceanomics.v2_consolidate=go" is set.
--
-- Rollback: v2_consolidate_revert.sql (sql/revert/NNN_... on the day), from the record in
-- pre_v2_archive.v6_moved. Nothing is dropped here, so the revert is exact.

BEGIN;

DO $consolidate$
DECLARE
  pre_v2_tables text[] := ARRAY[
    'sample', 'tissue', 'dna_extraction', 'rna_extraction', 'hic_lysate',
    'illumina_library', 'pacbio_library', 'ont_library', 'hic_library',
    'rna_library_ilmn', 'rna_library_kinx', 'sequencing',
    'mitogenome_data', 'lca', 'lca_validation', 'lca_raw_results', 'blast_filtered_lca'];
  pre_v2_views text[] := ARRAY['summary', 'goat_species_v1', 'mitogenome_submission_view'];
  archived_functions text[] := ARRAY['lca_set_content_hash()', 'set_updated_at()'];
  -- What 035-046 create in v2. Anything else found there is moved and reported.
  expected_tables text[] := ARRAY[
    'blast_filtered_lca', 'dna_extraction', 'hic_library', 'hic_lysate', 'illumina_library',
    'import_quarantine', 'lca', 'lca_raw_results', 'lca_validation', 'library',
    'mitogenome_data', 'ont_library', 'pacbio_library', 'prep_automation', 'rna_extraction',
    'rna_library_ilmn', 'rna_library_kinx', 'sample', 'sequencing', 'tissue',
    'value_conversions', 'workbook_attempt_keys'];
  expected_views text[] := ARRAY[
    'goat_species_v1', 'mitogenome_submission_view', 'summary', 'v_dna_extraction_browse',
    'v_hic_library_browse', 'v_hic_lysate_browse', 'v_illumina_library_browse',
    'v_library_browse', 'v_ont_library_browse', 'v_pacbio_library_browse',
    'v_quarantine_displaced', 'v_quarantine_open', 'v_rna_extraction_browse',
    'v_rna_library_ilmn_browse', 'v_rna_library_kinx_browse', 'v_sequencing_browse',
    'v_tissue_browse'];
  expected_functions text[] := ARRAY['quarantine', 'lca_set_content_hash'];
  -- The views 045 rebound to v2; their grants and the two write-path triggers must survive.
  rebound_views text[] := ARRAY[
    'lca_pivot_view', 'sample_view', 'v_genome_size_comparison', 'lca_results_view',
    'filtered_lca_view', 'embargo_assignment_view', 'lca_validation_report_view'];
  write_paths text[] := ARRAY['embargo_assignment_view', 'lca_validation_report_view'];
  t text;
  n bigint;
  msg text;
  acls jsonb := '{}';
  r record;
  stamp text := 'ARCHIVED ' || current_date || ' by the v2 consolidation migration (V.6); dropped in V.7. ';
BEGIN
  -- Replay guard.
  IF to_regnamespace('v2') IS NULL AND to_regnamespace('pre_v2_archive') IS NOT NULL THEN
    RAISE NOTICE 'v2 consolidation: already in place, nothing to do';
    RETURN;
  END IF;

  -- Opt-in guard.
  IF coalesce(current_setting('oceanomics.v2_consolidate', true), '') <> 'go' THEN
    RAISE EXCEPTION 'The v2 consolidation runs only on purpose. Follow docs/phase_v6_plan.md, '
      'then: PGOPTIONS="-c oceanomics.v2_consolidate=go" bin/apply_migrations.py';
  END IF;

  -- -------------------------------------------------------------------------------------
  -- 1. Preconditions
  -- -------------------------------------------------------------------------------------
  IF to_regnamespace('v2') IS NULL THEN
    RAISE EXCEPTION 'v2 consolidation: schema v2 does not exist';
  END IF;
  IF to_regnamespace('pre_v2_archive') IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: schema pre_v2_archive already exists';
  END IF;
  IF to_regclass('public.sample') IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: public.sample exists; the V.5 cutover (045) is not in place';
  END IF;

  FOREACH t IN ARRAY pre_v2_tables || pre_v2_views LOOP
    IF to_regclass('public.' || quote_ident(t || '_pre_v2')) IS NULL THEN
      RAISE EXCEPTION 'v2 consolidation: public.%_pre_v2 is missing', t;
    END IF;
  END LOOP;
  FOREACH t IN ARRAY expected_tables || expected_views LOOP
    IF to_regclass('v2.' || quote_ident(t)) IS NULL THEN
      RAISE EXCEPTION 'v2 consolidation: v2.% is missing', t;
    END IF;
  END LOOP;
  FOREACH t IN ARRAY expected_functions LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'v2'::regnamespace AND proname = t) THEN
      RAISE EXCEPTION 'v2 consolidation: function v2.% is missing', t;
    END IF;
  END LOOP;
  FOREACH t IN ARRAY rebound_views LOOP
    IF to_regclass('public.' || quote_ident(t)) IS NULL THEN
      RAISE EXCEPTION 'v2 consolidation: public.% is missing', t;
    END IF;
    acls := acls || jsonb_build_object(t,
      (SELECT coalesce(relacl::text, '') FROM pg_class WHERE oid = ('public.' || quote_ident(t))::regclass));
  END LOOP;

  SELECT string_agg(relname, ', ') INTO msg
    FROM pg_class WHERE relname LIKE '%SS260818%' AND relkind IN ('r', 'v', 'm');
  IF msg IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: drop the SS260818 snapshots first (Phase F): %', msg;
  END IF;

  -- Nothing outside the _pre_v2 set may read a _pre_v2 relation, by view or by foreign key.
  SELECT string_agg(DISTINCT v.relname || ' -> ' || ref.relname, ', ') INTO msg
    FROM pg_class v
    JOIN pg_rewrite rw ON rw.ev_class = v.oid
    JOIN pg_depend d ON d.objid = rw.oid AND d.classid = 'pg_rewrite'::regclass
                    AND d.refclassid = 'pg_class'::regclass
    JOIN pg_class ref ON ref.oid = d.refobjid AND ref.oid <> v.oid
   WHERE ref.relnamespace = 'public'::regnamespace AND ref.relname LIKE '%\_pre\_v2'
     AND NOT (v.relnamespace = 'public'::regnamespace AND v.relname LIKE '%\_pre\_v2');
  IF msg IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: still reading _pre_v2 relations: %', msg;
  END IF;
  SELECT string_agg(conrelid::regclass::text || ' -> ' || confrelid::regclass::text, ', ') INTO msg
    FROM pg_constraint
   WHERE contype = 'f' AND confrelid::regclass::text LIKE '%\_pre\_v2'
     AND conrelid::regclass::text NOT LIKE '%\_pre\_v2';
  IF msg IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: foreign keys into _pre_v2 relations: %', msg;
  END IF;

  -- The two public functions being archived must be used only by triggers on _pre_v2 tables.
  SELECT string_agg(tgrelid::regclass::text || ' uses ' || tgfoid::regprocedure::text, ', ') INTO msg
    FROM pg_trigger
   WHERE tgfoid IN (SELECT ('public.' || f)::regprocedure FROM unnest(archived_functions) f)
     AND tgrelid::regclass::text NOT LIKE '%\_pre\_v2';
  IF msg IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: archived functions still in use outside _pre_v2: %', msg;
  END IF;

  SELECT string_agg(c.relname || ' (' || c.relkind || ')', ', ') INTO msg
    FROM pg_class c
   WHERE c.relnamespace = 'v2'::regnamespace AND c.relkind IN ('r', 'p', 'v', 'm')
     AND NOT c.relname = ANY (expected_tables || expected_views);
  IF msg IS NOT NULL THEN
    RAISE NOTICE 'v2 consolidation: relations in v2 that no migration created, moved anyway: %', msg;
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO msg
    FROM pg_proc p
   WHERE p.pronamespace = 'v2'::regnamespace AND NOT p.proname = ANY (expected_functions);
  IF msg IS NOT NULL THEN
    RAISE NOTICE 'v2 consolidation: functions in v2 that no migration created, moved anyway: %', msg;
  END IF;

  -- -------------------------------------------------------------------------------------
  -- 2. Archive the _pre_v2 objects and the two functions only they use
  -- -------------------------------------------------------------------------------------
  CREATE SCHEMA pre_v2_archive;
  COMMENT ON SCHEMA pre_v2_archive IS
    'The twenty public objects the v2 cutover (045) replaced, plus the two trigger functions only '
    'they use, moved here by the v2 consolidation migration (V.6) so v2 could move into public. '
    'Frozen as of 2026-10-13. Kept for rollback; dropped in V.7.';

  -- The revert's record: what moved where, and every original value this file overwrites.
  CREATE TABLE pre_v2_archive.v6_moved (
    kind         text NOT NULL,   -- 'v2_schema', 'archived_rel', 'archived_fn', 'moved_rel', 'moved_fn'
    relkind      "char",
    name         text NOT NULL,   -- relation name, or function name
    identity     text NOT NULL DEFAULT '',  -- function identity arguments; '' for relations
    orig_comment text,            -- archived relations: comment before the stamp
    orig_def     text,            -- moved functions: definition before a body rewrite
    orig_config  text[],          -- moved functions: proconfig before a re-pin
    PRIMARY KEY (kind, name, identity)
  );
  COMMENT ON TABLE pre_v2_archive.v6_moved IS
    'Written by the v2 consolidation migration (V.6) and read by its revert. Do not edit.';

  INSERT INTO pre_v2_archive.v6_moved (kind, name, orig_comment)
    VALUES ('v2_schema', 'v2', obj_description('v2'::regnamespace, 'pg_namespace'));

  FOREACH t IN ARRAY pre_v2_tables || pre_v2_views LOOP
    INSERT INTO pre_v2_archive.v6_moved (kind, relkind, name, identity, orig_comment)
      SELECT 'archived_rel', c.relkind, c.relname, '', obj_description(c.oid, 'pg_class')
        FROM pg_class c WHERE c.oid = ('public.' || quote_ident(t || '_pre_v2'))::regclass;
    EXECUTE format('ALTER %s public.%I SET SCHEMA pre_v2_archive',
      CASE WHEN t = ANY (pre_v2_views) THEN 'VIEW' ELSE 'TABLE' END, t || '_pre_v2');
    EXECUTE format('COMMENT ON %s pre_v2_archive.%I IS %L',
      CASE WHEN t = ANY (pre_v2_views) THEN 'VIEW' ELSE 'TABLE' END, t || '_pre_v2',
      stamp || coalesce(obj_description(('pre_v2_archive.' || quote_ident(t || '_pre_v2'))::regclass,
                                        'pg_class'), ''));
  END LOOP;
  FOREACH t IN ARRAY archived_functions LOOP
    INSERT INTO pre_v2_archive.v6_moved (kind, name, identity)
      SELECT 'archived_fn', p.proname, pg_get_function_identity_arguments(p.oid)
        FROM pg_proc p WHERE p.oid = ('public.' || t)::regprocedure;
    EXECUTE format('ALTER FUNCTION public.%s SET SCHEMA pre_v2_archive', t);
  END LOOP;

  -- The archived objects keep the grants they had in public, readonly's SELECT among them; only
  -- the schema needs opening. No blanket GRANT here, so the revert restores the ACLs exactly.
  IF to_regrole('readonly') IS NOT NULL THEN
    GRANT USAGE ON SCHEMA pre_v2_archive TO readonly;
  END IF;

  -- -------------------------------------------------------------------------------------
  -- 3. Move v2 into public
  -- -------------------------------------------------------------------------------------
  -- Name collisions would fail the moves one at a time with a terse message; report them all.
  SELECT string_agg(c.relname, ', ') INTO msg
    FROM pg_class c
   WHERE c.relnamespace = 'v2'::regnamespace
     AND EXISTS (SELECT 1 FROM pg_class p WHERE p.relnamespace = 'public'::regnamespace
                                            AND p.relname = c.relname);
  IF msg IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: names already taken in public: %', msg;
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO msg
    FROM pg_proc p
   WHERE p.pronamespace = 'v2'::regnamespace
     AND EXISTS (SELECT 1 FROM pg_proc q WHERE q.pronamespace = 'public'::regnamespace
                    AND q.proname = p.proname AND q.proargtypes = p.proargtypes);
  IF msg IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: functions already defined in public: %', msg;
  END IF;

  -- Tables first: indexes, constraints, triggers and owned sequences move with them. Then
  -- sequences nothing owns (an owned sequence refuses to move on its own), then views.
  FOR r IN
    SELECT c.relname, c.relkind
      FROM pg_class c
     WHERE c.relnamespace = 'v2'::regnamespace
       AND (c.relkind IN ('r', 'p', 'v', 'm')
            OR (c.relkind = 'S' AND NOT EXISTS (
                  SELECT 1 FROM pg_depend d
                   WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid
                     AND d.refclassid = 'pg_class'::regclass AND d.deptype IN ('a', 'i'))))
     ORDER BY CASE c.relkind WHEN 'r' THEN 1 WHEN 'p' THEN 1 WHEN 'S' THEN 2 ELSE 3 END, c.relname
  LOOP
    INSERT INTO pre_v2_archive.v6_moved (kind, relkind, name, identity)
      VALUES ('moved_rel', r.relkind, r.relname, '');
    EXECUTE format('ALTER %s v2.%I SET SCHEMA public',
      CASE r.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW'
                     WHEN 'S' THEN 'SEQUENCE' ELSE 'TABLE' END, r.relname);
  END LOOP;

  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args,
           p.prokind, p.proconfig
      FROM pg_proc p WHERE p.pronamespace = 'v2'::regnamespace ORDER BY p.proname
  LOOP
    INSERT INTO pre_v2_archive.v6_moved (kind, name, identity, orig_def, orig_config)
      VALUES ('moved_fn', r.proname, r.args,
              CASE WHEN (SELECT prosrc FROM pg_proc WHERE oid = r.oid) ~ '\mv2\.'
                   THEN pg_get_functiondef(r.oid) END,
              r.proconfig);
    EXECUTE format('ALTER %s v2.%I(%s) SET SCHEMA public',
      CASE r.prokind WHEN 'p' THEN 'PROCEDURE' WHEN 'a' THEN 'AGGREGATE' ELSE 'FUNCTION' END,
      r.proname, r.args);
  END LOOP;

  SELECT string_agg(format('%s (%s)', t2.typname, t2.typtype), ', ') INTO msg
    FROM pg_type t2
   WHERE t2.typnamespace = 'v2'::regnamespace AND t2.typrelid = 0 AND t2.typelem = 0;
  IF msg IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: v2 holds free-standing types this file does not move: %', msg;
  END IF;

  -- -------------------------------------------------------------------------------------
  -- 4. What binds by text: function bodies and function search_path settings
  -- -------------------------------------------------------------------------------------
  FOR r IN SELECT name, identity, orig_def FROM pre_v2_archive.v6_moved
            WHERE kind = 'moved_fn' AND orig_def IS NOT NULL
  LOOP
    -- The definition still reads "FUNCTION v2.name(" from capture time; it now lives in public.
    EXECUTE regexp_replace(r.orig_def, '\mv2\.', 'public.', 'g');
    RAISE NOTICE 'v2 consolidation: rewrote public.%(%) without v2.', r.name, r.identity;
  END LOOP;
  FOR r IN SELECT name, identity, cfg
             FROM pre_v2_archive.v6_moved, unnest(orig_config) cfg
            WHERE kind = 'moved_fn' AND cfg ~ '^search_path=' AND cfg ~ '(=|,\s*)"?v2"?(,|$)'
  LOOP
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = %s', r.name, r.identity,
      regexp_replace(substr(r.cfg, length('search_path=') + 1), '(^|,\s*)"?v2"?(?=,|$)', '\1public', 'g'));
  END LOOP;

  -- -------------------------------------------------------------------------------------
  -- 5. Database search_path back to the default
  -- -------------------------------------------------------------------------------------
  EXECUTE format('ALTER DATABASE %I RESET search_path', current_database());

  -- -------------------------------------------------------------------------------------
  -- 6. Retire schema v2
  -- -------------------------------------------------------------------------------------
  FOR r IN
    SELECT pg_get_userbyid(d.defaclrole) AS grantor, pg_get_userbyid(a.grantee) AS grantee,
           a.privilege_type AS priv, d.defaclobjtype AS objtype
      FROM pg_default_acl d, aclexplode(d.defaclacl) a
     WHERE d.defaclnamespace = 'v2'::regnamespace
  LOOP
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA v2 REVOKE %s ON %s FROM %I',
      r.grantor, r.priv,
      CASE r.objtype WHEN 'r' THEN 'TABLES' WHEN 'S' THEN 'SEQUENCES' WHEN 'f' THEN 'FUNCTIONS'
                     WHEN 'T' THEN 'TYPES' ELSE 'SCHEMAS' END,
      r.grantee);
  END LOOP;
  DROP SCHEMA v2;

  -- -------------------------------------------------------------------------------------
  -- 7. Verification
  -- -------------------------------------------------------------------------------------
  IF to_regnamespace('v2') IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: schema v2 still exists';
  END IF;
  FOREACH t IN ARRAY expected_tables LOOP
    IF (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.' || quote_ident(t))) IS DISTINCT FROM 'r' THEN
      RAISE EXCEPTION 'v2 consolidation: public.% is not the moved table', t;
    END IF;
  END LOOP;
  FOREACH t IN ARRAY expected_views LOOP
    IF (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.' || quote_ident(t))) IS DISTINCT FROM 'v' THEN
      RAISE EXCEPTION 'v2 consolidation: public.% is not the moved view', t;
    END IF;
  END LOOP;

  SELECT string_agg(n2.nspname || '.' || p.proname, ', ') INTO msg
    FROM pg_proc p JOIN pg_namespace n2 ON n2.oid = p.pronamespace
   WHERE n2.nspname NOT IN ('pg_catalog', 'information_schema', 'pre_v2_archive')
     AND (p.prosrc ~ '\mv2\.' OR array_to_string(p.proconfig, ';') ~ '(=|,\s*)"?v2"?(,|;|$)');
  IF msg IS NOT NULL THEN
    RAISE EXCEPTION 'v2 consolidation: functions still naming v2: %', msg;
  END IF;

  FOREACH t IN ARRAY rebound_views LOOP
    IF (SELECT coalesce(relacl::text, '') FROM pg_class
         WHERE oid = ('public.' || quote_ident(t))::regclass) <> acls->>t THEN
      RAISE EXCEPTION 'v2 consolidation: grants on public.% changed', t;
    END IF;
  END LOOP;
  FOREACH t IN ARRAY write_paths LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid = ('public.' || quote_ident(t))::regclass AND NOT tgisinternal
                      AND tgtype & 64 <> 0) THEN   -- 64 = INSTEAD OF
      RAISE EXCEPTION 'v2 consolidation: public.% lost its INSTEAD OF trigger', t;
    END IF;
  END LOOP;

  IF to_regrole('readonly') IS NOT NULL AND NOT (
       has_table_privilege('readonly', 'public.sample', 'SELECT')
       AND has_table_privilege('readonly', 'public.summary', 'SELECT')
       AND has_table_privilege('readonly', 'public.v_sequencing_browse', 'SELECT')) THEN
    RAISE EXCEPTION 'v2 consolidation: readonly cannot read the moved objects';
  END IF;
  IF to_regrole('oceangenom_web') IS NOT NULL AND (
       NOT has_column_privilege('oceangenom_web', 'public.sample', 'workflow', 'UPDATE')
       OR has_table_privilege('oceangenom_web', 'public.sample', 'UPDATE')) THEN
    RAISE EXCEPTION 'v2 consolidation: oceangenom_web must be able to UPDATE sample.workflow and nothing else';
  END IF;

  -- Nothing outside the archive may depend on it: views, foreign keys, triggers.
  SELECT count(*) INTO n
    FROM pg_depend d
    JOIN pg_rewrite rw ON d.classid = 'pg_rewrite'::regclass AND d.objid = rw.oid
    JOIN pg_class v ON v.oid = rw.ev_class
    JOIN pg_class ref ON d.refclassid = 'pg_class'::regclass AND ref.oid = d.refobjid
   WHERE ref.relnamespace = 'pre_v2_archive'::regnamespace
     AND v.relnamespace <> 'pre_v2_archive'::regnamespace;
  n := n + (SELECT count(*) FROM pg_constraint c JOIN pg_class ref ON ref.oid = c.confrelid
                                                 JOIN pg_class s ON s.oid = c.conrelid
             WHERE c.contype = 'f' AND ref.relnamespace = 'pre_v2_archive'::regnamespace
               AND s.relnamespace <> 'pre_v2_archive'::regnamespace)
         + (SELECT count(*) FROM pg_trigger g JOIN pg_proc p ON p.oid = g.tgfoid
                                              JOIN pg_class s ON s.oid = g.tgrelid
             WHERE p.pronamespace = 'pre_v2_archive'::regnamespace
               AND s.relnamespace <> 'pre_v2_archive'::regnamespace);
  IF n > 0 THEN
    RAISE EXCEPTION 'v2 consolidation: % objects outside pre_v2_archive depend on it', n;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_db_role_setting
              WHERE setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
                AND setrole = 0 AND array_to_string(setconfig, ';') ~ 'search_path') THEN
    RAISE EXCEPTION 'v2 consolidation: the database still sets a search_path';
  END IF;

  RAISE NOTICE 'v2 consolidation: complete; % objects archived, % relations and % functions moved into public',
    (SELECT count(*) FROM pre_v2_archive.v6_moved WHERE kind LIKE 'archived%'),
    (SELECT count(*) FROM pre_v2_archive.v6_moved WHERE kind = 'moved_rel'),
    (SELECT count(*) FROM pre_v2_archive.v6_moved WHERE kind = 'moved_fn');
END
$consolidate$;

COMMIT;
