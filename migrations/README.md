# `migrations/` — historical only

**Nothing is applied from this directory.** It exists to preserve the two migration
conventions this project tried before settling on one.

The live convention is numbered SQL files in [`../sql/`](../sql/), recorded in the
`schema_migrations` table and applied with `bin/apply_migrations.py`. See:

- [`../docs/migration_system_decision.md`](../docs/migration_system_decision.md) — why that one
  won, and what the decision does not cover.
- [`../sql/README.md`](../sql/README.md) — how to write and apply a migration.
- [`../docs/database_change_checklist.md`](../docs/database_change_checklist.md) — the working
  rule, under "Migration Governance".

## What is in `legacy/`

| Files | Convention | Fate |
|---|---|---|
| `202607070001_add_core_lookup_indexes.sql`, `202608040001_create_empty_lca_table_copies.sql` | Phase 0 hand-numbered draft (July 2026) | Superseded. Neither was applied from here. |
| `sqitch_{deploy,revert,verify}_add_core_lookup_indexes.sql` | Sqitch (Aug 2026) | Superseded by `sql/030_core_lookup_indexes.sql`, which deployed this change extended from 19 to all 24 index candidates. **Do not deploy.** |
| `sqitch_{deploy,revert,verify}_create_empty_lca_table_copies.sql` | Sqitch (Aug 2026) | Never deployed and no longer wanted — the August LCA rebuild took a different route. |

The six Sqitch changes that built the `v2` scaffold are **not** here. They were ported to
`sql/035`–`040` (Phase V.3) and are now the live schema in `public` (V.6, `048`).

Sqitch itself was retired on 2026-10-05: it never ran against this database and left no
registry schema. `sqitch.conf` and `sqitch.plan` are deleted. Do not reinstate it to deploy
anything in `legacy/` or `design/v2/`; port the DDL into a numbered file in `sql/` instead.
