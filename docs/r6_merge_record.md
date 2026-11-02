# R.6 record: `v3` merged into `public` (`072`), 2026-11-02

Plan: [`r6_merge_plan.md`](r6_merge_plan.md).

## Why it ran today

At 10:20 AWST, eight outstanding cleanup commits were pushed to the mito production branch `inverts-dev` (the owner asked for everything outstanding to be committed). They were built on `phase-r-v3`, so production gained the Phase R writer (`f3f629f`). From then on every production mito upload failed with "relation mito_assembly does not exist" until the new tables reached `public`.

## SHAs (fetched before the merge)

| Repo | Default branch before | `phase-r-v3` |
|---|---|---|
| genomes_db_review | `e573bbf` | — |
| Draft pipeline | `master` `d6cb35d` | `45eae0f` |
| Mito pipeline | `inverts-dev` `6494002` | `6494002` (same) |
| ENA-draft-genomes | `main` `ab9f8c8` | `c0f78fd` |

## Step 0 (2026-11-02, about 05:26 UTC)

- `scripts/sync_v3.sh` run early: ok, and 826 GenomeScope rows carried the day's genome-size uploads across.
- **Checks:** `check_draft()` and `check_mito()` 0 on every check. `bin/check_drift.py` showed only the colleague's objects (`og_priority_log`, `og_workflow_recommendation`, `v_sample_master_species`). The ledger verified, with `071` applied.
- **Pre-change dump:** `~/oceanomics_genomes_pre_072_261102.dump` (24 MB).
- **Column-position readers (OceanGenom_Web):** not checked. The owner chose to go ahead and let them fix any break later.

## Rehearsal (PG14 restore of the dump)

| Check | Result |
|---|---|
| Apply without the opt-in | Refused; nothing changed |
| Apply with `oceanomics.r6_merge=yes` | v3 dropped; `mitogenome_data` and `draft_genomes` are views (2,519 / 1,720 rows = archived tables); grants carried; 56 views in `public`/`v4` all select; `summary`, `sample_view`, `lca_validation_report_view`, `embargo_assignment_view` row counts equal live |
| Mito writers (`phase-r-v3`, default `search_path`) | `push_mtdna_assm_results.py`, `push_emma_annotation_results.py` (OG3150 260925 from Acacia) and `push_assembly_qc.py` (NOVA_260925_LA) all write, and read back through `mitogenome_data` |
| Draft writers (`phase-r-v3`) | `push_assembly_results_to_sqldb.py` and `push_kmer_depth_to_sqldb.py` (OG2328) write, and read back through `draft_genomes` |
| Old draft writer (`master`) | Fails: "cannot insert into view" |
| ENA-draft (`phase-r-v3` on merged vs `main` on unmerged) | Step 06 identical per-field outcomes on OG1076, OG11, OG110; step 07 one row each on OG48, OG6; `draft_submission` 580 rows, 0 differing; step 00 1,697 rows, none one-sided |
| Revert | Schema identical to before `072` (0 diff lines) |
| Re-apply, then replay with the ledger row deleted | Identical schema; the replay is a no-op (same md5) |

**Found in rehearsal:** after the merge, writers write only the new tables. A revert therefore brings back old tables that lack those writes, and the old nightly sync (public → v3) would overwrite them.
- The revert now warns with the per-check counts instead of failing.
- Its header says not to restore the sync until the uploads are replayed into `public`.

## Live

- **Applied:** about 05:34 UTC with `PGOPTIONS="-c oceanomics.r6_merge=yes" bin/apply_migrations.py`. The ledger has 73 rows and verifies.
- **Post-checks (read-only):** all of the rehearsal's structural checks held on live, including the four reader counts and the 56-view sweep.
- **Writer dry runs on live:** draft `push_kmer_depth_to_sqldb.py --dry-run` (OG3110) and mito `push_assembly_qc.py --dry-run` (196 of 197) both ok. ENA-draft step 00 query: 1,697 rows.
- **Cron:** the 18:30 UTC `sync_v3.sh` line removed. Backup: `~/crontab_backup_pre_072_261102.txt`.
- **Writers deployed:**
  - draft `master` `d6cb35d` → `45eae0f` (186 tests pass); Setonix production clone pulled;
  - ENA-draft `main` `ab9f8c8` → `c0f78fd`; this host's checkout is on it;
  - mito already on it.
- **Baseline:** `schema/` refreshed with `072`'s hunks only (commit `2581ed0`). Drift now shows only the colleague's three objects.

## The mito release test (`RELEASE_TEST_261102`)

It was running from the mito production clone with uploads on.
- **Before 13:34 AWST (`072`):** 20 assembly and annotation uploads (14 assemblies) failed with "relation does not exist".
- **After `072`:** all 128 uploads succeeded.

The upload module logs the error and exits 0, so Nextflow cached the failed tasks as successes and `-resume` will not re-run them. List of failed task dirs: `/scratch/pawsey1348/tpeirce/mito_release_test/failed_uploads_pre072_ordered.txt`. The owner is re-running them separately.

A hand re-run was started and then stopped at the owner's request; its effect is unverified. It may have renamed some failed logs to `*.upload.txt.pre072` in those task dirs and re-run some uploads. Check those dirs before re-running.

**Follow-up:** the mito upload modules should fail the task when the script reports a database error. Today a failed upload is invisible to Nextflow.

## Left for later

- **R.7:** `annotation_id` on the LCA and ENA children; FKs to `sequencing_run`. Migration numbers from `073`.
- **RG.6 (other session):** G5 is now settled, R.6 first. `v_sequencing_run_fk_readiness` reads `public.hifi_reads_qc` and `hic_reads_qc`, which RG.6 turns into views, so RG.6 must drop or rebuild it. `sequencing_run` is in `public` for its FKs.
- **R.8:** drop `pre_v3_archive` after a quiet period.
- **OceanGenom_Web:** if it read either table by column position, it needs fixing on its side.
