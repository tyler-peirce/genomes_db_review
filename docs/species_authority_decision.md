# Species Authority Decision

Status: Draft decision record.

## Decision Needed

Choose the canonical species/taxonomy source for the database.

## Recommendation

Use `species` as the canonical table and treat `master_species` as either:

- a curated subset view for GoaT-facing output, or
- a deprecated legacy table after dependent views are migrated.

## Evidence From Review

| Check | Result |
|---|---:|
| Rows in `species` | 22,650 |
| Rows in `master_species` | 19,817 |
| Rows in both tables | 19,817 |
| Rows in `species` but not `master_species` | 2,833 |
| Rows in `master_species` but not `species` | 0 |

`species` is the superset and is already referenced by `species_ncbi_assembly`. `goat_species_v1` currently reads from `master_species`, which means GoaT output may omit species present only in `species`.

## Proposed Target State

- `species` is the authoritative taxonomy table.
- `master_species` becomes a documented curated subset view or is retired after compatibility checks.
- `sample.nominal_species_id` and `sample.assigned_species` are cleaned against `species`.
- GoaT views are regression-tested before changing their source table.

## Required Signoff

| Area | Owner | Signoff |
|---|---|---|
| Taxonomy/species data | TBD | Pending |
| Sample intake | TBD | Pending |
| GoaT API/reporting | TBD | Pending |
| Database owner | TBD | Pending |

## Follow-Up Work

- Confirm whether all `master_species`-only semantics can be represented as columns or filters on `species`.
- Compare representative `goat_species_v1` output before and after a proposed source change.
- Decide whether the 2,833 `species`-only rows should be GoaT-visible.

