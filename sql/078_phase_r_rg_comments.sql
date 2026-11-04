-- 078_phase_r_rg_comments.sql -- Comments on every column of the Phase R and RG tables, and the
-- table comments the merges left describing the window.
--
-- Record: docs/r_rg_docs_record.md.
--
-- Why. 051-077 gave all 46 draft_*, mito_*, ref_*, sequencing_run and *_read_qc tables a table
-- comment, but left 439 of their columns with none (2026-11-04). The column meanings are in the
-- writer scripts and the migration headers, which a reader of the database never sees. This
-- copies them in, each traced to one of:
--   OceanOmics-OceanGenomes-Draft-Genomes  origin/master       58353cf41815  bin/draft_genome_stats.py
--   Oceanomics-OceanGenomes-Mitogenomes    origin/inverts-dev  00aca11047a2  bin/push_*.py, mito_depth.py,
--                                                                            calculateLCA.py
--   OceanOmics-OceanGenomes-ref-genomes    origin/master       b330b008d39c  scripts/lib/refdb.py,
--                                                                            scripts/03_compile_results/
--   OceanOmics-OceanGenomes-post-curation  origin/master       36db0953e771  scripts/compile_results/
--   ENA-draft-genomes                      origin/main         c0f78fdaf14a  workflow/06, 07
--   ENA-ref-genomes                        origin/main         3f245cfb7e48  workflow/09, 10
--   ref_genomes_hic_automation             origin/main         4180383e79d3  push_hic_yield.py,
--                                                                            generate_hic_yield.py
--   OceanOmics-Database                    origin/main         547b53f21623  SS/import_data_lca_validation.py
-- The mito pipeline's default branch is inverts-dev, not master: master (b0cf5a325ef0,
-- 2026-09-07) still writes the pre-R names. Read the branch production runs.
--
-- Corrections, not just additions:
--   - mito_lca.taxon_rank_db / mito_lca_raw.taxon_rank_db: 017's comment said "taxonomic rank as
--     reported by the reference database". calculateLCA.py writes the taxonomy SOURCE the
--     lineage was taken from (fishbase, worms, ncbi), joined with ', ' on the LCA rows.
--   - mito_lca_raw.confidence_score / mito_lca.top_confidence_score: it is the BLAST e-value
--     (calculateLCA.py: 'confidence_score': evalue). Lower is better; 0 is the best possible.
--   - mito_assembly_run and ref_assembly_run: the window syncs derived them, and nothing has
--     written them since 072/073. Assemblies made after the merges have no run rows. Said so in
--     the table comments; the fix is a writer change, not this file.
--   - mito_blast_hit.subject_coverage holds BLAST qcovhsp (query cover per HSP), not a subject
--     coverage: it is the 21st field of calculateLCA.py's -outfmt, mapped by position.
--   - The table comments that still named v2./v3. objects or "live" vs "here".
--
-- Columns left uncommented on purpose: none. Where a value's meaning could not be traced past
-- its name, the comment says what it is known to hold and where it came from.
--
-- Comments only: no data, no structure. COMMENT ON replaces, so a replay is a no-op.
-- Revert: none needed (re-apply the earlier comments from 051-077 if ever wanted).

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('public.draft_genome') IS NULL OR to_regclass('public.ref_assembly') IS NULL
     OR to_regclass('public.mito_lca') IS NULL THEN
    RAISE EXCEPTION '078 needs the merged Phase R/RG tables (072, 073, 076)';
  END IF;
END
$pre$;

-- Draft genomes ------------------------------------------------------------------------------

COMMENT ON COLUMN draft_genome.draft_id IS 'Surrogate key. Every draft_* process table is keyed on it.';
COMMENT ON COLUMN draft_genome.og_id IS 'The sample (FK to sample).';
COMMENT ON COLUMN draft_genome.seq_date IS 'YYMMDD of the Illumina run the draft was built from. An identifier component, not a date: (og_id, seq_date) is the natural key.';
COMMENT ON COLUMN draft_genome.mach IS 'Sequencer code from the fastp file name (NOVA = NovaSeq, NEXT = NextSeq).';
COMMENT ON COLUMN draft_genome.initial IS 'Initials of the person who ran the sequencing, from the fastp file name (MACHINE_DATE_INITIAL).';
COMMENT ON COLUMN draft_genome.og_num IS 'Numeric part of og_id, for sorting. Generated.';
COMMENT ON COLUMN draft_genome.created_at IS 'When the row was first written (database clock).';

COMMENT ON TABLE draft_genome_run IS
  'The Illumina sequencing rows a draft was built from. Written by draft_genome_stats.py '
  'link_illumina_runs() on upload: Illumina rows of the OG on that seq_date whose instrument matches '
  'mach, so iSEQ QC runs are left out. Illumina only (trigger).';
COMMENT ON COLUMN draft_genome_run.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_genome_run.sequencing_id IS 'A sequencing row (library on a run) the draft''s reads came from (FK to sequencing).';

