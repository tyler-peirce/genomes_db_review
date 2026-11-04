# Next steps plan: run links for read QC, loud mito upload failures, password rotation (2026-11-04)

Status: **B done 2026-11-04** (record below); A and C not run. Owner decisions 2026-11-04: A strict; start with B. Follows R.7b ([`r7b_record.md`](r7b_record.md)) and RG.6 ([`rg6_record.md`](rg6_record.md)).

Three pieces, independent of each other:
- **A:** a migration.
- **B:** a mito pipeline change.
- **C:** owner-led, with a runbook that already exists.

---

## A. Run FKs for HiFi and Hi-C read QC (`077`)

### Why

RG.6's record left `hifi_read_qc.run_id` and `hic_read_qc.run_id` → `sequencing_run` to R.7, "once something maintains `sequencing_run`". `075` added that upkeep but only FK'd `sequencing`, `raw_data` and `rna_qc_kinnex`. These two are the gap.

### Measured (2026-11-04, read-only)

- `v_sequencing_run_fk_readiness`: `hifi_read_qc` 279 rows, `hic_read_qc` 552, 0 unmatched in each.
- Both tables already have FKs to `sample(og_id)` and `sequencing(sequencing_id)` (`ON DELETE SET NULL`), and no FK on `run_id`.
- **Writers:**
  - `OceanOmics-OceanGenomes-ref-genomes` `scripts/03_compile_results/0b_push_hifi_yield_results_to_sqldb.py` (`master` and `phase-rg-v4`);
  - `ref_genomes_hic_automation`'s `push_hic_yield.py` (INSERT … ON CONFLICT DO NOTHING).
- **The risk:** both run on reads straight off the sequencer, so they can push a run before the lab workbook lists it. RG.0 found 29 such rows (7 HiFi on `PACB_250717_AD`, 22 Hi-C on `NOVA_240719_AD` / `NOVA_250114_AD`), later fixed in the workbook (`069`).

### Design: **strict, decided by the owner 2026-11-04**

- **Strict (recommended):** add `hifi_read_qc_run_id_fkey` and `hic_read_qc_run_id_fkey` → `sequencing_run`, NOT VALID then VALIDATE, and index `run_id`.
  - A push for a run the workbook does not have yet is refused. The writers report it; the HiFi script exits non-zero; `push_hic_yield.py` to be checked.
  - The row lands once the run is in the workbook and the push is re-run.
  - This holds the line RG.0 drew: a run is real once the lab records it.
- **Lenient:** the same FKs, plus a BEFORE INSERT trigger on both tables that creates a missing run from its name, like `075`'s `sequencing_run_ensure`.
  - `refresh_sequencing_run()` must then keep runs that read QC uses.
  - Nothing is ever refused, but a mistyped run name becomes a run.

**In both cases** `refresh_sequencing_run()` is extended to keep a run referenced by `hifi_read_qc` or `hic_read_qc`. Otherwise deleting a run's last `sequencing` row would fail on the new FK instead of leaving the run.

### Steps

1. Read both writers. Confirm what each does on an FK error, and that the HiFi script exits non-zero.
2. **Write `077_read_qc_run_fks.sql`** and its revert, in the `075` style:
   - replay: if both FKs exist, do nothing;
   - verify: 0 unmatched, both FKs validated, and a probe insert with an unknown run is refused (strict) or creates the run (lenient).
3. **Rehearse on a restore of live:**
   - both writers on one real run each (a known run works; an unknown run behaves as chosen);
   - the nightly importer unchanged;
   - revert schema-identical; replay a no-op.
4. **Live:**
   - go/no-go: readiness 0 unmatched; no ref-genome push running;
   - dump, apply, verify;
   - baseline hunks;
   - record `docs/r7c_record.md`; tick RG.6's left-for-later item.

---

## B. Mito upload modules fail loudly without stopping the run

### The problem

