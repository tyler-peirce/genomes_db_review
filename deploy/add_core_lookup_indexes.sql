-- Deploy genomes_db:add_core_lookup_indexes to pg
-- no-transaction

-- Purpose: Add supporting indexes for core FK and og_id lookup columns identified in the database review.
-- Review source: database_review.md Finding 4.
-- Expected impact: Faster joins, parent updates/deletes, and reporting/API lookups without changing data semantics.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tissue_og_id
  ON tissue (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dna_extraction_tissue_id
  ON dna_extraction (tissue_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dna_extraction_og_id
  ON dna_extraction (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_extraction_tissue_id
  ON rna_extraction (tissue_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_extraction_og_id
  ON rna_extraction (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_illumina_library_dna_id
  ON illumina_library (dna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_illumina_library_og_id
  ON illumina_library (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pacbio_library_dna_id
  ON pacbio_library (dna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pacbio_library_og_id
  ON pacbio_library (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ont_library_dna_id
  ON ont_library (dna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ont_library_og_id
  ON ont_library (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hic_lysate_tissue_id
  ON hic_lysate (tissue_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hic_library_lysate_id
  ON hic_library (lysate_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hic_library_og_id
  ON hic_library (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_library_ilmn_rna_id
  ON rna_library_ilmn (rna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_library_ilmn_og_id
  ON rna_library_ilmn (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_library_kinx_rna_id
  ON rna_library_kinx (rna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_library_kinx_og_id
  ON rna_library_kinx (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sequencing_og_id
  ON sequencing (og_id);
