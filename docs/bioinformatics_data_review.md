# Bioinformatics Data Review

Scope: `ref_genomes`, `draft_genomes`, `raw_qc`, `hifi_reads_qc`, `hic_reads_qc`,
`raw_data`, `ref_genomes_assembly_uploads`, `ref_genomes_sra_uploads`, and the
scripts in `OceanOmics-Database/SS/` that populate them.

Status: review only. Nothing has been built.

All figures measured against the live database (`oceanomics_genomes` on the
production host) in a read-only session, 2026-08-05. `ref_genomes` = 1,856 rows,
`draft_genomes` = 1,461, `raw_qc` = 249.

> **Note on `OceanOmics-Database`.** That repo is **old and is not the live
> pipeline**. It is checked out here only as a record of intent — which columns
> each tool writes, and what the original table design was. Nothing in it should be
> read as current behaviour, and its bugs are not production incidents. Where the
> repo and the live database disagree, the live database is right. (`import_v2.py`
> and `name_convert_v2.py` are the exception — those are new, from the v2 build.)

## 1. `ref_genomes` is seven tables sharing a primary key

All 58 columns partition exactly into per-tool blocks — nothing unaccounted for,
no column in two blocks. This is not an interpretation imposed on the table:
`create_database.py:610` already writes the blocks out as comments
(`-- gfa stats results`, `-- BUSCO results`, `-- Merqury qv`, `-- Merqury
completeness`, `-- Omic results`). The table was designed as five tools' outputs
and never given five tables.

The live fill rates fall into exactly those blocks, which is the strongest possible
confirmation that the blocks are real:

| Block | Cols | Filled / 1,856 | Written by |
|---|---:|---|---|
| key | 5 | 100% | — |
| gfastats | 11 | 1,169 (63%) | `push_gfa_results_to_sqldb.py` |
| merqury QV | 4 | 845 (46%) | `push_merqury_qv_results_to_sqldb.py` |
| merqury completeness | 4 | 752 (41%) | `push_merqury_comp_results_to_sqldb.py` |
| BUSCO | 12 | 681 (37%) | `push_busco_results_to_sqldb.py` |
| omni-C / pairtools | 8 | 550 (30%) | `push_omnic_results_to_sqldb.py` |
| assembly summary | 4 | 332 (18%) | *no script in repo* |
| seqkit | 7 | 234 (13%) | *no script in repo* |
| chromosome assignment | 6 | 234 (13%) | *no script in repo* |

Within each block the counts are identical to the row — all seven seqkit columns are
filled in exactly 234 rows, all eight pairtools columns in exactly 550.

**This is the direct answer to your question about rows that never populate most
of the fields.** The sparsity is structural, not a data-quality problem:

- **No metric column in the table exceeds 64% fill.** The best is
  `contig_n50_size_mb` at 64.1%.
- **39.3% of rows (730) carry exactly one block.** A row with only merqury QV has
  4 of 53 non-key columns populated — 8%.
- Only 11.3% carry six blocks. None carry all seven.
- **22 rows carry no block at all** — key columns only, nothing else. All are
  stage 0, `a_ctg`/`p_ctg`, `hifi1`, early 2023: assemblies where gfastats never
  reported.

The blocks are also confined by stage, so most of the grid can never be filled:
seqkit and chromosome assignment exist **only at stage 3**; omni-C never appears at
stage 3; merqury never at stage 2. A stage-2 row cannot have merqury data no matter
what — but the columns are there, empty, on every row.

`draft_genomes` is the same shape — 105 columns partitioning exactly into 11 tool
blocks — but **it does not have the sparsity problem**: 88% of its rows carry 8 or 9
of 11 blocks. You were right to point at `ref_genomes` specifically.

### 1.1 Two columns are completely empty

| Column | Filled |
|---|---|
| `ref_genomes.k_mer_set` | **0 / 1,856** |
| `ref_genomes.hap2_chr_level_max_len` | **0 / 1,856** |
| `draft_genomes.sra_date_submitted` | **0 / 1,461** |

`k_mer_set` is worth a look rather than a straight drop: it is one of the four
columns `push_merqury_comp_results_to_sqldb.py` writes, and the other three are
populated in 752 rows. The same column in `draft_genomes` is filled 1,321 times. So
the value exists in merqury output and is being dropped on the `ref_genomes` path
specifically.

## 2. What the old scripts tell us about how the table was meant to work

