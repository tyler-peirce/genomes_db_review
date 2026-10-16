-- 052_v3_draft_genome.sql -- Phase R.3: the draft-genome tables in schema v3, beside public.
--
-- Why. public.draft_genomes is a dozen processes written sideways: each tool owns a block of
-- columns, and a tool that never ran leaves a block of NULLs that cannot say why
-- (docs/assembly_relations_plan.md §2.2, §4). This builds one identity table and one table per
-- process, split the way the pipeline writes them (OceanOmics-OceanGenomes-Draft-Genomes,
-- bin/draft_genome_stats.py FAMILY_COLUMNS):
--   draft_genome          one per (og_id, seq_date)
--   draft_genome_run      1..n: the Illumina sequencing rows it was built from
--   draft_fastp           fastp
--   draft_genomescope     GenomeScope2 summary + coverage summary, incl. host_assembly_size/
--                         _fraction; output_set says 'core' or 'extended' (newer columns)
--   draft_tiara           Tiara contig classification
--   draft_contamination   FCS-GX/BBMap exclude/trim/review, and num_contigs as
--                         num_contigs_lt_500bp (it is the count of contigs under 500 bp)
--   draft_busco           BUSCO, incl. its own assembly stats and internal stop codons
--   draft_merqury         Merqury QV + completeness
--   draft_gfastats        gfastats
--   draft_depthsizer      retired tool; loaded once, frozen (owner decision 12)
--   draft_submission      ENA-draft-genomes steps 06-07
-- and views:
--   v3.draft_genomes             compatibility: 103 kept columns in today's order
--   v3.v_genome_size_comparison  today's definition, on the new tables
--   v3.v_draft_genome_status     one row per draft, one flag per process (the owner's view)
--
-- A process row exists only where its block has a value, so a missing process is a missing
-- row (CHECK num_nonnulls > 0 on every process table).
--
-- Not carried (owner decision 14; plan §4.3): the 14 file columns (aws_*, fastp_r*, sra_r*,
-- historical), host_haploid_size and partition_confidence (no writer), sra_date_submitted
-- (never populated). They stay in public.draft_genomes until R.6 archives it.
--
-- draft_genome_run: Illumina only, instrument matching mach (NOVA -> NovaSeq,
-- NEXT -> NextSeq), which keeps out the iSEQ QC runs; 1,715 drafts get one run and 5 get two
-- (docs/assembly_relations_r0_record.md). A trigger rejects any non-Illumina sequencing row,
-- so a Hi-C "draft" like the 15 049 removed cannot be linked. ON DELETE CASCADE to
-- public.sequencing, so import_v2.py removing a stale row is never blocked; the sync re-derives.
--
-- draft_genome.og_id references public.sample. public.draft_genomes has no such FK, so during
-- the window a sample deletion that would orphan a draft is rejected (import_v2.py quarantines
-- that row). That is the intended relation, arriving early.
--
-- BUSCO's scaffold_n50 / contigs_n50 carry over unchanged, with comments saying they are not
-- reliable N50s (plan §4.2). The parser fix waits for R.0.4.
--
-- Sync and checks follow 051: v3.sync_draft() is the backfill and the nightly sync,
-- v3.check_draft() proves equality with public both ways. Both are window-only (dropped at
-- R.6). sync_draft never touches draft_depthsizer after the first load, and check_draft
-- asserts its row count.
--
-- Revert: sql/revert/052_v3_draft_genome_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v3.mito_assembly') IS NULL THEN
    RAISE EXCEPTION '052 needs schema v3 from 051';
  END IF;
END
$pre$;

CREATE TABLE IF NOT EXISTS v3.draft_genome (
    draft_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id      text NOT NULL REFERENCES public.sample (og_id),
    seq_date   text NOT NULL,     -- identifier component, not a date
    mach       text,              -- NOVA / NEXT, from the fastp file name
    initial    text,
    og_num     integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_genome_natural_key UNIQUE (og_id, seq_date)
);
COMMENT ON TABLE v3.draft_genome IS
  'One Illumina draft genome assembly. Written by OceanOmics-OceanGenomes-Draft-Genomes '
  'bin/draft_genome_stats.py.';

CREATE TABLE IF NOT EXISTS v3.draft_genome_run (
    draft_id      bigint NOT NULL REFERENCES v3.draft_genome ON DELETE CASCADE,
    sequencing_id text   NOT NULL REFERENCES public.sequencing (sequencing_id) ON DELETE CASCADE,
    PRIMARY KEY (draft_id, sequencing_id)
);
CREATE INDEX IF NOT EXISTS draft_genome_run_sequencing_id_idx ON v3.draft_genome_run (sequencing_id);
COMMENT ON TABLE v3.draft_genome_run IS
  'The Illumina sequencing rows a draft was built from. Illumina only (trigger).';

CREATE OR REPLACE FUNCTION v3.draft_genome_run_illumina_only() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  tech text;
BEGIN
  SELECT s.technology INTO tech FROM public.sequencing s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS DISTINCT FROM 'Illumina' THEN
    RAISE EXCEPTION 'draft_genome_run: % is % sequencing, not Illumina; a draft genome is an '
      'Illumina assembly', NEW.sequencing_id, coalesce(tech, 'unknown');
  END IF;
  RETURN NEW;
END
$fn$;
DROP TRIGGER IF EXISTS draft_genome_run_illumina_only ON v3.draft_genome_run;
CREATE TRIGGER draft_genome_run_illumina_only BEFORE INSERT OR UPDATE ON v3.draft_genome_run
  FOR EACH ROW EXECUTE FUNCTION v3.draft_genome_run_illumina_only();

CREATE TABLE IF NOT EXISTS v3.draft_fastp (
    draft_id                        bigint PRIMARY KEY REFERENCES v3.draft_genome ON DELETE CASCADE,
    passed_filter_reads             bigint,
    low_quality_reads               integer,
    too_many_n_reads                integer,
    too_short_reads                 integer,
    too_long_reads                  integer,
    raw_total_reads                 bigint,
    raw_total_bases                 bigint,
    raw_q20_bases                   bigint,
    raw_q30_bases                   bigint,
    raw_q20_rate                    numeric(7,6),
    raw_q30_rate                    numeric(7,6),
    raw_read1_mean_length           integer,
    raw_read2_mean_length           integer,
    raw_gc_content                  numeric(7,6),
    total_reads                     bigint,
    total_bases                     bigint,
    q20_bases                       bigint,
    q30_bases                       bigint,
    q20_rate                        numeric(7,6),
    q30_rate                        numeric(7,6),
    read1_mean_length               integer,
    read2_mean_length               integer,
    gc_content                      numeric(7,6),
    loaded_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_fastp_has_value CHECK (num_nonnulls(passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content) > 0)
);

CREATE TABLE IF NOT EXISTS v3.draft_genomescope (
    draft_id                        bigint PRIMARY KEY REFERENCES v3.draft_genome ON DELETE CASCADE,
    homozygosity                    numeric(8,4),
    heterozygosity                  numeric(8,4),
    genomesize                      bigint,
    repeatsize                      bigint,
    uniquesize                      bigint,
    modelfit                        numeric(8,4),
    errorrate                       numeric(8,4),
    homozygosity_min                numeric(8,4),
    heterozygosity_min              numeric(8,4),
    genomesize_min                  bigint,
    repeatsize_min                  bigint,
    uniquesize_min                  bigint,
    modelfit_allkmers               numeric(8,4),
    genome_size_reliable            boolean,
    genome_size_flags               text,
    kmercov                         numeric(10,4),
    lambda_depth                    numeric(10,4),
    host_assembly_size              bigint,
    host_assembly_fraction          numeric,
    output_set                      text GENERATED ALWAYS AS (CASE WHEN num_nonnulls(homozygosity_min, heterozygosity_min, genomesize_min, repeatsize_min, uniquesize_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth) > 0 THEN 'extended' ELSE 'core' END) STORED,
    loaded_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_genomescope_has_value CHECK (num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, homozygosity_min, heterozygosity_min, genomesize_min, repeatsize_min, uniquesize_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction) > 0)
);

