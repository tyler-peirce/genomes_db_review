-- 091_drop_archive_schemas.sql -- close-out of the v2 cutover (V.7), Phase R (R.8) and Phase RG
-- (RG.7): drop pre_v2_archive, pre_v3_archive and pre_v4_archive.
--
-- Why. Owner, 2026-11-23: do the close-out. Each schema holds the tables a cutover replaced, kept
-- "for a quiet period" as a rollback point:
--   - pre_v2_archive (179 MB; 18 tables, 3 views, 2 trigger functions): the pre-v2 lab, LCA and
--     mitogenome tables, archived by 048 on 2026-10-15.
--   - pre_v3_archive (11 MB; 9 tables): the flat mitogenome_data and draft_genomes and the 260909
--     orphans, archived by 072 (R.6) on 2026-11-02, and 076's hash maps.
--   - pre_v4_archive (1.4 MB; 8 tables, 2 views, 1 sequence): the six flat ref-genome tables,
--     ref_key_map and ref_excluded_rows, archived by 073 (RG.6) on 2026-11-02.
-- Checked on live, read-only, 2026-11-23:
--   - Nothing outside the three schemas depends on them: no view, FK, function body or trigger.
--     The one cross-schema FK runs outward (pre_v3_archive.mitogenome_data -> sample) and goes
--     with its table.
--   - No repository references them outside migrations and docs, at the remote default branch
--     of every pipeline (the SHAs in database_review.md 3.55).
--   - OceanGenom_Web has SELECT on all three; the owner confirmed it does not read them.
--   - R.8's data condition holds: every host, partition, lambda_depth, kmercov and modelfit value
--     in pre_v3_archive.draft_genomes has a value in public.draft_genomescope, and the only
--     archived draft not in public is OG617 230607, deleted by the owner on 2026-11-18
--     (docs/records/og617_230607_stub_before_delete_261118.jsonl).
--
-- Permanent copy (outside git, as R.8 and RG.7 specify):
--   ~/oceanomics_genomes_archives_pre_091_261123.dump   (pg_dump -Fc -n the three schemas)
--   sha256 f5f3945840862b6220a2c390c687445f60dd3b9dd502cbf81efedde4d87312e9
-- Verified by restoring it and comparing every table's row count and row-set md5 with live
-- (35 tables, 383,829 rows). The earlier full dumps (~/oceanomics_genomes_pre_v6_261015.dump,
-- ..._pre_072_261102.dump, ..._pre_073_261102.dump) hold the same data as at each cutover.
--
-- Opt-in, as for 047: this refuses to run unless the operator passes the row total of the
-- verified dump, and that total equals the live one:
--   PGOPTIONS="-c oceanomics.archive_dump_verified_rows=383829" bin/apply_migrations.py
--
-- Rejected: dropping table by table. DROP SCHEMA ... CASCADE is one statement, and the guard
-- refuses if anything outside the three schemas would go with it.
--
-- Replay: every schema is IF EXISTS and the guard skips once they are gone, so a replay is a
-- no-op. Revert: sql/revert/091_drop_archive_schemas_revert.sql (pg_restore of the dump above).

BEGIN;

DO $guard$
DECLARE
  live_rows bigint := 0;
  n bigint;
  r record;
  passed text := current_setting('oceanomics.archive_dump_verified_rows', true);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname IN ('pre_v2_archive', 'pre_v3_archive', 'pre_v4_archive')) THEN
    RETURN;  -- replay
  END IF;

  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('pre_v2_archive', 'pre_v3_archive', 'pre_v4_archive') AND c.relkind = 'r' LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I', r.nspname, r.relname) INTO n;
    live_rows := live_rows + n;
  END LOOP;
  IF passed IS NULL OR passed = '' OR passed::bigint <> live_rows THEN
    RAISE EXCEPTION '091: pass the row total of a verified dump of the three archive schemas '
      '(PGOPTIONS="-c oceanomics.archive_dump_verified_rows=N"); got %, live has %.', passed, live_rows;
  END IF;

  -- Anything outside the archives that depends on an object inside them would go with CASCADE.
  SELECT count(*) INTO n
    FROM pg_depend d
    JOIN pg_class rc ON rc.oid = d.refobjid AND d.refclassid = 'pg_class'::regclass
    JOIN pg_namespace rn ON rn.oid = rc.relnamespace
   WHERE rn.nspname IN ('pre_v2_archive', 'pre_v3_archive', 'pre_v4_archive')
     AND d.deptype = 'n'
     AND (   (d.classid = 'pg_rewrite'::regclass AND EXISTS (
                SELECT 1 FROM pg_rewrite w JOIN pg_class wc ON wc.oid = w.ev_class
                 WHERE w.oid = d.objid
                   AND wc.relnamespace::regnamespace::text NOT IN ('pre_v2_archive', 'pre_v3_archive', 'pre_v4_archive')))
          OR (d.classid = 'pg_constraint'::regclass AND EXISTS (
                SELECT 1 FROM pg_constraint k
                 WHERE k.oid = d.objid
                   AND k.conrelid::regclass::text !~ '^pre_v[234]_archive\.')));
  IF n > 0 THEN
    RAISE EXCEPTION '091: % objects outside the archive schemas depend on them; find them before dropping.', n;
  END IF;

  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace pn ON pn.oid = p.pronamespace
   WHERE pn.nspname NOT IN ('pre_v2_archive', 'pre_v3_archive', 'pre_v4_archive', 'pg_catalog', 'information_schema')
     AND p.prosrc ~ 'pre_v[234]_archive';
  IF n > 0 THEN
    RAISE EXCEPTION '091: % functions outside the archives name an archive schema in their body.', n;
  END IF;
END
$guard$;

DROP SCHEMA IF EXISTS pre_v2_archive CASCADE;
DROP SCHEMA IF EXISTS pre_v3_archive CASCADE;
DROP SCHEMA IF EXISTS pre_v4_archive CASCADE;

COMMIT;
