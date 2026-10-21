# Phase R plan — assembly relations: mitogenome split, draft-genome split, unconnected tables

Status: **R.0–R.5 done 2026-10-16** (`050`–`055` applied to live; pipeline branches ready, not
deployed). `056` (2026-10-19) reorders the `v3` mito and draft views: `og_num` first, columns
grouped by output. R.6, the merge, is next and has not started. Written 2026-10-15, after V.6; revised
2026-10-16 with the owner's answers, the draft pipeline's code, and the `v3` build approach.
Execution records: [`assembly_relations_r0_record.md`](assembly_relations_r0_record.md),
[`assembly_relations_rehearsal_r5.md`](assembly_relations_rehearsal_r5.md).
Source: `database_review.md` §7 ("Mitogenome and LCA tables", "`draft_genomes`"), §10 Lower #4
("Split `draft_genomes`", now promoted), and `docs/bioinformatics_data_review.md` §8–9. Previous
step: V.7 (close-out of the `v2` cutover). Migrations here number from `050` (`049` removed the
Hi-C drafts).

Owner decisions already taken (2026-10-15):

1. **Draft genomes only.** `ref_genomes` and its upload tables are out of scope. They are the
   obvious next phase, and §5 records them, but nothing here is designed for them.
2. **Surrogate keys.** Each new identity table gets `bigint GENERATED ALWAYS AS IDENTITY` as its
   primary key. Its natural key stays as a `UNIQUE` constraint, and child tables FK by id.

Owner decisions taken 2026-10-16 (answers to the first draft's open questions; details in the
sections named):

3. **No automatic "current" annotation.** Every annotation of an assembly is kept and shown. A
   person can mark one as selected, but that flag is optional and nothing else in the database
   reads it (§3.3).
4. **Genes long**, in `mito_annotation_gene`, with a wide view for reading (§3.4).
5. **`qc/99_genbank_submitter.py` is retired.** The four GenBank columns are empty on live, so
   they are dropped with nothing to move (§3.5).
6. **The `_rgj` (reference-guided join) step is gone from the pipeline.** The `_rgj` assemblies
   still in `mitogenome_data` stay, with their LCA rows. **Every ENA validation attempt on an
   `_rgj` assembly is removed**, whether or not the assembly still exists. `OG2936` is not
   submission-ready (§3.6).
7. **The draft-genome writer is `OceanOmics-OceanGenomes-Draft-Genomes`**, cloned at
   `~/OceanOmics-OceanGenomes-Draft-Genomes` (§2.2).
8. **`mito_assembly.stats` is not split.** Dropped from the plan.
9. **Declare the `og_workflow_*` → `sample` FKs** (§5, R.4).
10. **LCA and ENA rows whose annotation no longer exists are cleared**, not kept as stubs: they
    came from a misnamed or replaced annotation (§3.6).
11. **Everything new is built in a `v3` schema first**, beside `public`, tested there, and only
    then merged into `public` (§6.1).
12. **DepthSizer is retired.** Its existing values go into their own table, which is frozen: no
    writer, no new rows (§4.2).
13. **`import_v2.py` derives `seq_type` again**, with the old importer's rule (§2.3). This is an
    `OceanOmics-Database` change, outside the R steps.
14. **The 14 file columns, `host_haploid_size` and `partition_confidence` are dropped.** The file
    columns are historical and were not kept up to date. The upload scripts never push the two
    host columns (`FAMILY_COLUMNS` in `bin/draft_genome_stats.py` has only `host_assembly_size`
    and `host_assembly_fraction`). Their values stay in the archived table until R.8 (§4.3).

> **Evidence.** The first draft (2026-10-15) was measured from
> `~/oceanomics_genomes_pre_v6_261015.dump`, because live reads were unavailable that day. **Every
> figure was re-checked against live on 2026-10-16 (00:57 UTC) in a read-only session.** The
> mitogenome figures matched exactly. The live check corrected four things, which are now
> folded in below:
> - `draft_genomes` has 120 columns, not 119; a dump omits the generated `og_num`.
> - The 15 drafts with no Illumina run were assembled from a Hi-C run. They were removed on
>   2026-10-16 (`049`), and the run link stays Illumina-only.
> - gfastats and the assembly summary disagree far more than `ref_genomes` suggested.
> - `sequencing` is not unique on `(library_tube_id, run_id)`, because of 372 placeholder rows
>   (§2.3).
>
> A second read-only pass on 2026-10-16, after the owner's answers, measured the orphaned child
> rows (§3.6), the remaining `_rgj` assemblies, the GenBank columns (§3.5) and the N50 columns
> (§4.2). Live had moved slightly by then: 681 drafts carry both N50s, not 696.
>
> R.0 still re-runs the queries immediately before anything is built.

## 1. Why

The relational core is now sound: `sample → tissue → extraction → library → sequencing`, the
library registry, and the LCA tables FK'd to `mitogenome_data` and `sample`. The two analysis
tables that most of the bioinformatics hangs off are still flat, and most of the rest of the
database still has no relations at all.

- **`mitogenome_data` mixes two things with different cardinalities.** An assembly is made once.
  It can be annotated zero, one or several times: EMMA, then MITOS, then a MITOS rerun with a
  different genetic code. The table holds one row per assembly and one annotation in that row's
  columns. So:
  - **an assembly with no annotation carries 81 empty annotation columns** (374 rows);
  - **a re-annotation overwrites the previous one, and the rows that pointed at it are
    orphaned.** This has already happened. See §2.1.
- **`draft_genomes` is a dozen processes written sideways.** Each tool (fastp, GenomeScope, BUSCO,
  merqury, …) owns a block of columns. A sample that a tool never ran on gets a block of NULLs.
  A NULL can mean "did not run", "ran and reported nothing" or "ran before the column existed",
  and nothing tells them apart.
- **Many tables still have no FK in or out.** §5 goes through each of them.

The cure is the same in both halves: **one identity table, plus one table per thing that
happens to it.** A missing row means it did not happen. The empty-row picture people actually
want ("which samples are missing BUSCO?") becomes a view, not a property of the storage.

## 2. Current state, measured

### 2.1 `mitogenome_data`: 2,371 rows, 110 columns

The 110 columns fall into six groups with nothing left over:

| Group | Cols | Filled on |
|---|---:|---|
| Key `(og_id, tech, seq_date, code)` | 4 | all |
| Assembly result: `stats`, `length`, `avg_coverage`, `avg_base_coverage` | 4 | all (coverage 2,267) |
| Uniform depth: 12 `DEPTH_COLUMNS` + `depth_measured_at` | 13 | 1,954 `remap_full_v1`; 412 `not_measured`; 5 NULL |
| Annotation summary: `annotation`, `length_emma`, counts, `passed`, gene-order and `026` integrity blocks, … | 27 | 1,997 at most; the `026` block on 142 |
| Per-gene lengths (39) and translated lengths (15) | 54 | 1,997 at most; `atp9` on 29, `mtmuts` on 4 |
| Never populated: `seqlength_12s`, `seqlength_16s`, `seqlength_co1`, `status`, `genbank`, `bankit`, `genbank_accession`, `date_submitted_genbank` | 8 | **0** |

- **374 rows (16%) have no annotation.** On each one, all 81 annotation-side columns are NULL.
  `stats` alone shows why: 45 rows are `failed to assemble`, and the rest are scaffolds or
  discarded GetOrganelle variants that never reached annotation.
- Annotation values: `emma102` 1,836, `mitos2110` 145, `mito2110mc` 16.
- Cardinality: 1,206 samples have one assembly, and 420 have two to nine. Every
  `(og_id, tech, seq_date)` has one to four assembly codes.
- Gene columns are added by migration whenever biology demands. `atp9` and `mtmuts` came that
  way, for sponges and cnidarians, and fill 29 and 4 rows.

**The overwrite, with evidence.** The table has two unique keys: the primary key
`(og_id, tech, seq_date, code)` and `mitogenome_data_annotation_key`, which adds `annotation`.
Both writers upsert on the four-column key:

- `push_mtdna_assm_results.py:588`: `ON CONFLICT (og_id, tech, seq_date, code)`
- `push_emma_annotation_results.py:180`: the same

So a second annotation of the same assembly replaces the first in place. The children carry
`annotation` in their own primary keys, but their FK to `mitogenome_data` covers only the four
assembly columns. So they keep pointing at an annotation that no longer exists, and nothing
notices:

| Child | Rows | Distinct (assembly, annotation) | Annotation gone from its assembly | Assembly gone | Orphaned rows (live, 2026-10-16) |
|---|---:|---:|---:|---:|---:|
| `lca_validation` | 1,908 | 1,908 | 1 | 0 | 1 |
| `lca` | 4,951 | 1,800 | 2 | 0 | 8 |
| `lca_raw_results` | 46,914 | 1,800 | 2 | 0 | 74 |
| `blast_filtered_lca` | 243,695 | 1,837 | 3 | 0 | 443 |
| `ena_validation_attempts` | 1,188 | 1,188 | 2 | **3** | 5 |
| `ena_submissions` | 539 | 539 | 0 | 0 | 0 |

531 orphaned rows in all. Owner decision 10 clears them, and decision 6 adds one more `_rgj` ENA attempt: 532 rows (§3.6).

The worked example: OG3050 `ilmn.260909.getorg1770` was annotated with `mitos2110`, validated by
LCA, then re-annotated with `mito2110mc`. Its `lca_validation` row still says `mitos2110`. The
species validation is attached to an annotation the database no longer holds.

The five orphaned annotations are two different failures:

- **Replaced:** OG2628, OG3050 and OG3060 (`getorg1770`). The assembly now carries
  `mito2110mc`.
- **Wiped:** OG2951 and OG3000 (`getorg1770`). The assembly now carries **no annotation at
  all**. Their LCA and ENA rows describe a `mitos2110` annotation that has been erased, leaving
  the assembly looking never-annotated.

Both are what an assembly-keyed upsert does to a 1:N relationship.

The three ENA attempts whose assembly is gone are worth triage on their own. One of them,
`OG2936.ilmn.260909.getorg1770_rgj.mitos2110`, is `webin_status = PASS` and
`submission_ready = true` for an assembly code that `mitogenome_data` no longer has. On live,
those three samples now have `_concat` and `_mc` assemblies (each annotated `mitos2110`) where the
`_rgj` codes used to be. So the `_rgj` assemblies appear to have been renamed or replaced after
ENA validated them (recorded 2026-09-29). The attempts are left pointing at codes that no longer
exist:

