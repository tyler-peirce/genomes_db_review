# R.6 gate, A.3–A.5: backfill, depth-only mode, `ENA-draft-genomes` (2026-10-28)

Plan: [`r6_gate_plan.md`](r6_gate_plan.md).

## A.2 deployed

Both branches were merged by fast-forward:
- **Draft pipeline:** `origin/master` `4258bb8` → `5a055a5` (`r6-depth-columns`).
- **`ENA-draft-genomes`:** `origin/main` `b1a2759` → `fa72371` (`r6-coverage`).

Where each runs:
- **`ENA-draft-genomes`** runs from `~/ENA-draft-genomes` on this host, which is on `main`.
- **The draft pipeline** runs from `/software/projects/pawsey1348/tpeirce/repos/OceanOmics-OceanGenomes-Draft-Genomes` on Setonix, on `master`. That clone needs a `git pull` by the owner.

## A.3 backfill: 91 of 261 done

| Batch | Drafts | Source | State |
|---|---:|---|---|
| 260909 | 68 | Acacia `genomes.v2/<OG>/coverage/` | **Written** |
| 260925 | 23 | Acacia | **Written** |
| 260925 | 170 | Pawsey scratch only (`/scratch/pawsey1348/tpeirce/NOVA_260925_LA/draftgenomes/<OG>/coverage/`) | Waits for the run to be archived to Acacia |

How it ran:
- `push_kmer_depth_to_sqldb.py` from `r6-depth-columns`, over the staged `*_kmer_depth.json`.
- **Dry run first.** It also rewrites `lambda_depth`, the host columns and `partition_confidence`, so every staged value was compared with live first: 91 of 91 identical. The write therefore changed only `busco_read_depth`, `busco_regions` and `partition_note`.

On live afterwards:
- **260909:** 68 depths, 5.2–133.6x, 19 `partition_note`.
- **260925:** 23 depths, 7.5–36.4x, 1 `partition_note`.
- `v3.sync_draft()` carried all 91 to `v3`, and `check_draft()` is 0.

`genomescope_fit` stays empty for these: the 260909 coverage summaries predate it.

## A.4 depth-only mode: written, not yet run

Draft pipeline branch `r6-depth-only` (`57df4d9`), **not merged**: Nextflow is not installed on this host, so it has not been run.
- **Entry:** `nextflow run main.nf -entry DEPTH_ONLY --depth_samplesheet <csv>` (`workflows/depth_only.nf`). It runs `MEASURE_KMER_COVERAGE` and `SUMMARISE_KMER_COVERAGE` unchanged, plus `SEQKIT_STATS` where no stats are archived. It uploads the depth columns only, through the new `PUSH_KMER_DEPTH_RESULTS`. Nothing else is recomputed.
- **Launcher:** `scripts/depth_only/run_depth_only.sh <list.tsv>`.
  - It stages each draft's `.fna`, BAM, BUSCO `full_table` and GenomeScope model from Acacia, plus the fastp JSON from S3 (named `<OG>.ilmn.<RUN>_<seq_date>_<initials>.fastp.json`, checked on two OGs).
  - It writes the samplesheet and logs every draft with a missing or ambiguous input.
  - Where a draft has BUSCO tables for two lineages it takes the first in sorted order; either set anchors the depth.
- **Lists:** `scripts/depth_only/lists/<seq_date>.tsv` holds the 590 measurable drafts from A.0. `test_three.tsv` is OG1703 and OG1704 (251210) and OG1076 (250606).

**Next:** the owner runs `test_three.tsv` on Setonix and checks each `*_kmer_depth.json` `status`. That shows whether the archived BAMs match the archived assemblies. If it passes, merge to master and run the batches.

## A.5 `ENA-draft-genomes`

**Found: step 00 fails on live.** Its run lookup read `sequencing.og_id`, which has not existed since the v2 cutover (2026-10-15): `column sq.og_id does not exist`. Fixed on `main` (`4895647`):
- it reads `v_sequencing_browse`;
- it takes Illumina DNA libraries only (`library_type = 'illumina'`), as the draft pipeline links runs (`055`).

**`phase-r-v3` branch** (`582668b`, on top of `main`, pushed, **not run against live**):
- Steps 06 and 07 upsert `draft_submission` by `draft_id`. They fill only blank columns, and step 07 keeps its exactly-one-row check.
- Step 00 takes `scdepth` from `draft_depthsizer`.

**Rehearsal** on a restore of live, in two copies:
- **Old:** the `main` code on `public`, then `sync_draft()`.
- **New:** the branch code with `search_path = v3, public`.

| Check | Result |
|---|---|
| Step 06, three cases: no submission row (OG1076), partial with a matching BioSample (OG11), a conflicting BioSample (OG110) | Identical per-field outcomes: UPDATED / SKIPPED / CONFLICT_SKIPPED |
| Step 07 on OG48 and OG6 | Exactly 1 row in each version |
| `draft_submission` afterwards | 580 rows each; 0 differ |
| Step 00 samplesheet query | 1,697 rows each; no column differs |

The local checkout was put back on `main`, because this host runs the production steps.
