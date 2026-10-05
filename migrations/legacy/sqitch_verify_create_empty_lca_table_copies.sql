-- Verify genomes_db:create_empty_lca_table_copies on pg

BEGIN;

DO $$
DECLARE
  tbl text;
  row_count bigint;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['lca_new', 'lca_validation_new', 'lca_raw_results_new', 'blast_filtered_lca_new'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = tbl
    ) THEN
      RAISE EXCEPTION 'Missing expected table: %', tbl;
    END IF;

    EXECUTE format('SELECT count(*) FROM public.%I', tbl) INTO row_count;
    IF row_count != 0 THEN
      RAISE EXCEPTION 'Expected table % to be empty, found % rows', tbl, row_count;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
