-- 043_v2_mitogenome_submission_view.sql -- the v2 equivalent of mitogenome_submission_view.
--
-- Run after 042_v2_sample_length_depth_split.sql. Idempotent: CREATE OR REPLACE VIEW and
-- COMMENT, and its verification runs inside this transaction.
--
-- Why: public.mitogenome_submission_view (029) selects m.og_num from mitogenome_data. v2
--   drops that column from all five LCA / mitogenome tables (F2, 039 transformation 1), so the
--   view has no v2 form and cannot follow the cutover. Phase V.1 found the gap -- the August
--   cutover audit only covered views over the twelve lab tables -- and deliberately left the
--   DDL for later; docs/v2_cutover_dependencies.md lists it as the one outstanding piece. This
--   is that piece, written ahead of V.5 so the cutover migration only has to rebind names.
--
-- What changes, and nothing else does:
--   - og_num comes from v2.sample, joined on og_id. That is where F2 put it, and it is
--     null-safe: v2.sample.og_num is NULL on an og_id not matching ^OG[0-9]+$ rather than
--     raising, as the live generated column does. The join cannot fan out (og_id is
--     v2.sample's primary key) and cannot drop a row (v2.mitogenome_data.og_id has an FK to
--     it); it is a LEFT JOIN anyway, so the row count depends on mitogenome_data alone and
--     the verification below can say so.
--   - The ::text casts in 029's join conditions are gone. They existed because live mixes
--     varchar and text across these keys; every v2 key column is text (F8). The join keys
--     themselves are 029's exactly: the five-field sequence identity on both joins.
--   - Output column names and order match the public view. Some types differ (annotation,
--     extra_genes, missing_genes, order_correct are text, were varchar), which a reader of
--     the result cannot see.
--
-- Rejected:
--   - Recomputing og_num in the view with regexp_replace(og_id, 'OG', '')::integer, as two
--     cutover-neutral views do. It reproduces the live column's raise-on-bad-og_id failure
--     that F2 removed, and v2.sample already holds the answer one indexed join away.
--   - Reinstating og_num on v2.mitogenome_data. 036's verification forbids og_num on any v2
--     table but sample.
--   - Reading ena_validation_latest, or adding DISTINCT ON. 029 explains why both were wrong
--     for the public view and nothing about v2 changes that.
--
-- Schema-qualification. ena_validation_attempts is not replaced by v2 and stays in public, so
--   it is named public.ena_validation_attempts explicitly, the same convention 040 uses for
--   master_species and ref_genomes. The v2 tables are named v2.* explicitly too, so the view
--   binds the same way whatever search_path it is created under.
--
-- Not done here, and owned by V.5:
--   - Grants. No v2 object carries a grant to the readonly role yet -- 035-042 grant nothing,
--     and readonly has no USAGE on schema v2 -- so a grant on this view alone would be inert.
--     The cutover migration must grant USAGE on v2 and SELECT on its tables and views, or
--     every readonly consumer loses access the moment the search_path moves. That gap is
--     schema-wide, not this view's.
--   - Making this the view that unqualified mitogenome_submission_view resolves to. That is
--     the search_path swap and the _pre_v2 rename, at V.5.
--
-- Expected impact: Additive only. One view in schema v2. Nothing in public is touched.
--
-- Rollback: sql/revert/043_v2_mitogenome_submission_view_revert.sql.
--
--   bin/apply_migrations.py

BEGIN;

CREATE OR REPLACE VIEW v2.mitogenome_submission_view AS
 SELECT s.og_num,
    m.og_id,
    m.tech,
    m.seq_date,
    m.code,
    m.annotation,
    m.stats,
    m.length,
    m.length_emma,
    m.cds_no,
    m.trna_no,
    m.rrna_no,
    m.avg_coverage,
    m.avg_base_coverage,
    m.extra_genes,
    m.missing_genes,
    m.order_correct,
    e.table2asn_status,
    e.warning_codes,
    e.webin_status,
    e.webin_reason,
    e.submission_ready,
    l.validated_species_name,
    l.validator
   FROM v2.mitogenome_data m
     LEFT JOIN v2.sample s
       ON s.og_id = m.og_id
     LEFT JOIN public.ena_validation_attempts e
       ON e.og_id = m.og_id
      AND e.tech = m.tech
      AND e.seq_date = m.seq_date
      AND e.code = m.code
      AND e.annotation = m.annotation
     LEFT JOIN v2.lca_validation l
       ON l.og_id = m.og_id
      AND l.tech = m.tech
      AND l.seq_date = m.seq_date
      AND l.code = m.code
      AND l.annotation = m.annotation;