| full_seqid | webin_status | submission_ready |
|---|---|---|
| `OG2936.ilmn.260909.getorg1770_rgj.mitos2110` | PASS | **t** |
| `OG2982.ilmn.260909.getorg1770reseed_rgj.mitos2110` | NOT_RUN | f |
| `OG3038.ilmn.260909.getorg1770reseed_rgj.mitos2110` | NOT_RUN | f |

**Resolved by the owner (2026-10-16):** the `_rgj` (reference-guided join) step has been removed
from the pipeline, so these attempts describe assemblies that will never come back. They are
removed with the other orphans (§3.6). `OG2936` is not submission-ready, so its `PASS` /
`submission_ready = true` must not reach ENA.

**35 other `_rgj` assemblies are still in `mitogenome_data`** (live, 2026-10-16), from `seq_date`
230324 to 260605: 27 annotated `emma102` and 8 unannotated. Unlike the three above, they still
exist, and they have children: 25 `lca_validation`, 58 `lca`, 366 `lca_raw_results`, 715
`blast_filtered_lca` and 4 `ena_validation_attempts` rows (none in `ena_submissions`).
**Decided (owner decision 6):** the assemblies and their LCA rows stay and are carried across
unchanged. The ENA attempts go. Three of the four are the orphans above; the fourth is
`OG562.ilmn.230419.getorg1770reseed_rgj.emma102` (`NOT_RUN`, not submission-ready), whose
assembly still exists. Nothing has an FK to `ena_validation_attempts`. Four views read it
(`ena_submission_status`, `ena_validation_latest`, `mitogenome_submission_view` and its
`_pre_v2` copy), and they simply stop showing the row.

All of the orphans are from the 2026-09-09 batch, the first with several annotators in play. So
this is new and growing, not legacy.

**Writers and readers.**

- Writers are all in `Oceanomics-OceanGenomes-Mitogenomes/bin/`:
  - `push_mtdna_assm_results.py` writes the assembly result, plus a depth-only update path
    guarded to `DEPTH_COLUMNS`;
  - `push_emma_annotation_results.py` writes the annotation summary and genes as one unit;
  - `push_lca_*`, `push_species_validation.py` and `push_ena_validation_results.py` write the
    children.
- The reader views are `mitogenome_submission_view`, and through the children
  `lca_validation_report_view`, `lca_pivot_view`, `lca_results_view`, `filtered_lca_view`,
  `summary`, `sample_view` and `embargo_assignment_view`.
- Pipeline readers: `prepare_ena_metadata.py`, `audit_ena_readiness.py`,
  `compile_upload_report.py`, `compile_held_completeness.py`, `build_source_modifiers.py`,
  `backfill_ena_specimen_accessions.py`, `mitogenome_assembly_summary.py` and
  `qc/99_genbank_submitter.py`.

### 2.2 `draft_genomes`: 1,735 rows, 120 columns, PK `(og_id, seq_date)`

No migration creates this table (review Phase C.0). Its newer columns (extended GenomeScope,
host partition, stop codons) arrived by direct DDL. The 120 columns partition exactly into the
blocks below, with no column unassigned and none in two blocks:

| Block | Cols | Rows with any | Written by (pipeline family, §2.2 writers) |
|---|---:|---:|---|
| Key: `og_id`, `seq_date`, `mach`, `initial`, `og_num` | 5 | 1,735 | `mach_seqdate_initial` is the `run_id` of the run the reads came from; `mach`, `initial` come from `fastp` |
| fastp: filter, raw and clean read stats | 23 | 1,734 | `fastp` |
| GenomeScope | 7 | 1,426 | `assembly` (GenomeScope2 summary) |
| GenomeScope extended: `*_min`, `modelfit_allkmers`, `genome_size_reliable`, `genome_size_flags`, `kmercov`, `lambda_depth` | 10 | 80 | `assembly`: the six `*_min`/`allkmers` from the summary, the other four from `*_coverage_summary.json` |
| Contig classification: mitochondrion / plastid / prokarya counts and bp | 6 | 1,425 | `decontamination`, **Tiara** (confirmed: `parse_tiara`) |
| Contigs under 500 bp: `num_contigs` | 1 | 1,425 | `decontamination`, BBMap filter step's `*contig_count_500bp.txt`. **Not a total contig count**, despite its name |
| BUSCO | 7 | 1,405 | `busco` |
| Assembly summary: scaffolds, contigs, length, gaps, N50s | 6 | 1,405 | `busco`: **BUSCO's own assembly stats**, from the same short-summary JSON |
| merqury QV + completeness | 8 | 1,402 | `merqury`, always together |
| Contamination screen: exclude / trim / review | 6 | 701 | `decontamination`, **FCS-GX** report via BBMap `filterbyname` (confirmed) |
| DepthSizer | 6 | 701 | **Retired** (owner decision 12). The only writer found is the legacy `OceanOmics-Database/SS/import_data_draft_mergedresults.py` |
| Internal stop codons | 2 | 701 | `busco` (**BUSCO**, confirmed) |
| gfastats (`gfa_*`) | 7 | 696 | `gfastats`; overlaps the assembly summary |
| Host partition | 4 | 68 | `host_assembly_size`, `_fraction`: `assembly`, from the coverage summary. `host_haploid_size`, `partition_confidence`: **no writer; dropped** (owner decision 14) |
| Files: `aws_r1/r2/assm`, `fastp_r1/r2`, `sra_r1/r2`, each with a size | 14 | 697 / 642 / 164 | not this pipeline; historical, **dropped** (owner decision 14) |
| Submission: SRA, BioSample, BioProject, study, ERZ, GCA, comment, `sra_date_submitted` | 8 | 579 | `ENA-draft-genomes` steps 06–07 (column comments); `sra_date_submitted` is **0** |

The block boundaries above are the first draft's, by column meaning. The writer column shows
they do not line up with the processes that write them: the `busco` family writes three blocks
(BUSCO, assembly summary, stop codons), and `decontamination` writes Tiara, FCS-GX and the
under-500 bp count. §4.2 splits by writer.

- **309 rows carry fastp and nothing else.** 199 of them are from 2026 runs and 85 from 2025, so
  most are probably *not yet* assembled, not abandoned. Either way, today each shows about 90
  NULL columns that cannot say which.
- The table is not sparse the way `ref_genomes` is, but it has **two populations of assembled
  runs**. The 701 assembled from `seq_date` 250606 onwards carry the newer blocks
  (contamination, DepthSizer, stop codons, gfastats). The 703 from 221003 to 250520 have none
  of them. Those, plus the fastp-only rows, are the "empty rows" the owner sees.
- 27 `og_id`s have two or three rows (resequencing). 0 orphans against `sample`.
- **Every row matches a sequencing run.** All 1,735 `(og_id, seq_date)` pairs match a
  `sequencing` row through library → extraction → tissue. Fifteen of them (seq_date `251118`)
  match only run `NEXT_251118_AD`.
  - That run is entirely shallow Hi-C: 15 `_HICL` libraries on a NextSeq, `hic_depth = Shallow`.
  - **These 15 are draft assemblies of Hi-C reads.** They are 0.6–99 Mb long, against a median
    of 829 Mb for other drafts. BUSCO completeness is 0.0–1.1%, against a median of 56.1%.
    GenomeScope sizes are 0.1–3.2 Mb.
  - None carries a submission accession.
  - 14 of the 15 samples already have a reference assembly in `ref_genomes`, and 6 have a
    proper Illumina draft on an earlier date.
  - **Removed 2026-10-16 by migration `049`** (owner decision), archived in
    `archive/draft_genomes_hic_251118/`. Live now has 1,720 drafts.
  - **The run link is Illumina-only** (owner decision 2026-10-16). A draft genome is an
    Illumina assembly, so `draft_genome_run` may reference only Illumina sequencing rows, and the
    push step should reject anything else at write time.
- Before the §2.3 cleanup, the counts were inflated by placeholder duplicates: 1,383 drafts
  matched one Illumina row and 350 matched two. **On live after both cleanups (2026-10-16), all
  1,720 drafts match an Illumina run: 1,675 match one and 45 match two.** The 45 are two
  different things:
  - **40 (`seq_date` 250331) are one library on two runs:** an iSeq QC run (`ISEQ_250331_AD`,
    51 samples) and the NovaSeq run (`NOVA_250331_AD`) the reads actually came from. The draft's
    own `mach` is `NOVA`. Matching `mach` to the instrument (`NOVA` → NovaSeq,
    `NEXT` → NextSeq) leaves each of them one run.
  - **5 (`seq_date` 230814: OG3, OG9, OG11, OG22 and OG23) are two libraries on one run:**
    `_D_IL` and `_D2_IL`, both on `NOVA_230814_LP`. Their read counts, 500–857 M reads and
    74–127 Gb, against a median of 52.7 Gb, suggest the assembly pooled both libraries. These
    are the genuine many-to-many cases; confirm with the pipeline owner.
  - Joining on the draft's full run ID (`mach_seqdate_initial`) would be stricter, but it fails
    42 drafts: their stored `initial` disagrees with the run ID in `sequencing` (`LP_Jess`
    against `NOVA_230607_LP` for OG206–OG226, and `AD` against `NOVA_250606_ADJP` for 21
    others). Fixing those initials would let the join use the run ID. Until then, `mach` plus
    `seq_date` is the reliable key.