CREATE TABLE IF NOT EXISTS v3.draft_tiara (
    draft_id                        bigint PRIMARY KEY REFERENCES v3.draft_genome ON DELETE CASCADE,
    num_contigs_mitochondrion       integer,
    num_contigs_plastid             integer,
    num_contigs_prokarya            integer,
    bp_mitochondrion                bigint,
    bp_plastid                      bigint,
    bp_prokarya                     bigint,
    loaded_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_tiara_has_value CHECK (num_nonnulls(num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya) > 0)
);

CREATE TABLE IF NOT EXISTS v3.draft_contamination (
    draft_id                        bigint PRIMARY KEY REFERENCES v3.draft_genome ON DELETE CASCADE,
    num_contigs_exclude             integer,
    num_contigs_trim                integer,
    num_contigs_review              integer,
    bp_exclude                      integer,
    bp_trim                         integer,
    bp_review                       integer,
    num_contigs_lt_500bp            integer,
    loaded_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_contamination_has_value CHECK (num_nonnulls(num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, num_contigs_lt_500bp) > 0)
);

CREATE TABLE IF NOT EXISTS v3.draft_busco (
    draft_id                        bigint PRIMARY KEY REFERENCES v3.draft_genome ON DELETE CASCADE,
    complete                        numeric(4,1),
    single_copy                     numeric(4,1),
    multi_copy                      numeric(4,1),
    fragmented                      numeric(4,1),
    missing                         numeric(4,1),
    n_markers                       integer,
    domain                          text,
    number_of_scaffolds             integer,
    number_of_contigs               integer,
    total_length                    bigint,
    percent_gaps                    numeric(5,2),
    scaffold_n50                    integer,
    contigs_n50                     integer,
    internal_stop_codon_count       bigint,
    internal_stop_codon_percent     numeric(5,2),
    loaded_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_busco_has_value CHECK (num_nonnulls(complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, internal_stop_codon_count, internal_stop_codon_percent) > 0)
);

