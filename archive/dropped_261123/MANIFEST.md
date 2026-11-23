# raw_data and the ena_specimen_accessions table

Both removed from live by migration `089` on owner decision 2026-11-23 (`database_review.md`
§11 Q13 and Q14). `raw_data` was dropped. `ena_specimen_accessions` was replaced by a view over
`sample` with the same name and columns. See the header of
`sql/089_drop_raw_data_specimen_view.sql` for the evidence.

Exported **2026-11-23 01:52 UTC** from `oceanomics_genomes` on `146.118.120.134`, read-only.

| File | Rows | Notes |
|---|---:|---|
| `raw_data.csv.gz` | 8,010 | all 5 columns, including the generated `og_num`; ordered by `run_id, lane_id, filename` |
| `ena_specimen_accessions.csv.gz` | 2,848 | all 6 columns; ordered by `og_id`. 1 row has an accession (OG111 `SAMEA132129018`, which disagrees with `sample.ncbi_biosample_id`) |
| `schema.sql` | — | `pg_dump --schema-only` of both tables: columns, keys, checks, FKs, comments, grants |
| `SHA256SUMS` | — | checksums of the three files above |

Row fingerprints, as checked by `089`'s guard and its revert:
`md5(string_agg(to_jsonb(t)::text, E'\n' ORDER BY <order above>))`

- `raw_data`: `5cee43e79ea3960a70eb7de0e7043cae`
- `ena_specimen_accessions`: `bb17327c6b962bf76dd898aa5777d2b0`

The revert (`sql/revert/089_drop_raw_data_specimen_view_revert.sql`, run from the repository
root) reloads both tables from these CSVs and checks the fingerprints. Revert `090` first.
