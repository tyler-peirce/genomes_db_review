-- 067_draft_depth_and_host_columns.sql -- the draft pipeline's read depth and host partition
-- columns, in public and in v3.
--
-- Why (database_review.md Finding 17; plan docs/r6_gate_plan.md, A.1).
--   1. host_haploid_size and partition_confidence have had a writer since draft pipeline 2de4e1e
--      (2026-10-14), and 261 rows on live. Owner decision 14 dropped them from v3 because "no
--      upload script pushes them", read from a clone 12 days behind origin/master. Reversed
--      2026-10-28: they go on v3.draft_genomescope beside host_assembly_size/_fraction.
--   2. The ENA COVERAGE for drafts falls back to total_bases / genomesize, which is not a coverage.
--      The pipeline measures read depth over Complete single-copy BUSCO genes (busco_mean_depth in
--      *_kmer_depth.json and the final *_coverage_summary.json) but uploads only lambda_depth,
--      which is that depth halved and scaled into k-mer space to cross-check GenomeScope.
--      busco_read_depth stores the depth itself. It measures what DepthSizer's scdepth measured
--      for drafts up to 250520, so ENA-draft-genomes can take one, then the other.
--   3. Three more values from the same files: genomescope_fit (whether the uploaded GenomeScope
--      numbers are the reseeded refit), busco_regions (how many genes the depth and the partition
--      rest on) and partition_note (why a partition is low confidence).
--
-- How. Until R.6 the production writer writes public.draft_genomes and v3.sync_draft() copies it
--   into v3 nightly; check_draft() compares the two by named column. So every new column goes into
--   both, and the invariant holds:
--   - public.draft_genomes gains busco_read_depth, genomescope_fit, busco_regions, partition_note.
--     host_haploid_size and partition_confidence are already there; they were added by hand before
--     2026-10-13 and are adopted here (comments, and the value checks below).
--   - v3.draft_genomescope gains all six. draft_genomescope_has_value counts them, so a draft with
--     only a depth still gets a row.
--   - partition_confidence is 'high' or 'low', and genomescope_fit 'original' or 'reseeded', in
--     both tables. On public the checks make a bad value fail at the writer rather than in the
--     nightly sync. All 261 live partition_confidence values pass.
--   - sync_draft() and check_draft() are replaced, with the six added to the genomescope block and
--     to both EXCEPT ALL arms. Their bodies are otherwise 055's and 056's, which match live.
--   - v3.draft_genomes is dropped and created (OR REPLACE cannot insert columns mid-list), grouped
--     as 056 does: depth beside lambda_depth, genomescope_fit with the genome size, the host
--     columns together. 98 -> 104 columns. Nothing depends on it (pg_depend, 2026-10-28); its
--     comment and the readonly and oceangenom_web grants are restored and checked.
--   - The migration runs sync_draft() once, which copies the 261 host values into v3. The new
--     depth columns are empty until the backfill (A.3) and the depth-only re-run (A.4).
--
-- Rejected: putting the new columns in v3 only. The production writer cannot reach v3 before R.6,
--   the sync would never carry them, and check_draft() would compare different column sets.
--
-- Revert: sql/revert/067_draft_depth_and_host_columns_revert.sql. It drops the four new public
--   columns with their values; take them from the pre-change dump if they matter by then.

BEGIN;

-- public.draft_genomes -----------------------------------------------------------------------

ALTER TABLE public.draft_genomes
  ADD COLUMN IF NOT EXISTS busco_read_depth numeric(10,4),
  ADD COLUMN IF NOT EXISTS genomescope_fit  text,
  ADD COLUMN IF NOT EXISTS busco_regions    integer,
  ADD COLUMN IF NOT EXISTS partition_note   text;

DO $checks$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.draft_genomes'::regclass
                 AND conname = 'draft_genomes_partition_confidence_check') THEN
    ALTER TABLE public.draft_genomes ADD CONSTRAINT draft_genomes_partition_confidence_check
      CHECK (partition_confidence IN ('high', 'low'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.draft_genomes'::regclass
                 AND conname = 'draft_genomes_genomescope_fit_check') THEN
    ALTER TABLE public.draft_genomes ADD CONSTRAINT draft_genomes_genomescope_fit_check
      CHECK (genomescope_fit IN ('original', 'reseeded'));
  END IF;
END
$checks$;

-- v3.draft_genomescope -----------------------------------------------------------------------

ALTER TABLE v3.draft_genomescope
  ADD COLUMN IF NOT EXISTS host_haploid_size    bigint,
  ADD COLUMN IF NOT EXISTS partition_confidence text,
  ADD COLUMN IF NOT EXISTS partition_note       text,
  ADD COLUMN IF NOT EXISTS busco_regions        integer,
  ADD COLUMN IF NOT EXISTS busco_read_depth     numeric(10,4),
  ADD COLUMN IF NOT EXISTS genomescope_fit      text;

DO $checks$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'v3.draft_genomescope'::regclass
                 AND conname = 'draft_genomescope_partition_confidence_check') THEN
    ALTER TABLE v3.draft_genomescope ADD CONSTRAINT draft_genomescope_partition_confidence_check
      CHECK (partition_confidence IN ('high', 'low'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'v3.draft_genomescope'::regclass
                 AND conname = 'draft_genomescope_genomescope_fit_check') THEN
    ALTER TABLE v3.draft_genomescope ADD CONSTRAINT draft_genomescope_genomescope_fit_check
      CHECK (genomescope_fit IN ('original', 'reseeded'));
  END IF;
END
$checks$;

ALTER TABLE v3.draft_genomescope DROP CONSTRAINT IF EXISTS draft_genomescope_has_value;
ALTER TABLE v3.draft_genomescope ADD CONSTRAINT draft_genomescope_has_value CHECK (num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, homozygosity_min, heterozygosity_min, genomesize_min, repeatsize_min, uniquesize_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit) > 0);

