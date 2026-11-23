# Ocean Genomes Data Dictionary

Status: rewritten 2026-11-04, after Phases R and RG and migrations `078`/`079`. Updated
2026-11-13: design reasons from the migration headers added to each section, the
[migration index](#migration-index) added, and `082`–`088` reflected. The first draft
(2026-07-07) described the pre-`v2` schema.

This is the map of the `oceanomics_genomes` database: what each table is for, what one row is,
who writes it, how the tables connect, and why they are shaped that way. **Column detail lives in
the database**, as comments added by `078` (Phase R/RG tables) and `079` (everything else). Read
them with `\d+ <table>` in psql, or in DBeaver's column view. This file does not repeat them.

Row counts are from live on 2026-11-04 unless marked.

## Where to look

| For | Look at |
|---|---|
| What a column means, its unit, what NULL means | The column comment (`\d+ <table>`) |
| Why a table is shaped the way it is | "Why it is shaped this way" in its section below; the full reasoning, with what was rejected, is the header of the migration named there (`sql/NNN_*.sql`) |
| What each migration did | The [migration index](#migration-index) at the end |
| Comment coverage, measured | `psql -f scripts/comment_coverage.sql` |
| Whether live matches source control | `bin/check_drift.py --coverage` |
| The rules for changing anything | `docs/database_change_checklist.md` |
| The open design questions | `database_review.md` §11 |

`docs/live_object_inventory.md`, `live_column_inventory.md` and `live_relationship_index_review.md`
were generated on 2026-07-07 and describe the pre-`v2` schema. They are kept as history and
nothing regenerates them.

## Conventions

- **`og_id`** is the specimen, `OG<number>`, and `sample.og_id` is its home. Every lab, assembly
  and submission table has an FK to it. **`og_num`** is its numeric part, generated, for sorting
  (`016`, `020`); `ORDER BY og_id` puts OG1000 before OG703, so views put `og_num` first (`046`,
  `056`).
- **`seq_date` is an identifier component, not a date.** It is the `YYMMDD` of a run id
  (`NOVA_240313_AD`) and part of the assembly keys (`OG82.ilmn.240313.getorg1770`). Use
  `sequencing.run_date` or `sequencing_run.run_date` for when sequencing happened. The same goes
  for `lca_run_date` and `blast_run_date`.
- **Surrogate keys** (`draft_id`, `assembly_id`, `annotation_id`, `part_id`, `read_set_id`) are
  identities. Each table also has a natural-key `UNIQUE` that the writers upsert on.
- **A process row exists only where the process ran.** The draft and ref per-tool tables have
  `CHECK num_nonnulls(...) > 0`. A missing row means the tool did not run (or its result was not
  uploaded); it never means "ran and found nothing" (`052`, `057`).
- **`loaded_at`** is when the writer last wrote the row, by the database clock.
- **Compatibility views** keep the exact name of the table they replaced (`draft_genomes`,
  `mitogenome_data`, `ref_genomes`, `lca`, ...). They are read-only. Writers use the base tables.
- **Out of scope here:** GoaT (`goat_species_v1`, `goat_project_metadata_v1`), `master_species`,
  `master_species_genome` and the OceanGenom_Web tables are colleagues' work (owner, 2026-11-13).
  They are listed so the map is complete, not documented.

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
        │          └─ hic_lysate ─────── hic_library ──────┘                  rna_qc_kinnex,
        └─ (assembly and submission tables, below)                            hifi_read_qc, hic_read_qc
```

| Table | Rows | One row is | Written by | Notes |
|---|---:|---|---|---|
| `sample` | 3,411 | A specimen | `import_v2.py` (1.MetaData); OceanGenom_Web (workflow, priority, embargo); ENA steps 06 and 09 (BioSample, BioProjects) | Planning columns are kept in the database (2026-10-28) |
| `tissue` | 8,013 | A tissue subsample | `import_v2.py` (2.Tissue) | |
| `dna_extraction` | 2,743 | One extraction attempt | `import_v2.py` (3.DNAExtractions) | Attempt key `(tissue_id, ext_num)` |
| `rna_extraction` | 270 | One extraction attempt | `import_v2.py` (3.RNAExtractions) | |
| `hic_lysate` | 430 | One lysate | `import_v2.py` (4.HiCLysate) | |
| `illumina_library`, `pacbio_library`, `ont_library`, `hic_library`, `rna_library_ilmn`, `rna_library_kinx` | 2,131 / 436 / 98 / 326 / 393 / 188 | One library prep attempt | `import_v2.py` (the 4.* sheets) | Status checked against `lab_status` (`082`) |
| `library` | 3,552 | A library of any technology | `import_v2.py` | One key for `sequencing` to point at |
| `sequencing` | 4,677 | One library on one run | `import_v2.py` (5.Sequencing) | No pair repeats; PacBio SMRT cells share the row, Illumina lanes are not rows (§11 Q5, 2026-11-23) |
| `sequencing_run` | 213 | A run | Triggers on `sequencing` (`075`) | FK target for `sequencing`, `rna_qc_kinnex`, `hifi_read_qc`, `hic_read_qc` |
| `design_description` | 2 | An Illumina prep protocol | Fixed | FK from `sequencing.design_no` (`063`) |
| `prep_automation` | 2 | Manual or automated prep | Fixed | Lookup |
| `lab_status` | 65 | An allowed Status value on one lab sheet | By hand (`INSERT`) | FK target for the nine sheets' status columns, through their `status_sheet` column (`082`) |
| `rna_qc_kinnex` | 96 | Kinnex read QC, library × run | No current writer found | Keys: `061` |
| `hifi_read_qc` | 279 | HiFi yield, library × run | ref repo `0b_push_hifi_yield_results_to_sqldb.py` | `sequencing_id` NULL where no single row matches |
| `hic_read_qc` | 552 | Hi-C yield, library × run × lane | `ref_genomes_hic_automation/push_hic_yield.py` | As above. Keyed on OG, tissue and library code, not the tube, so 51 rows cannot link where an OG has two Hi-C libraries on a run |

Read QC is kept at the `sequencing` grain, one library on one run, with Hi-C split further by
lane; `draft_fastp` is per draft (§11 Q4, 2026-11-23). `raw_data` (a FASTQ file list, unmaintained
since NOVA_250520) was dropped by `089`; it is in `archive/dropped_261123/`.

Import bookkeeping: `import_quarantine` (1,866 rows rejected by a constraint, held for the lab to
fix), `value_conversions` (1,457 values stored by a conversion rule, with the raw text),
`workbook_attempt_keys` (staging for the backfill's tie-breaking).

**Why it is shaped this way**

- **Children reach `og_id` through their parent FK, not a copied column** (`036` F1). A copied
  `og_id` could disagree with the parent; the browse views (`v_*_browse`, `037`) put it back for
  reading, with `is_latest`.
- **Typed columns.** Dates are `date` and measurements numeric (`036` F3). A value the lab typed
  that does not convert (`'3.44g'`, `23°09'06"S`, `>1.8`) is stored by a rule and logged in
  `value_conversions` with the raw text (`041`), or held in `import_quarantine` (`038`).
- **Attempts are numbered per parent and unique**: `unique(parent_id, attempt_num)`, parent FKs
  `NOT NULL`, every FK indexed (`036` F7). "Latest" is not a column: it is computed per parent in
  the views, as the spreadsheet does.
- **`sequencing` points at one `library`**, a registry of every library of any technology,
  instead of five nullable per-technology columns (`036` F6).
- **`sample` length and depth are split** into total length, fork length and unspecified, and a
  depth range (`042`), because the workbook columns held more than one quantity.
- **`status_overwrite` is a boolean the lab sets** to force which attempt counts (`036` F4a).
  `summary` uses it first, then the highest attempt number; ties all show (`081`).
- **Status values are one vocabulary** (`lab_status`, `082`): the variants (`HOLD`, `Ilumina`,
  `Failed QC - PacBio`, ...) are mapped at import, and an unknown value loads as NULL with a
  quarantine record instead of splitting a count.
- **`sequencing_run` is derived**, never written: triggers on `sequencing` keep one row per
  `run_id`, parsing `mach`, `run_seq_date` and `initial` from the name, and filling `instrument`
  and `run_date` only where every row of the run agrees (`053`, `075`). The read-QC tables FK to
  it strictly: a push for a run the workbook does not list yet is refused (`077`).
- **Proximity ligation lives on `hic_lysate`.** `hic_library.prox_ligation_conc` is kept as a
  legacy column while the lab still records it there (`036` F13).

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
compatibility view. `v_genome_size_comparison` sets each draft's genome size beside NCBI's
assembly for the species (see Taxonomy).

**Why it is shaped this way**

- **One table per process, not one wide row** (`052`). The old `draft_genomes` held a dozen tools
  side by side, and a tool that never ran left a block of NULLs that could not say why. The split
  follows the pipeline's own families (`draft_genome_stats.py` `FAMILY_COLUMNS`).
- **Illumina only.** A trigger on `draft_genome_run` refuses any non-Illumina row, after 15
  "drafts" turned out to be shallow Hi-C libraries (`049`). iSEQ QC runs are excluded by matching
  the instrument to the run's machine.
- **Depth and host columns** (`busco_read_depth`, `host_haploid_size`, `partition_confidence`,
  `partition_note`, `genomescope_fit`, `busco_regions`) were added once the pipeline had writers
  for them (`067`). ENA
  `COVERAGE` comes from the measured depth, never `bases / genome size`.
- **DepthSizer is frozen**: loaded once, never synced (owner decision 12).

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
| `mito_assembly_run` | 2,562 | A sequencing row an assembly was built from | Derived by triggers (`080`) |
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

**Why it is shaped this way**

- **Every annotation is kept** (`051`). The old `mitogenome_data` had one annotation per assembly
  in its columns, so a re-annotation overwrote the last one and an unannotated assembly carried
  81 empty columns. `is_selected` is an optional flag a person sets; nothing reads it.
- **Genes are long, one row per gene** (`mito_annotation_gene`, owner decision 4), with the wide
  form generated as a view from `mito_gene`.
- **Children are keyed by `annotation_id`** (`074`, `076`). A trigger fills it from the natural
  columns a writer sends, so the writers did not change; `076` then dropped the natural columns
  from the LCA tables and put compatibility views under the old names.
- **LCA rows are content-addressed** (`017`): their key includes an md5 over the row, so an
  identical re-upload is a no-op and a changed one is a new row. `annotation_id` is excluded from
  the hash, so adding it did not change any stored key (`074`).
- **Depth is measured the same way on every platform** (`003`, `mito_assembly_depth`), because
  `avg_coverage` held three different quantities depending on the assembler.
- **QC gates record their exceptions in queryable columns** instead of passing silently: tolerated
  tRNAs (`021`), accepted gene-order variants and how far off canonical a rejected order was
  (`023`), whether a second taxonomy source agreed (`025`, which must never become a gate), the
  annotation-integrity verdict (`026`), the completeness profile and assembly QC verdict (`068`).
- **Species validation matches at the rank the label has** (`024`, `validated_rank`): many
  nominal IDs are not binomials (`'Diaphus sp 1'`, `'Ophidiidae'`). `validation_status` looks for
  the nominal ID in the LCA species lists (`066`). Curators flag rows to escalate or investigate
  in OceanGenom_Web (`084`).
- **Run links are derived, ilmn → Illumina (not iSEQ), hic → Hi-C, hifi → PacBio, DNA libraries
  only** (`051`, `055`, `080`); mito links include failed runs.

## Reference genomes (Phase RG, `057`–`071`, merged by `073`)

```
ref_read_set ─┬─ ref_read_set_run ── sequencing      ref_stage
              ├─ ref_read_set_external                   │
              ├─ ref_genomescope, ref_hifi_adapter_filter │
                                                          │
ref_assembly ─┬─ ref_assembly_run ── sequencing           │
              └─ ref_assembly_part (stage × haplotype) ───┘
                   └─ ref_gfastats, ref_busco, ref_merqury_qv, ref_merqury_completeness,
                      ref_omnic, ref_seqkit_stats, ref_chromosome_stats,
                      ref_decontamination   (one per tool)

ref_submission ─┬─ ref_submission_haplotype
                └─ ref_sra_upload ─┬─ ref_sra_upload_run ── sequencing
                                   └─ ref_sra_upload_unlinked
```

| Table | Rows | One row is | Written by |
|---|---:|---|---|
| `ref_assembly` | 468 | An assembly attempt, `(og_id, seq_date, version)` | ref repo and post-curation, via `scripts/lib/refdb.py` |
| `ref_assembly_part` | 2,024 | One sequence set at one stage | `refdb.py`, on the first result for it |
| `ref_assembly_run` | 434 | A sequencing row an assembly was built from | Derived by triggers (`080`); hand links for the readiness view |
| `ref_stage` | 4 | Stage 0-3: contigs, scaffolded, decontaminated, curated | Fixed |
| `ref_gfastats` | 1,294 | gfastats; **the** N50 | `04a/04b_*push_gfa*` (ref repo), `04a_push_gfa_results_to_sqldb.py` (post-curation) |
| `ref_busco` | 781 | BUSCO | `03a_push_busco_results_to_sqldb.py` |
| `ref_merqury_qv` / `ref_merqury_completeness` | 968 / 878 | Merqury | `02b_*` / `02d_*` push scripts |
| `ref_omnic` | 576 | Hi-C mapping QC (pairtools stats) | `05a_push_omnic_results_to_sqldb.py` |
| `ref_seqkit_stats` | 300 | seqkit stats of the curated FASTA | post-curation `05a_push_stats_compiled_results_to_sql.py` |
| `ref_chromosome_stats` | 300 | Chromosome assignment after curation | post-curation `06b_push_percentage_stats_to_sqldb.py` |
| `ref_decontamination` | 306 | What FCS-GX and Tiara removed from one stage-2 haplotype, with the YaHS input (`083`) | `06_decontam_compile.py` + `06a_push_decontam_results_to_sqldb.py` |
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

**Why it is shaped this way**

- **Assembly → part → one row per tool** (`057`). The old `ref_genomes` was seven tools written
  sideways at one key, and 66% of its cells were NULL. A part is one stage (`ref_stage`) of one
  haplotype (`hap1`, `hap2`, or `dual` for both together).
- **Read QC belongs to a read set, not an OG** (`058`, `062`). GenomeScope and HiFiAdapterFilt run
  on the same input reads, so they share `ref_read_set`, which records its PacBio rows. Its
  `seq_date` is the latest run date of those rows, which can differ from the samplesheet date on
  the assembly by up to ~10 days. Dates were recovered from the Acacia backups, not guessed; reads
  that are not OceanOmics sequencing are marked external (`071`).
- **Run links are exact `(og_id, seq_date)` matches to PacBio/ONT DNA rows, failed runs excluded**
  (`057`, `069`, `080`); no fuzzy dates. Hi-C runs are not linked to assemblies yet (review
  Finding 17.5).
- **Submissions are enforced against the curated part they submit** (`070`), and the accession
  kinds are split by shape: ENA analysis `ERZ` (`analysis_accession`), WGS master
  (`assembly_accession`) and `GCA_` (`gca_accession`), each with a `CHECK`.
- **SRA uploads link to the sequencing rows their files came from** (`064`); a Hi-C file named
  `..._HICL1` is the library `..._HICL` (`065`). `ref_sra_upload.release_date` is the embargo end
  date from the receipt (`060`).

## ENA

| Table | Rows | One row is | Written by |
|---|---:|---|---|
| `ena_validation_attempts` | 1,374 | One ENA validation of one mitogenome annotation | mito pipeline `push_ena_validation_results.py` |
| `ena_submissions` | 539 | One submission of an annotation | `ENA-mito-genomes` (downstream; this pipeline never writes it) |
| `ena_specimen_accessions` | 3,721 | View (`089`): a sample and its BioSample from `sample.ncbi_biosample_id` | Not a write path; read by mito `audit_ena_readiness.py`. The old table is in `archive/dropped_261123/` (§11 Q14) |
| `ena_related_assemblies` | 0 | Planned; FK to `sample` (`089`) | None |

`ena_validation_latest` and `ena_submission_status` are the reading views.

**Why it is shaped this way**

- **One row per validation attempt, overwritten on rerun** (`002`); `attempt_count` keeps the
  tally. Keyed on the full sequence id (assembly plus annotation, `014`), because re-annotating
  an assembly used to overwrite the previous annotation's record.
- **Validation is not submission** (`005`): Webin test and production results are separate, and
  `submission_ready` is recomputed from them (`019`).
- **Selection, locus tags and submission belong to the downstream `ENA-mito-genomes` pipeline.**
  The in-repo package registry, selection layer, locus-tag registry and candidate runs were
  retired (`010`–`013`); their two empty archive tables went in `085`. `ena_submissions` records
  what happened after a sequence left this pipeline (`015`).
- **Any INSDC BioSample is recorded**, whichever archive minted it (`SAMEA`, `SAMN`, `SAMD`), and
  the ENA-registration gap is named rather than guessed (`007`).

## Taxonomy and external contracts

| Object | Rows | What it is | Notes |
|---|---:|---|---|
| `species` | 22,724 | Species names and lineage | NCBI `rankedlineage.dmp` via draft repo `scripts/taxonomy/load_taxonomy.py` (insert-only), plus AFD rows. Not maintained |
| `master_species`, `master_species_genome` | 19,817 each | The vertebrate genomes project's species list for GoaT | **A colleague's; out of scope** |
| `ncbi_genome_assemblies` | 1,830 | NCBI assembly metadata, 1,725 taxa | No writer found; no FK to `species`; no PK (`assembly_accession` is UNIQUE). No total length column |
| `v_genome_size_comparison` | 1,572 (2026-11-13) | Per draft: GenomeScope genome size beside the NCBI assembly chosen for the nominal species | `087`. Matched on taxon id through `species`; 1,053 drafts have one. One assembly per taxon: RefSeq reference genome, then most complete level, then latest release (`ncbi_assembly_count` says how many there were). No NCBI size or ratio: the table has no length |
| `goat_species_v1`, `goat_project_metadata_v1` | | GoaT export | **A colleague's; out of scope.** External contract: a breaking change is `_v2` beside it |

`master_species` is the maintained species list (owner, 2026-11-13; §11 Q1). It is vertebrates
only, so many samples (invertebrates above all) have a `nominal_species_id` that is not in it.
That is expected and is not validated (§10 Highest 8).

`species_ncbi_assembly` (never loaded) was dropped by `085`, with `v_genome_size_comparison`,
which read it. `087` recreated the view on `ncbi_genome_assemblies`.

## Archives

| Schema | Holds | Drop | Permanent copy |
|---|---|---|---|
| `pre_v2_archive` | The 20 pre-`v2` tables and views | V.7, after a quiet period | `~/oceanomics_genomes_pre_v6_261015.dump` |
| `pre_v3_archive` | `mitogenome_data`, `draft_genomes`, the 260909 orphans, `076`'s hash maps | R.8, after a quiet period | A `pg_dump` taken the morning of the drop |
| `pre_v4_archive` | The six old ref-genome tables and their two views, `ref_key_map`, `ref_excluded_rows` | RG.7, after a quiet period | As R.8 |

The two empty `public.ena_*_archive` tables were dropped by `085`.

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
- **Run links are derived in the database** (`080`). `refresh_assembly_runs()` links an assembly to the
  OG's runs of its `seq_date`, from triggers on `mito_assembly`, `ref_assembly`, `sequencing` and
  `library`. Mito links include failed runs; ref links do not. A tissue or extraction moved upstream
  of `library` is not caught: run `SELECT refresh_assembly_runs(ARRAY(SELECT og_id FROM sample))`.
- **DepthSizer is retired.** `draft_depthsizer` is frozen at its 701 rows.
- **261 draft values exist only in `pre_v3_archive.draft_genomes`**: the `lambda_depth`-era
  host and partition values for the 260909 and 260925 batches. They are lost at R.8 unless
  backfilled first (`database_review.md` Finding 17.1).
- **Lab status columns are checked against `lab_status`** (`082`). A value the lab enters that
  is not in its sheet's list loads as NULL, with a `lookup` record in `import_quarantine` holding
  the raw value. Add the value to `lab_status` and the next import fills it in. `summary` reports the latest extraction or library per
  technology: `status_overwrite` first, then the highest attempt number. Rows tied for latest
  (for example attempt 1 on two tissues) all show, comma-joined (`081`).

## Open decisions

| Decision | Options | Needed for |
|---|---|---|
| `sample.workflow` and `priority` values (§11 Q2) | The web app's vocabulary; left to the colleague who owns OceanGenom_Web (owner, 2026-11-23) | Their column comments |
| Unwritten `sample` submission columns | Keep, or drop in favour of `draft_submission` / `ref_submission` | Column cleanup |

Settled 2026-11-13: the species source for names is `master_species` (§11 Q1), and the GoaT
contract (§11 Q6) is out of scope, a colleague's. Settled 2026-11-23: `sequencing` is one library
on a run (Q5), QC follows it (Q4), `raw_data` dropped (Q13), `ena_specimen_accessions` a view
over `sample` (Q14), and the ENA accession gaps explained (Q12); `089`.

## Migration index

One line per migration in `sql/`: what it did, and why. The header of each file has the full
reasoning, what was rejected, and how to revert it. `001`–`026` came from the mitogenome/ENA
pipeline, `027`–`034` from this review's Phases A and B, `035`–`048` are the `v2` lab redesign
and cutover, `049`–`077` Phases R and RG, and `078` onwards the follow-ups.

| # | What | Why |
|---|---|---|
| `000` | Creates `schema_migrations`, the ledger | It recorded every migration but not its own creation |
| `001` | Creates `ena_validation_attempts` | Record each ENA validation of a mitogenome flatfile |
| `002` | One row per validation attempt; reruns overwrite (`attempt_count`) | Reruns were appending history rows |
| `003` | Uniform, cross-platform mito read depth | `avg_coverage` held three different quantities by assembler |
| `004` | ENA candidate package registry and specimen locus tags | Package every viable annotation; select later (retired by `010`–`013`) |
| `005` | Split Webin test and production results | Validation is not submission |
| `006` | Technology-aware locus-tag prefixes | One specimen is published once per technology, each with its own ENA study |
| `007` | Record any INSDC BioSample accession | NCBI-minted `SAMN` accessions; name the ENA-registration gap |
| `008` | `ena_submission_queue` view | One read-only surface for the downstream submitter (retired by `012`) |
| `009` | Renumber locus serials into coordinate order | EMMA sorted features as strings, which was baked into the serials |
| `010` | Archive and drop the locus-tag registry | Locus tags moved to the downstream ENA pipeline |
| `011` | Drop the local package validation gate | It never said anything `package_status` did not |
| `012` | Drop the in-repo ENA selection layer | Selection and submission moved to `ENA-mito-genomes` |
| `013` | Drop `ena_candidate_runs` | The last remnant of the selection layer |
| `014` | Key `ena_validation_attempts` on the full seq id | Re-annotation overwrote the previous annotation's record |
| `015` | Create `ena_submissions` | Record what happened to a sequence after it left this pipeline |
| `016` | `og_num` on `mitogenome_data` as a generated column | Every other table had it |
| `017` | Records the LCA content-addressing rework | Applied directly to live in August and never written down |
| `018` | `og_num` back to column 1 of `mitogenome_data` | `016` moved it to column 91 |
| `019` | Recompute `submission_ready` | `005`, replayed on a restore, wrongly cleared it |
| `020` | `og_num` on `ena_validation_attempts` | Same convention as the other tables |
| `021` | `trna_advisory` on the annotation QC gate | Keep tRNAs waived by the tolerance queryable |
| `022` | Widen three LCA columns | Too narrow for real BLAST output; 87 assemblies lost LCA rows |
| `023` | Record accepted and rejected gene-order variants | A published rearrangement used to fail like a scrambled assembly |
| `024` | `validated_rank` on LCA validation | Many nominal IDs are not binomials |
| `025` | Second-source taxonomy check for gene-order rules | Audit only; must never become a gate |
| `026` | Annotation-integrity verdict, lineage gene expectations, ATP9 and mtMutS | The final QC verdict and invertebrate genes, additive |
| `027` | Reporting views read live tables, not the August snapshots | `summary` and two others served frozen data (review Finding 11) |
| `028`, `029` | `mitogenome_submission_view` joins ENA on the full seq id, from the base table | Its join was one grain too coarse (Finding 16) |
| `030` | Indexes on the core FK and `og_id` columns | Finding 4; `summary` 7.6 s → 2.0 s |
| `031` | Drop the data-delivery subsystem | Abandoned; 124 stale rows |
| `032` | Drop `lca_old` | Superseded by a full LCA re-run; archived to CSV |
| `033`, `034` | Catch-up: eight reporting views (and the writable report's trigger), `design_description` | Bring hand-made objects under migration management |
| `035`–`040` | The `v2` schema: lab tables, browse views, quarantine, LCA tables, `summary` | The lab redesign (§ Specimens), built empty beside `public` |
| `041` | `value_conversions` | Store values converted by rule, with the raw text, instead of NULL |
| `042` | Split `sample` length (TL/FL/unspecified) and depth (range) | Each column held more than one quantity |
| `043` | `v2` form of `mitogenome_submission_view` | The old one read a column `v2` drops |
| `044` | Catch-up: OceanGenom_Web's `og_workflow_*` tables | Created by direct DDL (open question 16) |
| `045` | The `v2` cutover | `v2` becomes the schema names resolve to; old objects become `*_pre_v2` |
| `046` | `og_num` first in the twelve browse views | Numeric sort |
| `047` | Drop the `SS260818` snapshots | Phase F; the last copy of one was exported first |
| `048` | Move `v2` into `public` | Retire the parallel schema |
| `049` | Delete 15 drafts assembled from Hi-C reads | A draft is a shotgun Illumina assembly |
| `050` | Remove LCA/ENA rows whose annotation no longer exists | Re-annotation had orphaned them |
| `051` | Mitogenome tables in `v3` | Keep every annotation; one table per thing that happens to an assembly |
| `052` | Draft-genome tables in `v3` | One table per process instead of one wide row |
| `053` | `sequencing_run` in `v3` | Runs were keyed on everywhere but had no entity |
| `054` | Five FKs to `sample` | Tables carried `og_id` without the relation |
| `055` | Run links match DNA libraries only | RNA libraries share a technology with DNA ones |
| `056` | `og_num` first and columns grouped in the `v3` views | Column order recorded history, not meaning |
| `057` | Reference-genome assembly tables in `v4` | `ref_genomes` was seven tools at one key, 66% NULL |
| `058` | Reference read QC in `v4` | `raw_qc` was keyed on `og_id` alone, so re-sequencing overwrote |
| `059` | Reference submissions in `v4` | Haplotypes side by side; a column holding a status or a date |
| `060` | `ref_sra_upload.release_date` | The date is the embargo end from the receipt |
| `061` | `rna_qc_kinnex` key and FKs | Arrived by direct DDL with neither |
| `062` | `ref_read_set`, shared by GenomeScope and HiFiAdapterFilt | Both run on the same reads; dates recovered from Acacia |
| `063` | FK `sequencing.design_no` → `design_description` | A lookup in use; answers open question 15 |
| `064` | SRA uploads link to their sequencing rows | "Which reads did we submit" had no join |
| `065` | `..._HICL1` files are library `..._HICL` | Sample-sheet naming |
| `066` | `validation_status` matches the nominal ID in the LCA species lists | It compared a list with `=`; `nom_id_in_results` added nothing |
| `067` | Draft read depth and host partition columns | Writers existed; ENA `COVERAGE` was the wrong quantity (Finding 17) |
| `068` | Mito completeness profile and assembly QC verdict | Computed by the pipeline but not stored (Finding 17.4) |
| `069` | Ref run links skip failed runs | The lab's workbook fixes of 2026-10-22 |
| `070` | Ref submission haplotypes enforced against their curated part; accessions split by kind | One column held ERZ, WGS masters and blanks |
| `071` | External read sets, and the last four read sets dated | RG.6 gate |
| `072` | R.6: `v3` becomes `public` | The mito and draft tables become the schema of record |
| `073` | RG.6: `v4` becomes `public` | The ref-genome tables become the schema of record |
| `074` | Every LCA and ENA child row gets `annotation_id` with an FK | Nothing stopped a child naming a missing annotation |
| `075` | `sequencing_run` kept by triggers; FKs to it | The nightly sync that rebuilt it was gone |
| `076` | LCA tables stored by `annotation_id`, behind compatibility views | The natural columns were redundant after `074` |
| `077` | Strict FKs from the read-QC tables to `sequencing_run` | Owner decision: refuse a run the workbook does not list |
| `078`, `079` | Comments on every column this project owns | Meanings lived only in writers and headers |
| `080` | Assembly run links derived by triggers | No writer after the window syncs went |
| `081` | `summary` rebuilt set-based | 1.75 s, 1.2 s of it JIT; now ~60 ms |
| `082` | `lab_status` vocabulary, FK on nine Status columns | Variants of one status split counts |
| `083` | `ref_decontamination` | Nothing recorded what FCS-GX and Tiara removed |
| `084` | Escalate/investigate flags; per-gene LCA taxa in the report | Curator request |
| `085` | Drop `species_ncbi_assembly`, the two ENA archives, `v_genome_size_comparison` | Empty, no writer or reader (owner decision) |
| `086` | Correct `ncbi_genome_assemblies`' comment | It named the objects `085` dropped |
| `087` | `v_genome_size_comparison` recreated on `ncbi_genome_assemblies` | Owner decision; the NCBI table that has data. No length there, so no NCBI size or ratio |
| `088` | `ncbi_genome_assemblies`' comment names its reader | `086`'s said it had none |
| `089` | Drop `raw_data`; `ena_specimen_accessions` a view over `sample`; §11 answers in comments | Owner decisions 2026-11-23: unmaintained table; a one-off backfill nothing read |
| `090` | `refresh_sequencing_run()` stops checking `raw_data` | `089` left it reading the dropped table, so writes to `sequencing` failed for three minutes |
