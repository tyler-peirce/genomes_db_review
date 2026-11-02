# R.6 plan: merge `v3` into `public` (`072`), 2026-11-02

Status: **done 2026-11-02** (record: [`r6_merge_record.md`](r6_merge_record.md)). Design: [`assembly_relations_plan.md`](assembly_relations_plan.md) §6.1 and R.6. Gate work: [`r6_gate_plan.md`](r6_gate_plan.md) and the `r6_gate_*_record.md` files.

## Why today

**The mito production branch already writes the `v3` tables.**
- On 2026-11-02 at 10:20 AWST, eight cleanup commits were pushed to `inverts-dev`. They were built on `phase-r-v3`, not on `inverts-dev`, so `inverts-dev` now equals `phase-r-v3`.
- That brings in `f3f629f` "Write mitogenome results to the Phase R tables".
- The Setonix production clone (`…/Oceanomics-OceanGenomes-Mitogenomes-inverts`) is on it: `b583638`, then `6494002` (docs).

**Every mito upload fails until R.6.**
- Production sessions have `search_path = public`. The writer's unqualified `mito_assembly`, `mito_annotation` and `mito_assembly_qc` don't exist there, so every mito upload fails with "relation does not exist".
- Nothing is written to the wrong place, but nothing is written at all.
- A mito release test (`RELEASE_TEST_261102`) is running from that clone now with uploads on, so its uploads will fail.

The draft (`master`) and ENA-draft (`main`) production branches do not carry their `v3` writers; they still write `public`.

## Go / no-go (checked 2026-11-02, read-only)

| Check | Result |
|---|---|
| `check_mito()` | 0 on every check |
| `check_draft()` | 588 rows each way: today's depth and genome-size uploads, not yet synced. Step 0.2 syncs them |
| `bin/check_drift.py` | Only the colleague's objects: `og_priority_log`, `og_workflow_recommendation` (known) and `v_sample_master_species` (new, theirs). Nothing ours |
| `apply_migrations.py --verify` (07:17 cron) | Ledger OK, all hashes match. `071` is applied, so this is `072` |
| Nightly `sync_v3` | ok (2026-11-01) |
| Writer branches | Draft `phase-r-v3` `45eae0f` (186 tests); mito `phase-r-v3` = `inverts-dev` `6494002`; ENA-draft `phase-r-v3` `c0f78fd`. Each contains its default branch |
| Objects outside `v3` that name `v3.` | None. No function or view; no `v4` FK into `v3`; `sync_v4.sql` mentions it only in a comment |
| Objects depending on the old tables | Views: `mitogenome_submission_view`, `v_genome_size_comparison` (both already rebuilt in `v3`). FKs: `lca_mitogenome_fkey`, `lca_raw_results_mitogenome_fkey`, `lca_validation_mitogenome_fkey`. No triggers. Functions: only the four window functions |
| Name clashes `v3` ↔ `public` | Exactly the four above: two tables, two views |
| Readers by column position (OceanGenom_Web) | **Not checkable here.** `pg_stat_statements` is not installed and the web code is not on this host. Owner or colleague to confirm (step 0.4) |

## Step 0: confirm it is good to go

1. **Fetch every clone and record SHAs** (checklist, "For Pipeline Writer and Reader Audits").
2. **Final sync, then the drift run.**
   - Run `scripts/sync_v3.sh` now; it is the 18:30 UTC job, run early.
   - Then `check_draft()` and `check_mito()` must both be 0, and `bin/check_drift.py` must show only the colleague's three objects.
3. **Pause writers for the window.**
   - **Mito release test:** let it run. Its upload tasks fail until `072` lands. After step 3, `-resume` it; only the failed upload tasks re-run.
   - **No draft or ENA run** between step 2 and step 4.
4. **Column-position readers.** The owner or the colleague confirms OceanGenom_Web does not read `mitogenome_data` or `draft_genomes` by position. `056` already changed the column order in the `v3` views, and their column lists differ from the old tables (§4.3).
   - If unconfirmed, go ahead anyway. The failure is loud, and the old tables stay in `pre_v3_archive` until R.8.
