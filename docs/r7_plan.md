# R.7 plan — re-parent the mito child tables onto `mito_annotation`; FKs to `sequencing_run`

Status: **done 2026-11-02** as `074` and `075` (record: [`r7_record.md`](r7_record.md); `075` also restores `sequencing_run` upkeep, which R.6 had dropped). Earlier plans: `docs/r6_merge_plan.md` (R.6, done), `docs/r6_gate_plan.md`.

## Context

R.6 (`072`, 2026-11-02) made `mito_assembly` / `mito_annotation` the tables of record. As part of that it dropped the three four-column FKs from `lca`, `lca_raw_results` and `lca_validation` to the old `mitogenome_data`. **Since then nothing enforces that an LCA or ENA row refers to an annotation that exists.** `blast_filtered_lca`, `ena_validation_attempts` and `ena_submissions` never had such an FK.

R.7 restores that integrity against the new tables. It also adds the run FKs that `sequencing_run` was built for. Design: `docs/assembly_relations_plan.md` §3 and R.7.

**Out of scope, as the design says:** dropping the natural columns from the LCA tables and rebuilding `summary`, `sample_view`, `lca_validation_report_view`, `filtered_lca_view`, `lca_pivot_view`, `lca_results_view` and `embargo_assignment_view` on `annotation_id`. That is a separate batch, R.7b, after a release has run clean on R.7.

**Running alongside:** RG.6 is being applied by another session now. Migration numbers below are placeholders (`07A`, `07B`) and are fixed once RG.6's number is in the ledger.

## Measured on live (2026-11-02, read-only, after `072`)

| Child table | Rows | Resolve to exactly 1 annotation | 0 | >1 | Size |
|---|---:|---:|---:|---:|---:|
| `lca` | 5,467 | 5,467 | 0 | 0 | 3.6 MB |
| `lca_raw_results` | 49,687 | 49,687 | 0 | 0 | 35 MB |
| `lca_validation` | 2,051 | 2,051 | 0 | 0 | 0.6 MB |
| `blast_filtered_lca` | 247,675 | 247,675 | 0 | 0 | 120 MB |
| `ena_validation_attempts` | 1,371 | 1,371 | 0 | 0 | 1.0 MB |
| `ena_submissions` | 539 | 539 | 0 | 0 | 0.7 MB |

Resolution is by `(og_id, tech, seq_date, code, annotation)` → `mito_assembly` ⋈ `mito_annotation`. `mito_annotation` has 2,145 rows, unique on `(assembly_id, annotation)`.

**Run links:** `sequencing.run_id` 4,468 rows (12 NULL), `raw_data.run_id` 8,010 and `rna_qc_kinnex.run_id` 96, with **0 unmatched** against `sequencing_run` (PK `run_id`). `v_sequencing_run_fk_readiness` is 0 failing for all four children. The HiFi and Hi-C read-QC FKs are RG.6's.

**Constraints today:**
- The four LCA tables have an FK to `sample(og_id)` only.
- `lca` and `lca_raw_results` have a BEFORE INSERT OR UPDATE trigger, `lca_set_content_hash()`. It computes `content_hash = md5(to_jsonb(NEW) - 'lca_run_date' - 'og_num' - 'content_hash')`, and `content_hash` is part of both PKs.
- No FK points at `sequencing_run` yet.

**Writers of the child tables:**
- **Mito pipeline (`inverts-dev`):** `push_lca_blast_results.py` (`blast_filtered_lca`, `lca`, with DELETE of superseded rows), `push_lca_raw_results.py`, `push_species_validation.py` (`lca_validation`), `push_qc_validator.py` (UPDATE `lca_validation` by key), `push_ena_validation_results.py`.
- **ENA-mito-genomes (`main` `bbba294`):** step 06 (INSERT `ena_submissions`), step 07 (UPDATE `ena_submissions` by `full_seqid`).
- **`033`'s INSTEAD OF UPDATE** on `lca_validation_report_view`.
- **`OceanOmics-Database/SS/` importers:** decommissioned; they fail closed.

## Design decision: the database fills `annotation_id`; writers are unchanged in R.7

A BEFORE INSERT OR UPDATE trigger on each child table resolves the row's natural columns to `annotation_id`:
- When `annotation_id` is NULL, it fills it.
- When it is given, it requires it to agree with the natural columns.
- When the natural columns match no annotation, or more than one, it raises a clear error.

