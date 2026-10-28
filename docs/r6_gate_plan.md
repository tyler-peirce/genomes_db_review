# R.6 gate batch: draft depth and host columns, ENA-draft-genomes, mito QC columns

## Context

`database_review.md` Finding 17 (2026-10-28) found two draft gaps that block R.6:
- **Host columns.** `host_haploid_size` and `partition_confidence` have a live writer but no `v3` column.
- **`ENA-draft-genomes`.** Steps 06 and 07 update `draft_genomes`, which becomes a view at R.6. Step 00 reads the hidden `scdepth`.

It also found that the draft ENA `COVERAGE` falls back to `total_bases / genomesize`. The measured read depth (`busco_mean_depth`) is computed but never uploaded. And the mito pipeline discards `completeness_profile` and its assembly QC verdict.

This batch fixes all of it in two parts: **A, draft (the R.6 gate)** and **B, mito**.

Owner decisions (2026-10-28):
- Do both parts.
- Re-run depth for the 613 assembled drafts that have none. Use a **depth-only mode now**; a full GENOME_QC re-run is a later, separate batch.
- The coverage summaries for the backfill are at `pawsey0964:oceanomics-draftgenomes/genomes.v2/<OG>/coverage/`.
- The new column is named `busco_read_depth`.

## Ground rules (from memory and the checklist)

- **Live reads are read-only.**
- **Every migration is rehearsed on a restore of live** (apply, revert schema-identical, replay a no-op) before it is applied with `bin/apply_migrations.py`.
- **A pre-change dump is taken before each apply.**
- **Pawsey is read-only for me.** The owner runs every pipeline job; I give the exact commands.
- **Drift:** the colleague's `og_priority_log` / `og_workflow_recommendation` drift stays out of the baseline. Refresh only the baseline files each migration changes.
- **No writer branch runs against live before R.6.** Changes that also land on a production branch (`master` / `inverts-dev`) write `public` only.
- **Fetch every clone first and record the SHAs read** (checklist, "For Pipeline Writer and Reader Audits").

## Design: new columns go into both `public` and `v3`

Until R.6, the production writers write `public` and `sync_v3` (18:30 UTC) copies `public` into `v3`. `check_draft()` / `check_mito()` compare the two by named columns.

So each new column is:
- added to the `public` table by migration (no DDL outside `sql/`),
- added to the `v3` table it belongs to,
- carried by `sync_*`, compared by `check_*`, and shown in the compatibility view.

This keeps the "v3 equals public" invariant, and lets the production writers start storing the values now. At R.6 the `public` columns are archived with their tables.

---

## Part A: draft genomes

### A.0 Measure (read-only)
1. **Fetch and record SHAs** for these clones:
   - Draft (`origin/master`, `phase-r-v3`)
   - `ENA-draft-genomes` (`origin/main`)
   - Mito (`origin/inverts-dev`, `phase-r-v3`)
   - `OceanOmics-Database`
2. **Re-measure on live:**
   - fill counts for `host_*`, `lambda_depth` and `scdepth`;
   - the 613 assembled drafts with neither, by `seq_date`: 37 / 2 / 31 / 117 / 115 / 113 / 71 / 46 / 55 / 2 / 12 / 12;
   - the 12 from 260909, which are `too_few_busco_regions` and stay unmeasurable.
3. **Confirm the Acacia layout for each affected batch** (`rclone lsf`, read-only). Per OG, look for:
   - `coverage/*_coverage_summary.json` and `*_kmer_depth.json`
   - `assemblies/genome/bwa/*.sorted.bam`
   - `busco/*full_table.tsv`
   - `kmers/*genomescope/*model.txt`
   - `fastp` json
   - the `.fna`

   Record which batches lack any of these.

### A.1 Migration `067_draft_depth_and_host_columns.sql`
Patterned on `052`, `055` and `056`; replaces functions from `055` / `056`.
- **`public.draft_genomes`:** `ADD COLUMN busco_read_depth numeric(10,4)`, `genomescope_fit text`, `busco_regions integer`, `partition_note text`. `host_haploid_size` and `partition_confidence` already exist; they were added by hand before 2026-10-13.
- **`v3.draft_genomescope`:** add all six, with these checks:
  - `partition_confidence IN ('high','low')`
  - `genomescope_fit IN ('original','reseeded')`

  Also drop and recreate `draft_genomescope_has_value` to include the six.
- **`v3.sync_draft()`:** replace it from `055`'s body, adding the six to the genomescope delete, insert, update and `IS DISTINCT FROM` lists.
- **`v3.draft_genomes` view:**
  - DROP and CREATE, as `056` does.
  - The six go in the GenomeScope / host block after `host_assembly_fraction`.
  - Restore the comment and the grants to `readonly` and `oceangenom_web`.
  - Re-check `v_draft_genome_status` and `v_genome_size_comparison` dependencies; there's no CASCADE, so a dependency fails loudly.