The scripts in `SS/ref_genomes_table/` are stale (see the note above), so nothing
here is a live fault. They are still the best available record of what each block
of `ref_genomes` is *for*, and of how far the live table has drifted from its
original design.

All five push scripts end with:

```sql
ON CONFLICT (og_id, seq_date, stage, haplotype) DO UPDATE SET ...
```

I confirmed against live that `ref_genomes` has **exactly one unique index**:

```
ref_genomes_pkey UNIQUE (og_id, seq_date, stage, haplotype, version)
```

Postgres requires the `ON CONFLICT` inference set to match a unique index exactly,
so these scripts could not run against today's table even if someone tried.
`create_database.py:664` declares `PRIMARY KEY (og_id, seq_date, stage, haplotype)`,
matching them — so the old repo is internally consistent, and it is the live table
that has moved on.

The useful part is the size of the drift. Since those scripts were written, the live
table has gained `version` in the primary key plus the seqkit, chromosome-assignment
and `num_gaps` columns — **14 columns and a key change**, none of it reflected in any
DDL under version control. Whatever loads `ref_genomes` today is undocumented here.

`version` is fully populated on live, and its contents show it is part of assembly
identity rather than a version number:

| version | rows | stages |
|---|---:|---|
| `hic1` | 844 | 0,1,2,3 |
| `hifi1` | 833 | 0,1 |
| `hic2` | 162 | 0,1,2,3 |
| `ont1` | 8 | 1,2,3 |
| `hic3` | 3 | 3 |
| `231027` | 3 | 1 |
| `hi1` | 3 | 1 |

It is *which data type and which round of scaffolding* — which makes it part of the
assembly's identity, and is why it belongs in the key. But `231027` is a date in a
version column and `hi1` is a typo for `hic1`, and both are sitting in a primary key
where nothing can correct them without a delete. A lookup table or a check constraint
on this column would have caught both.

## 3. Two columns claiming the same metric, disagreeing

This is the finding I flagged as "run this query first", and the answer is the bad one.

Three quantities have two columns each in `ref_genomes` — one from gfastats, one
from the assembly-summary block:

| Quantity | gfastats | assembly summary | Both filled | **Disagree** |
|---|---|---|---:|---:|
| scaffold N50 | `scaffold_n50` | `scaffold_n50_bus` | 285 | **51** |
| contig N50 | `contig_n50` | `contigs_n50_bus` | 285 | **39** |
| scaffold count | `num_scaffolds` | `number_of_scaffolds` | 285 | **49** |

The disagreements are not a unit conversion or a consistent tool offset. Of 285
rows, 234 have a ratio of exactly 1.000 and the remaining 51 are scattered — 1.797,
0.582, 1.660, 0.734, 1.083 — with no mode. These are measurements of *different
things* recorded against the same primary key.

The magnitudes matter. Real rows:

| og_id | stage | hap | `scaffold_n50` | `scaffold_n50_bus` | `num_scaffolds` | `number_of_scaffolds` |
|---|---:|---|---:|---:|---:|---:|
| OG113 | 3 | hap1 | 69,037,583 | 38,601,165 | 459 | 224 |
| OG38 | 3 | hap1 | 50,143,677 | 32,585,020 | 263 | 115 |
| OG2164 | 2 | hap2 | 34,539,934 | 59,373,174 | 42 | 5 |

A scaffold N50 of 69 Mb or 38.6 Mb for the same finished reference genome is not a
rounding difference — it is the headline quality number, and which one you get
depends on which column you happen to read. The scaffold counts differ by 2× or more
throughout, suggesting one tool counts every scaffold and the other counts only those
it analysed.

Nothing in the schema says which is authoritative. There is no provenance column, so
a consumer cannot even tell which tool produced which. The fix is one column per
quantity plus a recorded source, not two columns whose meaning depends on which
happens to be non-null.

## 4. Correction: `raw_qc` is not a duplicate — it is a second, unlabelled run

**I got this wrong in the first pass and the live data corrects it.** I reported
`raw_qc` as 8 of 9 columns duplicating `draft_genomes`, and recommended collapsing
them. The column overlap is real, but the conclusion was wrong.

`raw_qc` and `draft_genomes` hold genomescope output for 87 shared rows. The values
disagree in **87 of 87** for `genomesize` and 84 of 87 for `heterozygosity` — and
again with no consistent ratio (0.45 to 1.08, no mode). Example: OG114 is
1,555,140,873 bp in `raw_qc` and 698,045,379 bp in `draft_genomes`, a factor of 2.2.

