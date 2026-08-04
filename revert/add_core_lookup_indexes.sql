-- Revert genomes_db:add_core_lookup_indexes from pg
-- no-transaction

DROP INDEX CONCURRENTLY IF EXISTS idx_tissue_og_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_dna_extraction_tissue_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_dna_extraction_og_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_rna_extraction_tissue_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_rna_extraction_og_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_illumina_library_dna_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_illumina_library_og_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_pacbio_library_dna_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_pacbio_library_og_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_ont_library_dna_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_ont_library_og_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_hic_lysate_tissue_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_hic_library_lysate_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_hic_library_og_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_rna_library_ilmn_rna_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_rna_library_ilmn_og_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_rna_library_kinx_rna_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_rna_library_kinx_og_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_sequencing_og_id;
