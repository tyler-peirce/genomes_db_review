-- Verify genomes_db:create_v2_lab_tables on pg

BEGIN;

DO $$
DECLARE
  tbl text;
  row_count bigint;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'v2_sample', 'v2_tissue', 'v2_dna_extraction', 'v2_rna_extraction',
    'v2_hic_lysate', 'v2_illumina_library', 'v2_ont_library', 'v2_pacbio_library',
    'v2_hic_library', 'v2_rna_library_ilmn', 'v2_rna_library_kinx', 'v2_sequencing'
  ] LOOP
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

  -- Spot-check that the new gap-analysis columns landed on the right tables.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'v2_sample' AND column_name = 'cites'
  ) THEN
    RAISE EXCEPTION 'Missing expected column: v2_sample.cites';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'v2_hic_library' AND column_name = 'expected_distinct_30m_reads'
  ) THEN
    RAISE EXCEPTION 'Missing expected column: v2_hic_library.expected_distinct_30m_reads';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'v2_sequencing' AND column_name = 'hic_depth'
  ) THEN
    RAISE EXCEPTION 'Missing expected column: v2_sequencing.hic_depth';
  END IF;
END $$;

ROLLBACK;
