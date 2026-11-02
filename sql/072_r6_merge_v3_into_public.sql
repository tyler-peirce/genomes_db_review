-- 072_r6_merge_v3_into_public.sql -- Phase R.6: make the v3 mitogenome and draft-genome tables
-- the schema of record, by moving them into public and the old flat tables out.
--
-- Plan: docs/r6_merge_plan.md; design docs/assembly_relations_plan.md §6.1 and R.6.
--
-- What it does, in one transaction:
--   1. final sync public -> v3 (sync_mito, sync_draft, sync_sequencing_run), then requires
--      check_mito() and check_draft() to be 0 on every check;
--   2. requires the objects it moves and drops to be exactly the ones listed below, so anything
--      added since this file was written stops it rather than being carried along unseen;
--   3. drops the old public.mitogenome_submission_view and public.v_genome_size_comparison (v3
--      has rebuilt versions under the same names) and the three LCA FKs to the old
--      mitogenome_data (R.7 re-parents those tables onto mito_annotation);
--   4. moves public.mitogenome_data and public.draft_genomes to pre_v3_archive (kept until R.8);
--   5. drops the window-only functions (sync_*, check_*);
--   6. moves every remaining v3 table, view and function into public and drops v3.
--
-- Moving keeps OIDs, so views stay bound to the tables they read, owned sequences, indexes,
-- constraints and triggers follow their tables, and grants travel with each object. The v3
-- views already carry the grants the public objects of the same name had (readonly SELECT on
-- all; oceangenom_web SELECT on mitogenome_data and draft_genomes); asserted below rather than
-- re-granted.
--
-- After this, mitogenome_data and draft_genomes are the read-only compatibility views. A writer
-- that still inserts into them fails on "cannot insert into view", which is the point: the
-- phase-r-v3 writers, which write the new tables, deploy the same day.
--
-- Opt-in, because it changes what production writers can write:
--     PGOPTIONS="-c oceanomics.r6_merge=yes" bin/apply_migrations.py
-- Replay: when v3 is gone and public.mito_assembly exists, the file does nothing.
--
-- Revert: sql/revert/072_r6_merge_v3_into_public_revert.sql.

BEGIN;

DO $r6$
DECLARE
  want_tables text[] := ARRAY[
    'draft_busco','draft_contamination','draft_depthsizer','draft_fastp','draft_genome',
    'draft_genome_run','draft_genomescope','draft_gfastats','draft_merqury','draft_submission',
    'draft_tiara','mito_annotation','mito_annotation_gene','mito_assembly','mito_assembly_depth',
    'mito_assembly_qc','mito_assembly_run','mito_gene','sequencing_run'];
  want_views text[] := ARRAY[
    'draft_genomes','mitogenome_data','mitogenome_submission_view','v_draft_genome_status',
    'v_genome_size_comparison','v_mito_annotation_genes','v_sequencing_run_fk_readiness',
    'v_sequencing_run_issues'];
  window_fns text[] := ARRAY['sync_mito','sync_draft','sync_sequencing_run','check_mito','check_draft'];
  kept_fns text[] := ARRAY['draft_genome_run_illumina_only','rebuild_mito_gene_views'];
  have text[];
  obj text;
  n bigint;
  r record;
  old_mito bigint;
  old_draft bigint;
