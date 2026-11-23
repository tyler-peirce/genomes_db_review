# Draft genomes: Acacia backfill and re-run list (2026-11-09)

Plan: session plan `it-looks-like-the-purring-unicorn.md`. Follows the R.6 gate work in
[`r6_gate_a3_a5_record.md`](r6_gate_a3_a5_record.md), which closed depth and genome size for 250606 onwards.

## Method

- **Listings** (read-only, from this host, which has the same `pawsey0964:` and `s3:` remotes as Setonix):
  - `rclone lsf -R --files-only pawsey0964:oceanomics-draftgenomes/genomes.v2/`: 287,469 files under 1,591 OG folders
  - `s3:ocom.oceangenomes/analysed-data/draft-genomes/`: 7,797 files
  - `s3:ocom.oceangenomes/illumina-raw/<run>/` for the runs of every draft that has no assembly
- **[`scripts/draft_acacia_inventory.py`](../scripts/draft_acacia_inventory.py):**
  - `summarise` reduces the listings to one row per `(og_id, seq_date)` with a file count per result family.
  - `classify` joins that with live `v_draft_genome_status` and `draft_genomes`, read-only. It writes one row per draft and missing family to [`records/draft_gaps_261109.tsv`](records/draft_gaps_261109.tsv).
- **Matching rules:**
  - Files match a draft by `<OG>.ilmn.[NOVA_]<seq_date>` in the name. The BAM and DepthSizer's `scdepth` carry no date; they count only for OGs with one draft.
  - Raw reads match by `<run_id>/<library_tube_id>_`. Older runs (NOVA_230607_LP) name them by `field_id` instead, so that is tried too. `field_id` may contain spaces (`GT 20217`).

**States:**

| State | Meaning |
|---|---|
| backfill | The result file is on Acacia; the database has no row |
| rerun | Not produced, but its inputs are archived (assembly, BAM, BUSCO table, GenomeScope model, fastp) |
| rerun_missing_input | An input is missing; for the verdict, that is the `kmer_depth.json` a depth re-run makes |
| reassemble | No assembly anywhere; raw reads on S3 |
| superseded_scdepth | No `busco_read_depth`, but DepthSizer `scdepth` exists (≤250520) |
| lost | Nothing anywhere (**none found**) |

## What is missing (1,720 drafts on live)

| Family | Backfill | Re-run | Re-run, input missing | Re-assemble | Only `scdepth` |
|---|---:|---:|---:|---:|---:|
| GenomeScope | 0 | 0 | 0 | 116 | |
| Tiara | 0 | 0 | 0 | 117 | |
| FCS-GX / <500 bp | 1 * | 0 | 0 | 116 | |
| BUSCO | **20** | 0 | 0 | 117 | |
| Merqury | **21** | 1 | 0 | 118 | |
| gfastats | **1** | 727 | 0 | 118 | |
| Depth (`busco_read_depth`) | 13 † | 25 | 11 | 121 | 701 |
| Genome-size verdict | 7 † | 1 | 730 ‡ | 121 | |

\* OG1254 250606: see "Not backfilled".  
† The file exists but holds no value (see below), so these are re-runs.  
‡ They need the depth first: the verdict reads `kmer_depth.json`.

The per-batch breakdown is in the gap TSV: `awk -F'\t' '{print $3,$4,$2}' records/draft_gaps_261109.tsv | sort | uniq -c`.

## Backfill: 22 drafts

**Why these never loaded:**
- **250514:** the 20 drafts with no BUSCO have BUSCO and Merqury results archived in the old `busco_acti/` layout. The same 20 also have no `draft_merqury` row.
- **OG1093 and OG1263 (250606):** single families missing.
- The upload logs are gone, so the original cause is not recorded.

**Draft pipeline branch `backfill-missing-families`**, from `origin/master` `58353cf`. In `bin/backfill_draft_genome_stats.py`:
- **`--families busco,merqury,…`:**
  - Only those families' files are required, so a draft whose archive has no gfastats can still be filled.
  - A family the database already holds is verified against the archive and never rewritten; a difference rolls back the whole draft.
  - A fill never creates a draft.
  - Without `--apply`, `plan.tsv` reports WRITE / PRESENT_IDENTICAL / PRESENT_DIFFERS / NO_DRAFT_ROW from a read-only session.