CREATE TABLE IF NOT EXISTS v3.draft_merqury (
    draft_id                        bigint PRIMARY KEY REFERENCES v3.draft_genome ON DELETE CASCADE,
    unique_k_mers_assembly          bigint,
    k_mers_total                    bigint,
    qv                              numeric(6,4),
    error                           numeric(12,11),
    k_mer_set                       text,
    solid_k_mers                    bigint,
    total_k_mers                    bigint,
    completeness                    numeric(7,4),
    loaded_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_merqury_has_value CHECK (num_nonnulls(unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness) > 0)
);

CREATE TABLE IF NOT EXISTS v3.draft_gfastats (
    draft_id                        bigint PRIMARY KEY REFERENCES v3.draft_genome ON DELETE CASCADE,
    gfa_num_contigs                 bigint,
    gfa_contig_n50                  bigint,
    gfa_num_scaffolds               bigint,
    gfa_scaffold_n50                bigint,
    gfa_largest_scaffold            bigint,
    gfa_total_scaffold_length       bigint,
    gfa_gc_content_percent          numeric(10,2),
    loaded_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_gfastats_has_value CHECK (num_nonnulls(gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent) > 0)
);

CREATE TABLE IF NOT EXISTS v3.draft_depthsizer (
    draft_id                        bigint PRIMARY KEY REFERENCES v3.draft_genome ON DELETE CASCADE,
    depmethod                       text,
    adjust                          text,
    readbp                          bigint,
    mapadjust                       numeric(7,6),
    scdepth                         numeric(5,2),
    estgenomesize                   bigint,
    loaded_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_depthsizer_has_value CHECK (num_nonnulls(depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize) > 0)
);

CREATE TABLE IF NOT EXISTS v3.draft_submission (
    draft_id                        bigint PRIMARY KEY REFERENCES v3.draft_genome ON DELETE CASCADE,
    sra_accession                   character varying,
    biosample_accession             character varying,
    study                           character varying,
    bioproject_accession            character varying,
    ena_analysis_accession          text,
    assembly_accession              text,
    comment                         character varying,
    loaded_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_submission_has_value CHECK (num_nonnulls(sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment) > 0)
);

