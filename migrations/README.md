# Migration Convention

Status: Draft convention for Phase 0.

The current database does not yet have source-controlled migrations. Until a migration tool is selected, use this folder for reviewed SQL migration files.

## File Naming

Use timestamped files:

```text
YYYYMMDDHHMM_short_description.sql
```

Example:

```text
202607071200_add_core_fk_indexes.sql
```

## Required Header

Every migration should start with:

```sql
-- Purpose:
-- Review source:
-- Expected impact:
-- Rollback notes:
-- Verification:
```

## Safety Rules

- Prefer additive changes before cleanup changes.
- Use `CREATE INDEX CONCURRENTLY` for large production tables when appropriate.
- Add foreign keys only after data-quality checks pass.
- Preserve public view/API outputs unless a contract change is approved.
- Keep data cleanup mappings in reviewed files before running updates.

