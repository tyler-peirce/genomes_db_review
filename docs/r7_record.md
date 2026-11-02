# R.7 record: `annotation_id` on the mito child tables; `sequencing_run` upkeep and run FKs (`074`, `075`), 2026-11-02

Plan: [`r7_plan.md`](r7_plan.md). R.6 record: [`r6_merge_record.md`](r6_merge_record.md).

## What changed on live

**`074`:** `lca`, `lca_raw_results`, `lca_validation`, `blast_filtered_lca`, `ena_validation_attempts` and `ena_submissions` each now have:
- `annotation_id bigint NOT NULL`, indexed;
- a validated FK `<table>_annotation_fkey` to `mito_annotation`;
- a trigger `<table>_annotation_id` (function `mito_child_annotation_id()`). It fills `annotation_id` from `(og_id, tech, seq_date, code, annotation)` when a writer omits it, checks it when one sends it, and refuses a row naming no single annotation ("upload the assembly and its annotation before its LCA/ENA results").
- **Writers are unchanged.**
- **`lca_set_content_hash()`** now excludes `annotation_id`. The hash triggers were disabled during the backfill, and every stored `content_hash` was asserted unchanged.

**`075`:** `sequencing_run` is kept current by triggers on `sequencing`.
- **Per row:** `sequencing_run_ensure` creates the run before the row lands.
- **Per statement:** `sequencing_run_refresh_{ins,upd,del}` re-derive instrument and run date, and drop a run nothing uses.
- **Function:** `refresh_sequencing_run(text[])` holds the logic of the dropped `v3.sync_sequencing_run`.
- **FKs, validated:** `sequencing_run_id_fkey`, `raw_data_run_id_fkey` and `rna_qc_kinnex_run_id_fkey` to `sequencing_run`. Plus `sequencing_run_id_idx`.

## Found while building it (not in the plan)

- **`sequencing_run` had lost its upkeep at R.6.** `072` dropped `v3.sync_sequencing_run()` with the other window functions, and the nightly importer (`import_v2.py`, `phase-r-import` branch) never writes `sequencing_run`. Any run first seen after 2026-11-02 would have had no row, and with `075`'s FK the importer would then have rejected those sequencing rows. The upkeep triggers in `075` replace the nightly sync.
- **`ena_submissions`' key columns are GENERATED from `full_seqid`.** A BEFORE trigger sees generated columns as NULL, so the first version of the trigger would have refused every ENA-mito step 06 insert. The rehearsal caught it. For that table the trigger derives the key from `full_seqid` with the same expressions, and fires on `UPDATE OF full_seqid, annotation_id`.

## Rehearsal (PG14 restore of live, post-RG.6)

| Check | Result |
|---|---|
| `074` without the opt-in | Refused; nothing changed |
| Apply both with `oceanomics.r7_annotation_id=yes` | 17 s (248,559 `blast_filtered_lca` rows) |
| `push_lca_blast_results.py` and `push_lca_raw_results.py` (`inverts-dev`, unchanged) on OG3150 260925, run twice | Rows matched, `annotation_id` filled. **No row added on either pass** ("0 inserted, 16 refreshed"), so stored hashes still deduplicate |
| `push_ena_validation_results.py` (OG3150) | Updated the attempt; `annotation_id` filled |
| `lca_validation` upsert (`push_species_validation.py` shape) and the `033` `lca_validation_report_view` UPDATE | Work; `annotation_id` kept |
| ENA-mito step 06 shape (re-upsert existing; new submission) and step 07 UPDATE | Work; new row's `annotation_id` filled from `full_seqid` |
| Orphan insert into each of the six tables | Refused with the trigger's message |
| `import_v2.py` on the 261101 workbook | Loaded / rejected / degraded counts identical to live's 2026-11-01 run for every table |
| New run via a `sequencing` insert; its last row deleted | Run created (mach, date, initial, instrument), then removed |
| Revert `075` then `074` | Schema identical (0 diff lines). Re-apply identical; replay with the ledger rows deleted a no-op (same md5) |

## Live

- **Go/no-go:** all 306,741 child rows resolve to exactly one annotation. 0 runs missing, 0 unmatched. No active writes on the child tables. Drift only the colleague's objects.
- **Pre-change dump:** `~/oceanomics_genomes_pre_074_261102b.dump`.
- **Applied:** about 08:27 UTC; 17 s; the ledger has 76 rows and verifies.
- **Post-checks:** all nine FKs validated; 0 NULL `annotation_id`; four triggers on `sequencing`; every `public` view selects. A mito `push_assembly_qc.py --dry-run` is ok.
- **Baseline:** `schema/` refreshed with the `074`/`075` hunks only (commit `1461ebb`). Drift shows only the colleague's three objects.
- **Tomorrow:** check the 18:00 UTC import output (`~/lab_db_updates/out.261102.txt`) and the 07:17 drift run.

## Effects to know

- **An LCA, BLAST, validation or ENA row for an assembly/annotation not in the database is now refused.** The pipeline already uploads annotations first.
- **Failed uploads can still look like successes.** The mito upload modules swallow script errors (R.6 record), so a refused row shows only in the `*.upload.txt` log. Making those modules fail the task is still open.

## Next

- **R.7b:** writers send `annotation_id`; then drop the natural columns from the LCA tables and rebuild `summary`, `sample_view`, `lca_validation_report_view`, `filtered_lca_view`, `lca_pivot_view`, `lca_results_view` and `embargo_assignment_view` on it. After a release has run clean on R.7.
- **R.8:** drop `pre_v3_archive`; comments; data dictionary.
