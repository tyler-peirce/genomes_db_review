# Plan: depth and genome-size re-run for drafts up to 250520

Status: **done 2026-11-18.** Run 2, the re-run from reads (rr1) and the fixes are recorded below and in [`draft_backfill_record.md`](draft_backfill_record.md) ("Draft tables review and fixes"). Left by decision or for lack of input: OG91 240313 (owner), OG348 230324 (too few BUSCO regions; its FCS-GX exclude total needs `bigint`), and 42 drafts with no FCS-GX values (9 held, 33 with no source).

## Why

The 724 assembled drafts from 221003–250520 never went through `MEASURE_KMER_COVERAGE`, `GENOMESCOPE_RESEED` or `RECHECK_GENOME_SIZE`. On live, 704 of them have no:
- `busco_read_depth`, `lambda_depth`, `busco_regions`;
- host partition (`host_*`, `partition_*`);
- `kmercov`, `genome_size_reliable`, `genome_size_flags` or `genomescope_fit`.

The 20 from 250514 that have depth were done on 2026-11-09.

These values are not in any archived file, so they have to be computed. The two modes that compute them already exist and were run on 250606–260925 (A.4 and A.6 in [`r6_gate_a3_a5_record.md`](r6_gate_a3_a5_record.md)):
- `-entry DEPTH_ONLY` reads the assembly, BAM, BUSCO table, GenomeScope model and fastp report.
- `-entry GENOME_SIZE_ONLY` then reads that `kmer_depth.json`, plus the meryl histogram, GenomeScope summary and model, seqkit stats, BUSCO short summary and fastp report.

The A.6 runs showed why the verdict matters: 183 of 542 later drafts had a GenomeScope fit that disagreed with the measured depth, and most of those genome sizes were wrong.

701 of these drafts have DepthSizer `scdepth`. It is the same quantity as `busco_read_depth`, but without the host partition or the GenomeScope cross-check, and the verdict needs `kmer_depth.json` either way, so they are in scope.

## What the archive holds (Acacia listing, 2026-11-09)

| Inputs | Drafts |
|---|---:|
| All loose on Acacia, or the assembly on S3 | 509 (15 of them share one undated BAM between two drafts of the OG) |
| Need `assemblies.tar.gz` and/or `kmers.tar.gz` opened | 129 |
| Reach both steps (includes 26 with the histogram under another name) | **664** |
| Cannot run: no GenomeScope model, fastp report or BAM anywhere | 40 |

