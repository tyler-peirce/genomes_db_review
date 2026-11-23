-- Revert 092: put back coverage_summary's comment as 073 left it. Then delete 092's ledger row.
BEGIN;
COMMENT ON VIEW public.coverage_summary IS 'Coverage per OG from raw_qc, hifi_reads_qc and hic_reads_qc (the compatibility views). Replaced the public view of the same name at RG.6 (073); the old one is in pre_v4_archive.';
COMMIT;