- **`v3.check_draft()`:** replace it, adding the six to both `EXCEPT ALL` arms.
- **Backfill inside the migration:** `SELECT * FROM v3.sync_draft()`, then a verify block: every check is 0, and `v3` host counts equal `public` (261).
- **Column comments** on every new column: source file, and that `busco_read_depth` is per-base read depth over Complete BUSCOs (successor to `scdepth`), not `lambda_depth`.
- **Revert file** in `sql/revert/`.
- **Baseline:** refresh `schema/current_views.sql` and `current_schema.sql` only (memory: og drift left out).

### A.2 Draft pipeline uploader
Files: `bin/draft_genome_stats.py`, `bin/backfill_draft_genome_stats.py`, `tests/`.
- **`parse_coverage_summary()`:** add `busco_read_depth` (from `busco_mean_depth`), `genomescope_fit`, `busco_regions` and `partition_note`.
  - **Also read `*_kmer_depth.json` when present.** It is the original source of the depth and partition fields, and the depth-only mode (A.4) produces it without a new coverage summary.
  - Add a `parse_kmer_depth()` and a `kmer_depth` entry in the backfill `COMPONENTS`, globbing `coverage/*_kmer_depth.json`, optional.
- **`FAMILY_COLUMNS["assembly"]`:** add the four new columns. Extend `OPTIONAL_COLUMNS` in the backfill script.
- **Land on `origin/master` first,** where it writes `public`, deployable once `067` is live. Then **merge `origin/master` into `phase-r-v3`**: 8 commits behind today, with known conflicts in `draft_genome_stats.py`. Confirm the v3 mapping (`"assembly": draft_genomescope`) covers all six.
- **Tests:** the existing suite, plus new parser tests using an OG3078 fixture copied from Acacia (`coverage_summary.json`, `kmer_depth.json`).

### A.3 Backfill the 261 drafts (260909, 260925) from Acacia
- **Stage:** `rclone copy` each OG's `coverage/` into the scratchpad. These files are untrusted, so stage them into a fresh directory and run with `python -I`.
- **Dry run:** `backfill_draft_genome_stats.py --archive-root <stage> --manifest <261 OGs> --db-config … --report-dir …` without `--apply`. Review the report: only the four new columns should change; existing values must verify identical.
- **Apply:** with `--apply`, after a pre-change dump. The nightly `sync_v3` carries the values to `v3`; run `v3.sync_draft()` by hand to confirm.

### A.4 Depth-only mode and the re-run of the 613 drafts
- **New pipeline entry** (draft `origin/master`; a `--depth_only` flag or a small workflow).
  - **Input:** a samplesheet of OG plus staged archive paths: `.fna`, `sorted.bam`, BUSCO `full_table`, GenomeScope `model.txt`, fastp json, seqkit stats.
  - **What it runs:** `MEASURE_KMER_COVERAGE` and `SUMMARISE_KMER_COVERAGE` only. If seqkit stats are missing, `SEQKIT_STATS` on the `.fna` (cheap). **No** re-mapping, BUSCO, reseed or `RECHECK_GENOME_SIZE`, so genome size and QC values don't change.
  - **Output:** publishes `coverage/*_kmer_depth.json` beside the archived files and uploads through the A.2 parser, which writes only the depth and partition columns.
- **First check on 2 OGs** (owner runs on Pawsey): one from 251210 and one from 250606. The BAM's contigs must match the BUSCO `full_table`; `MEASURE_KMER_COVERAGE` drops regions naming unknown contigs and reports `too_few_busco_regions` if most are dropped.
  - If the archived BAM was mapped to a different assembly version, fall back to `BWAMEM2_MEM` on the archived fastp reads (S3) in this mode.
- **Run:** I write a launcher in the style of `scripts/rerun_NOVA_260909_LA/_run_tier.sh` and per-batch samplesheets. The owner runs it, batch by batch.
- **Record:** drafts that come out `too_few_busco_regions`. They have no measured depth and their ENA `COVERAGE` is held. This includes the 12 from 260909.
- **Full GENOME_QC re-run** for the older drafts is noted as a later batch, not done here.

### A.5 `ENA-draft-genomes`
**On `main`** (production, writes `public`; deploy once `067` is live):
- **Step 00:** select `dg.busco_read_depth` alongside `dg.scdepth`.
- **Step 03** (`03_make_assembly_manifests.py`, the `COVERAGE` choice): use `busco_read_depth`, then `scdepth`. **Stop with a clear error** if neither exists; never send `total_bases / genomesize`.

**On a new `phase-r-v3` branch** (cut from fetched `origin/main`; does not run before R.6):
- **Steps 06 and 07:** upsert `v3.draft_submission`, using `draft_id` from `v3.draft_genome` by `(og_id, seq_date)`. Keep the blank-only update semantics of today's `UPDATE`, and step 07's `rowcount == 1` guard. Step 06's `UPDATE sample` is unchanged.
- **Step 00:** take `scdepth` from `v3.draft_depthsizer`.
- **Rehearsal** on a restore of live with the merge simulated, as in RG.5: old and new steps 06 and 07 produce identical `draft_submission` rows for a sample batch.

