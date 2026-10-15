# Phase V.6 plan — consolidate `v2` into `public`

Status: **written and rehearsed 2026-10-15, not applied.** Source step: `database_review.md` §9,
Phase V.6. Previous step: V.5, migration `045`, applied 2026-10-13. Next step: V.7 (drop the
archive, coverage).

Two files, both outside the numbered sequence until the day, for the reason `045` was:

| File | What it does | Revert |
|---|---|---|
| `sql/cutover/drop_ss260818_snapshots.sql` | Phase F: drops the eight SS260818 snapshot objects | `..._revert.sql`, structure only |
| `sql/cutover/v2_consolidate.sql` | V.6: archives the `_pre_v2` objects, moves `v2` into `public`, drops schema `v2` | `..._revert.sql`, exact |

Each file's header explains its steps. This document covers what must be true before they run,
how to run them, and how to check they worked.

## What changes for everyone

- `FROM sample` and `FROM public.sample` are the same table. The database stops setting a
  `search_path`; new sessions get the default, `"$user", public`.
- Schema `v2` no longer exists. **A query that names `v2.sample` fails.** Nothing was told to
  write `v2.`, and nothing in this repository, the importer, the mitogenome pipeline or the
  samplesheet scripts does. A DBeaver user who started doing so after 2026-10-13 drops the
  prefix.
- Sessions already open are unaffected. Their `search_path` still says `v2, public`, and
  PostgreSQL skips a schema on the path that doesn't exist. No restart is needed. Recycling the
  web app's pool is tidy, not required.
- The twenty `*_pre_v2` objects move to schema `pre_v2_archive`, frozen as of the cutover.
  `readonly` can read them; nobody else can reach them. V.7 drops them.
- Column contracts don't change. Whatever V.5 removed stays removed.

## What the live catalog showed (2026-10-15)

These findings shaped the migration.

- **`v2` holds** 22 tables, 17 views, 60 indexes, one identity sequence and three functions.
  The third function, `build_postcuration_samplesheet_rows(text[])`, comes from no migration.
  The post-curation script drops and recreates it unqualified, so since `045` it has been
  landing in `v2`. Any such object is moved too and named in a NOTICE.
- **Name collisions with `public`** are why the `_pre_v2` objects have to leave first:
  - `rna_library_kinx_pkey` is held by `rna_library_kinx_pre_v2`;
  - `mitogenome_data_pkey` is held by `mitogenome_data_SS260818`;
  - the function `lca_set_content_hash()` exists in both schemas. The public copy and
    `set_updated_at()` are used only by triggers on `_pre_v2` tables, so they go into the
    archive with them.
- **Two things bind to `v2` by text, not OID:**
  - `quarantine()` is `LANGUAGE sql` and inserts into `v2.import_quarantine`;
  - `lca_set_content_hash()` is pinned to `search_path = v2, pg_temp`.

  Both are rewritten. The originals are kept in `pre_v2_archive.v6_moved`.
- **Phase F is a prerequisite.** `lca_results_view_SS260818` reads `sample_pre_v2`, the only
  dependant of a `_pre_v2` relation outside the set.
- **The importer named `v2.` 38 times.** Fixed first (prerequisite 1).

## Prerequisites

1. **Done 2026-10-15: `import_v2.py` uses unqualified names.** Its SQL follows the
   `search_path`, so the same code works before and after. A start-up check refuses to run if
   `sample`, `library` and `value_conversions` don't resolve to the v2 tables.
   - A `--dry-run` against live gave output identical to the 2026-10-14 nightly run.
   - With `search_path = public` it refuses, exit 2.
   - cron runs the file in place, so the 18:00 UTC run on 2026-10-15 is the first live run.
     **Confirm it exited 0 before applying.**
2. **Export `blast_filtered_lca_SS260818` somewhere outside git, and verify it.** It has
   192,207 rows (about 4.7 MB gzipped). `archive/snapshots_SS260818/MANIFEST.md` kept it out
   of the repo deliberately; the other four snapshot tables are already archived there. Reload
   the export into a scratch table and compare it `EXCEPT` both ways before relying on it.
   Record where it went in that MANIFEST. The Phase F file refuses to run unless the operator
   passes the row count of the verified export.
3. **Optional: tell DBeaver users and the web app owner** in one line: unqualified queries are
   unaffected; a `v2.` prefix stops working.

## Pre-flight, the morning of

1. `bin/check_drift.py` is clean. `bin/apply_migrations.py --verify` is clean with nothing
   pending.
2. The previous night's import: `~/lab_db_updates/out.YYMMDD.txt` shows a complete run, and
   `~/log/fetch_excel.FAILING` does not exist.
3. `scripts/audit_v2_dependents.py`, for the last time. Expect nothing new.
4. List what is in `v2` but not in `035`–`046`. Expect only
   `build_postcuration_samplesheet_rows`.
