# R.6 gate, B.0–B.1: mito branch and migration `068` (2026-10-28)

Plan: [`r6_gate_plan.md`](r6_gate_plan.md) Part B.

## B.0

**The production branch is `inverts-dev`.** The Setonix clone the pipeline runs from (`/software/projects/pawsey1348/tpeirce/repos/Oceanomics-OceanGenomes-Mitogenomes-inverts`) is on a local branch, `invert-generalization`. That branch tracks `origin/inverts-dev` and sits at the same commit, `acf878c`.

**`phase-r-v3` is brought up to date.** It merged `origin/inverts-dev` (10 commits, none touching an upload script or `sql/`), giving `d0a12ca`. It was **pushed to GitHub for the first time**.

**Unit tests:** 970 ran, with the same 5 failures as plain `origin/inverts-dev`. Biopython is not installed on this host, so the merge introduced none of them.

## B.1 migration `068`

Files:
- `sql/068_mito_completeness_and_assembly_qc.sql`
- `sql/revert/068_mito_completeness_and_assembly_qc_revert.sql`

What it does:
- **`public.mitogenome_data`** gains `completeness_profile` (`vertebrate`/`core`) and the assembly QC verdict: `qc_status` (complete / manual_review / failed / superseded), `manual_review_reason`, `numt_flag`, `frameshift_flag`, `reference_species`, `reference_accession`, `qc_updated_at`. Both value sets are checked.
- **In `v3`:** `mito_annotation.completeness_profile`, and a new `v3.mito_assembly_qc` with one row per assembly.
- **Functions and view:** `sync_mito()` and `check_mito()` are rebuilt from `055` and `056`, which equal live, with the new columns added. `v3.mitogenome_data` goes from 104 to 112 columns.

**Rehearsal** on a restore of a pre-068 dump of live (`~/oceanomics_genomes_pre_068_261028.dump`):

| Check | Result |
|---|---|
| Apply | Ledger 69. Every `check_mito` 0. View has 112 columns |
| Nightly `scripts/sync_v3.sql` | `sync_v3 ok` |
| Simulated writers on OG3078 (profile on the annotation; verdict on both assemblies), then `sync_mito()` | `assembly qc upserted 2`, `annotation upserted 1`; shown in the view; checks 0 |
| Clear one assembly's verdict, then sync | `assembly qc deleted 1` |
| Bad `qc_status` / `completeness_profile` | Refused |
| Revert, then `pg_dump -s` against before | Identical, apart from the `\restrict` token |
| Re-apply; replay with the ledger row deleted | Clean; sync changed 0 rows; `v3.mitogenome_data` md5 identical; `--verify` clean |

**Live:** applied at 08:03 UTC, after a fresh pre-change dump.
- Ledger 69, every hash matches.
- `check_mito()` all 0.
- 112 columns.
- `readonly` and `oceangenom_web` keep `SELECT`, and `readonly` reads `mito_assembly_qc`.
- Drift shows only the known og tables.

**Baseline:** only the `public.mitogenome_data` hunks were taken, into `current_schema.sql` and `current_constraints.sql`.

Every new column stays empty until the writers deploy (B.2) and the backfill runs (B.3).
