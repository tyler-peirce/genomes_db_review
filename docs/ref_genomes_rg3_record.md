# Phase RG, RG.3 record: `059_v4_ref_submission.sql`

Runbook: [`ref_genomes_runbook_rg0_rg5.md`](ref_genomes_runbook_rg0_rg5.md) RG.3. Figures:
[`ref_genomes_rg0_record.md`](ref_genomes_rg0_record.md) §4.

**Status: done 2026-10-19.** Rehearsed, then applied on live at 08:06:18 UTC.

## What was built

| Object | Purpose |
|---|---|
| `v4.ref_submission` | One per OG, as in public: BioSample, umbrella and raw-data BioProjects, and `embargo_status` (NOT NULL, Release/Embargo). `assembly_id` is the OG's one curated assembly, NULL where it has none or several |
| `v4.ref_submission_haplotype` | `(submission, hap1/hap2)`: BioProject, assembly and GCA accessions. Replaces the `_hap1`/`_hap2` column pairs. A row exists only where the haplotype has a value |
| `v4.ref_sra_upload` | One per SRR accession, under its `submission_id`. `ncbi_status` (Released/ToBeReleased) and **`status_date`** are split, at most one per row |
| `v4.ref_genomes_assembly_uploads`, `v4.ref_genomes_sra_uploads` | Compatibility views that reproduce public exactly; `ncbi_status` is recombined as `to_char(status_date, 'YYYY-MM-DD')` |
| `v4.sync_ref_submission()`, `v4.check_ref_submission()`, two `sync_*_source` views | Window-only. `scripts/sync_v4.sql` already lists them. The sync runs after `sync_ref_assembly`, so `assembly_id` follows the same night's assemblies |
| `sql/revert/059_v4_ref_submission_revert.sql` | Drops 059's objects; leaves `057`/`058` intact |

Profile on live before writing it (2026-10-19, read-only):
- `embargo_status` is never NULL: Release 76, Embargo 12.
- Every date in `ncbi_status` is ISO `YYYY-MM-DD`, and there are no other values.
- No row of either table is empty.
- OG695 has submission-level values only, with no haplotype accessions.

**Departures from the runbook text:**
- `ref_sra_upload` references `ref_submission`, not `sample` directly. Public's FK is to the
  assembly-uploads table, and this keeps that meaning.
- Values outside the CHECK domains (embargo, `data_type`, status) are reported as untriaged key
  problems and fail the night. They are never guessed.

## Rehearsal, 2026-10-19

Run on a throwaway cluster restored from a `pg_dump -Fc` of live taken at 07:59 UTC, which
includes `057` and `058` (ledger at `058`). Same set-up as RG.1.

| Check | Result |
|---|---|
| Apply `059` | Ledger 60. **All equal to RG.0 §4:** `ref_submission` 88, 84 with `assembly_id`, `ref_submission_haplotype` 174, `ref_sra_upload` 304 (status 164, `status_date` 132, neither 8) |
| `check_ref_submission()` | Both compatibility views match public, 0 differences either way. No untriaged keys. `note:` 4 submissions without a single curated assembly: OG637, OG645, OG910 (two curated), OG906 (none) |
| `sync_v4.sql` straight after | No changes; all four checks pass |
| `oceangenom_web` | Reads `v4.ref_genomes_assembly_uploads` |
| Revert, then `pg_dump -s` against the pre-`059` dump | Identical apart from `\restrict`. `sync_v4.sql` still passes with `057`/`058` alone (it skips functions that do not exist) |
| Re-apply; replay with the ledger row deleted | Clean; the replay changed nothing (md5 identical); `--verify` clean |

**Simulated writes into `public`, then `sync_v4.sql`:**

| Change | Result in v4 |
|---|---|
| New submission with hap1 values only (OG762) | 1 `ref_submission` row and 1 haplotype row (hap1). Linked to OG762's one curated assembly |
| Two new SRA rows, one dated and one with every value NULL | Date stored in `status_date`; the other row stored with all values NULL |
| An SRA status changed from a date to `Released` | `status_date` cleared and `ncbi_status` set |
| OG637's hap2 accessions cleared | Its hap2 row deleted; hap1 kept |
| OG906 gains a stage-3 part in `ref_genomes` | **Linked in the same night:** `sync_ref_assembly` added the part, then `sync_ref_submission` set `assembly_id`. Note count 4 → 3 |
| Checks | All 0 |
| An SRA status `Pending` | **The night failed** (`uploads: public rows with an untriaged key problem (1)`); nothing written |

## Apply on live, 2026-10-19

| Step | Result |
|---|---|
| Pre-flight | `059` the only pending file; no drift; no active sessions. Uploads 88 / 304, as in the rehearsal dump |
| **`059` applied** | **08:06:18 UTC**; ledger 60. Counts identical to the rehearsal: 88 / 84 linked / 174 / 304 |
| `--verify`, `check_drift.py --update` | Clean; 75 objects, +0 / −0 (`public` only) |
| `export_schema_baseline.sh` | No change beyond the `\restrict` token: `public` unchanged |
| `sync_v4.sh` by hand | 08:06:19 UTC, exit 0. All three v4 syncs and checks pass. Notes: 61 / 15 / 77 / 4. No `.FAILING` |

The throwaway cluster was stopped and deleted after this record was written.