COMMENT ON TABLE v3.draft_fastp IS 'fastp read QC. Written by push_fastp_to_sqldb.py.';
COMMENT ON TABLE v3.draft_genomescope IS
  'GenomeScope2 fit and the coverage-summary verdict. Written by push_assembly_results_to_sqldb.py. '
  'output_set: extended where the newer columns were computed; core rows have them NULL by design.';
COMMENT ON TABLE v3.draft_tiara IS 'Tiara contig classification. Written by push_decontamination_results_to_sqldb.py.';
COMMENT ON TABLE v3.draft_contamination IS
  'FCS-GX contamination screen via BBMap filterbyname, and the count of contigs under 500 bp. '
  'Written by push_decontamination_results_to_sqldb.py.';
COMMENT ON COLUMN v3.draft_contamination.num_contigs_lt_500bp IS
  'Contigs under 500 bp (*contig_count_500bp.txt). Was draft_genomes.num_contigs.';
COMMENT ON TABLE v3.draft_busco IS
  'BUSCO, with BUSCO''s own assembly statistics and internal stop codons, from one short-summary '
  'JSON. Written by push_busco_results_to_sqldb.py.';
COMMENT ON COLUMN v3.draft_busco.scaffold_n50 IS
  'NOT a reliable N50: on most rows it behaves as an L50 (a contig count). Use '
  'draft_gfastats.gfa_scaffold_n50. docs/assembly_relations_plan.md §4.2.';
COMMENT ON COLUMN v3.draft_busco.contigs_n50 IS
  'NOT a reliable N50; see scaffold_n50. Use draft_gfastats.gfa_contig_n50.';
COMMENT ON TABLE v3.draft_merqury IS 'Merqury QV and k-mer completeness. Written by push_merqury_results_to_sqldb.py.';
COMMENT ON TABLE v3.draft_gfastats IS 'gfastats assembly statistics; the authoritative N50. Written by push_gfa_results_to_sqldb.py.';
COMMENT ON TABLE v3.draft_depthsizer IS
  'DepthSizer: RETIRED and CLOSED (owner decision 12, 2026-10-16). Loaded once from '
  'draft_genomes; no writer, no new rows.';
COMMENT ON TABLE v3.draft_submission IS 'Submission accessions. Written by ENA-draft-genomes steps 06-07.';

