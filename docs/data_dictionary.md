# Ocean Genomes Data Dictionary

Status: rewritten 2026-11-04, after Phases R and RG and migrations `078`/`079`. The first draft
(2026-07-07) described the pre-`v2` schema.

This is the map of the `oceanomics_genomes` database: what each table is for, what one row is,
who writes it, and how the tables connect. **Column detail lives in the database**, as comments
added by `078` (Phase R/RG tables) and `079` (everything else). Read them with `\d+ <table>` in
psql, or in DBeaver's column view. This file does not repeat them.

Row counts are from live on 2026-11-04.

## Where to look

| For | Look at |
|---|---|
| What a column means, its unit, what NULL means | The column comment (`\d+ <table>`) |
| Why a table is shaped the way it is | The header of the migration that created it (`sql/NNN_*.sql`) |
| Comment coverage, measured | `psql -f scripts/comment_coverage.sql` |
| Whether live matches source control | `bin/check_drift.py --coverage` |
| The rules for changing anything | `docs/database_change_checklist.md` |
| The open design questions | `database_review.md` §11 |

`docs/live_object_inventory.md`, `live_column_inventory.md` and `live_relationship_index_review.md`
were generated on 2026-07-07 and describe the pre-`v2` schema. They are kept as history and
nothing regenerates them.

## Conventions

- **`og_id`** is the specimen, `OG<number>`, and `sample.og_id` is its home. Every lab, assembly
  and submission table has an FK to it. **`og_num`** is its numeric part, generated, for sorting.
- **`seq_date` is an identifier component, not a date.** It is the `YYMMDD` of a run id
  (`NOVA_240313_AD`) and part of the assembly keys (`OG82.ilmn.240313.getorg1770`). Use
  `sequencing.run_date` or `sequencing_run.run_date` for when sequencing happened.
- **Surrogate keys** (`draft_id`, `assembly_id`, `annotation_id`, `part_id`, `read_set_id`) are
  identities. Each table also has a natural-key `UNIQUE` that the writers upsert on.
- **A process row exists only where the process ran.** The draft and ref per-tool tables have
  `CHECK num_nonnulls(...) > 0`. A missing row means the tool did not run (or its result was not
  uploaded); it never means "ran and found nothing".
- **`loaded_at`** is when the writer last wrote the row, by the database clock.
- **Compatibility views** keep the exact name of the table they replaced (`draft_genomes`,
  `mitogenome_data`, `ref_genomes`, `lca`, ...). They are read-only. Writers use the base tables.

## Specimens and lab workflow

The `v2` design (migrations `035`–`048`). The nightly import, `OceanOmics-Database/import_v2.py`,
loads the lab workbook, sheet by sheet, through the mapping in `name_convert_v2.py`. Each lab
column's comment names its sheet and header.

```
sample ─┬─ tissue ─┬─ dna_extraction ─┬─ illumina_library ─┐
        │          │                  ├─ pacbio_library ───┤
        │          │                  └─ ont_library ──────┤
        │          ├─ rna_extraction ─┬─ rna_library_ilmn ─┼─ library ── sequencing ── sequencing_run
        │          │                  └─ rna_library_kinx ─┤                              │
        │          └─ hic_lysate ─────── hic_library ──────┘                  raw_data, rna_qc_kinnex,
        └─ (assembly and submission tables, below)                            hifi_read_qc, hic_read_qc
```

| Table | Rows | One row is | Written by | Notes |
|---|---:|---|---|---|
| `sample` | 3,411 | A specimen | `import_v2.py` (1.MetaData); OceanGenom_Web (workflow, priority, embargo); ENA steps 06 and 09 (BioSample, BioProjects) | Planning columns are kept in the database (2026-10-28) |
| `tissue` | 8,013 | A tissue subsample | `import_v2.py` (2.Tissue) | |
| `dna_extraction` | 2,743 | One extraction attempt | `import_v2.py` (3.DNAExtractions) | Attempt key `(tissue_id, ext_num)` |
| `rna_extraction` | 270 | One extraction attempt | `import_v2.py` (3.RNAExtractions) | |
| `hic_lysate` | 430 | One lysate | `import_v2.py` (4.HiCLysate) | |
| `illumina_library`, `pacbio_library`, `ont_library`, `hic_library`, `rna_library_ilmn`, `rna_library_kinx` | 2,131 / 436 / 98 / 326 / 393 / 188 | One library prep attempt | `import_v2.py` (the 4.* sheets) | Status columns are free text (Phase H) |
| `library` | 3,552 | A library of any technology | `import_v2.py` | One key for `sequencing` to point at |
| `sequencing` | 4,480 | A sequencing record: usually one library on one run | `import_v2.py` (5.Sequencing) | Grain undecided (§11 Q5) |
| `sequencing_run` | 213 | A run | Triggers on `sequencing` (`075`) | FK target for `sequencing`, `raw_data`, `rna_qc_kinnex`, `hifi_read_qc`, `hic_read_qc` |
| `design_description` | 2 | An Illumina prep protocol | Fixed | FK from `sequencing.design_no` (`063`) |
| `prep_automation` | 2 | Manual or automated prep | Fixed | Lookup |
| `raw_data` | 8,010 | One FASTQ file | No current writer found | No new rows since July (§11 Q13) |
| `rna_qc_kinnex` | 96 | Kinnex read QC, library × run | No current writer found | Keys: `061` |
| `hifi_read_qc` | 279 | HiFi yield, library × run | ref repo `0b_push_hifi_yield_results_to_sqldb.py` | `sequencing_id` NULL where no single row matches |
| `hic_read_qc` | 552 | Hi-C yield, library × run × lane | `ref_genomes_hic_automation/push_hic_yield.py` | As above |