5. **Pre-change dump:** `~/oceanomics_genomes_pre_072_261102.dump` (`pg_dump -Fc`).

## Step 1: migration `sql/072_r6_merge_v3_into_public.sql`

One transaction, behind an opt-in like `050`: `PGOPTIONS='-c oceanomics.r6_merge=yes'`, refused without it.

1. **Final sync inside the transaction:** `v3.sync_mito()`, `sync_draft()`, `sync_sequencing_run()`, then assert `check_mito()` and `check_draft()` are all 0. Abort otherwise.
2. **Dependency snapshot:** list views depending on `public.mitogenome_data` and `draft_genomes` from `pg_depend`. Assert the set is exactly `{mitogenome_submission_view, v_genome_size_comparison}`; anything new aborts.
3. **Record grants.** Copy the old tables' and views' grants into a temp table, to re-apply to the objects that take their names.
4. **Drop** `public.mitogenome_submission_view` and `public.v_genome_size_comparison` (the old versions; the `v3` versions replace them).
5. **Drop the three LCA FKs** to the old `mitogenome_data`. Re-parenting is R.7.
6. **Archive the old tables:** `ALTER TABLE public.mitogenome_data SET SCHEMA pre_v3_archive`, and the same for `draft_genomes`. Their indexes, constraints and owned sequences move with them.
7. **Drop the window-only functions:** `v3.sync_mito`, `sync_draft`, `sync_sequencing_run`, `check_mito`, `check_draft`.
8. **Move every `v3` object** with `SET SCHEMA public`. Owned sequences, indexes, constraints and triggers follow their tables; views keep their OIDs, so dependencies stay intact.
   - **Tables (19):** `draft_busco`, `draft_contamination`, `draft_depthsizer`, `draft_fastp`, `draft_genome`, `draft_genome_run`, `draft_genomescope`, `draft_gfastats`, `draft_merqury`, `draft_submission`, `draft_tiara`, `mito_annotation`, `mito_annotation_gene`, `mito_assembly`, `mito_assembly_depth`, `mito_assembly_qc`, `mito_assembly_run`, `mito_gene`, `sequencing_run`.
   - **Views (8):** `draft_genomes`, `mitogenome_data`, `mitogenome_submission_view`, `v_draft_genome_status`, `v_genome_size_comparison`, `v_mito_annotation_genes`, `v_sequencing_run_fk_readiness`, `v_sequencing_run_issues`.
   - **Functions (2):** `draft_genome_run_illumina_only` (the trigger), and `rebuild_mito_gene_views` with `SET search_path = public, pg_temp`. It is `v3, public, pg_temp` today and its body uses unqualified names.
9. **Grants:** re-apply step 3's grants to the moved views under the same names. Today that is `readonly` and `oceangenom_web` SELECT on `mitogenome_data` and `draft_genomes`, plus whatever the two old views carried. `readonly` gets SELECT on every moved table and view, as it had in `v3`.
10. **`DROP SCHEMA v3 RESTRICT`.** It must be empty.
11. **Verify block:**
    - No `public` view depends on a `pre_v3_archive` table.
    - Row counts: `public.mitogenome_data` (view) = `pre_v3_archive.mitogenome_data` = 2,519, and `public.draft_genomes` (view) = archive = 1,720.
    - `EXCEPT ALL` both ways on each view's named column list against the archived table, which is what `check_*` compared: 0 rows.
    - `v3` no longer exists.
    - `INSERT INTO public.mitogenome_data` fails (it is a view, with no `INSTEAD OF`); tested in a savepoint.

**Revert** in `sql/revert/072_…`:
- move everything back into a recreated `v3`;
- move the archive tables back to `public`;
- recreate the two old views from the baseline definitions, the three FKs, and the five window functions from their `067`/`068` bodies.

The rehearsal proves it schema-identical.

## Step 2: rehearsal on a restore of live (as for `067`/`068`)

Throwaway PG14 cluster `$S/pg067` (port 55432, private socket, `en_AU.UTF-8`, roles `readonly` and `oceangenom_web`); restore today's dump.