A refused or failed database write currently looks like success:
- **Scripts that swallow the error:** `push_mtdna_assm_results.py` and `push_emma_annotation_results.py` catch database errors, print `❌ Database error`, and exit 0.
- **Modules that force success:** `PUSH_QC_VALIDATOR` and `PUSH_ENA_VALIDATION_RESULTS` run their script under `set +e`, record `UPLOAD_EXIT=` in the log, and `exit 0`.
- **The cost:** Nextflow records the task as succeeded and caches it, so `-resume` never re-runs it. This is how 20 of the release test's uploads (`RELEASE_TEST_261102`) were lost silently before R.6, and why `-resume` could not recover them.

The other upload scripts already exit non-zero on failure: `push_lca_blast_results.py`, `push_lca_raw_results.py`, `push_species_validation.py` and `push_assembly_qc.py`.

### What the pipeline already does with a failed task

`conf/base.config`'s default `errorStrategy`:
- retries once unconditionally, to cover Setonix's lost sbatch acknowledgements;
- then `'ignore'`, with `maxErrors = '-1'`.

So a failed upload task **does not stop the run**; the rest of the samples carry on. Ignored tasks are not cached, so `-resume` re-runs exactly them. The owner's requirement, "fail but keep the run going", is met by letting the tasks fail honestly.

### Changes (mito pipeline, branch `loud-upload-failures` from `inverts-dev`)

1. **`push_mtdna_assm_results.py` and `push_emma_annotation_results.py`:** exit 1 on a database error, after printing it. Keep their deliberate non-error outcomes at 0:
   - "existing successful row preserved";
   - "nothing to change";
   - `--force` refusals that are policy, not failure.
   Check each `return` path.
2. **`PUSH_QC_VALIDATOR` and `PUSH_ENA_VALIDATION_RESULTS`:** keep writing the log and `UPLOAD_EXIT=`, then `exit $upload_rc` instead of `exit 0`. Their scripts already exit 0 for the "no row / preserved / not submission_ready" outcomes, so only real errors fail.
3. **A failed-upload list you can see.** Ignored tasks do not publish their outputs, so the `*.upload.txt` of a failed upload stays in its work dir.
   - Add an `errorStrategy` closure for the upload label (`withLabel: process_upload`). It decides exactly as the default does (one retry, then ignore), and **on the final ignore appends a line** to `${params.outdir}/sql_uploaded_data/FAILED_UPLOADS.tsv`: process, tag, exit status, work dir, time.
   - `workflow.onComplete` prints the count and the file's path at the end of the run, so a failed upload cannot pass unnoticed.
4. **`UPLOAD_RESULTS_SUMMARY`** (the MultiQC "SQL Upload Summary") reads `FAILED_UPLOADS.tsv` when present and lists those uploads as failed. Today it only sees published logs.
5. **Tests:**
   - unit tests that each script exits 1 on a database error and 0 on its policy outcomes;
   - nf-test for one upload module with a config pointing at an unreachable database: the task fails, the workflow completes, and `FAILED_UPLOADS.tsv` names the task.
6. **Docs:** `docs/output.md` (Database uploads: what a failed upload looks like and how to re-run it with `-resume`), and `CHANGELOG.md`.

### Verification

- **The nf-test above.**
- **A real run on Setonix** against live, with uploads on, on 2–3 samples, one of them deliberately un-annotated, so its LCA upload is refused by `074`'s FK. Expected:
  - the run completes;
  - the refused task is listed in `FAILED_UPLOADS.tsv` and in the end-of-run message;
  - `-resume` after uploading the annotation re-runs only that task.
- Merge to `inverts-dev`, pull the Setonix production clone, record in the mito `CHANGELOG.md` and the review doc.

### Not in scope

The draft pipeline's upload modules. Check whether they swallow errors the same way; a short follow-up if so.

---

## C. Rotate the `postgres` password (backlog: highest priority)

The password has never been rotated. It was world-readable on this host for about two months (Finding 14) and is in `OceanOmics-Database`'s git history. The runbook is `OceanOmics-Database/ROTATION.md`; the owner runs it.

