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

