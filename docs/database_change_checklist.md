# Database Change Checklist

Use this checklist before changing the Ocean Genomes database schema, data-cleanup rules, views, or API-facing outputs.

## Before Work Starts

- Confirm the table or view owner.
- Confirm whether the affected object is active, planned, deprecated, archive, or staging.
- Regenerate the schema baseline if the live database may have changed.
- Identify downstream consumers, including GoaT API views and direct database users.
- Capture current row counts and relevant data-quality checks.

## For Cleanup Work

- Save proposed mappings before running updates.
- Separate obvious typo fixes from ambiguous scientific or workflow decisions.
- Preserve historical identifiers until their meaning is classified.
- Record before/after counts.

## For Indexes

- Capture the query or view the index supports.
- Save before/after `EXPLAIN` output for important queries.
- Check for redundant existing indexes.
- Use production-safe index creation strategy for large tables.

## For Constraints

- Run orphan/null/duplicate checks first.
- Use staged validation where possible.
- Confirm import and update paths will satisfy the new constraint.
- Document rejected rows or cleanup exceptions.

## For Views and API Outputs

- Save representative output before refactoring.
- Keep column names and semantics stable unless a versioned contract change is approved.
- Add smoke tests for API-backed views.
- Compare row counts and selected known examples after changes.


## Migration Governance

The one-page rule. Decided 2026-10-05 — see `docs/migration_system_decision.md` for why.

- **There is one migration system.** Numbered SQL files in `sql/`, recorded in the
  `schema_migrations` table. Sqitch is retired; `migrations/` is historical only.
- **No DDL reaches this database any other way.** Not from a psql session, not from DBeaver,
  not from a pipeline script. 22 tables and 6 views arrived that way before this rule existed
  and cost months of catch-up work.
- **Apply with the script, never by hand:** `bin/apply_migrations.py`. It runs the file and
  writes its ledger row in one invocation, so the two cannot come apart. Applying by hand is
  how `026` ended up applied-but-unledgered.
- **Never edit an applied file.** Its SHA-256 is in the ledger and the apply script refuses to
  continue when a hash stops matching. To correct an applied migration, supersede it with a new
  numbered file — `028` → `029` is the worked example.
- **Every migration carries a prose header** saying why the change was made, what was rejected,
  and what must not be done later. These headers are the project's design record; the schema
  cannot reconstruct them.
- **Migrations are idempotent**, guarded with `to_regclass()` so they replay safely against a
  partial schema.
- **Commit `schema/object_inventory.tsv` in the same change as the migration that explains it.**
  A baseline update with no migration beside it is drift being rubber-stamped.
- **Drift is checked daily** by `bin/drift_cron.sh` (`bin/check_drift.py` plus
  `bin/apply_migrations.py --verify`). If it reports an object in NEITHER `sql/` nor the
  baseline, someone has just applied DDL outside this process — find out who before accepting
  it into the baseline.