This is the design's "consistency trigger", extended to fill. It means:
- No pipeline or ENA-mito code has to change or deploy for R.7. Today's writers keep sending the natural columns, and the FK is enforced underneath them.
- The ENA-mito owner question in the design reduces to "a new NOT NULL column appears on `ena_submissions`, filled for you". Its writers do not name it, so nothing they do changes. The owner decided on 2026-10-20 that both ENA tables link to `mito_annotation`.
- R.7b, which drops the natural columns, is when writers must send `annotation_id`.

**Writing an LCA row for an annotation that does not exist now fails.** That is the integrity being restored. Order matters in the pipeline: annotation upload before LCA upload. It already runs in that order.

## Migration `07A_r7_child_annotation_id.sql`

One transaction; opt-in `PGOPTIONS="-c oceanomics.r7_annotation_id=yes"`, as in `050` and `072`. Replay: if every child already has a validated `annotation_id` FK, do nothing.

1. **Guards:** every child row resolves to exactly one annotation (the measurement above; abort with the counts otherwise).
2. **`public.mito_child_annotation_id()`**, one trigger function shared by all six tables:
   - `SET search_path = public, pg_temp`;
   - looks up `annotation_id` from `NEW.og_id, tech, seq_date, code, annotation`;
   - fills or checks it; raises `foreign_key_violation` with the key on no match.
3. **For each of the six tables:**
   1. `ADD COLUMN annotation_id bigint`.
   2. **Content hash.** Add `- 'annotation_id'` to `lca_set_content_hash()`, so the new column is not part of the hash. Without this, a re-upload no longer matches the stored hash and duplicates rows. Disable `lca_content_hash` and `lca_raw_results_content_hash` for the backfill, so no stored hash (a PK column) is recomputed. Re-enable afterwards.
   3. **Backfill:** `UPDATE … SET annotation_id = r.annotation_id FROM (mito_assembly ⋈ mito_annotation) r WHERE <natural key match>`. `blast_filtered_lca` (247,675 rows, 120 MB) is the long one.
   4. Assert 0 NULLs, then `SET NOT NULL`.
   5. `CREATE INDEX <table>_annotation_id_idx ON <table> (annotation_id)`. FK checks on `mito_annotation` deletes need it, and `push_emma_annotation_results.py` deletes genes, not annotations.
   6. `ADD CONSTRAINT <table>_annotation_fkey FOREIGN KEY (annotation_id) REFERENCES mito_annotation (annotation_id) NOT VALID`, then `VALIDATE CONSTRAINT`. NO ACTION on delete: an annotation with LCA results cannot be deleted silently.
   7. **Trigger:** `CREATE TRIGGER <table>_annotation_id BEFORE INSERT OR UPDATE OF og_id, tech, seq_date, code, annotation, annotation_id`. Firing order against `*_content_hash` does not matter, because step 3.2 keeps `annotation_id` out of the hash.
   8. A column comment naming the trigger and that writers may omit the column.
4. **Verify:**
   - each FK `convalidated`;
   - 0 NULLs;
   - a probe insert with a bogus annotation fails, and one with a real key fills `annotation_id`, both in rolled-back savepoints;
   - `content_hash` of every `lca` / `lca_raw_results` row unchanged: compare `md5(string_agg(content_hash ORDER BY …))` before and after.
   - `summary`, `sample_view`, `lca_validation_report_view` and `embargo_assignment_view` row counts unchanged.

**Revert `sql/revert/07A_…`:** drop the triggers, FKs, indexes and columns; restore `lca_set_content_hash()` without the exclusion; drop the function. Schema-identical in rehearsal.

## Migration `07B_r7_run_fks.sql`

Opt-in not needed: it adds constraints and changes no data.
- `sequencing.run_id`, `raw_data.run_id` and `rna_qc_kinnex.run_id` each get `FOREIGN KEY (run_id) REFERENCES sequencing_run (run_id) NOT VALID`, then `VALIDATE`. NULLs are allowed: 12 in `sequencing`.
- Index `run_id` where one does not exist already.

**Writer check before applying:**
- `OceanOmics-Database/import_v2.py` writes `sequencing`, `raw_data` and `sequencing_run`. It must insert the run before its rows. Read it, and rehearse one nightly import on the restore. That import is the 18:00 UTC cron `fetch_excel.sh`; confirm it calls `import_v2.py`.
- `rna_qc_kinnex`: find its writer (`grep -r rna_qc_kinnex` across repos); same check.
- If the importer inserts children first, use `DEFERRABLE INITIALLY DEFERRED` FKs instead. The rehearsal decides.

