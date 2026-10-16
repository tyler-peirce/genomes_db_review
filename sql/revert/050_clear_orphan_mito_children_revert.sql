-- 050_clear_orphan_mito_children_revert.sql -- put back the 532 rows 050 deleted.
--
-- Restores from the pre_v3_archive.<table>_orphans_260909 copies 050 made, then drops them.
-- Generated columns (og_num) are left out of the insert. ena_validation_attempts.id is
-- GENERATED ALWAYS AS IDENTITY, so it is inserted with OVERRIDING SYSTEM VALUE and keeps its
-- original value. lca and lca_raw_results recompute content_hash on insert from the row's own
-- content (lca_set_content_hash), which reproduces the archived value; the md5 check below
-- proves it.
--
-- The archive CSVs in archive/mito_orphans_260909/ are the copy of last resort if the
-- pre_v3_archive tables are gone.
--
-- After running this, delete 050's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '050_clear_orphan_mito_children.sql';

BEGIN;

CREATE TEMP TABLE orphan_expect (tbl text, n int, fingerprint text) ON COMMIT DROP;
INSERT INTO orphan_expect VALUES
  ('lca_validation',            1, '24a8eb61a07a022b1f31197c4a3d98db'),
  ('lca',                       8, '0ca64eefbb3f2e985d3c768f421cf9c0'),
  ('lca_raw_results',          74, '4b5a7b787106e9faacfe94f1331764d1'),
  ('blast_filtered_lca',      443, 'fc306a49206bdbbfa9dd81afe356b267'),
  ('ena_validation_attempts',   6, '7569ae8b5b48a937b5a45857f2d5a318');

DO $revert$
DECLARE
  e        record;
  cols     text;
  arch     text;
  n        int;
  checksum text;
BEGIN
  FOR e IN SELECT * FROM orphan_expect LOOP
    arch := e.tbl || '_orphans_260909';
    IF to_regclass('pre_v3_archive.' || arch) IS NULL THEN
      RAISE NOTICE 'pre_v3_archive.% not found; nothing to restore for %', arch, e.tbl;
      CONTINUE;
    END IF;

    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum) INTO cols
    FROM pg_attribute a
    WHERE a.attrelid = ('public.' || e.tbl)::regclass
      AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = '';

    EXECUTE format('INSERT INTO public.%I (%s) %s SELECT %s FROM pre_v3_archive.%I',
                   e.tbl, cols,
                   CASE WHEN e.tbl = 'ena_validation_attempts' THEN 'OVERRIDING SYSTEM VALUE' ELSE '' END,
                   cols, arch);

    EXECUTE format('SELECT count(*), md5(string_agg(to_jsonb(x)::text, E''\n'' ORDER BY to_jsonb(x)::text COLLATE "C")) '
                   'FROM public.%I x WHERE EXISTS (SELECT 1 FROM pre_v3_archive.%I a WHERE %s)',
                   e.tbl, arch,
                   CASE WHEN e.tbl = 'ena_validation_attempts' THEN 'a.id = x.id'
                        ELSE '(a.og_id, a.tech, a.seq_date, a.code, a.annotation) = (x.og_id, x.tech, x.seq_date, x.code, x.annotation)' END)
      INTO n, checksum;
    IF n <> e.n OR checksum <> e.fingerprint THEN
      RAISE EXCEPTION '%: restored % rows with md5 %, expected % with %', e.tbl, n, checksum, e.n, e.fingerprint;
    END IF;

    EXECUTE format('DROP TABLE pre_v3_archive.%I', arch);
  END LOOP;

  -- Drop the schema only if 050 created nothing else in it since.
  IF to_regnamespace('pre_v3_archive') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_class WHERE relnamespace = to_regnamespace('pre_v3_archive')) THEN
    DROP SCHEMA pre_v3_archive;
  END IF;
END
$revert$;

COMMIT;