- **BUSCO glob** `assemblies/genome/busco*/*short_summary.json`. Runs before 250606 publish to `busco_<tag>/`.
- **Tests:** 6 new (`FamilyFillTests`); 192 pass.

**Where it ran:** on Setonix, from `/scratch/pawsey0964/tpeirce/draft_backfill/`, at the owner's request. Nothing is staged on this host.
- **Code:** the production clone's `bin/` and `tests/` were exported (`git archive`, at `d4bcb35`; `draft_genome_stats.py` is identical to `58353cf`). The branch's `backfill_draft_genome_stats.py` was put over them, md5 checked.
- **Staged:** the BUSCO, Merqury and gfastats files of the 22 drafts, copied from Acacia to `stage/archive/` (80 files, 496 KB).
- **Run in** the upload container, `tylerpeirce-psycopg2-0.1.img`. Its 37 existing backfill tests pass against the new script.

**Dry run:**

| Manifest | Families | Drafts | Plan |
|---|---|---:|---|
| 250514 | busco, merqury | 20 | 40 WRITE |
| OG1093 250606 | merqury | 1 | 1 WRITE |
| OG1263 250606 | gfastats | 1 | 1 WRITE |

- No family the database holds would be touched.
- Parsed BUSCO complete runs 26.9–87.9% (actinopterygii, 3,640 markers; vertebrata, 3,354), and Merqury QV 51.3–61.1.

**Snapshot before writing:** [`records/draft_backfill_before_261109.csv`](records/draft_backfill_before_261109.csv), 22 rows of `draft_genomes`.

**Applied 2026-11-09** with `--apply`, after the dry run was repeated on Setonix with the same plan. Reports are in `apply_250514/`, `apply_merq/` and `apply_gfa/` on scratch.

| Manifest | Committed | Verified |
|---|---:|---|
| 250514 (busco, merqury) | 20 / 20 | 40 PASS |
| OG1093 (merqury) | 1 / 1 | PASS |
| OG1263 (gfastats) | 1 / 1 | PASS |

**Checked on live afterwards** (read-only):
- **250514:** every draft now has BUSCO and Merqury (30 of 30).
- **250606:** the remaining gaps are the re-assembly drafts and OG1254.
- **Diff against the snapshot:** only the target families changed (busco 260 values, merqury 168, gfastats 7). No value that was filled before changed.
- **By hand:** OG133's BUSCO (C 26.9%, n 3,354) and QV (59.4604), OG1093's completeness (96.4163) and OG1263's N50 (1,523) equal the archived files.
- `check_draft()` no longer exists (dropped with `v3` by `072`), so it was not run.

### Not backfilled, although a file exists

- **Depth, 13 drafts** (OG1841 260114; 12 of 260909, as in A.0): `kmer_depth.json` has `status: too_few_busco_regions` and no depth. There is nothing to load. Their ENA `COVERAGE` stays held.
- **Verdict, 7 drafts** (OG1254, OG1262, OG1263 250606; OG1724 251210; OG1942 251215; OG1889 260108; OG2607 260724):
  - Their `coverage_summary.json` predates the reliability gate and has no verdict.
  - A.6 skipped them: OG1724 has no GenomeScope files, OG2607 no BAM, and the others were outside its lists.
  - The `GENOME_SIZE_ONLY` mode would give them one.
- **OG1254 250606, FCS-GX:**
  - The filter report and <500 bp count are archived.
  - The Tiara, BUSCO, Merqury and gfastats files are not, yet the database has all four.
  - `parse_decontamination` needs the Tiara file, so the family cannot be rebuilt without risking the stored Tiara values. Left as is.

## Re-runs started 2026-11-09 (owner: gfastats and depth only)

All on Setonix under `/scratch/pawsey0964/tpeirce/draft_backfill/`; nothing is staged on this host.

### gfastats, 727 drafts

- **Script:** `gfastats/gfastats_only.sh`. It is a Slurm job on `copy` (account `pawsey0964`, 16 CPUs, 59 GB, 8 workers), because there is no pipeline entry for gfastats alone.
- **Per draft:**
  - It stages the `.fna` and GenomeScope summary from Acacia (S3 if the assembly is only there).
  - It runs the pipeline's container (`gfastats:1.3.6--hdcf5f25_3`) with the module's command: `gfastats --nstar-report --threads N <assembly> <size>`. The size is the haploid length from the reseeded summary if there is one, else the original; it is omitted if not a positive integer. The NG statistics it feeds are not stored.
  - Output goes to `results/<OG>/assemblies/genome/gfastats/<prefix>.assembly_summary`, and the staged `.fna` is removed.
  - The status of each draft goes to `status.tsv`.
