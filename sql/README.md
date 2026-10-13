# Numbered SQL Migrations

Status: **the project's one migration system.** Decided 2026-10-05 —
see [`../docs/migration_system_decision.md`](../docs/migration_system_decision.md) for the
evidence and for what that decision deliberately does not cover (the `v2` go/no-go).

These files are the deployed system of record for the `oceanomics_genomes` schema: numbered,
idempotent, hash-ledgered in `schema_migrations`, and applied with `bin/apply_migrations.py`.
Sqitch is retired — `sqitch.conf` and `sqitch.plan` are gone, `migrations/` is historical, and
the undeployed `v2` scaffold is reference DDL in [`../design/v2/`](../design/v2/).

The working rule for anyone changing the schema is in
[`../docs/database_change_checklist.md`](../docs/database_change_checklist.md) under
"Migration Governance". The short version: no DDL reaches this database any other way.

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
- **Reverts are partial.** `sql/revert/` covers `027` onwards only. `001`–`026` have
  no rollback scripts and will not get them retroactively — they are applied
  history.
- **Catch-up migrations have no-op reverts.** `033` and `034` describe objects
  that already existed; they created nothing. Their reverts deliberately do
  nothing and say so, because dropping a view or table the migration never
  created is data loss, not a rollback. To remove such an object, write a
  forward migration following the `031` / `032` pattern: investigate, archive,
  then drop. This is the standing pattern for any future catch-up migration.
- **`035`–`040` (the `v2` schema, Phase V.3) must not be replayed after the backfill.** Each
  carries its former verify script inside its own transaction, and those assert that the new
  tables and the quarantine are empty. That holds at creation, so the crash-recovery replay is
  safe, but a replay after `scripts/backfill_v2.sql` has run fails — loudly, and rolled back.
  Once V.6 consolidates `v2` into `public`, fix forward rather than replaying.
- **The `v2` cutover waits in `sql/cutover/`, unnumbered.** The runner reads only files
  directly in `sql/`, and applies pending files in order, so a numbered cutover waiting for its
  window would block every migration after it. On the day it is moved to the next free number
  and applied like any other migration; `docs/phase_v5_plan.md` has the commands. It also
  refuses to run unless the operator opts in with `PGOPTIONS="-c oceanomics.v2_cutover=go"`,
  in case it is numbered early by mistake. Its replay is a no-op once applied.
- **`000` cannot ledger itself.** The bootstrap file creates
  `schema_migrations`, and a file cannot contain its own SHA-256. On the live
  database it applies as a guarded no-op and is ledgered normally. On an empty
  database run it by hand first:

  ```bash
  psql -f sql/000_bootstrap_schema_migrations.sql
  bin/apply_migrations.py
  ```

  `bin/apply_migrations.py` prints exactly that when it finds no ledger.

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

Both exit non-zero on a problem. They run daily via `bin/drift_cron.sh`, which
is quiet unless something is wrong — see "Scheduled checks" below.

## Connecting to a target

No credentials are committed. The tooling resolves, in order: `$DATABASE_URL`,
then `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`, then
`~/postgresql_details/oceanomics.cfg` — the same file
`OceanOmics-Database/db_config.py` reads, so there is one credentials file for
both repos. Keep it mode `600`. See Finding 14 and
`OceanOmics-Database/ROTATION.md`.

## Scheduled checks

`bin/drift_cron.sh` runs `bin/check_drift.py` and `bin/apply_migrations.py
--verify` once a day. It is installed and runs daily at 07:17.

| Signal | Meaning |
|---|---|
| `~/log/genomes_db_drift.log` | Every run, pass or fail, appended. |
| `~/log/genomes_db_drift.FAILING` | Exists **only** while the last run failed. Removed on the next healthy run. |
| stdout / exit 1 | Produced only on failure. |

**This host has no MTA** — no `sendmail`, no `mail`, postfix inactive — so cron
mail is dropped. That is why the status file exists: it is the one signal you
can check without a mail system. Surface it from a login banner or a monitoring
agent. If an MTA is configured later, the silent-when-healthy behaviour means
cron mail will carry only real failures, and `MAILTO=` can go at the top of the
crontab.

Host cron, not CI: GitHub runners cannot reach the database host, and wiring
them up would mean committing credentials, which is what Finding 14 undid.

The crontab entry, recorded here so it survives a lost crontab:

```cron
# Schema governance: object-inventory drift + migration ledger hash check.
# Silent when healthy. On failure it writes ~/log/genomes_db_drift.FAILING --
# this host has no MTA, so cron mail would be dropped. See sql/README.md.
17 7 * * * /home/tyler/genomes_db_review/bin/drift_cron.sh
```

Install with `crontab -e`, and check it with `crontab -l`. Override the log
path with `DRIFT_LOG` when testing.

**It currently reports drift every day, on purpose.** Three tables —
`og_workflow_recommendation`, `og_workflow_assignment_log`,
`og_workflow_notification` — appeared on the live database by direct DDL after
the 2026-10-02 baseline and have not been claimed by anyone. They are in
neither `sql/` nor the baseline, so a rebuild would lose them. The decision was
to leave the alarm sounding rather than quietly accept them into the baseline;
see open question 16. Do not silence it with `--update` until someone owns
those tables.
