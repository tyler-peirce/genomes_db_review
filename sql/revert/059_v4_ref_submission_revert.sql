-- 059_v4_ref_submission_revert.sql -- remove the submission objects 059 built in v4.
--
-- v4 holds only copies until the RG.6 swap, so nothing is lost. 057's and 058's objects stay.
--
-- After running this, delete 059's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '059_v4_ref_submission.sql';

BEGIN;

DROP FUNCTION IF EXISTS v4.check_ref_submission();
DROP FUNCTION IF EXISTS v4.sync_ref_submission();
DROP VIEW IF EXISTS v4.ref_genomes_sra_uploads;
DROP VIEW IF EXISTS v4.ref_genomes_assembly_uploads;
DROP VIEW IF EXISTS v4.sync_ref_sra_source;
DROP VIEW IF EXISTS v4.sync_ref_submission_source;
DROP TABLE IF EXISTS v4.ref_sra_upload, v4.ref_submission_haplotype, v4.ref_submission;

COMMIT;
