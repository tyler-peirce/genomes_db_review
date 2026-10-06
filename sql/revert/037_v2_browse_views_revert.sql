-- Revert 037_v2_browse_views.sql.
--
-- Ported from design/v2/revert/create_v2_browse_views.sql. Run the v2 reverts in reverse order, 040 down
-- to 035. Like the other files in sql/revert/ this does not touch the ledger; afterwards
-- remove the row by hand:
--
--     DELETE FROM schema_migrations WHERE filename = '037_v2_browse_views.sql';
--
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
