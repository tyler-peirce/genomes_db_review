# Schema Baseline

Point-in-time snapshots of the live `public` schema of `oceanomics_genomes`. These are
**descriptive baselines, not migrations** — they record what the database looks like, not how
it got there. Migrations live in [`../sql/`](../sql/).

Last re-baselined 2026-10-02 (the previous baseline was three months stale and described 31 of
53 tables).

## Files

| File | Purpose |
|---|---|
| `current_schema.sql` | Full `public` schema-only dump from `pg_dump`. |
| `current_views.sql` | View definitions extracted from PostgreSQL catalogs. |
| `current_indexes.sql` | Index definitions extracted from PostgreSQL catalogs. |
| `current_constraints.sql` | Constraint definitions extracted from PostgreSQL catalogs. |
| `object_inventory.tsv` | Approved list of live tables and views. The drift check compares against this. |

## Regenerating

```bash
./scripts/export_schema_baseline.sh          # rewrites the four SQL files
bin/check_drift.py --update                  # rewrites object_inventory.tsv
```

Credentials are never committed. Both the export script and the Python tooling resolve a
connection in the same order:

1. `$DATABASE_URL`
2. `DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USER` / `DB_PASSWORD`
3. `~/postgresql_details/oceanomics.cfg` — the shared credentials file, also read by
   `OceanOmics-Database/db_config.py`. Keep it mode `600`.

The old instruction to `source /home/tyler/.env.db` is superseded by that file; see Finding 14
and `OceanOmics-Database/ROTATION.md`.

## Rules

- **`object_inventory.tsv` is an approval, not an observation.** Run `--update` only once you
  have decided the live state is correct, and commit the result in the same change as the
  migration that explains it. A baseline update with no migration beside it is drift being
  rubber-stamped.
- **Every schema change should be a migration** and should leave this baseline reproducible.
- `bin/check_drift.py` reports two things: inventory drift against `object_inventory.tsv`, and
  with `--coverage`, which live objects no migration describes. The second is the Phase B
  catch-up worklist. It runs daily via `bin/drift_cron.sh`.
