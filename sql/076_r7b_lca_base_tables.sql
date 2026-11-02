-- 076_r7b_lca_base_tables.sql -- Phase R.7b: store the four LCA tables by annotation_id only, behind
-- compatibility views under the old names.
--
-- Plan: docs/r7b_plan.md. Follows 074 (R.7), which gave these tables a validated annotation_id
-- and a trigger holding the natural columns (og_id, tech, seq_date, code, annotation) equal to it.
-- Those columns are therefore redundant; this removes them.
--
--   lca                -> mito_lca             PK (annotation_id, region, content_hash)
--   lca_raw_results    -> mito_lca_raw         PK (annotation_id, sequence_region, accession_id, content_hash)
--   lca_validation     -> mito_lca_validation  PK (annotation_id)
--   blast_filtered_lca -> mito_blast_hit       PK (annotation_id, match_sequence_id, region)
--
-- Each base table drops the five natural columns, the FK to sample (redundant through the
-- annotation) and 074's annotation_id trigger (it read those columns), and keeps its annotation_id
-- FK to mito_annotation. A view under the old name joins mito_annotation and mito_assembly back in
-- and shows exactly the old column list in the old order, so every reader -- ENA-draft-genomes
-- steps 00/06, ENA-ref-genomes step 00, OceanGenom_Web through summary, and the ten views below --
-- sees what it saw. The views are read-only; the mito pipeline's writers now write the base tables
-- (mito branch r7b-lca-base-tables, deployed the same day), using mito_annotation_id() to resolve
-- the key.
--
-- content_hash: lca_set_content_hash() hashes the whole row minus a few columns, so dropping the
-- natural columns changes every hash. They are recomputed here, by the trigger, and the old->new
-- map is kept in pre_v3_archive.*_hash_map_076. Measured 2026-11-02: every stored hash equalled a
-- fresh computation and no recomputed key collides.
--
-- The ten dependent views (from pg_depend, recursive) are dropped and recreated from their own
-- definitions, unchanged in text: they name lca_validation etc., which now resolve to the
-- compatibility views. Comments, grants and the 033 INSTEAD OF UPDATE trigger are restored, and
-- lca_validation_report_view_upd() now updates mito_lca_validation by annotation_id.
--
-- Opt-in:  PGOPTIONS="-c oceanomics.r7b_lca=yes" bin/apply_migrations.py
-- Replay: when mito_lca_validation exists and lca_validation is a view, the file does nothing.
-- Revert: sql/revert/076_r7b_lca_base_tables_revert.sql.

BEGIN;

-- The key lookup every writer uses. Strict (the default) raises the same message as 074's trigger;
-- non-strict returns NULL, for UPDATE/DELETE/SELECT where "no such annotation" means "no row".
CREATE OR REPLACE FUNCTION public.mito_annotation_id(p_og_id text, p_tech text, p_seq_date text,
                                                     p_code text, p_annotation text,
                                                     p_strict boolean DEFAULT true)
RETURNS bigint LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $fn$
DECLARE
  found bigint;
  n int;
BEGIN
  SELECT min(an.annotation_id), count(*) INTO found, n
    FROM mito_annotation an JOIN mito_assembly a USING (assembly_id)
   WHERE a.og_id = p_og_id AND a.tech = p_tech AND a.seq_date = p_seq_date
     AND a.code = p_code AND an.annotation = p_annotation;
  IF n = 1 THEN
    RETURN found;
  END IF;
  IF p_strict THEN
    RAISE EXCEPTION USING ERRCODE = 'foreign_key_violation',
      MESSAGE = format('%s mito annotation(s) match %s.%s.%s.%s annotation %s; upload the assembly '
                       'and its annotation before its LCA/ENA results',
                       n, p_og_id, p_tech, p_seq_date, p_code, p_annotation);
  END IF;
  RETURN NULL;
