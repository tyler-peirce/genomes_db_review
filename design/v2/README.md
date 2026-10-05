# `v2` redesign — reference DDL, not a migration

Status: **written, reviewed, constraint-tested, and not deployed.** Nothing in this directory
is applied by any tool. There is no `v2` schema on the live database.

These files were authored as a Sqitch project at the repo root. Sqitch was retired as a tool
on 2026-10-05 (`docs/migration_system_decision.md`), so they moved here rather than being
deleted — the DDL is real work and the decision that would consume it has not been made.

## Why it is parked

The `v2` go/no-go is blocked on **open question 7** in `database_review.md`: which downstream
users and scripts query this database from outside `genomes_db_review` and
`OceanOmics-Database`. Cutover is a `search_path` swap, so the risk is a client carrying
hardcoded `public.` prefixes, or one that silently follows the swap. `pg_stat_activity` shows
at least two human consumers on DBeaver connecting as `postgres` from external IPs — evidence,
not an answer. Closing it needs `pg_stat_statements` or `log_statement = 'mod'` enabled for a
fortnight, a live `postgresql.conf` change that has deliberately not been made.

Consequence: **17 live objects have no catch-up migration and will not get one until this is
answered** — the 12 lab tables, the four live LCA tables, and `goat_species_v1`. Their DDL is
here, so writing `public` catch-up migrations for them would duplicate it and be wasted if
cutover proceeds.

## If cutover is approved

These become numbered migrations in `sql/`, in plan order, applied with
`bin/apply_migrations.py`. Do not resurrect Sqitch to deploy them. Original plan order:

| # | File |
|---|---|
| 1 | `deploy/create_v2_schema.sql` |
| 2 | `deploy/create_v2_lab_tables.sql` |
| 3 | `deploy/create_v2_browse_views.sql` |
| 4 | `deploy/create_v2_quarantine.sql` |
| 5 | `deploy/create_v2_summary_view.sql` |
| 6 | `deploy/create_v2_lca_tables.sql` |
| 7 | `backfill_v2.sql` (data load, not DDL; re-runnable and idempotent) |

The `revert/` and `verify/` pairs are retained. The verify scripts are executable checks worth
porting into the migrations' own verification; Sqitch ran them automatically after each deploy
and `bin/apply_migrations.py` does not.

## Two known gaps — read before deciding

1. **The five `v2` LCA tables have DDL but no backfill.** `backfill_v2.sql` covers the twelve
   lab tables only. A cutover today would land an empty `v2.lca`, `v2.lca_raw_results`,
   `v2.lca_validation`, `v2.blast_filtered_lca` and `v2.mitogenome_data`.
2. **`v2.summary` reads `public.lca_validation`** (`deploy/create_v2_summary_view.sql`,
   lines ~128–138) even though `v2.lca_validation` exists. Probably an oversight rather than a
   deliberate out-of-scope qualification: `master_species` and `ref_genomes` are
   schema-qualified on purpose and documented as such at the top of the same file;
   `lca_validation` is not.

## Background

- `docs/v2_scaffold_design_review.md` — the design review, decisions 1–11.
- `docs/v2_cutover_dependencies.md` — what reads the twelve lab tables, and what each needs at
  cutover. Eleven views audited down to two needing a rebuild; the other eight are
  cutover-neutral and are captured in `sql/033_catchup_core_views.sql`.
- `docs/lab_key_strategy.md`, `docs/spreadsheet_column_gap_analysis.md`.
