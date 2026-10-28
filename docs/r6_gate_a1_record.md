# R.6 gate, A.1: migration `067` record

Plan: [`r6_gate_plan.md`](r6_gate_plan.md) A.1. Files:
- `sql/067_draft_depth_and_host_columns.sql`
- `sql/revert/067_draft_depth_and_host_columns_revert.sql`

## What it does

- **`public.draft_genomes`** gains `busco_read_depth numeric(10,4)`, `genomescope_fit`, `busco_regions` and `partition_note`. It adopts the hand-added `host_haploid_size` and `partition_confidence` with comments and value checks.
- **`v3.draft_genomescope`** gains all six. `has_value` counts them.
- **`sync_draft()` and `check_draft()`** are rebuilt from `055` and `056` (byte-for-byte equal to live) with the six added.
- **`v3.draft_genomes`** goes from 98 to 104 columns: depth beside `lambda_depth`, `genomescope_fit` with the genome size, and the host columns together.
- **One `sync_draft()` run** copies the 261 host values into `v3`.

## Rehearsal, 2026-10-28

Throwaway PostgreSQL 14.24 cluster:
- `en_AU.UTF-8`;
- roles `readonly` and `oceangenom_web`;
- private socket, port 55432.

Restored from a `pg_dump -Fc` of live (`~/oceanomics_genomes_pre_067_261028.dump`, 24 MB). The restore was clean: ledger at 67 files, every `check_draft` 0. Applied with the real `bin/apply_migrations.py` through `DATABASE_URL`.

| Check | Result |
|---|---|
| Apply | 0.5 s. `draft_genomescope upserted 261`; ledger 68 |
| `check_draft()` | Every check 0 |
| `v3.draft_genomes` | 1,720 rows, 104 columns, starting with `og_num`. Host columns 261 / 261. New depth columns 0 (filled by A.3 and A.4) |
| Nightly `scripts/sync_v3.sql` straight after | `sync_v3 ok` |
| Simulated writer: depth, regions, fit on OG3078 260909; depth only on OG1703 251210; then `sync_draft()` | `draft_genomescope upserted 2`; both in the view; checks 0 |
| `partition_confidence = 'medium'`, `genomescope_fit = 'refit'` on `public` | Both refused by the new checks |
| Grants | `readonly` and `oceangenom_web` can `SELECT` `v3.draft_genomes` |
| Revert, then `pg_dump -s` against the pre-apply dump | Identical, apart from `pg_dump`'s `\restrict` token |
| Re-apply | Clean; ledger 68 |
| Replay with the ledger row deleted | `sync_draft()` changed 0 rows. `v3.draft_genomes` md5 identical before and after (`d93e2c20…`). `--verify` clean |

## Live

**Applied 2026-10-28 at 07:41 UTC**, with the owner's go-ahead, by `bin/apply_migrations.py`. The pre-change dump was retaken immediately before: `~/oceanomics_genomes_pre_067_261028.dump`, 24 MB.

| Check | Result |
|---|---|
| Apply | `draft_genomescope upserted 261`; ledger 68 |
| `--verify` | 68 applied files, all hashes match |
| `v3.check_draft()` | Every check 0 |
| `v3.draft_genomes` | 104 columns. Host columns 261 / 261; `busco_read_depth` 0, waiting for A.3 and A.4. `readonly` and `oceangenom_web` keep `SELECT` |
| `check_drift.py` | Only the known og drift (`og_priority_log` +, `og_workflow_recommendation` −) |

**Baseline.** These files were refreshed from a read-only export:
- `schema/current_schema.sql`
- `schema/current_constraints.sql`
- `schema/current_indexes.sql`

Each change was taken hunk by hunk, keeping only what a ledgered migration explains:
- `067`;
- `066`'s LCA views;
- `061`'s `rna_qc_kinnex` key and FKs;
- `063`'s `design_description` comment and `sequencing.design_no` FK.

The last three had never reached these three files; only `current_views.sql` was refreshed then.

Left out, as live changes no migration explains, so the old baseline text stays:
- every `og_priority_log` / `og_workflow_*` change (the colleague's OceanGenom_Web work);
- four `master_species` columns (`ref_genome_country`, `ref_genome_country_source`, `first_reference_for_family`, `first_reference_for_genus`) and its comments, which are a colleague's species work.

`schema/object_inventory.tsv` is not regenerated, because that would accept the og drift. `current_views.sql` is unchanged, since it does not cover `v3`.

## Writers that depend on it

All committed and pushed as branches, not deployed:

| Repository | Branch | Change |
|---|---|---|
| Draft pipeline | `r6-depth-columns` (`5a055a5`, from `origin/master`) | `parse_coverage_summary()` reads the four new columns. New `parse_kmer_depth()` and `push_kmer_depth_to_sqldb.py`, which write the depth columns only. `RECHECK_GENOME_SIZE` copies `busco_regions`. The backfill reads `*_kmer_depth.json`. 173 tests pass |
| Draft pipeline | `phase-r-v3` (`3ccc1ab`) | Merged `origin/master` and the above. 0 behind master. `FAMILY_TABLES` maps all six to `draft_genomescope`. 179 tests pass |
| `ENA-draft-genomes` | `r6-coverage` (`fa72371`, from `origin/main`) | Step 00 selects `busco_read_depth`. Step 03 sends `busco_read_depth`, then `scdepth`, and stops when neither exists; no `total_bases / genomesize` |

Checked on a real file: OG3078 260909's archived `kmer_depth.json` gives `busco_read_depth` 68.55. That equals `lambda_depth × 2 × L / (L − 20)` with read length 148.

Each of these must deploy **after** `067` is on live. The draft pipeline and step 00 name columns that do not exist before it.