COMMENT ON COLUMN draft_fastp.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_fastp.passed_filter_reads IS 'Reads that passed fastp filtering (filtering_result).';
COMMENT ON COLUMN draft_fastp.low_quality_reads IS 'Reads removed for low base quality.';
COMMENT ON COLUMN draft_fastp.too_many_n_reads IS 'Reads removed for too many N bases.';
COMMENT ON COLUMN draft_fastp.too_short_reads IS 'Reads removed as shorter than the length limit.';
COMMENT ON COLUMN draft_fastp.too_long_reads IS 'Reads removed as longer than the length limit.';
COMMENT ON COLUMN draft_fastp.raw_total_reads IS 'Reads before filtering (summary.before_filtering). raw_* columns are before filtering; the unprefixed ones after.';
COMMENT ON COLUMN draft_fastp.raw_total_bases IS 'Bases before filtering.';
COMMENT ON COLUMN draft_fastp.raw_q20_bases IS 'Bases at Q20 or better, before filtering.';
COMMENT ON COLUMN draft_fastp.raw_q30_bases IS 'Bases at Q30 or better, before filtering.';
COMMENT ON COLUMN draft_fastp.raw_q20_rate IS 'Fraction (0-1, not %) of bases at Q20 or better, before filtering.';
COMMENT ON COLUMN draft_fastp.raw_q30_rate IS 'Fraction (0-1, not %) of bases at Q30 or better, before filtering.';
COMMENT ON COLUMN draft_fastp.raw_read1_mean_length IS 'Mean read 1 length in bp, before filtering.';
COMMENT ON COLUMN draft_fastp.raw_read2_mean_length IS 'Mean read 2 length in bp, before filtering.';
COMMENT ON COLUMN draft_fastp.raw_gc_content IS 'GC fraction (0-1, not %) before filtering.';
COMMENT ON COLUMN draft_fastp.total_reads IS 'Reads after filtering (summary.after_filtering).';
COMMENT ON COLUMN draft_fastp.total_bases IS 'Bases after filtering.';
COMMENT ON COLUMN draft_fastp.q20_bases IS 'Bases at Q20 or better, after filtering.';
COMMENT ON COLUMN draft_fastp.q30_bases IS 'Bases at Q30 or better, after filtering.';
COMMENT ON COLUMN draft_fastp.q20_rate IS 'Fraction (0-1, not %) of bases at Q20 or better, after filtering.';
COMMENT ON COLUMN draft_fastp.q30_rate IS 'Fraction (0-1, not %) of bases at Q30 or better, after filtering.';
COMMENT ON COLUMN draft_fastp.read1_mean_length IS 'Mean read 1 length in bp, after filtering.';
COMMENT ON COLUMN draft_fastp.read2_mean_length IS 'Mean read 2 length in bp, after filtering.';
COMMENT ON COLUMN draft_fastp.gc_content IS 'GC fraction (0-1, not %) after filtering.';
COMMENT ON COLUMN draft_fastp.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN draft_genomescope.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_genomescope.homozygosity IS 'GenomeScope2 homozygosity, %, upper value of its min/max pair. Rows written before numeric(8,4) are rounded to 2 places.';
COMMENT ON COLUMN draft_genomescope.heterozygosity IS 'GenomeScope2 heterozygosity, %, upper value. See heterozygosity_min for the lower.';
COMMENT ON COLUMN draft_genomescope.genomesize IS 'GenomeScope2 haploid genome length, bp, upper value. Only as good as the fit: check genome_size_reliable and genome_size_flags before quoting it.';
COMMENT ON COLUMN draft_genomescope.repeatsize IS 'GenomeScope2 repeat length, bp, upper value.';
COMMENT ON COLUMN draft_genomescope.uniquesize IS 'GenomeScope2 unique length, bp, upper value.';
COMMENT ON COLUMN draft_genomescope.modelfit IS 'GenomeScope2 model fit, %: the fit within the model''s own region (fullscore). Not the share of k-mers explained; that is modelfit_allkmers.';
COMMENT ON COLUMN draft_genomescope.errorrate IS 'GenomeScope2 read error rate, %.';
COMMENT ON COLUMN draft_genomescope.homozygosity_min IS 'GenomeScope2 homozygosity, %, lower value of its min/max pair. NULL on core rows.';
COMMENT ON COLUMN draft_genomescope.heterozygosity_min IS 'GenomeScope2 heterozygosity, %, lower value. NULL on core rows.';
COMMENT ON COLUMN draft_genomescope.genomesize_min IS 'GenomeScope2 haploid genome length, bp, lower value. NULL on core rows, or where the model diverged (Inf).';
COMMENT ON COLUMN draft_genomescope.repeatsize_min IS 'GenomeScope2 repeat length, bp, lower value.';
COMMENT ON COLUMN draft_genomescope.uniquesize_min IS 'GenomeScope2 unique length, bp, lower value.';
COMMENT ON COLUMN draft_genomescope.modelfit_allkmers IS 'GenomeScope2 model fit, %, as the share of all retained k-mers the model accounts for (allscore). GenomeScope prints it in the "min" column, but it is not a bound; it can be far below modelfit.';
COMMENT ON COLUMN draft_genomescope.genome_size_reliable IS 'The coverage-summary verdict on genomesize (*_coverage_summary.json). false: do not quote it; genome_size_flags says why. NULL on core rows.';
COMMENT ON COLUMN draft_genomescope.genome_size_flags IS '''; ''-joined reasons from the coverage summary, e.g. no_kmer_peak, degenerate_model_fit, genome_size_disagrees_with_assembly, host_coverage_too_low. NULL: none raised, or a core row.';
COMMENT ON COLUMN draft_genomescope.kmercov IS 'GenomeScope2 fitted k-mer coverage (kmercov; fitted_kmer_coverage in older summaries).';
COMMENT ON COLUMN draft_genomescope.lambda_depth IS 'busco_read_depth halved and put into k-mer space, for checking kmercov against the alignments. Not a sequencing depth: never send it as ENA COVERAGE.';
COMMENT ON COLUMN draft_genomescope.host_assembly_size IS 'Assembly bp at the host''s read depth, from per-contig depth. A lower bound: a symbiont at host depth counts as host, a high-copy host repeat does not.';
COMMENT ON COLUMN draft_genomescope.host_assembly_fraction IS 'host_assembly_size as a fraction (0-1) of the assembly length.';
COMMENT ON COLUMN draft_genomescope.output_set IS 'Generated: extended when any of the newer columns is set, otherwise core. Core rows predate them; their NULLs are not failures.';
COMMENT ON COLUMN draft_genomescope.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN draft_tiara.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_tiara.num_contigs_mitochondrion IS 'Contigs Tiara classed as mitochondrion.';
COMMENT ON COLUMN draft_tiara.num_contigs_plastid IS 'Contigs Tiara classed as plastid.';
COMMENT ON COLUMN draft_tiara.num_contigs_prokarya IS 'Contigs Tiara classed as prokarya (bacteria/archaea).';
COMMENT ON COLUMN draft_tiara.bp_mitochondrion IS 'bp in the mitochondrion contigs.';
COMMENT ON COLUMN draft_tiara.bp_plastid IS 'bp in the plastid contigs.';
COMMENT ON COLUMN draft_tiara.bp_prokarya IS 'bp in the prokarya contigs.';
COMMENT ON COLUMN draft_tiara.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN draft_contamination.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_contamination.num_contigs_exclude IS 'Contigs FCS-GX marked EXCLUDE (removed whole). 0 when the report had no EXCLUDE line.';
COMMENT ON COLUMN draft_contamination.num_contigs_trim IS 'Contigs FCS-GX marked TRIM (contaminant span cut out).';
COMMENT ON COLUMN draft_contamination.num_contigs_review IS 'Contigs FCS-GX marked REVIEW (left in, flagged).';
COMMENT ON COLUMN draft_contamination.bp_exclude IS 'bp in the EXCLUDE contigs.';
COMMENT ON COLUMN draft_contamination.bp_trim IS 'bp in the TRIM actions.';
COMMENT ON COLUMN draft_contamination.bp_review IS 'bp in the REVIEW contigs.';
COMMENT ON COLUMN draft_contamination.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON TABLE draft_busco IS
  'BUSCO, with BUSCO''s own assembly statistics and internal stop codons, from one short-summary JSON. '
  'Written by push_busco_results_to_sqldb.py. Its N50 columns are not reliable N50s; use draft_gfastats.';
COMMENT ON COLUMN draft_busco.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_busco.complete IS 'Complete BUSCOs, % of n_markers (single_copy + multi_copy).';
COMMENT ON COLUMN draft_busco.single_copy IS 'Complete single-copy BUSCOs, %.';
COMMENT ON COLUMN draft_busco.multi_copy IS 'Complete duplicated BUSCOs, %.';
COMMENT ON COLUMN draft_busco.fragmented IS 'Fragmented BUSCOs, %.';
COMMENT ON COLUMN draft_busco.missing IS 'Missing BUSCOs, %.';
COMMENT ON COLUMN draft_busco.n_markers IS 'Number of BUSCO markers in the lineage dataset searched.';
COMMENT ON COLUMN draft_busco.domain IS 'Domain BUSCO reports for the lineage (eukaryota on every row as of 2026-11).';
COMMENT ON COLUMN draft_busco.number_of_scaffolds IS 'BUSCO''s own scaffold count. gfastats is the authority (draft_gfastats.gfa_num_scaffolds).';
COMMENT ON COLUMN draft_busco.number_of_contigs IS 'BUSCO''s own contig count. Use draft_gfastats.gfa_num_contigs.';
COMMENT ON COLUMN draft_busco.total_length IS 'BUSCO''s own total assembly length, bp. Use draft_gfastats.gfa_total_scaffold_length.';
COMMENT ON COLUMN draft_busco.percent_gaps IS 'BUSCO''s own % of N bases.';
COMMENT ON COLUMN draft_busco.internal_stop_codon_count IS 'Complete BUSCO genes with an internal stop codon. NULL where the BUSCO version did not report it.';
COMMENT ON COLUMN draft_busco.internal_stop_codon_percent IS 'Those genes as % of complete BUSCOs. A high value points at frameshifts in the assembly.';
COMMENT ON COLUMN draft_busco.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN draft_merqury.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_merqury.unique_k_mers_assembly IS 'Merqury .qv: k-mers found only in the assembly, not in the reads (errors).';
COMMENT ON COLUMN draft_merqury.k_mers_total IS 'Merqury .qv: all k-mers in the assembly.';
COMMENT ON COLUMN draft_merqury.qv IS 'Merqury consensus quality value (Phred-scaled; higher is better).';
COMMENT ON COLUMN draft_merqury.error IS 'Merqury per-base error rate (the probability QV encodes).';
COMMENT ON COLUMN draft_merqury.k_mer_set IS 'Merqury completeness: which read k-mer set it was measured against (all on every row so far).';
COMMENT ON COLUMN draft_merqury.solid_k_mers IS 'Merqury completeness: solid read k-mers found in the assembly.';
COMMENT ON COLUMN draft_merqury.total_k_mers IS 'Merqury completeness: all solid read k-mers.';
COMMENT ON COLUMN draft_merqury.completeness IS 'Merqury k-mer completeness, % (solid_k_mers / total_k_mers).';
COMMENT ON COLUMN draft_merqury.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN draft_gfastats.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_gfastats.gfa_num_contigs IS 'gfastats # contigs.';
COMMENT ON COLUMN draft_gfastats.gfa_contig_n50 IS 'gfastats contig N50, bp. The authoritative contig N50 for a draft.';
COMMENT ON COLUMN draft_gfastats.gfa_num_scaffolds IS 'gfastats # scaffolds.';
COMMENT ON COLUMN draft_gfastats.gfa_scaffold_n50 IS 'gfastats scaffold N50, bp. The authoritative scaffold N50 for a draft.';
COMMENT ON COLUMN draft_gfastats.gfa_largest_scaffold IS 'gfastats largest scaffold, bp.';
COMMENT ON COLUMN draft_gfastats.gfa_total_scaffold_length IS 'gfastats total scaffold length, bp.';
COMMENT ON COLUMN draft_gfastats.gfa_gc_content_percent IS 'gfastats GC content, %.';
COMMENT ON COLUMN draft_gfastats.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN draft_depthsizer.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_depthsizer.depmethod IS 'DepthSizer depth method (mpileup on every row). Frozen historical value.';
COMMENT ON COLUMN draft_depthsizer.adjust IS 'DepthSizer read-length adjustment applied: IndelRatio, or blank/nan for none. Frozen.';
COMMENT ON COLUMN draft_depthsizer.readbp IS 'Total read bp DepthSizer sized the genome from. Frozen.';
COMMENT ON COLUMN draft_depthsizer.mapadjust IS 'DepthSizer mapping adjustment ratio (0-1). Frozen.';
COMMENT ON COLUMN draft_depthsizer.scdepth IS 'DepthSizer single-copy read depth. Succeeded by draft_genomescope.busco_read_depth (067). Frozen.';
COMMENT ON COLUMN draft_depthsizer.estgenomesize IS 'DepthSizer genome size estimate, bp. Frozen; not comparable with GenomeScope genomesize.';
COMMENT ON COLUMN draft_depthsizer.loaded_at IS 'When the row was loaded from draft_genomes (2026-10-16).';

COMMENT ON COLUMN draft_submission.draft_id IS 'The draft (FK to draft_genome).';
COMMENT ON COLUMN draft_submission.sra_accession IS 'Run accession(s) of the raw reads: ERR... from ENA-draft-genomes step 06 (comma-joined, one per lane), or SRR... from the earlier NCBI submissions. Blank-only writes.';
COMMENT ON COLUMN draft_submission.biosample_accession IS 'BioSample the reads and assembly were submitted under (SAMN.../SAMEA...). Step 06; blank-only.';
COMMENT ON COLUMN draft_submission.study IS 'SRA study (SRP...) of the earlier NCBI read submissions. Loaded from draft_genomes; no current writer.';
COMMENT ON COLUMN draft_submission.bioproject_accession IS 'BioProject of the earlier NCBI submissions (PRJNA1098793). Loaded from draft_genomes; step 06 deliberately does not write it, since both current BioProjects are constants.';
COMMENT ON COLUMN draft_submission.ena_analysis_accession IS 'ENA analysis (ERZ...) accession from the Webin-CLI assembly receipt. ENA-draft-genomes step 06; blank-only.';
COMMENT ON COLUMN draft_submission.assembly_accession IS 'Public INSDC assembly accession (GCA_...), filled once ENA processes the ERZ. ENA-draft-genomes step 07; blank-only, never overwritten. Older rows may hold NCBI JB... accessions.';
COMMENT ON COLUMN draft_submission.comment IS 'Free-text note from the old workbook (e.g. failed sequencing, files to remove from NCBI). 4 rows; no current writer.';
COMMENT ON COLUMN draft_submission.loaded_at IS 'When the row was last written (database clock).';

-- Mitogenomes --------------------------------------------------------------------------------

COMMENT ON TABLE mito_gene IS
  'Mitochondrial gene names. A new gene is an INSERT here plus rebuild_mito_gene_views(); gene is '
  'also the legacy length column name, and gene || ''_trans'' the translated-length one.';
COMMENT ON COLUMN mito_gene.gene IS 'Gene name as used in the legacy column names (cox1, nad4l, trna_leuuag, rrna12s).';
COMMENT ON COLUMN mito_gene.gene_class IS 'pcg (protein-coding), rrna or trna.';
COMMENT ON COLUMN mito_gene.sort_order IS 'Column order in v_mito_annotation_genes and the compatibility view.';
COMMENT ON COLUMN mito_gene.has_translation IS 'true for genes that also carry a translated length (<gene>_trans).';

COMMENT ON COLUMN mito_assembly.assembly_id IS 'Surrogate key. mito_annotation, depth, QC and run rows hang off it.';
COMMENT ON COLUMN mito_assembly.og_id IS 'The sample (FK to sample).';
COMMENT ON COLUMN mito_assembly.tech IS 'Reads the assembly used: ilmn, hifi or hic.';
COMMENT ON COLUMN mito_assembly.seq_date IS 'YYMMDD of the run the reads came from. An identifier component, not a date.';
COMMENT ON COLUMN mito_assembly.code IS 'Assembler and version, with any variant suffix: getorg1770, getorg1770reseed, getorg1770_mc, v323mitohifi, v10oatk... Part of the natural key (og_id, tech, seq_date, code).';
COMMENT ON COLUMN mito_assembly.stats IS 'Assembler result status as the pipeline records it: circular genome, scaffold, N scaffold(s), failed to assemble.';
COMMENT ON COLUMN mito_assembly.length IS 'Length of the assembled FASTA, bp. 0 when the assembly failed.';
COMMENT ON COLUMN mito_assembly.avg_coverage IS 'LEGACY, assembler-specific and NOT comparable across assemblers: k-mer coverage for GetOrganelle rows, reference-recruited read depth for MitoHiFi rows, NULL for Oatk (003). Use mito_assembly_depth.mean_depth.';
COMMENT ON COLUMN mito_assembly.avg_base_coverage IS 'LEGACY: GetOrganelle''s base coverage over its reduced read set, or MitoHiFi''s same single value as avg_coverage. Not comparable across assemblers (003).';
COMMENT ON COLUMN mito_assembly.created_at IS 'When the row was first written (database clock).';
COMMENT ON COLUMN mito_assembly.updated_at IS 'When the assembly result was last rewritten.';

COMMENT ON COLUMN mito_assembly_depth.assembly_id IS 'The assembly (FK to mito_assembly).';
COMMENT ON COLUMN mito_assembly_depth.depth_method IS 'remap_full_v1 = measured by remapping the full post-QC read set to this assembly (circular molecules folded on a doubled reference). not_measured = the step ran and measured nothing (the assembly never reached annotation, or the step was skipped); every other column is then NULL except depth_measured_at.';
COMMENT ON COLUMN mito_assembly_depth.mean_depth IS 'Mean per-base read depth of the sample''s own reads remapped to this assembly. Comparable across assemblers and technologies; use this, not mito_assembly.avg_coverage.';
COMMENT ON COLUMN mito_assembly_depth.median_depth IS 'Median per-base depth.';
COMMENT ON COLUMN mito_assembly_depth.depth_sd IS 'Standard deviation of per-base depth.';
COMMENT ON COLUMN mito_assembly_depth.depth_cv IS 'Coefficient of variation of per-base depth (depth_sd / mean_depth).';
COMMENT ON COLUMN mito_assembly_depth.breadth_1x IS 'Fraction (0-1) of target positions at depth >= 1.';
COMMENT ON COLUMN mito_assembly_depth.breadth_10x IS 'Fraction (0-1) of target positions at depth >= 10.';
COMMENT ON COLUMN mito_assembly_depth.mito_mapped_reads IS 'Primary alignments that passed the identity and clipping filters (mito_depth.py).';
COMMENT ON COLUMN mito_assembly_depth.total_reads IS 'Primary reads in the read set mapped.';
COMMENT ON COLUMN mito_assembly_depth.mito_read_fraction IS 'mito_mapped_reads / total_reads.';
COMMENT ON COLUMN mito_assembly_depth.depth_target_length_bp IS 'Length of the target the depth was measured over, bp (the monomer, when a circular target was doubled).';
COMMENT ON COLUMN mito_assembly_depth.depth_target_fasta IS 'File name of the FASTA the reads were mapped to.';
COMMENT ON COLUMN mito_assembly_depth.depth_measured_at IS 'When the depth step recorded its result, including a not_measured result.';

COMMENT ON TABLE mito_assembly_run IS
  'The sequencing rows (a library on a run) an assembly was built from, derived from (og_id, seq_date) '
  'and tech; ilmn excludes iSEQ QC runs. Derived by the Phase R window sync and loaded at the 072 merge. '
  'No writer has added rows since, so assemblies created after 2026-11-02 have none (078).';
COMMENT ON COLUMN mito_assembly_run.assembly_id IS 'The assembly (FK to mito_assembly).';
COMMENT ON COLUMN mito_assembly_run.sequencing_id IS 'A sequencing row the assembly''s reads came from (FK to sequencing).';

COMMENT ON COLUMN mito_assembly_qc.assembly_id IS 'The assembly (FK to mito_assembly).';

COMMENT ON COLUMN mito_annotation.annotation_id IS 'Surrogate key. LCA, BLAST, validation and ENA rows resolve to it with mito_annotation_id().';
COMMENT ON COLUMN mito_annotation.assembly_id IS 'The assembly annotated (FK to mito_assembly).';
COMMENT ON COLUMN mito_annotation.annotation IS 'Annotator and version: emma102, mitos2110, mito2110mc. Unique per assembly.';
COMMENT ON COLUMN mito_annotation.selected_by IS 'Who set is_selected. Required when it is true. Set by hand only.';
COMMENT ON COLUMN mito_annotation.selected_at IS 'When is_selected was set. Set by hand only.';
COMMENT ON COLUMN mito_annotation.length_emma IS 'Length of the annotated sequence, bp. Named for EMMA but filled for MITOS annotations too.';
COMMENT ON COLUMN mito_annotation.cds_no IS 'Protein-coding genes annotated.';
COMMENT ON COLUMN mito_annotation.trna_no IS 'tRNAs annotated.';
COMMENT ON COLUMN mito_annotation.rrna_no IS 'rRNAs annotated.';
COMMENT ON COLUMN mito_annotation.manual_curation_notes IS 'Free text from a curator: what was changed by hand, dated, and where the work is. NULL for most rows.';
COMMENT ON COLUMN mito_annotation.extra_genes IS 'Genes present beyond the expected set, '';''-joined. ''no'' or NULL: none.';
COMMENT ON COLUMN mito_annotation.missing_genes IS 'Expected genes absent, '';''-joined, judged against completeness_profile. ''no'' or NULL: none.';
COMMENT ON COLUMN mito_annotation.order_correct IS 'Gene order verdict: yes, no, variant (accepted by an order_variant rule), or NULL where not evaluated.';
COMMENT ON COLUMN mito_annotation.passed IS 'The annotation QC gate: yes or no. The only column evaluate_qc_conditions.py routes on.';
COMMENT ON COLUMN mito_annotation.trna_advisory IS 'tRNAs the QC gate waived (at most annotation_trna_tolerance, default 2), '';''-joined. ''no'' or NULL: none waived (021).';
COMMENT ON COLUMN mito_annotation.order_variant IS 'Id of the curated gene-order rule that accepted this order (e.g. scarine_imq); set only when order_correct = variant. ''no'' or NULL: none (023).';
COMMENT ON COLUMN mito_annotation.order_deviation IS 'For a rejected order, genes outside the longest common subsequence against the nearest accepted order. Text so it can carry ''no''. Advisory; never affects passed (023).';
COMMENT ON COLUMN mito_annotation.annotation_gaps IS 'Interior intergenic spans >= annotation_gap_threshold (default 50 bp), '';''-joined as ND4:11768-TS1:11982(213). Advisory (023).';
COMMENT ON COLUMN mito_annotation.order_variant_taxon_check IS 'Whether the BLAST LCA agrees with the rank an order_variant rule keyed on: agree, disagree:<taxon>, unresolved, or no (no rule fired). Must never become a gate (025).';
COMMENT ON COLUMN mito_annotation.order_status IS 'Kind of order deviation: reference, trna_displacement, rearranged_block, rearranged_major or not_evaluated (026). NULL: produced before 026.';
COMMENT ON COLUMN mito_annotation.order_deviation_detail IS 'The displaced elements, '';''-joined in EMMA gene codes (ND1;TA;TL2...). none: nothing displaced (026).';
COMMENT ON COLUMN mito_annotation.expected_lineage_genes IS 'Genes expected for this lineage outside the vertebrate set (e.g. atp9, mtMutS). none: no extra genes expected (026).';
COMMENT ON COLUMN mito_annotation.missing_expected_lineage_genes IS 'Which of expected_lineage_genes are absent. none: all present (026).';
COMMENT ON COLUMN mito_annotation.lineage_gene_advisories IS 'Advisory notes on the lineage genes. none: nothing to report (026).';
COMMENT ON COLUMN mito_annotation.mitos_unmapped_features IS 'MITOS features the MITOS-to-EMMA conversion could not map. none: all mapped (026).';
COMMENT ON COLUMN mito_annotation.mitos_known_auxiliary_features IS 'MITOS features kept but deliberately excluded from completeness scoring. none: no such features (026).';
COMMENT ON COLUMN mito_annotation.duplicate_loci IS 'Genes annotated more than once. none: no duplicates (026).';
COMMENT ON COLUMN mito_annotation.annotation_integrity_status IS 'ok, advisory, broken or not_evaluated: the final verdict on the published annotation after every repair branch merges. NULL means produced before 026, not clean.';
COMMENT ON COLUMN mito_annotation.annotation_integrity_issues IS 'What annotation_integrity_status rests on, '';''-joined (e.g. cds_convention:stop_codon_excluded(checked_from_gff)). none on a clean run; NULL before 026.';
COMMENT ON COLUMN mito_annotation.annotation_stats_version IS 'annotation_stats.py version that wrote the QC columns. NULL: written before 026.';
COMMENT ON COLUMN mito_annotation.annotation_updated_at IS 'When annotation_stats.py last refreshed the QC columns. A stale value means a rerun did not reach this row.';
COMMENT ON COLUMN mito_annotation.created_at IS 'When the row was first written (database clock).';
COMMENT ON COLUMN mito_annotation.updated_at IS 'When the row was last rewritten.';

COMMENT ON TABLE mito_annotation_gene IS
  'Per-gene lengths of one annotation. No row: the annotation has no value for that gene. Written by '
  'push_emma_annotation_results.py with its annotation.';
COMMENT ON COLUMN mito_annotation_gene.annotation_id IS 'The annotation (FK to mito_annotation).';
COMMENT ON COLUMN mito_annotation_gene.gene IS 'The gene (FK to mito_gene).';
COMMENT ON COLUMN mito_annotation_gene.length IS 'Annotated length of the gene, bp.';
COMMENT ON COLUMN mito_annotation_gene.translated_length IS 'Translated length, amino acids. Protein-coding genes only.';

COMMENT ON TABLE mito_lca IS
  'Lowest common ancestor calls per marker region, one row per annotation, region and result. Written by '
  'push_lca_blast_results.py (calculateLCA.py output). Row identity is content_hash, so a re-run with a '
  'changed answer adds a row; --force deletes the superseded ones.';
COMMENT ON COLUMN mito_lca.region IS 'Marker region: 12s, 16s, CO1...';
COMMENT ON COLUMN mito_lca.species_in_lca IS 'Every species the LCA was taken over, '', ''-joined.';
COMMENT ON COLUMN mito_lca.number_unq_blast_hits IS 'Unique BLAST hits the LCA was computed from.';
COMMENT ON COLUMN mito_lca.domain IS 'LCA lineage: domain.';
COMMENT ON COLUMN mito_lca.phylum IS 'LCA lineage: phylum.';
COMMENT ON COLUMN mito_lca.class IS 'LCA lineage: class.';
COMMENT ON COLUMN mito_lca."order" IS 'LCA lineage: order. Quote the column name.';
COMMENT ON COLUMN mito_lca.family IS 'LCA lineage: family.';
COMMENT ON COLUMN mito_lca.genus IS 'LCA lineage: genus.';
COMMENT ON COLUMN mito_lca.specific_epiphet IS 'LCA lineage: specific epithet (the column name''s spelling is a kept typo).';
COMMENT ON COLUMN mito_lca.species IS 'LCA species assignment (scientificName in the LCA output).';
COMMENT ON COLUMN mito_lca.scientific_name_authorship IS 'Authority for the name, parsed from the top hit''s label; ''not applicable: authorship info missing'' when absent.';
COMMENT ON COLUMN mito_lca.taxon_rank IS 'The rank the LCA resolved to: species, genus, family...';
COMMENT ON COLUMN mito_lca.top_taxon_id IS 'Taxon id of the top hit (BLAST staxids).';
COMMENT ON COLUMN mito_lca.taxon_id_db IS 'Where top_taxon_id comes from: NCBI (staxids are always NCBI Taxonomy), or NCBI:name-match.';
COMMENT ON COLUMN mito_lca.top_accession_id IS 'Accession of the top BLAST hit.';
COMMENT ON COLUMN mito_lca.accession_id_ref_db IS 'Reference database inferred from top_accession_id''s format: GenBank, DDBJ, BOLD, NBDL, OG (our own), or unknown.';
COMMENT ON COLUMN mito_lca.taxon_rank_db IS 'Taxonomy source(s) the lineage was taken from, '', ''-joined: fishbase, worms, ncbi. Not a rank, whatever the name (017''s comment was wrong).';
COMMENT ON COLUMN mito_lca.top_percent_query_cover IS 'Query cover of the top hit, %.';
COMMENT ON COLUMN mito_lca.top_percent_query_cover_hsp IS 'Query cover of the top hit''s HSP, %.';
COMMENT ON COLUMN mito_lca.alignment_length IS 'Alignment length of the top hit, bp.';
COMMENT ON COLUMN mito_lca.subject_length IS 'Length of the top hit''s subject sequence, bp.';
COMMENT ON COLUMN mito_lca.sequence_length IS 'Length of the query region sequence, bp.';
COMMENT ON COLUMN mito_lca.top_confidence_score IS 'The top hit''s BLAST e-value (calculateLCA.py stores evalue under this name). Lower is better; 0 is the best possible. double precision: values reach ~1e-163.';
COMMENT ON COLUMN mito_lca.top_percent_match IS 'Percent identity of the top hit.';

COMMENT ON TABLE mito_lca_raw IS
  'Every BLAST hit that fed an LCA call, per annotation and region (unfiltered LCA output). Written by '
  'push_lca_raw_results.py. Row identity includes content_hash: one accession can give several HSPs in '
  'one run.';
COMMENT ON COLUMN mito_lca_raw.content_hash IS
  'md5 of the row content, maintained by the mito_lca_raw_content_hash trigger. Part of the key because '
  'one BLAST accession can yield several HSPs in a single run, which share accession and run date but '
  'differ in percent_match. Never in an INSERT or UPDATE column list.';
COMMENT ON COLUMN mito_lca_raw.sequence_region IS 'Marker region: 12s, 16s, CO1...';
COMMENT ON COLUMN mito_lca_raw.lca_run_date IS 'YYMMDD the LCA ran, as text (also text on mito_lca).';
COMMENT ON COLUMN mito_lca_raw.domain IS 'Hit lineage: domain.';
COMMENT ON COLUMN mito_lca_raw.phylum IS 'Hit lineage: phylum.';
COMMENT ON COLUMN mito_lca_raw.class IS 'Hit lineage: class.';
COMMENT ON COLUMN mito_lca_raw."order" IS 'Hit lineage: order. Quote the column name.';
COMMENT ON COLUMN mito_lca_raw.family IS 'Hit lineage: family.';
COMMENT ON COLUMN mito_lca_raw.genus IS 'Hit lineage: genus.';
COMMENT ON COLUMN mito_lca_raw.specific_epiphet IS 'Hit lineage: specific epithet (kept typo in the name).';
COMMENT ON COLUMN mito_lca_raw.scientific_name IS 'The hit''s species name.';
COMMENT ON COLUMN mito_lca_raw.scientific_name_authorship IS 'Authority for the name, parsed from the hit label.';
COMMENT ON COLUMN mito_lca_raw.taxon_rank IS 'Rank of the hit''s name: species, genus...';
COMMENT ON COLUMN mito_lca_raw.taxon_id IS 'Taxon id of the hit (BLAST staxids).';
COMMENT ON COLUMN mito_lca_raw.taxon_id_db IS 'Where taxon_id comes from: NCBI, or NCBI:name-match.';
COMMENT ON COLUMN mito_lca_raw.verbatim_identification IS 'The subject''s FASTA label as BLAST returned it, e.g. [organism=Galeocerdo cuvier] ... mitochondrion, complete genome.';
COMMENT ON COLUMN mito_lca_raw.accession_id IS 'Accession of the hit.';
COMMENT ON COLUMN mito_lca_raw.accession_id_ref_db IS 'Reference database inferred from accession_id''s format: GenBank, DDBJ, BOLD, NBDL, OG, unknown.';
COMMENT ON COLUMN mito_lca_raw.percent_match IS 'Percent identity of the hit.';
COMMENT ON COLUMN mito_lca_raw.percent_query_cover IS 'Query cover, %.';
COMMENT ON COLUMN mito_lca_raw.percent_query_cover_hsp IS 'Query cover of the HSP, %.';
COMMENT ON COLUMN mito_lca_raw.alignment_length IS 'Alignment length, bp.';
COMMENT ON COLUMN mito_lca_raw.subject_length IS 'Subject sequence length, bp.';
COMMENT ON COLUMN mito_lca_raw.sequence_length IS 'Query region sequence length, bp.';
COMMENT ON COLUMN mito_lca_raw.confidence_score IS 'The hit''s BLAST e-value (calculateLCA.py stores evalue under this name). Lower is better. double precision: values reach ~1e-163; do not narrow it to real.';
COMMENT ON COLUMN mito_lca_raw.taxon_rank_db IS 'Taxonomy source the hit''s lineage was taken from: fishbase, worms or ncbi. Not a rank, whatever the name.';

COMMENT ON TABLE mito_blast_hit IS
  'BLAST hits retained after LCA filtering, one row per matched sequence and region. Written by '
  'push_lca_blast_results.py.';
COMMENT ON COLUMN mito_blast_hit.match_sequence_id IS 'Accession of the matched subject sequence.';
COMMENT ON COLUMN mito_blast_hit.taxon_id IS 'BLAST staxids for the match, verbatim. Usually one NCBI taxon id, but a '';''-joined list when the accession is registered under several taxa: cast it before using it as a number (022).';
COMMENT ON COLUMN mito_blast_hit.scientific_name IS 'BLAST sscinames.';
COMMENT ON COLUMN mito_blast_hit.common_name IS 'BLAST scomnames.';
COMMENT ON COLUMN mito_blast_hit.kingdoms IS 'BLAST sskingdoms (e.g. Eukaryota).';
COMMENT ON COLUMN mito_blast_hit.percent_identity IS 'pident, %.';
COMMENT ON COLUMN mito_blast_hit.alignment_length IS 'length, bp.';
COMMENT ON COLUMN mito_blast_hit.query_length IS 'qlen, bp.';
COMMENT ON COLUMN mito_blast_hit.subject_length IS 'slen, bp.';
COMMENT ON COLUMN mito_blast_hit.mismatch IS 'mismatch: mismatched positions.';
COMMENT ON COLUMN mito_blast_hit.gap_open IS 'gapopen: gap openings.';
COMMENT ON COLUMN mito_blast_hit.gaps IS 'gaps: gap positions.';
COMMENT ON COLUMN mito_blast_hit.query_start IS 'qstart.';
COMMENT ON COLUMN mito_blast_hit.query_end IS 'qend.';
COMMENT ON COLUMN mito_blast_hit.subject_start IS 'sstart.';
COMMENT ON COLUMN mito_blast_hit.subject_end IS 'send.';
COMMENT ON COLUMN mito_blast_hit.subject_title IS 'stitle: the subject''s FASTA title.';
COMMENT ON COLUMN mito_blast_hit.evalue IS 'BLAST e-value. Lower is better.';
COMMENT ON COLUMN mito_blast_hit.bit_score IS 'BLAST bit score.';
COMMENT ON COLUMN mito_blast_hit.query_coverage IS 'BLAST qcovs: query cover over all HSPs, %.';
COMMENT ON COLUMN mito_blast_hit.subject_coverage IS 'BLAST qcovhsp, the query cover of this HSP, %, whatever the name: the 21st -outfmt field (calculateLCA.py). Not a subject coverage.';
COMMENT ON COLUMN mito_blast_hit.region IS 'Marker region: 12s, 16s, CO1...';
COMMENT ON COLUMN mito_blast_hit.blast_run_date IS 'YYMMDD the BLAST ran, as text.';

COMMENT ON TABLE mito_lca_validation IS
  'Species-ID validation of an annotation''s LCA calls: the species to submit and who confirmed it. '
  'validator: push_species_validation.py (nf-core) or a curator''s initials; validator_2: '
  'push_qc_validator.py (QCd-nf-core) or a curator. Submission needs both. Read by summary and the '
  'reporting views.';
COMMENT ON COLUMN mito_lca_validation.validated_species_name IS 'The species name validated for submission; the mito QC workflow puts it in the processed file headers.';
COMMENT ON COLUMN mito_lca_validation.validator IS 'First validator: nf-core (push_species_validation.py, which overwrites only its own rows unless --force) or a curator''s initials.';
COMMENT ON COLUMN mito_lca_validation.nominal_species_id_lca_comment IS 'Curator''s note on the nominal ID against the LCA (workbook "Nominal species ID/LCA comment", SS/import_data_lca_validation.py).';
COMMENT ON COLUMN mito_lca_validation.validator_2 IS 'Second validator: QCd-nf-core (push_qc_validator.py, once the sample is submission_ready; never overwrites) or a curator''s initials.';
COMMENT ON COLUMN mito_lca_validation.data_release IS 'Empty on every row (2026-11-04) and no writer found. Candidate for removal.';
COMMENT ON COLUMN mito_lca_validation.validated_rank IS 'Rank the species ID was confirmed at: species, genus, genus_downgraded (a tentative cf./aff./? label released at genus), family, or unmatched (held) (024).';
COMMENT ON COLUMN mito_lca_validation.lca_genus IS 'For a family-level release, the genus the LCA resolved: a label-upgrade candidate for a curator. NULL at every other rank (024).';
COMMENT ON COLUMN mito_lca_validation.row_created_on IS 'When the row was first written (database clock).';

-- Reference genomes --------------------------------------------------------------------------

COMMENT ON TABLE ref_stage IS
  'Assembly stages, from the pipeline file names (<og>_v<date>.<version>.<stage>.<tool>...). Fixed '
  'lookup (057); no writer.';
COMMENT ON COLUMN ref_stage.stage IS 'Stage number in the file name: 0 contigs, 1 scaffolded, 2 decontaminated, 3 curated.';
COMMENT ON COLUMN ref_stage.name IS 'Short stage name.';
COMMENT ON COLUMN ref_stage.description IS 'What the stage contains and which tool produced it.';

COMMENT ON COLUMN ref_assembly.assembly_id IS 'Surrogate key. Parts, run links and the submission hang off it.';
COMMENT ON COLUMN ref_assembly.og_id IS 'The sample (FK to sample).';
COMMENT ON COLUMN ref_assembly.seq_date IS 'YYMMDD from the file name (<og>_v<date>). An identifier component, not a date.';
COMMENT ON COLUMN ref_assembly.version IS 'Strategy and attempt from the file name: hic1, hifi2, ont1...';
COMMENT ON COLUMN ref_assembly.strategy IS 'Generated from version: hic (HiFi + Hi-C), hifi (HiFi only) or ont.';
COMMENT ON COLUMN ref_assembly.attempt IS 'Generated from version: the attempt number.';
COMMENT ON COLUMN ref_assembly.og_num IS 'Numeric part of og_id, for sorting. Generated.';
COMMENT ON COLUMN ref_assembly.created_at IS 'When the row was first written (database clock).';

COMMENT ON TABLE ref_assembly_part IS
  'One sequence set of an assembly at a stage: hap1, hap2, p_ctg/a_ctg (hifiasm primary/alternate '
  'contigs), or dual. Created by scripts/lib/refdb.py when a push script first writes a result for it '
  '(ref repo and post-curation). Every per-tool ref_* table is keyed on part_id.';
COMMENT ON COLUMN ref_assembly_part.part_id IS 'Surrogate key. The per-tool tables are keyed on it.';
COMMENT ON COLUMN ref_assembly_part.assembly_id IS 'The assembly (FK to ref_assembly).';
COMMENT ON COLUMN ref_assembly_part.stage IS 'The stage (FK to ref_stage).';
COMMENT ON COLUMN ref_assembly_part.created_at IS 'When the row was first written (database clock).';

COMMENT ON TABLE ref_assembly_run IS
  'The sequencing rows an assembly was built from: PacBio/ONT DNA, and Hi-C once writers record it '
  '(trigger). Derived by the RG window sync and loaded at the 073 merge. No writer has added rows since '
  '(078).';
COMMENT ON COLUMN ref_assembly_run.assembly_id IS 'The assembly (FK to ref_assembly).';
COMMENT ON COLUMN ref_assembly_run.sequencing_id IS 'A sequencing row the assembly''s reads came from (FK to sequencing).';

COMMENT ON COLUMN ref_gfastats.part_id IS 'The assembly part (FK to ref_assembly_part).';
COMMENT ON COLUMN ref_gfastats.num_contigs IS 'gfastats # contigs.';
COMMENT ON COLUMN ref_gfastats.contig_n50 IS 'gfastats contig N50, bp. The authoritative contig N50.';
COMMENT ON COLUMN ref_gfastats.contig_n50_size_mb IS 'contig N50 in Mb, as the tool reported it: stored, not derived from contig_n50 (RG.0 §1.6).';
COMMENT ON COLUMN ref_gfastats.num_scaffolds IS 'gfastats # scaffolds.';
COMMENT ON COLUMN ref_gfastats.scaffold_n50 IS 'gfastats scaffold N50, bp. The authoritative scaffold N50.';
COMMENT ON COLUMN ref_gfastats.scaffold_n50_size_mb IS 'scaffold N50 in Mb, as the tool reported it: stored, not derived.';
COMMENT ON COLUMN ref_gfastats.largest_scaffold IS 'gfastats largest scaffold, bp.';
COMMENT ON COLUMN ref_gfastats.largest_scaffold_size_mb IS 'largest scaffold in Mb, as the tool reported it: stored, not derived.';
COMMENT ON COLUMN ref_gfastats.total_scaffold_length IS 'gfastats total scaffold length, bp.';
COMMENT ON COLUMN ref_gfastats.total_scaffold_length_size_mb IS 'total scaffold length in Mb, as the tool reported it: stored, not derived.';
COMMENT ON COLUMN ref_gfastats.gc_content_percent IS 'gfastats GC content, %.';
COMMENT ON COLUMN ref_gfastats.num_gaps IS 'gfastats # gaps. Written by the post-curation push only (295 of 1,294 rows on 2026-11-04); NULL on ref-repo rows.';
COMMENT ON COLUMN ref_gfastats.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON TABLE ref_busco IS
  'BUSCO completeness and BUSCO''s own assembly statistics. Written by 03a_push_busco_results_to_sqldb.py '
  '(ref repo and post-curation). Its N50 columns are not reliable N50s; use ref_gfastats.';
COMMENT ON COLUMN ref_busco.part_id IS 'The assembly part (FK to ref_assembly_part).';
COMMENT ON COLUMN ref_busco.dataset IS 'BUSCO lineage dataset searched, e.g. actinopterygii_odb10, vertebrata_odb10.';
COMMENT ON COLUMN ref_busco.complete IS 'Complete BUSCOs, % of n_markers.';
COMMENT ON COLUMN ref_busco.single_copy IS 'Complete single-copy BUSCOs, %.';
COMMENT ON COLUMN ref_busco.multi_copy IS 'Complete duplicated BUSCOs, %.';
COMMENT ON COLUMN ref_busco.fragmented IS 'Fragmented BUSCOs, %.';
COMMENT ON COLUMN ref_busco.missing IS 'Missing BUSCOs, %.';
COMMENT ON COLUMN ref_busco.n_markers IS 'Number of markers in the dataset.';
COMMENT ON COLUMN ref_busco.internal_stop_codon_percent IS 'Complete BUSCO genes with an internal stop codon, %.';
COMMENT ON COLUMN ref_busco.percent_gaps IS 'BUSCO''s own % of N bases.';
COMMENT ON COLUMN ref_busco.number_of_scaffolds IS 'BUSCO''s own scaffold count. Use ref_gfastats.num_scaffolds.';
COMMENT ON COLUMN ref_busco.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_merqury_qv.part_id IS 'The assembly part (FK to ref_assembly_part).';
COMMENT ON COLUMN ref_merqury_qv.unique_k_mers_assembly IS 'Merqury .qv: k-mers found only in the assembly, not in the reads (errors).';
COMMENT ON COLUMN ref_merqury_qv.k_mers_total IS 'Merqury .qv: all k-mers in the assembly.';
COMMENT ON COLUMN ref_merqury_qv.qv IS 'Merqury consensus quality value (Phred-scaled; higher is better).';
COMMENT ON COLUMN ref_merqury_qv.error IS 'Merqury per-base error rate (the probability QV encodes).';
COMMENT ON COLUMN ref_merqury_qv.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON TABLE ref_merqury_completeness IS
  'Merqury k-mer completeness. Written by 02d_push_merqury_completeness_results_to_sqldb.py (ref repo '
  'and post-curation). The old ref_genomes.k_mer_set was not carried: it was never filled.';
COMMENT ON COLUMN ref_merqury_completeness.part_id IS 'The assembly part (FK to ref_assembly_part).';
COMMENT ON COLUMN ref_merqury_completeness.solid_k_mers IS 'Solid read k-mers found in the assembly.';
COMMENT ON COLUMN ref_merqury_completeness.total_k_mers IS 'All solid read k-mers.';
COMMENT ON COLUMN ref_merqury_completeness.completeness IS 'Merqury k-mer completeness, % (solid_k_mers / total_k_mers).';
COMMENT ON COLUMN ref_merqury_completeness.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_omnic.part_id IS 'The assembly part (FK to ref_assembly_part).';
COMMENT ON COLUMN ref_omnic.total IS 'pairtools stats total: Hi-C read pairs.';
COMMENT ON COLUMN ref_omnic.total_unmapped IS 'Pairs with neither side mapped.';
COMMENT ON COLUMN ref_omnic.total_single_sided_mapped IS 'Pairs with one side mapped.';
COMMENT ON COLUMN ref_omnic.total_mapped IS 'Pairs with both sides mapped.';
COMMENT ON COLUMN ref_omnic.total_dups IS 'Mapped pairs marked as duplicates.';
COMMENT ON COLUMN ref_omnic.total_nodups IS 'Mapped pairs after deduplication.';
COMMENT ON COLUMN ref_omnic.cis IS 'Deduplicated pairs with both sides on the same sequence.';
COMMENT ON COLUMN ref_omnic.trans IS 'Deduplicated pairs on different sequences.';
COMMENT ON COLUMN ref_omnic.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_seqkit_stats.part_id IS 'The assembly part (FK to ref_assembly_part).';
COMMENT ON COLUMN ref_seqkit_stats.format IS 'seqkit stats format (FASTA).';
COMMENT ON COLUMN ref_seqkit_stats."type" IS 'seqkit stats sequence type (DNA). Quote the column name.';
COMMENT ON COLUMN ref_seqkit_stats.num_seqs IS 'Sequences in the curated FASTA.';
COMMENT ON COLUMN ref_seqkit_stats.sum_len IS 'Total length, bp.';
COMMENT ON COLUMN ref_seqkit_stats.min_len IS 'Shortest sequence, bp.';
COMMENT ON COLUMN ref_seqkit_stats.avg_len IS 'Mean sequence length, bp.';
COMMENT ON COLUMN ref_seqkit_stats.max_len IS 'Longest sequence, bp.';
COMMENT ON COLUMN ref_seqkit_stats.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_chromosome_stats.part_id IS 'The assembly part (FK to ref_assembly_part).';
COMMENT ON COLUMN ref_chromosome_stats.num_chromosomes IS 'SUPER_* scaffolds: chromosomes assigned in curation.';
COMMENT ON COLUMN ref_chromosome_stats.pct_assigned IS '% of assembly length in SUPER_* scaffolds.';
COMMENT ON COLUMN ref_chromosome_stats.pct_no_super IS '% of assembly length outside them (100 - pct_assigned).';
COMMENT ON COLUMN ref_chromosome_stats.num_seq_no_super IS 'Sequences not assigned to a chromosome.';
COMMENT ON COLUMN ref_chromosome_stats.max_len_no_super IS 'Longest unassigned sequence, bp.';
COMMENT ON COLUMN ref_chromosome_stats.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_read_set.read_set_id IS 'Surrogate key. ref_genomescope, ref_hifi_adapter_filter and the run links hang off it.';
COMMENT ON COLUMN ref_read_set.og_id IS 'The sample (FK to sample).';
COMMENT ON COLUMN ref_read_set.seq_date IS 'YYMMDD: the latest seq_date of its sequencing rows (or the staging date of an external set). NULL = unknown.';
COMMENT ON COLUMN ref_read_set.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON TABLE ref_read_set_run IS
  'The PacBio sequencing rows in a read set. PacBio DNA libraries only (trigger); never on an external '
  'read set (trigger). Written by scripts/lib/refdb.py with its read set. Migration 062.';
COMMENT ON COLUMN ref_read_set_run.read_set_id IS 'The read set (FK to ref_read_set).';
COMMENT ON COLUMN ref_read_set_run.sequencing_id IS 'A PacBio sequencing row in the set (FK to sequencing).';

COMMENT ON COLUMN ref_read_set_external.read_set_id IS 'The read set (FK to ref_read_set).';
COMMENT ON COLUMN ref_read_set_external.note IS 'Where the reads were found and what is not known about them.';
COMMENT ON COLUMN ref_read_set_external.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_genomescope.read_set_id IS 'The HiFi read set (FK to ref_read_set).';
COMMENT ON COLUMN ref_genomescope.homozygosity IS 'GenomeScope2 homozygosity, %, 2 places (the draft table keeps 4).';
COMMENT ON COLUMN ref_genomescope.heterozygosity IS 'GenomeScope2 heterozygosity, %, 2 places.';
COMMENT ON COLUMN ref_genomescope.genomesize IS 'GenomeScope2 haploid genome length, bp. 1 Gb exactly where the model failed (the writer''s default; see the table comment).';
COMMENT ON COLUMN ref_genomescope.repeatsize IS 'GenomeScope2 repeat length, bp.';
COMMENT ON COLUMN ref_genomescope.uniquesize IS 'GenomeScope2 unique length, bp.';
COMMENT ON COLUMN ref_genomescope.modelfit IS 'GenomeScope2 model fit, %.';
COMMENT ON COLUMN ref_genomescope.errorrate IS 'GenomeScope2 read error rate, %.';
COMMENT ON COLUMN ref_genomescope.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_hifi_adapter_filter.read_set_id IS 'The HiFi read set (FK to ref_read_set).';
COMMENT ON COLUMN ref_hifi_adapter_filter.contam_reads IS 'HiFi reads HiFiAdapterFilt removed as adapter-contaminated.';
COMMENT ON COLUMN ref_hifi_adapter_filter.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_submission.submission_id IS 'Surrogate key. Haplotype accessions and SRA uploads hang off it.';
COMMENT ON COLUMN ref_submission.og_id IS 'The sample (FK to sample). One submission per OG.';
COMMENT ON COLUMN ref_submission.assembly_id IS 'The OG''s one curated (stage 3) assembly (FK to ref_assembly); NULL where it has none or several. Copied to ref_submission_haplotype.assembly_id by trigger.';
COMMENT ON COLUMN ref_submission.biosample IS 'BioSample accession the genome was submitted under (SAMN.../SAMEA...).';
COMMENT ON COLUMN ref_submission.bioproject_umbrella IS 'Umbrella BioProject of the genome (PRJNA.../PRJEB...).';
COMMENT ON COLUMN ref_submission.bioproject_rawdata IS 'BioProject the raw reads were submitted to.';
COMMENT ON COLUMN ref_submission.embargo_status IS 'Release or Embargo: whether the genome may be made public.';
COMMENT ON COLUMN ref_submission.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_submission_haplotype.submission_id IS 'The submission (FK to ref_submission).';
COMMENT ON COLUMN ref_submission_haplotype.haplotype IS 'hap1 or hap2.';
COMMENT ON COLUMN ref_submission_haplotype.bioproject IS 'The haplotype''s own BioProject, under the umbrella.';
COMMENT ON COLUMN ref_submission_haplotype.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN ref_sra_upload.srr_accession IS 'Run accession of the uploaded reads (SRR.../ERR...).';
COMMENT ON COLUMN ref_sra_upload.submission_id IS 'The genome submission the reads belong to (FK to ref_submission).';
COMMENT ON COLUMN ref_sra_upload.filenames IS 'The uploaded file names, '', ''-joined. resolve_sra_upload_runs() matches them to sequencing rows.';
COMMENT ON COLUMN ref_sra_upload.data_type IS 'hifi, hic, ont or illumina. NULL: not recorded.';
COMMENT ON COLUMN ref_sra_upload.ncbi_status IS 'Released or ToBeReleased. NULL: not recorded. The release date is in release_date.';
COMMENT ON COLUMN ref_sra_upload.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON TABLE ref_sra_upload_run IS
  'The sequencing rows (library on a run) an SRA upload''s files came from; several where one upload '
  'carries several libraries. Written by ENA-ref-genomes step 09, and by resolve_sra_upload_runs() from '
  'the file names. Migration 064.';
COMMENT ON COLUMN ref_sra_upload_run.srr_accession IS 'The upload (FK to ref_sra_upload).';
COMMENT ON COLUMN ref_sra_upload_run.sequencing_id IS 'A sequencing row its files came from (FK to sequencing).';

COMMENT ON TABLE ref_sra_upload_unlinked IS
  'SRA uploads reviewed and left with no sequencing link, and why (064''s evidence). '
  'resolve_sra_upload_runs() does not re-resolve these; delete a row once the lab has fixed the cause.';
COMMENT ON COLUMN ref_sra_upload_unlinked.srr_accession IS 'The upload (FK to ref_sra_upload).';
COMMENT ON COLUMN ref_sra_upload_unlinked.reason IS 'Why no sequencing row could be linked, e.g. no filenames, or a staged file matching no raw file by size.';
COMMENT ON COLUMN ref_sra_upload_unlinked.reviewed_on IS 'When the upload was reviewed.';

-- Sequencing runs and read QC ----------------------------------------------------------------

COMMENT ON COLUMN sequencing_run.run_id IS 'Run id, MACHINE_YYMMDD_INITIALS (e.g. NEXT_230801_AD), as in sequencing.run_id.';
COMMENT ON COLUMN sequencing_run.mach IS 'Machine code parsed from run_id (NOVA, NEXT, ISEQ, MISEQ, PACB, ONT; case varies: iSeq, iSEQ). NULL where run_id does not follow the pattern.';
COMMENT ON COLUMN sequencing_run.run_seq_date IS 'The YYMMDD component of run_id. An identifier component, not a date; see run_date.';
COMMENT ON COLUMN sequencing_run.initial IS 'Initials parsed from run_id.';
COMMENT ON COLUMN sequencing_run.instrument IS 'sequencing.instrument where every row of the run agrees; NULL where they disagree or none is set.';
COMMENT ON COLUMN sequencing_run.run_date IS 'sequencing.run_date where every row of the run agrees; NULL otherwise. Can differ from run_seq_date.';
COMMENT ON COLUMN sequencing_run.created_at IS 'When the run was first seen (database clock).';
COMMENT ON COLUMN sequencing_run.updated_at IS 'When the derived values last changed.';

COMMENT ON COLUMN hifi_read_qc.hifi_qc_id IS 'Surrogate key.';
COMMENT ON COLUMN hifi_read_qc.og_id IS 'The sample (FK to sample), parsed from the SMRT Link SampleName.';
COMMENT ON COLUMN hifi_read_qc.tissue IS 'Tissue code parsed from the SampleName.';
COMMENT ON COLUMN hifi_read_qc.ext_type IS 'Extraction code parsed from the SampleName.';
COMMENT ON COLUMN hifi_read_qc.lib_code IS 'Library code parsed from the SampleName (e.g. SBL).';
COMMENT ON COLUMN hifi_read_qc.run_id IS 'The PacBio run (FK to sequencing_run; 077). From the yield CSV''s RunName.';
COMMENT ON COLUMN hifi_read_qc.sequencing_id IS 'The one sequencing row of this library on this run; NULL where none or several match (v_read_qc_sequencing_readiness).';
COMMENT ON COLUMN hifi_read_qc.barcode IS 'Barcode, with bc2032--bc2032 simplified to bc2032.';
COMMENT ON COLUMN hifi_read_qc.barcode_quality IS 'SMRT Link BarcodeQuality.';
COMMENT ON COLUMN hifi_read_qc.hifi_reads IS 'HiFi reads (SMRT Link HiFiReads).';
COMMENT ON COLUMN hifi_read_qc.hifi_read_length IS 'Mean HiFi read length, bp (HiFiReadLength).';
COMMENT ON COLUMN hifi_read_qc.hifi_read_quality IS 'HiFi read quality as SMRT Link reports it, e.g. Q27. Text.';
COMMENT ON COLUMN hifi_read_qc.hifi_yield IS 'HiFi yield, bases (HiFiYield).';
COMMENT ON COLUMN hifi_read_qc.polymerase_read_length IS 'Mean polymerase read length, bp (PolymeraseReadLength).';
COMMENT ON COLUMN hifi_read_qc.loaded_at IS 'When the row was last written (database clock).';

COMMENT ON COLUMN hic_read_qc.hic_qc_id IS 'Surrogate key.';
COMMENT ON COLUMN hic_read_qc.og_id IS 'The sample (FK to sample), parsed from the BaseSpace BioSampleName (OG<num><tissue>-<ext_type>_<lib_code>_<lane>).';
COMMENT ON COLUMN hic_read_qc.tissue IS 'Tissue code from the BioSampleName. NULL: not recorded.';
COMMENT ON COLUMN hic_read_qc.ext_type IS 'Extraction code from the BioSampleName. NULL: not recorded.';
COMMENT ON COLUMN hic_read_qc.lib_code IS 'Library code from the BioSampleName (e.g. HICL). NULL: not recorded.';
COMMENT ON COLUMN hic_read_qc.lane IS 'Lane from the BioSampleName (L1, L2...). NULL: not recorded.';
COMMENT ON COLUMN hic_read_qc.run_id IS 'The Illumina run (FK to sequencing_run; 077).';
COMMENT ON COLUMN hic_read_qc.sequencing_id IS 'The one Hi-C sequencing row of this OG and tissue on this run; NULL where none or several match (v_read_qc_sequencing_readiness).';
COMMENT ON COLUMN hic_read_qc.datecreated IS 'BaseSpace DateCreated of the dataset.';
COMMENT ON COLUMN hic_read_qc.isarchived IS 'BaseSpace IsArchived: the dataset has been moved to archive storage.';
COMMENT ON COLUMN hic_read_qc.isfiledeleted IS 'BaseSpace IsFileDataDeleted: the files are gone from BaseSpace.';
COMMENT ON COLUMN hic_read_qc.totalreadspf IS 'BaseSpace TotalReadsPF: reads passing filter, both mates counted.';
COMMENT ON COLUMN hic_read_qc.totalclusterspf IS 'BaseSpace TotalClustersPF: clusters (read pairs) passing filter.';
COMMENT ON COLUMN hic_read_qc.read1length IS 'Read 1 length, cycles (bp).';
COMMENT ON COLUMN hic_read_qc.read2length IS 'Read 2 length, cycles (bp).';
COMMENT ON COLUMN hic_read_qc.ispairedend IS 'BaseSpace IsPairedEnd.';
COMMENT ON COLUMN hic_read_qc.yield_gb IS 'Yield, Gb: totalclusterspf x (read1length + read2length) / 1e9 (generate_hic_yield.py).';
COMMENT ON COLUMN hic_read_qc.totalsize_gb IS 'Size of the dataset''s files, GB (BaseSpace TotalSize / 1e9). Not a yield.';
COMMENT ON COLUMN hic_read_qc.loaded_at IS 'When the row was last written (database clock).';

-- Check: no column on these tables is left without a comment ---------------------------------

DO $chk$
DECLARE
  missing text;
BEGIN
  SELECT string_agg(format('%s.%s', c.relname, a.attname), ', ' ORDER BY c.relname, a.attnum)
    INTO missing
    FROM pg_class c
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
   WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
     AND (c.relname ~ '^(draft_|mito_|ref_)' OR c.relname IN ('sequencing_run', 'hifi_read_qc', 'hic_read_qc'))
     AND col_description(c.oid, a.attnum) IS NULL;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION '078: columns still without a comment: %', missing;
  END IF;
  RAISE NOTICE '078: every column of the Phase R/RG tables has a comment';
END
$chk$;

COMMIT;
