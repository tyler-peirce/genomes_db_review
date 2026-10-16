-- 050_clear_orphan_mito_children.sql -- remove LCA/ENA rows whose annotation no longer exists,
-- and every ENA validation attempt on an `_rgj` assembly.
--
-- Why. mitogenome_data holds one annotation per assembly, and both writers upsert on the four
-- assembly columns, so a re-annotation overwrote the previous one. Child rows that carried the
-- old annotation were left describing an annotation the database no longer holds
-- (docs/assembly_relations_plan.md §2.1, §3.6). Owner decisions 2026-10-16:
--   - decision 10: rows whose annotation is gone came from a misnamed or replaced annotation;
--     clear them, do not keep them as stubs;
--   - decision 6: the reference-guided-join (`_rgj`) step is gone from the pipeline. The `_rgj`
--     assemblies and their LCA rows stay, but every ENA validation attempt on an `_rgj`
--     assembly is removed. OG2936's attempt (PASS, submission_ready = true) is not
--     submission-ready.
-- This must happen before Phase R builds `v3`, whose backfill requires every child row to
-- resolve to an annotation (§6, R.2).
--
-- Rows, on live 2026-10-16 (532 in all):
--   lca_validation 1, lca 8, lca_raw_results 74, blast_filtered_lca 443:
--     OG2628, OG3050, OG3060 ilmn.260909.getorg1770.mitos2110 (replaced by mito2110mc);
--   ena_validation_attempts 6:
--     OG2951, OG3000 ilmn.260909.getorg1770.mitos2110 (annotation wiped);
--     OG2936 getorg1770_rgj, OG2982 and OG3038 getorg1770reseed_rgj, all 260909 mitos2110
--     (assembly gone);
--     OG562.ilmn.230419.getorg1770reseed_rgj.emma102 (assembly exists; `_rgj`, decision 6);
--   ena_submissions 0.
--
-- What was rejected. Keeping orphans as backfilled stub annotations (the plan's first draft):
-- the owner judged them misnamed, not history. Deleting by a generic NOT EXISTS: a future orphan
-- would be swept up by a replay, so the keys are listed.
--
-- Not touched, and asserted: the 35 `_rgj` assemblies and their 25 lca_validation, 58 lca,
-- 366 lca_raw_results and 715 blast_filtered_lca rows.
--
-- Guards, all before anything is deleted:
--   1. Replay: if no keyed row is present, the file does nothing.
--   2. Opt-in. Refuses unless PGOPTIONS carries the row count this file expects:
--        PGOPTIONS="-c oceanomics.clear_mito_orphans=532" bin/apply_migrations.py
--   3. Each table's keyed row count equals the archived count.
--   4. The three LCA keys are still orphaned: no mitogenome_data row carries that
--      (assembly, annotation). If one has reappeared, it is not an orphan, so refuse.
--   5. Each table's keyed rows are byte-identical to the archive (md5 below). If a writer has
--      touched them since, re-export and update this file.
--
-- Archive. archive/mito_orphans_260909/ (one CSV per table, MANIFEST.md, SHA256SUMS). This file
-- also copies the rows into pre_v3_archive.<table>_orphans_260909, which the revert restores
-- from. pre_v3_archive is the schema Phase R's merge (R.6) archives the old tables into.
--
-- Revert: sql/revert/050_clear_orphan_mito_children_revert.sql.

BEGIN;

CREATE TEMP TABLE orphan_lca_keys (og_id text, tech text, seq_date text, code text, annotation text)
  ON COMMIT DROP;
INSERT INTO orphan_lca_keys VALUES
  ('OG2628', 'ilmn', '260909', 'getorg1770', 'mitos2110'),
  ('OG3050', 'ilmn', '260909', 'getorg1770', 'mitos2110'),
  ('OG3060', 'ilmn', '260909', 'getorg1770', 'mitos2110');

CREATE TEMP TABLE orphan_ena_keys (full_seqid text) ON COMMIT DROP;
INSERT INTO orphan_ena_keys VALUES
  ('OG2951.ilmn.260909.getorg1770.mitos2110'),
  ('OG3000.ilmn.260909.getorg1770.mitos2110'),
  ('OG2936.ilmn.260909.getorg1770_rgj.mitos2110'),
  ('OG2982.ilmn.260909.getorg1770reseed_rgj.mitos2110'),
  ('OG3038.ilmn.260909.getorg1770reseed_rgj.mitos2110'),
  ('OG562.ilmn.230419.getorg1770reseed_rgj.emma102');

-- table, expected rows, md5(string_agg(to_jsonb(row)::text, E'\n' ORDER BY to_jsonb(row)::text COLLATE "C"))
CREATE TEMP TABLE orphan_expect (tbl text, n int, fingerprint text) ON COMMIT DROP;
INSERT INTO orphan_expect VALUES
  ('lca_validation',            1, '24a8eb61a07a022b1f31197c4a3d98db'),
  ('lca',                       8, '0ca64eefbb3f2e985d3c768f421cf9c0'),
  ('lca_raw_results',          74, '4b5a7b787106e9faacfe94f1331764d1'),
  ('blast_filtered_lca',      443, 'fc306a49206bdbbfa9dd81afe356b267'),
  ('ena_validation_attempts',   6, '7569ae8b5b48a937b5a45857f2d5a318');

CREATE TEMP TABLE orphan_deleted (done boolean) ON COMMIT DROP;

CREATE SCHEMA IF NOT EXISTS pre_v3_archive;
COMMENT ON SCHEMA pre_v3_archive IS
  'Phase R archive: rows and tables replaced by the v3 design. Dropped at R.8 after a pg_dump. '
  'docs/assembly_relations_plan.md';

DO $guard$
DECLARE
  e        record;
  present  int := 0;
  n        int;
  checksum text;
  where_   text;
BEGIN
  FOR e IN SELECT * FROM orphan_expect LOOP
    where_ := CASE WHEN e.tbl = 'ena_validation_attempts'
                   THEN 'full_seqid IN (SELECT full_seqid FROM orphan_ena_keys)'
                   ELSE '(og_id, tech, seq_date, code, annotation) IN (SELECT * FROM orphan_lca_keys)' END;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE %s', e.tbl, where_) INTO n;
    present := present + n;
  END LOOP;
  IF present = 0 THEN
    RETURN;  -- already removed; replay
  END IF;

  IF coalesce(current_setting('oceanomics.clear_mito_orphans', true), '') <> '532' THEN
    RAISE EXCEPTION 'This deletes 532 orphaned and _rgj LCA/ENA rows (% still present). Run with '
      'PGOPTIONS="-c oceanomics.clear_mito_orphans=532"', present;
  END IF;

  IF EXISTS (SELECT 1 FROM public.mitogenome_data m JOIN orphan_lca_keys k
               USING (og_id, tech, seq_date, code, annotation)) THEN
    RAISE EXCEPTION 'An orphaned annotation is back in mitogenome_data, so its LCA rows are not '
      'orphans any more. Investigate before deleting.';
  END IF;

  FOR e IN SELECT * FROM orphan_expect LOOP
    where_ := CASE WHEN e.tbl = 'ena_validation_attempts'
                   THEN 'full_seqid IN (SELECT full_seqid FROM orphan_ena_keys)'
                   ELSE '(og_id, tech, seq_date, code, annotation) IN (SELECT * FROM orphan_lca_keys)' END;
    EXECUTE format('SELECT count(*), md5(string_agg(to_jsonb(x)::text, E''\n'' ORDER BY to_jsonb(x)::text COLLATE "C")) '
                   'FROM public.%I x WHERE %s', e.tbl, where_) INTO n, checksum;
    IF n <> e.n THEN
      RAISE EXCEPTION '%: expected % keyed rows, found %. Some were already removed or added; '
        'investigate.', e.tbl, e.n, n;
    END IF;
    IF checksum <> e.fingerprint THEN
      RAISE EXCEPTION '%: rows changed since they were archived on 2026-10-16 (md5 %). Re-export '
        'and update this file.', e.tbl, checksum;
    END IF;
  END LOOP;

  -- Copy into the archive schema; the revert restores from these.
  FOR e IN SELECT * FROM orphan_expect LOOP
    where_ := CASE WHEN e.tbl = 'ena_validation_attempts'
                   THEN 'full_seqid IN (SELECT full_seqid FROM orphan_ena_keys)'
                   ELSE '(og_id, tech, seq_date, code, annotation) IN (SELECT * FROM orphan_lca_keys)' END;
    EXECUTE format('CREATE TABLE pre_v3_archive.%I AS SELECT * FROM public.%I WHERE %s',
                   e.tbl || '_orphans_260909', e.tbl, where_);
    EXECUTE format('COMMENT ON TABLE pre_v3_archive.%I IS %L', e.tbl || '_orphans_260909',
                   'Rows removed from public.' || e.tbl || ' by 050 (orphaned or _rgj); '
                   'archive/mito_orphans_260909/');
  END LOOP;

  DELETE FROM public.lca_validation      WHERE (og_id, tech, seq_date, code, annotation) IN (SELECT * FROM orphan_lca_keys);
  DELETE FROM public.lca                 WHERE (og_id, tech, seq_date, code, annotation) IN (SELECT * FROM orphan_lca_keys);
  DELETE FROM public.lca_raw_results     WHERE (og_id, tech, seq_date, code, annotation) IN (SELECT * FROM orphan_lca_keys);
  DELETE FROM public.blast_filtered_lca  WHERE (og_id, tech, seq_date, code, annotation) IN (SELECT * FROM orphan_lca_keys);
  DELETE FROM public.ena_validation_attempts WHERE full_seqid IN (SELECT full_seqid FROM orphan_ena_keys);
  INSERT INTO orphan_deleted VALUES (true);
END
$guard$;

DO $verify$
DECLARE
  n int;
BEGIN
  -- No child row left whose (assembly, annotation) is not in mitogenome_data.
  SELECT count(*) INTO n FROM (
    SELECT og_id, tech, seq_date, code, annotation FROM public.lca_validation
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.lca
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.lca_raw_results
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.blast_filtered_lca
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.ena_validation_attempts
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.ena_submissions) c
  WHERE NOT EXISTS (SELECT 1 FROM public.mitogenome_data m
                    WHERE (m.og_id, m.tech, m.seq_date, m.code, m.annotation)
                        = (c.og_id, c.tech, c.seq_date, c.code, c.annotation));
  IF n <> 0 THEN
    RAISE EXCEPTION '% child rows still have no matching annotation after 050', n;
  END IF;

  IF EXISTS (SELECT 1 FROM public.ena_validation_attempts WHERE code ~ '_rgj') THEN
    RAISE EXCEPTION 'An _rgj ENA validation attempt is still present after 050';
  END IF;

  -- The _rgj assemblies and their LCA rows are kept. Checked only on the run that deleted, so a
  -- later replay is not tied to today's counts.
  IF EXISTS (SELECT 1 FROM orphan_deleted) AND (
     (SELECT count(*) FROM public.mitogenome_data    WHERE code ~ '_rgj') <> 35
  OR (SELECT count(*) FROM public.lca_validation     WHERE code ~ '_rgj') <> 25
  OR (SELECT count(*) FROM public.lca                WHERE code ~ '_rgj') <> 58
  OR (SELECT count(*) FROM public.lca_raw_results    WHERE code ~ '_rgj') <> 366
  OR (SELECT count(*) FROM public.blast_filtered_lca WHERE code ~ '_rgj') <> 715) THEN
    RAISE EXCEPTION 'The kept _rgj assemblies or their LCA rows changed; expected 35/25/58/366/715';
  END IF;
END
$verify$;

COMMIT;
