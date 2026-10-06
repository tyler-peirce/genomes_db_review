-- Verify genomes_db:create_v2_lca_tables on pg

BEGIN;

DO $$
DECLARE
  tbl text;
  n   bigint;
  rec record;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'mitogenome_data', 'lca', 'lca_validation', 'lca_raw_results', 'blast_filtered_lca'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = 'v2' AND table_name = tbl) THEN
      RAISE EXCEPTION 'Missing expected table: v2.%', tbl;
    END IF;

    EXECUTE format('SELECT count(*) FROM v2.%I', tbl) INTO n;
    IF n <> 0 THEN
      RAISE EXCEPTION 'Expected v2.% to be empty, found % rows', tbl, n;
    END IF;

    -- Every one of them must now reach sample by a real foreign key (none of the live tables does).
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint c
      JOIN pg_namespace ns ON ns.oid = c.connamespace AND ns.nspname = 'v2'
      WHERE c.contype = 'f'
        AND c.conrelid = format('v2.%I', tbl)::regclass
        AND c.confrelid = 'v2.sample'::regclass
    ) THEN
      RAISE EXCEPTION 'v2.% has no foreign key to v2.sample', tbl;
    END IF;

    -- A real primary key, not just a unique constraint.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c
                   WHERE c.contype = 'p' AND c.conrelid = format('v2.%I', tbl)::regclass) THEN
      RAISE EXCEPTION 'v2.% has no primary key', tbl;
    END IF;

    IF obj_description(format('v2.%I', tbl)::regclass, 'pg_class') IS NULL THEN
      RAISE EXCEPTION 'Table v2.% has no COMMENT (Finding 9)', tbl;
    END IF;
  END LOOP;

  -- The og_num generated column must not have come across (F2).
  FOR rec IN
    SELECT c.table_name FROM information_schema.columns c
    WHERE c.table_schema = 'v2' AND c.column_name = 'og_num'
      AND c.table_name IN ('mitogenome_data','lca','lca_validation','lca_raw_results','blast_filtered_lca')
  LOOP
    RAISE EXCEPTION 'v2.%.og_num exists; it raises on a non-parsing og_id and is available from sample (F2)', rec.table_name;
  END LOOP;

  -- lca_run_date must agree between the two tables that key on it (F8).
  IF (SELECT data_type FROM information_schema.columns
       WHERE table_schema='v2' AND table_name='lca' AND column_name='lca_run_date')
     IS DISTINCT FROM
     (SELECT data_type FROM information_schema.columns
       WHERE table_schema='v2' AND table_name='lca_raw_results' AND column_name='lca_run_date') THEN
    RAISE EXCEPTION 'lca.lca_run_date and lca_raw_results.lca_run_date still disagree on type (F8)';
  END IF;

  -- No character varying anywhere (F8).
  FOR rec IN
    SELECT c.table_name, c.column_name FROM information_schema.columns c
    WHERE c.table_schema = 'v2' AND c.data_type = 'character varying'
      AND c.table_name IN ('mitogenome_data','lca','lca_validation','lca_raw_results','blast_filtered_lca')
  LOOP
    RAISE EXCEPTION 'v2.%.% is character varying; v2 standardises on text (F8)', rec.table_name, rec.column_name;
  END LOOP;

  -- The *_new check this used to carry is gone, not relaxed. It guarded against touching
  -- `lca_new` and its siblings while the LCA rebuild was concurrent work. That rebuild has
  -- landed and those tables are now the live LCA tables themselves, so the check tested a
  -- condition that can no longer occur. Corrected 2026-10-05, Phase V.1 item 1.
  --
  -- What is worth asserting instead: the columns migrations 017, 022 and 024 added, which
  -- this file omitted for three months, and the content-addressed keys.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'v2' AND table_name = 'lca'
                   AND column_name = 'content_hash') THEN
    RAISE EXCEPTION 'v2.lca.content_hash is missing (migration 017)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'v2' AND table_name = 'lca_validation'
                   AND column_name = 'validated_rank') THEN
    RAISE EXCEPTION 'v2.lca_validation.validated_rank is missing (migration 024)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'v2' AND table_name = 'mitogenome_data'
                   AND column_name = 'annotation_integrity_status') THEN
    RAISE EXCEPTION 'v2.mitogenome_data is missing the migration 026 annotation columns';
  END IF;

  -- The key must include content_hash, not lca_run_date: 33 live lca_raw_results rows
  -- collide under a run_date key (several HSPs per accession in one run).
  IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'v2.lca_raw_results'::regclass AND c.contype = 'p'
          AND pg_get_constraintdef(c.oid) LIKE '%content_hash%') THEN
    RAISE EXCEPTION 'v2.lca_raw_results primary key does not include content_hash; it is not satisfiable by live data';
  END IF;

  -- content_hash is NOT NULL and in the key, so the trigger that fills it must exist.
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgrelid = 'v2.lca'::regclass AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'v2.lca has no content_hash trigger; every insert would violate NOT NULL';
  END IF;
END $$;

ROLLBACK;