- **Reader:** `v_genome_size_comparison`.
- **Writers (found 2026-10-16, owner decision 7).** In `OceanOmics-OceanGenomes-Draft-Genomes`
  (`d384e4c`), every metric write goes through one function:
  - `bin/draft_genome_stats.py`, `upsert_record()`:
    `INSERT INTO draft_genomes (og_id, seq_date, <family columns>) … ON CONFLICT (og_id, seq_date)
    DO UPDATE SET <family columns>`. `FAMILY_COLUMNS` lists six families: `fastp`, `assembly`,
    `decontamination`, `busco`, `merqury` and `gfastats`.
  - Six thin CLIs call it (`bin/push_{fastp,assembly_results,decontamination_results,busco_results,merqury_results,gfa_results}_to_sqldb.py`),
    each run by a `PUSH_*` process in `modules/local/upload_results/`, wired in
    `subworkflows/local/upload_results/main.nf`.
  - `bin/backfill_draft_genome_stats.py` re-parses published archives and calls the same
    upsert. It also reads back through `fetch_database_record()` (`SELECT … FROM draft_genomes`)
    to verify.
  - The table name appears in exactly two SQL strings, so R.5's writer change is one module, not
    six.
  - **Columns with no writer in any repository here** (searched: this pipeline including its
    full git history, `OceanOmics-Database`, `OceanOmics-OceanGenomes-ref-genomes`, the
    mitogenome pipeline):
    - `host_haploid_size`, `partition_confidence`: 68 rows, **all `seq_date` 260909**, the same
      68 rows as `host_assembly_size` (which the pipeline does write). They look like a
      one-off load during the NOVA_260909_LA rerun (`scripts/rerun_NOVA_260909_LA/`), not a
      pipeline step. Example: OG3024, haploid 306 Mb, assembly-host 357 Mb, confidence `high`.
    - The 14 file columns: paths, not metrics (`aws_r1` = `OG623.ilmn.230419.R1.fastq.gz`,
      `aws_assm` = `OG623.ilmn.230419.v129mh.fna`, `sra_r1` =
      `OG623.ilmn.NOVA_230419_AD2.R1.fq.gz`). Last filled for `seq_date` 250520 (`aws_*`),
      250214 (`fastp_*`) and 230814 (`sra_*`). So they record the old AWS backup and SRA upload
      and have stopped; the backup scripts in `scripts/backup_scripts/` do not write the
      database.
  - **Not written by this pipeline:** DepthSizer (retired), `host_haploid_size`, `partition_confidence`,
    the 14 file columns and the submission block. The submission block is
    `ENA-draft-genomes` steps 06–07, per the column comments. The rest are retired or dropped
    (owner decisions 12 and 14). `OceanOmics-Database/SS/04_push_results_to_sqldb.py` is the stale original, fastp only.

### 2.3 Found on the way: stale `sequencing` rows

> **Resolved 2026-10-16.** `import_v2.py` now deletes `sequencing` rows the workbook no longer
> carries and quarantines blank or incomplete run IDs (`OceanOmics-Database/README.md`). Its
> first run on live, with `--max-stale-sequencing 500` against `OceanGenomes_Database_261015.xlsx`,
> removed all 458 stale rows, and live now has 4,460. Each is kept whole in `import_quarantine`.
> No duplicate `(library_tube_id, run_id)` group remains. The 12 placeholders still in the
> workbook stay, and are quarantined for the lab with `OG779G_D2_IL_NEXT_`. Rehearsed first on a
> restore of live, which gave an identical result. Not done: the 193 placeholders' `seq_type`
> was not carried over, and `import_v2.py` still does not derive `seq_type` (now decided: it will; see `seq_type` below).
> The analysis as written before the fix follows.

This is outside the scope of this phase, but it blocks two steps in it, so it is recorded here.
Checked against live and `OceanGenomes_Database_261015.xlsx` on 2026-10-16.

**The workbook builds the ID by formula.** `5.Sequencing`'s `Sequencing ID` is
`=CONCATENATE(B,"_",J)`, that is, `Library Tube ID & "_" & Sequencing Run ID`. A row entered
before its run ID gets the ID `<tube>_`. Once the run is filled in, the ID changes to
`<tube>_<run_id>`.

**The database keeps every ID it has ever seen.** The importers upsert on `sequencing_id`.
`import_v2.py` only deletes rows on tables with an attempt key, and `sequencing` has none. So a
row whose ID changes, or that leaves the workbook, stays in the table. On live, **458 of 4,918
`sequencing` rows are not in the 2026-10-15 workbook**:

- **360 are `<tube>_` placeholders.** These IDs were in the workbook once and are not now.
- **98 are full IDs that the lab removed or renamed.** For example, 61 rows on `NOVA_260724_AD`.

**The 372 placeholders on live** (`sequencing_id = library_tube_id || '_'`):