5. `pg_dump -Fc` of live. Restore it into a throwaway cluster and rehearse as in the record
   below. Keep the dump: it is also the permanent archive of the `_pre_v2` data once V.7 drops
   it.
6. Avoid 18:00 UTC (the import) and check nobody is mid-write.

## Apply

```sh
cd ~/genomes_db_review
git mv sql/cutover/drop_ss260818_snapshots.sql        sql/047_drop_ss260818_snapshots.sql
git mv sql/cutover/drop_ss260818_snapshots_revert.sql sql/revert/047_drop_ss260818_snapshots_revert.sql
git mv sql/cutover/v2_consolidate.sql                 sql/048_v2_consolidate.sql
git mv sql/cutover/v2_consolidate_revert.sql          sql/revert/048_v2_consolidate_revert.sql
git commit -m "Number Phase F and the v2 consolidation as 047 and 048"
PGOPTIONS="-c oceanomics.blast_filtered_lca_ss260818_exported_rows=192207" bin/apply_migrations.py --target 047
PGOPTIONS="-c oceanomics.v2_consolidate=go" bin/apply_migrations.py
```

Renumber if something else lands first. Both files take well under a second.

## Post-checks, from a new session

- `SHOW search_path` gives `"$user", public`, and `pg_db_role_setting` holds no database-wide
  `search_path`.
- `to_regnamespace('v2')` is NULL.
- `count(*)` from `sample` equals `count(*)` from `public.sample`.
- In a transaction you roll back:
  - one update through `embargo_assignment_view` lands in `public.sample`, not in
    `pre_v2_archive.sample_pre_v2`;
  - one update through `lca_validation_report_view` lands in `public.lca_validation`.
- `SET ROLE readonly` can read `summary`.
- For `oceangenom_web`: `has_column_privilege('public.sample', 'workflow', 'UPDATE')` is true
  and `has_table_privilege('public.sample', 'UPDATE')` is false.
- `bin/apply_migrations.py --verify` is clean. `bin/check_drift.py` now differs from the
  baseline by exactly the moves; accept them with `scripts/export_schema_baseline.sh`.
- The next nightly `import_v2.py` exits 0. The next mitogenome pipeline and samplesheet runs
  succeed.

## Rollback

```sh
psql ... -f sql/revert/048_v2_consolidate_revert.sql
psql ... -c "DELETE FROM schema_migrations WHERE filename = '048_v2_consolidate.sql'"
```

The rollback is exact and needs no data carried over, because the tables move back with
everything written to them. `045`'s revert can run again only after this. `047`'s revert
restores structure only; the data comes from the archive and the export.

## After the apply

- Move the cutover-only tools to `scripts/archive/v2_cutover/`. They compare `v2` with `public`
  or were one-offs, and mean nothing once `v2` is gone: `backfill_v2.sql`, `run_backfill.py`,
  `reconcile_v2.py`, `apply_value_rules.py`, `diff_v2_against_live.py` and
  `audit_v2_dependents.py`. `check_v2_mappings.py` stays; it reads no schema by name.
- Update `database_review.md` (V.6, Phase F, §13), `sql/README.md` and `migrations/README.md`.

## Rehearsal record — 2026-10-15

Run on a restore of a 05:38 UTC dump of live, with roles `readonly` and `oceangenom_web`
recreated. It used the real `bin/apply_migrations.py` from a copy of `bin/` and `sql/` with
the two files numbered `047` and `048`.

| Check | Result |
|---|---|
| Either file without its opt-in | Refused, with the message naming the setting |
| `047` with the row count | Applied. No SS260818 object left; `lca_validation_report_view_upd()` and the live view's trigger kept |
| `048` | Applied in about 0.3 s: 20 objects and 2 functions archived, 39 relations and 3 functions moved, schema `v2` dropped |
| `search_path` from a new session | `"$user", public`; no database setting |
| `sample` / `public.sample` | 3,401 / 3,401 |
| Index names | `mitogenome_data_pkey` and `rna_library_kinx_pkey` on the moved tables; the old ones in the archive |
| `quarantine()` | Rewritten to `public.import_quarantine`; a call works |
| `lca_set_content_hash()` | Re-pinned to `public, pg_temp`; triggers on `lca` and `lca_raw_results` intact |
| Writes through the two writable views | Landed in `public`, not in the archive (rolled back) |
| `readonly` / `oceangenom_web` | `summary` readable / `UPDATE (workflow)` only |
| `import_v2.py` against the consolidated copy | Exit 0. Output identical to the dry run against live, apart from one quarantine record the post-check itself wrote |
| Revert `048`, then `pg_dump -s` against the pre-apply dump | No line added. The only removals are the eight SS260818 objects, from `047`. `search_path` back to `v2, public` |
| Re-apply, then replay both with their ledger rows deleted | No-op; schema byte-identical; `--verify` clean |

One defect was found and fixed: a PL/pgSQL loop variable `r` shadowed a table alias `r`, and
the first apply failed on `record "r" is not assigned yet`. The rename was rehearsed again from
the same point.