-- Column comments, the same text on both tables.
DO $comments$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['public.draft_genomes', 'v3.draft_genomescope'] LOOP
    EXECUTE format($c$COMMENT ON COLUMN %s.busco_read_depth IS %L$c$, t,
      'Mean per-base read depth over the Complete single-copy BUSCO genes (busco_mean_depth in '
      '*_kmer_depth.json, from MEASURE_KMER_COVERAGE). The sequencing depth of the host genome, '
      'and what ENA COVERAGE should carry; the successor to DepthSizer''s scdepth. Not '
      'lambda_depth, which is this halved and scaled into k-mer space.');
    EXECUTE format($c$COMMENT ON COLUMN %s.busco_regions IS %L$c$, t,
      'Number of Complete BUSCO regions busco_read_depth and the host partition were measured '
      'over (busco_regions in *_kmer_depth.json).');
    EXECUTE format($c$COMMENT ON COLUMN %s.genomescope_fit IS %L$c$, t,
      'original or reseeded: which GenomeScope fit genomesize, kmercov and the model fit come '
      'from (genomescope_fit in *_coverage_summary.json; GENOMESCOPE_RESEED keeps the refit only '
      'when it wins). NULL before the reseed existed.');
    EXECUTE format($c$COMMENT ON COLUMN %s.host_haploid_size IS %L$c$, t,
      'Host assembly mass with haplotype-split contigs (those at about half the host depth) '
      'counted once. A lower bound, like host_assembly_size. From *_kmer_depth.json.');
    EXECUTE format($c$COMMENT ON COLUMN %s.partition_confidence IS %L$c$, t,
      'high or low: whether the BUSCO depth anchor of the host partition can be trusted. Do not '
      'quote a host size from a low partition; partition_note says why it is low.');
    EXECUTE format($c$COMMENT ON COLUMN %s.partition_note IS %L$c$, t,
      'Why partition_confidence is low: few_busco_regions, no_dominant_mode or anchor_off_mode. '
      'NULL when it is high.');
  END LOOP;
END
$comments$;

-- sync_draft(): 055's body, with the six columns in the genomescope block --------------------

