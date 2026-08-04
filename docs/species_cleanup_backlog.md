# Species Cleanup Backlog

Status: Draft cleanup plan. Do not run update statements until mappings are reviewed.

## Known Issues

| Check | Count |
|---|---:|
| `sample.nominal_species_id` blank/null | 33 |
| `sample.nominal_species_id` not in `species` | 645 |
| `sample.nominal_species_id` not in `master_species` | 706 |
| `sample.assigned_species` not in `species` | 25 |
| `sample.assigned_species` not in `master_species` | 25 |

## Profiling Queries

```sql
-- Blank nominal species IDs.
SELECT og_id, nominal_species_id, assigned_species
FROM sample
WHERE nominal_species_id IS NULL OR btrim(nominal_species_id) = ''
ORDER BY og_id;

-- Nominal species IDs not present in canonical species table.
SELECT s.nominal_species_id, count(*) AS sample_count
FROM sample s
LEFT JOIN species sp ON sp.species = s.nominal_species_id
WHERE s.nominal_species_id IS NOT NULL
  AND btrim(s.nominal_species_id) <> ''
  AND sp.species IS NULL
GROUP BY s.nominal_species_id
ORDER BY sample_count DESC, s.nominal_species_id;

-- Assigned species values not present in canonical species table.
SELECT s.assigned_species, count(*) AS sample_count
FROM sample s
LEFT JOIN species sp ON sp.species = s.assigned_species
WHERE s.assigned_species IS NOT NULL
  AND btrim(s.assigned_species) <> ''
  AND sp.species IS NULL
GROUP BY s.assigned_species
ORDER BY sample_count DESC, s.assigned_species;
```

## Mapping Table Template

| Source field | Current value | Proposed canonical value | Action | Reviewer | Notes |
|---|---|---|---|---|---|
| `sample.nominal_species_id` | TBD | TBD | map/add species/leave blank/archive | TBD | TBD |
| `sample.assigned_species` | TBD | TBD | map/add species/leave blank/archive | TBD | TBD |

## Cleanup Rules To Decide

- Whether blanks mean unknown, not yet assigned, or invalid import.
- Whether misspellings should be updated in place or tracked through a mapping table.
- Whether missing species should be inserted into `species` or rejected from sample records.
- Whether `assigned_species` must always be canonical or can remain a free-text expert determination.

