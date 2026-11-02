# R.7b plan: store the LCA tables by `annotation_id` only (`076`)

Status: **plan, 2026-11-02; not run.** Design: [`assembly_relations_plan.md`](assembly_relations_plan.md) R.7 item 3. Follows R.7 ([`r7_record.md`](r7_record.md)).

## Context

R.7 (`074`) gave the four LCA tables a validated `annotation_id`, and a trigger keeps it equal to the natural columns `(og_id, tech, seq_date, code, annotation)` on every write. So the natural columns are now redundant: they repeat what `annotation_id` already says.

R.7b removes the duplication. The four tables keep only `annotation_id`, and their primary keys are re-keyed on it. The design's view rebuild ("the biggest since V.5") comes with it.

**What R.7b fixes, and what it doesn't.** Since R.7, the natural columns cannot disagree with `annotation_id` (the trigger checks every write). So R.7b fixes no correctness problem. Its value is a single source of truth, smaller tables, and keys that survive a re-annotation. That is why the design put it "after a release has run clean on R.7". R.7 went live at 08:27 UTC today, and the owner has asked to proceed now.

## The import check that clears the way (2026-11-02, 08:42 UTC)

`fetch_excel.sh` was run by hand, exactly as the 18:00 UTC cron runs it. That was the first import with `075`'s triggers on `sequencing`.

