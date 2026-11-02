-- Revert 074_r7_child_annotation_id.sql: the six child tables lose annotation_id, its index, FK and
-- trigger; lca_set_content_hash() goes back to hashing without the annotation_id exclusion; the
-- trigger function is dropped. The column and the hash exclusion leave together, so stored hashes
-- (computed without annotation_id) still match what the restored function computes.
--
-- Opt-in:  PGOPTIONS="-c oceanomics.r7_revert=yes" psql -f sql/revert/074_r7_child_annotation_id_revert.sql
-- then delete 074's ledger row.

BEGIN;

DO $rv$
DECLARE
  t text;
BEGIN
  IF coalesce(current_setting('oceanomics.r7_revert', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'This removes annotation_id from the six mito child tables. Run with '
      'PGOPTIONS="-c oceanomics.r7_revert=yes"';
  END IF;
  FOREACH t IN ARRAY ARRAY['lca','lca_raw_results','lca_validation','blast_filtered_lca',
                           'ena_validation_attempts','ena_submissions'] LOOP
    EXECUTE format('DROP TRIGGER %I ON public.%I', t || '_annotation_id', t);
    EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', t, t || '_annotation_fkey');
    EXECUTE format('DROP INDEX public.%I', t || '_annotation_id_idx');
    EXECUTE format('ALTER TABLE public.%I DROP COLUMN annotation_id', t);
  END LOOP;
END
$rv$;

DROP FUNCTION public.mito_child_annotation_id();

-- lca_set_content_hash() as it was on live before 074 (pg_get_functiondef, 2026-11-02).
CREATE OR REPLACE FUNCTION public.lca_set_content_hash()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    NEW.content_hash := md5(
        (to_jsonb(NEW) - 'lca_run_date' - 'og_num' - 'content_hash')::text
    );
    RETURN NEW;
END $function$

;

COMMIT;
