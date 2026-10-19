# Phase RG, RG.1 record: `057_v4_ref_assembly.sql`

Runbook: [`ref_genomes_runbook_rg0_rg5.md`](ref_genomes_runbook_rg0_rg5.md) RG.1. Figures:
[`ref_genomes_rg0_record.md`](ref_genomes_rg0_record.md) §4.

**Status: rehearsed 2026-10-19; awaiting the owner's OK to apply on live.**

## What was built

| File | Purpose |
|---|---|
| `sql/057_v4_ref_assembly.sql` | Schema `v4`; `ref_stage`, `ref_assembly`, `ref_assembly_part`, `ref_assembly_run`; the 7 tool tables; `ref_key_map` and `ref_excluded_rows` (seeded from RG.0 §3); `sync_ref_genomes_source`, `sync_ref_assembly()`, `check_ref_assembly()`; the views `ref_genomes`, `goat_species_v1`, `v_ref_assembly_status`, `v_ref_assembly_summary`, `v_ref_assembly_run_readiness` |
| `sql/revert/057_v4_ref_assembly_revert.sql` | `DROP SCHEMA v4 CASCADE`, refusing while `058`/`059` objects exist |
| `scripts/sync_v4.sql`, `scripts/sync_v4.sh` | The nightly sync and check, separate from `sync_v3`. Log at `~/log/genomes_db_sync_v4.log`, plus a `.FAILING` marker |

**How `057` was produced.** Like `052`, it is generated from one column map, so the sync, the
check and the compatibility view cannot disagree about columns. The generator asserts that the map
covers all 53 non-key columns of `public.ref_genomes`: 51 go to tool tables, and 2 are dropped
(`k_mer_set`, `hap2_chr_level_max_len`).

**Departures from the runbook text:**
- The nightly check compares only the set of species `goat_species_v1` marks `in_assembly`, not
  the whole view. That set is the only part that depends on `ref_genomes`, and a full comparison
  costs about 22 s a night: the view takes 11 s to read on live, and the comparison reads it
  twice. The full view comparison is done here and again in RG.5.
- A public row with no value at all is never carried: no empty parts. The check reports these
  as a `note:`.
- Check names starting `note:` are informational. `sync_v4.sql` reports them and does not fail.
- `sync_ref_assembly()` sets `client_min_messages = warning`, which keeps the temp-table notices
  out of the nightly log.

## Rehearsal, 2026-10-19

The throwaway PostgreSQL 14 cluster was restored from a `pg_dump -Fc` of live taken at
05:31 UTC (23 MB), set up as follows:
- `en_AU.UTF-8`, as live;
- roles `readonly` and `oceangenom_web` recreated;
- private socket, port 55432.

The real `bin/apply_migrations.py` was run against it through `DATABASE_URL`. The restore was
clean, with the ledger at `056`.

| Check | Result |
|---|---|
| Apply `057` | Applied in 0.6 s; ledger 58. Every count equals RG.0 §4: 468 assemblies, 2,024 parts, gfastats 1,294, BUSCO 781, Merqury QV 968, completeness 878, OMNIC 576, seqkit 300, chromosome 300, 434 run links |
| Triage guard | Matched exactly 7 remapped and 12 excluded rows |
| `check_ref_assembly()` | Every check 0. `note: assemblies with no run link` 61 |
| `v4.ref_genomes` against `public.ref_genomes` | 0 rows differ either way (inside the check) |
| **Full** `v4.goat_species_v1` against `public.goat_species_v1` | **0 rows differ either way** (19,817 rows) |
| `sync_v4.sql` straight after | No changes; `sync_v4 ok` |
| Grants | `readonly` reads the tool tables; `oceangenom_web` reads `v4.ref_genomes`; default privileges in `v4` for `readonly` |
| Revert, then `pg_dump -s` against the pre-apply dump | Identical, except `pg_dump`'s random per-run `\restrict` token. No `v4` schema and no default-privilege row left |
| Re-apply | Clean |
| Replay with the ledger row deleted | No change. `v4.ref_genomes` md5 identical before and after; `--verify` clean |

**Simulated pipeline writes into `public`, then `sync_v4.sql`:**

| Change | Result in v4 |
|---|---|
| New assembly: one BUSCO-only row (OG762 991231 hic9 stage 3 hap1) | Assembly and part inserted, with 1 `ref_busco` row and nothing else |
| BUSCO value changed on an existing part | Updated in place; other tools unchanged |
| A gfastats-only row (p_ctg) deleted | Part deleted (cascade) |
| Merqury QV added to a part that had gfastats, BUSCO and OMNIC | 1 `ref_merqury_qv` row added; the others untouched |
| All OMNIC values cleared on a row whose only tool was OMNIC | That public row now has no value, so its part is dropped, not kept empty. `note: public rows with no value` = 1 |
| Checks after the sync | Every check 0 |

**Failure handling:**

| Case | Result |
|---|---|
| Two public rows with untriaged versions (`hic`, `hic1x`), plus a valid BUSCO change in the same night | `sync_v4 check failed after sync: … public rows with an untriaged key problem (2)`, exit 3. **The whole night rolled back:** the valid change was not applied either |
| `sync_v4.sh` on that failure | Exit 3. `.FAILING` written, naming the log and the runbook |
| Bad rows removed, `sync_v4.sh` again | Exit 0; change applied; `.FAILING` removed |

## One observation for RG.6, not a defect

On OG762 the HiFi-only assembly appears as two `ref_assembly` rows, because that is how
`public` stores it:
- **hifi1 241018:** stage 0 p_ctg/a_ctg, written by `04b`, dated by the HiFi run;
- **hifi1 241019:** stage-1 haplotypes, written by the hic run's push scripts under the hic
  run's date.

Measured on the rehearsal copy:
- **37 hifi1 assemblies have stage-1 parts only** (18 of them with OMNIC). All share a date with
  a hic assembly, and 30 have another hifi1 date for the same OG, as OG762 does.
- The other 51 hifi1 assemblies with OMNIC have stages 0 and 1 under one date. They are not split.

v4 mirrors `public` faithfully. Whether to fold the two into one assembly is a question for the RG.4 writers and the
RG.6 data rewrite, not for `057`.

## Apply on live

Pending the owner's OK.
