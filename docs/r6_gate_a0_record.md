# R.6 gate, A.0: measurement record (2026-10-28)

Plan: [`r6_gate_plan.md`](r6_gate_plan.md). Read-only throughout:
- live in a `default_transaction_read_only` session;
- Acacia with `rclone lsf`;
- Pawsey with `find`.

## Code read (fetched 2026-10-28)

| Repository | Ref | SHA |
|---|---|---|
| Draft pipeline | `origin/master` | `4258bb8` (2026-10-20) |
| Draft pipeline | `phase-r-v3` (also on origin) | `4d1fa2f`, 8 behind `origin/master` |
| `ENA-draft-genomes` | `origin/main` | `b1a2759` (2026-10-01) |
| Mito pipeline | `origin/inverts-dev` | `acf878c` (2026-10-20) |
| Mito pipeline | `phase-r-v3` | `f3f629f`, 10 behind `origin/inverts-dev`, **not on origin** |
| `OceanOmics-Database` | `origin/main` | `7e67d37`; the working copy has two uncommitted files that are not this work |

## Live

Out of 1,720 drafts:

| Column | Filled |
|---|---:|
| `host_assembly_size`, `host_haploid_size`, `partition_confidence` | 261 each (`partition_confidence`: 241 high, 20 low) |
| `lambda_depth` | 261 |
| `scdepth` | 701 |
| Assembled (`gfa_scaffold_n50`) with neither depth | **613** |

Types in `public.draft_genomes`:
- `host_haploid_size bigint`, `partition_confidence text`
- `lambda_depth` and `kmercov numeric(10,4)`
- `scdepth numeric(5,2)`

These live definitions match the migrations, compared by body:
- `v3.sync_draft()` matches `055`.
- `v3.check_draft()` matches `056`.
- Nothing depends on `v3.draft_genomes`. It grants `SELECT` to `readonly` and `oceangenom_web`.
- The ledger has 67 files; the last is `066`.

## Backfill source for the 261 drafts that have `lambda_depth`

| Batch | Drafts | `coverage/` on Acacia | Elsewhere |
|---|---:|---:|---|
| 260909 | 68 | 68 | — |
| 260925 | 193 | 23 | 170 on Pawsey scratch, `/scratch/pawsey1348/tpeirce/NOVA_260925_LA/draftgenomes/<OG>/coverage/` (`*_coverage_summary.json` and `*_kmer_depth.json`, 170 each) |

**NOVA_260925_LA is not yet archived to Acacia.** Scratch is purged, so archive it before the purge window.

## Depth re-run: the 613 drafts with no depth

Required for the depth-only mode, per draft on Acacia (`genomes.v2/<OG>/`):
- the `.fna`
- `assemblies/genome/bwa/*.sorted.bam`
- a BUSCO `full_table.tsv`
- the GenomeScope `model.txt`

| Status | Drafts |
|---|---:|
| All four present, can re-run | **590** |
| Already measured: `kmer_depth.json` exists, `too_few_busco_regions` (all 260909) | 12 |
| Missing an input | 11 |

The 11 missing an input:

| Missing | Drafts |
|---|---|
| GenomeScope model | OG1731, OG1738, OG1752, OG1756, OG1765, OG1769 (251210) |
| Everything, or not on Acacia | OG1848 (260108), OG1789 (260114), OG2407 and OG2409 (260703) |
| BAM only | OG2607 (260724) |

**Two more inputs are not on Acacia for any batch:**
- **fastp JSON.** It is archived to S3, `s3://ocom.oceangenomes/analysed-data/draft-genomes/<OG>/`.
- **seqkit stats.** Present only for 260514, 260724 and 260909.

`SUMMARISE_KMER_COVERAGE` needs both, for the read length and the assembly size. The depth-only mode therefore:
- stages the fastp JSON from S3;
- runs `SEQKIT_STATS` on the `.fna` where no stats exist.

Per-draft status is kept beside the depth-only samplesheets.