**Tarballs:**
- About 12 GB each (OG280's assemblies tarball: a 10 GB BAM, 1 GB `.fna`, BUSCO files). Listing one takes about 90 s.
- Their layout differs: `assemblies/genome/bam/<key>.sorted.bam`, and `busco/<OG>/<OG>.<date>.busco.<Tag>.full_table.tsv` with no `ilmn`.
- `kmers.tar.gz` holds the model and histogram; its summaries were extracted on 2026-11-11.

The 40 that cannot run are listed per draft in the stage report (step 1), and their stored genome size stays without a verdict.

## Steps

### 1. Stage (Slurm `copy`, account `pawsey0964`, 8 streams)

Into `/scratch/pawsey0964/tpeirce/draft_backfill/old_rerun/stage/<OG>.<date>/`, in the loose layout the launchers already read:
- **Loose drafts:** `rclone copy` with the launcher's include patterns, widened as on 2026-11-09 (`busco*/`, `kmers/<key>*/*model.txt`, the histogram under `kmers/*<date>*.hist`).
- **Tarred drafts:** stream each tarball (`rclone cat | tar -xz --wildcards`) and keep only:
  - from `assemblies.tar.gz`: the BAM, `.fna`, BUSCO full table and short summary;
  - from `kmers.tar.gz`: the model and histogram.

  Each file is put at the loose path with the draft key in its name, e.g. `assemblies/genome/bwa/<OG>.sorted.bam` and `assemblies/genome/busco_tar/<key>.busco.<tag>.full_table.tsv`.
- **fastp:** from S3.
- **Report:** each draft is `ready` or names what is missing.
- **Size and time:** about 12–15 GB per draft (the BAM), so stage in batches of about 100 drafts (about 1.5 TB). That is about 7 TB pulled in total, 6–8 h of copying.

### 2. Depth only, by batch

- **Launcher:** the scratch copy of `run_depth_only.sh` (`draft_backfill/pipeline/`, from production `d4bcb35`) with `BASE` set to the new folder. Production stays on `master`.
- **Test first:** OG280 (tarred), OG481 (loose) and one shared-BAM draft (e.g. OG2 240716).
  - Check each `kmer_depth.json` is `status: ok`, and that `MEASURE_KMER_COVERAGE` accepts the BAM against the assembly.
  - A BAM built from the other draft of the OG fails that check rather than giving a wrong depth.
- **Then** batches in tmux, as on 2026-11-09.
- **Upload:** `PUSH_KMER_DEPTH_RESULTS` writes the depth and partition columns only. They are empty for all these drafts, so nothing is overwritten.
- **Cost:** about 0.6 CPU-h per draft (2026-11-09: 13.9 CPU-h for 24 drafts), about 400 CPU-h in all, and about a day of wall time with staging.

### 3. Genome size only

- **Launcher:** a scratch copy of `run_genome_size_only.sh` with the same pattern widening, the histogram pattern, and `DEPTH` pointing at step 2's folder. Only drafts with `status: ok` depth go in.
- **Snapshot before any upload:** `docs/records/genome_size_before_old_rerun.csv`, every column the upload can touch, as A.6 did.
- **Test:** the step 2 test drafts first, then by batch.
- **Upload:** `PUSH_ASSEMBLY_RESULTS` writes the whole GenomeScope family (see decision 1).

### 4. Check, record, archive

- **On live:** fill counts by batch; a diff against the snapshot with every changed `genomesize` listed against `host_haploid_size`; and that no depth column changed in step 3.
- **Record:** `docs/draft_backfill_record.md` and a review revision line.
- **Archive to Acacia** (asked separately): `*_kmer_depth.json`, the final `*_coverage_summary.json`, the reseed decisions and winning refits, copied in beside each draft with `--ignore-existing`, as A.6 did.

## Progress

**2026-11-11, test staging** (`old_rerun/stage_old.sh`, Slurm `copy`):
- **OG481 and OG2 240716:** all loose, `ready`.
- **OG280:**
  - Its assembly, BAM and BUSCO table and short summary came from `assemblies.tar.gz` and were renamed to the loose layout.
  - Its `kmers.tar.gz` has the summary and histogram (`<key>.hist`), but **no GenomeScope model**.
  - Up to 108 tarred OGs may be the same: 108 of the 206 with `kmers.tar.gz` have no loose model.
- **Bug found and fixed:** the "already staged" check also searched the extraction folders, so extracted files were never moved into place.

**Step 1b, regenerate missing models** (`old_rerun/regen_models.sh`):
- GenomeScope2 is run as the pipeline runs it (`-k 21 -m 1000`, same container) on the archived histogram.
- The model is kept only when the new summary parses to exactly the archived values; otherwise the draft is skipped.
- **OG280:** every value identical; model placed.
- **Run it as one task:** two concurrent copies wrote an interleaved summary.

**Launchers:**
- `run_depth_only_old.sh` and `run_genome_size_only_old.sh` are in `draft_backfill/pipeline/scripts/`. They set `BASE`/`DEPTH` to `old_rerun/`; the genome-size copy also accepts old-layout summary, model and BUSCO names.
- **Batches:** `old_rerun/batches/b0`–`b6` (101 drafts each, 95 in b6, by date). Batch 0 staging started (job 52794629).

**Test results (2026-11-11), checked on live against the snapshot**

| Draft | Route | Depth | Regions | kmercov ratio | Genome size |
|---|---|---:|---:|---:|---|
| OG481 230419 | loose | 74.6x | 2,960 | 0.96 | `reliable`, `kmercov` 30.88, fit `original`, `genomesize` unchanged |
| OG280 230419 | both tarballs, regenerated model | 24.6x | 1,314 | 0.95 | `reliable`, `kmercov` 10.13, fit `original`, `genomesize` unchanged |
| OG2 240716 | loose, BAM shared with 250514 | wrong | 158 | — | not run |

**OG2 240716 is a defect in the pipeline's BAM check:**
- MEGAHIT names contigs `k141_N` in every run, so a BAM built from the OG's other draft (250514) passed the name check.
- Its depth (40.48x over 158 regions) was uploaded. The 8 depth columns of draft 642 were set back to NULL at once, guarded to exactly that row and value; the snapshot shows they were empty this morning.
- **New gate (step 1c, `old_rerun/bam_check.sh`):** the BAM header's contig names and lengths must equal the assembly's.
  - OG481 and OG280 match; OG2 240716 does not.
  - The four shared-BAM drafts uploaded on 2026-11-09 (OG2, OG66, OG80, OG83 250514) all match, so their values stand.
- **Elsewhere on live:** only two other multi-draft OGs have a depth on one draft: OG891 251031 and OG1848 260114. Both are the newer draft, which owns the archived BAM, with healthy region counts.

**Other fixes made during the test:**
- Tarball extractions now go to `old_rerun/tar_extract/<draft>/`, outside the stage folder; a leftover duplicate assembly there had made OG280's ambiguous.
- `run_depth_only_old.sh` no longer re-copies (and re-hashes) staged files.

**Full run started 13:35 AWST:** `old_rerun/run_batches.sh b0 … b6` in tmux `old_batches` on setonix-03, log `old_rerun/run_batches.log`. Per batch:
1. Stage (the next batch stages in the background).
2. Gate (`gate.sh`): model regeneration, then the BAM check.
3. Depth only.
4. Genome size only, for drafts whose depth is `ok`.
5. Plain `rm` of that batch's staged BAMs and assemblies.

The three test drafts' staged files were removed the same way (7 files).

**First full run (2026-11-11 13:35–16:35) computed nothing.**
- **Run name:** the driver passed lists named `gate/b0.ready.tsv`. The launchers name the Nextflow run after the list, and `depth_b0.ready_…` is not a valid run name, so every depth and genome-size launch exited at once.
- **No stop on failure:** the driver went on to each batch's cleanup and removed the staged BAMs and assemblies (1,479 files).
- **On live:** no upload happened; the ≤250520 drafts still have only the 22 depths and 2 verdicts of before.
- **Kept:** the 106 regenerated models (all accepted) and the stage reports.

**The gate was also too strict.** It excluded 62 drafts as MISMATCH.
- The archived assembly is the decontaminated, adapter-trimmed one, so a few contigs differ from what was mapped: OG89 240716 shares 98,790 of 98,995 contigs with its BAM, and OG110 240716 shares 123,781 of 123,785.
- A BAM from the other draft shares almost none: OG2 240716, 49 of 331,874.
- **The check now requires** at least 98% of the assembly's contigs to be in the BAM header with the same name and length.

**Second run started 2026-11-13 09:45** (tmux `old_batches2` on setonix-03; the first run's log is `run_batches.run1.log`).
- The driver copies each list to `gate/ready/<b>.tsv` and `gate/gsize/<b>.tsv`.
- It stops with nothing removed if either launcher exits non-zero.
- The `stage_done` markers were cleared, so every batch is staged again.

**gfastats OG1280/OG1293:** job 52774424 timed out at 12 h, running one worker on both. Resubmitted as 52976590 (2 workers, 2 days), with its upload as 52976592.

## Owner decisions (2026-11-11)

1. **Full upload, as A.6.** Snapshot first; refits may change `genomesize`; every draft gets a verdict; percentages go to full precision. Every changed size is listed against the host size afterwards.
2. **Staged files are removed by me, on Pawsey, between batches.** Only the BAMs and assemblies I staged, by plain `rm` of each file, run on Setonix, never from this host.
3. **All 664 are in scope**, including the `scdepth` drafts.

## Decisions as first asked

1. **The genome-size upload changes stored values.** A.6 accepted this for 250606 onwards:
   - **`genomesize` changes** wherever a reseeded fit wins. In A.6 that was 56 of 183 suspects, 55 of them closer to the host size.
   - **Every draft gets a verdict.** Many will be `unreliable` (A.6: 173 of 183 suspects).
   - **Percentages are re-read at full precision:** the stored GenomeScope percentages are rounded to 2 dp and become full precision.

   The alternative is to upload the verdict columns only and report the refits without applying them.
2. **Staging space.** The BAMs make about 1.5 TB per batch. The launcher never deletes, so the batch's staged BAMs and assemblies must be removed between batches. Either I remove them file by file (plain `rm` of the files I staged, no recursive or forced delete), or you run the cleanup command I give you after each batch.
3. **The 701 drafts with DepthSizer `scdepth`** are included by default (above). Say if you would rather run only the 3 drafts with no depth of any kind.

### Result (run 2, finished 2026-11-13 19:09; checked on live 2026-11-16, read-only)

- 701 drafts in b0–b6. 654 passed the gate; 603 went through depth (51 skipped by the launcher: 26 no GenomeScope model, 25 no model and no fastp). 602 depth `ok`, 1 `too_few_busco_regions` (OG348 230324). Genome size ran on all 602. Every launcher exited 0; all staged BAMs and assemblies were removed (scratch `old_rerun` 28G after b6).
- Gate exclusions (47): 27 missing BAM or histogram (e.g. 221115), 19 BAMs from the OG's other draft (≤0.02% shared contigs), 1 borderline (OG63 240716, 97.8% shared).
- Live, drafts ≤250520: verdict 604 (541 reliable, 63 not), `busco_read_depth`/host 624, `kmercov` 604, partition 612 high / 12 low.
- `genomesize` changed for 14 drafts against `records/genome_size_before_old_rerun.csv`; each rose to near `host_haploid_size` (old fits were about half the genome). Reliable: OG453 230607, OG455 230607, OG619 230607, OG240 230324, OG780 250520. Not reliable: OG1274 250331, OG359 230324, OG182 230814, OG563 230419, OG500 230323, OG76 230814, OG74 240813, OG1282 250331, OG173 250520.
- Still needing a re-run (98 drafts, `old_rerun/reruns_needed.tsv` on scratch): re-map (no or wrong BAM) or rerun GenomeScope/fastp from reads.
- gfastats OG1280/OG1293: computed 2026-11-14; first upload refused on a leftover empty `.tmp`; moved to `leftover_tmp/`, upload 53213893 committed 727, 0 failed, 0 verification failures.

### Archive to Acacia (2026-11-16)

- Checked first, read-only (`draft_backfill/archive/verify_in_db.py`, the pipeline's parsers + `matches_stored`): 604 coverage summaries, 727 gfastats summaries, 634 depth files and the 14 winning reseeded GenomeScope summaries all PASS against live. One FAIL, held back: OG2 240716 `_kmer_depth.json` (the wrong-BAM depth reset on 2026-11-09).
- Copied with `rclone copy --ignore-existing` into `genomes.v2/<OG>/` in the production layout (`coverage/`, `kmers/<key>.genomescope/`, `assemblies/genome/{gfastats,seqkit}/`), plus the 106 regenerated GenomeScope models beside their summaries (`kmers/<key>/`). `rclone check`: 0 differences on every set. Nothing already on Acacia was replaced: 609 `coverage/versions.yml` already present (the genome-size step's copy) were left, and the depth step's copies were added as `coverage/versions.depth_only.yml`.

### Re-run from reads (started 2026-11-16)

- 99 drafts: 98 from `old_rerun/reruns_needed.tsv` plus OG2 240716. Four have no assembly anywhere (OG373, OG399, OG421 230324; OG617 230607, which also has no trimmed reads on S3) and need a full re-assembly: not started, owner to decide. The other 95 run in `draft_backfill/reads_rerun/`.
- Only the missing inputs are rebuilt, with the pipeline's own commands and containers; the archived assembly is kept. BAM: bwa-mem2 mem of the fastp reads (S3 analysed-data) to the archived `.fna`, samtools sort. GenomeScope model: `genomescope2 -k 21 -m 1000` on the archived histogram (found under `NOVA_240313_LA` names, which staging had missed), else meryl k=21 from the fastp reads. fastp report: fastp with the pipeline's flags on the raw lanes (S3 illumina-raw) pooled.
- Nothing is placed unless it reproduces the stored values (`rr_place.py`, read-only): GenomeScope summary equal to the stored GenomeScope columns; fastp report equal (or within 0.5%, listed as NEAR) to the stored fastp columns. New BAMs pass the same 98% contig gate. Then the same DEPTH_ONLY + GENOME_SIZE_ONLY runs (`rr_finish.sh`). New BAMs are kept on scratch pending an archive decision.
- Test: OG103 240313 model from the archived histogram: PASS, identical to live.
- fastp flags differ by run, so the rebuilt report uses the command recorded in a fastp report from the same or the adjacent run: 221115/221123 fastp 0.23.2 and 231024/240313 fastp 0.23.4, both `--max_len 150 --length_required 100` with no `--dedup`/`--cut_tail`; 230419 onwards the current flags. With the current flags OG303 221123 failed (total_reads 325.4M against 366.1M stored); with the 0.23.2 profile it matched every stored fastp column exactly.
- GenomeScope check allows 1 bp on the integer sizes (the stored values were rounded from a summary printed at different precision; OG82 and OG51 240313 differed by exactly 1 bp and otherwise matched).
- Running: `rr_driver.sh` (tmux `rr_driver`, setonix-03, 12 drafts at a time) then `rr_after.sh` (tmux `rr_after`, setonix-04): resets the four 231024 reports computed before the per-run profile (OG38, OG40, OG44, OG57), retries anything not placed, then `rr_finish.sh rr1`. Log: `reads_rerun/rr_driver.log`; checks: `reads_rerun/place_report.tsv`.

### Correction: the four "re-assemble" drafts (2026-11-16)

None of them needs a re-assembly.

- **OG373, OG399, OG421 (230324):** the inventory only counted Acacia copies of the `.fna`. Their 230324 `.fna` and trimmed reads are on S3 `analysed-data`, and `rr_stage.sh` already falls back to S3. The live sequencing table shows no newer run for any of them; 230324 NovaSeq is the latest. They were appended to `rr_list.tsv` (the old list is kept as `rr_list.before_reassemble_fix.tsv`), so `rr_after.sh` picks them up in its retry pass and they go through stage, compute and place like the rest.
- **OG617 230607:** superseded by the 240813 draft (library `OG617U_D_IL2`). That draft is complete on Acacia and live, with depth, `genome_size_reliable = t` and a host partition. The 230607 row has `total_reads = 0` and the same `genomesize` as 240813, so it looks like a stub, not a separate assembly. Not re-run.
- **For the owner, no change made:** OG617 also has a `seq_date = '240813-genomescope'` draft row holding only a GenomeScope result. It is a duplicate of the 240813 row.
- Record: `reads_rerun/reassemble.resolved.tsv`.

### Result of the re-run from reads, and corrections (checked 2026-11-18)

- **rr1 (2026-11-16 21:34–22:57):** 87 drafts placed, gate 87 ready / 0 excluded, depth and genome size exit 0. On live, drafts ≤250520 then had no verdict for 36 of 724 (was 120) and no depth for 13 (was 100).
- **Not placed in rr1:** 7 refused on GenomeScope differences of 1–20 bp (OG87, OG108, OG91, OG116, OG118, OG119, OG311); OG373, OG399, OG421 (no BUSCO table); OG1289 (out of memory twice). Genome size also skipped OG301, OG302 (no histogram) and OG1286 (no BUSCO short summary).
- **Correction: the genome-size uploads created fake drafts.** Every genome-size push in this plan (b0–b6 and rr1) ran with the unpatched scratch `pipeline/bin`. 674 `draft_genome` rows with `seq_date = '<date>-genomescope'` were made, OG617's among them, and the GenomeScope percentages went to them instead of the real drafts. The "percentages at full precision" part of decision 1 had therefore not been applied.
- All of the above was fixed or finished on 2026-11-18: see "Draft tables review and fixes (2026-11-18)" in [`draft_backfill_record.md`](draft_backfill_record.md).
