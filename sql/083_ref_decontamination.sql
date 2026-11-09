-- 083_ref_decontamination.sql -- What decontamination removed from each reference-genome haplotype.
--
-- Backlog Medium 9, Finding 17.5. The ref-genomes pipeline's DECONTAMINATION subworkflow runs
-- FCS-GX and then Tiara on each YaHS haplotype and drops what they flag, but nothing recorded how
-- much. The draft pipeline keeps the equivalent (num_contigs_*, bp_*).
--
-- One row per decontaminated part (stage 2, hap1 or hap2), like every per-tool ref_* table:
--   - input_*: the YaHS scaffolds the two tools were given.
--   - fcs_*: FCS-GX report rows by action; bp is end - start + 1 of each row. EXCLUDE and TRIM are
--     what FCSGX_CLEANGENOME removes; FIX and REVIEW are counted, not removed.
--   - tiara_*: the contigs TIARA_TIARA removes (its contig_removal rule): mitochondrion, plastid,
--     and prokarya / bacteria / archaea together as prokaryote. bp from the scaffold lengths. Tiara
--     classifies only contigs of 1 kb and more (-m 1000).
-- Writer: OceanOmics-OceanGenomes-ref-genomes scripts/03_compile_results/06_decontam_compile.py
-- (from scratch, or from the Acacia backups for the backfill), then 06a_push_decontam_results_to_sqldb.py
-- through scripts/lib/refdb.py. Not the module's tiara_filter_summary.txt: its bp column is always
-- 0 (it sums a len= field Tiara's report does not have).
--
-- Replay: CREATE ... IF NOT EXISTS; comments are re-set.
-- Revert: sql/revert/083_ref_decontamination_revert.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS ref_decontamination (
    part_id               bigint PRIMARY KEY REFERENCES ref_assembly_part ON DELETE CASCADE,
    input_seqs            integer,
    input_bp              bigint,
    fcs_exclude_seqs      integer,
    fcs_exclude_bp        bigint,
    fcs_trim_seqs         integer,
    fcs_trim_bp           bigint,
    fcs_fix_seqs          integer,
    fcs_review_seqs       integer,
    tiara_mito_seqs       integer,
    tiara_mito_bp         bigint,
    tiara_plastid_seqs    integer,
    tiara_plastid_bp      bigint,
    tiara_prokaryote_seqs integer,
    tiara_prokaryote_bp   bigint,
    loaded_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_decontamination_has_value CHECK (num_nonnulls(
      input_seqs, input_bp, fcs_exclude_seqs, fcs_exclude_bp, fcs_trim_seqs, fcs_trim_bp,
      fcs_fix_seqs, fcs_review_seqs, tiara_mito_seqs, tiara_mito_bp, tiara_plastid_seqs,
      tiara_plastid_bp, tiara_prokaryote_seqs, tiara_prokaryote_bp) > 0),
    CONSTRAINT ref_decontamination_non_negative CHECK (
      coalesce(least(input_seqs, fcs_exclude_seqs, fcs_trim_seqs, fcs_fix_seqs, fcs_review_seqs,
                     tiara_mito_seqs, tiara_plastid_seqs, tiara_prokaryote_seqs), 0) >= 0
      AND coalesce(least(input_bp, fcs_exclude_bp, fcs_trim_bp, tiara_mito_bp, tiara_plastid_bp,
                         tiara_prokaryote_bp), 0) >= 0)
);

COMMENT ON TABLE ref_decontamination IS
  'What decontamination removed from one haplotype (part at stage 2, hap1/hap2): FCS-GX actions and '
  'Tiara removals, with the YaHS input they were given. Written by the ref-genomes pipeline''s '
  '06_decontam_compile.py and 06a_push_decontam_results_to_sqldb.py (083).';
COMMENT ON COLUMN ref_decontamination.part_id IS 'The decontaminated part (stage 2, hap1 or hap2).';
COMMENT ON COLUMN ref_decontamination.input_seqs IS 'Scaffolds in the YaHS haplotype given to FCS-GX.';
COMMENT ON COLUMN ref_decontamination.input_bp IS 'Total length of those scaffolds, bp.';
COMMENT ON COLUMN ref_decontamination.fcs_exclude_seqs IS 'FCS-GX EXCLUDE: whole sequences removed as contamination.';
COMMENT ON COLUMN ref_decontamination.fcs_exclude_bp IS 'bp of the EXCLUDE rows (end - start + 1).';
COMMENT ON COLUMN ref_decontamination.fcs_trim_seqs IS 'FCS-GX TRIM: sequences with a contaminated end trimmed off (distinct sequences).';
COMMENT ON COLUMN ref_decontamination.fcs_trim_bp IS 'bp trimmed (end - start + 1 of the TRIM rows).';
COMMENT ON COLUMN ref_decontamination.fcs_fix_seqs IS 'FCS-GX FIX: sequences with an internal contaminated span (distinct sequences); counted, not removed by cleangenome.';
COMMENT ON COLUMN ref_decontamination.fcs_review_seqs IS 'FCS-GX REVIEW: sequences flagged for a look; not removed.';
COMMENT ON COLUMN ref_decontamination.tiara_mito_seqs IS 'Contigs Tiara classed mitochondrion and removed. These are mitogenome copies, not contamination.';
COMMENT ON COLUMN ref_decontamination.tiara_mito_bp IS 'Their total length, bp, from the YaHS scaffolds.';
COMMENT ON COLUMN ref_decontamination.tiara_plastid_seqs IS 'Contigs Tiara classed plastid and removed.';
COMMENT ON COLUMN ref_decontamination.tiara_plastid_bp IS 'Their total length, bp.';
COMMENT ON COLUMN ref_decontamination.tiara_prokaryote_seqs IS 'Contigs Tiara classed prokarya, bacteria or archaea and removed.';
COMMENT ON COLUMN ref_decontamination.tiara_prokaryote_bp IS 'Their total length, bp.';
COMMENT ON COLUMN ref_decontamination.loaded_at IS 'When this row was last written.';

COMMIT;
