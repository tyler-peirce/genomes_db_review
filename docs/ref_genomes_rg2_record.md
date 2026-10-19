# Phase RG, RG.2 record: `058_v4_ref_read_qc.sql`

Runbook: [`ref_genomes_runbook_rg0_rg5.md`](ref_genomes_runbook_rg0_rg5.md) RG.2. Figures:
[`ref_genomes_rg0_record.md`](ref_genomes_rg0_record.md) §4.

**Status: rehearsed 2026-10-19; awaiting the owner's OK to apply on live.**

## What was built

| Object | Purpose |
|---|---|
| `v4.ref_genomescope` | GenomeScope2, one row per `(og_id, seq_date)`. `seq_date` NULL = before RG, read set unknown |
| `v4.ref_hifi_adapter_filter` | HiFiAdapterFilt `contam_reads`, with the same key |
| `v4.hifi_read_qc` | One row per library per run. `sequencing_id` is set where exactly one sequencing row matches the rebuilt tube on that run |
| `v4.hic_read_qc` | One row per library per run per lane. Blank key parts become NULL. `sequencing_id` is set where exactly one Hi-C row of that OG and tissue is on the run |
| `v4.raw_qc`, `v4.hifi_reads_qc`, `v4.hic_reads_qc` | Compatibility views with public's columns in public's order. `raw_qc` shows the latest read set per OG, dated before undated |
| `v4.coverage_summary` | Today's definition, on the v4 views |
| `v4.v_read_qc_sequencing_readiness` | Read-QC rows with no link, and why |
| `v4.sync_ref_read_qc()`, `v4.check_ref_read_qc()`, three `sync_*_source` views | Window-only sync and check. `scripts/sync_v4.sql` already lists them |
| 4 `ref_excluded_rows` (`raw_qc`) | OG750_PD, OG90_bc2008, OG90ULI, OG760 (RG.0 §3) |
| `sql/revert/058_v4_ref_read_qc_revert.sql` | Drops 058's objects and its 4 exclusion rows; leaves `057` intact |

Like `057`, the file is generated from one column map.

**Departures from the runbook text:**
- `sequencing_id` uses `ON DELETE SET NULL`, not `CASCADE`. A read-QC row is real data even
  when its sequencing row is removed. The sync re-derives the link.
- There is no FK to `sequencing_run`. That table lives in `v3`, and `v4` must not depend on
  `v3`. The `run_id` FK waits for RG.6, after R.6 has put `sequencing_run` in `public`.
- While the sync owns `ref_genomescope` and `ref_hifi_adapter_filter`, it manages only rows
  with `seq_date` NULL, because `public` has no read-set date. The dated rows are for the RG.4
  writers.

## Rehearsal, 2026-10-19

Run on a throwaway PostgreSQL 14 cluster restored from a `pg_dump -Fc` of live taken at
06:28 UTC. That dump already includes `057`, with the ledger at `057`. Same set-up as RG.1.

| Check | Result |
|---|---|
| Apply `058` | Ledger 59. `ref_genomescope` 248, `ref_hifi_adapter_filter` 143, `hifi_read_qc` 277, `hic_read_qc` 552: **all equal to RG.0 §4** |
| Triage guard | Exactly 4 `raw_qc` rows excluded |
| `check_ref_read_qc()` | `raw_qc`, `hifi_reads_qc`, `hic_reads_qc` and **`coverage_summary`** all match public, 0 differences either way. No untriaged keys |
| Sequencing links | HiFi 262 of 277, Hi-C 475 of 552, as RG.0 measured |
| Readiness reasons | HiFi: run not in sequencing 7, tube not in `library` 4, no single row 4. Hi-C: run not in sequencing 22, several libraries 51, none 4. These total 15 and 77 |
| Blank Hi-C key parts | Stored NULL: tissue 2, ext_type 8, lib_code 1, lane 26. Shown as `''` by `v4.hic_reads_qc` |
| `sync_v4.sql` straight after | No changes; `sync_v4 ok` |
| `readonly` | Reads the new tables, through the default privileges and the grant |
| Revert, then `pg_dump -s` against the pre-`058` dump | Identical apart from `\restrict`. `057`'s objects and its 4 exclusions intact; `check_ref_assembly()` all 0 |
| Re-apply; replay with the ledger row deleted | Clean; the replay changed nothing (md5 identical); `--verify` clean |

**Simulated writes into `public`, then `sync_v4.sql`:**

| Change | Result in v4 |
|---|---|
| `raw_qc` genomesize changed (OG762) | `ref_genomescope` updated |
| `raw_qc` GenomeScope cleared, `contam_reads` kept (OG113) | The `ref_genomescope` row was deleted and the adapter-filter row kept. `v4.raw_qc` shows NULL GenomeScope values and contam 0, the same as public |
| New `raw_qc` row with contam only (OG2613) | 1 `ref_hifi_adapter_filter` row, and no GenomeScope row |
| `hifi_reads_qc` yield changed; one row deleted | Updated; deleted |
| New `hic_reads_qc` row with a blank lane on an unknown run | Inserted with `lane` NULL and `sequencing_id` NULL. Unlinked count 77 → 78 |
| OG88's blank-key Hi-C row changed | Updated in place; its link kept |
| Checks | All 0 |
| An orphan `hifi_reads_qc` row (OG999999X) | **The night failed** (`hifi_reads_qc: differs from public`, exit 3) and nothing was written to v4 |

## Apply on live

Pending the owner's OK.
