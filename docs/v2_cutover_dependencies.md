# v2 Cutover Dependencies

Date: 2026-08-05
Revised: 2026-10-05 (Phase V.1 item 5 -- re-audited against the live catalog, not by reading
view definitions. See the "What the August audit missed" section.)
Purpose: record every object that reads the twelve lab workflow tables, and what each one needs
at cutover. Answers F10 of `docs/v2_scaffold_design_review.md`, which flagged that nothing
tracked this.

## The key simplification

Decision 3 makes cutover a `search_path` swap rather than a rename. Every view in
`schema/current_views.sql` references its tables **unqualified** (`FROM sample s`, not
`FROM public.sample s`), so a view recreated with `v2` ahead of `public` on the search path
resolves to the v2 tables with no edit at all.

That means a view only breaks if it references something the v2 design **removed or retyped**.
Auditing on that basis reduced eleven views to two that need rebuilding — **three as of
2026-10-05**, and the audit itself was too narrow; see the next section.

Note also what this simplification does *not* cover, which the August text left implicit: it
is about whether a view's **SQL** needs editing. It is not about whether the view needs
recreating. Every one of them does, because views bind to OIDs.

## What the August audit missed

Re-audited 2026-10-05 with `scripts/audit_v2_dependents.py`, which reads `pg_depend`,
`pg_rewrite`, `pg_trigger` and `pg_proc` rather than view text. Four corrections, each of
which would have caused a problem at cutover:

1. **The audit scope was twelve tables; `v2` recreates seventeen.** The five LCA/mitogenome
   tables are `v2` objects too (decision 1, §5 step 11), and ten non-snapshot views read the
   seventeen. `mitogenome_submission_view` was never audited at all and it **breaks**: it
   selects `m.og_num` directly from `mitogenome_data`, a column `v2` removes under F2. It has
   also been reworked three times since this document was written (`027`, `028`, `029`).

2. **`embargo_assignment_view` is a write path, not a reader.** It is listed below as
   cutover-neutral, reading seven `sample` columns. It also carries
   `trg_embargo_assignment_view_upd`, an `INSTEAD OF UPDATE` trigger that writes to `sample`.
   Two of the eleven views are writable, not one.

3. **Eleven of this database's own functions follow the swap silently.** None pins a
   `search_path`, the database- and role-level `search_path` are both unset, and the session
   default is `"$user", public`. Six are `build_*_samplesheet*` functions that generate
   Nextflow samplesheets from `sample` and `sequencing` -- and `sequencing` loses its five
   library tube-ID columns under F6. Dispositions (pin / follow / rewrite) are recorded in
   `docs/v2_scaffold_design_review.md` revision 2 and in the script itself. **The pinning
   `ALTER FUNCTION`s are Phase V.5 work, not V.1** -- V.1 changes no live object.

4. **`v2` was dropping two triggers on the floor.** `lca_set_content_hash` maintains
   `content_hash` on `lca` and `lca_raw_results` (migration `017`); `v2` had neither the
   column nor the trigger. Fixed -- `create_v2_lca_tables.sql` now creates
   `v2.lca_set_content_hash()` with a pinned `search_path`. `set_updated_at` on
   `rna_library_kinx` is deliberately not carried forward, because `v2` drops
   `created_at`/`updated_at`; that function must therefore be **pinned to `public`** so it
   cannot follow the swap into a table with no such column.

## Views that must be rebuilt

| View | What breaks | Fix |
|---|---|---|
| `summary` | Joins eight lab tables on their `og_id` columns (F1, removed); guards on `s.illumina_sequencing` / `hifi_sequencing` / `hic_sequencing` / `nanopore_sequencing` / `rna_extraction` / `rna_ilmn_sequencing` / `rna_kinnex_sequencing` (F4, removed); selects `s.summary_comments` (F4, removed); tests `status_overwrite::text = 'Y'` (F4a, now boolean) | Rebuilt as `v2.summary` in `create_v2_summary_view` |
| `goat_species_v1` | `samp.pb_status` (F5, removed — it was a Summary-sheet rollup) | Rebuilt as `v2.goat_species_v1`, reading the status from `v2.summary` |
| `mitogenome_submission_view` | Selects `m.og_num` from `mitogenome_data` (F2, removed). **Added 2026-10-05; the August audit never covered it.** | Rebuilt as `v2.mitogenome_submission_view` in `sql/043_v2_mitogenome_submission_view.sql` (applied 2026-10-13), taking `og_num` from `v2.sample`. Identical to the public view on live: 2,349 rows, 0 differing in either direction. |