BEGIN
  -- Replay.
  IF to_regnamespace('v3') IS NULL AND to_regclass('public.mito_assembly') IS NOT NULL THEN
    RAISE NOTICE '072: already merged (no v3, public.mito_assembly exists); nothing to do';
    RETURN;
  END IF;

  IF coalesce(current_setting('oceanomics.r6_merge', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'This merges v3 into public and turns mitogenome_data and draft_genomes into '
      'views. Run with PGOPTIONS="-c oceanomics.r6_merge=yes"';
  END IF;

  -- 1. Final sync, then the checks.
  PERFORM * FROM v3.sync_sequencing_run();
  PERFORM * FROM v3.sync_mito();
  PERFORM * FROM v3.sync_draft();
  FOR r IN SELECT 'mito' AS side, * FROM v3.check_mito()
           UNION ALL SELECT 'draft', * FROM v3.check_draft() LOOP
    IF r.problems <> 0 THEN
      RAISE EXCEPTION '072: %: % problem(s) in "%" after the final sync', r.side, r.problems, r.check_name;
    END IF;
  END LOOP;
  SELECT count(*) INTO old_mito FROM public.mitogenome_data;
  SELECT count(*) INTO old_draft FROM public.draft_genomes;

  -- 2. Exactly the expected objects.
  SELECT array_agg(relname ORDER BY relname) INTO have FROM pg_class
   WHERE relnamespace = 'v3'::regnamespace AND relkind IN ('r','p');
  IF have IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(want_tables) x) THEN
    RAISE EXCEPTION '072: v3 tables are %, expected %', have, want_tables;
  END IF;
  SELECT array_agg(relname ORDER BY relname) INTO have FROM pg_class
   WHERE relnamespace = 'v3'::regnamespace AND relkind IN ('v','m');
  IF have IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(want_views) x) THEN
    RAISE EXCEPTION '072: v3 views are %, expected %', have, want_views;
  END IF;
  SELECT array_agg(proname ORDER BY proname) INTO have FROM pg_proc
   WHERE pronamespace = 'v3'::regnamespace;
  IF have IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(window_fns || kept_fns) x) THEN
    RAISE EXCEPTION '072: v3 functions are %, expected %', have, window_fns || kept_fns;
  END IF;
  SELECT array_agg(DISTINCT dv.relname ORDER BY dv.relname) INTO have
    FROM pg_depend d JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class
   WHERE d.refobjid IN ('public.mitogenome_data'::regclass, 'public.draft_genomes'::regclass)
     AND dv.oid NOT IN ('public.mitogenome_data'::regclass, 'public.draft_genomes'::regclass);
  IF have IS DISTINCT FROM ARRAY['mitogenome_submission_view','v_genome_size_comparison'] THEN
    RAISE EXCEPTION '072: views reading the old tables are %, expected the two this file rebuilds', have;
  END IF;
  SELECT array_agg(conname::text ORDER BY conname) INTO have FROM pg_constraint
   WHERE contype = 'f' AND confrelid IN ('public.mitogenome_data'::regclass, 'public.draft_genomes'::regclass);
  IF have IS DISTINCT FROM ARRAY['lca_mitogenome_fkey','lca_raw_results_mitogenome_fkey',
                                 'lca_validation_mitogenome_fkey'] THEN
    RAISE EXCEPTION '072: FKs to the old tables are %, expected the three LCA FKs', have;
  END IF;
  -- Grants: every grantee the old public objects had, the v3 object of the same name has.
  SELECT count(*) INTO n FROM information_schema.role_table_grants o
   WHERE o.table_schema = 'public'
     AND o.table_name IN ('mitogenome_data','draft_genomes','mitogenome_submission_view','v_genome_size_comparison')
     AND o.privilege_type = 'SELECT'
     AND NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants v
                      WHERE v.table_schema = 'v3' AND v.table_name = o.table_name
                        AND v.grantee = o.grantee AND v.privilege_type = 'SELECT');
  IF n <> 0 THEN
    RAISE EXCEPTION '072: % SELECT grant(s) on the old objects are missing from their v3 replacements', n;
  END IF;

  -- 3. The old views and the LCA FKs.
  DROP VIEW public.mitogenome_submission_view;
  DROP VIEW public.v_genome_size_comparison;
  ALTER TABLE public.lca             DROP CONSTRAINT lca_mitogenome_fkey;
  ALTER TABLE public.lca_raw_results DROP CONSTRAINT lca_raw_results_mitogenome_fkey;
  ALTER TABLE public.lca_validation  DROP CONSTRAINT lca_validation_mitogenome_fkey;

  -- 4. The old tables, kept until R.8.
  ALTER TABLE public.mitogenome_data SET SCHEMA pre_v3_archive;
  ALTER TABLE public.draft_genomes   SET SCHEMA pre_v3_archive;
  COMMENT ON TABLE pre_v3_archive.mitogenome_data IS
    'The flat mitogenome table before Phase R (archived by 072, 2026-11-02). Read-only history; '
    'public.mitogenome_data is now a view over mito_assembly / mito_annotation. Dropped in R.8.';
  COMMENT ON TABLE pre_v3_archive.draft_genomes IS
    'The flat draft-genome table before Phase R (archived by 072, 2026-11-02). Read-only history; '
    'public.draft_genomes is now a view over draft_genome and the draft_* tables. Dropped in R.8.';

  -- 5. Window-only functions.
  FOR r IN SELECT p.oid::regprocedure AS fn FROM pg_proc p
            WHERE p.pronamespace = 'v3'::regnamespace AND p.proname = ANY (window_fns) LOOP
    EXECUTE format('DROP FUNCTION %s', r.fn);
  END LOOP;

  -- 6. Everything else into public.
  FOREACH obj IN ARRAY want_tables LOOP
    EXECUTE format('ALTER TABLE v3.%I SET SCHEMA public', obj);
  END LOOP;
  FOREACH obj IN ARRAY want_views LOOP
    EXECUTE format('ALTER VIEW v3.%I SET SCHEMA public', obj);
  END LOOP;
  FOR r IN SELECT p.oid::regprocedure AS fn FROM pg_proc p
            WHERE p.pronamespace = 'v3'::regnamespace AND p.proname = ANY (kept_fns) LOOP
    EXECUTE format('ALTER FUNCTION %s SET SCHEMA public', r.fn);
  END LOOP;
  -- Its body uses unqualified names; it found them through v3 first.
  ALTER FUNCTION public.rebuild_mito_gene_views() SET search_path = public, pg_temp;

  -- Sequences not owned by a moved table would be left behind; there should be none.
  SELECT count(*) INTO n FROM pg_class WHERE relnamespace = 'v3'::regnamespace;
  IF n <> 0 THEN
    RAISE EXCEPTION '072: % relation(s) still in v3 after the move: %', n,
      (SELECT string_agg(relname, ', ') FROM pg_class WHERE relnamespace = 'v3'::regnamespace);
  END IF;
  DROP SCHEMA v3 RESTRICT;

  -- Verify.
  SELECT count(*) INTO n
    FROM pg_depend d JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class
    JOIN pg_class t ON t.oid = d.refobjid
   WHERE dv.relnamespace = 'public'::regnamespace AND t.relnamespace = 'pre_v3_archive'::regnamespace;
  IF n <> 0 THEN
    RAISE EXCEPTION '072: % public view dependency still points into pre_v3_archive', n;
  END IF;
  IF (SELECT count(*) FROM public.mitogenome_data) <> old_mito THEN
    RAISE EXCEPTION '072: public.mitogenome_data has % rows, the old table had %',
      (SELECT count(*) FROM public.mitogenome_data), old_mito;
  END IF;
  IF (SELECT count(*) FROM public.draft_genomes) <> old_draft THEN
    RAISE EXCEPTION '072: public.draft_genomes has % rows, the old table had %',
      (SELECT count(*) FROM public.draft_genomes), old_draft;
  END IF;
  IF (SELECT relkind FROM pg_class WHERE oid = 'public.mitogenome_data'::regclass) <> 'v'
     OR (SELECT relkind FROM pg_class WHERE oid = 'public.draft_genomes'::regclass) <> 'v' THEN
    RAISE EXCEPTION '072: mitogenome_data and draft_genomes should now be views';
  END IF;
  -- An old writer must fail loudly. The sub-block rolls back whatever it did.
  BEGIN
    INSERT INTO public.draft_genomes (og_id, seq_date) VALUES ('OG_072_PROBE', '000000');
    RAISE EXCEPTION USING ERRCODE = 'P0072', MESSAGE = 'insert into draft_genomes succeeded';
  EXCEPTION
    WHEN SQLSTATE 'P0072' THEN
      RAISE EXCEPTION '072: an insert into the draft_genomes view succeeded; old writers would not fail';
    WHEN OTHERS THEN
      NULL;  -- "cannot insert into view" or similar: what an old writer will now see
  END;

  RAISE NOTICE '072: merged. mitogenome_data % rows, draft_genomes % rows; v3 dropped', old_mito, old_draft;
END
$r6$;

COMMIT;
