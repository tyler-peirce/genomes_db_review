-- 074_r7_child_annotation_id.sql -- Phase R.7: tie every LCA and ENA child row to the annotation it
-- describes, with a foreign key to mito_annotation.
--
-- Plan: docs/r7_plan.md; design docs/assembly_relations_plan.md §3 and R.7.
--
-- Why. 072 (R.6) dropped the three four-column FKs from lca, lca_raw_results and lca_validation
-- to the old flat mitogenome_data; blast_filtered_lca, ena_validation_attempts and ena_submissions
-- never had one. Since then nothing stopped a child row naming an annotation that does not exist.
--
-- What. For each of the six child tables:
--   - add annotation_id bigint, backfill it from the row's natural columns
--     (og_id, tech, seq_date, code, annotation) -> mito_assembly -> mito_annotation, SET NOT NULL;
--   - index it, and FK it to mito_annotation (NOT VALID, then VALIDATE; NO ACTION on delete);
--   - a BEFORE INSERT OR UPDATE trigger, mito_child_annotation_id(), that fills annotation_id from the
--     natural columns (on ena_submissions, from full_seqid, because its natural columns are
--     generated and a BEFORE trigger sees them as NULL) when a writer leaves it out, checks it when one sends it, and refuses a row
--     whose natural columns name no annotation (or more than one).
-- Writers are unchanged: they keep sending the natural columns and the trigger fills the rest.
-- Dropping those natural columns is R.7b.
--
-- content_hash. lca and lca_raw_results key their rows by lca_set_content_hash(), an md5 over the
-- whole row minus three columns. A new column would change every new hash, so a re-upload would no
-- longer match the stored rows and would duplicate them. annotation_id is therefore added to the
-- exclusions (it is derived from columns already hashed). The two hash triggers are disabled during
-- the backfill, so no stored hash -- a primary-key column -- is recomputed; asserted below.
--
-- Measured on live 2026-11-02: every one of the 306,790 child rows resolves to exactly one annotation.
--
-- Opt-in, because it changes what writers may insert:
--     PGOPTIONS="-c oceanomics.r7_annotation_id=yes" bin/apply_migrations.py
-- Replay: when all six FKs exist and are validated, the file does nothing.
-- Revert: sql/revert/074_r7_child_annotation_id_revert.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.mito_child_annotation_id() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
DECLARE
  found bigint;
  n int;
  k_og text; k_tech text; k_date text; k_code text; k_ann text;
BEGIN
  IF TG_TABLE_NAME = 'ena_submissions' THEN
    -- Its natural columns are GENERATED from full_seqid, and a BEFORE trigger sees generated
    -- columns as NULL; derive them with the same expressions instead.
    k_og   := split_part(NEW.full_seqid, '.', 1);
    k_tech := split_part(NEW.full_seqid, '.', 2);
    k_date := split_part(NEW.full_seqid, '.', 3);
    k_code := split_part(NEW.full_seqid, '.', 4);
    k_ann  := substring(NEW.full_seqid FROM '^(?:[^.]+[.]){4}(.+)$');
  ELSE
    k_og := NEW.og_id; k_tech := NEW.tech; k_date := NEW.seq_date; k_code := NEW.code;
    k_ann := NEW.annotation;
  END IF;
  SELECT min(an.annotation_id), count(*) INTO found, n
    FROM mito_annotation an JOIN mito_assembly a USING (assembly_id)
   WHERE a.og_id = k_og AND a.tech = k_tech AND a.seq_date = k_date
     AND a.code = k_code AND an.annotation = k_ann;
  IF n <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = 'foreign_key_violation',
      MESSAGE = format('%s: %s mito annotation(s) match %s.%s.%s.%s annotation %s; upload the '
                       'assembly and its annotation before its LCA/ENA results',
                       TG_TABLE_NAME, n, k_og, k_tech, k_date, k_code, k_ann);
  END IF;
  IF NEW.annotation_id IS NULL THEN
    NEW.annotation_id := found;
  ELSIF NEW.annotation_id <> found THEN
    RAISE EXCEPTION USING ERRCODE = 'foreign_key_violation',
      MESSAGE = format('%s: annotation_id %s does not match %s.%s.%s.%s annotation %s (annotation_id %s)',
                       TG_TABLE_NAME, NEW.annotation_id, k_og, k_tech, k_date, k_code, k_ann, found);
  END IF;
  RETURN NEW;