1. **Apply `072`**, with and without the opt-in (without must refuse).
2. **Simulated writers**, each from its `phase-r-v3` branch, default `search_path`:
   - **Mito:** `push_mtdna_assm_results.py`, `push_emma_annotation_results.py` and `push_assembly_qc.py` on the NOVA_260925_LA summary staged on 2026-10-30. Each writes, then reads back through `mitogenome_data`.
   - **Draft:** `push_assembly_results_to_sqldb.py` and `push_kmer_depth_to_sqldb.py` on OG2328's archived summaries. Read back through `draft_genomes`.
   - **ENA-draft:** steps 06 and 07 in dry run, then for real on OG1076 and OG48. Step 00's samplesheet query returns the same 1,697 rows as before.
3. **An old writer fails loudly:** `master` `push_assembly_results_to_sqldb.py` raises "cannot insert into view".
4. **Readers:** `summary`, `sample_view`, `lca_validation_report_view` and `embargo_assignment_view` return the same row counts as before, and every view in `public` still selects.
5. **Revert:** `pg_dump -s` identical to before `072`, ignoring the `\restrict` token. Re-apply, then replay with the ledger row deleted: a no-op.
6. **Baseline:** export `schema/current_*.sql` from the rehearsal and take only `072`'s hunks. The colleague's drift stays out.

## Step 3: merge on live (today, after step 2 passes)

1. `bin/apply_migrations.py --dry-run`: only `072` pending.
2. `PGOPTIONS='-c oceanomics.r6_merge=yes' bin/apply_migrations.py`, then `--verify`.
3. **Remove the 18:30 UTC `sync_v3.sh` cron line** on this host (owner's crontab). Keep the script in git; it is now dead code.
4. **Deploy the writers, the same day:**
   - **Draft:** fast-forward `master` to `phase-r-v3`. It is 7 commits ahead and contains `master`. Run the tests, push, `git pull` the Setonix production clone.
   - **ENA-draft:** fast-forward `main` to `phase-r-v3` (2 commits ahead). Pull `~/ENA-draft-genomes` (runs from this host).
   - **Mito:** nothing to merge; production already has it.
5. **Post-checks on live (read-only):**
   - every step 1.11 assertion again;
   - draft `push_kmer_depth_to_sqldb.py --dry-run` on one archived JSON;
   - mito `push_assembly_qc.py --dry-run` on the 260925 summary;
   - ENA-draft step 00 query row count.
6. **Resume the mito release test** with `-resume`; its failed upload tasks re-run and land in the new tables. Check its `sql_uploaded_data/` logs.
7. **Next morning:**
   - `drift_cron.sh` shows only the colleague's drift once the baseline is committed;
   - `sync_v4` (19:00 UTC) is ok;
   - no `sync_v3` failure marker, because the job is gone.

## Step 4: records

- **`docs/r6_merge_record.md`:** SHAs, rehearsal results, live apply, post-checks.
- **`assembly_relations_plan.md`:** R.6 done; R.7 next. Its migration numbers are now `073`+.
- **`database_review.md`:** revision row; Finding 17 and the R.6 gate paragraph closed.
- **RG.6 (other session):** G5 is decided by this. `v_sequencing_run_fk_readiness` reads `public.hifi_reads_qc` and `hic_reads_qc`, which RG.6 turns into views. RG.6 must drop or rebuild it. `sequencing_run` is now in `public` for RG.6's FKs.

## Rollback

- **Database:** the revert migration, run with the same opt-in. If the revert itself fails, restore the pre-change dump.
- **Writers:** reset the draft `master` and ENA-draft `main` to their pre-merge SHAs (recorded in step 0.1). Mito production would then need its pre-Phase R commits back. That is a separate decision; record `364873c`, the last pre-Phase R `inverts-dev`.

## Not in R.6

- R.7: `annotation_id` on the LCA and ENA children; FKs to `sequencing_run`.
- R.8: dropping `pre_v3_archive`, comments, data dictionary.
- The 7 rows in `v_sequencing_run_issues`: moved as-is, triaged in R.7.
