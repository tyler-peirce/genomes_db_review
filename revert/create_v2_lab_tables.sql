-- Revert genomes_db:create_v2_lab_tables from pg

-- Rollback notes: safe at any point before the (future, separate) import/backfill work starts
-- populating these tables — they hold no data until then.
--
-- Dropped in reverse foreign-key dependency order, so no CASCADE is needed. No IF EXISTS: if a
-- table is already gone, or something unexpected depends on one, this should fail loudly
-- rather than quietly half-revert.

BEGIN;

DROP TABLE v2.sequencing;
DROP TABLE v2.rna_library_kinx;
DROP TABLE v2.rna_library_ilmn;
DROP TABLE v2.hic_library;
DROP TABLE v2.ont_library;
DROP TABLE v2.pacbio_library;
DROP TABLE v2.illumina_library;
DROP TABLE v2.library;
DROP TABLE v2.hic_lysate;
DROP TABLE v2.rna_extraction;
DROP TABLE v2.dna_extraction;
DROP TABLE v2.tissue;
DROP TABLE v2.sample;
DROP TABLE v2.prep_automation;

COMMIT;