The reason is visible in the coverage. Of `raw_qc`'s 249 og_ids:

| | count |
|---|---:|
| in `ref_genomes` only | 170 |
| in both | 76 |
| in `draft_genomes` only | **0** |
| in neither (orphans) | 3 |

`raw_qc` belongs to the **reference/HiFi** pipeline; the genomescope block in
`draft_genomes` belongs to the **draft/Illumina** pipeline. Same tool, different read
sets, genuinely different and both legitimate.

So this is not redundant storage. It is worse in one specific way: **the only thing
recording which read set a genome-size estimate came from is which table it is
sitting in.** There is no column for it. Any query that unions or coalesces the two —
and `coverage_summary` reads `genomesize` from `raw_qc` while joining HiFi *and* Hi-C
yields — is silently mixing two different estimates.

The fix is a single genomescope table with an explicit input-readset column, not a
merge of the two and not leaving them apart.

`contam_reads` is still misfiled: it is HiFiAdapterFilt output
(`push_hifiadapt_results_to_sqldb.py`), a property of the reads, not of a genomescope
run, and it is the only column in `raw_qc` not shared with `draft_genomes`.

## 5. Columns that are arithmetic restatements of other columns

Verified on live, all 1,856 rows:

| Identity | Result |
|---|---|
| `total = total_unmapped + total_single_sided_mapped + total_mapped` | 0 drift |
| `total_mapped = total_dups + total_nodups` | 0 drift |
| `total_nodups = cis + trans` | 0 drift |
| `error = 10 ^ (−qv / 10)` | 845/845 agree |
| `contig_n50_size_mb = contig_n50 / 1e6` | 0 drift |
| `scaffold_n50_size_mb = scaffold_n50 / 1e6` | **2 rows drift** |

That is 4 unit-conversion columns, 1 log transform, and 3 subtotals — **8 of the 53
non-key columns carry no information**, plus the 2 dead columns from §1.1.

Two things the live data adds that the sample files did not show:

- The two drift rows are off by one cent — `145.15` stored where `145144741 / 1e6`
  rounds to `145.14` (OG1161), and `28.55` vs `28.54` (OG778). Harmless in
  themselves, and exactly the failure mode that makes stored derivations a bad idea:
  they can disagree with their source and nothing notices.
- **21 rows have `contig_n50_size_mb` populated but `contig_n50` null** — a derived
  value with no source. That is why the `*_size_mb` columns (1,190) out-fill the base
  columns (1,169).

Either drop these and let consumers divide, or make them `GENERATED ALWAYS AS
(... / 1e6) STORED` so they cannot drift. I would keep `cis`/`trans` and drop the
three subtotals — the components are what the pipeline measures, and cis/trans ratio
is the metric anyone actually wants from an omni-C run.

## 6. `ref_genomes` and `draft_genomes` overlap on 19 non-key columns

Both pipelines run BUSCO, merqury and gfastats and both store the results inline.
Where they overlap, the vocabularies diverged:

| Quantity | `ref_genomes` | `draft_genomes` |
|---|---|---|
| contig N50 (gfastats) | `contig_n50` | `gfa_contig_n50` |
| contig N50 (assembly summary) | `contigs_n50_bus` | `contigs_n50` |
| scaffold count (gfastats) | `num_scaffolds` | `gfa_num_scaffolds` |
| scaffold count (assembly summary) | `number_of_scaffolds` | `number_of_scaffolds` |

Four spellings of contig N50 across two tables. Only 76 og_ids appear in both tables
(247 in `ref_genomes`, 1,431 in `draft_genomes`), so these are largely different
sample populations — but any cross-pipeline query has to know all four names.

## 7. NCBI submission state is tracked in four places

| Table | Columns | Grain |
|---|---|---|
| `draft_genomes` | `sra_accession`, `biosample_accession`, `bioproject_accession`, `study`, `assembly_accession`, `sra_date_submitted`, `comment` | one draft assembly |
| `ref_genomes_assembly_uploads` | `biosample`, `bioproject_umbrella`, `bioproject_hap1`, `bioproject_hap2`, `bioproject_rawdata`, `assembly_accession_hap1`, `assembly_accession_hap2`, `embargo_status` | one sample, haplotypes as columns |
| `ref_genomes_sra_uploads` | `srr_accession`, `filenames`, `data_type`, `ncbi_status` | one SRA run |
| `sample` | `ncbi_bioproject_id_lvl_3_hifi` and siblings | one sample |