| | Rows |
|---|---:|
| Still in the 2026-10-15 workbook | 12 (`OG1310O`–`OG1322O_D_IL`, status `Sequenced` with no run ID entered) |
| Not in the workbook: stale | 360 |
| Has a canonical `<tube>_<run_id>` twin | 356 |
| … identical to the twin apart from the ID | **17** |
| … differs from the twin | 339 |
| No twin | 16 (the 12 above; 3 HiFi placeholders whose run differs from their tube's real run; `OG779G_D2_IL_`, whose twin is `OG779G_D2_IL_NEXT_`, a truncated run ID that is also in the workbook) |

**They are not exact duplicates.** Where a placeholder and its twin differ, it is always one of
three columns:

- `seq_type`: 193 placeholders say `Illumina`, and their twin is NULL.
- `status`: 146 placeholders are NULL, and their twin says `Sequenced`.
- `smrt_num`, `cell_id`, `hic_depth`: 15, 5 and 12 rows respectively, where the twin carries the
  value (or a different `smrt_num`, 1 against 0, on 10).

**All 372 were inherited.** Every one was already in the pre-`v2` table (now
`pre_v2_archive.sequencing_pre_v2`, which holds 374 `_`-terminated IDs), and the V.4 backfill
copied them across.

- In 193 pairs, the twin was created afterwards by `import_v2.py`. That importer does not
  write `seq_type` (`name_convert_v2.py:30`; the old `import_data.py` computed it), which is why
  only the placeholder has it.
- In the other 163 pairs, both rows were already in `public` before `v2`.

It is not known from here how pre-`v2` placeholders came to carry a `run_id` while their ID
lacks one. A formula value cached before recalculation is the likely route.

**`seq_type` (owner decision 13).** `import_v2.py` derives `seq_type` again, with the rule the
old `import_data.py` used (lines 135–165): `Hi-C` → `HiC`; `Illumina` → `Illumina` for a `_D`
tube and `RNA` for an `_R` tube; `ONT` → `ONT`; any `PacBio*` → `PacBio` for `_D` and `RNA` for
`_R`; anything else is quarantined, not raised. On live (2026-10-16) that rule reproduces every
non-NULL value exactly (4,267 rows), and all 193 NULLs are Illumina `_D` tubes, so the first run
fills them with `Illumina`. The mapping in `name_convert_v2.py:30` that was removed stays
removed: the value is derived, not read from the workbook's `Type` column. Nothing in this plan
depends on it (`draft_genome_run` uses `technology`), so it can land any time.

**Consequences:**
- `(library_tube_id, run_id)` cannot be made unique, so the QC foreign keys in §5 cannot target
  it;
- any per-run count from `sequencing` (including `summary` and the samplesheet builders)
  double-counts these runs;
- the draft-to-run link in §4.1 must exclude them.

**Fix (R.0, before R.3 and R.7). Done 2026-10-16; see the note above:**
1. **Resolve the 344 stale placeholders that have a twin. Merge first, then delete:**
   - fill the twin's NULL `seq_type` from the placeholder, or better, have `import_v2.py`
     derive `seq_type` from the library type as the old importer did, which also fixes the
     other 193 NULLs on live;
   - keep the twin's values everywhere else;
   - then delete the placeholder.
2. **Hand to the lab:**
   - the 12 workbook rows marked `Sequenced` with no run ID;
   - `OG779G_D2_IL`'s `NEXT_` run ID;
   - the 3 HiFi placeholders.
3. **Stop it recurring.** `sequencing` needs the same "the workbook no longer carries it"
   handling the attempt-keyed tables have: delete it, keeping the row as `displaced`, when
   nothing references it. That also clears the 98 other stale rows. Separately, quarantine any
   workbook row whose run ID is blank or truncated, so an ID is never minted before its run
   exists.

## 3. Design: mitogenome

```text
sample
  └─ mito_assembly                 one per (og_id, tech, seq_date, code)
       ├─ mito_assembly_depth      0..1   remap depth (MITOGENOME_COVERAGE)
       ├─ mito_assembly_run        0..n   → sequencing   (§5)
       └─ mito_annotation          0..n   one per annotator run; all kept; optional is_selected, read by nothing
            ├─ mito_annotation_gene  0..n   one row per gene
            ├─ lca / lca_raw_results / blast_filtered_lca / lca_validation
            └─ ena_validation_attempts / ena_submissions
```

### 3.1 `mito_assembly`

```sql
CREATE TABLE mito_assembly (
    assembly_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id             text NOT NULL REFERENCES sample(og_id),
    tech              text NOT NULL,
    seq_date          text NOT NULL,     -- identifier component, not a date (review Phase G.3)
    code              text NOT NULL,
    stats             text,
    length            integer,
    avg_coverage      real,              -- legacy, assembler-specific; see mean_depth
    avg_base_coverage real,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT mito_assembly_natural_key UNIQUE (og_id, tech, seq_date, code),
    CONSTRAINT mito_assembly_tech_check CHECK (tech IN ('ilmn', 'hifi', 'hic'))
);
```

`stats` mixes topology and scaffold count (`circular genome`, `3 scaffold(s)`,
`failed to assemble`). It stays one column (owner decision 8).

### 3.2 `mito_assembly_depth`

This is a separate table because a separate process writes it, at a separate time. The
writer's own comments already treat it as a different thing ("adding a depth to a preserved
row can never rewrite the assembly result it belongs to"). A separate table makes that
guarantee structural, not a matter of code discipline.

```sql
CREATE TABLE mito_assembly_depth (
    assembly_id            bigint PRIMARY KEY REFERENCES mito_assembly ON DELETE CASCADE,
    depth_method           text NOT NULL,
    mean_depth             double precision,
    median_depth           double precision,
    depth_sd               double precision,
    depth_cv               double precision,
    breadth_1x             double precision,
    breadth_10x            double precision,
    mito_mapped_reads      bigint,
    total_reads            bigint,
    mito_read_fraction     double precision,
    depth_target_length_bp integer,
    depth_target_fasta     text,
    depth_measured_at      timestamptz
);
```

- **`not_measured` is stored (changed when built, `051`).** The first draft dropped these
  rows, on the reading that the 412 carry nothing else. On live every one of them carries
  `depth_measured_at`: the time the depth step ran and measured nothing. That is an event, so
  each is a row with `depth_method = 'not_measured'` and NULL measurements. The 5 assemblies
  with NULL `depth_method` were never touched by the step and have no row. Every measured row
  today is `remap_full_v1`. No `legacy_*` label from `003` survives in the data; if one
  reappears, it is information and belongs in this table.
- `DEPTH_METHOD_NOT_MEASURED` keeps its meaning in the writer: a new assembly with no depth
  gets a `not_measured` row.

### 3.3 `mito_annotation`

```sql
CREATE TABLE mito_annotation (
    annotation_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assembly_id      bigint NOT NULL REFERENCES mito_assembly ON DELETE CASCADE,
    annotation       text NOT NULL,          -- annotator+version: emma102, mitos2110, mito2110mc
    is_selected      boolean NOT NULL DEFAULT false,   -- set by a person only; see below
    selected_by      text,
    selected_at      timestamptz,
    length_emma, cds_no, trna_no, rrna_no,
    extra_genes, missing_genes, passed, trna_advisory,
    order_correct, order_status, order_variant, order_variant_taxon_check,
    order_deviation, order_deviation_detail, annotation_gaps,
    expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories,
    mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci,
    annotation_integrity_status, annotation_integrity_issues,
    annotation_stats_version, annotation_updated_at, manual_curation_notes,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT mito_annotation_natural_key UNIQUE (assembly_id, annotation)
);
CREATE UNIQUE INDEX mito_annotation_one_selected
    ON mito_annotation (assembly_id) WHERE is_selected;
```

Column types carry over from `mitogenome_data` unchanged, so no value changes in the move.
Tightening `passed` (`yes` / `no`) to `boolean` and constraining the status vocabularies is
worth doing, but it goes in a later migration, after the split has been reconciled.
Combining the two would make a failed `EXCEPT ALL` ambiguous about which change caused it.

**No annotation is made "current" (owner decision 3).** Every annotation of an assembly is kept,
and every one is visible: in the compatibility view (§3.7), in `v_mito_annotation_genes` (§3.4)
and to ENA, which already keys on `full_seqid` and so on the annotation.

**`is_selected` is an option, not a mechanism.** It is there for anyone who wants to record a
choice, and it affects nothing else:

- no writer sets or clears it, and the backfill sets none;
- a person who chooses sets `is_selected`, `selected_by` and `selected_at` on one annotation, and
  the partial unique index allows at most one per assembly;
- **no view, FK, trigger or pipeline reads it.** The compatibility view, the ENA views, `summary`
  and the LCA views behave the same whether it is set or not. Only `v_mito_annotation_genes`
  shows it, as a plain column for whoever is looking.

### 3.4 `mito_annotation_gene`

```sql
CREATE TABLE mito_annotation_gene (
    annotation_id     bigint NOT NULL REFERENCES mito_annotation ON DELETE CASCADE,
    gene              text   NOT NULL REFERENCES mito_gene(gene),
    length            integer,
    translated_length integer,     -- protein-coding genes only
    PRIMARY KEY (annotation_id, gene)
);
-- mito_gene: lookup of the 39 current gene names (rrna12s … trna_gln, atp9, mtmuts),
-- with gene_class ('pcg', 'rrna', 'trna') and the legacy column name, for the view.
```

- **This replaces 54 columns with one table and a lookup.** The next lineage-specific gene
  becomes an `INSERT` into `mito_gene`, not a migration on a 2,000-row table and an edit to
  both writers.
- It also removes a real ambiguity. Today a NULL `atp9` on a fish could mean "not present",
  "not looked for" or "the column did not exist yet". In the new table, no row means not
  annotated, and the annotation's `missing_genes` says why.
- **Cost:** 72,063 rows (one per non-NULL gene value today), and a pivot in the
  compatibility view. Both are small.
- **Decided long (owner decision 4), with a view to read it wide.** `v_mito_annotation_genes`
  has one row per annotation: the assembly key, `annotation`, `is_selected` (display only), then one length
  column per gene and one translated-length column per protein-coding gene, in the old column
  names and order (`max(length) FILTER (WHERE gene = 'cox1') AS cox1`, …). It is the same pivot
  the compatibility view uses, kept separately so people can browse genes without the other
  80 columns.
  - The view's gene list is generated from `mito_gene`. A new gene is still an `INSERT`, plus a
    `CREATE OR REPLACE VIEW` that a helper function (`v3.rebuild_mito_gene_views()`) writes from
    the lookup, so nobody hand-edits 54 `FILTER` lines.

### 3.5 Dropped columns

The eight never-populated columns are not carried forward:

- `seqlength_12s`, `seqlength_16s`, `seqlength_co1` and `status`: 0 of 2,371 rows.
- `genbank`, `bankit`, `genbank_accession` and `date_submitted_genbank`: GenBank tracking from
  before the move to ENA. `qc/99_genbank_submitter.py`, their only reader, is retired (owner
  decision 5).
  - **They hold nothing to keep.** On live (2026-10-16) all four are empty on all 2,371 rows of
    `mitogenome_data` and all 2,349 rows of `pre_v2_archive.mitogenome_data_pre_v2`. A scan of
    every text column of every `public` base table (outside the LCA and NCBI reference tables)
    for an INSDC-style accession found none. So no GenBank table is built.

They survive in the archived `mitogenome_data` until R.8. Review principle 10 (document before
removing) is met by this section and by the object comment on the archived table.

### 3.6 Re-parenting the children

`lca`, `lca_raw_results`, `blast_filtered_lca` and `lca_validation` each gain
`annotation_id bigint NOT NULL REFERENCES mito_annotation`. It is backfilled by joining on the
five natural columns. The same goes for `ena_validation_attempts` and `ena_submissions`. Once
the orphans below are cleared, every ENA row resolves too, so their `annotation_id` is
`NOT NULL` as well. (The first draft made it nullable only to hold the three `_rgj` orphans.)
The pipeline no longer produces `_rgj` assemblies, so none can gain a new ENA attempt.

**Orphans are cleared, not kept as stubs (owner decision 10).** A child row whose
`(assembly, annotation)` is not on its assembly came from a misnamed or replaced annotation, and
it is removed. The first draft's `backfilled_stub` rows are dropped from the design. On live
(2026-10-16) that is **531 rows** across 8 annotations, plus one `_rgj` ENA attempt whose
assembly still exists (owner decision 6), **532 rows** in all:

| Annotation | Why orphaned | Rows cleared |
|---|---|---|
| OG2628, OG3050, OG3060 `getorg1770.mitos2110` | replaced by `mito2110mc` | `lca_validation` 1, `lca` 8, `lca_raw_results` 74, `blast_filtered_lca` 443 |
| OG2951, OG3000 `getorg1770.mitos2110` | annotation wiped | `ena_validation_attempts` 2 |
| OG2936 `getorg1770_rgj`, OG2982 and OG3038 `getorg1770reseed_rgj` (`mitos2110`) | assembly gone (`_rgj` step removed, owner decision 6) | `ena_validation_attempts` 3, including OG2936's `submission_ready = true` |
| OG562 `getorg1770reseed_rgj.emma102` | not orphaned; an `_rgj` ENA attempt (owner decision 6). The assembly and its LCA rows stay | `ena_validation_attempts` 1 |

- This is a destructive step on `public`, so it is its own migration (`050`, R.1), before
  anything is built in `v3`. Rows are archived first, to `archive/mito_orphans_260909/` as CSV
  and to a `pre_v3_archive` table, the way `049` archived the Hi-C drafts.
- The OG3050 `lca_validation` row is the one species validation lost. If that species check
  matters, it should be re-run on the `mito2110mc` annotation, which has none.
- OG2951 and OG3000 then look exactly as they are: assemblies with no annotation. Re-annotating
  them is pipeline work, not part of this plan.

**Natural columns stay for one release.** The children keep `og_id`, `tech`, `seq_date`, `code`
and `annotation` while `push_lca_*` and the ENA writers learn to send `annotation_id`. A
`CHECK`-equivalent trigger keeps the two consistent in the meantime. After that, a later
migration drops the natural columns from the four LCA tables, re-keys their primary keys to
`(annotation_id, …)`, and has the views join through `mito_annotation` for `og_id`. The ENA
tables keep `full_seqid` permanently, because it is the identifier ENA knows them by.

### 3.7 Compatibility

- **A view named `mitogenome_data`** reproduces today's 102 live columns: the 110 less the
  eight dropped.
  - **One row per (assembly, annotation)**, because every annotation is visible (owner
    decision 3), plus one row for each unannotated assembly. That is the grain the table's own
    `mitogenome_data_annotation_key` already describes. It LEFT JOINs depth and pivots genes
    back to columns, as `v_mito_annotation_genes` does. It does not show `is_selected`, so its
    shape is exactly today's.
  - **On day one it returns exactly today's 2,371 rows,** because the overwrite has left every
    assembly with one annotation at most. It grows past one row per assembly only when an
    assembly is re-annotated.
  - An unannotated assembly shows NULLs there exactly as today. The difference is that the
    NULLs are now computed, not stored.
  - **Column order (`056`, 2026-10-19).** The view no longer copies the old table's order, which
    recorded when each column was added. It opens with `og_num`, `og_id` and
    `nominal_species_id` (two columns more than the old table), then the assembly key, and then
    one block per output: assembly, depth and coverage, annotation, and genes (rRNA, each
    protein-coding gene beside its `_trans`, tRNA). `draft_genomes`, `mitogenome_submission_view`,
    `v_mito_annotation_genes`, `v_genome_size_comparison` and `v_draft_genome_status` follow the
    same rule. **Read these views by column name, never by position.**
  - Every reader in §2.1 keeps working on day one. **R.0 lists the readers that assume one row
    per assembly** (that select by `(og_id, tech, seq_date, code)` without `annotation`).
    Those must handle several rows (by grouping, or by choosing in their own logic) before the
    first re-annotation lands. They must not rely on `is_selected`, which nothing maintains. `mitogenome_assembly_summary.py` and `summary` are the likely ones.
    The ENA readers key on `full_seqid` and are unaffected.
- **`mitogenome_submission_view`** is rebuilt on the new tables. Its annotation join, `028` and
  `029`'s five-column key, becomes `annotation_id`, which is what that key was trying to be.
- **Writers cannot go through the view.** `INSERT … ON CONFLICT` cannot target a view, and an
  `INSTEAD OF` trigger cannot emulate `ON CONFLICT` against two tables honestly. So the writers
  change first (R.5), as the importer did before V.5.
- **The merge moves the old table out of the way (§6.1).** `public.mitogenome_data` (the
  table) moves to `pre_v3_archive`, and `v3.mitogenome_data` (the view) moves into `public` and
  takes the name. An old writer then fails with "cannot insert into view" on its first run. It
  does not silently write somewhere nobody reads.

## 4. Design: draft genome

```text
sample
  └─ draft_genome                 one per (og_id, seq_date)
       ├─ draft_genome_run        1..n  → sequencing      (which runs it was built from)
       ├─ draft_fastp             0..1
       ├─ draft_genomescope       0..1
       ├─ draft_tiara             0..1
       ├─ draft_contamination     0..1   FCS-GX + contigs < 500 bp
       ├─ draft_busco             0..1   incl. BUSCO's assembly stats and stop codons
       ├─ draft_merqury           0..1
       ├─ draft_depthsizer        0..1
       ├─ draft_gfastats          0..1
       └─ draft_submission        0..1
```

### 4.1 Identity and run link

```sql
CREATE TABLE draft_genome (
    draft_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id      text NOT NULL REFERENCES sample(og_id),
    seq_date   text NOT NULL,
    mach       text,            -- NOVA / NEXT
    initial    text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT draft_genome_natural_key UNIQUE (og_id, seq_date)
);

CREATE TABLE draft_genome_run (
    draft_id      bigint NOT NULL REFERENCES draft_genome ON DELETE CASCADE,
    sequencing_id text   NOT NULL REFERENCES sequencing(sequencing_id),
    PRIMARY KEY (draft_id, sequencing_id)
);
```

- `draft_genome_run` is backfilled from the join in §2.2: `(og_id, seq_date)` through
  `v_sequencing_browse`, **Illumina DNA libraries only (`library_type = 'illumina'`, added by
  `055`: RNA libraries share the technology), and the instrument must match the draft's `mach`**
  (`NOVA` → NovaSeq, `NEXT` → NextSeq). This keeps out the iSeq QC runs. On live (2026-10-16),
  that gives 1,715 drafts one row and 5 two rows (the pooled libraries in §2.2). Every draft
  gets at least one.
- **Illumina only, enforced.** A trigger on `draft_genome_run` rejects a `sequencing_id` that
  is not an Illumina DNA library (`055`). A plain `CHECK` cannot read another table. This is what stops
  a repeat of the 15 Hi-C drafts that `049` removed. A draft with no Illumina run cannot be
  linked, and R.0 lists any such draft.

### 4.2 One table per process

Each table has `draft_id bigint PRIMARY KEY REFERENCES draft_genome ON DELETE CASCADE`, the
block's columns with their current types, and `loaded_at timestamptz NOT NULL DEFAULT now()`.

The tables follow the writer (§2.2): one table per thing the pipeline runs, so each `PUSH_*`
step writes exactly one table.

| Table | Columns from `draft_genomes` | Rows | Writer |
|---|---|---:|---|
| `draft_fastp` | `passed_filter_reads` … `gc_content` (23) | 1,734 | `fastp` |
| `draft_genomescope` | the 7 core + 10 extended, nullable, + `host_assembly_size`, `host_assembly_fraction` (68 rows), + generated `output_set` | 1,426 | `assembly` (GenomeScope summary + coverage summary) |
| `draft_tiara` | `num_contigs_mitochondrion/plastid/prokarya`, `bp_*` (6) | 1,425 | `decontamination` (Tiara) |
| `draft_contamination` | `num_contigs_exclude/trim/review`, `bp_exclude/trim/review` (6), and `num_contigs` stored as **`num_contigs_lt_500bp`** | 1,425 (701 with FCS-GX values) | `decontamination` (FCS-GX + BBMap) |
| `draft_busco` | `complete` … `domain` (7); BUSCO's assembly stats `number_of_scaffolds`, `number_of_contigs`, `total_length`, `percent_gaps`, `scaffold_n50`, `contigs_n50` (6); `internal_stop_codon_count`, `_percent` (2) | 1,405 | `busco` |
| `draft_merqury` | QV (4) + completeness (4) | 1,402 | `merqury` |
| `draft_gfastats` | `gfa_*` (7) | 696 | `gfastats` |
| `draft_depthsizer` | `depmethod` … `estgenomesize` | 701 | **none: frozen** (owner decision 12) |
| `draft_submission` | SRA, BioSample, BioProject, study, ERZ, GCA, comment | 579 | `ENA-draft-genomes` 06–07; `sra_date_submitted` dropped (0 rows) |

- **Changed from the first draft.** `draft_assembly_summary` and `draft_stop_codon` fold into
  `draft_busco`, because BUSCO writes them in the same record. The contig-classification table
  is now `draft_tiara`, and `num_contigs` moves to `draft_contamination` under an honest name.
  The compatibility view still calls it `num_contigs`.
- **No host-partition table.** `host_assembly_size` and `_fraction` arrive in the same `assembly`
  record as the GenomeScope verdict, from `*_coverage_summary.json`, so they go on
  `draft_genomescope`. They are NULL where the coverage summary did not compute them, which is
  the same labelled case as the extended columns. The other two host columns are dropped (§4.3).
- **`draft_depthsizer` is a frozen archive of a retired tool.** It is loaded once by the backfill
  and has no writer. It is left out of `scripts/sync_v3.sql` after the first copy, and its
  object comment says it is retired and closed. `v_draft_genome_status` leaves it out of
  `processes_done` and the per-process flags, so a new draft is never shown as "missing
  DepthSizer". The `draft_genomes` compatibility view no longer shows its six columns (`056`;
  §4.3).
