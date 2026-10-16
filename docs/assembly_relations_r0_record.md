# Phase R, R.0 record: measurements and checks before `050`–`054`

Run 2026-10-16 against live `oceanomics_genomes` (146.118.120.134) in read-only sessions
(`default_transaction_read_only=on`). Runbook:
[`assembly_relations_runbook_r0_r5.md`](assembly_relations_runbook_r0_r5.md) R.0.

## R.0.1 Figures the migrations assert

All unchanged from the plan's 2026-10-16 figures.

| Figure | Live | Used by |
|---|---:|---|
| Orphans: `lca_validation` / `lca` / `lca_raw_results` / `blast_filtered_lca` / `ena_validation_attempts` / `ena_submissions` | 1 / 8 / 74 / 443 / 5 / 0 | `050` |
| `_rgj` ENA attempts (ids 4285, 4280, 4281 orphaned; 2801 = OG562, assembly exists) | 4 | `050` |
| `_rgj` rows that stay: assemblies / `lca_validation` / `lca` / `lca_raw_results` / `blast_filtered_lca` | 35 / 25 / 58 / 366 / 715 | `050` |
| Child table totals before `050`: same order as the orphans row | 1,908 / 4,951 / 46,914 / 243,695 / 1,188 / 539 | `050` |
| `mitogenome_data` rows / annotated | 2,371 / 1,997 | `051` |
| `depth_method`: `remap_full_v1` / `not_measured` / NULL | 1,954 / 412 / 5 | `051` |
| `tech`: `ilmn` / `hic` / `hifi` | 1,725 / 373 / 273 | `051` |
| `draft_genomes` rows | 1,720 | `052` |

**Draft → run** (`draft_genome_run`, `052`): Illumina, with instrument matching `mach`
(`NOVA` → `NovaSeq`, `NEXT` → `NextSeq`; live has only these two `mach` values, 1,691 / 29).
1,715 drafts get one run and 5 get two (the pooled 230814 libraries). None gets zero.

**Mitogenome assembly → run** (`mito_assembly_run`, `051`). `mitogenome_data` has no `mach`, so
the rule is by `tech`:

| `tech` | Matches `sequencing` rows on the same `(og_id, seq_date)` where | 0 runs | 1 | 2+ |
|---|---|---:|---:|---:|
| `ilmn` | `technology = 'Illumina'` and `instrument <> 'iSEQ'` | 0 | 1,720 | 5 |
| `hic` | `technology = 'Hi-C'` | 8 | 349 | 16 |
| `hifi` | `technology LIKE 'PacBio%'` | 1 | 259 | 13 |

- iSeq is excluded because 44 `ilmn` assemblies otherwise match an iSeq QC run as well as the
  NovaSeq run the reads came from. This is the same pattern as the drafts in plan §2.2. No `ilmn`
  assembly matches only an iSeq run.
- Several Hi-C and HiFi runs per assembly are real (lanes, cells), so all of them are linked.
- The 9 with no match get no `mito_assembly_run` row (the table is 0..n).

**BUSCO vs gfastats N50:** unchanged. 681 drafts have both; all 524 far-apart rows fit the L50
bounds.

## R.0.2 `ENA-draft-genomes`: not found

- Column comments name it: `ena_analysis_accession` is written by "ENA-draft-genomes step 06",
  and `assembly_accession` by "ENA-draft-genomes workflow/07_resolve_gca_accessions.py".
- **Not found anywhere reachable.** It is not on this host (a filesystem search for
  `07_resolve_gca_accessions.py` found nothing). It is not among the public repositories of
  `Minderoo-OceanOmics-Centre-UWA`; `OceanOmics-ENAUploads` is eDNA submissions and does not
  mention `draft_genomes`. It may be private or on Pawsey, and Pawsey was unreachable all day
  (ssh timeout).
- **Consequence:** this blocks nothing up to R.5, because `052` builds only in `v3` and
  `public.draft_genomes` is untouched. **It is a gate for R.6:** before the merge, someone with
  access must confirm what it writes and that it reads none of the 17 dropped columns (plan
  §4.3).

## R.0.3 Readers of `mitogenome_data`

**Views in `public`** (from `pg_depend`, recursively): only `mitogenome_submission_view`.
**For `draft_genomes`:** only `v_genome_size_comparison`. `summary` reads neither.

**Mitogenome pipeline** (`Oceanomics-OceanGenomes-Mitogenomes`, `inverts-dev`, `9d70d01`):

| Reader | What it reads | Assumes one row per assembly? | Fix in R.5 |
|---|---|---|---|
| `bin/audit_ena_readiness.py` | `DISTINCT og_id`; a diagnostic `count(*)` of rows and of depth rows; a per-`og_id` candidate listing | The two counts would count annotations, not assemblies | Count `DISTINCT (og_id, tech, seq_date, code)` |
| `bin/backfill_ena_specimen_accessions.py` | `DISTINCT og_id` | no | none |
| `bin/build_source_modifiers.py` | `sample` joined to `mitogenome_data`, `GROUP BY` sample columns | no (grouped) | none |
| `bin/prepare_ena_metadata.py` | `mean_depth` by the four assembly columns, `fetchone()` | Would get one of several rows, but depth is per assembly, so every row carries the same value | none needed; optionally add `LIMIT 1` for clarity |
| `bin/compile_upload_report.py` | the push scripts' log text, e.g. "Success: Overwrote mitogenome_data" | n/a | **The new writers must keep these status strings,** or this classifier is updated alongside |
| `bin/compile_held_completeness.py`, `bin/depth_tsv.py`, `bin/mitogenome_assembly_summary.py`, the `.nf` files | comments only; no query | no | none |
| `bin/qc/99_genbank_submitter.py` | retired | — | — |

So no reader needs `is_selected`. The only code change is the counts in
`audit_ena_readiness.py`.

## R.0.4 BUSCO JSONs: blocked

The HPC (`setonix-08.pawsey.org.au`) refused every connection on 2026-10-16. Until someone opens
OG2649 260909 and OG2033 251215's short-summary JSON, **`BUSCO_KEYMAP` is not changed in R.5.**
The stored columns carry over unchanged, with a comment saying they are unreliable, exactly as
planned. The parser fix waits.

## R.0.5 Triage

| Item | Finding | Disposition |
|---|---|---|
| `raw_data` "30 blank `og_id`" | They are **NULL**, not empty strings. Every non-NULL `og_id` is in `sample`. | An FK allows NULL, so `raw_data → sample` goes in `054` now. Leave the 30 NULLs for the lab. |
| 7 `hifi_reads_qc` rows | All on `PACB_250717_AD`, which is in no `sequencing` row; nothing on 250717 at all | Lab: the run is missing from the workbook. Blocks only R.7's FK. |
| 22 `hic_reads_qc` rows | `NOVA_240719_AD` (10, nothing on that date) and `NOVA_250114_AD` (12; `sequencing` has only `PACB_250114_AD` that day) | Lab: Hi-C runs missing from the workbook. Blocks only R.7's FK. |