END
$fn$;
COMMENT ON FUNCTION public.mito_annotation_id(text, text, text, text, text, boolean) IS
  'annotation_id for (og_id, tech, seq_date, code, annotation). Strict (default) raises when none or '
  'several match; non-strict returns NULL. Used by the mito pipeline writers of mito_lca, '
  'mito_lca_raw, mito_lca_validation and mito_blast_hit. 076, Phase R.7b.';

DO $r7b$
DECLARE
  tabs text[][] := ARRAY[
    ['lca',                'mito_lca',            'annotation_id, region, content_hash'],
    ['lca_raw_results',    'mito_lca_raw',        'annotation_id, sequence_region, accession_id, content_hash'],
    ['lca_validation',     'mito_lca_validation', 'annotation_id'],
    ['blast_filtered_lca', 'mito_blast_hit',      'annotation_id, match_sequence_id, region']];
  nat_cols text[] := ARRAY['og_id','tech','seq_date','code','annotation'];
  want_views text[] := ARRAY[
    'public.embargo_assignment_view','public.filtered_lca_view','public.goat_species_v1',
    'public.lca_pivot_view','public.lca_results_view','public.lca_validation_report_view',
    'public.mitogenome_submission_view','public.sample_view','public.summary',
    'pre_v4_archive.goat_species_v1'];
  i int;
  old text; base text; pk text;
  have text[];
  n bigint;
  sel text;
  r record;
  hashmap text;