- `draft_busco` gains `lineage` from the BUSCO filename tag (`buscoLineageTag`) if the writer
  passes it. Today `domain` is the only lineage information stored.

**Extended GenomeScope stays in the GenomeScope table.** It is the same tool's output from a
newer version of the script, not a separate process. Its columns are NULL on the 1,346 older
rows because that version did not compute them, and `output_set` (`core` / `extended`, a
generated column, so no writer has to set it) says which is which.
That is the one place a NULL inside a process table is intended. It is labelled, not ambiguous.

**gfastats and BUSCO both report N50, and on drafts they disagree badly.** Both report scaffold
count, N50 and total length. On the 696 drafts that had both (live, 2026-10-16, first pass):

| Quantity | Disagree |
|---|---:|
| scaffold N50 | **608** |
| contig N50 | **608** |
| scaffold count | 26 |
| total length | 28 |

**What the pipeline shows (checked 2026-10-16, owner decision 7):**

- **"Assembly summary" is BUSCO's own output.** `parse_busco()` reads `Scaffold N50`,
  `Contigs N50`, `Number of scaffolds` and so on from the BUSCO short-summary JSON
  (`BUSCO_KEYMAP`) and stores them as `scaffold_n50`, `contigs_n50`, …. The two programs are
  BUSCO (`modules/nf-core/busco`, container `busco:6.0.0`, conda `5.8.3`) and gfastats 1.3.6
  (`modules/local/gfastats`).
- **Both run on the same FASTA.** In `subworkflows/local/genome_qc/main.nf`, `BUSCO_BUSCO` and
  `GFASTATS` both take `assembly`, which `workflows/draftgenomes.nf` passes as the decontaminated
  assembly. So "different input" does not explain it, except on samples loaded from
  precomputed results, where BUSCO and gfastats may come from different runs.
- **The BUSCO value behaves like an L50 (a count of contigs), not an N50 (a length).** On the
  live comparison (681 drafts with both, both > 0):

  | Agreement | Rows | BUSCO > gfastats | Fits the L50 bounds |
  |---|---:|---:|---:|
  | equal | 87 | 0 | 49 |
  | within 5% | 67 | 66 | 65 |
  | further apart | **524** | **524** | **524** |

  "Fits the L50 bounds" means the value obeys two limits that any L50 must, given gfastats'
  N50, largest contig and total length: `L50 < total / (2 × N50) + 1` and
  `L50 ≥ total / (2 × largest)`. Every one of the 524 does. Example: OG2649 (260909) has 273,047
  contigs, 194 Mb, and a gfastats N50 of 711 bp. BUSCO's "N50" of 110,080, read as a count of
  contigs of about 880 bp, is 97 Mb, which is half the assembly.
- Lengths and counts agree on about 96% of rows. Only the N50s differ, which fits a label
  problem, not a data problem.
- **The 87 exact matches are real N50s.** So some BUSCO runs report the length and some report
  the count. Which BUSCO version wrote which row is not recorded, and the HPC was unreachable
  on 2026-10-16 to open one JSON from each group. R.0 does that: OG2649 (260909, count) against
  OG2033 (251215, equal).

**Recommendation:** gfastats is the authoritative N50, and it is the only N50 to report.
`draft_busco` keeps BUSCO's two N50 columns exactly as stored, so the split changes no value
(§7), with a column comment saying they are unreliable. A later migration, once R.0 has read the
JSONs, either drops them or renames them to `l50` where they prove to be counts. The parser fix
goes in the pipeline: `BUSCO_KEYMAP` should stop mapping BUSCO's N50 keys, or map the L50
keys explicitly. In `ref_genomes` the same comparison disagreed on 51 of 285
(`bioinformatics_data_review.md` §3), and the ref-genome pipeline should be checked for the same
cause. Until then, **nobody should report a draft N50 from `scaffold_n50` or `contigs_n50`.**

### 4.3 Dropped columns

Seventeen `draft_genomes` columns are not carried onto the new tables (owner decision 14):

| Columns | Rows filled | Why |
|---|---:|---|
| `aws_r1`, `aws_r2`, `aws_assm`, `fastp_r1`, `fastp_r2`, `sra_r1`, `sra_r2`, each with `_size` (14) | 697 / 642 / 164 | historical file paths, not kept up to date; last filled for `seq_date` 250520 |
| `host_haploid_size`, `partition_confidence` | 68 | one-off load for the 260909 batch; no upload script pushes them |
| `sra_date_submitted` | 0 | never populated |

- **Nothing reads them.** On live (2026-10-16), no view depends on any of the 16 file and host
  columns, and no code in the draft pipeline, `OceanOmics-Database`, the ref-genomes pipeline,
  the mitogenome pipeline or this repository names them. `ENA-draft-genomes` is not cloned
  here, so R.0.2 checks it before the merge.
- Their values stay in `pre_v3_archive.draft_genomes` until R.8, and in the `pg_dump` taken
  then. The first draft's `draft_file` table is not built.

**Not shown by the views (`056`, owner request 2026-10-19).** These columns are kept on the new
tables but left out of the views, so after the merge they are dropped columns for readers too:
- the six DepthSizer columns (`depmethod`, `adjust`, `readbp`, `mapadjust`, `scdepth`,
  `estgenomesize`) are out of `draft_genomes`. `v3.draft_depthsizer` keeps the 701 frozen rows;
- `avg_coverage` and `avg_base_coverage` are out of `mitogenome_submission_view`. They are
  still in `mitogenome_data`.