COMMENT ON VIEW v2.mitogenome_submission_view IS
    'One row per mitogenome assembly with its ENA validation result and validated species '
    'name, for ENA submission. v2 form of public.mitogenome_submission_view (029): og_num '
    'comes from v2.sample, because v2 drops it from mitogenome_data (F2). See migration 043.';

-- ---------------------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------------------
--
-- Structure and fan-out are asserted. Data agreement with the public view is REPORTED, not
-- asserted: v2.mitogenome_data is loaded by scripts/backfill_v2.sql, insert-only, while the
-- pipelines keep writing public.mitogenome_data, so the two legitimately drift between a
-- backfill and the cutover. A difference here is a reason to re-sync before V.5, not a
-- reason to refuse a view definition. The rehearsal compares them properly; see the V.5
-- record in database_review.md.

DO $$
DECLARE
  v2_cols     text[];
  public_cols text[];
  n_view      bigint;
  n_base      bigint;
  n_v2_only   bigint;
  n_pub_only  bigint;
BEGIN
  IF to_regclass('v2.mitogenome_submission_view') IS NULL THEN
    RAISE EXCEPTION 'Missing view v2.mitogenome_submission_view';
  END IF;
  IF obj_description('v2.mitogenome_submission_view'::regclass, 'pg_class') IS NULL THEN
    RAISE EXCEPTION 'v2.mitogenome_submission_view has no COMMENT (Finding 9)';
  END IF;

  -- Same columns in the same order as the view it replaces, so a consumer reading by
  -- position or by name sees no change. Skipped when the public view is gone, i.e. on a
  -- replay after the V.5 rename.
  SELECT array_agg(column_name::text ORDER BY ordinal_position) INTO v2_cols
    FROM information_schema.columns
   WHERE table_schema = 'v2' AND table_name = 'mitogenome_submission_view';
  IF to_regclass('public.mitogenome_submission_view') IS NOT NULL THEN
    SELECT array_agg(column_name::text ORDER BY ordinal_position) INTO public_cols
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'mitogenome_submission_view';
    IF v2_cols IS DISTINCT FROM public_cols THEN
      RAISE EXCEPTION 'v2.mitogenome_submission_view columns % differ from public''s %',
        v2_cols, public_cols;
    END IF;
  END IF;

  -- One row per v2.mitogenome_data row: the joins must not fan out. 029 records why
  -- ena_validation_attempts holds one row per sequence identity; this checks it still does.
  SELECT count(*) INTO n_view FROM v2.mitogenome_submission_view;
  SELECT count(*) INTO n_base FROM v2.mitogenome_data;
  IF n_view <> n_base THEN
    RAISE EXCEPTION 'v2.mitogenome_submission_view has % rows, v2.mitogenome_data has %: a join fans out',
      n_view, n_base;
  END IF;

  IF to_regclass('public.mitogenome_submission_view') IS NOT NULL THEN
    SELECT count(*) INTO n_v2_only FROM (
      SELECT * FROM v2.mitogenome_submission_view
      EXCEPT ALL
      SELECT * FROM public.mitogenome_submission_view) d;
    SELECT count(*) INTO n_pub_only FROM (
      SELECT * FROM public.mitogenome_submission_view
      EXCEPT ALL
      SELECT * FROM v2.mitogenome_submission_view) d;
    RAISE NOTICE 'mitogenome_submission_view: % rows in v2; % only in v2, % only in public',
      n_view, n_v2_only, n_pub_only;
  END IF;
END $$;

COMMIT;
