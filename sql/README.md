# Numbered SQL Migrations (deployed)

Status: **applied to the live database.** These 30 files are the deployed system
of record for the mitogenome/ENA schema work. The Sqitch project at the repo root
(`sqitch.plan` / `deploy/` / `revert/` / `verify/`) is **declared but has never
been deployed** — do not read `migrations/README.md`'s "Status: Adopted — Sqitch"
as a description of what is running.

Which of the two systems should be canonical is **undecided**. See open question
8 in `database_review.md`. One Sqitch change has since been resolved in this
directory's favour: `add_core_lookup_indexes` was ported to
`030_core_lookup_indexes.sql` and deployed from here, so the Sqitch copy in
`deploy/` is superseded and must not also be deployed. That precedent settles one
change, not the question. This directory exists to put the deployed migrations
under version control.

## Do not reformat an applied file

Each file's contents are hash-checked by a SHA-256 recorded in the live
`schema_migrations` table. Editing an applied file — including reformatting,
fixing a typo in a header, or changing line endings — invalidates that check and
leaves the ledger disagreeing with the tree.

To correct an applied migration, **supersede it with a new numbered file.**
`028_mitogenome_submission_view_annotation_key.sql` →
`029_mitogenome_submission_view_join_base_table.sql` is the worked example: 029
retains 028's fix, corrects its stated rationale, and explains both in its
header.

## Per-file conventions

Each migration opens with a prose header explaining why the change was made,
what was rejected, and what must not be done later. Keep that up — these headers
carry design rationale that is not recoverable from the schema itself.

Migrations are idempotent and guarded with `to_regclass()` so they replay safely
against a partial schema.

Every file is wrapped in `BEGIN`/`COMMIT` **except**
`030_core_lookup_indexes.sql`, which is `CREATE INDEX CONCURRENTLY` throughout
and therefore cannot run inside a transaction block. That file says so in its
header. Do not "fix" it by adding transaction control, and apply it in
autocommit.

## Known gaps

- ~~**The ledger is populated out of band.**~~ **Closed 2026-10-02.** Apply
  migrations with `bin/apply_migrations.py`, which runs the file and writes its
  `schema_migrations` row in one invocation, so the two can no longer come
  apart. It also refuses to do anything if an already-applied file's hash no
  longer matches the tree. Applying by hand still works and still risks the
  `026` failure mode — use the script.
- **Reverts are partial.** `revert/` covers `027`–`030` only. `001`–`026` have no
  rollback scripts.

## Applying a migration

```bash
bin/apply_migrations.py --dry-run    # what is pending, plus a drift report
bin/apply_migrations.py              # apply and ledger everything pending
bin/apply_migrations.py --verify     # hash-check applied files; exit 1 on drift
```

The script picks up `-- no-transaction` files automatically — it also detects
`CREATE INDEX CONCURRENTLY` directly, so `030` is handled correctly despite not
carrying the marker.

Drift in the object inventory (as opposed to the migration files) is a separate
check:

```bash
bin/check_drift.py              # live objects vs schema/object_inventory.tsv
bin/check_drift.py --coverage   # which objects no migration describes
bin/check_drift.py --update     # accept the current live state as baseline
```

Both exit non-zero on a problem, so either can go in cron or CI.

## Connecting to a target

No credentials are committed. The tooling resolves, in order: `$DATABASE_URL`,
then `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`, then
`~/postgresql_details/oceanomics.cfg` — the same file
`OceanOmics-Database/db_config.py` reads, so there is one credentials file for
both repos. Keep it mode `600`. See Finding 14 and
`OceanOmics-Database/ROTATION.md`.
