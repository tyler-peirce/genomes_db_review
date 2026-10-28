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
- **Name views by what they are** (decided 2026-10-22):
  - **A new view gets a `v_` prefix**: `v_sequencing_browse`, `v_read_set_run_readiness`. A
    readiness or issue list ends in `_readiness` or `_issues`.
  - **A compatibility view keeps the exact name of the table it stands in for** (`v3.draft_genomes`,
    `v4.raw_qc`), so existing queries keep working when it replaces that table. No prefix.
  - **An external contract keeps its versioned name** (`goat_species_v1`). A breaking change is a
    new version (`_v2`) beside the old one, never a rename.
  - **Window-only sync helpers start `sync_`** and are dropped when their window closes.
  - **Older views keep their names** (`summary`, `sample_view`, `lca_results_view`, ...).
    Readers depend on them; renaming one is a contract change, not a tidy-up.

## For Pipeline Writer and Reader Audits

Added 2026-10-28 (`database_review.md` Finding 17.6). Pipeline commits are often made on Pawsey
and pushed to GitHub, and this host's clones do not see them until someone fetches. Owner
decision 14 dropped two columns because the upload scripts "never push" them. That was read from
a draft clone 12 days behind `origin/master`, and the writer had been added in between.

- **Fetch every clone before reading it:** `git fetch` in each pipeline repository. That means
  the draft, mito and ref-genomes pipelines, post-curation, every `ENA-*` repository, and
  `OceanOmics-Database`.
- **Read the remote default branch, not the local checkout:** `origin/master` or
  `origin/inverts-dev`, as the repository uses. Read it with
  `git show origin/<branch>:<path>` or `git grep <pattern> origin/<branch>`.
- **Record the commit SHA that was read** in the audit record, beside each writer or reader. A
  claim that code does or does not do something holds only for that commit.
- **Cut writer branches from the fetched remote default branch.** Before each rehearsal, bring
  the branch up to date with that remote and rerun its tests. Check with
  `git rev-list --left-right --count <branch>...origin/<default>`: the right-hand number must
  be 0.
- **Before dropping a column as "unread" or "unwritten", search every repository at its remote
  default branch.** Do the same for anything readable on Pawsey. Say in the record which places
  could not be read.


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
