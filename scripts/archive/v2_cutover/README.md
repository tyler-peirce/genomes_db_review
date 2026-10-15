# Retired v2 cutover tooling

Moved here 2026-10-15 when Phase V.6 (`sql/048_v2_consolidate.sql`) moved `v2` into `public`
and dropped the schema. Each of these compared `v2` with the pre-cutover `public` tables, or
did a one-off job that is finished. They name schema `v2`, which no longer exists, and they
resolve paths relative to `scripts/`, so they won't run from here as they are. They are kept
because `database_review.md` and the `docs/phase_v*_plan.md` records cite them.

| File | Was for |
|---|---|
| `backfill_v2.sql`, `run_backfill.py` | V.4: copied `public` into `v2` |
| `reconcile_v2.py` | V.4: proved every row was loaded or quarantined |
| `apply_value_rules.py` | One-off fill of values already sitting NULL (migration 041) |
| `diff_v2_against_live.py` | V.1–V.3: v2 DDL compared with the live catalog |
| `audit_v2_dependents.py` | V.1–V.6: in-database dependents of the replaced tables; last run on V.6 morning |

The live successors are `bin/check_drift.py` (inventory), `scripts/check_v2_mappings.py`
(workbook headers against the importer's mappings) and the import's own quarantine report.