- **Test (job 52555124):** OG481 230419 and OG802 250520.
  - Scaffold count and total length equal the BUSCO values already stored (OG481: 122,869 and 714,867,696), and the expected size equals `genomesize`.
  - The fill-only dry run plans a WRITE for both.
- **Full run:** job 52555713, started 10:52 AWST.
  - It managed about 13 drafts per 20 minutes (around 12 minutes each per worker), which would be about 18 h.
  - A second job, 52557892 (`gfastats_only_rev.sh`), walks the list in reverse. Its temporary files carry the job ID.
  - Where the two meet, a draft may be done twice, or one copy may fail when the other removes the staged `.fna`. The finished summary is still written once, by an atomic `mv`.
- **Upload:** job 52557290 (`gfastats/upload_gfastats.sh`), queued `afterany` on both jobs. It runs the fill-only backfill (`--families gfastats --apply`) over every draft whose status is `ok`. Its report is `gfastats/rep_upload/`.

### Depth only, 36 drafts

- **Launcher:** `scripts/depth_only/run_depth_only.sh` from a `git archive` of the production clone (`d4bcb35`) at `pipeline/`. The production clone stays on `master`. Three changes in that copy only:
  - `BASE` is `draft_backfill/depth_only`.
  - The BUSCO table may be under `busco*/` (`busco_acti/` before 250606).
  - The GenomeScope model may be `kmers/<key>/<key>-genomescope_model.txt` (older layout). The reseeded model is never taken.
- **Test (OG69 and OG2, 250514):** both `status: ok`.
  - OG69: 106.76x, 2,331 regions, high partition. OG2: 44.46x, 2,077 regions, high partition.
  - The kmercov ratio is 0.95–0.97.
  - Uploaded to the 250514 drafts only; OG2's 240716 draft is unchanged, as is `genomesize`.
  - OG2, OG66, OG80 and OG83 have one undated BAM for two drafts. MEASURE_KMER_COVERAGE checks it against the assembly, and OG2's matched.
- **The other 34:** tmux `depth_rest` on setonix-06, log `depth_only/depth_rest.out`. Drafts without inputs are written to `depth_only/samplesheets/depth_rest.skipped.tsv`. Expected: OG1731, OG1738, OG1756 (no model), OG2607 (no BAM), OG373, OG399, OG421 (nothing).

### Progress, 2026-11-09 15:00 AWST

**Depth:** the `depth_rest` run finished at 13:26.
- **Samplesheet:** 24 drafts; 96 tasks succeeded.
- **Skipped (10):**
  - OG373, OG399 and OG421 (230324) have nothing archived.
  - OG2607 has no BAM.
  - OG1731, OG1738 and OG1756 have no model.
  - OG1752, OG1765 and OG1769 keep their model as plain `kmers/<key>.genomescope/model.txt`, a third layout. The launcher copy now accepts `kmers/<key>*/*model.txt`, and those three are running in tmux `depth_model` on setonix-05.
- **On live:** 26 of the 36 have `busco_read_depth` (5.9–106.8x), all with a high partition. All 26 `kmer_depth.json` files are `status: ok`.
- **GenomeScope against measured depth** (kmercov ÷ `lambda_depth`, which should be about 1):
  - 0.94–1.09 for most drafts.
  - About 1.5 for OG83 and OG102 (250514).
  - 8.7–15.2 for OG1262, OG1263 (250606), OG1917 (251210), OG1942 (251215) and OG1889 (260108). These have 6–10x depth and only 149–251 BUSCO regions, so their stored `genomesize` is very probably far too small. They are the first candidates for `GENOME_SIZE_ONLY`.

**gfastats:** 128 `ok`, 2 failed, at about 4 h.
- **Failures:** OG1293 (4.7 Gb assembly) and OG1280 (5.3 Gb) exited with an empty stderr. Most likely out of memory with 8 workers sharing 59 GB. Retry alone at the end.
- **Speed:** two more jobs, 52575735 and 52575737, run the middle thirds of the 581 drafts not yet started (`mid1.tsv` and `mid2.tsv`). The upload job now waits on all four.

