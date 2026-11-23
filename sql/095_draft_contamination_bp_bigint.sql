-- 095_draft_contamination_bp_bigint.sql -- draft_contamination.bp_exclude, bp_trim and bp_review
-- become bigint.
--
-- Why. Owner, 2026-11-23. FCS-GX's report for OG348 230324 says EXCLUDE 570,688 contigs /
-- 2,313,565,842 bp, more than an integer holds (2,147,483,647). The 2026-11-18 FCS-GX backfill
-- (docs/draft_backfill_record.md, "FCS-GX columns") held OG348 out for this reason. A draft
-- assembly is a few Gb at most, so a bp count of excluded, trimmed or reviewed sequence can pass
-- 2^31 whenever most of an assembly is contaminant. The contig counts stay integer.
--
-- draft_genomes (056/067) reads the three columns, and PostgreSQL will not change the type of a
-- column a view reads, so the view is dropped and created again with the same definition (live
-- pg_get_viewdef, 2026-11-23), comment, owner and grants. Its three columns become bigint too. No
-- view depends on draft_genomes, and no function body names draft_contamination (checked
-- 2026-11-23). v_draft_genome_status reads only draft_contamination.draft_id and is not touched.
--
-- Rejected: numeric (bigint is what draft_tiara's bp_mitochondrion/plastid/prokarya already use);
-- storing OG348 as NULL (the report has the value).
--
-- Revert: sql/revert/095_draft_contamination_bp_bigint_revert.sql. It refuses while any value is
-- above the integer limit (OG348 once filled).
-- Replay: ALTER ... TYPE bigint on a bigint column does nothing; the view is created again as it was.

BEGIN;

DROP VIEW IF EXISTS public.draft_genomes;

ALTER TABLE public.draft_contamination
  ALTER COLUMN bp_exclude TYPE bigint,
  ALTER COLUMN bp_trim    TYPE bigint,
  ALTER COLUMN bp_review  TYPE bigint;

CREATE VIEW public.draft_genomes AS
 SELECT d.og_num,
    d.og_id,
    s.nominal_species_id,
    d.seq_date,
    d.mach,
    d.initial,
    f.raw_total_reads,
    f.raw_total_bases,
    f.raw_q20_bases,
    f.raw_q30_bases,
    f.raw_q20_rate,
    f.raw_q30_rate,
    f.raw_read1_mean_length,
    f.raw_read2_mean_length,
    f.raw_gc_content,
    f.passed_filter_reads,
    f.low_quality_reads,
    f.too_many_n_reads,
    f.too_short_reads,
    f.too_long_reads,
    f.total_reads,
    f.total_bases,
    f.q20_bases,
    f.q30_bases,
    f.q20_rate,
    f.q30_rate,
    f.read1_mean_length,
    f.read2_mean_length,
    f.gc_content,
    gs.homozygosity,
    gs.homozygosity_min,
    gs.heterozygosity,
    gs.heterozygosity_min,
    gs.repeatsize,
    gs.repeatsize_min,
    gs.uniquesize,
    gs.uniquesize_min,
    gs.modelfit,
    gs.modelfit_allkmers,
    gs.errorrate,
    gs.kmercov,
    gs.lambda_depth,
    gs.busco_read_depth,
    gs.busco_regions,
    gs.genomesize,
    gs.genomesize_min,
    gs.genomescope_fit,
    gs.genome_size_reliable,
    gs.genome_size_flags,
    gs.host_assembly_size,
    gs.host_assembly_fraction,
    gs.host_haploid_size,
    gs.partition_confidence,
    gs.partition_note,
    ti.num_contigs_mitochondrion,
    ti.num_contigs_plastid,
    ti.num_contigs_prokarya,
    ti.bp_mitochondrion,
    ti.bp_plastid,
    ti.bp_prokarya,
    ct.num_contigs_exclude,
    ct.num_contigs_trim,
    ct.num_contigs_review,
    ct.bp_exclude,
    ct.bp_trim,
    ct.bp_review,
    ct.num_contigs_lt_500bp AS num_contigs,
    b.complete,
    b.single_copy,
    b.multi_copy,
    b.fragmented,
    b.missing,
    b.n_markers,
    b.domain,
    b.number_of_scaffolds,
    b.number_of_contigs,
    b.total_length,
    b.percent_gaps,
    b.scaffold_n50,
    b.contigs_n50,
    b.internal_stop_codon_count,
    b.internal_stop_codon_percent,
    mq.unique_k_mers_assembly,
    mq.k_mers_total,
    mq.qv,
    mq.error,
    mq.k_mer_set,
    mq.solid_k_mers,
    mq.total_k_mers,
    mq.completeness,
    gf.gfa_num_contigs,
    gf.gfa_contig_n50,
    gf.gfa_num_scaffolds,
    gf.gfa_scaffold_n50,
    gf.gfa_largest_scaffold,
    gf.gfa_total_scaffold_length,
    gf.gfa_gc_content_percent,
    su.sra_accession,
    su.biosample_accession,
    su.study,
    su.bioproject_accession,
    su.ena_analysis_accession,
    su.assembly_accession,
    su.comment
   FROM draft_genome d
     JOIN sample s ON s.og_id = d.og_id
     LEFT JOIN draft_fastp f ON f.draft_id = d.draft_id
     LEFT JOIN draft_genomescope gs ON gs.draft_id = d.draft_id
     LEFT JOIN draft_tiara ti ON ti.draft_id = d.draft_id
     LEFT JOIN draft_contamination ct ON ct.draft_id = d.draft_id
     LEFT JOIN draft_busco b ON b.draft_id = d.draft_id
     LEFT JOIN draft_merqury mq ON mq.draft_id = d.draft_id
     LEFT JOIN draft_gfastats gf ON gf.draft_id = d.draft_id
     LEFT JOIN draft_submission su ON su.draft_id = d.draft_id;

ALTER VIEW public.draft_genomes OWNER TO postgres;
COMMENT ON VIEW public.draft_genomes IS 'Compatibility view: the kept columns of the old draft_genomes table plus nominal_species_id, grouped by process (056), plus the read depth and host partition columns (067). Read by column name, not position. DepthSizer (retired) is not shown; see draft_depthsizer. Not a write path: writers use draft_genome and its process tables.';
GRANT SELECT ON public.draft_genomes TO readonly;
GRANT SELECT ON public.draft_genomes TO oceangenom_web;

COMMIT;