1. **Pick a Monday and announce it.** The DBeaver users and anyone with a cfg on Setonix will need the new password.
2. **Confirm last night's backup.** `/etc/cron.d/db_s3_push`, 19:00 UTC.
3. **Change it in `psql` with `\password postgres`,** not `ALTER ROLE`, which logs it.
4. **Update the cfg files:**
   - `~/postgresql_details/oceanomics.cfg` on this host: the importer, the drift and sync crons, the ENA steps, and the review tooling;
   - the copy in `/home/tpeirce/postgresql_details/` on Setonix: every pipeline's `--sql_config`.
5. **Propagate** per the runbook's table (OceanGenom_Web's own credentials are a different role).
6. **Check, the next day:**
   - the 18:00 UTC import log;
   - the 07:17 drift run;
   - one pipeline upload `--dry-run` from Setonix;
   - `apply_migrations.py --verify`.
7. **Rotate `readonly` on a different day.**

What I can do: run the next-day checks, and grep every repo for a password literal or a cfg path not covered by the runbook beforehand. Choosing and entering the password stays with the owner.

## Order

1. **B first.** It changes how every future mito run reports failures, and it makes A's refusals visible.
2. **A.**
3. **C** on the next Monday.

---

## Record: B done (2026-11-04)

**Mito pipeline `inverts-dev`:** `8665897` → `ee4503d` (branch `loud-upload-failures`, merged and deleted). The Setonix production clone is pulled.
- **The two scripts:** `push_mtdna_assm_results.py` and `push_emma_annotation_results.py` exit 1 on a database error. Emma's "no annotation name" path counts as one.
- **The two modules:** `PUSH_QC_VALIDATOR` and `PUSH_ENA_VALIDATION_RESULTS` exit with their script's code.
- **The completion handler** (`PIPELINE_COMPLETION`) writes `sql_uploaded_data/FAILED_UPLOADS.tsv` from the execution trace and warns. It lists the last attempt per task, so a retry that succeeded is not listed.
- **The trace** gains a `workdir` field.

**Tests:**
- `tests/unit/test_upload_exit_codes.py`: real scripts against a closed port (exit 1), and the modules no longer force `exit 0`. The suite has the same 5 pre-existing failures (Biopython missing on this host).
- **Nextflow harness** `tests/upload_failure/` on Setonix (slurm, singularity, with `dead.cfg`, so nothing reached a database):
  - the upload failed (exit 1), was retried once and ignored;
  - the independent task completed;
  - the run ended "completed successfully, but with errored process(es)" with exit 0;
  - `FAILED_UPLOADS.tsv` named the task, its attempt, its exit code and its work dir, whose `*.upload.txt` holds the database error;
  - `-resume` re-ran only the failed upload, with the other task cached.

**Changed from the plan:**
- **Step 4** (the MultiQC "SQL Upload Summary" reading `FAILED_UPLOADS.tsv`) was dropped. That summary runs before the end of the run, so the file does not exist yet. The completion warning and the file cover it.
- **The real-data check** with an un-annotated sample was not run. The harness exercised the same path against an unreachable database.

**Found on the way: Setonix's default software environment changed.**
- **What changed:** since early November 2026 login nodes start in `pawseyenv/2026.11`. `nextflow/25.04.6` and `singularity/4.1.0-nompi` are no longer loadable there; they need `module load pawseyenv/2025.08` first, and Nextflow also needs `gcc-native/13.2` in that environment.
- **What breaks:** every launcher that loads them fails:
  - the draft `nextflow_run*.sh` and `scripts/*/run_*.sh`;
  - the mito `nextflow_run.sh`;
  - the mito `pawsey_profile.config`, which loads Singularity in every task through `module` and `beforeScript`.
- **The harness ran** only with a test-only override: `pawseyenv/2025.08` loaded in the launcher, and `process.module = 'pawseyenv/2025.08:singularity/4.1.0-nompi'` in the tasks.
- **Status:** not yet fixed in any repo.