BEGIN
  -- Replay.
  IF to_regclass('public.mito_lca_validation') IS NOT NULL
     AND (SELECT relkind FROM pg_class WHERE oid = 'public.lca_validation'::regclass) = 'v' THEN
    RAISE NOTICE '076: already applied; nothing to do';
    RETURN;
  END IF;
  IF coalesce(current_setting('oceanomics.r7b_lca', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'This moves lca, lca_raw_results, lca_validation and blast_filtered_lca to '
      'annotation_id-keyed base tables behind read-only views; writers must use the base tables '
      'afterwards. Run with PGOPTIONS="-c oceanomics.r7b_lca=yes"';
  END IF;

  -- Guards: natural columns agree with annotation_id everywhere (074's trigger makes it so).
  FOR i IN 1..array_length(tabs, 1) LOOP
    EXECUTE format(
      'SELECT count(*) FROM %I c JOIN mito_annotation an USING (annotation_id) '
      'JOIN mito_assembly a ON a.assembly_id = an.assembly_id '
      'WHERE (a.og_id, a.tech, a.seq_date, a.code, an.annotation) '
      '  IS DISTINCT FROM (c.og_id, c.tech, c.seq_date, c.code, c.annotation)', tabs[i][1]) INTO n;
    IF n <> 0 THEN
      RAISE EXCEPTION '076: % % row(s) whose natural columns disagree with annotation_id', n, tabs[i][1];
    END IF;
  END LOOP;

  -- The views that read these tables, directly or through each other.
  CREATE TEMP TABLE r7b_views ON COMMIT DROP AS
  WITH RECURSIVE dep(oid, lvl) AS (
    SELECT DISTINCT rw.ev_class, 1 FROM pg_depend d JOIN pg_rewrite rw ON rw.oid = d.objid
     WHERE d.refobjid IN ('public.lca'::regclass, 'public.lca_raw_results'::regclass,
                          'public.lca_validation'::regclass, 'public.blast_filtered_lca'::regclass)
    UNION
    SELECT DISTINCT rw.ev_class, dep.lvl + 1 FROM dep JOIN pg_depend d ON d.refobjid = dep.oid
      JOIN pg_rewrite rw ON rw.oid = d.objid WHERE rw.ev_class <> dep.oid AND dep.lvl < 10)
  SELECT dep.oid, max(lvl) AS lvl, n.nspname AS sch, c.relname AS name,
         pg_get_viewdef(dep.oid) AS def, obj_description(dep.oid, 'pg_class') AS cmt,
         (SELECT count(*) FROM pg_class WHERE false) AS rows_before
    FROM dep JOIN pg_class c ON c.oid = dep.oid JOIN pg_namespace n ON n.oid = c.relnamespace
   GROUP BY dep.oid, n.nspname, c.relname;
  SELECT array_agg(sch || '.' || name ORDER BY sch || '.' || name) INTO have FROM r7b_views;
  IF have IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(want_views) x) THEN
    RAISE EXCEPTION '076: dependent views are %, expected %', have, want_views;
  END IF;
  FOR r IN SELECT * FROM r7b_views LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I', r.sch, r.name) INTO n;
    UPDATE r7b_views SET rows_before = n WHERE oid = r.oid;
  END LOOP;
  CREATE TEMP TABLE r7b_view_cols ON COMMIT DROP AS
  SELECT n.nspname AS sch, c.relname AS name, a.attnum, a.attname, format_type(a.atttypid, a.atttypmod) AS typ,
         col_description(c.oid, a.attnum) AS cmt
    FROM r7b_views v JOIN pg_class c ON c.oid = v.oid JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped;
  CREATE TEMP TABLE r7b_view_grants ON COMMIT DROP AS
  SELECT g.table_schema AS sch, g.table_name AS name, g.grantee, g.privilege_type
    FROM information_schema.role_table_grants g JOIN r7b_views v ON v.sch = g.table_schema AND v.name = g.table_name
   WHERE g.grantee <> 'postgres';
  CREATE TEMP TABLE r7b_view_triggers ON COMMIT DROP AS
  SELECT pg_get_triggerdef(t.oid) AS def FROM pg_trigger t JOIN r7b_views v ON v.oid = t.tgrelid
   WHERE NOT t.tgisinternal;

  -- The old tables' column lists, row counts, grants and a content fingerprint.
  CREATE TEMP TABLE r7b_cols ON COMMIT DROP AS
  SELECT c.relname AS tbl, a.attnum, row_number() OVER (PARTITION BY c.relname ORDER BY a.attnum) AS pos,
         a.attname, format_type(a.atttypid, a.atttypmod) AS typ
    FROM pg_class c JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
   WHERE c.oid IN ('public.lca'::regclass, 'public.lca_raw_results'::regclass,
                   'public.lca_validation'::regclass, 'public.blast_filtered_lca'::regclass);
  CREATE TEMP TABLE r7b_tbl (tbl text, n bigint, fp text, compat_fp text) ON COMMIT DROP;
  CREATE TEMP TABLE r7b_tbl_grants ON COMMIT DROP AS
  SELECT g.table_name AS tbl, g.grantee, g.privilege_type FROM information_schema.role_table_grants g
   WHERE g.table_schema = 'public' AND g.grantee <> 'postgres'
     AND g.table_name IN ('lca','lca_raw_results','lca_validation','blast_filtered_lca');
  FOR i IN 1..array_length(tabs, 1) LOOP
    old := tabs[i][1];
    -- fp: everything but the natural columns and the hash (which changes); compat_fp: the whole
    -- row as readers see it, hash aside.
    EXECUTE format(
      'INSERT INTO r7b_tbl SELECT %L, count(*), '
      'md5(string_agg((to_jsonb(t) - %5$L::text[] - ''content_hash'')::text, '','' ORDER BY (to_jsonb(t) - %5$L::text[] - ''content_hash'')::text)), '
      'md5(string_agg((to_jsonb(t) - ''content_hash'')::text, '','' ORDER BY (to_jsonb(t) - ''content_hash'')::text)) FROM %2$I t',
      old, old, NULL, NULL, nat_cols);
  END LOOP;

  -- Drop the dependent views (the set is checked above, so CASCADE reaches nothing else).
  EXECUTE (SELECT 'DROP VIEW ' || string_agg(format('%I.%I', sch, name), ', ') || ' CASCADE' FROM r7b_views);

  -- Hash maps, before the hashes change.
  CREATE TABLE pre_v3_archive.lca_hash_map_076 AS
  SELECT annotation_id, region, content_hash AS old_hash,
         md5((to_jsonb(l) - 'lca_run_date' - 'og_num' - 'content_hash' - 'annotation_id'
              - 'og_id' - 'tech' - 'seq_date' - 'code' - 'annotation')::text) AS new_hash
    FROM lca l;
  CREATE TABLE pre_v3_archive.lca_raw_results_hash_map_076 AS
  SELECT annotation_id, sequence_region, accession_id, content_hash AS old_hash,
         md5((to_jsonb(l) - 'lca_run_date' - 'og_num' - 'content_hash' - 'annotation_id'
              - 'og_id' - 'tech' - 'seq_date' - 'code' - 'annotation')::text) AS new_hash
    FROM lca_raw_results l;
  COMMENT ON TABLE pre_v3_archive.lca_hash_map_076 IS
    'content_hash of every lca row before 076 (old, with the natural columns) and after (new). 2026-11-02.';
  COMMENT ON TABLE pre_v3_archive.lca_raw_results_hash_map_076 IS
    'content_hash of every lca_raw_results row before 076 (old) and after (new). 2026-11-02.';

  -- The base tables.
  FOR i IN 1..array_length(tabs, 1) LOOP
    old := tabs[i][1]; base := tabs[i][2]; pk := tabs[i][3];
    EXECUTE format('ALTER TABLE public.%I RENAME TO %I', old, base);
    EXECUTE format('DROP TRIGGER %I ON public.%I', old || '_annotation_id', base);
    EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', base, old || '_og_id_fkey');
    EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', base, old || '_pkey');
    EXECUTE format('ALTER TABLE public.%I DROP COLUMN og_id, DROP COLUMN tech, DROP COLUMN seq_date, '
                   'DROP COLUMN code, DROP COLUMN annotation', base);
    IF old IN ('lca', 'lca_raw_results') THEN
      -- The BEFORE UPDATE trigger recomputes content_hash from the row as it now is.
      EXECUTE format('UPDATE public.%I SET content_hash = content_hash', base);
    END IF;
    EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I PRIMARY KEY (%s)', base, base || '_pkey', pk);
    -- Rename what still carries the old table name.
    FOR r IN SELECT conname FROM pg_constraint WHERE conrelid = format('public.%I', base)::regclass
               AND conname LIKE old || '\_%' LOOP
      EXECUTE format('ALTER TABLE public.%I RENAME CONSTRAINT %I TO %I', base, r.conname,
                     base || substr(r.conname, length(old) + 1));
    END LOOP;
    FOR r IN SELECT c.relname FROM pg_index x JOIN pg_class c ON c.oid = x.indexrelid
              WHERE x.indrelid = format('public.%I', base)::regclass AND c.relname LIKE old || '\_%' LOOP
      EXECUTE format('ALTER INDEX public.%I RENAME TO %I', r.relname, base || substr(r.relname, length(old) + 1));
    END LOOP;
    FOR r IN SELECT tgname FROM pg_trigger WHERE tgrelid = format('public.%I', base)::regclass
               AND NOT tgisinternal AND tgname LIKE old || '\_%' LOOP
      EXECUTE format('ALTER TRIGGER %I ON public.%I RENAME TO %I', r.tgname, base,
                     base || substr(r.tgname, length(old) + 1));
    END LOOP;
    EXECUTE format('COMMENT ON COLUMN public.%I.annotation_id IS %L', base,
      'The mito_annotation this row describes. Writers resolve it with mito_annotation_id(). 076, Phase R.7b.');
  END LOOP;

  -- Recomputed hashes match the maps.
  IF EXISTS (SELECT 1 FROM mito_lca l LEFT JOIN pre_v3_archive.lca_hash_map_076 m
               ON m.annotation_id = l.annotation_id AND m.region = l.region AND m.new_hash = l.content_hash
              WHERE m.annotation_id IS NULL)
     OR EXISTS (SELECT 1 FROM mito_lca_raw l LEFT JOIN pre_v3_archive.lca_raw_results_hash_map_076 m
               ON m.annotation_id = l.annotation_id AND m.sequence_region = l.sequence_region
              AND m.accession_id = l.accession_id AND m.new_hash = l.content_hash
              WHERE m.annotation_id IS NULL) THEN
    RAISE EXCEPTION '076: a recomputed content_hash does not match its map';
  END IF;

  -- Compatibility views: the old column list, in the old order.
  FOR i IN 1..array_length(tabs, 1) LOOP
    old := tabs[i][1]; base := tabs[i][2];
    SELECT string_agg(CASE attname
                        WHEN 'og_id' THEN 'a.og_id' WHEN 'tech' THEN 'a.tech'
                        WHEN 'seq_date' THEN 'a.seq_date' WHEN 'code' THEN 'a.code'
                        WHEN 'annotation' THEN 'an.annotation'
                        ELSE format('t.%I', attname) END, ', ' ORDER BY attnum)
      INTO sel FROM r7b_cols WHERE tbl = old;
    EXECUTE format('CREATE VIEW public.%I AS SELECT %s FROM public.%I t '
                   'JOIN public.mito_annotation an ON an.annotation_id = t.annotation_id '
                   'JOIN public.mito_assembly a ON a.assembly_id = an.assembly_id', old, sel, base);
    EXECUTE format('COMMENT ON VIEW public.%I IS %L', old,
      'Compatibility view (076, Phase R.7b): ' || base || ' with the natural columns (og_id, tech, '
      'seq_date, code, annotation) joined back from mito_annotation / mito_assembly, in the old '
      'column order. Read-only: write ' || base || ', resolving the key with mito_annotation_id().');
    FOR r IN SELECT * FROM r7b_tbl_grants WHERE tbl = old LOOP
      EXECUTE format('GRANT %s ON public.%I TO %I', r.privilege_type, old, r.grantee);
    END LOOP;
  END LOOP;

  -- The 033 update path, onto the base table.
  CREATE OR REPLACE FUNCTION public.lca_validation_report_view_upd() RETURNS trigger
  LANGUAGE plpgsql AS $f$
  BEGIN
    -- Optional safety: prevent attempts to change the identifying fields via the view
    IF NEW.og_id IS DISTINCT FROM OLD.og_id
       OR NEW.tech IS DISTINCT FROM OLD.tech
       OR NEW.seq_date IS DISTINCT FROM OLD.seq_date
       OR NEW.code IS DISTINCT FROM OLD.code
       OR NEW.annotation IS DISTINCT FROM OLD.annotation
    THEN
      RAISE EXCEPTION
        'Cannot change key fields (og_id, tech, seq_date, code, annotation) through lca_validation_report_view';
    END IF;

    -- Persist only the editable columns back to the base table (mito_lca_validation since 076).
    UPDATE mito_lca_validation
    SET validated_species_name         = NEW.validated_species_name,
        validator                      = NEW.validator,
        validator_2                    = NEW.validator_2,
        nominal_species_id_lca_comment = NEW.comment
    WHERE annotation_id = mito_annotation_id(OLD.og_id, OLD.tech, OLD.seq_date, OLD.code, OLD.annotation, false);

    -- If no row was updated, something is off (missing row or key mismatch).
    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Update failed: no matching row in lca_validation for (og_id=%, tech=%, seq_date=%, code=%, annotation=%)',
        OLD.og_id, OLD.tech, OLD.seq_date, OLD.code, OLD.annotation;
    END IF;

    RETURN NEW;
  END;
  $f$;

  -- Recreate the dependent views, parents first, with comments, grants and triggers.
  FOR r IN SELECT * FROM r7b_views ORDER BY lvl, sch, name LOOP
    EXECUTE format('CREATE VIEW %I.%I AS %s', r.sch, r.name, r.def);
    IF r.cmt IS NOT NULL THEN
      EXECUTE format('COMMENT ON VIEW %I.%I IS %L', r.sch, r.name, r.cmt);
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM r7b_view_cols WHERE cmt IS NOT NULL LOOP
    EXECUTE format('COMMENT ON COLUMN %I.%I.%I IS %L', r.sch, r.name, r.attname, r.cmt);
  END LOOP;
  FOR r IN SELECT * FROM r7b_view_grants LOOP
    EXECUTE format('GRANT %s ON %I.%I TO %I', r.privilege_type, r.sch, r.name, r.grantee);
  END LOOP;
  FOR r IN SELECT * FROM r7b_view_triggers LOOP
    EXECUTE r.def;
  END LOOP;

  -- Verify.
  FOR i IN 1..array_length(tabs, 1) LOOP
    old := tabs[i][1]; base := tabs[i][2];
    -- Base table: same rows, same non-key content.
    EXECUTE format(
      'SELECT count(*) = (SELECT n FROM r7b_tbl WHERE tbl = %L) AND '
      'md5(string_agg((to_jsonb(t) - ''content_hash'')::text, '','' ORDER BY (to_jsonb(t) - ''content_hash'')::text)) '
      '  = (SELECT fp FROM r7b_tbl WHERE tbl = %L) FROM public.%I t', old, old, base) INTO STRICT sel;
    IF sel <> 'true' THEN RAISE EXCEPTION '076: % differs from the old % (rows or content)', base, old; END IF;
    -- Compatibility view: the old rows exactly, hash aside, and the old column list and types.
    EXECUTE format(
      'SELECT md5(string_agg((to_jsonb(t) - ''content_hash'')::text, '','' ORDER BY (to_jsonb(t) - ''content_hash'')::text)) '
      '  = (SELECT compat_fp FROM r7b_tbl WHERE tbl = %L) FROM public.%I t', old, old) INTO STRICT sel;
    IF sel <> 'true' THEN RAISE EXCEPTION '076: compatibility view % does not reproduce the old table', old; END IF;
    IF EXISTS (
      (SELECT pos, attname, typ FROM r7b_cols WHERE tbl = old)
      EXCEPT
      (SELECT row_number() OVER (ORDER BY a.attnum), a.attname, format_type(a.atttypid, a.atttypmod)
         FROM pg_attribute a
        WHERE a.attrelid = format('public.%I', old)::regclass AND a.attnum > 0 AND NOT a.attisdropped)) THEN
      RAISE EXCEPTION '076: compatibility view % has a different column list', old;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM r7b_views LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I', r.sch, r.name) INTO n;
    IF n <> r.rows_before THEN
      RAISE EXCEPTION '076: %.% returns % rows, had %', r.sch, r.name, n, r.rows_before;
    END IF;
  END LOOP;
  IF EXISTS (
    (SELECT sch, name, attnum, attname, typ FROM r7b_view_cols)
    EXCEPT
    (SELECT n.nspname, c.relname, a.attnum, a.attname, format_type(a.atttypid, a.atttypmod)
       FROM r7b_views v JOIN pg_namespace n ON n.nspname = v.sch
       JOIN pg_class c ON c.relname = v.name AND c.relnamespace = n.oid
       JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped)) THEN
    RAISE EXCEPTION '076: a recreated view has a different column list';
  END IF;
  -- The compatibility views are read-only: an old writer fails loudly.
  BEGIN
    INSERT INTO public.lca_validation (og_id) VALUES ('OG1');
    RAISE EXCEPTION USING ERRCODE = 'P0076', MESSAGE = 'insert into the lca_validation view succeeded';
  EXCEPTION
    WHEN SQLSTATE 'P0076' THEN RAISE EXCEPTION '076: the lca_validation view accepted an insert';
    WHEN OTHERS THEN NULL;
  END;

  RAISE NOTICE '076: LCA tables stored by annotation_id; compatibility views and % dependent views in place',
    (SELECT count(*) FROM r7b_views);
END
$r7b$;

COMMIT;