### A.6 Records
- **Plan:** copy this plan to `docs/r6_gate_plan.md`. Write per-step records, `docs/r6_gate_g*_record.md`, in the RG record style.
- **Review doc:** update Finding 17 status and add revision rows.
- **Assembly relations plan:** tick the R.6 gate items as they close.

---

## Part B: mitogenomes

### B.0 Measure (read-only)
- **Merge check:** `phase-r-v3` against `origin/inverts-dev` (10 behind, none touching uploads). Run the test suite after the merge.
- **What's archived on Acacia** (`pawsey0964:oceanomics-mitochondrial-genomes/<OG>/<assembly>/`): `annotation/*.annotation_stats.csv` holds `completeness_profile`. The run-level `mitogenome_assembly_summary_mqc.tsv` is not archived per assembly; only the per-assembly MultiQC HTML is.
- **Can the verdict be rebuilt?** Test whether `mitogenome_assembly_summary.py` reproduces it from one archived assembly directory (OG3078 reseed).

### B.1 Migration `068_mito_completeness_and_assembly_qc.sql`
- **`completeness_profile text CHECK IN ('vertebrate','core')`:** add it to `public.mitogenome_data` and `v3.mito_annotation`.
- **New `v3.mito_assembly_qc`** (`assembly_id` PK, FK `mito_assembly`), one row per assembly, like `mito_assembly_depth`. Its columns are also added to `public.mitogenome_data`:
  - `qc_status` (complete / manual_review / failed / superseded)
  - `manual_review_reason`
  - `numt_flag`, `frameshift_flag`
  - `reference_species`, `reference_accession`
  - `qc_updated_at`

  It's named `qc_status` to avoid the dropped legacy `status` column.
- **`v3.sync_mito()`, `v3.check_mito()` and the `v3.mitogenome_data` view:** replace and recreate them (latest bodies in `055` / `056`), the same way as A.1. Restore grants and comments. Revert file and baseline refresh as in A.1.

### B.2 Mito pipeline writers
Land on `origin/inverts-dev` (writes `public`), then merge into `phase-r-v3` (writes `v3`).
- **`bin/push_emma_annotation_results.py`:** add `completeness_profile` to `annotation_columns`, the INSERT and the DO UPDATE lists. `tests/unit/test_push_emma_column_parity.py` enforces the parity. Bump `ANNOTATION_STATS_VERSION`.
- **New `bin/push_assembly_qc.py`** and an `upload_results/assembly_qc` module:
  - reads `mitogenome_assembly_summary_mqc.tsv` after `MITOGENOME_ASSEMBLY_SUMMARY`;
  - upserts the verdict per `assembly_prefix`, skipping `superseded` rows' identity issues;
  - reuses `pg_row_guard.py` and the config loading in the existing push scripts.
- **On `phase-r-v3`:** the same values go to `v3.mito_annotation.completeness_profile` and `v3.mito_assembly_qc`.

### B.3 Mito backfill
- **`completeness_profile`:** from each archived `annotation_stats.csv` (staged with rclone, then a dry run and apply). Fallback: recompute with `annotation_stats.completeness_profile(genetic_code, class_name)` from stored taxonomy.
- **The verdict:** if B.0 shows `mitogenome_assembly_summary.py` reproduces it from archived directories, run it over the archive and push with `push_assembly_qc.py`. Otherwise it's forward-only, and the review records that older assemblies have no verdict.

---

## R.6 gate when this batch is done
- **`067` and `068` are applied,** and `check_draft` / `check_mito` are 0 nightly.
- **Draft `phase-r-v3` and mito `phase-r-v3` are up to date with their remotes,** and their tests pass.
- **`ENA-draft-genomes` `phase-r-v3` is rehearsed.**
- **The 261-row backfill is applied, and the 613 re-run is done** (or the remainder is listed and held).

## Verification
- **Each migration**, on a restore of live:
  - apply, then every `check_*` is 0;
  - revert is schema-identical (`pg_dump -s` diff);
  - replay is a no-op;
  - row counts are unchanged in every `v3` view.
- **On live after apply:**
  - `bin/apply_migrations.py --verify` passes and the ledger has 68 / 69 files;
  - `check_drift.py` shows only the known og drift;
  - the next 18:30 `sync_v3` reports ok.
- **Draft parser:**
  - the unit tests pass;
  - parsing the OG3078 fixtures gives `busco_read_depth` ≈ `lambda_depth × 2 × L / (L−k+1)`;
  - the backfill dry run reports only the new columns changing.
- **Depth-only mode:** on the 2 test OGs, the `kmer_depth.json` agrees with a hand `samtools bedcov` over the BUSCO BED, and the uploaded genome size is unchanged.
- **`ENA-draft-genomes`:**
  - **step 03:** a manifest for a 260909 sample shows `COVERAGE` from `busco_read_depth`; a draft with neither value stops;
  - **steps 06 and 07 on the branch:** identical `draft_submission` rows in the rehearsal.
- **Mito:** the column parity test passes, `push_assembly_qc.py` dry runs on a staged run, and `check_mito` is 0 after the backfill.