END
$fn$;
COMMENT ON FUNCTION public.mito_child_annotation_id() IS
  'Fills or checks annotation_id on the LCA and ENA child tables from (og_id, tech, seq_date, code, '
  'annotation), and refuses a row that names no single annotation. 074, Phase R.7.';

-- annotation_id is derived from columns already in the hash, so it stays out of it.
CREATE OR REPLACE FUNCTION public.lca_set_content_hash() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $function$
BEGIN
    NEW.content_hash := md5(
        (to_jsonb(NEW) - 'lca_run_date' - 'og_num' - 'content_hash' - 'annotation_id')::text
    );
    RETURN NEW;
END $function$;

DO $r7$
DECLARE
  children text[] := ARRAY['lca','lca_raw_results','lca_validation','blast_filtered_lca',
                           'ena_validation_attempts','ena_submissions'];
  t text;
  n bigint;
  bad bigint;
  hash_before text;
  hash_raw_before text;
  readers_before bigint[];
  readers_after bigint[];
BEGIN
  -- Replay.
  SELECT count(*) INTO n FROM pg_constraint
   WHERE contype = 'f' AND convalidated AND confrelid = 'public.mito_annotation'::regclass
     AND conname = ANY (SELECT c || '_annotation_fkey' FROM unnest(children) c);
  IF n = array_length(children, 1) THEN
    RAISE NOTICE '074: all six annotation FKs present and validated; nothing to do';
    RETURN;
  END IF;

  IF coalesce(current_setting('oceanomics.r7_annotation_id', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'This adds annotation_id with an FK to mito_annotation on six tables, so a child '
      'row for an unknown annotation is refused from now on. Run with '
      'PGOPTIONS="-c oceanomics.r7_annotation_id=yes"';
  END IF;

  -- Every child row must resolve to exactly one annotation.
  FOREACH t IN ARRAY children LOOP
    EXECUTE format(
      'SELECT count(*) FROM %I c WHERE (SELECT count(*) FROM mito_annotation an '
      'JOIN mito_assembly a USING (assembly_id) WHERE a.og_id = c.og_id AND a.tech = c.tech '
      'AND a.seq_date = c.seq_date AND a.code = c.code AND an.annotation = c.annotation) <> 1', t)
      INTO bad;
    IF bad <> 0 THEN
      RAISE EXCEPTION '074: % row(s) in % do not resolve to exactly one annotation', bad, t;
    END IF;
  END LOOP;

  SELECT md5(string_agg(content_hash, ',' ORDER BY og_id, tech, seq_date, code, annotation, region, content_hash))
    INTO hash_before FROM lca;
  SELECT md5(string_agg(content_hash, ',' ORDER BY og_id, tech, seq_date, code, annotation, sequence_region,
                        accession_id, content_hash))
    INTO hash_raw_before FROM lca_raw_results;
  readers_before := ARRAY[(SELECT count(*) FROM summary), (SELECT count(*) FROM sample_view),
                          (SELECT count(*) FROM lca_validation_report_view),
                          (SELECT count(*) FROM embargo_assignment_view)];

  ALTER TABLE lca DISABLE TRIGGER lca_content_hash;
  ALTER TABLE lca_raw_results DISABLE TRIGGER lca_raw_results_content_hash;

  FOREACH t IN ARRAY children LOOP
    EXECUTE format('ALTER TABLE %I ADD COLUMN annotation_id bigint', t);
    EXECUTE format(
      'UPDATE %I c SET annotation_id = an.annotation_id FROM mito_annotation an '
      'JOIN mito_assembly a USING (assembly_id) WHERE a.og_id = c.og_id AND a.tech = c.tech '
      'AND a.seq_date = c.seq_date AND a.code = c.code AND an.annotation = c.annotation', t);
    EXECUTE format('SELECT count(*) FROM %I WHERE annotation_id IS NULL', t) INTO bad;
    IF bad <> 0 THEN
      RAISE EXCEPTION '074: % row(s) in % left without annotation_id', bad, t;
    END IF;
    EXECUTE format('ALTER TABLE %I ALTER COLUMN annotation_id SET NOT NULL', t);
    EXECUTE format('CREATE INDEX %I ON %I (annotation_id)', t || '_annotation_id_idx', t);
    EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (annotation_id) '
                   'REFERENCES mito_annotation (annotation_id) NOT VALID', t, t || '_annotation_fkey');
    EXECUTE format('ALTER TABLE %I VALIDATE CONSTRAINT %I', t, t || '_annotation_fkey');
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF %s ON %I FOR EACH ROW EXECUTE '
                   'FUNCTION mito_child_annotation_id()', t || '_annotation_id',
                   CASE WHEN t = 'ena_submissions' THEN 'full_seqid, annotation_id'
                        ELSE 'og_id, tech, seq_date, code, annotation, annotation_id' END, t);
    EXECUTE format('COMMENT ON COLUMN %I.annotation_id IS %L', t,
      'The mito_annotation this row describes. Filled from (og_id, tech, seq_date, code, annotation) '
      'by the ' || t || '_annotation_id trigger when a writer omits it; checked when one sends it. '
      '074, Phase R.7.');
  END LOOP;

  ALTER TABLE lca ENABLE TRIGGER lca_content_hash;
  ALTER TABLE lca_raw_results ENABLE TRIGGER lca_raw_results_content_hash;

  -- Verify.
  IF (SELECT md5(string_agg(content_hash, ',' ORDER BY og_id, tech, seq_date, code, annotation, region, content_hash)) FROM lca)
     IS DISTINCT FROM hash_before
     OR (SELECT md5(string_agg(content_hash, ',' ORDER BY og_id, tech, seq_date, code, annotation, sequence_region,
                               accession_id, content_hash)) FROM lca_raw_results)
     IS DISTINCT FROM hash_raw_before THEN
    RAISE EXCEPTION '074: a stored content_hash changed';
  END IF;
  SELECT count(*) INTO n FROM pg_constraint
   WHERE contype = 'f' AND convalidated AND confrelid = 'public.mito_annotation'::regclass
     AND conname = ANY (SELECT c || '_annotation_fkey' FROM unnest(children) c);
  IF n <> array_length(children, 1) THEN
    RAISE EXCEPTION '074: % of 6 annotation FKs validated', n;
  END IF;
  readers_after := ARRAY[(SELECT count(*) FROM summary), (SELECT count(*) FROM sample_view),
                         (SELECT count(*) FROM lca_validation_report_view),
                         (SELECT count(*) FROM embargo_assignment_view)];
  IF readers_after IS DISTINCT FROM readers_before THEN
    RAISE EXCEPTION '074: reader row counts changed: % -> %', readers_before, readers_after;
  END IF;
  -- A child row for an annotation that does not exist is refused.
  BEGIN
    INSERT INTO lca_validation (og_id, tech, seq_date, code, annotation)
    VALUES ('OG1', 'ilmn', '000000', 'probe074', 'none');
    RAISE EXCEPTION USING ERRCODE = 'P0074', MESSAGE = 'probe insert succeeded';
  EXCEPTION
    WHEN SQLSTATE 'P0074' THEN
      RAISE EXCEPTION '074: an lca_validation row for a missing annotation was accepted';
    WHEN foreign_key_violation THEN
      NULL;
  END;

  RAISE NOTICE '074: annotation_id added, backfilled and enforced on %', children;
END
$r7$;

COMMIT;
