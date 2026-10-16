# Hi-C draft genome archive

The 15 `draft_genomes` rows with `seq_date` 251118, removed by migration `049` on owner
decision 2026-10-16. They are draft assemblies built from run `NEXT_251118_AD`, which holds only
shallow Hi-C libraries, so they are not draft genomes. See the header of
`sql/049_remove_hic_draft_genomes.sql` and `docs/assembly_relations_plan.md` §2.2.

Exported **2026-10-16** from `oceanomics_genomes` on `146.118.120.134`.

| File | Rows | Notes |
|---|---:|---|
| `draft_genomes_hic_251118.csv` | 15 | all 120 columns, including generated `og_num` |
| `SHA256SUMS` | — | checksum of the CSV |

Row fingerprint, as checked by `049` and its revert:
`md5(string_agg(to_jsonb(d)::text, E'\n' ORDER BY og_id))` = `ee48835d1d3e2282dd4ed107be07b2a2`.

The revert (`sql/revert/049_remove_hic_draft_genomes_revert.sql`) re-inserts these rows exactly
and does not need this CSV; the CSV is here to be read.
