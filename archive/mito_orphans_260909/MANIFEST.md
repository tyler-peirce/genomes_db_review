# Orphaned and `_rgj` mitogenome child rows

The 532 rows removed by migration `050` on owner decisions 2026-10-16:
- LCA rows for three annotations replaced in place by a later annotation (OG2628, OG3050 and
  OG3060 `ilmn.260909.getorg1770.mitos2110`);
- ENA validation attempts for two wiped annotations (OG2951 and OG3000), for three `_rgj`
  assemblies that no longer exist (OG2936, OG2982 and OG3038), and for OG562's `_rgj` assembly,
  which still exists. The `_rgj` step is retired.

See the header of `sql/050_clear_orphan_mito_children.sql` and
`docs/assembly_relations_plan.md` §3.6.

Exported **2026-10-16** from `oceanomics_genomes` on `146.118.120.134`, read-only.

| File | Rows | md5 fingerprint (as checked by `050` and its revert) |
|---|---:|---|
| `lca_validation.csv` | 1 | `24a8eb61a07a022b1f31197c4a3d98db` |
| `lca.csv` | 8 | `0ca64eefbb3f2e985d3c768f421cf9c0` |
| `lca_raw_results.csv` | 74 | `4b5a7b787106e9faacfe94f1331764d1` |
| `blast_filtered_lca.csv` | 443 | `fc306a49206bdbbfa9dd81afe356b267` |
| `ena_validation_attempts.csv` | 6 | `7569ae8b5b48a937b5a45857f2d5a318` |
| `SHA256SUMS` | — | checksums of the CSVs |

Fingerprint: `md5(string_agg(to_jsonb(t)::text, E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"))` over the
keyed rows of each table. All columns are included, generated `og_num` too.

`050` also copies the rows to `pre_v3_archive.<table>_orphans_260909`, and the revert
(`sql/revert/050_clear_orphan_mito_children_revert.sql`) restores from there. These CSVs are the
copy to read, and the copy of last resort.

The sort is `COLLATE "C"` so the fingerprint does not depend on the database's collation (live
is `en_AU.UTF-8`). The CSVs themselves are ordered by the database default collation.