Import bookkeeping: `import_quarantine` (1,866 rows rejected by a constraint, held for the lab to
fix), `value_conversions` (1,457 values stored by a conversion rule, with the raw text),
`workbook_attempt_keys` (staging for the backfill's tie-breaking).

## Draft genomes (Phase R, `052`, merged by `072`)

```
draft_genome ─┬─ draft_genome_run ── sequencing
              ├─ draft_fastp, draft_genomescope, draft_tiara, draft_contamination,
              │  draft_busco, draft_merqury, draft_gfastats        (one per process)
              ├─ draft_depthsizer                                  (retired, frozen)
              └─ draft_submission
```

| Table | Rows | One row is | Written by |
|---|---:|---|---|
| `draft_genome` | 1,720 | An Illumina draft, `(og_id, seq_date)` | `OceanOmics-OceanGenomes-Draft-Genomes`, `bin/draft_genome_stats.py` |
| `draft_genome_run` | 1,725 | A sequencing row a draft was built from | `draft_genome_stats.py` `link_illumina_runs()`; Illumina only (trigger) |
| `draft_fastp` | 1,719 | fastp read QC | `push_fastp_to_sqldb.py` |
| `draft_genomescope` | 1,604 | GenomeScope2 fit, coverage verdict, host depth and partition | `push_assembly_results_to_sqldb.py`, `push_kmer_depth_to_sqldb.py` |
| `draft_tiara` | 1,603 | Tiara contig classes | `push_decontamination_results_to_sqldb.py` |
| `draft_contamination` | 1,603 | FCS-GX actions, contigs under 500 bp | `push_decontamination_results_to_sqldb.py` |
| `draft_busco` | 1,583 | BUSCO | `push_busco_results_to_sqldb.py` |
| `draft_merqury` | 1,580 | Merqury QV and completeness | `push_merqury_results_to_sqldb.py` |
| `draft_gfastats` | 874 | gfastats; **the** N50 | `push_gfa_results_to_sqldb.py` |
| `draft_depthsizer` | 701 | DepthSizer (retired 2026-10-16) | None; frozen |
| `draft_submission` | 579 | ENA/NCBI accessions | `ENA-draft-genomes` steps 06 (ERR, ERZ, BioSample) and 07 (GCA) |

`v_draft_genome_status` shows, per draft, which processes have a row. `draft_genomes` is the
compatibility view.

## Mitogenomes (Phase R, `051`, `068`, `074`–`076`)

```
mito_assembly ─┬─ mito_assembly_depth (0..1)    mito_assembly_qc (0..1)
               ├─ mito_assembly_run ── sequencing
               └─ mito_annotation (all kept) ─┬─ mito_annotation_gene ── mito_gene
                                              ├─ mito_lca, mito_lca_raw, mito_blast_hit
                                              ├─ mito_lca_validation
                                              └─ ena_validation_attempts, ena_submissions
```

| Table | Rows | One row is | Written by (mito pipeline, `inverts-dev`) |
|---|---:|---|---|
| `mito_assembly` | 2,521 | An assembly, `(og_id, tech, seq_date, code)` | `push_mtdna_assm_results.py` |
| `mito_assembly_depth` | 2,516 | The remap depth verdict | `push_mtdna_assm_results.py` (from `mito_depth.py`) |
| `mito_assembly_qc` | 196 | The assembly QC verdict | `push_assembly_qc.py` |
| `mito_assembly_run` | 2,560 | A sequencing row an assembly was built from | **None since `072`** (see caveats) |
| `mito_annotation` | 2,146 | One annotator run on an assembly | `push_emma_annotation_results.py` |
| `mito_annotation_gene` | 77,549 | One gene's length in one annotation | `push_emma_annotation_results.py` |
| `mito_gene` | 39 | A gene name | Fixed; add a gene with `rebuild_mito_gene_views()` |
| `mito_lca` | 5,490 | An LCA call per annotation and region | `push_lca_blast_results.py` |
| `mito_lca_raw` | 49,790 | A BLAST hit behind an LCA call | `push_lca_raw_results.py` |
| `mito_blast_hit` | 249,464 | A BLAST hit kept after filtering | `push_lca_blast_results.py` |
| `mito_lca_validation` | 2,054 | The species validated for submission | `push_species_validation.py`, `push_qc_validator.py`, curators |

Every child resolves its annotation with `mito_annotation_id()`. The mito writers' default branch
is **`inverts-dev`**; `master` is from September and still writes the pre-R names.

`mitogenome_data`, `lca`, `lca_raw_results`, `lca_validation` and `blast_filtered_lca` are the
compatibility views. `mitogenome_submission_view`, `lca_validation_report_view` and the LCA views
are the reporting views.

## Reference genomes (Phase RG, `057`–`071`, merged by `073`)

```
ref_read_set ─┬─ ref_read_set_run ── sequencing      ref_stage
              ├─ ref_read_set_external                   │
              ├─ ref_genomescope, ref_hifi_adapter_filter │
                                                          │
ref_assembly ─┬─ ref_assembly_run ── sequencing           │
              └─ ref_assembly_part (stage × haplotype) ───┘
                   └─ ref_gfastats, ref_busco, ref_merqury_qv, ref_merqury_completeness,
                      ref_omnic, ref_seqkit_stats, ref_chromosome_stats   (one per tool)

ref_submission ─┬─ ref_submission_haplotype
                └─ ref_sra_upload ─┬─ ref_sra_upload_run ── sequencing
                                   └─ ref_sra_upload_unlinked
```

| Table | Rows | One row is | Written by |
|---|---:|---|---|
| `ref_assembly` | 468 | An assembly attempt, `(og_id, seq_date, version)` | ref repo and post-curation, via `scripts/lib/refdb.py` |
| `ref_assembly_part` | 2,024 | One sequence set at one stage | `refdb.py`, on the first result for it |
| `ref_assembly_run` | 434 | A sequencing row an assembly was built from | **None since `073`** (see caveats) |
| `ref_stage` | 4 | Stage 0-3: contigs, scaffolded, decontaminated, curated | Fixed |
| `ref_gfastats` | 1,294 | gfastats; **the** N50 | `04a/04b_*push_gfa*` (ref repo), `04a_push_gfa_results_to_sqldb.py` (post-curation) |
| `ref_busco` | 781 | BUSCO | `03a_push_busco_results_to_sqldb.py` |
| `ref_merqury_qv` / `ref_merqury_completeness` | 968 / 878 | Merqury | `02b_*` / `02d_*` push scripts |
| `ref_omnic` | 576 | Hi-C mapping QC (pairtools stats) | `05a_push_omnic_results_to_sqldb.py` |
| `ref_seqkit_stats` | 300 | seqkit stats of the curated FASTA | post-curation `05a_push_stats_compiled_results_to_sql.py` |
| `ref_chromosome_stats` | 300 | Chromosome assignment after curation | post-curation `06b_push_percentage_stats_to_sqldb.py` |
| `ref_read_set` | 249 | A HiFi read set one run of the pipeline used | `refdb.py` |
| `ref_read_set_run` / `ref_read_set_external` | 266 / 1 | Its PacBio rows, or why it has none | `refdb.py` / by hand (`071`) |
| `ref_genomescope` / `ref_hifi_adapter_filter` | 249 / 143 | Read-set k-mer profile / adapter filter | `01a_*`, `0a_*` push scripts |
| `ref_submission` | 88 | The genome submission of an OG | `ENA-ref-genomes` steps 09 and 10 |
| `ref_submission_haplotype` | 174 | One haplotype's BioProject and accessions | `ENA-ref-genomes` steps 09 and 10 |
| `ref_sra_upload` | 304 | One raw-read run uploaded | `ENA-ref-genomes` step 09 |
| `ref_sra_upload_run` / `ref_sra_upload_unlinked` | 294 / 14 | Its sequencing rows, or why it has none | step 09 and `resolve_sra_upload_runs()` / by review |

`v_ref_assembly_status` and `v_ref_assembly_summary` are the status views. `ref_genomes`,
`ref_genomes_assembly_uploads`, `ref_genomes_sra_uploads`, `raw_qc`, `hifi_reads_qc` and
`hic_reads_qc` are the compatibility views. The `v_*_readiness` views list the rows with a
missing link, and why.

## ENA

| Table | Rows | One row is | Written by |
|---|---:|---|---|
| `ena_validation_attempts` | 1,374 | One ENA validation of one mitogenome annotation | mito pipeline `push_ena_validation_results.py` |
| `ena_submissions` | 539 | One submission of an annotation | `ENA-mito-genomes` (downstream; this pipeline never writes it) |
| `ena_specimen_accessions` | 2,848 | A specimen's ENA-usable BioSample, if known | mito `backfill_ena_specimen_accessions.py`; 1 accession (§11 Q14) |
| `ena_related_assemblies` | 0 | Planned | None |
| `ena_locus_registry_archive`, `ena_candidate_loci_archive` | 0 | Archived by `010` | None |

`ena_validation_latest` and `ena_submission_status` are the reading views.

## Taxonomy and external contracts

| Object | Rows | What it is | Notes |
|---|---:|---|---|
| `species` | 22,724 | Species names and lineage | NCBI `rankedlineage.dmp` via draft repo `scripts/taxonomy/load_taxonomy.py` (insert-only), plus AFD rows |
| `master_species`, `master_species_genome` | 19,817 each | OceanGenom_Web's curated species list | The colleague's; not documented here |
| `ncbi_genome_assemblies` | 1,830 | NCBI assembly metadata | No writer found; no FK to `species` |
| `species_ncbi_assembly` | 0 | Planned NCBI assembly table | Empty, and read by `v_genome_size_comparison` |
| `goat_species_v1`, `goat_project_metadata_v1` | | GoaT export | External contract; a breaking change is `_v2` beside it (§11 Q6) |

Which species table is authoritative is undecided (§11 Q1).

## Archives

| Schema | Holds | Drop | Permanent copy |
|---|---|---|---|
| `pre_v2_archive` | The 20 pre-`v2` tables and views | V.7, after a quiet period | `~/oceanomics_genomes_pre_v6_261015.dump` |
| `pre_v3_archive` | `mitogenome_data`, `draft_genomes`, the 260909 orphans, `076`'s hash maps | R.8, after a quiet period | A `pg_dump` taken the morning of the drop |
| `pre_v4_archive` | The six old ref-genome tables and their two views, `ref_key_map`, `ref_excluded_rows` | RG.7, after a quiet period | As R.8 |
| `public.ena_*_archive` | Two empty ENA tables (`010`) | With R.8 | Not needed: empty |

## Data caveats

Things a reader will otherwise get wrong. Each is also in the column comment.

- **N50: use gfastats, never BUSCO.** `draft_busco.scaffold_n50`/`contigs_n50` and
  `ref_busco.*_n50_bus` are BUSCO's own figures; on most drafts they behave as an L50. Use
  `draft_gfastats` and `ref_gfastats`. gfastats and BUSCO disagreed on 608 of 696 drafts
  (`assembly_relations_plan.md` §4.2).
- **`confidence_score` in the LCA tables is a BLAST e-value**: lower is better, 0 is best.
- **`taxon_rank_db` is a taxonomy source** (fishbase, worms, ncbi), not a rank.
- **`mito_blast_hit.subject_coverage` is BLAST `qcovhsp`**, the query cover per HSP.
- **`mito_assembly.avg_coverage` is not comparable across assemblers.** Use
  `mito_assembly_depth.mean_depth`.
- **`draft_genomescope.lambda_depth` is not a sequencing depth.** For ENA `COVERAGE`, use
  `busco_read_depth`.
- **Genome size needs its verdict.** Check `draft_genomescope.genome_size_reliable` and
  `genome_size_flags` before quoting `genomesize`. `ref_genomescope.genomesize` is exactly 1 Gb
  where the model failed.
- **Run links stopped at the merges.** Nothing has written `mito_assembly_run` since `072` or
  `ref_assembly_run` since `073`. Assemblies made since then have no run links.
- **`v_genome_size_comparison`'s NCBI columns are always NULL**, because it reads the empty
  `species_ncbi_assembly`.
- **DepthSizer is retired.** `draft_depthsizer` is frozen at its 701 rows.
- **261 draft values exist only in `pre_v3_archive.draft_genomes`**: the `lambda_depth`-era
  host and partition values for the 260909 and 260925 batches. They are lost at R.8 unless
  backfilled first (`database_review.md` Finding 17.1).
- **Lab status columns are free text.** `summary` reports the one extraction or library per
  specimen that has `status_overwrite`, otherwise the highest attempt number.

## Open decisions

| Decision | Options | Needed for |
|---|---|---|
| Canonical species source (§11 Q1) | `species`, `master_species`, or a curated view | Species cleanup, an FK from `sample.nominal_species_id`, GoaT |
| Sample status columns (§11 Q2) | User-entered, imported, or derived | Status normalisation, `summary` |
| `sequencing` row grain (§11 Q5) | Run, library on a run, lane, or output file | The library model, QC relationships |
| GoaT contract (§11 Q6) | What `goat_species_v1` must keep | Refactoring it |
| `ena_specimen_accessions` (§11 Q14) | Keep, or a view over `sample` | ENA tables |
| Unwritten `sample` submission columns | Keep, or drop in favour of `draft_submission` / `ref_submission` | Column cleanup |