CREATE OR REPLACE FUNCTION v3.sync_draft() RETURNS TABLE (step text, changed bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  n             bigint;
  depthsizer_on boolean := NOT EXISTS (SELECT 1 FROM v3.draft_depthsizer);
BEGIN
  DELETE FROM v3.draft_genome g
  WHERE NOT EXISTS (SELECT 1 FROM public.draft_genomes p WHERE (p.og_id, p.seq_date) = (g.og_id, g.seq_date));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.draft_genome AS t (og_id, seq_date, mach, initial)
  SELECT og_id, seq_date, mach, initial FROM public.draft_genomes
  ON CONFLICT (og_id, seq_date) DO UPDATE SET mach = EXCLUDED.mach, initial = EXCLUDED.initial
    WHERE (t.mach, t.initial) IS DISTINCT FROM (EXCLUDED.mach, EXCLUDED.initial);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_fastp x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.passed_filter_reads, p.low_quality_reads, p.too_many_n_reads, p.too_short_reads, p.too_long_reads, p.raw_total_reads, p.raw_total_bases, p.raw_q20_bases, p.raw_q30_bases, p.raw_q20_rate, p.raw_q30_rate, p.raw_read1_mean_length, p.raw_read2_mean_length, p.raw_gc_content, p.total_reads, p.total_bases, p.q20_bases, p.q30_bases, p.q20_rate, p.q30_rate, p.read1_mean_length, p.read2_mean_length, p.gc_content) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_fastp deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_fastp AS t (draft_id, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content)
  SELECT g.draft_id, p.passed_filter_reads, p.low_quality_reads, p.too_many_n_reads, p.too_short_reads, p.too_long_reads, p.raw_total_reads, p.raw_total_bases, p.raw_q20_bases, p.raw_q30_bases, p.raw_q20_rate, p.raw_q30_rate, p.raw_read1_mean_length, p.raw_read2_mean_length, p.raw_gc_content, p.total_reads, p.total_bases, p.q20_bases, p.q30_bases, p.q20_rate, p.q30_rate, p.read1_mean_length, p.read2_mean_length, p.gc_content
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.passed_filter_reads, p.low_quality_reads, p.too_many_n_reads, p.too_short_reads, p.too_long_reads, p.raw_total_reads, p.raw_total_bases, p.raw_q20_bases, p.raw_q30_bases, p.raw_q20_rate, p.raw_q30_rate, p.raw_read1_mean_length, p.raw_read2_mean_length, p.raw_gc_content, p.total_reads, p.total_bases, p.q20_bases, p.q30_bases, p.q20_rate, p.q30_rate, p.read1_mean_length, p.read2_mean_length, p.gc_content) > 0
  ON CONFLICT (draft_id) DO UPDATE SET passed_filter_reads = EXCLUDED.passed_filter_reads, low_quality_reads = EXCLUDED.low_quality_reads, too_many_n_reads = EXCLUDED.too_many_n_reads, too_short_reads = EXCLUDED.too_short_reads, too_long_reads = EXCLUDED.too_long_reads, raw_total_reads = EXCLUDED.raw_total_reads, raw_total_bases = EXCLUDED.raw_total_bases, raw_q20_bases = EXCLUDED.raw_q20_bases, raw_q30_bases = EXCLUDED.raw_q30_bases, raw_q20_rate = EXCLUDED.raw_q20_rate, raw_q30_rate = EXCLUDED.raw_q30_rate, raw_read1_mean_length = EXCLUDED.raw_read1_mean_length, raw_read2_mean_length = EXCLUDED.raw_read2_mean_length, raw_gc_content = EXCLUDED.raw_gc_content, total_reads = EXCLUDED.total_reads, total_bases = EXCLUDED.total_bases, q20_bases = EXCLUDED.q20_bases, q30_bases = EXCLUDED.q30_bases, q20_rate = EXCLUDED.q20_rate, q30_rate = EXCLUDED.q30_rate, read1_mean_length = EXCLUDED.read1_mean_length, read2_mean_length = EXCLUDED.read2_mean_length, gc_content = EXCLUDED.gc_content, loaded_at = now()
    WHERE (t.passed_filter_reads, t.low_quality_reads, t.too_many_n_reads, t.too_short_reads, t.too_long_reads, t.raw_total_reads, t.raw_total_bases, t.raw_q20_bases, t.raw_q30_bases, t.raw_q20_rate, t.raw_q30_rate, t.raw_read1_mean_length, t.raw_read2_mean_length, t.raw_gc_content, t.total_reads, t.total_bases, t.q20_bases, t.q30_bases, t.q20_rate, t.q30_rate, t.read1_mean_length, t.read2_mean_length, t.gc_content) IS DISTINCT FROM (EXCLUDED.passed_filter_reads, EXCLUDED.low_quality_reads, EXCLUDED.too_many_n_reads, EXCLUDED.too_short_reads, EXCLUDED.too_long_reads, EXCLUDED.raw_total_reads, EXCLUDED.raw_total_bases, EXCLUDED.raw_q20_bases, EXCLUDED.raw_q30_bases, EXCLUDED.raw_q20_rate, EXCLUDED.raw_q30_rate, EXCLUDED.raw_read1_mean_length, EXCLUDED.raw_read2_mean_length, EXCLUDED.raw_gc_content, EXCLUDED.total_reads, EXCLUDED.total_bases, EXCLUDED.q20_bases, EXCLUDED.q30_bases, EXCLUDED.q20_rate, EXCLUDED.q30_rate, EXCLUDED.read1_mean_length, EXCLUDED.read2_mean_length, EXCLUDED.gc_content);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_fastp upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_genomescope x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction, p.host_haploid_size, p.partition_confidence, p.partition_note, p.busco_regions, p.busco_read_depth, p.genomescope_fit) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_genomescope deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_genomescope AS t (draft_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, homozygosity_min, heterozygosity_min, genomesize_min, repeatsize_min, uniquesize_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit)
  SELECT g.draft_id, p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction, p.host_haploid_size, p.partition_confidence, p.partition_note, p.busco_regions, p.busco_read_depth, p.genomescope_fit
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction, p.host_haploid_size, p.partition_confidence, p.partition_note, p.busco_regions, p.busco_read_depth, p.genomescope_fit) > 0
  ON CONFLICT (draft_id) DO UPDATE SET homozygosity = EXCLUDED.homozygosity, heterozygosity = EXCLUDED.heterozygosity, genomesize = EXCLUDED.genomesize, repeatsize = EXCLUDED.repeatsize, uniquesize = EXCLUDED.uniquesize, modelfit = EXCLUDED.modelfit, errorrate = EXCLUDED.errorrate, homozygosity_min = EXCLUDED.homozygosity_min, heterozygosity_min = EXCLUDED.heterozygosity_min, genomesize_min = EXCLUDED.genomesize_min, repeatsize_min = EXCLUDED.repeatsize_min, uniquesize_min = EXCLUDED.uniquesize_min, modelfit_allkmers = EXCLUDED.modelfit_allkmers, genome_size_reliable = EXCLUDED.genome_size_reliable, genome_size_flags = EXCLUDED.genome_size_flags, kmercov = EXCLUDED.kmercov, lambda_depth = EXCLUDED.lambda_depth, host_assembly_size = EXCLUDED.host_assembly_size, host_assembly_fraction = EXCLUDED.host_assembly_fraction, host_haploid_size = EXCLUDED.host_haploid_size, partition_confidence = EXCLUDED.partition_confidence, partition_note = EXCLUDED.partition_note, busco_regions = EXCLUDED.busco_regions, busco_read_depth = EXCLUDED.busco_read_depth, genomescope_fit = EXCLUDED.genomescope_fit, loaded_at = now()
    WHERE (t.homozygosity, t.heterozygosity, t.genomesize, t.repeatsize, t.uniquesize, t.modelfit, t.errorrate, t.homozygosity_min, t.heterozygosity_min, t.genomesize_min, t.repeatsize_min, t.uniquesize_min, t.modelfit_allkmers, t.genome_size_reliable, t.genome_size_flags, t.kmercov, t.lambda_depth, t.host_assembly_size, t.host_assembly_fraction, t.host_haploid_size, t.partition_confidence, t.partition_note, t.busco_regions, t.busco_read_depth, t.genomescope_fit) IS DISTINCT FROM (EXCLUDED.homozygosity, EXCLUDED.heterozygosity, EXCLUDED.genomesize, EXCLUDED.repeatsize, EXCLUDED.uniquesize, EXCLUDED.modelfit, EXCLUDED.errorrate, EXCLUDED.homozygosity_min, EXCLUDED.heterozygosity_min, EXCLUDED.genomesize_min, EXCLUDED.repeatsize_min, EXCLUDED.uniquesize_min, EXCLUDED.modelfit_allkmers, EXCLUDED.genome_size_reliable, EXCLUDED.genome_size_flags, EXCLUDED.kmercov, EXCLUDED.lambda_depth, EXCLUDED.host_assembly_size, EXCLUDED.host_assembly_fraction, EXCLUDED.host_haploid_size, EXCLUDED.partition_confidence, EXCLUDED.partition_note, EXCLUDED.busco_regions, EXCLUDED.busco_read_depth, EXCLUDED.genomescope_fit);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_genomescope upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_tiara x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.num_contigs_mitochondrion, p.num_contigs_plastid, p.num_contigs_prokarya, p.bp_mitochondrion, p.bp_plastid, p.bp_prokarya) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_tiara deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_tiara AS t (draft_id, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya)
  SELECT g.draft_id, p.num_contigs_mitochondrion, p.num_contigs_plastid, p.num_contigs_prokarya, p.bp_mitochondrion, p.bp_plastid, p.bp_prokarya
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.num_contigs_mitochondrion, p.num_contigs_plastid, p.num_contigs_prokarya, p.bp_mitochondrion, p.bp_plastid, p.bp_prokarya) > 0
  ON CONFLICT (draft_id) DO UPDATE SET num_contigs_mitochondrion = EXCLUDED.num_contigs_mitochondrion, num_contigs_plastid = EXCLUDED.num_contigs_plastid, num_contigs_prokarya = EXCLUDED.num_contigs_prokarya, bp_mitochondrion = EXCLUDED.bp_mitochondrion, bp_plastid = EXCLUDED.bp_plastid, bp_prokarya = EXCLUDED.bp_prokarya, loaded_at = now()
    WHERE (t.num_contigs_mitochondrion, t.num_contigs_plastid, t.num_contigs_prokarya, t.bp_mitochondrion, t.bp_plastid, t.bp_prokarya) IS DISTINCT FROM (EXCLUDED.num_contigs_mitochondrion, EXCLUDED.num_contigs_plastid, EXCLUDED.num_contigs_prokarya, EXCLUDED.bp_mitochondrion, EXCLUDED.bp_plastid, EXCLUDED.bp_prokarya);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_tiara upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_contamination x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.num_contigs_exclude, p.num_contigs_trim, p.num_contigs_review, p.bp_exclude, p.bp_trim, p.bp_review, p.num_contigs) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_contamination deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_contamination AS t (draft_id, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, num_contigs_lt_500bp)
  SELECT g.draft_id, p.num_contigs_exclude, p.num_contigs_trim, p.num_contigs_review, p.bp_exclude, p.bp_trim, p.bp_review, p.num_contigs
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.num_contigs_exclude, p.num_contigs_trim, p.num_contigs_review, p.bp_exclude, p.bp_trim, p.bp_review, p.num_contigs) > 0
  ON CONFLICT (draft_id) DO UPDATE SET num_contigs_exclude = EXCLUDED.num_contigs_exclude, num_contigs_trim = EXCLUDED.num_contigs_trim, num_contigs_review = EXCLUDED.num_contigs_review, bp_exclude = EXCLUDED.bp_exclude, bp_trim = EXCLUDED.bp_trim, bp_review = EXCLUDED.bp_review, num_contigs_lt_500bp = EXCLUDED.num_contigs_lt_500bp, loaded_at = now()
    WHERE (t.num_contigs_exclude, t.num_contigs_trim, t.num_contigs_review, t.bp_exclude, t.bp_trim, t.bp_review, t.num_contigs_lt_500bp) IS DISTINCT FROM (EXCLUDED.num_contigs_exclude, EXCLUDED.num_contigs_trim, EXCLUDED.num_contigs_review, EXCLUDED.bp_exclude, EXCLUDED.bp_trim, EXCLUDED.bp_review, EXCLUDED.num_contigs_lt_500bp);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_contamination upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_busco x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.complete, p.single_copy, p.multi_copy, p.fragmented, p.missing, p.n_markers, p.domain, p.number_of_scaffolds, p.number_of_contigs, p.total_length, p.percent_gaps, p.scaffold_n50, p.contigs_n50, p.internal_stop_codon_count, p.internal_stop_codon_percent) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_busco deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_busco AS t (draft_id, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, internal_stop_codon_count, internal_stop_codon_percent)
  SELECT g.draft_id, p.complete, p.single_copy, p.multi_copy, p.fragmented, p.missing, p.n_markers, p.domain, p.number_of_scaffolds, p.number_of_contigs, p.total_length, p.percent_gaps, p.scaffold_n50, p.contigs_n50, p.internal_stop_codon_count, p.internal_stop_codon_percent
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.complete, p.single_copy, p.multi_copy, p.fragmented, p.missing, p.n_markers, p.domain, p.number_of_scaffolds, p.number_of_contigs, p.total_length, p.percent_gaps, p.scaffold_n50, p.contigs_n50, p.internal_stop_codon_count, p.internal_stop_codon_percent) > 0
  ON CONFLICT (draft_id) DO UPDATE SET complete = EXCLUDED.complete, single_copy = EXCLUDED.single_copy, multi_copy = EXCLUDED.multi_copy, fragmented = EXCLUDED.fragmented, missing = EXCLUDED.missing, n_markers = EXCLUDED.n_markers, domain = EXCLUDED.domain, number_of_scaffolds = EXCLUDED.number_of_scaffolds, number_of_contigs = EXCLUDED.number_of_contigs, total_length = EXCLUDED.total_length, percent_gaps = EXCLUDED.percent_gaps, scaffold_n50 = EXCLUDED.scaffold_n50, contigs_n50 = EXCLUDED.contigs_n50, internal_stop_codon_count = EXCLUDED.internal_stop_codon_count, internal_stop_codon_percent = EXCLUDED.internal_stop_codon_percent, loaded_at = now()
    WHERE (t.complete, t.single_copy, t.multi_copy, t.fragmented, t.missing, t.n_markers, t.domain, t.number_of_scaffolds, t.number_of_contigs, t.total_length, t.percent_gaps, t.scaffold_n50, t.contigs_n50, t.internal_stop_codon_count, t.internal_stop_codon_percent) IS DISTINCT FROM (EXCLUDED.complete, EXCLUDED.single_copy, EXCLUDED.multi_copy, EXCLUDED.fragmented, EXCLUDED.missing, EXCLUDED.n_markers, EXCLUDED.domain, EXCLUDED.number_of_scaffolds, EXCLUDED.number_of_contigs, EXCLUDED.total_length, EXCLUDED.percent_gaps, EXCLUDED.scaffold_n50, EXCLUDED.contigs_n50, EXCLUDED.internal_stop_codon_count, EXCLUDED.internal_stop_codon_percent);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_busco upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_merqury x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.unique_k_mers_assembly, p.k_mers_total, p.qv, p.error, p.k_mer_set, p.solid_k_mers, p.total_k_mers, p.completeness) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_merqury deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_merqury AS t (draft_id, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness)
  SELECT g.draft_id, p.unique_k_mers_assembly, p.k_mers_total, p.qv, p.error, p.k_mer_set, p.solid_k_mers, p.total_k_mers, p.completeness
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.unique_k_mers_assembly, p.k_mers_total, p.qv, p.error, p.k_mer_set, p.solid_k_mers, p.total_k_mers, p.completeness) > 0
  ON CONFLICT (draft_id) DO UPDATE SET unique_k_mers_assembly = EXCLUDED.unique_k_mers_assembly, k_mers_total = EXCLUDED.k_mers_total, qv = EXCLUDED.qv, error = EXCLUDED.error, k_mer_set = EXCLUDED.k_mer_set, solid_k_mers = EXCLUDED.solid_k_mers, total_k_mers = EXCLUDED.total_k_mers, completeness = EXCLUDED.completeness, loaded_at = now()
    WHERE (t.unique_k_mers_assembly, t.k_mers_total, t.qv, t.error, t.k_mer_set, t.solid_k_mers, t.total_k_mers, t.completeness) IS DISTINCT FROM (EXCLUDED.unique_k_mers_assembly, EXCLUDED.k_mers_total, EXCLUDED.qv, EXCLUDED.error, EXCLUDED.k_mer_set, EXCLUDED.solid_k_mers, EXCLUDED.total_k_mers, EXCLUDED.completeness);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_merqury upserted'; changed := n; RETURN NEXT;

  DELETE FROM v3.draft_gfastats x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.gfa_num_contigs, p.gfa_contig_n50, p.gfa_num_scaffolds, p.gfa_scaffold_n50, p.gfa_largest_scaffold, p.gfa_total_scaffold_length, p.gfa_gc_content_percent) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_gfastats deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_gfastats AS t (draft_id, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent)
  SELECT g.draft_id, p.gfa_num_contigs, p.gfa_contig_n50, p.gfa_num_scaffolds, p.gfa_scaffold_n50, p.gfa_largest_scaffold, p.gfa_total_scaffold_length, p.gfa_gc_content_percent
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.gfa_num_contigs, p.gfa_contig_n50, p.gfa_num_scaffolds, p.gfa_scaffold_n50, p.gfa_largest_scaffold, p.gfa_total_scaffold_length, p.gfa_gc_content_percent) > 0
  ON CONFLICT (draft_id) DO UPDATE SET gfa_num_contigs = EXCLUDED.gfa_num_contigs, gfa_contig_n50 = EXCLUDED.gfa_contig_n50, gfa_num_scaffolds = EXCLUDED.gfa_num_scaffolds, gfa_scaffold_n50 = EXCLUDED.gfa_scaffold_n50, gfa_largest_scaffold = EXCLUDED.gfa_largest_scaffold, gfa_total_scaffold_length = EXCLUDED.gfa_total_scaffold_length, gfa_gc_content_percent = EXCLUDED.gfa_gc_content_percent, loaded_at = now()
    WHERE (t.gfa_num_contigs, t.gfa_contig_n50, t.gfa_num_scaffolds, t.gfa_scaffold_n50, t.gfa_largest_scaffold, t.gfa_total_scaffold_length, t.gfa_gc_content_percent) IS DISTINCT FROM (EXCLUDED.gfa_num_contigs, EXCLUDED.gfa_contig_n50, EXCLUDED.gfa_num_scaffolds, EXCLUDED.gfa_scaffold_n50, EXCLUDED.gfa_largest_scaffold, EXCLUDED.gfa_total_scaffold_length, EXCLUDED.gfa_gc_content_percent);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_gfastats upserted'; changed := n; RETURN NEXT;

  -- Frozen after the first load (owner decision 12).
  IF depthsizer_on THEN
  DELETE FROM v3.draft_depthsizer x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.depmethod, p.adjust, p.readbp, p.mapadjust, p.scdepth, p.estgenomesize) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_depthsizer deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_depthsizer AS t (draft_id, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize)
  SELECT g.draft_id, p.depmethod, p.adjust, p.readbp, p.mapadjust, p.scdepth, p.estgenomesize
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.depmethod, p.adjust, p.readbp, p.mapadjust, p.scdepth, p.estgenomesize) > 0
  ON CONFLICT (draft_id) DO UPDATE SET depmethod = EXCLUDED.depmethod, adjust = EXCLUDED.adjust, readbp = EXCLUDED.readbp, mapadjust = EXCLUDED.mapadjust, scdepth = EXCLUDED.scdepth, estgenomesize = EXCLUDED.estgenomesize, loaded_at = now()
    WHERE (t.depmethod, t.adjust, t.readbp, t.mapadjust, t.scdepth, t.estgenomesize) IS DISTINCT FROM (EXCLUDED.depmethod, EXCLUDED.adjust, EXCLUDED.readbp, EXCLUDED.mapadjust, EXCLUDED.scdepth, EXCLUDED.estgenomesize);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_depthsizer upserted'; changed := n; RETURN NEXT;
  END IF;

  DELETE FROM v3.draft_submission x USING v3.draft_genome g JOIN public.draft_genomes p USING (og_id, seq_date)
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.sra_accession, p.biosample_accession, p.study, p.bioproject_accession, p.ena_analysis_accession, p.assembly_accession, p.comment) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_submission deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_submission AS t (draft_id, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment)
  SELECT g.draft_id, p.sra_accession, p.biosample_accession, p.study, p.bioproject_accession, p.ena_analysis_accession, p.assembly_accession, p.comment
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.sra_accession, p.biosample_accession, p.study, p.bioproject_accession, p.ena_analysis_accession, p.assembly_accession, p.comment) > 0
  ON CONFLICT (draft_id) DO UPDATE SET sra_accession = EXCLUDED.sra_accession, biosample_accession = EXCLUDED.biosample_accession, study = EXCLUDED.study, bioproject_accession = EXCLUDED.bioproject_accession, ena_analysis_accession = EXCLUDED.ena_analysis_accession, assembly_accession = EXCLUDED.assembly_accession, comment = EXCLUDED.comment, loaded_at = now()
    WHERE (t.sra_accession, t.biosample_accession, t.study, t.bioproject_accession, t.ena_analysis_accession, t.assembly_accession, t.comment) IS DISTINCT FROM (EXCLUDED.sra_accession, EXCLUDED.biosample_accession, EXCLUDED.study, EXCLUDED.bioproject_accession, EXCLUDED.ena_analysis_accession, EXCLUDED.assembly_accession, EXCLUDED.comment);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_submission upserted'; changed := n; RETURN NEXT;

  -- Run links: derived, so replace what differs.
  CREATE TEMP TABLE IF NOT EXISTS sync_draft_run_want (draft_id bigint, sequencing_id text) ON COMMIT DROP;
  TRUNCATE sync_draft_run_want;
  INSERT INTO sync_draft_run_want
  SELECT DISTINCT g.draft_id, s.sequencing_id
  FROM v3.draft_genome g
  JOIN public.v_sequencing_browse s ON s.og_id = g.og_id AND s.seq_date = g.seq_date
  WHERE s.technology = 'Illumina' AND s.library_type = 'illumina'   -- DNA libraries only (055)
    AND s.instrument = CASE g.mach WHEN 'NOVA' THEN 'NovaSeq' WHEN 'NEXT' THEN 'NextSeq' END;

  DELETE FROM v3.draft_genome_run r
  WHERE NOT EXISTS (SELECT 1 FROM sync_draft_run_want w
                    WHERE (w.draft_id, w.sequencing_id) = (r.draft_id, r.sequencing_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.draft_genome_run (draft_id, sequencing_id)
  SELECT draft_id, sequencing_id FROM sync_draft_run_want
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link inserted'; changed := n; RETURN NEXT;
END
$fn$;

-- The view: 056's, with the six columns -----------------------------------------------------

DROP VIEW IF EXISTS v3.draft_genomes;

CREATE VIEW v3.draft_genomes AS
SELECT
       -- identification
       d.og_num,
       d.og_id,
       s.nominal_species_id,
       d.seq_date,
       d.mach,
       d.initial,
       -- fastp: raw reads
       f.raw_total_reads,
       f.raw_total_bases,
       f.raw_q20_bases,
       f.raw_q30_bases,
       f.raw_q20_rate,
       f.raw_q30_rate,
       f.raw_read1_mean_length,
       f.raw_read2_mean_length,
       f.raw_gc_content,
       -- fastp: filter results
       f.passed_filter_reads,
       f.low_quality_reads,
       f.too_many_n_reads,
       f.too_short_reads,
       f.too_long_reads,
       -- fastp: filtered reads
       f.total_reads,
       f.total_bases,
       f.q20_bases,
       f.q30_bases,
       f.q20_rate,
       f.q30_rate,
       f.read1_mean_length,
       f.read2_mean_length,
       f.gc_content,
       -- GenomeScope: each _min beside its pair
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
       -- read depth over Complete single-copy BUSCOs (067)
       gs.lambda_depth,
       gs.busco_read_depth,
       gs.busco_regions,
       -- GenomeScope: genome size
       gs.genomesize,
       gs.genomesize_min,
       gs.genomescope_fit,
       gs.genome_size_reliable,
       gs.genome_size_flags,
       -- host depth partition (067 adds the last three)
       gs.host_assembly_size,
       gs.host_assembly_fraction,
       gs.host_haploid_size,
       gs.partition_confidence,
       gs.partition_note,
       -- Tiara
       ti.num_contigs_mitochondrion,
       ti.num_contigs_plastid,
       ti.num_contigs_prokarya,
       ti.bp_mitochondrion,
       ti.bp_plastid,
       ti.bp_prokarya,
       -- contamination (FCS-GX / BBMap), and contigs under 500 bp
       ct.num_contigs_exclude,
       ct.num_contigs_trim,
       ct.num_contigs_review,
       ct.bp_exclude,
       ct.bp_trim,
       ct.bp_review,
       ct.num_contigs_lt_500bp AS num_contigs,
       -- BUSCO
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
       -- Merqury
       mq.unique_k_mers_assembly,
       mq.k_mers_total,
       mq.qv,
       mq.error,
       mq.k_mer_set,
       mq.solid_k_mers,
       mq.total_k_mers,
       mq.completeness,
       -- gfastats
       gf.gfa_num_contigs,
       gf.gfa_contig_n50,
       gf.gfa_num_scaffolds,
       gf.gfa_scaffold_n50,
       gf.gfa_largest_scaffold,
       gf.gfa_total_scaffold_length,
       gf.gfa_gc_content_percent,
       -- submission
       su.sra_accession,
       su.biosample_accession,
       su.study,
       su.bioproject_accession,
       su.ena_analysis_accession,
       su.assembly_accession,
       su.comment
FROM v3.draft_genome d
JOIN public.sample s ON s.og_id = d.og_id
LEFT JOIN v3.draft_fastp f ON f.draft_id = d.draft_id
LEFT JOIN v3.draft_genomescope gs ON gs.draft_id = d.draft_id
LEFT JOIN v3.draft_tiara ti ON ti.draft_id = d.draft_id
LEFT JOIN v3.draft_contamination ct ON ct.draft_id = d.draft_id
LEFT JOIN v3.draft_busco b ON b.draft_id = d.draft_id
LEFT JOIN v3.draft_merqury mq ON mq.draft_id = d.draft_id
LEFT JOIN v3.draft_gfastats gf ON gf.draft_id = d.draft_id
LEFT JOIN v3.draft_submission su ON su.draft_id = d.draft_id;
COMMENT ON VIEW v3.draft_genomes IS
  'Compatibility view: the kept columns of the old draft_genomes table plus nominal_species_id, '
  'grouped by process (056), plus the read depth and host partition columns (067). Read by '
  'column name, not position. DepthSizer (retired) is not shown; see v3.draft_depthsizer. Not a '
  'write path.';

GRANT SELECT ON v3.draft_genomes TO readonly;
GRANT SELECT ON v3.draft_genomes TO oceangenom_web;

-- check_draft(): 056's body, with the six columns in both EXCEPT ALL arms -------------------

CREATE OR REPLACE FUNCTION v3.check_draft() RETURNS TABLE (check_name text, problems bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  check_name := 'draft_genomes: v3 rows not in public';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit FROM v3.draft_genomes
    EXCEPT ALL
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit FROM public.draft_genomes) x;
  RETURN NEXT;

  check_name := 'draft_genomes: public rows not in v3';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit FROM public.draft_genomes
    EXCEPT ALL
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction, host_haploid_size, partition_confidence, partition_note, busco_regions, busco_read_depth, genomescope_fit FROM v3.draft_genomes) x;
  RETURN NEXT;

  check_name := 'v_genome_size_comparison: differs (either way)';
  SELECT (SELECT count(*) FROM (SELECT og_id, seq_date, species, ncbi_taxon_id, estimated_bp, ncbi_bp, estimated_over_ncbi, assembly_accession, assembly_level, is_refseq, is_representative FROM v3.v_genome_size_comparison
                                EXCEPT ALL SELECT og_id, seq_date, species, ncbi_taxon_id, estimated_bp, ncbi_bp, estimated_over_ncbi, assembly_accession, assembly_level, is_refseq, is_representative FROM public.v_genome_size_comparison) x)
       + (SELECT count(*) FROM (SELECT og_id, seq_date, species, ncbi_taxon_id, estimated_bp, ncbi_bp, estimated_over_ncbi, assembly_accession, assembly_level, is_refseq, is_representative FROM public.v_genome_size_comparison
                                EXCEPT ALL SELECT og_id, seq_date, species, ncbi_taxon_id, estimated_bp, ncbi_bp, estimated_over_ncbi, assembly_accession, assembly_level, is_refseq, is_representative FROM v3.v_genome_size_comparison) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'drafts with no Illumina run link';
  SELECT count(*) INTO problems FROM v3.draft_genome g
  WHERE NOT EXISTS (SELECT 1 FROM v3.draft_genome_run r WHERE r.draft_id = g.draft_id);
  RETURN NEXT;

  check_name := 'draft_depthsizer rows beyond the 701 loaded on 2026-10-16 (it is frozen)';
  SELECT greatest(count(*) - 701, 0) INTO problems FROM v3.draft_depthsizer;
  RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v3.check_draft() IS
  'Phase R window only: v3 draft tables against public, by key and value. Every problems value '
  'must be 0. Dropped at the R.6 merge.';

-- Copy the host values across, then verify ---------------------------------------------------

SELECT * FROM v3.sync_draft() WHERE changed <> 0;

DO $verify$
DECLARE
  r record;
  n_pub bigint;
  n_v3  bigint;
BEGIN
  FOR r IN SELECT * FROM v3.check_draft() LOOP
    IF r.problems <> 0 THEN
      RAISE EXCEPTION '067 check failed: %: %', r.check_name, r.problems;
    END IF;
  END LOOP;

  SELECT count(host_haploid_size) + count(partition_confidence) INTO n_pub FROM public.draft_genomes;
  SELECT count(host_haploid_size) + count(partition_confidence) INTO n_v3 FROM v3.draft_genomescope;
  IF n_pub <> n_v3 THEN
    RAISE EXCEPTION '067: host columns not carried to v3 (public %, v3 %)', n_pub, n_v3;
  END IF;

  IF (SELECT count(*) FROM information_schema.columns
       WHERE table_schema = 'v3' AND table_name = 'draft_genomes') <> 104
     OR (SELECT column_name FROM information_schema.columns
          WHERE table_schema = 'v3' AND table_name = 'draft_genomes' AND ordinal_position = 1)
        IS DISTINCT FROM 'og_num' THEN
    RAISE EXCEPTION '067: v3.draft_genomes should have 104 columns starting with og_num';
  END IF;

  IF NOT has_table_privilege('readonly', 'v3.draft_genomes', 'SELECT')
     OR NOT has_table_privilege('oceangenom_web', 'v3.draft_genomes', 'SELECT') THEN
    RAISE EXCEPTION '067: v3.draft_genomes lost a grant';
  END IF;

  IF (SELECT count(*) FROM v3.draft_genomes) <> (SELECT count(*) FROM public.draft_genomes) THEN
    RAISE EXCEPTION '067: v3.draft_genomes row count differs from public';
  END IF;

  RAISE NOTICE '067: % host values in each schema; view has 104 columns', n_pub;
END
$verify$;

COMMIT;
