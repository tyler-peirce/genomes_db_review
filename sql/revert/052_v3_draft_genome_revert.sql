-- 052_v3_draft_genome_revert.sql -- remove the draft-genome objects 052 built in v3.
--
-- v3 holds only copies until the R.6 merge, so nothing is lost. 051's objects stay. 053's
-- reverts do not depend on these.
--
-- After running this, delete 052's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '052_v3_draft_genome.sql';

BEGIN;

DROP FUNCTION IF EXISTS v3.check_draft();
DROP FUNCTION IF EXISTS v3.sync_draft();
DROP VIEW IF EXISTS v3.v_draft_genome_status;
DROP VIEW IF EXISTS v3.v_genome_size_comparison;
DROP VIEW IF EXISTS v3.draft_genomes;
DROP TABLE IF EXISTS v3.draft_submission, v3.draft_depthsizer, v3.draft_gfastats, v3.draft_merqury,
                     v3.draft_busco, v3.draft_contamination, v3.draft_tiara, v3.draft_genomescope,
                     v3.draft_fastp, v3.draft_genome_run, v3.draft_genome;
DROP FUNCTION IF EXISTS v3.draft_genome_run_illumina_only();

COMMIT;
