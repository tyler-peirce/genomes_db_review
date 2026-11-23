-- 092_coverage_summary_comment.sql -- coverage_summary's comment named pre_v4_archive, which 091
-- dropped. Comment only.
--
-- goat_species_v1's comment says the same, but GoaT is a colleague's (database_review.md §2), so
-- it is left for them.
-- Revert: sql/revert/092_coverage_summary_comment_revert.sql. Replay: the same COMMENT again.

BEGIN;
COMMENT ON VIEW public.coverage_summary IS 'Coverage per OG from raw_qc, hifi_reads_qc and hic_reads_qc (the compatibility views). Replaced the public view of the same name at RG.6 (073); the old one was in pre_v4_archive, dropped by 091 (copy: ~/oceanomics_genomes_archives_pre_091_261123.dump).';
COMMIT;
