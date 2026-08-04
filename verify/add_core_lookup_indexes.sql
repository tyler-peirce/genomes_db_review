-- Verify genomes_db:add_core_lookup_indexes on pg

BEGIN;

DO $$
DECLARE
  expected text[] := ARRAY[
    'idx_tissue_og_id',
    'idx_dna_extraction_tissue_id',
    'idx_dna_extraction_og_id',
    'idx_rna_extraction_tissue_id',
    'idx_rna_extraction_og_id',
    'idx_illumina_library_dna_id',
    'idx_illumina_library_og_id',
    'idx_pacbio_library_dna_id',
    'idx_pacbio_library_og_id',
    'idx_ont_library_dna_id',
    'idx_ont_library_og_id',
    'idx_hic_lysate_tissue_id',
    'idx_hic_library_lysate_id',
    'idx_hic_library_og_id',
    'idx_rna_library_ilmn_rna_id',
    'idx_rna_library_ilmn_og_id',
    'idx_rna_library_kinx_rna_id',
    'idx_rna_library_kinx_og_id',
    'idx_sequencing_og_id'
  ];
  idx text;
BEGIN
  FOREACH idx IN ARRAY expected LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_indexes
      WHERE schemaname = 'public' AND indexname = idx
    ) THEN
      RAISE EXCEPTION 'Missing expected index: %', idx;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