On 2026-10-19 the only code naming the DepthSizer columns was the decommissioned
`OceanOmics-Database/SS/` importer, and no code read `mitogenome_submission_view`.

### 4.4 Views

- **`draft_genomes`** is the compatibility view. It has today's 120 columns less the 17 dropped
  in §4.3, so 103, LEFT JOINed from the tables above. Since `056` it shows 98: it adds
  `nominal_species_id`, drops the six DepthSizer columns, and groups the rest by process.
  `v_genome_size_comparison` and every external reader keep working. As in §3.7, the old table
  moves to `pre_v3_archive` at the merge.
- **`v_draft_genome_status`** is the view the owner asked for: one row per draft genome, with
  one boolean per process and a rollup.

  ```sql
  SELECT d.og_num, d.og_id, d.seq_date,
         (f.draft_id  IS NOT NULL) AS has_fastp,
         (gs.draft_id IS NOT NULL) AS has_genomescope,
         (b.draft_id  IS NOT NULL) AS has_busco,
         …,
         num_nonnulls(f.draft_id, gs.draft_id, b.draft_id, …) AS processes_done,
         (b.draft_id IS NULL AND f.draft_id IS NOT NULL)        AS reads_only
  FROM draft_genome d
  LEFT JOIN draft_fastp f USING (draft_id) …
  ```

  The empty cells are still there to look at. They are just computed now, not stored. A
  per-process column also makes "which samples still need BUSCO" a one-line filter. Retired
  tools (DepthSizer) are not processes a draft can be missing.

## 5. Connectivity review: every table with no relation

This is the state after V.6 (75 objects). "In" and "out" mean declared foreign keys.

