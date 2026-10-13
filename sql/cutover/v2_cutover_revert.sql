-- Revert the v2 cutover (sql/cutover/v2_cutover.sql): point unqualified names back at public.
--
-- Mirrors the cutover in reverse: capture the seven rebound views' definitions while they read v2,
-- rename the _pre_v2 objects back, rebind the views to public (the same two DROP + CREATE,
-- restoring triggers, grants and comments), unpin the two functions, reset the database
-- search_path, strip the cutover's deprecation stamp from the comments, and revoke the v2 grants
-- the cutover added. sample.workflow, which the web application owns, is copied back. Nothing
-- else written to v2 after the cutover is copied back to public: if the
-- importer or the pipelines have written since, those writes exist only in v2 and must be
-- carried over by hand before or after running this.
--
-- New sessions pick up the reset search_path; open sessions keep v2 first until they
-- reconnect. Does not touch the ledger; afterwards:
--
--     DELETE FROM schema_migrations WHERE filename LIKE '%\_v2\_cutover.sql';

BEGIN;

DO $revert$
DECLARE
  replaced_tables text[] := ARRAY[
    'sample', 'tissue', 'dna_extraction', 'rna_extraction', 'hic_lysate',
    'illumina_library', 'pacbio_library', 'ont_library', 'hic_library',
    'rna_library_ilmn', 'rna_library_kinx', 'sequencing',
    'mitogenome_data', 'lca', 'lca_validation', 'lca_raw_results', 'blast_filtered_lca'];
  replaced_views text[] := ARRAY['summary', 'goat_species_v1', 'mitogenome_submission_view'];
  rebind_views text[] := ARRAY[
    'lca_pivot_view', 'sample_view', 'v_genome_size_comparison', 'lca_results_view',
    'filtered_lca_view', 'embargo_assignment_view', 'lca_validation_report_view'];
  rebuild_views text[] := ARRAY['embargo_assignment_view', 'lca_validation_report_view'];
  replaced text[];
  t text;
  kind text;
  c text;
  defs jsonb := '{}';
  acls jsonb := '{}';
  trigs jsonb := '{}';
  comments jsonb := '{}';
  g record;
BEGIN
  replaced := replaced_tables || replaced_views;

  IF to_regclass('public.sample_pre_v2') IS NULL THEN
    RAISE EXCEPTION 'v2 cutover revert: public.sample_pre_v2 is missing; the cutover is not applied';
  END IF;

  -- Capture while the views read v2: under search_path = v2, public the v2 names print
  -- unqualified, so the same text rebinds to public once public is first again.
  PERFORM set_config('search_path', 'v2, public', true);
  FOREACH t IN ARRAY rebind_views LOOP
    defs := defs || jsonb_build_object(t, pg_get_viewdef(('public.' || quote_ident(t))::regclass));
    acls := acls || jsonb_build_object(t,
      (SELECT coalesce(relacl::text, '') FROM pg_class WHERE oid = ('public.' || quote_ident(t))::regclass));
  END LOOP;
  FOREACH t IN ARRAY rebuild_views LOOP
    trigs := trigs || jsonb_build_object(t, (
      SELECT coalesce(jsonb_agg(pg_get_triggerdef(oid)), '[]') FROM pg_trigger
       WHERE tgrelid = ('public.' || quote_ident(t))::regclass AND NOT tgisinternal));
    comments := comments || jsonb_build_object(t,
      obj_description(('public.' || quote_ident(t))::regclass, 'pg_class'));
  END LOOP;

  -- Rename back, restoring each comment to what it was before the cutover stamped it.
  FOREACH t IN ARRAY replaced LOOP
    kind := CASE WHEN t = ANY (replaced_views) THEN 'VIEW' ELSE 'TABLE' END;
    EXECUTE format('ALTER %s public.%I RENAME TO %I', kind, t || '_pre_v2', t);
    c := regexp_replace(
      obj_description(('public.' || quote_ident(t))::regclass, 'pg_class'),
      '^DEPRECATED \S+ by the v2 cutover migration: superseded by v2\.\S+\. Kept for rollback until V\.6\. ',
      '');
    EXECUTE format('COMMENT ON %s public.%I IS %L', kind, t, nullif(c, ''));
  END LOOP;

  -- sample.workflow is web-owned and written in v2 after the cutover; carry it back, as the cutover
  -- carried it forward. Nothing else written to v2 is copied back (see the header).
  UPDATE public.sample p SET workflow = v.workflow
    FROM v2.sample v
   WHERE v.og_id = p.og_id AND v.workflow IS DISTINCT FROM p.workflow;

  -- Rebind to public.
  PERFORM set_config('search_path', 'public', true);
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

  ALTER FUNCTION public.lca_set_content_hash() RESET search_path;
  ALTER FUNCTION public.set_updated_at() RESET search_path;

  EXECUTE format('ALTER DATABASE %I RESET search_path', current_database());

  -- Revoke the v2 grants the cutover added. Before the cutover no role but the owner had any.
  FOR g IN
    SELECT pg_get_userbyid(a.grantee) AS grantee
      FROM pg_class cl, aclexplode(cl.relacl) a
     WHERE cl.relnamespace = 'v2'::regnamespace AND a.grantee <> cl.relowner AND a.grantee <> 0
    UNION   -- roles holding only column grants (the cutover mirrors oceangenom_web's UPDATE (workflow))
    SELECT pg_get_userbyid(a.grantee)
      FROM pg_attribute at JOIN pg_class cl ON cl.oid = at.attrelid, aclexplode(at.attacl) a
     WHERE cl.relnamespace = 'v2'::regnamespace AND at.attacl IS NOT NULL
       AND a.grantee <> cl.relowner AND a.grantee <> 0
  LOOP
    EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA v2 FROM %I', g.grantee);
  END LOOP;
  -- REVOKE ALL on a table also revokes its column privileges; assert it.
  IF EXISTS (SELECT 1 FROM pg_attribute at JOIN pg_class cl ON cl.oid = at.attrelid,
                    aclexplode(at.attacl) a
              WHERE cl.relnamespace = 'v2'::regnamespace AND at.attacl IS NOT NULL
                AND a.grantee <> cl.relowner AND a.grantee <> 0) THEN
    RAISE EXCEPTION 'v2 cutover revert: column grants remain on v2';
  END IF;
  FOR g IN
    SELECT pg_get_userbyid(a.grantee) AS grantee
      FROM pg_namespace n, aclexplode(n.nspacl) a
     WHERE n.nspname = 'v2' AND a.grantee <> n.nspowner AND a.grantee <> 0
  LOOP
    EXECUTE format('REVOKE USAGE ON SCHEMA v2 FROM %I', g.grantee);
  END LOOP;
  IF to_regrole('readonly') IS NOT NULL THEN
    ALTER DEFAULT PRIVILEGES IN SCHEMA v2 REVOKE SELECT ON TABLES FROM readonly;
  END IF;

  -- Same check as the cutover, the other way round: nothing may still read v2 except v2 itself.
  IF EXISTS (
    SELECT 1 FROM pg_class v
      JOIN pg_rewrite rw ON rw.ev_class = v.oid
      JOIN pg_depend d ON d.objid = rw.oid AND d.classid = 'pg_rewrite'::regclass
                      AND d.refclassid = 'pg_class'::regclass
      JOIN pg_class r ON r.oid = d.refobjid
     WHERE v.relnamespace = 'public'::regnamespace AND r.relnamespace = 'v2'::regnamespace) THEN
    RAISE EXCEPTION 'v2 cutover revert: a public view still reads v2';
  END IF;
END
$revert$;

COMMIT;
