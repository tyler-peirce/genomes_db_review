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

## B.2 mito writers (2026-10-28)

Both branches are pushed and not deployed.

**`r6-mito-qc`** (`364873c`, from `origin/inverts-dev`, writes `public`):
- `push_emma_annotation_results.py` writes `completeness_profile`, which it already required and then dropped.
- New `push_assembly_qc.py` and `PUSH_ASSEMBLY_QC`, once per run after `MITOGENOME_ASSEMBLY_SUMMARY`, under the usual upload gate. It updates the verdict on existing `mitogenome_data` rows, never inserts, and skips by name any prefix that is not `og.tech.seq_date.code`.
- Tests: 7 new unit tests; all 49 upload-script tests pass. The full suite has the same 5 failures as `origin/inverts-dev`, because Biopython is not installed on this host.
- **The Nextflow wiring has not been run.** Nextflow is not installed here. Test it on Setonix before merging into `inverts-dev`.

**`phase-r-v3`** (`d51b1c2`):
- Merges `r6-mito-qc`, keeping the Phase R annotation writer, with `completeness_profile` added to its own lists.
- `push_assembly_qc.py` upserts `mito_assembly_qc` for an existing `mito_assembly`.

**Rehearsal** on a restore of live, using 8 real rows from NOVA_260925_LA's summary table (`r6-mito-qc` plus `sync_mito()` against `phase-r-v3`):
- the same outcome per row: 6 set, 2 `no_row`;
- identical `mito_assembly_qc` rows.

One of the `no_row` assemblies, `OG2651.ilmn.260925.getorg1770`, is in the summary but not in the database; only its `_concat` and reseed assemblies are.

## B.3 backfill: what can be backfilled

**`completeness_profile`:**
- The archived `annotation_stats.csv` files on Acacia carry it only for the newest batch. Of 8 sampled assemblies, 221003–260605 lack the column; 260925 has it.
- Of the 2,144 annotated assemblies on live, **289** have `annotation_stats_version` 2.0.0 (after `b0cf5a3`, 2026-09-07, which keyed the profile on the genetic code). **1,855 have no version**: which standard their `passed` was judged against is not recorded anywhere.
- The genetic code is not stored in the database. It can be derived, because code 2 applies to exactly the vertebrates: profile = `vertebrate` when the species is in a vertebrate class, else `core`. But **463** annotated assemblies have no species class, because their nominal species is not in `species`.

**Assembly QC verdict:** the run-level summary table is not archived to Acacia. Only runs still on Pawsey scratch can be backfilled; NOVA_260925_LA's covers about 200 assemblies.

**Proposal, waiting for the owner:**
- derive `completeness_profile` for the 289 version-2.0.0 annotations only, and leave the 1,855 NULL as "standard not recorded";
- backfill the verdict from NOVA_260925_LA's table;
- otherwise forward-only.

## B.3 `completeness_profile` backfill, done 2026-10-30

**Owner decision:** fill only the 289 annotations with `annotation_stats_version` 2.0.0; leave the 1,855 unversioned ones NULL ("standard not recorded"). The verdict is forward-only.

**Source.** Every one of the 289 (260909: 96, 260925: 193) has an archived `annotation_stats.csv` on Acacia, matched on its `annotation`, that carries the profile the pipeline actually applied:
- 199 `vertebrate`, 90 `core`.
- 100 of the 289 have no species class. For the 189 that do, the archived value equals the class rule (vertebrate class → `vertebrate`) in every case.

The archived values were written, not derived ones.

**Write:**
- `UPDATE public.mitogenome_data`, filling only an empty profile on version-2.0.0 rows, keyed on `(og_id, tech, seq_date, code, annotation)`.
- Required to match exactly 289 rows, or roll back. It matched 289.
- `sync_mito()` carried them (`annotation upserted 289`); `check_mito()` is all 0.