| Table | Rows | Relation today | Proposal | Evidence | Where |
|---|---:|---|---|---|---|
| `draft_genomes` | 1,720 | none | → `sample`; → Illumina `sequencing` via `draft_genome_run` | 0 orphans; 1,720/1,720 match an Illumina run | **R.3** in `v3` |
| `mitogenome_data` | 2,371 | → `sample` | + → `sequencing` via `mito_assembly_run`, as for draft | 1,977/1,985 `(og_id, seq_date)` match | **R.2** in `v3` |
| `ena_validation_attempts` | 1,188 | none | → `mito_annotation` | 1,183 match; the 5 orphans cleared in R.1 | **R.7** |
| `ena_submissions` | 539 | none | → `mito_annotation` | 539/539 match | **R.7** |
| `ena_specimen_accessions` | 2,848 | parent of `ena_related_assemblies` only | → `sample` | 2,848/2,848 match | **R.4** (`054`) |
| `raw_data` | 8,010 | none | → `sample`; `run_id` → `sequencing_run` | 8,010/8,010 `run_id` match; 30 blank `og_id` | **R.4** (→ `sample`), **R.7** (→ `sequencing_run`) |
| `hifi_reads_qc` | 277 | none | `run_id` → `sequencing_run`; later → `sequencing` by (tube, run) | 270/277 by `run_id`; (tube, run) 262/277 | **Phase RG** in `v4` (moved from R.7, owner decision 2026-10-19; `ref_genomes_runbook_rg0_rg5.md`) |
| `hic_reads_qc` | 552 | none | `run_id` → `sequencing_run`; library resolvable through the lysate | 530/552 by `run_id`; a Hi-C library on that run for 526/552 | **Phase RG** in `v4` (moved from R.7, as above) |
| `raw_qc` | 252 | none | → `sample` after 3 orphans fixed | | **Phase RG** in `v4` (split per read set; orphans excluded) |
| `rna_qc_kinnex` | 96 | none | PK + → `rna_library_kinx` | | Phase C.2 (unchanged) |
| `ref_genomes`, `ref_genomes_assembly_uploads` | 2,036 / 88 | none / parent of SRA uploads | → `sample`, and the same split as §4 | 4 orphans in `ref_genomes` | **Phase RG** in `v4` (owner decision 1's "next phase") |
| `species`, `species_ncbi_assembly`, `ncbi_genome_assemblies`; `sample.nominal_species_id` | | partial | Phase E | | Phase E (unchanged) |
| `og_workflow_recommendation`, `_assignment_log`, `_notification` | 0 | none: each has an `og_id text` column, but **no declared FK** (live, 2026-10-16) | → `sample(og_id)` | 0 rows, so satisfiable trivially | **R.4** (`054`; declared, owner decision 9) |
| `master_species`, `master_species_genome` | 19,817 | internal only | none | | colleague's work, untouched |
| `design_description` | 2 | none | removal candidate | | open question 15 of the review |
| `ena_locus_registry_archive`, `ena_candidate_loci_archive` | 0 | none | drop | empty since `010` | **R.8** |
| `schema_migrations`, `import_quarantine`, `value_conversions`, `workbook_attempt_keys` | | none | none: infrastructure, unconnected by design | | |

**Answering review open questions 4 and 5 from the data.** Those questions (which grain QC
records belong to, and what a `sequencing` row is) have blocked every QC relation since July.
Live data answers most of both:

- `raw_data`, `hifi_reads_qc` and `hic_reads_qc` all carry a `run_id` that matches
  `sequencing.run_id` on 97–100% of rows.
- HiFi QC is per library per run. The tube rebuilds as
  `og_id || tissue || '_' || ext_type || '_' || lib_code` on 273 of 277 rows, and that
  `(tube, run)` is in `sequencing` on 262.
- Hi-C QC is per library per run per lane. Its `lib_code` (`HICL`) does not rebuild the tube,
  whose live form is like `OG106G-1_HICL`. A Hi-C library of the same sample and tissue is on the
  same run for 526 of 552.

**`sequencing` is "a library on a run"**, but it cannot serve as the FK target yet.
`(library_tube_id, run_id)` is not unique on live, because of the §2.3 placeholders.

The relation that is clean today sits one level up. The database has no run entity, even
though 4,905 `sequencing` rows name only **214 distinct runs**, and `raw_data` and both QC
tables key on the run. So:

- **Add `sequencing_run` (`run_id` PK, plus `instrument`, `run_date`, `mach` and `initial`
  parsed from the ID).** Seed it from `sequencing`, and FK `sequencing.run_id` to it.
- **`raw_data`, `hifi_reads_qc` and `hic_reads_qc` FK `run_id` → `sequencing_run`.** This is
  satisfiable today except for 7 HiFi and 22 Hi-C rows, which R.0 triages.
- **Library-level links come after the §2.3 cleanup:** `hifi_reads_qc` → `sequencing` on
  `(library_tube_id, run_id)` (after adding a `library_tube_id` column), and `hic_reads_qc`
  likewise once its tube is recorded rather than inferred.

**After this phase**, the tables with no relation in or out fall from 20 to 9 (live count,
2026-10-16, with the three `og_workflow_*` FKs declared). Four of the 9 are infrastructure. The
other five are owned elsewhere or already scheduled: `raw_qc` and `rna_qc_kinnex` (Phase C),
`ref_genomes` (next phase), `ncbi_genome_assemblies` (Phase E) and `design_description` (open
question 15 of the review).

```text
BEFORE (analysis side)                  AFTER
sample                                  sample
  -> mitogenome_data                      -> mito_assembly ─> sequencing (via _run)
       -> lca*  (4-col FK)                     -> mito_assembly_depth
  draft_genomes      (none)                    -> mito_annotation
  raw_data           (none)                         -> mito_annotation_gene
  hifi_reads_qc      (none)                         -> lca, lca_raw_results, blast_filtered_lca, lca_validation
  hic_reads_qc       (none)                         -> ena_validation_attempts, ena_submissions
  ena_validation_*   (none)               -> draft_genome ─> sequencing (via _run)
  ena_submissions    (none)                    -> draft_<process> × 9
  ena_specimen_acc.  (none)               -> ena_specimen_accessions
  og_workflow_*      (none)               -> og_workflow_*
                                        sequencing
                                          -> raw_data, hifi_reads_qc, hic_reads_qc
```

## 6. Phased plan

Every step follows `sql/README.md` and `docs/database_change_checklist.md`:

- guarded and idempotent DDL;
- checks inside the migration, before `COMMIT`;
- an opt-in `PGOPTIONS` setting on anything destructive;
- a revert file in `sql/revert/`;
- a rehearsal on a fresh restore of live before live is touched;
- `bin/check_drift.py --update` and `scripts/export_schema_baseline.sh` after;
- reconciliation **by key and by value** with `EXCEPT ALL` both ways, never by count alone. V.4
  found two bugs that matching counts had hidden.

Migration numbers start at `050`; `049` (the Hi-C drafts) is already applied.

The step-by-step runbook for R.0–R.5 is
[`assembly_relations_runbook_r0_r5.md`](assembly_relations_runbook_r0_r5.md).

### 6.1 Build in `v3`, then merge into `public` (owner decision 11)

Every new object in this plan is created in a new schema, `v3`, on live. `public` is left as it
is, and nobody's work changes, until the new shape has been checked against the old one
alongside it. This is the `v2` pattern (V.4–V.6), with two lessons from it applied.

**What lives in `v3` during the test window:**

- every new table: `mito_assembly`, `mito_assembly_depth`, `mito_annotation`, `mito_gene`,
  `mito_annotation_gene`, `mito_assembly_run`, `draft_genome`,
  `draft_genome_run`, the nine `draft_*` process tables and `sequencing_run`;
- the new views: `v_mito_annotation_genes` and `v_draft_genome_status`;
- **compatibility views under the old names:** `v3.mitogenome_data`, `v3.draft_genomes` and
  `v3.mitogenome_submission_view`. A session with `search_path = v3, public` sees the new shape
  under today's names, and everything else falls through to `public`. That is how readers are
  tested (R.5) without touching anyone else's session.

**Rules for the window:**

- **FKs point from `v3` into `public`** (`sample`, `sequencing`), never the other way. Nothing
  in `public` depends on `v3`, so `DROP SCHEMA v3 CASCADE` is always a clean revert.
- **Production keeps writing `public`.** `scripts/sync_v3.sql` copies `public.mitogenome_data`
  and `public.draft_genomes` into `v3`. It upserts on the natural keys, so ids stay stable
  across runs, and deletes `v3` rows whose source row has gone. It runs before every check, and
  nightly after `import_v2.py` while the window is open.
- **Nothing writes `v3` on live except the sync.** Writer tests run against a rehearsal restore
  (R.5). If a test wrote `v3` on live, the sync would overwrite it or be confused by it.
- **New code never names `v3.`** The importer named `v2.` 38 times, and V.6 had to fix every
  one before `v2` could go (`phase_v6_plan.md`). Writers and readers use unqualified names and
  pick the schema up from `search_path`, so the same code works before and after the merge.
- The `readonly` role gets `USAGE` on `v3` and `SELECT` on its tables, so anyone can look.

**The merge (R.6) is one migration, not V.5's two steps.** V.5 put `v2` first on `search_path`,
then V.6 moved everything back into `public`. Here the objects move straight into `public`:

1. final sync, then checks;
2. move the old tables out: `ALTER TABLE public.mitogenome_data SET SCHEMA pre_v3_archive`, and
   the same for `draft_genomes`;
3. `ALTER … SET SCHEMA public` for every `v3` table, sequence and view;
4. **rebuild every view that read the old tables.** A view is bound to the table's OID, not
   its name, so `mitogenome_submission_view`, `v_genome_size_comparison` and the rest would
   otherwise follow the old tables into `pre_v3_archive` without a word. The migration
   lists them from `pg_depend` before the move and asserts afterwards that no `public` view
   depends on a `pre_v3_archive` table;
5. drop the four-column LCA FKs to the old `mitogenome_data` (re-parenting follows in R.7);
6. `DROP SCHEMA v3` (`RESTRICT`: it must already be empty).

### R.0 — Measure on live, list readers, take the remaining decisions

1. Re-run every figure in §2 and §5 against live. Queries:

   ```sql
   -- annotated vs not
   SELECT annotation IS NULL AS unannotated, count(*) FROM mitogenome_data GROUP BY 1;
   -- children whose (assembly, annotation) no longer exists (531 rows on 2026-10-16;
   -- plus 1 non-orphan _rgj ENA attempt: SELECT … FROM ena_validation_attempts WHERE code ~ '_rgj')
   SELECT 'lca_validation' t, count(*) FROM lca_validation c
    WHERE NOT EXISTS (SELECT 1 FROM mitogenome_data m
      WHERE (m.og_id,m.tech,m.seq_date,m.code,m.annotation)
          = (c.og_id,c.tech,c.seq_date,c.code,c.annotation))
   -- … repeat for lca, lca_raw_results, blast_filtered_lca, ena_validation_attempts, ena_submissions
   ;
   -- draft blocks: rows with any value per block (one line per block from §2.2)
   SELECT count(*) FILTER (WHERE num_nonnulls(complete,single_copy,multi_copy,fragmented,missing,n_markers,domain) > 0) AS busco,
          count(*) FILTER (WHERE num_nonnulls(gfa_num_contigs,gfa_contig_n50,gfa_num_scaffolds,gfa_scaffold_n50,gfa_largest_scaffold,gfa_total_scaffold_length,gfa_gc_content_percent) > 0) AS gfastats
          -- … one FILTER per block
   FROM draft_genomes;
   -- draft → Illumina runs (n = 0 is a draft that cannot be linked)
   SELECT n, count(*) FROM (
     SELECT d.og_id, d.seq_date, count(s.sequencing_id) n
     FROM draft_genomes d LEFT JOIN v_sequencing_browse s
       ON s.og_id = d.og_id AND s.seq_date = d.seq_date AND s.technology = 'Illumina'
     GROUP BY 1,2) x GROUP BY n ORDER BY n;
   -- BUSCO vs gfastats N50, with the L50 bounds test (§4.2)
   SELECT count(*) FILTER (WHERE gfa_scaffold_n50 > 0 AND scaffold_n50 IS NOT NULL) both,
          count(*) FILTER (WHERE gfa_scaffold_n50 <> scaffold_n50) disagree,
          count(*) FILTER (WHERE scaffold_n50 <> gfa_scaffold_n50
            AND scaffold_n50 < gfa_total_scaffold_length / (2.0 * gfa_scaffold_n50) + 1
            AND scaffold_n50 >= gfa_total_scaffold_length / (2.0 * gfa_largest_scaffold)) fits_l50
   FROM draft_genomes WHERE gfa_scaffold_n50 > 0;
   -- is sequencing unique on (library_tube_id, run_id)? (0 groups after the 2026-10-16 cleanup)
   SELECT library_tube_id, run_id, count(*) FROM sequencing GROUP BY 1,2 HAVING count(*) > 1;
   ```

2. **Writers: located** (§2.2). DepthSizer is retired, and the file and two host columns are
   dropped. Still to check: `ENA-draft-genomes` (steps 06–07 write the submission block), which
   is not cloned here. Confirm what it writes, and that it reads none of the 17 dropped columns
   (§4.3).
   `ENA-draft-genomes` steps 06–07 are not cloned here yet. R.6 cannot land until each live
   writer has a version that writes the new tables.
3. **List the readers that assume one row per assembly** (§3.7): grep the mitogenome pipeline,
   the views and `summary` for reads of `mitogenome_data` that do not carry `annotation`.
4. **Open one BUSCO short-summary JSON from each population** (§4.2): OG2649 260909 (count) and
   OG2033 251215 (equal). Record the BUSCO version and the exact keys.
5. Triage the 7 `hifi_reads_qc` and 22 `hic_reads_qc` rows whose `run_id` is not in
   `sequencing`.

Done since the first draft: the §2.3 placeholder cleanup (2026-10-16), the decisions in the
header, and the triage of the `_rgj` ENA attempts (all four go in R.1).

### R.1 — Clear the orphaned LCA and ENA rows in `public` (`050`)

The one step that changes `public` before the merge, because the orphans are wrong today
whatever shape comes next (§3.6).

1. Archive the 532 rows (§3.6): CSV in `archive/mito_orphans_260909/`, and a copy in
   `pre_v3_archive.<table>_orphans`.
2. Delete them, behind an opt-in `PGOPTIONS` setting, with the expected count per table
   asserted before `COMMIT`: `lca_validation` 1, `lca` 8, `lca_raw_results` 74,
   `blast_filtered_lca` 443, `ena_validation_attempts` 6, `ena_submissions` 0.
3. Post-check: the R.0 orphan query returns 0 for every child table, and no
   `ena_validation_attempts` row has an `_rgj` code. The 35 `_rgj` assemblies and their LCA rows
   are unchanged.

### R.2 — Mitogenome tables in `v3` (`051`)

1. `CREATE SCHEMA v3`. Create `mito_assembly`, `mito_assembly_depth`, `mito_annotation`,
   `mito_gene` (seeded), `mito_annotation_gene` and `mito_assembly_run`.
2. Backfill in one transaction: assemblies from every row; depth where `depth_method` is a
   measured method (today only `remap_full_v1`, 1,954 rows); annotations where
   `annotation IS NOT NULL` (none `is_selected`); genes by unpivoting.
3. Build `v3.mitogenome_data`, `v3.mitogenome_submission_view` and `v_mito_annotation_genes`.
   Verify inside the migration that `v3.mitogenome_data` equals
   `public.mitogenome_data` on every kept column, using `EXCEPT ALL` both ways.
4. Verify that every LCA and ENA row in `public` resolves to exactly one `v3.mito_annotation`,
   by the five natural columns. After R.1 the count of unresolved rows must be 0. This proves
   R.7's backfill before any `public` table is altered.
5. Add `scripts/sync_v3.sql` (mitogenome half) and schedule it.

### R.3 — Draft genome tables in `v3` (`052`)

1. Create `draft_genome`, `draft_genome_run` and the nine process tables, and
   backfill them. `draft_genome_run` follows §4.1: Illumina only, and the instrument must match
   `mach`.
2. Build `v3.draft_genomes` and verify it equals `public.draft_genomes` on the 103 kept columns,
   `EXCEPT ALL` both ways. Then build `v_draft_genome_status`.
3. Add the draft half of `scripts/sync_v3.sql`. It skips `draft_depthsizer` (frozen).

### R.4 — Run entity in `v3`, and FKs between existing tables (`053`, `054`)

1. **`053`:** create `v3.sequencing_run`, seeded from the 214 distinct `sequencing.run_id`
   values (§5). Check in `v3` that `sequencing`, `raw_data` and the two QC tables would satisfy
   an FK to it. The FKs themselves wait for the merge, because a `public` table must not point
   into `v3`.
2. **`054`:** FKs between tables that already exist in `public` and need nothing new. They can
   land any time, and do not wait for the merge:
   - `ena_specimen_accessions → sample` (2,848 of 2,848 match);
   - the three `og_workflow_* → sample` (0 rows; owner decision 9). Each `og_id` gets
     `REFERENCES sample(og_id)`, matching the other `sample` FKs, plus an index;
   - `raw_data → sample`, once its 30 blank `og_id` are fixed or quarantined.

   Each is added `NOT VALID`, then `VALIDATE`d, and the child column is indexed.

### R.5 — Writers and readers, tested against `v3`

1. **`Oceanomics-OceanGenomes-Mitogenomes`:**
   - `push_mtdna_assm_results.py` upserts `mito_assembly` on its natural key
     (`RETURNING assembly_id`), and writes depth to `mito_assembly_depth`. The existing guard
     logic (`decide_write`, the depth-only path) carries over unchanged in meaning.
   - `push_emma_annotation_results.py` upserts `mito_annotation` on
     `(assembly_id, annotation)` and replaces that annotation's gene rows, in one transaction.
     **It never touches `is_selected`. A re-annotation now adds a row and no longer overwrites
     one.**
   - Unit tests: `tests/unit/test_push_mtdna_assm_decide_write.py` and
     `test_push_emma_column_parity.py` are updated. The parity test becomes "every annotation
     output column lands in exactly one table".
2. **`OceanOmics-OceanGenomes-Draft-Genomes`:** in `bin/draft_genome_stats.py`,
   `upsert_record()` upserts `draft_genome` (`RETURNING draft_id`), then upserts the family's
   own table on `draft_id`. `FAMILY_COLUMNS` becomes a map from family to table, splitting the
   `busco`, `decontamination` and `assembly` families as §4.2 does.
   `fetch_database_record()` reads the `draft_genomes` view, so the backfill verifier keeps
   working. Add the fix to `BUSCO_KEYMAP` here (§4.2). The six `push_*` CLIs need no change.
   **A new tool is a new table and a migration, and no existing writer can break.**
3. **Test writers on a rehearsal restore of live** with `PGOPTIONS='-c search_path=v3,public'`:
   - run each push step on real outputs;
   - annotate one assembly twice;
   - compare the `v3` compatibility views with what the old writer produces on the same inputs.
4. **Test readers on live, read-only,** with the same `search_path`: the §2.1 pipeline readers,
   `prepare_ena_metadata.py`, `v_genome_size_comparison` and the samplesheet builders. They
   should need no edit, except those found in R.0.3.

### R.6 — Merge `v3` into `public` (`057`)

**Carried from R.0–R.5 into the R.6 runbook:**
- Gate: `ENA-draft-genomes` is still unseen (R.0.2). Confirm what it writes and that it reads
  none of the 17 dropped columns, nor the eight that `056` left out of the views (§4.3).
- Confirm that no reader, OceanGenom_Web included, selects these views by column position.
  `056` changed the column order.
- Drop the window-only functions (`v3.sync_mito`, `sync_draft`, `sync_sequencing_run`,
  `check_mito`, `check_draft`) and the 18:30 UTC `sync_v3.sh` cron line.
- Re-point `v3.rebuild_mito_gene_views()`'s `search_path` setting to `public, pg_temp`. Its
  body uses unqualified names.
- Rebuild the two views that depend on the old tables: `mitogenome_submission_view` and
  `v_genome_size_comparison` (R.0.3 found no others).
- Drop the three four-column FKs from `lca`, `lca_raw_results` and `lca_validation` to the old
  `mitogenome_data` (`blast_filtered_lca` has none).
- Deploy the `phase-r-v3` branches the same day.

Behind an opt-in, as §6.1 describes: final sync, move the two old tables to `pre_v3_archive`,
move every `v3` object into `public`, rebuild the dependent views, drop the old LCA FKs, and drop
`v3`. **The new writers deploy the same day**, so there is no window for an old writer to fail
into. Post-check: the next pipeline runs write the new tables, an old writer fails loudly on
"cannot insert into view", and no `public` view depends on a `pre_v3_archive` table.

### R.7 — Re-parent the LCA and ENA children; FKs to `sequencing_run` (`058`, `059`)

1. **`058`:** add `annotation_id`, backfill it (proved in R.2.4), then `SET NOT NULL` on the
   four LCA tables and both ENA tables. Add each FK `NOT VALID`, then `VALIDATE`.
   - **Agree the ENA columns with the owner of the downstream submitter first.**
     `ena_submissions` is their ledger (`015`).
   - Add a consistency trigger, so a row's natural columns must agree with its `annotation_id`
     until the writers stop sending them.
   - Update `push_lca_*`, `push_species_validation.py` and `push_ena_validation_results.py` to
     send `annotation_id`.
   - **`ena_submissions` and `ena_validation_attempts` connect to `mito_annotation`, not to
     `sample`** (owner decision 2026-10-20). No `og_id` → `sample` FK is added to either, even
     as a stopgap. On 2026-10-20 all 1,898 rows (539 + 1,359) resolved to exactly one
     annotation by `(og_id, tech, seq_date, code, annotation)`, none to two. Writers to change:
     `ENA-mito-genomes/workflow/06_push_submission_data_to_db.py` (and `07_resolve_gca_accessions.py`
     if it writes these tables) and `Oceanomics-OceanGenomes-Mitogenomes/bin/push_ena_validation_results.py`.
2. **`059`:** FK `sequencing.run_id`, `raw_data.run_id` and `rna_qc_kinnex.run_id` to
   `sequencing_run` (2026-10-20: 4,448, 8,010 and 96 rows, 0 unmatched in each; `rna_qc_kinnex`
   got its primary key and its FKs to `rna_library_kinx` in `061`). (Number taken
   at landing; Phase RG may claim `057`–`059` first.) `hifi_reads_qc` and `hic_reads_qc`
   moved to Phase RG on 2026-10-19: their `run_id` FK and library-level links are built in
   `v4` and land with RG.6 (`ref_genomes_runbook_rg0_rg5.md`).
3. Later, once a release has run clean: drop the natural columns from the LCA tables, re-key
   their PKs, and rebuild `lca_pivot_view`, `lca_results_view`, `lca_validation_report_view`
   (keeping its `INSTEAD OF UPDATE` path, see `033`), `filtered_lca_view`, `summary`,
   `sample_view` and `embargo_assignment_view` to join through `mito_annotation`. **This is the
   biggest view rebuild since V.5. Rehearse it as V.5 was rehearsed.**

### R.8 — Close-out

- After a quiet period, drop `pre_v3_archive` (the old `mitogenome_data` and `draft_genomes`,
  and the orphan copies) and the two empty `ena_*_archive` tables. A `pg_dump` taken the morning
  of the drop is the permanent copy.
- Object and column comments on every new table, naming the writing tool and the process.
  `draft_busco.scaffold_n50` and `contigs_n50` say they are not reliable N50s (§4.2).
- Add the new tables to `docs/data_dictionary.md`.
- Update `database_review.md` §7, §9 and §13, and re-run `bin/check_drift.py --coverage`.
  `draft_genomes` leaves the Phase C.0 catch-up list, because R.3 creates its replacement.

## 7. Risks

- **One writer not yet seen.** `ENA-draft-genomes` (the submission block) is not cloned here
  (R.0.2). If it, or any unknown writer, still writes `draft_genomes` after the merge, it fails
  on the view. That is loud, not silent. **The compatibility view is not a write path.**
- **A dropped column turns out to be read.** If something outside these repositories selects
  one of the 17 columns in §4.3, it fails after the merge with "column does not exist". The
  values are still in `pre_v3_archive.draft_genomes` until R.8, so the fix is to point that
  reader at the archive or retire it.
- **The ENA tables are owned downstream.** `annotation_id` on `ena_submissions` needs their
  agreement. If it is declined, R.7 still covers the four LCA tables, and the ENA tables keep
  their natural keys, joined through a view.
- **`ON CONFLICT` cannot target a view.** That is why writers change before the merge and not
  after. Moving the old table out makes a missed writer fail loudly, not silently.
- **Views follow OIDs.** Moving a table with `SET SCHEMA` carries every dependent view with it.
  R.6 rebuilds them and asserts that none is left pointing into `pre_v3_archive` (§6.1).
- **Several annotations per assembly.** Once the new writer runs, `mitogenome_data` can return
  more than one row per assembly (§3.7). Readers that assume one must be fixed in R.5, before
  the merge, without leaning on `is_selected`.
- **Pivot cost.** The `mitogenome_data` view pivots about 72,000 gene rows. That is fine for
  pipeline readers. Measure `summary` before and after R.7, because it reads `lca_validation`
  per sample and was 2.0 s at last measure.
- **Two shapes during the test window.** Between R.2 and R.6, the pipeline writes `public` and a
  sync copies it into `v3`. Run the sync before every check, and keep the window to weeks, not
  months. A `v3` that drifts from the code becomes a second database nobody trusts.
- **Do not combine the split with value changes.** The type and vocabulary tightening in §3.3,
  and any rename of BUSCO's N50 columns, go in a later migration, so a reconcile failure has one
  cause.

## 8. Open questions

1. ~~Which annotation is current?~~ **None. All are shown; `is_selected` is an optional flag
   nothing reads (owner decision 3).**
2. ~~Genes long or wide?~~ **Long, with `v_mito_annotation_genes` (owner decision 4).**
3. ~~Is `qc/99_genbank_submitter.py` retired?~~ **Yes. The GenBank columns are empty and are
   dropped (owner decision 5).**
4. ~~The `_rgj` assemblies and ENA attempts~~ **Assemblies stay; all four `_rgj` ENA attempts are
   removed in R.1 (owner decision 6).**
5. ~~Where is the draft-genome push code?~~ **`OceanOmics-OceanGenomes-Draft-Genomes`,
   `bin/draft_genome_stats.py` (§2.2). The columns it does not write are retired or dropped
   (owner decisions 12 and 14).**
6. **BUSCO's N50 columns (§4.2).** The pipeline shows two programs, BUSCO and gfastats, on the
   same FASTA. BUSCO's stored "N50" behaves as an L50 on every one of 524 far-apart rows, and is
   a real N50 on 87. Recommendation: gfastats is authoritative. Confirm by reading the BUSCO
   JSONs (R.0.4), then fix `BUSCO_KEYMAP` and decide whether to drop or rename the stored
   columns. Check `ref_genomes` for the same cause.
7. ~~Split `mito_assembly.stats`?~~ **No (owner decision 8).**
8. ~~FK from `og_workflow_*` to `sample`?~~ **Declared in R.4, `054` (owner decision 9).**
9. ~~Should `import_v2.py` derive `seq_type` again?~~ **Yes (owner decision 13, §2.3).**
10. ~~OG2951 and OG3000: what wiped their annotation?~~ **A misnamed or replaced annotation;
    the orphaned rows are cleared (owner decision 10, R.1).** Re-annotating them is pipeline
    work.
11. ~~The 15 Hi-C drafts~~ **Deleted 2026-10-16, `049`.**

## 9. Success criteria

| Criterion | Measure |
|---|---|
| No assembly stores empty annotation columns | `mito_assembly` has no annotation columns; 0 rows in `mito_annotation` without an annotation |
| A re-annotation adds, never overwrites | Annotate one assembly twice in the rehearsal: two `mito_annotation` rows, both visible in `mitogenome_data`, neither selected |
| The selection flag affects nothing | No view, FK, trigger or pipeline query other than `v_mito_annotation_genes` references `is_selected` (`pg_depend` and a grep of both pipelines) |
| Every LCA and ENA row points at a real annotation | 0 orphans and 0 `_rgj` ENA attempts after R.1; validated FKs on `annotation_id` after R.7 |
| A missing process is a missing row | 0 all-NULL rows in any `draft_*` process table |
| DepthSizer is closed | `draft_depthsizer` row count unchanged after the merge; no writer or sync touches it |
| The gaps are visible | `v_draft_genome_status` returns one row per draft genome with per-process flags |
| Readers did not break | `v3` compatibility views equal the `public` tables on every kept column, `EXCEPT ALL` both ways, before the merge |
| `public` untouched until the merge | Between R.2 and R.6, no `public` object depends on `v3`; `DROP SCHEMA v3 CASCADE` reverts cleanly on a rehearsal |
| Nothing left behind by the merge | No `public` view depends on a `pre_v3_archive` table; schema `v3` gone; no code names `v3.` |
| Fewer unconnected tables | 20 → 9, the 9 all accounted for in §5 |
| Nothing arrived by direct DDL | `bin/check_drift.py` clean; every new object created by a numbered migration |