## Views that are cutover-neutral

Audited column by column. Each reads only columns that survive into v2, so **no edit to the
view's SQL is needed** — but each one must still be **recreated** at cutover.

**Use `CREATE OR REPLACE VIEW`, not `DROP` + `CREATE`.** Corrected 2026-10-05. `CREATE OR
REPLACE` re-parses the definition and rebinds it to whatever the `search_path` resolves to
now, which is exactly what is wanted, while preserving grants to the `readonly` role, the
dependent views, and — decisively — the `INSTEAD OF UPDATE` triggers on
`lca_validation_report_view` and `embargo_assignment_view`, both of which a `DROP` destroys
silently. Its one restriction, that it cannot change a view's column names, types or order,
does not bite on views that are cutover-neutral by definition. `027` (line 29) and `033`
(line 71) already recorded this reasoning for the readonly role and the DBeaver users. Only
`summary`, `goat_species_v1` and `mitogenome_submission_view`, whose output columns change,
need `DROP` + `CREATE`.

> **Correction, 2026-10-05.** This section previously said a `search_path` swap was
> "sufficient and no DDL is needed". That is wrong, and it is the sentence someone would have
> acted on. **PostgreSQL views bind to table OIDs at creation time, not to names.** An
> existing view holds a dependency on the specific `public` table it was created over, so it
> ignores the `search_path` entirely and keeps reading `public` — and it also survives a
> rename of that table, silently following the OID. Left alone, all nine of these would keep
> serving pre-cutover data under their own unchanged names while direct queries moved to
> `v2`: Finding 11 repeated, by construction. Recreating them is what makes the swap apply.
> See Phase V.5 in `database_review.md`.
>
> **`sql/033_catchup_core_views.sql` line ~24 still carries the uncorrected sentence** ("a
> search_path swap is sufficient and no DDL is needed"). It is deliberately left there.
> `033` is applied and ledgered, and `docs/database_change_checklist.md` is explicit: never
> edit an applied file, because `bin/apply_migrations.py` refuses to continue when a
> SHA-256 stops matching. A comment is not worth breaking the ledger for. This document is
> the correction of record; anyone reading `033`'s header should land here.

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

## Functions — the six samplesheet builders (reviewed 2026-10-13)

`scripts/audit_v2_dependents.py` flagged six `build_*` functions for review. The finding
that matters most is not about columns: **these functions are owned by the scripts that call
them, not by the database.** `create_samplesheet_hifi_hic.py`, `create_samplesheet_hifi_only.py`
and `create_samplesheet_from_config.py` in `OceanOmics-OceanGenomes-ref-genomes` each run
`DROP FUNCTION IF EXISTS build_nfcore_samplesheet_rows(text[])` and then `CREATE` their own
body, unqualified, every time they run. The live body matches none of the three: it carries
`/scratch/pawsey0964/lhuet/genomenotes/` paths and filters on `seq_type`, so it came from a
fourth script that is not on this host. The `hicpost` and `postcuration` builders carry
`lhuet/post_curation/` paths and are in the same position. A migration that rewrote any of
them would be overwritten on the next pipeline run, so **the fix belongs in the calling
scripts**.

| Function | Verdict | Why |
|---|---|---|
| `build_final_data_compile` | follows unchanged | `sample` and `lca_validation` columns all survive; `ref_genomes` stays in `public` |
| `build_postcuration_samplesheet_rows` | follows unchanged | reads only `ref_genomes` and `raw_qc`, neither replaced |
| `build_rna_kinx_samplesheet_rows` | follows unchanged | every `rna_library_kinx` column survives |
| `build_nfcore_samplesheet_rows` | **breaks** | `sequencing.og_id` is gone (F1) |
| `build_hicpost_samplesheet_rows` | **breaks** | `sequencing.og_id` is gone (F1) |
| `build_rna_kinx_samplesheet_from_run` | **breaks** | `sequencing.rna_library_tube_id` is gone (F6) |

After the swap, the three that break fail loudly at `CREATE` time, because a SQL function
body is checked against the tables it names. That is the failure mode V.5 wants, but it
lands on a pipeline run, so the scripts should be changed on cutover day, not discovered.

**The fixes, each a one-line change in the calling script.** Unqualified names, so the same
text works after V.5 (resolved through the `search_path`) and after V.6 (everything in
`public`). They do not work before V.5, because `v_sequencing_browse` is not on the
`search_path` until then.

- `nfcore` and `hicpost`, in the `latest_seq` CTE: `FROM sequencing seq` becomes
  `FROM v_sequencing_browse seq`. Nothing else changes; the view exposes `og_id`,
  `technology`, `seq_type` and `seq_date`.
- `rna_kinx_from_run`: every `rna_library_tube_id` on `sequencing` becomes
  `library_tube_id` (the `tubes` CTE, the join, and the `samples_in_pool` output). The
  `rna_library_kinx` side keeps its `rna_library_tube_id`.

**Checked against live 2026-10-13**, comparing the current CTE on `public` with the rewrite on
`v2`:

| Variant | Samples, old / new | Differences |
|---|---|---|
| `technology IN ('PacBio HIFI', 'PacBio')` (hifi_hic, hifi_only) | 260 / 260 | 0 |
| `technology = 'PacBio'` (from_config, live hicpost) | 31 / 31 | 0 |
| `seq_type = 'PacBio'` (live nfcore) | 260 / 260 | 0 |
| `rna_kinx_from_run`, every run | 137 / 137 rows | 1 — `OG108G_R_KL`, where `public` holds blanks and `v2` holds the 2026-10-06 workbook's plate, pool and barcode. A freshness difference between the schemas, not the rewrite. |

**Two existing inconsistencies to raise with the pipeline owner, and not fix here:**

- **The scripts disagree on what counts as PacBio.** `from_config` and the live `hicpost`
  filter `technology = 'PacBio'`, which matches 35 rows and misses the 308
  `'PacBio HIFI'` rows. `hifi_hic` and `hifi_only` use `IN ('PacBio HIFI', 'PacBio')`, and
  the live `nfcore` uses `seq_type = 'PacBio'`, which picks up one Kinnex row as well. For
  31 samples against 260, the `date` column of a `from_config` or `hicpost` samplesheet can
  come from a different run than the `nfcore` one.
- **`seq.seq_date::date` raises on a malformed date**, aborting the whole samplesheet rather
  than skipping the row. No PacBio row is malformed today: the 41 non-`YYMMDD` values are
  39 `cDNA` rows with no technology and 2 Illumina `CSIRO` rows, all outside every filter
  above. It is a latent failure, worth a `seq_date ~ '^[0-9]{6}$'` guard when the scripts are
  next touched.

Unknown and needing an answer from the team before cutover:

- DBeaver saved queries and any hardcoded `public.` prefixes.
- Nextflow / Snakemake pipelines reading the database directly.
- Any R or Python analysis scripts outside these two repos.
- Grafana / reporting tools, if any.

Suggested way to close it: a fortnight of statement logging on the live database, then an
inventory of the distinct client applications actually connecting. That is evidence rather
than recollection, and it is the only method that finds consumers nobody remembers.

> **Correction, 2026-10-05.** This previously suggested `log_statement = 'mod'` or
> `pg_stat_statements`. **`'mod'` is the wrong setting** — it logs DDL and data-modifying
> statements only, and the consumers at risk here are overwhelmingly *readers*. It would have
> run for a fortnight and reported nothing while missing the entire problem. The corrected
> procedure — `log_statement = 'all'` with an attributing `log_line_prefix`, reload-only, in
> five steps with exit criteria — is under open question 7 in `database_review.md`, and is
> Phase V.0. The result belongs in this section when it lands.