-- Sync (window-only: dropped at R.6) --------------------------------------------------------

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
  WHERE x.draft_id = g.draft_id AND num_nonnulls(p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction) = 0;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'draft_genomescope deleted'; changed := n; RETURN NEXT;
  INSERT INTO v3.draft_genomescope AS t (draft_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, homozygosity_min, heterozygosity_min, genomesize_min, repeatsize_min, uniquesize_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction)
  SELECT g.draft_id, p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction
  FROM public.draft_genomes p JOIN v3.draft_genome g USING (og_id, seq_date)
  WHERE num_nonnulls(p.homozygosity, p.heterozygosity, p.genomesize, p.repeatsize, p.uniquesize, p.modelfit, p.errorrate, p.homozygosity_min, p.heterozygosity_min, p.genomesize_min, p.repeatsize_min, p.uniquesize_min, p.modelfit_allkmers, p.genome_size_reliable, p.genome_size_flags, p.kmercov, p.lambda_depth, p.host_assembly_size, p.host_assembly_fraction) > 0
  ON CONFLICT (draft_id) DO UPDATE SET homozygosity = EXCLUDED.homozygosity, heterozygosity = EXCLUDED.heterozygosity, genomesize = EXCLUDED.genomesize, repeatsize = EXCLUDED.repeatsize, uniquesize = EXCLUDED.uniquesize, modelfit = EXCLUDED.modelfit, errorrate = EXCLUDED.errorrate, homozygosity_min = EXCLUDED.homozygosity_min, heterozygosity_min = EXCLUDED.heterozygosity_min, genomesize_min = EXCLUDED.genomesize_min, repeatsize_min = EXCLUDED.repeatsize_min, uniquesize_min = EXCLUDED.uniquesize_min, modelfit_allkmers = EXCLUDED.modelfit_allkmers, genome_size_reliable = EXCLUDED.genome_size_reliable, genome_size_flags = EXCLUDED.genome_size_flags, kmercov = EXCLUDED.kmercov, lambda_depth = EXCLUDED.lambda_depth, host_assembly_size = EXCLUDED.host_assembly_size, host_assembly_fraction = EXCLUDED.host_assembly_fraction, loaded_at = now()
    WHERE (t.homozygosity, t.heterozygosity, t.genomesize, t.repeatsize, t.uniquesize, t.modelfit, t.errorrate, t.homozygosity_min, t.heterozygosity_min, t.genomesize_min, t.repeatsize_min, t.uniquesize_min, t.modelfit_allkmers, t.genome_size_reliable, t.genome_size_flags, t.kmercov, t.lambda_depth, t.host_assembly_size, t.host_assembly_fraction) IS DISTINCT FROM (EXCLUDED.homozygosity, EXCLUDED.heterozygosity, EXCLUDED.genomesize, EXCLUDED.repeatsize, EXCLUDED.uniquesize, EXCLUDED.modelfit, EXCLUDED.errorrate, EXCLUDED.homozygosity_min, EXCLUDED.heterozygosity_min, EXCLUDED.genomesize_min, EXCLUDED.repeatsize_min, EXCLUDED.uniquesize_min, EXCLUDED.modelfit_allkmers, EXCLUDED.genome_size_reliable, EXCLUDED.genome_size_flags, EXCLUDED.kmercov, EXCLUDED.lambda_depth, EXCLUDED.host_assembly_size, EXCLUDED.host_assembly_fraction);
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
  WHERE s.technology = 'Illumina'
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
COMMENT ON FUNCTION v3.sync_draft() IS
  'Phase R window only: copy public.draft_genomes into the v3 tables, keyed on (og_id, seq_date). '
  'Loads draft_depthsizer only while it is empty. Dropped at the R.6 merge.';

-- Views -------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW v3.draft_genomes AS
SELECT
       d.og_id,
       d.mach,
       d.seq_date,
       d.initial,
       f.passed_filter_reads,
       f.low_quality_reads,
       f.too_many_n_reads,
       f.too_short_reads,
       f.too_long_reads,
       f.raw_total_reads,
       f.raw_total_bases,
       f.raw_q20_bases,
       f.raw_q30_bases,
       f.raw_q20_rate,
       f.raw_q30_rate,
       f.raw_read1_mean_length,
       f.raw_read2_mean_length,
       f.raw_gc_content,
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
       gs.heterozygosity,
       gs.genomesize,
       gs.repeatsize,
       gs.uniquesize,
       gs.modelfit,
       gs.errorrate,
       ct.num_contigs_lt_500bp AS num_contigs,
       ti.num_contigs_mitochondrion,
       ti.num_contigs_plastid,
       ti.num_contigs_prokarya,
       ti.bp_mitochondrion,
       ti.bp_plastid,
       ti.bp_prokarya,
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
       mq.unique_k_mers_assembly,
       mq.k_mers_total,
       mq.qv,
       mq.error,
       mq.k_mer_set,
       mq.solid_k_mers,
       mq.total_k_mers,
       mq.completeness,
       ds.depmethod,
       ds.adjust,
       ds.readbp,
       ds.mapadjust,
       ds.scdepth,
       ds.estgenomesize,
       su.sra_accession,
       su.biosample_accession,
       su.study,
       su.bioproject_accession,
       su.ena_analysis_accession,
       su.assembly_accession,
       su.comment,
       d.og_num,
       ct.num_contigs_exclude,
       ct.num_contigs_trim,
       ct.num_contigs_review,
       ct.bp_exclude,
       ct.bp_trim,
       ct.bp_review,
       gf.gfa_num_contigs,
       gf.gfa_contig_n50,
       gf.gfa_num_scaffolds,
       gf.gfa_scaffold_n50,
       gf.gfa_largest_scaffold,
       gf.gfa_total_scaffold_length,
       gf.gfa_gc_content_percent,
       b.internal_stop_codon_percent,
       b.internal_stop_codon_count,
       gs.genomesize_min,
       gs.repeatsize_min,
       gs.uniquesize_min,
       gs.homozygosity_min,
       gs.heterozygosity_min,
       gs.modelfit_allkmers,
       gs.genome_size_reliable,
       gs.genome_size_flags,
       gs.kmercov,
       gs.lambda_depth,
       gs.host_assembly_size,
       gs.host_assembly_fraction