| Table | 261101 loaded / rejected / degraded | 261102 |
|---|---|---|
| `sequencing` | 4,455 / 16 / 0 | 4,455 / 16 / 0 |
| `sample` | 3,392 / 0 / 182 | 3,405 / 1 / 182 (today's workbook edits) |
| `tissue` | 7,880 / 8 / 0 | 7,907 / 8 / 0 |
| every other table | identical | identical |

**After the import:**
- 212 runs in `sequencing`, 212 in `sequencing_run`;
- 0 runs missing, 0 unused;
- 0 runs whose instrument or run date disagrees with `sequencing`;
- all nine R.7 FKs validated;
- no failure flag (`~/log/fetch_excel.FAILING` absent).

**Nothing is missing.**

## Who reads and writes the four tables (2026-11-02)

**Tables:** `lca` (5,475 rows), `lca_raw_results` (49,743), `lca_validation` (2,052), `blast_filtered_lca` (248,559).

**Writers (all in the mito pipeline, `inverts-dev`):**
- `push_lca_blast_results.py`: INSERT `blast_filtered_lca` and `lca` ON CONFLICT on the natural PK; DELETE superseded `lca` rows by natural key.
- `push_lca_raw_results.py`: INSERT ON CONFLICT; DELETE by natural key.
- `push_species_validation.py`: reads, then INSERT ON CONFLICT `(og_id, tech, seq_date, code, annotation)`.
- `push_qc_validator.py`: SELECT and UPDATE `lca_validation` by natural key.
- `public.lca_validation_report_view_upd()`: the `033` INSTEAD OF UPDATE path.

**Readers outside the database:**
- **ENA-draft-genomes:** steps 00 and 06 read `lca_validation` by `og_id`, `seq_date`, `tech`.
- **ENA-ref-genomes:** step 00 reads `lca_validation` by `og_id`, `tech`, `seq_date`.
- **OceanGenom_Web:** has SELECT on `summary` only.

**Readers inside the database (10 views and 2 functions):**
- Read directly: `summary`, `sample_view`, `lca_validation_report_view` (with its INSTEAD OF UPDATE trigger), `filtered_lca_view`, `lca_pivot_view`, `embargo_assignment_view`, `mitogenome_submission_view`.
- Read through those: `lca_results_view`, `goat_species_v1`, `pre_v4_archive.goat_species_v1`.
- Functions: `build_final_data_compile(text[])` and `lca_validation_report_view_upd()`.

## Approach: normalised base tables, compatibility views under the old names (the R.6 pattern)

Dropping the columns in place would break every reader above. The ENA readers alone filter on `og_id`, `seq_date` and `tech`. Instead:

**Base tables, renamed:**

| Base table | Was | Primary key |
|---|---|---|
| `mito_lca` | `lca` | `(annotation_id, region, content_hash)` |
| `mito_lca_raw` | `lca_raw_results` | `(annotation_id, sequence_region, accession_id, content_hash)` |
| `mito_lca_validation` | `lca_validation` | `(annotation_id)` |
| `mito_blast_hit` | `blast_filtered_lca` | `(annotation_id, match_sequence_id, region)` |

- Each drops `og_id`, `tech`, `seq_date`, `code` and `annotation`, plus its FK to `sample` (redundant through the annotation). It keeps its `annotation_id` FK to `mito_annotation`.
- R.7's `*_annotation_id` triggers go with the columns they read.

**Compatibility views under the old names** (`lca`, `lca_raw_results`, `lca_validation`, `blast_filtered_lca`):
- each is `base ⋈ mito_annotation ⋈ mito_assembly`, with exactly the old column list in the old order (natural columns first, `annotation_id` last);
- `SELECT *` and every named-column reader sees what it sees today;
- grants are copied from the old tables.

**The 10 dependent views** are dropped and recreated from their current definitions (`pg_get_viewdef`), so they read the compatibility views. Definitions are textually unchanged, because they name `lca_validation` and the other old names, which now resolve to the views. Comments and grants are restored, and so is the `033` INSTEAD OF UPDATE trigger on `lca_validation_report_view`. Its function is changed to update `mito_lca_validation` by `annotation_id`.

**`content_hash`** is recomputed once, inside the migration. With the natural columns gone, `to_jsonb(NEW)` changes, so every stored hash would otherwise stop matching what the trigger computes. The migration:
- recomputes all hashes with the trigger;
- asserts the new PK has no collision;
- keeps the old hashes in `pre_v3_archive.*_hash_map_076` (old hash, new hash, `annotation_id`) for audit.

**Writers send `annotation_id` and write the base tables.** This is the only code change, and it is all in the mito pipeline: a branch `r7b-lca-base-tables` from `inverts-dev`.
- **Lookup:** each script resolves `annotation_id` once per upload, from the assembly prefix and annotation (`mito_annotation ⋈ mito_assembly`). There is no match only if the annotation upload was skipped; that fails loudly, as since R.7.
- `push_lca_blast_results.py` and `push_lca_raw_results.py`: INSERT into `mito_blast_hit` / `mito_lca` / `mito_lca_raw` ON CONFLICT on the new PKs; DELETE by `annotation_id`.
- `push_species_validation.py`: INSERT `mito_lca_validation` ON CONFLICT `(annotation_id)`; its read can stay on the `lca_validation` view.
- `push_qc_validator.py`: UPDATE `mito_lca_validation` WHERE `annotation_id`.
- Unit tests for each, against the new SQL. Deploy the same day as the migration: merge to `inverts-dev`, pull the Setonix production clone.

**Not changed:** `ena_validation_attempts` and `ena_submissions` keep their natural columns. `ena_submissions` derives them from `full_seqid`; the ENA tables are the downstream submitter's ledger. The ENA-draft and ENA-ref readers, and OceanGenom_Web.

## Migration `076_r7b_lca_base_tables.sql`

One transaction; opt-in `PGOPTIONS="-c oceanomics.r7b_lca=yes"`. Replay: if `mito_lca_validation` exists and `lca_validation` is a view, do nothing.

1. **Guards:**
   - no running writer (checked before applying);
   - the dependent-view set equals the ten above, from `pg_depend`, recursive;
   - every row's natural columns still agree with its `annotation_id` (they must, since R.7).
2. **Snapshot** row counts and an md5 per table over the non-key columns, ordered by the new PK, to compare after.
3. **Save the dependent views:** definition, comment, grants, triggers. Drop them, leaves first.
4. **For each of the four tables:**
   - `ALTER TABLE … RENAME TO mito_…`;
   - drop R.7's trigger and the `sample` FK;
   - drop the old PK;
   - drop the five natural columns;
   - recompute `content_hash` (`lca`, `lca_raw` only), recording the hash map;
   - add the new PK;
   - rename the indexes and constraints to match the new name.
5. **Create the four compatibility views** with the old names and column order. `COMMENT` each as "compatibility view; write `mito_…`". Grants.
6. **Recreate the ten dependent views** from step 3, in dependency order, with comments, grants and the `033` trigger. `lca_validation_report_view_upd()` is rewritten to update `mito_lca_validation` by `annotation_id`. Check `build_final_data_compile` still compiles and runs.
7. **Verify:**
   - row counts and non-key md5s equal step 2;
   - every compatibility view returns the old row count and column list;
   - all ten views select with the same row counts as before (`summary` 3,402 and so on), and their column lists are unchanged;
   - no view depends on anything in `pre_v3_archive`;
   - an insert into `lca_validation` (the view) fails: writers must use the base table.

**Revert `sql/revert/076_…`:** rebuild the four tables with natural columns from the compatibility views, restore the old PKs, FKs, triggers and hashes (from the hash map), and the views. Prove it schema-identical in rehearsal.

## Rehearsal (as for `072`, `074`)

On a restore of live taken just before:
1. Refused without the opt-in; applied with it. Time it: `blast_filtered_lca` is 248,559 rows and the hash recompute touches 55,218 rows.
2. **New writers** (branch `r7b-lca-base-tables`) on OG3150 260925 from Acacia (`lca/`, `ena/validation/`), run twice: the second pass adds no rows. **Old writers** (`inverts-dev`) fail loudly on the views.
3. **Readers:**
   - the ENA-draft step 00 query (1,697 rows) and the ENA-ref step 00 query give the same result as before;
   - `summary`, `sample_view`, `lca_validation_report_view` and `embargo_assignment_view` counts are equal, and an md5 of each view's full output equals before;
   - the `033` update path works;
   - `build_final_data_compile` returns the same output for a sample of OGs.
4. **Performance:** time `summary`, `lca_pivot_view` and `lca_validation_report_view` before and after (`summary` was 2.0 s). Each compatibility view adds two joins.
5. **Revert** schema-identical, re-apply, replay a no-op.
6. **Baseline:** `076`'s hunks only; `object_inventory.tsv` gains `mito_lca`, `mito_lca_raw`, `mito_lca_validation` and `mito_blast_hit` as tables, and the four old names become views.

## Live (same day as the writer deploy)

1. Fetch every clone and record SHAs. Re-run the R.7 go/no-go and the import check above.
2. **No mito run uploading:** `squeue` on Setonix, and the release test if it is still going.
3. Pre-change dump. Apply `076` with the opt-in, then `--verify`.
4. **Deploy the writers:** merge `r7b-lca-base-tables` to `inverts-dev` (tests pass), pull the Setonix production clone.
5. **Post-checks:**
   - the verify block's assertions again;
   - the ENA-draft step 00 row count;
   - one mito writer `--dry-run` where it has one;
   - the 18:00 UTC import and the 07:17 drift run next morning.
6. **Records:**
   - `docs/r7b_record.md`;
   - `assembly_relations_plan.md`: R.7 item 3 done;
   - `database_review.md` revision row;
   - mito `CHANGELOG.md` and `docs/output.md` name the new tables.

## Rollback

- **Database:** the revert file with its opt-in.
- **Writers:** reset `inverts-dev` to its pre-merge SHA and pull on Setonix.
- **Uploads made between the apply and a revert** exist only in the base tables. The revert rebuilds from them, so nothing is lost.

## Decisions for the owner

1. **Approach:** base tables plus compatibility views (recommended, above), or drop the columns in place and rewrite every reader, including ENA-draft, ENA-ref and the ten views.
2. **Names** of the base tables: `mito_lca`, `mito_lca_raw`, `mito_lca_validation`, `mito_blast_hit`.
3. **Timing:** now, or after one clean release run on R.7, as the design intended. R.7 already prevents any disagreement, so waiting costs nothing in correctness.
