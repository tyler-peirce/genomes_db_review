# v2 Cutover Dependencies

Date: 2026-08-05
Purpose: record every object that reads the twelve lab workflow tables, and what each one needs
at cutover. Answers F10 of `docs/v2_scaffold_design_review.md`, which flagged that nothing
tracked this.

## The key simplification

Decision 3 makes cutover a `search_path` swap rather than a rename. Every view in
`schema/current_views.sql` references its tables **unqualified** (`FROM sample s`, not
`FROM public.sample s`), so a view recreated with `v2` ahead of `public` on the search path
resolves to the v2 tables with no edit at all.

That means a view only breaks if it references something the v2 design **removed or retyped**.
Auditing on that basis reduces eleven views to two that need rebuilding.

## Views that must be rebuilt

| View | What breaks | Fix |
|---|---|---|
| `summary` | Joins eight lab tables on their `og_id` columns (F1, removed); guards on `s.illumina_sequencing` / `hifi_sequencing` / `hic_sequencing` / `nanopore_sequencing` / `rna_extraction` / `rna_ilmn_sequencing` / `rna_kinnex_sequencing` (F4, removed); selects `s.summary_comments` (F4, removed); tests `status_overwrite::text = 'Y'` (F4a, now boolean) | Rebuilt as `v2.summary` in `create_v2_summary_view` |
| `goat_species_v1` | `samp.pb_status` (F5, removed — it was a Summary-sheet rollup) | Rebuilt as `v2.goat_species_v1`, reading the status from `v2.summary` |

## Views that are cutover-neutral

Audited column by column. Each reads only columns that survive into v2, so a `search_path`
swap is sufficient and no DDL is needed.

| View | Lab tables read | Columns used, all surviving |
|---|---|---|
| `sample_view` | `sample` | `og_id`, `project_id`, `nominal_species_id`, `photo_id`, `photo_voucher`, `specimen_voucher`, `voucher_id` |
| `embargo_assignment_view` | `sample` | `og_id`, `collector`, `embargo_status`, `nominal_species_id`, `common_name`, `field_id`, `contact`, `date_collected` |
| `lca_results_view` | `sample` | `nominal_species_id` |
| `v_genome_size_comparison` | `sample` | `og_id`, `nominal_species_id` |
| `lca_validation_report_view` | via `sample_view` | — |
| `filtered_lca_view` | via `lca_results_view` | — |
| `coverage_summary` | none | reads `hifi_reads_qc`, `hic_reads_qc`, `raw_qc` only |
| `lca_pivot_view` | none | reads `lca` only |
| `goat_project_metadata_v1` | none | constants only |

Two of these recompute `og_num` themselves with
`regexp_replace(og_id, 'OG', '', 'g')::integer` rather than reading the column. That keeps
working, but note it shares the live `og_num`'s failure mode: it raises on an `og_id` with no
digits. `v2.sample.og_num` is null-safe (F2), so they should be switched to read the column
during cutover. Neither is urgent enough to block.

## Tables outside the twelve that reference them

From F11. These carry `og_id` or a tube ID but were not part of the lab-table redesign:

`rna_qc_kinnex`, `raw_data`, `raw_qc`, `hifi_reads_qc`, `hic_reads_qc`, `draft_genomes`,
`ref_genomes`, `mitogenome_data`, `lca`, `lca_validation`, `lca_raw_results`,
`blast_filtered_lca`.

They join on `og_id`, which `v2.sample` still has as its primary key, so they are
cutover-neutral in the same way. The LCA and mitogenome group additionally gets v2 equivalents
in `create_v2_lca_tables` (decision 1, §5 step 11); the rest are a later change.

## Consumers outside this repo — still open

Open question 10 of `database_review.md` is **not closed by this document** and remains the one
genuine cutover blocker.

Known from the sibling repo:

- `OceanOmics-Database/import_data.py`, `queries.py`, `name_convert.py` — the nightly import.
  `queries.py` writes **unqualified table names**, so it follows the `search_path` and will
  land in `v2` once the role's `search_path` is changed. That is convenient and dangerous in
  equal measure: it means the cutover moves the importer silently, so the importer changes of
  §5 step 10 must land *before* the swap, not after.

Unknown and needing an answer from the team before cutover:

- DBeaver saved queries and any hardcoded `public.` prefixes.
- Nextflow / Snakemake pipelines reading the database directly.
- Any R or Python analysis scripts outside these two repos.
- Grafana / reporting tools, if any.

Suggested way to close it: enable `log_statement = 'mod'` or query `pg_stat_statements` on the
live database for a fortnight and inventory the distinct client applications actually
connecting. That is evidence rather than recollection, and it is the only method that finds
consumers nobody remembers.