FROM v3.draft_genome d
LEFT JOIN v3.draft_fastp f ON f.draft_id = d.draft_id
LEFT JOIN v3.draft_genomescope gs ON gs.draft_id = d.draft_id
LEFT JOIN v3.draft_tiara ti ON ti.draft_id = d.draft_id
LEFT JOIN v3.draft_contamination ct ON ct.draft_id = d.draft_id
LEFT JOIN v3.draft_busco b ON b.draft_id = d.draft_id
LEFT JOIN v3.draft_merqury mq ON mq.draft_id = d.draft_id
LEFT JOIN v3.draft_gfastats gf ON gf.draft_id = d.draft_id
LEFT JOIN v3.draft_depthsizer ds ON ds.draft_id = d.draft_id
LEFT JOIN v3.draft_submission su ON su.draft_id = d.draft_id;
COMMENT ON VIEW v3.draft_genomes IS
  'Compatibility view: the 103 kept columns of the old draft_genomes table, in its order. '
  'Not a write path.';

CREATE OR REPLACE VIEW v3.v_genome_size_comparison AS
SELECT d.og_id,
       d.seq_date,
       sp.species,
       sp.ncbi_taxon_id,
       gs.genomesize AS estimated_bp,
       a.total_sequence_length AS ncbi_bp,
       CASE WHEN a.total_sequence_length > 0
            THEN round(gs.genomesize::numeric / a.total_sequence_length::numeric, 3)
            ELSE NULL::numeric END AS estimated_over_ncbi,
       a.assembly_accession,
       a.assembly_level,
       a.is_refseq,
       a.is_representative
FROM v3.draft_genome d
LEFT JOIN v3.draft_genomescope gs ON gs.draft_id = d.draft_id
JOIN public.sample s ON s.og_id = d.og_id
JOIN public.species sp ON s.nominal_species_id = sp.species
LEFT JOIN public.species_ncbi_assembly a ON a.species = sp.species AND a.is_chosen;

CREATE OR REPLACE VIEW v3.v_draft_genome_status AS
SELECT d.og_num, d.og_id, d.seq_date, d.mach,
       (r.n_runs > 0)               AS has_run_link,
       (f.draft_id  IS NOT NULL)    AS has_fastp,
       (gs.draft_id IS NOT NULL)    AS has_genomescope,
       gs.output_set                AS genomescope_output_set,
       (ti.draft_id IS NOT NULL)    AS has_tiara,
       (ct.draft_id IS NOT NULL)    AS has_contamination,
       (b.draft_id  IS NOT NULL)    AS has_busco,
       (mq.draft_id IS NOT NULL)    AS has_merqury,
       (gf.draft_id IS NOT NULL)    AS has_gfastats,
       (su.draft_id IS NOT NULL)    AS has_submission,
       num_nonnulls(f.draft_id, gs.draft_id, ti.draft_id, ct.draft_id, b.draft_id, mq.draft_id,
                    gf.draft_id) AS processes_done,
       (f.draft_id IS NOT NULL AND num_nonnulls(gs.draft_id, ti.draft_id, ct.draft_id, b.draft_id,
                                                mq.draft_id, gf.draft_id) = 0) AS reads_only
