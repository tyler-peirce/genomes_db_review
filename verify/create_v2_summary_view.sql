-- Verify genomes_db:create_v2_summary_view on pg

-- The point of this view is that it replaces columns removed from v2.sample. So the useful
-- assertion is not "it exists" but "it produces every rollup that was removed", plus the
-- planned/actual pairs decision 9 exists to enable.

BEGIN;

DO $$
DECLARE
  col text;
BEGIN
  FOREACH col IN ARRAY ARRAY['summary', 'goat_species_v1'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.views
                   WHERE table_schema = 'v2' AND table_name = col) THEN
      RAISE EXCEPTION 'Missing expected view: v2.%', col;
    END IF;
    EXECUTE format('SELECT 1 FROM v2.%I LIMIT 1', col);   -- executes it, so a bad column fails here
  END LOOP;

  -- Every rollup removed from v2.sample must be recoverable here (decision 5, F5).
  FOREACH col IN ARRAY ARRAY[
    'tissues', 'extracted', 'dna_extraction_status', 'illumina_status', 'pacbio_status',
    'hic_status', 'nanopore_status', 'rna_extraction_status', 'rna_ilmn_status',
    'rna_kinnex_status'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = 'summary' AND column_name = col) THEN
      RAISE EXCEPTION 'v2.summary does not replace the removed sample column "%" (decision 5)', col;
    END IF;
  END LOOP;

  -- Planned/actual pairs (F5, decision 9).
  FOREACH col IN ARRAY ARRAY[
    'illumina_planned', 'illumina_actual', 'hifi_planned', 'hifi_actual',
    'hic_planned', 'hic_actual', 'nanopore_planned', 'nanopore_actual',
    'rna_planned', 'rna_actual', 'rna_ilmn_planned', 'rna_ilmn_actual'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = 'summary' AND column_name = col) THEN
      RAISE EXCEPTION 'v2.summary is missing % (F5 planned-vs-actual)', col;
    END IF;
  END LOOP;

  -- The dead Summary-sheet columns must not have reappeared under their old names.
  FOREACH col IN ARRAY ARRAY['summary_comments', 'illumina_sequencing', 'rna_kinnex_sequencing'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'v2' AND table_name = 'summary' AND column_name = col) THEN
      RAISE EXCEPTION 'v2.summary.% is a dead column that should not have been carried over (F4)', col;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