### Outcome, 2026-11-11

**gfastats: 725 of 727 written to live.**
- **Jobs:** 52575735 and 52575737 completed. 52555713 and 52557892 ended `OUT_OF_MEMORY` (Slurm's verdict on the job after a worker was killed); the other workers had finished their drafts.
- **First upload (52557290) wrote nothing.** Three drafts (OG1273, OG1274, OG1277) failed validation. Each had a complete summary, but empty `.tmp` files from out-of-memory attempts sat beside it and matched the parser's glob. The script commits only when every draft validates.
- **Fix:** the 9 empty `.tmp` files were moved to `gfastats/leftover_tmp/`.
- **Second upload:** dry run 725 WRITE; then applied. 725 committed, 725 PASS. Report: `gfastats/rep_apply/`.
- **On live:** 1,600 of 1,720 drafts have gfastats. The assembled drafts still without are:
  - OG1280 and OG1293, the two largest assemblies (5.3 and 4.7 Gb), which ran out of memory. Retried alone (job 52774424, 1 worker, 59 GB), with an upload queued after it (52774425).
  - OG1254 250606 and OG617 230607, which have no final `.fna` anywhere (re-assembly list). OG1254's Acacia folder has `.fa`/`.fasta` copies, but not the published assembly.
- **BUSCO and gfastats N50 differ** for 109 of the 721 pre-250606 drafts that now have both. That is expected (data dictionary: BUSCO's N50 is unreliable).

**Depth: 29 of 36 written to live.**
- OG1752 (37.8x), OG1765 (64.6x) and OG1769 (86.8x) were measured on 2026-11-09, all `ok`, high partition, kmercov ratio 0.93–0.95.
- OG1769's upload task was killed once by the system and passed on its retry; the value is on live.
- **Not measurable (7):** OG373, OG399, OG421 (nothing archived); OG1731, OG1738, OG1756 (no GenomeScope model); OG2607 (no BAM).

## GenomeScope columns backfill, 2026-11-11

**The owner noticed** that many GenomeScope columns were empty. On live, before this fill:
- **221003–250520 (724 drafts):** only the max values were stored. Every `*_min`, `modelfit_allkmers`, `kmercov`, verdict, `genomescope_fit` and depth/host column was empty.
- **260925 (193):** `genomescope_fit` was empty, though its coverage summaries have it.

**Why the earlier backfill missed them:**
- **Glob:** the GenomeScope pattern was `kmers/*genomescope/*summary.txt`. Older runs publish `kmers/<key>/<key>-genomescope_summary.txt`, 240313 uses `kmers/<OG>.ilmn.NOVA_240313_LA/`, and some 251210 drafts a plain `summary.txt`.
- **Date parsing:** `ids_from_dot_name` cut the date at `_` only. The old name prefix `OG481.ilmn.230419-genomescope` gave `230419-genomescope`, and the 240313 one gave `NOVA`.
- **Tarballs:** 129 OGs keep `kmers/` only as `kmers.tar.gz` (6–16 GB, mostly meryl databases), which no listing showed.
- **Fill granularity:** fill-only worked per family, so a draft that had any GenomeScope value was never filled.

**Draft pipeline changes (branch `backfill-missing-families`; 214 tests pass):**
- **Per-column fill:** writes only columns the database has empty and the archive has a value for. Any stored value must match the file at the stored precision (`numeric(10,4)` rounding allowed), or the draft is refused. A column the file lacks is left alone.
- **Glob** is now `kmers/*/*summary.txt`. Candidates are matched by the identity inside the file; a reseeded summary is still preferred.
- **`ids_from_dot_name`** accepts `-` and the `NOVA_<date>_` run name.

**Done on Setonix** (`draft_backfill/gs/`):
- **Staging:** every draft's GenomeScope summaries and coverage JSONs (3,270 files, 34 MB). For the 129 tarred OGs, job 52776804 streamed each `kmers.tar.gz` and kept only the summaries; all 129 had one.
- **Snapshot:** [`records/draft_genomescope_before_261111.csv`](records/draft_genomescope_before_261111.csv), all 1,604 rows, taken before the writes.
- **Applied:** 1,426 + 155 drafts committed and verified. Refused, as intended: OG1752, OG1765 and OG1769 (251210). Their plain `summary.txt` comes from a different GenomeScope run than the stored values (e.g. OG1752: 1,462 Mb against 1,061 Mb stored).
- **Diff against the snapshot:** 925 drafts gained values: 720 got the six `*_min`/`modelfit_allkmers` columns, 193 `genomescope_fit` (260925) and 12 `busco_regions` (260909). No stored value changed. `output_set` is generated and moved `core` → `extended` where values were added.
- **Coverage now:** `*_min` 1,581 of 1,604.
  - The 23 without are the 3 refused, OG1724 and OG25 (two candidate summaries each), OG1848 and OG617 (no summary), and 16 with nothing on Acacia for the draft: OG303–OG312 (221123), OG373, OG399, OG421, OG1731, OG1738, OG1789, OG2407, OG2409.
  - OG303 and the other 221123 drafts have a k-mer histogram, so GenomeScope could be re-run from it.

**Still empty for ≤250520 and not in any file:** `kmercov`, `genome_size_reliable`, `genome_size_flags`, `genomescope_fit`, `lambda_depth`, `busco_read_depth` and the host columns. These are computed by `DEPTH_ONLY` and `GENOME_SIZE_ONLY`, which these batches never ran (20 of 250514 aside). That is a re-run of 700+ drafts whose BAMs are often inside `assemblies.tar.gz`.

## Re-run list

| Re-run | Drafts | Inputs | How |
|---|---:|---|---|
| **gfastats** | 727 | The `.fna` alone (Acacia or S3) | A small `-entry GFASTATS_ONLY` in the style of `depth_only.nf`; upload with `push_gfa_results_to_sqldb.py`. Every batch 221003–250520, plus 4 later. Minutes of CPU each |
| **Depth, no depth of any kind** | 25 + 11 | 25 have every input: 16 of 250514, plus OG1262, OG1263, OG1724, OG1752, OG1765, OG1769, OG1917, OG1942, OG1889. Of the 11: OG1731, OG1738, OG1756 (251210) have no GenomeScope model; OG2607 has no BAM; OG373, OG399, OG421 (230324) have none of the inputs. OG2, OG66, OG80, OG83 (250514) have a BAM, but the OG has two drafts and the BAM name carries no date, so check which draft it belongs to | `DEPTH_ONLY` lists |
| **Depth, `scdepth` only** | 701 | Archived (BAM, BUSCO `full_table`, GenomeScope model) | `DEPTH_ONLY`. Optional: `scdepth` is the same quantity from DepthSizer. Re-running gives the host partition and `lambda_depth` cross-check, and is what the verdict needs |
| **Genome-size verdict** | 730 + 8 | `kmer_depth.json` from the depth re-run | `GENOME_SIZE_ONLY` after depth. A.6 found most sizes disagreeing with depth were wrong; none of the ≤250520 drafts has been checked |
| **Re-assemble** | 116 reads-only, plus 5 | Raw reads on S3 `illumina-raw/` for all of them | A full draft run. 250214 (80), 230607 (22), 260108 (6), 251215 (4), 230620 (3), 251031 (1). Plus 5 drafts whose assembly is in the database but whose `.fna` is on neither Acacia nor S3: OG617 230607, OG1848 260108, OG1789 260114, OG2407 and OG2409 260703 |

**Other notes:**
- **GenomeScope glob.** The backfill's GenomeScope glob is still `kmers/*genomescope/*summary.txt`. Before 250606, GenomeScope sits in `kmers/<OG>.ilmn.<date>/<…>-genomescope_summary.txt`. No draft needs it now, since every assembled draft has a GenomeScope row. Widen it before any `--families assembly` fill of those batches.
- **Unmatched folders.** Two keys on Acacia match no draft: `OG616/…230302` and a `multiqc/` folder (230814).

## Draft tables review and fixes (2026-11-18)

Plan: session plan `we-are-running-these-linear-pebble.md`. Runs on Setonix under `draft_backfill/`; snapshots in `docs/records/*_261118.*`. Every write was preceded by a read-only check and a snapshot, and checked against it afterwards.

### Fake `-genomescope` drafts: 674 removed

- **What:** the genome-size uploads of 2026-11-13 (b0–b6, 588 drafts), the 2026-11-11 tests (2) and rr1 on 2026-11-16 (84) each created a `draft_genome` row with `seq_date = '<date>-genomescope'`, holding only a `draft_genomescope` row.
- **Cause:** the scratch `pipeline/bin/draft_genome_stats.py` (from `d4bcb35`) took the date from the summary's `name prefix = OG481.ilmn.230419-genomescope` line, cutting only at `_`. The verdict and depth went to the real draft (they come from the coverage JSON); the GenomeScope summary at full precision went to the fake one, so the "full precision" part of the old-batch decision had not happened.
- **Fix:**
  - `ids_from_dot_name` in the scratch `pipeline/bin` replaced by the branch version (md5 `7fba2f1e…` → `d0b00ce8…`; old file kept as `.pre_261118`).
  - Re-push (`old_rerun/repush/repush.py`): the 688 summary + coverage pairs the push tasks had read, parsed with the patched code. Check first (read-only): every identity a real draft; every value equal to the real row at its stored precision and to the fake row; 8 drafts only filled empty `*_min` columns (OG25 230814, OG303–OG312 221123 except 305/307/311). Then `upload_records`, the pipeline's own upsert.
  - Diff against `draft_genomescope_before_repush_261118.csv`: 674 drafts changed; only `homozygosity`, `heterozygosity`, `modelfit`, `errorrate` (2 dp → 4 dp), the 8 fills, and 23 integer sizes by ±1 bp (rounding of the same fit). No fake row changed.
  - `DELETE` of exactly the 674 snapshot `draft_id`s (`draft_genome_junk_rows_261118.csv`), guarded on no rows outside `draft_genomescope`. Live: 1,747 drafts, none with a non-6-digit date.

### OG617 230607 stub deleted (owner)

Draft 500: a 2-read fastp row and copies of the 240813 draft's BUSCO, Merqury, Tiara, FCS, DepthSizer and GenomeScope values. Its 9 rows are in `og617_230607_stub_before_delete_261118.jsonl`. The `sequencing` row for the 230607 run is kept.

### Genome size and depth

| Drafts | Done | Result on live |
|---|---|---|
| 20 × 250514 (depth from 2026-11-09) | `GENOME_SIZE_ONLY` | All 20 have a verdict: 18 reliable; OG83, OG102 not (kmercov ratio ~1.5). All fits `original`, `genomesize` unchanged |
| OG87, OG108 231024; OG116, OG118, OG119 240313; OG311 221123 (refused at place on 1–20 bp) | Owner: GenomeScope sizes may differ by ≤ 0.01% (`GS_REL_TOL=1e-4` in `rr_place.py`, default 0). OG91 240313 (~12 kb off) kept out | All 6 placed; depth and verdict uploaded. OG87 reliable; the other 5 not (`implausible_model_bias`, ratio 1.36–1.57; OG311 `degenerate_model_fit`). `genomesize` moved 0–13 bp |
| OG108…OG119 above | Their stage folders had lost the BUSCO table and fastp report since 2026-11-16; re-staged with `rr_stage.sh` (rr2b) | — |
| OG1286 250331 | BUSCO short summary staged from Acacia's nested `busco.Acti/short_summary.specific…json` (values equal live; the launcher wants the lower-case `busco.acti` name) | Reliable, fit `original`, `genomesize` unchanged |
| OG301, OG302 221115 | k-mer histogram rebuilt from reads (meryl, then GenomeScope checked against live; `FORCE_NEEDS` in `rr_stage.sh`, exported explicitly since Setonix `sbatch` does not pass the environment) | Both reliable, fit `original`, `genomesize` unchanged |
| OG373, OG399, OG421 230324 | BUSCO 5.4.6 run on the S3 assembly (C 74.1 / 80.0 / 77.0 % against 74.6 / 80.4 / 77.4 % stored: used only for depth regions, never uploaded); then BAM, model, histogram and fastp from reads. Their first fastp pass used the current flags and was refused at place (17% off); 230324 ran fastp 0.23.4 `--max_len 150` (OG300's report), now in `rr_compute.sh`, and the second pass matched | All 3 reliable, depth 72.9 / 42.0 / 42.8x, fit `original`, `genomesize` unchanged |
| OG1289 250514 | BAM mapping on `highmem` (two OOMs at 230 GB: `samtools sort -@128 -m 1G` beside the index), then its fastp report re-staged from S3 (the stage folder had lost it, as for rr2b) | Reliable, depth 40.9x over 532 regions, fit `original`, `genomesize` unchanged |
| OG91 240313, OG348 230324 | — | Left: OG91 by decision; OG348 too few BUSCO regions |

### FCS-GX columns (`num_contigs_/bp_ exclude, trim, review`)

All 723 drafts ≤250520 had them empty.

- **From the archive (584):** `NCBI/<key>.filter_report.txt`, loose on Acacia. Filled by `fcs/fcs_fill.py`: only the six columns, only where all six are empty, one transaction with read-back. Identity check: the archived `<500 bp` count must equal the stored `num_contigs_lt_500bp`. OG481: EXCLUDE 4 / 4,549 bp, as in the file. Diff against `draft_contamination_before_fcs_261118.csv`: only those columns on those drafts; Tiara unchanged.
  - The backfill script's decontamination family was not used: it needs the Tiara summary, and the old summaries (tab header, space-separated rows) parse to zeros, so its own guard refused every draft.
  - Older reports print `TRIM 0 ` without bp (taken as 0 bp), and 230814 reports hold the block twice (identical; a retried `tee -a`).
- **Held (9):**
  - Archive and live disagree on the `<500 bp` count, so the archived report is from another decontamination run: OG304, OG306, OG309, OG310, OG311, OG312 (221123; by 13–79 contigs), OG490, OG517 (230419; by 7–10%).
  - OG348 230324: EXCLUDE 570,688 contigs / 2,313,565,842 bp, above the `integer` column's limit. Needs `bigint` (a migration) to store.
- **Re-screened (FCS-GX 0.5.5, the pipeline's database, on the pre-FCS `<key>.v129mh.fasta`; `fcs_rerun/`):** not a recovery of the original screen (2022–23, older GX and database).
  - 20 × 221003 (no GX report was archived): filled. OG269 has no species and ran with 7898 (Actinopterygii). Largest: OG298 106,128 contigs / 79.7 Mb, OG269 43,582 / 47.3 Mb.
  - 77 × 230419 whose `assemblies.tar.gz` has empty `NCBI/` and `tiara/` folders: filled (11 with no species ran with 7898). No `<500 bp` file exists for these or for 221003, so they had no identity check.
- **Cannot be filled (33):** no report and no pre-FCS assembly anywhere: OG373, OG399, OG421 (230324), and 30 of 230419 whose tarball holds only the final `.fna` (OG484, OG492, OG506, OG509, OG519, OG520, OG521, OG522, OG529, OG531, OG534, OG536, OG539, OG542, OG547, OG549, OG556, OG558, OG560, OG563, OG577, OG583, OG587, OG588, OG589, OG594, OG604, OG606, OG613, OG624).
- **Total:** 681 of the 723 filled (584 from the archive, 97 re-screened); 42 empty (9 held, 33 cannot).

### Where the draft tables stand (live, 2026-11-18)

- 1,747 drafts, none with a fake date.
- Drafts ≤250520 (723 assembled): a genome-size verdict for 721 (643 reliable); only OG91 240313 (owner) and OG348 230324 (too few BUSCO regions) have none, and only they keep 2 dp GenomeScope percentages.
- FCS-GX columns filled for 681 of 723; the 42 left are listed above.
- Re-assembly drafts with no assembly anywhere (105 ≤250520, 12 later) and `draft_submission` are unchanged and outside this work.

### BUSCO stop-codon columns

`internal_stop_codon_count/percent` stay empty for ≤250520: those batches ran BUSCO 5.4.6, which does not report them (owner).

### Drafts with no assembly (owner, 2026-11-23)

Of the 116 drafts with no assembly on live (list with runs: [`records/drafts_without_assembly_261123.tsv`](records/drafts_without_assembly_261123.tsv)), 104 will **not** be assembled:
- `NOVA_250214_AD`, 80 drafts (OG1162–OG1251): a collaborator's data set, one species.
- `NOVA_230607_LP` "Jess" samples, OG206–OG226 (21): *Galeocerdo cuvier*.
- `NOVA_230620_LP` OG3, OG12, OG15: use the 230814 drafts; the 230620 reads are likely in that assembly.

The other 12 are rows with 0–404 reads (OG472 230607, OG864 251031, and 251215/260108 rows of OG1834, OG1842, OG1844, OG1845, OG1846, OG1849, OG1850; all but OG472 and OG864 have an assembled 260114 draft). There is no re-assembly backlog.

Owner, 2026-11-23: all 116 rows stay in the draft tables, stubs included ("they tell a story"). Nothing is deleted.