FROM v3.draft_genome d
LEFT JOIN LATERAL (SELECT count(*) AS n_runs FROM v3.draft_genome_run x WHERE x.draft_id = d.draft_id) r ON true
LEFT JOIN v3.draft_fastp f          ON f.draft_id  = d.draft_id
LEFT JOIN v3.draft_genomescope gs   ON gs.draft_id = d.draft_id
LEFT JOIN v3.draft_tiara ti         ON ti.draft_id = d.draft_id
LEFT JOIN v3.draft_contamination ct ON ct.draft_id = d.draft_id
LEFT JOIN v3.draft_busco b          ON b.draft_id  = d.draft_id
LEFT JOIN v3.draft_merqury mq       ON mq.draft_id = d.draft_id
LEFT JOIN v3.draft_gfastats gf      ON gf.draft_id = d.draft_id
LEFT JOIN v3.draft_submission su    ON su.draft_id = d.draft_id;
COMMENT ON VIEW v3.v_draft_genome_status IS
  'One row per draft genome: which pipeline processes have results. processes_done counts the '
  'seven pipeline processes (fastp to gfastats); submission is shown but not counted; DepthSizer '
  'is retired and not shown.';

-- Checks (window-only: dropped at R.6) ------------------------------------------------------

CREATE OR REPLACE FUNCTION v3.check_draft() RETURNS TABLE (check_name text, problems bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  check_name := 'draft_genomes: v3 rows not in public';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction FROM v3.draft_genomes
    EXCEPT ALL
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction FROM public.draft_genomes) x;
  RETURN NEXT;

  check_name := 'draft_genomes: public rows not in v3';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction FROM public.draft_genomes
    EXCEPT ALL
    SELECT og_id, mach, seq_date, initial, passed_filter_reads, low_quality_reads, too_many_n_reads, too_short_reads, too_long_reads, raw_total_reads, raw_total_bases, raw_q20_bases, raw_q30_bases, raw_q20_rate, raw_q30_rate, raw_read1_mean_length, raw_read2_mean_length, raw_gc_content, total_reads, total_bases, q20_bases, q30_bases, q20_rate, q30_rate, read1_mean_length, read2_mean_length, gc_content, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, num_contigs, num_contigs_mitochondrion, num_contigs_plastid, num_contigs_prokarya, bp_mitochondrion, bp_plastid, bp_prokarya, complete, single_copy, multi_copy, fragmented, missing, n_markers, domain, number_of_scaffolds, number_of_contigs, total_length, percent_gaps, scaffold_n50, contigs_n50, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, depmethod, adjust, readbp, mapadjust, scdepth, estgenomesize, sra_accession, biosample_accession, study, bioproject_accession, ena_analysis_accession, assembly_accession, comment, og_num, num_contigs_exclude, num_contigs_trim, num_contigs_review, bp_exclude, bp_trim, bp_review, gfa_num_contigs, gfa_contig_n50, gfa_num_scaffolds, gfa_scaffold_n50, gfa_largest_scaffold, gfa_total_scaffold_length, gfa_gc_content_percent, internal_stop_codon_percent, internal_stop_codon_count, genomesize_min, repeatsize_min, uniquesize_min, homozygosity_min, heterozygosity_min, modelfit_allkmers, genome_size_reliable, genome_size_flags, kmercov, lambda_depth, host_assembly_size, host_assembly_fraction FROM v3.draft_genomes) x;
  RETURN NEXT;

  check_name := 'v_genome_size_comparison: differs (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v3.v_genome_size_comparison
                                EXCEPT ALL SELECT * FROM public.v_genome_size_comparison) x)
       + (SELECT count(*) FROM (SELECT * FROM public.v_genome_size_comparison
                                EXCEPT ALL SELECT * FROM v3.v_genome_size_comparison) x)
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

-- Backfill and verify -----------------------------------------------------------------------

SELECT * FROM v3.sync_draft();

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v3.check_draft() LOOP
    IF r.problems <> 0 THEN
      RAISE EXCEPTION '052 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
END
$verify$;

GRANT SELECT ON ALL TABLES IN SCHEMA v3 TO readonly;
GRANT SELECT ON v3.draft_genomes TO oceangenom_web;

COMMIT;
