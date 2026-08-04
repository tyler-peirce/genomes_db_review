# Schema Baseline

Status: Staged Phase 0 artifact for the Ocean Genomes database review.

This folder is intended to hold source-controlled snapshots of the live PostgreSQL schema. These files are descriptive baselines, not migrations by themselves.

## Expected Files

| File | Purpose |
|---|---|
| `current_schema.sql` | Full `public` schema-only dump from `pg_dump`. |
| `current_views.sql` | View definitions extracted from PostgreSQL catalogs. |
| `current_indexes.sql` | Index definitions extracted from PostgreSQL catalogs. |
| `current_constraints.sql` | Constraint definitions extracted from PostgreSQL catalogs. |

## Export Command

From the repository root:

```bash
set -a
source /home/tyler/.env.db
set +a
./scripts/export_schema_baseline.sh
```

Or use a single libpq connection string:

```bash
DATABASE_URL='postgresql://USER:PASSWORD@HOST:PORT/DBNAME' ./scripts/export_schema_baseline.sh
```

The export script writes the files above into this folder by default. Do not commit credentials or environment-specific connection strings.

## Review Rule

Before structural cleanup starts, regenerate these files from the live database and review the diff. Any future database change should be represented by a migration and should leave this baseline reproducible.

