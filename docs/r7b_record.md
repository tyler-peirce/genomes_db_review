# R.7b record: the LCA tables stored by `annotation_id` (`076`), 2026-11-02

Plan: [`r7b_plan.md`](r7b_plan.md). Follows R.7 ([`r7_record.md`](r7_record.md)).

**Owner decisions (2026-11-02):**
- base tables plus compatibility views;
- names `mito_lca`, `mito_lca_raw`, `mito_lca_validation`, `mito_blast_hit`;
- run the same day as R.7.

## What changed on live

| Base table (PK) | Was | Old name now |
|---|---|---|
| `mito_lca` `(annotation_id, region, content_hash)` | `lca` | read-only view |
| `mito_lca_raw` `(annotation_id, sequence_region, accession_id, content_hash)` | `lca_raw_results` | read-only view |
| `mito_lca_validation` `(annotation_id)` | `lca_validation` | read-only view |
| `mito_blast_hit` `(annotation_id, match_sequence_id, region)` | `blast_filtered_lca` | read-only view |

- **Base tables:** dropped the five natural columns, the FK to `sample`, `074`'s `*_annotation_id` triggers and the natural-key indexes. They keep the `annotation_id` FK to `mito_annotation` and its index. Constraint, index and trigger names were renamed to the `mito_*` prefix.
- **Compatibility views:** each shows the old column list in the old order, joined through `mito_annotation` ⋈ `mito_assembly`, with the old grants (`readonly`; `oceangenom_web` on `lca_validation`).
- **The ten dependent views** were recreated from their own definitions, unchanged in text: `summary`, `sample_view`, `lca_validation_report_view` (plus its `033` INSTEAD OF trigger), `filtered_lca_view`, `lca_pivot_view`, `lca_results_view`, `embargo_assignment_view`, `mitogenome_submission_view`, `goat_species_v1` and `pre_v4_archive.goat_species_v1`.
- **`content_hash`:** recomputed by the trigger on `mito_lca` and `mito_lca_raw`. The old→new maps are kept in `pre_v3_archive.lca_hash_map_076` and `lca_raw_results_hash_map_076`.
- **New function `mito_annotation_id(og_id, tech, seq_date, code, annotation [, strict])`:** the writers' key lookup. Strict mode raises the same message as `074`'s trigger.
- **`lca_validation_report_view_upd()`** now updates `mito_lca_validation` by `annotation_id`.

## Writers

Mito pipeline `inverts-dev` `6494002` → `d21531e` (branch `r7b-lca-base-tables`, merged and deleted).
- `push_lca_blast_results.py`, `push_lca_raw_results.py`, `push_species_validation.py` and `push_qc_validator.py` write the base tables, keyed via `mito_annotation_id()`. Their reads stay on the views.
- The two SQL-text unit tests were updated. The suite has the same 5 failures as `inverts-dev` (Biopython missing on this host).
- Docs commit `8665897`. The Setonix production clone is pulled.
- No other repo changed. ENA-draft steps 00/06, ENA-ref step 00 and OceanGenom_Web read the views.

## Rehearsal (PG14 restore of live, post-075)

| Check | Result |
|---|---|
| Without the opt-in | Refused |
| Apply | 2 min 20 s; built-in verify passed: base rows and content equal; each compatibility view reproduces its old table exactly (rows, columns, types); ten views same row counts and column lists; compatibility views refuse inserts |
| Full output against an unmigrated restore | Identical, sorted row for row: `summary` (3,409), `sample_view`, `lca_validation_report_view`, `filtered_lca_view`, `lca_pivot_view`, `lca_results_view`, `embargo_assignment_view` (2,605, by COPY), `mitogenome_submission_view`, `goat_species_v1` and the four compatibility views. Timings unchanged (`summary` 1.15 s → 1.22 s) |
| New writers on OG3150 260925, twice | No row added on either pass; prune paths ran; species validation written and visible through the view; QC validator fill and preserve paths both work |
| Unknown annotation | Refused per row with the lookup's message |
| Old writers (`inverts-dev` `6494002`) | Fail: "cannot insert into view" |
| Revert | Schema identical (after resetting `lca_validation`'s ACL order, which a default privilege had changed). Data, `content_hash` included, identical to before. Re-apply identical; replay a no-op |

**Pre-existing, not caused by 076:** `SELECT * … ::text` over `embargo_assignment_view` raises "invalid input syntax for type integer" on both copies. COPY and `count(*)` work.

## Live

- **Go/no-go:** no active LCA writes. A fresh dump `~/oceanomics_genomes_pre_076_261102b.dump`.
- **Applied:** 09:10:27–09:12:36 UTC; the ledger has 77 rows and verifies.
- **Writers deployed:** at 09:13:02, 26 s later. The one release-test upload in that gap (OG3088 `lca_raw`, 09:12:38) had no rows to write, so nothing was lost.
- **Post-checks:**
  - the four old names are views and the four `mito_*` are tables;
  - every `public` and `pre_v4_archive` view selects;
  - the web grant on `lca_validation` is kept;
  - ENA-draft step 00: 1,697 rows.
- **Baseline:** `076`'s hunks (commit `85e0c38`), plus two index lines R.6 had left stale (`mitogenome_data_og_id_idx` removed, `mito_assembly_run_sequencing_id_idx` added). `object_inventory.tsv` lists the four `mito_*` tables and the four old names as views. Drift shows only the colleague's three objects.

## The days after (checked 2026-11-04)

- **2026-11-03 import:**
  - `sequencing` 4,467 loaded (+12), 16 rejected; no failure flag;
  - a new run appeared and the `075` triggers created it: 213 runs in `sequencing`, 213 in `sequencing_run`, none missing;
  - the first production run of the upkeep.
- **Base tables** grew with the release test's uploads (`mito_blast_hit` 249,464 rows): the new writers work in production.
- **All 10 FKs** to `mito_annotation` / `sequencing_run` are validated; the ledger verifies.

## Next

- **R.8:** after a quiet period, drop `pre_v3_archive` (the old flat tables, the orphan copies and the two `076` hash maps) and the empty `ena_*_archive` tables. Object comments; `docs/data_dictionary.md`; `database_review.md` §7, §9, §13.
- **Mito upload modules:** still exit 0 when a script reports a database error (R.6 record), so a refused row shows only in `*.upload.txt`.
