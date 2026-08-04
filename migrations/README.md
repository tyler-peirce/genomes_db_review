# Migration Convention

Status: Adopted — Sqitch.

Schema changes are managed with [Sqitch](https://sqitch.org/) from the repo root (`sqitch.conf` / `sqitch.plan` / `deploy/` / `revert/` / `verify/`). This replaced the Phase 0 draft convention of hand-numbered files in this folder; the two files created under that convention are preserved for history in `migrations/legacy/` and have been ported into Sqitch changes of the same name (`add_core_lookup_indexes`, `create_empty_lca_table_copies`).

## Connecting to a target

No target/credentials are committed to the repo. Set standard libpq environment variables before running Sqitch, e.g.:

```bash
export PGHOST=... PGPORT=... PGDATABASE=... PGUSER=...
export PGPASSWORD=...   # or use a ~/.pgpass entry instead
sqitch deploy db:pg:
```

Alternatively, register a named target once per machine (still no password committed):

```bash
sqitch target add prod db:pg://USER@HOST:PORT/DBNAME
sqitch deploy prod
```

## Adding a change

```bash
sqitch add <short_name> -n "One-line description of the change."
```

This creates `deploy/<short_name>.sql`, `revert/<short_name>.sql`, and `verify/<short_name>.sql`, and appends the change to `sqitch.plan`.

## Required content per change

Every deploy script should start with a short comment block carried over from the Phase 0 convention:

```sql
-- Purpose:
-- Review source:
-- Expected impact:
```

Rollback notes belong as comments in the `revert/` script; verification logic belongs as executable checks in the `verify/` script (Sqitch runs `verify` automatically after every `deploy`, and fails the deploy if verification fails).

## Safety rules

- Prefer additive changes before cleanup changes.
- Use `CREATE INDEX CONCURRENTLY` / `DROP INDEX CONCURRENTLY` for large production tables when appropriate, and add `-- no-transaction` as the first line of the `deploy`/`revert` scripts for that change (Sqitch wraps scripts in a transaction by default, which `CONCURRENTLY` cannot run inside).
- Add foreign keys only after data-quality checks pass.
- Preserve public view/API outputs unless a contract change is approved.
- Keep data cleanup mappings in reviewed files before running updates.

## Common commands

```bash
sqitch status prod      # what's deployed vs. pending
sqitch deploy prod      # deploy all pending changes (runs verify after each)
sqitch verify prod      # re-run verify scripts against a deployed target
sqitch revert prod      # revert the most recent change (prompts to confirm)
sqitch log prod         # deployment history
```