Four spellings of BioProject, three of BioSample.
`ref_genomes_assembly_uploads` has 54 rows against `ref_genomes`' 1,856 — it is a
working list, not a record of anything. It also repeats haplotype as a column pair
(`_hap1`/`_hap2`) where `ref_genomes` has it as a key column, so joining the two
requires unpivoting one side. `draft_genomes.sra_date_submitted` is empty in all
1,461 rows.

## 8. File paths

`draft_genomes` carries 14 columns of file location — `aws_r1`, `aws_r1_size`,
`aws_r2`, `aws_r2_size`, `aws_assm`, `aws_assm_size`, and the same pattern for
`fastp_` and `sra_`. That is a seven-row child table written sideways: seven files,
each with a path and a size, as a fixed column set. Adding an eighth file kind is a
migration.

`raw_data` already exists and is nearly that table — `(og_id, run_id, lane_id,
filename)`, 8,010 rows — but has no size, no file-kind, and no link to the assembly.

## 9. Proposed shape

One identity table plus one table per tool — the same `v2` pattern already used for
the lab tables.

```
v2.assembly                       one row per assembly artefact
    assembly_id      generated pk
    og_id            → v2.sample(og_id)
    pipeline         'reference' | 'draft'
    seq_date, stage, haplotype, version
    unique (og_id, pipeline, seq_date, stage, haplotype, version)
```

Then one table per tool, each keyed on `assembly_id`, holding only that tool's
columns:

```
v2.assembly_gfastats       v2.assembly_busco          v2.assembly_merqury
v2.assembly_seqkit         v2.assembly_hic_contacts   v2.assembly_chromosomes
v2.assembly_summary        v2.assembly_contamination  v2.assembly_read_qc
v2.assembly_genomescope    v2.assembly_depthsizer
v2.assembly_file           (many per assembly)
v2.assembly_submission     (NCBI state)
```

What this buys, in order of how much it matters:

1. **§3 becomes impossible.** `assembly_gfastats.scaffold_n50` and
   `assembly_summary.scaffold_n50` are two rows from two tools with the source named,
   not two columns in one row with no way to tell them apart. The 51 disagreements
   become visible and resolvable instead of silent.
2. **§4 becomes expressible.** `assembly_genomescope` gets a readset column, so a
   HiFi estimate and an Illumina estimate for the same sample are two labelled rows
   rather than two tables and a convention.
3. **`ref_genomes` and `draft_genomes` collapse into one set of tables**, since they
   run the same tools. The 19-column overlap and the four-way N50 spelling go away.
4. **A missing row means "this tool did not run"** — a fact worth recording. A null
   today means that, *and* "ran and reported nothing", *and* "ran before the column
   existed", indistinguishably.
5. **Adding a tool is a new table, not a migration.** The seqkit and chromosome
   blocks were added to live without going through `create_database.py`, which is how
   the ingest scripts got broken (§2). A new table cannot break an existing writer.

The cost is joins. `v2.v_ref_genomes` and `v2.v_draft_genomes` reproduce the current
wide shape exactly so nothing downstream changes on day one — the same
build-then-cutover approach as the lab tables, no flag day.

`coverage_summary` is the one existing consumer that must be rewritten, and it needs
a decision from §4 about which genomescope estimate it should be reading.

## 10. Open questions for the team

1. **What loads `ref_genomes` today, and where does its DDL live?** The current
   pipeline is not in any repo here, and the live table has drifted 14 columns and a
   primary-key change away from the last DDL under version control (§2). Bringing
   that writer into the Sqitch plan matters more than anything else in this document,
   because it is the reason the drift went unnoticed.
2. **For the 51 disagreeing rows in §3, which tool is right?** This needs a
   bioinformatician, not a schema change — the schema change only stops it recurring.
3. **Should `coverage_summary` use the HiFi or the Illumina genome-size estimate?**
   It currently reads `raw_qc`, which is the HiFi one, while summing both HiFi and
   Hi-C yields against it.
4. **Is `draft_genomes` a different pipeline or an earlier stage of the same one?**
   Only 76 og_ids overlap, which suggests genuinely different, but if it is the
   latter it should be `stage` values on `assembly`.
5. **Which of the four NCBI-tracking tables is authoritative?**
6. `k_mer_set` is empty in `ref_genomes` but populated in `draft_genomes` — is the
   ref-side merqury load dropping it, or is it not meaningful there?
