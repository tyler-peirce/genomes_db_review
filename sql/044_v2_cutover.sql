-- 044_v2_cutover.sql -- Phase V.5: make v2 the schema unqualified names resolve to, and make
-- the superseded public objects fail loudly instead of serving stale data.
--
-- Run after 043_v2_mitogenome_submission_view.sql, during a quiet window, after the pre-flight
-- in docs/phase_v5_plan.md. This is the cutover. Read that plan before applying it.
--
-- What it does, in order, in one transaction:
--
--   1. Refuses to run unless v2 is complete and the five pipeline-fed tables match public.
--      scripts/backfill_v2.sql is insert-only (ON CONFLICT DO NOTHING) and the mitogenome /
--      LCA pipelines write public, so a pipeline overwrite made after the backfill exists only
--      in public. Cutting over then would lose it silently. The lab tables are not checked
--      here: they legitimately differ by the open quarantine, and scripts/reconcile_v2.py is
--      the check for them (zero UNEXPLAINED), run in the pre-flight.
--   2. Captures the definitions of the seven views that read replaced tables and survive,
--      under search_path = public, so they print with unqualified names.
--   3. Mirrors every grant on the twenty replaced objects onto their v2 counterparts, grants
--      USAGE on schema v2, and gives readonly SELECT on all of v2, now and by default, as it
--      has on public. Without this every readonly and oceangenom_web query fails with
--      "permission denied for schema v2" the moment the search_path moves.
--   4. Renames the twenty replaced objects -- the seventeen tables and public's summary,
--      goat_species_v1 and mitogenome_submission_view -- to <name>_pre_v2. A query naming
--      public.sample then fails with "relation does not exist": immediate, unambiguous, and,
--      unlike a DROP, reversible. REVOKE cannot do this job: everyone connects as postgres,
--      and superusers bypass permissions (database_review.md, V.5).
--   5. Rebinds the seven views to v2 by re-executing their definitions under
--      search_path = v2, public. A view binds to table OIDs, not names, so without this all
--      seven would follow the rename and keep serving pre-cutover data under their own names
--      -- Finding 11 again, by construction.
--      Five take CREATE OR REPLACE, which keeps grants and dependants. Two cannot:
--      embargo_assignment_view and lca_validation_report_view expose varchar columns that are
--      text in v2 (F8), and CREATE OR REPLACE refuses to change a column's type. Found in
--      the 2026-10-13 rehearsal; the earlier plan assumed it could not happen. Those two are
--      dropped and recreated, and their grants, comments and INSTEAD OF UPDATE triggers are
--      captured first and restored -- the triggers are the write paths, and losing them
--      silently is exactly why the plan preferred CREATE OR REPLACE. Neither view has a
--      dependant, so the DROP needs no CASCADE; if one appears, the DROP fails loudly.
--   6. Pins public.lca_set_content_hash() and public.set_updated_at() to search_path = public
--      (dispositions in scripts/audit_v2_dependents.py). Their triggers stay on the _pre_v2
--      tables and must not resolve column names against v2.
--   7. Sets search_path = v2, public at the DATABASE level, not per role, so a role nobody
--      remembered still resolves correctly. No role overrides it today (pg_db_role_setting
--      holds only oceangenom_web's statement_timeout). It applies to NEW sessions: an open
--      DBeaver session keeps its old path, finds no public.sample, and fails loudly until it
--      reconnects.
--   8. Verifies, before COMMIT: nothing outside the _pre_v2 and SS260818 objects still reads
--      a _pre_v2 relation; the seven views read v2; both triggers and all captured grants are
--      back; readonly can use v2.
--
-- Not done here: nothing is dropped and nothing moves schema. That is V.6, after a quiet
-- period. The _pre_v2 objects keep their data and indexes; V.6 must drop them before moving v2
-- objects into public, because their index and constraint names (sample_pkey, ...) collide.
--
-- Replay: a single DO block that returns at once if the cutover is already in place
-- (public.sample gone and public.sample_pre_v2 present), so the crash-recovery replay in
-- bin/apply_migrations.py is a no-op. It is not idempotent in any other sense, and must not
-- be: a half-applied state cannot arise, because everything is one transaction.
--
-- Opt-in: refuses to run unless PGOPTIONS="-c oceanomics.v2_cutover=go" is set, so an
-- unrelated bin/apply_migrations.py run cannot cut over by accident.
--
-- Rollback: sql/revert/044_v2_cutover_revert.sql. Instant: renames, rebinding and grants only.

BEGIN;

DO $cutover$
DECLARE
  replaced_tables text[] := ARRAY[
    'sample', 'tissue', 'dna_extraction', 'rna_extraction', 'hic_lysate',
    'illumina_library', 'pacbio_library', 'ont_library', 'hic_library',
    'rna_library_ilmn', 'rna_library_kinx', 'sequencing',
    'mitogenome_data', 'lca', 'lca_validation', 'lca_raw_results', 'blast_filtered_lca'];
  replaced_views text[] := ARRAY['summary', 'goat_species_v1', 'mitogenome_submission_view'];
  pipeline_tables text[] := ARRAY[
    'mitogenome_data', 'lca', 'lca_raw_results', 'lca_validation', 'blast_filtered_lca'];
  -- Dependency order: a view is rebound after the views it reads.
  rebind_views text[] := ARRAY[
    'lca_pivot_view', 'sample_view', 'v_genome_size_comparison', 'lca_results_view',
    'filtered_lca_view', 'embargo_assignment_view', 'lca_validation_report_view'];
  rebuild_views text[] := ARRAY['embargo_assignment_view', 'lca_validation_report_view'];
  replaced text[];
  t text;
  cols text;
  n bigint;
  defs jsonb := '{}';
  acls jsonb := '{}';
  trigs jsonb := '{}';
  comments jsonb := '{}';
  g record;
  stamp text := 'DEPRECATED ' || current_date || ' by migration 044 (v2 cutover): superseded by v2.';
BEGIN
  replaced := replaced_tables || replaced_views;

  -- Replay guard.
  IF to_regclass('public.sample') IS NULL AND to_regclass('public.sample_pre_v2') IS NOT NULL THEN
    RAISE NOTICE '044: cutover already in place, nothing to do';
    RETURN;
  END IF;

  -- Opt-in guard. Committed to sql/ ahead of the window, this file is pending for anyone who
  -- runs bin/apply_migrations.py, so it refuses unless the operator asks for it by name.
  -- PGOPTIONS reaches psql through the runner's environment.
  IF coalesce(current_setting('oceanomics.v2_cutover', true), '') <> 'go' THEN
    RAISE EXCEPTION '044 is the v2 cutover and runs only on purpose. Follow docs/phase_v5_plan.md, '
      'then: PGOPTIONS="-c oceanomics.v2_cutover=go" bin/apply_migrations.py --target 044';
  END IF;

  -- -------------------------------------------------------------------------------------
  -- 1. Preconditions
  -- -------------------------------------------------------------------------------------
  FOREACH t IN ARRAY replaced LOOP
    IF to_regclass('public.' || quote_ident(t)) IS NULL THEN
      RAISE EXCEPTION '044: public.% is missing; the cutover expects every replaced object in place', t;
    END IF;
    IF to_regclass('public.' || quote_ident(t || '_pre_v2')) IS NOT NULL THEN
      RAISE EXCEPTION '044: public.%_pre_v2 already exists', t;
    END IF;
    IF to_regclass('v2.' || quote_ident(t)) IS NULL THEN
      RAISE EXCEPTION '044: v2.% is missing; apply 035-043 first', t;
    END IF;
  END LOOP;
  FOREACH t IN ARRAY rebind_views LOOP
    IF to_regclass('public.' || quote_ident(t)) IS NULL THEN
      RAISE EXCEPTION '044: dependent view public.% is missing', t;
    END IF;
  END LOOP;

  -- The five pipeline-fed tables must match on every shared column. og_num is dropped in v2
  -- (F2) and content_hash covers og_num, so neither is comparable; both sides cast to text,
  -- because v2 changed varchar to text (F8) and lca_raw_results.lca_run_date from integer.
  FOREACH t IN ARRAY pipeline_tables LOOP
    SELECT string_agg(format('%I::text', a.column_name), ', ' ORDER BY a.column_name) INTO cols
      FROM information_schema.columns a
      JOIN information_schema.columns b
        ON b.table_schema = 'v2' AND b.table_name = a.table_name AND b.column_name = a.column_name
     WHERE a.table_schema = 'public' AND a.table_name = t
       AND a.column_name NOT IN ('og_num', 'content_hash');
    EXECUTE format(
      'SELECT count(*) FROM ((SELECT %1$s FROM public.%2$I EXCEPT ALL SELECT %1$s FROM v2.%2$I)'
      ' UNION ALL (SELECT %1$s FROM v2.%2$I EXCEPT ALL SELECT %1$s FROM public.%2$I)) d', cols, t)
      INTO n;
    IF n > 0 THEN
      RAISE EXCEPTION '044: v2.% differs from public.% in % rows. The backfill is insert-only, so '
        'pipeline writes since it ran are missing from v2. Re-sync before cutting over.', t, t, n;
    END IF;
  END LOOP;

  -- -------------------------------------------------------------------------------------
  -- 2. Capture the seven definitions, unqualified, and what a DROP would lose
  -- -------------------------------------------------------------------------------------
  PERFORM set_config('search_path', 'public', true);
  FOREACH t IN ARRAY rebind_views LOOP
    defs := defs || jsonb_build_object(t, pg_get_viewdef(('public.' || quote_ident(t))::regclass));
    IF defs->>t ~* '\mv2\.' THEN
      RAISE EXCEPTION '044: public.% already names v2 explicitly; review it by hand', t;
    END IF;
    acls := acls || jsonb_build_object(t,
      (SELECT coalesce(relacl::text, '') FROM pg_class WHERE oid = ('public.' || quote_ident(t))::regclass));
  END LOOP;
  FOREACH t IN ARRAY rebuild_views LOOP
    trigs := trigs || jsonb_build_object(t, (
      SELECT coalesce(jsonb_agg(pg_get_triggerdef(oid)), '[]') FROM pg_trigger
       WHERE tgrelid = ('public.' || quote_ident(t))::regclass AND NOT tgisinternal));
    comments := comments || jsonb_build_object(t,
      obj_description(('public.' || quote_ident(t))::regclass, 'pg_class'));
    IF EXISTS (SELECT 1 FROM pg_description
                WHERE objoid = ('public.' || quote_ident(t))::regclass AND objsubid > 0) THEN
      RAISE EXCEPTION '044: public.% has column comments, which this migration does not restore', t;
    END IF;
  END LOOP;

  -- -------------------------------------------------------------------------------------
  -- 3. Grants on v2
  -- -------------------------------------------------------------------------------------
  -- Mirror each non-owner grant on a replaced object onto its v2 counterpart.
  FOREACH t IN ARRAY replaced LOOP
    FOR g IN
      SELECT pg_get_userbyid(a.grantee) AS grantee, string_agg(a.privilege_type, ', ') AS privs
        FROM pg_class c, aclexplode(c.relacl) a
       WHERE c.oid = ('public.' || quote_ident(t))::regclass
         AND a.grantee <> c.relowner AND a.grantee <> 0
       GROUP BY a.grantee
    LOOP
      EXECUTE format('GRANT %s ON v2.%I TO %I', g.privs, t, g.grantee);
    END LOOP;
  END LOOP;
  -- Column-level grants live in pg_attribute.attacl, not in the table's relacl, so the loop
  -- above does not see them. The web application depends on one: oceangenom_web holds
  -- UPDATE (workflow) ON sample and nothing else writable on it, which is how its Assign
  -- button sets a sample's workflow. Missed in the first rehearsal, which ran without the
  -- role's column grants. A grant on a column v2 removed has nowhere to go: refuse rather
  -- than drop a privilege silently.
  FOREACH t IN ARRAY replaced_tables LOOP
    FOR g IN
      SELECT pg_get_userbyid(a.grantee) AS grantee, at.attname::text AS col,
             string_agg(a.privilege_type, ', ') AS privs
        FROM pg_attribute at
        JOIN pg_class c ON c.oid = at.attrelid,
             aclexplode(at.attacl) a
       WHERE at.attrelid = ('public.' || quote_ident(t))::regclass
         AND at.attacl IS NOT NULL AND NOT at.attisdropped
         AND a.grantee <> 0 AND a.grantee <> c.relowner
       GROUP BY a.grantee, at.attname
    LOOP
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'v2' AND table_name = t AND column_name = g.col) THEN
        RAISE EXCEPTION '044: % holds % on public.%.%, which v2 removes; decide what replaces it first',
          g.grantee, g.privs, t, g.col;
      END IF;
      EXECUTE format('GRANT %s (%I) ON v2.%I TO %I', g.privs, g.col, t, g.grantee);
    END LOOP;
  END LOOP;
  -- Schema access for every role that has it on public, and readonly's blanket SELECT.
  FOR g IN
    SELECT pg_get_userbyid(a.grantee) AS grantee
      FROM pg_namespace n, aclexplode(n.nspacl) a
     WHERE n.nspname = 'public' AND a.privilege_type = 'USAGE'
       AND a.grantee <> 0 AND a.grantee <> n.nspowner
  LOOP
    EXECUTE format('GRANT USAGE ON SCHEMA v2 TO %I', g.grantee);
  END LOOP;
  IF to_regrole('readonly') IS NOT NULL THEN
    GRANT USAGE ON SCHEMA v2 TO readonly;
    GRANT SELECT ON ALL TABLES IN SCHEMA v2 TO readonly;
    ALTER DEFAULT PRIVILEGES IN SCHEMA v2 GRANT SELECT ON TABLES TO readonly;
  END IF;

  -- -------------------------------------------------------------------------------------
  -- 4. Rename the replaced objects
  -- -------------------------------------------------------------------------------------
  FOREACH t IN ARRAY replaced LOOP
    EXECUTE format('ALTER %s public.%I RENAME TO %I',
      CASE WHEN t = ANY (replaced_views) THEN 'VIEW' ELSE 'TABLE' END, t, t || '_pre_v2');
    EXECUTE format('COMMENT ON %s public.%I IS %L',
      CASE WHEN t = ANY (replaced_views) THEN 'VIEW' ELSE 'TABLE' END, t || '_pre_v2',
      stamp || t || '. Kept for rollback until V.6. '
        || coalesce(obj_description(('public.' || quote_ident(t || '_pre_v2'))::regclass, 'pg_class'), ''));
  END LOOP;

  -- -------------------------------------------------------------------------------------
  -- 5. Rebind the seven views to v2
  -- -------------------------------------------------------------------------------------
  PERFORM set_config('search_path', 'v2, public', true);
  FOREACH t IN ARRAY rebind_views LOOP
    IF t = ANY (rebuild_views) THEN
      EXECUTE format('DROP VIEW public.%I', t);
      EXECUTE format('CREATE VIEW public.%I AS %s', t, defs->>t);
      FOR g IN SELECT jsonb_array_elements_text(trigs->t) AS def LOOP
        EXECUTE g.def;
      END LOOP;
      IF comments->>t IS NOT NULL THEN
        EXECUTE format('COMMENT ON VIEW public.%I IS %L', t, comments->>t);
      END IF;
      FOR g IN
        SELECT pg_get_userbyid(a.grantee) AS grantee, string_agg(a.privilege_type, ', ') AS privs
          FROM aclexplode(nullif(acls->>t, '')::aclitem[]) a
         WHERE a.grantee <> (SELECT relowner FROM pg_class WHERE oid = ('public.' || quote_ident(t))::regclass)
           AND a.grantee <> 0
         GROUP BY a.grantee
      LOOP
        EXECUTE format('GRANT %s ON public.%I TO %I', g.privs, t, g.grantee);
      END LOOP;
    ELSE
      EXECUTE format('CREATE OR REPLACE VIEW public.%I AS %s', t, defs->>t);
    END IF;
  END LOOP;

  -- -------------------------------------------------------------------------------------
  -- 6. Pin the two functions that must not follow the swap
  -- -------------------------------------------------------------------------------------
  ALTER FUNCTION public.lca_set_content_hash() SET search_path = public;
  ALTER FUNCTION public.set_updated_at() SET search_path = public;

  -- -------------------------------------------------------------------------------------
  -- 7. Database search_path
  -- -------------------------------------------------------------------------------------
  EXECUTE format('ALTER DATABASE %I SET search_path = v2, public', current_database());

  -- -------------------------------------------------------------------------------------
  -- 8. Verification
  -- -------------------------------------------------------------------------------------
  -- Nothing live may still read a _pre_v2 relation. The SS260818 snapshot views are exempt:
  -- they are frozen by design and go in Phase F.
  SELECT count(*), string_agg(DISTINCT v.relname || ' -> ' || r.relname, ', ') INTO n, cols
    FROM pg_class v
    JOIN pg_rewrite rw ON rw.ev_class = v.oid
    JOIN pg_depend d ON d.objid = rw.oid AND d.classid = 'pg_rewrite'::regclass
                    AND d.refclassid = 'pg_class'::regclass
    JOIN pg_class r ON r.oid = d.refobjid AND r.oid <> v.oid
   WHERE r.relname LIKE '%\_pre\_v2' AND r.relnamespace = 'public'::regnamespace
     AND v.relname NOT LIKE '%\_pre\_v2' AND v.relname NOT LIKE '%SS260818%';
  IF n > 0 THEN
    RAISE EXCEPTION '044: still reading superseded objects: %', cols;
  END IF;

  FOREACH t IN ARRAY rebind_views LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_rewrite rw
        JOIN pg_depend d ON d.objid = rw.oid AND d.classid = 'pg_rewrite'::regclass
                        AND d.refclassid = 'pg_class'::regclass
        JOIN pg_class r ON r.oid = d.refobjid
       WHERE rw.ev_class = ('public.' || quote_ident(t))::regclass
         AND r.relnamespace = 'v2'::regnamespace) THEN
      RAISE EXCEPTION '044: public.% does not read anything in v2 after rebinding', t;
    END IF;
    IF (SELECT coalesce(relacl::text, '') FROM pg_class
         WHERE oid = ('public.' || quote_ident(t))::regclass) <> acls->>t THEN
      RAISE EXCEPTION '044: grants on public.% changed: % -> %', t, acls->>t,
        (SELECT relacl::text FROM pg_class WHERE oid = ('public.' || quote_ident(t))::regclass);
    END IF;
  END LOOP;

  FOREACH t IN ARRAY rebuild_views LOOP
    IF (SELECT count(*) FROM pg_trigger
         WHERE tgrelid = ('public.' || quote_ident(t))::regclass AND NOT tgisinternal)
       <> jsonb_array_length(trigs->t) THEN
      RAISE EXCEPTION '044: public.% lost a trigger in the rebuild', t;
    END IF;
  END LOOP;

  -- Every column grant on a renamed table must hold on its v2 column.
  FOR g IN
    SELECT pg_get_userbyid(a.grantee) AS grantee, c.relname AS tbl, at.attname::text AS col,
           a.privilege_type AS priv
      FROM pg_attribute at
      JOIN pg_class c ON c.oid = at.attrelid,
           aclexplode(at.attacl) a
     WHERE c.relnamespace = 'public'::regnamespace AND c.relname LIKE '%\_pre\_v2'
       AND at.attacl IS NOT NULL AND a.grantee <> 0 AND a.grantee <> c.relowner
  LOOP
    IF NOT has_column_privilege(g.grantee, 'v2.' || quote_ident(regexp_replace(g.tbl, '_pre_v2$', '')),
                                g.col, g.priv) THEN
      RAISE EXCEPTION '044: % lost % on %.% in v2', g.grantee, g.priv, g.tbl, g.col;
    END IF;
  END LOOP;

  IF to_regrole('readonly') IS NOT NULL AND NOT (
       has_schema_privilege('readonly', 'v2', 'USAGE')
       AND has_table_privilege('readonly', 'v2.sample', 'SELECT')
       AND has_table_privilege('readonly', 'v2.summary', 'SELECT')) THEN
    RAISE EXCEPTION '044: readonly cannot read v2';
  END IF;

  RAISE NOTICE '044: cutover complete; % objects renamed to _pre_v2, % views rebound',
    array_length(replaced, 1), array_length(rebind_views, 1);
END
$cutover$;

COMMIT;
