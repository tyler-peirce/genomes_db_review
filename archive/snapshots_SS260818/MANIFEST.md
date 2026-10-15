# SS260818 snapshot archive

CSV exports of the August 2026 (`SS260818`) snapshot tables, plus `lca_old`.

Exported **2026-10-05** from `oceanomics_genomes` on `146.118.120.134`.

## Contents

| File | Source table | Rows | Status in the database |
|---|---|---:|---|
| `mitogenome_data_SS260818.csv.gz` | `mitogenome_data_SS260818` | 2181 | still live |
| `lca_SS260818.csv.gz` | `lca_SS260818` | 9890 | still live |
| `lca_raw_results_SS260818.csv.gz` | `lca_raw_results_SS260818` | 51032 | still live |
| `lca_validation_SS260818.csv.gz` | `lca_validation_SS260818` | 2056 | still live |
| `lca_old.csv.gz` | `lca_old` | 2895 | **dropped, migration 032** |
| `schema.sql` | DDL for all of the above **plus** `blast_filtered_lca_SS260818` and the three snapshot views | — | — |
| `SHA256SUMS` | checksums for every file here | — | — |

## Not archived, deliberately

**`blast_filtered_lca_SS260818` data is NOT here.** 192,207 rows — 51 MB as CSV,
4.7 MB gzipped, more than twice everything else combined. Decided against
committing that much binary to the repo. The table is still live in the
database, and its DDL *is* in `schema.sql`, but its contents exist only in the
database and the nightly S3 base backup
(`s3://ocom-databases/oceanomics_genomes/base_backups`).

If you drop that table later, export it somewhere else first.

**Exported 2026-10-15, before Phase F dropped the table:** `/home/tyler/blast_filtered_lca_SS260818.csv.gz`
(192,207 rows, 4.98 MB, sha256 `9e291c53e01413f6db85991d46c41769fad242736d01ed7c6d44c4d6627c3da4`). Outside the repo, by owner decision. Same
format as the files here (CSV with header, no column list needed). Verified by reloading it
into an empty table and comparing an md5 over every row, ordered, against live: identical
(`046d2ddeb253a34760b6af546af00cca`).

## Restoring

The exports **omit `og_num`** on every table. It is
`GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED`, so Postgres
refuses to `COPY` into it, and it recomputes itself from `og_id` on insert.
Nothing is lost.

Because of that, restore is a plain load with no column list and no
preprocessing:

```bash
createdb snapshot_restore
psql -d snapshot_restore -f schema.sql
zcat lca_SS260818.csv.gz | psql -d snapshot_restore \
  -c '\copy "lca_SS260818" from stdin with (format csv, header)'
```

Do **not** filter the CSV through anything that re-serialises it. A CSV
round-trip through most tools turns `""` (empty string) into an unquoted empty
field, which `COPY` then reads as NULL. That silently altered 11 rows of
`lca_validation_SS260818` during testing. Load the files as they are.

Verified on export day: all five files reload into an empty schema and compare
`EXCEPT` identical in both directions against the live tables.

## Three things to know before dropping the snapshots

1. **`lca_validation_report_view_upd()` is shared.** The same trigger function
   backs `lca_validation_report_view_SS260818` *and* the live
   `lca_validation_report_view`. Drop the snapshot views, keep the function.
2. **`sql/revert/027_reporting_views_live_tables_revert.sql` reads
   `lca_validation_SS260818` and `mitogenome_data_SS260818`.** Once those are
   dropped, migration `027` can no longer be reverted. `027` is applied and
   settled, so this is accepted — noted in that file.
3. **The table names are mixed-case.** Unquoted SQL folds to lower case and
   fails with `relation "mitogenome_data_ss260818" does not exist`. Double-quote
   every reference.

## Dependency state

As of migration `032`, `lca_old` is gone and with it the only foreign key into
`mitogenome_data_SS260818` from outside the snapshot set. The remaining three
inbound FKs are from `lca_SS260818`, `lca_raw_results_SS260818` and
`lca_validation_SS260818` — all within the set. The snapshots are now a
self-contained group: drop the three views, then the five tables.