Revert: drop the three FKs (and any index this file created).

## Rehearsal (as for `067`, `068`, `072`)

Throwaway PG14 cluster `$S/pg067` (port 55432), restored from a fresh `pg_dump -Fc` of live taken after RG.6.

1. **`07A`:** refused without the opt-in; then applied with it. Time the `blast_filtered_lca` backfill; it must fit a quiet window.
2. **Writers against the rehearsal**, default `search_path`, unchanged code:
   - **Mito:** `push_lca_blast_results.py`, `push_lca_raw_results.py`, `push_species_validation.py`, `push_qc_validator.py` and `push_ena_validation_results.py` on one archived assembly (OG3150 260925 from Acacia: `lca/`, `ena/validation/`). The rows land with `annotation_id` filled. Re-running the LCA upload adds **no** rows, which checks the content-hash exclusion.
   - **A missing annotation:** the same LCA upload for an assembly with no `mito_annotation` row fails with the trigger's message.
   - **ENA-mito step 06 and 07** on a test receipt for one `full_seqid`; then `-rgj`/obsolete keys fail as expected.
   - **`lca_validation_report_view` UPDATE** (the `033` path) still works.
3. **`07B`:** the nightly importer run against the restore (`import_v2.py` on the latest workbook in `~/lab_db_updates`) succeeds with the FKs in place.
4. **Revert both:** `pg_dump -s` identical to before, ignoring `\restrict`. Re-apply, then replay with the ledger rows deleted: a no-op.
5. **Baseline:** export into a temp dir and take only `07A`/`07B` hunks (colleague drift excluded: `og_*`, `master_species`, `v_sample_master_species`). Update `schema/object_inventory.tsv` (no new objects; the inventory lists tables and views only).

## Live

1. Fetch all clones and record SHAs. Confirm RG.6's migration is in the ledger, and number these files after it.
2. **Go / no-go (read-only):**
   - the resolution query above is still 0 / 0 for the zero and many columns;
   - the run-link query is still 0 unmatched;
   - `bin/check_drift.py` shows only the colleague's objects;
   - `apply_migrations.py --verify` passes;
   - no mito pipeline run is uploading. Check `squeue` on Setonix, and the release test.
3. Pre-change dump `~/oceanomics_genomes_pre_07A_<date>.dump`.
4. `PGOPTIONS="-c oceanomics.r7_annotation_id=yes" bin/apply_migrations.py` (applies `07A` and `07B` in order), then `--verify`.
5. **Post-checks:**
   - the step 4 verify assertions again;
   - one dry-run upload per mito writer that has `--dry-run`;
   - next morning: `drift_cron.sh` clean (colleague drift only), and the 18:00 UTC import ok (`~/lab_db_updates` log).
6. **Records:**
   - `docs/r7_record.md`;
   - `assembly_relations_plan.md` R.7 done, R.7b next;
   - `database_review.md` revision row.

## Rollback

- Each revert file, with the same opt-in for `07A`, then delete the ledger rows.
- No writer changed, so there is nothing to roll back in the pipelines.

## Risks

- **An LCA upload for an unannotated assembly now fails.** Intended. If a pipeline path does this, for example the BLAST of precomputed annotations, the rehearsal's writer runs show it first.
- **The `blast_filtered_lca` backfill locks the table.** It runs inside the migration's transaction, minutes at 120 MB. Run it when no mito upload is in flight (go/no-go step 2).
- **Stored `content_hash` values that a fresh calculation would no longer reproduce.** Leaving the triggers disabled during the backfill avoids touching them. Rehearsal step 2's re-upload shows whether today's hashes still dedupe.
- **RG.6 interplay:** `07B` and RG.6 both add FKs to `sequencing_run`. Independent, but number after RG.6, and re-read `v_sequencing_run_fk_readiness` after it lands.

## Verification summary

R.7 is done when:
- all six children carry a validated `annotation_id` FK to `mito_annotation`, and the three run FKs are validated;
- unchanged writers still upload, and a re-upload adds no rows;
- an orphan upload fails loudly;
- every reader returns the same counts;
- the revert is schema-identical;
- drift is clean the next morning.
