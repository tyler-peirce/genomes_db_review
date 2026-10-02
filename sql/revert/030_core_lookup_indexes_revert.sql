-- Revert 030_core_lookup_indexes.sql.
--
-- DROP INDEX CONCURRENTLY, for the same reason the forward migration uses
-- CREATE ... CONCURRENTLY: these tables take live writes. Like the forward file,
-- this one must NOT be wrapped in BEGIN/COMMIT.
--
-- Dropping these is safe for correctness -- they are performance-only, back no
-- constraint, and nothing references them by name. It will, however, return
-- summary and the per-sample lookups to their pre-030 plans.
--
-- If Finding 3's foreign keys have been added by the time this is run, do not
-- run it: those FKs depend on the child-side indexes here.

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
DROP INDEX CONCURRENTLY IF EXISTS idx_sequencing_illumina_library_tube_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_sequencing_pacbio_library_tube_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_sequencing_ont_library_tube_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_sequencing_hic_library_tube_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_ref_genomes_sra_uploads_og_id;
