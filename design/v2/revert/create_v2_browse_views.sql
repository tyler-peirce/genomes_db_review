-- Revert genomes_db:create_v2_browse_views from pg

-- v_sequencing_browse is dropped first: it selects from v_library_browse.

BEGIN;

DROP VIEW v2.v_sequencing_browse;
DROP VIEW v2.v_rna_library_kinx_browse;
DROP VIEW v2.v_rna_library_ilmn_browse;
DROP VIEW v2.v_hic_library_browse;
DROP VIEW v2.v_ont_library_browse;
DROP VIEW v2.v_pacbio_library_browse;
DROP VIEW v2.v_illumina_library_browse;
DROP VIEW v2.v_library_browse;
DROP VIEW v2.v_hic_lysate_browse;
DROP VIEW v2.v_rna_extraction_browse;
DROP VIEW v2.v_dna_extraction_browse;
DROP VIEW v2.v_tissue_browse;

COMMIT;
