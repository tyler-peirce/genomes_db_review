-- 058_v4_ref_read_qc_revert.sql -- remove the read-QC objects 058 built in v4.
--
-- v4 holds only copies until the RG.6 swap, so nothing is lost. 057's objects stay. Refuses while
-- 059's objects exist only because 059 is reverted first by convention; 059 does not use these.
--
-- After running this, delete 058's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '058_v4_ref_read_qc.sql';

BEGIN;

DO $revert$
BEGIN
  IF to_regclass('v4.ref_submission') IS NOT NULL THEN
    RAISE EXCEPTION 'v4 still holds 059 objects; revert 059 first';
  END IF;
END
$revert$;

DROP FUNCTION IF EXISTS v4.check_ref_read_qc();
DROP FUNCTION IF EXISTS v4.sync_ref_read_qc();
DROP VIEW IF EXISTS v4.v_read_qc_sequencing_readiness;
DROP VIEW IF EXISTS v4.coverage_summary;
DROP VIEW IF EXISTS v4.hic_reads_qc;
DROP VIEW IF EXISTS v4.hifi_reads_qc;
DROP VIEW IF EXISTS v4.raw_qc;
DROP VIEW IF EXISTS v4.sync_raw_qc_source;
DROP VIEW IF EXISTS v4.sync_read_qc_hic_source;
DROP VIEW IF EXISTS v4.sync_read_qc_hifi_source;
DROP TABLE IF EXISTS v4.hic_read_qc, v4.hifi_read_qc, v4.ref_hifi_adapter_filter, v4.ref_genomescope;
DELETE FROM v4.ref_excluded_rows WHERE source_table = 'raw_qc'
  AND og_id IN ('OG750_PD', 'OG90_bc2008', 'OG90ULI', 'OG760')
  AND seq_date IS NULL AND version IS NULL AND stage IS NULL AND haplotype IS NULL;

COMMIT;
