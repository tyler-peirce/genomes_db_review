# Phase R runbook, R.0 to R.5: assembly relations, up to the `v3` merge

Status: **not started.** Written 2026-10-16. This is the "how" for
[`assembly_relations_plan.md`](assembly_relations_plan.md) (the "what and why"). Section numbers
like §3.6 refer to the plan. It stops before R.6, the merge of `v3` into `public`, which gets
its own runbook once R.5's gate is met.

**What is true when R.5 is done:**
- `public` is changed in two ways only:
  - 532 orphaned and `_rgj` LCA/ENA rows are archived and removed (`050`);
  - five FKs are declared between existing tables (`054`).
- Schema `v3` holds the full new mitogenome and draft-genome design, backfilled, kept current by
  a nightly sync, and proved equal to `public` through compatibility views.
- Both pipelines have a branch that writes the new tables, tested on a rehearsal restore.
- No production writer has changed yet. That happens on R.6's day.

## 0. Before you start

### 0.1 Rules for every step

These are the repo's standing rules (`sql/README.md`, `docs/database_change_checklist.md`):

- Every schema change is a numbered file in `sql/`, applied with `bin/apply_migrations.py`.
  There is no hand DDL.
- Each file opens with a prose header (why, what was rejected, guards, revert), and is wrapped in
  `BEGIN`/`COMMIT`. Each is idempotent, guarded with `to_regclass()`, and checks itself before
  `COMMIT`.
- Anything destructive refuses to run without an opt-in `PGOPTIONS` setting carrying the
  expected row count, as `049` does.
- Each file has a revert in `sql/revert/`.
- **Rehearse on a fresh restore of live before applying to live,** as V.6 did
  (`phase_v6_plan.md`, "Rehearsal record"): `pg_dump -Fc` live, restore into a throwaway
  cluster, recreate roles `readonly` and `oceangenom_web`, and run the real
  `bin/apply_migrations.py` there. Rehearse the revert too, then re-apply.
- After each live apply, run `bin/apply_migrations.py --verify`,
  `bin/check_drift.py --update` and `scripts/export_schema_baseline.sh`, then commit.
- Avoid 18:00 UTC, when `import_v2.py` runs from the `tyler` crontab, and check nobody is
  mid-write.
- Read-only checks on live use `PGOPTIONS="-c default_transaction_read_only=on"`.

### 0.2 Order and what can run in parallel

```text
R.0 measure ─┬─> R.1 (050) orphans ──> R.2 (051) mito in v3 ──> R.3 (052) draft in v3 ─┐
             │                                                                        ├─> R.5 writers + readers ──> gate for R.6
             └─> R.4 (053) sequencing_run in v3, (054) public FKs ────────────────────┘
S.1 import_v2 seq_type: independent, any time
```

- `054` touches only existing `public` tables, so it can land as soon as R.0 has re-measured
  it.
- `053` needs schema `v3`, so it lands after `051`.
- Migration numbers are fixed by order of landing. If something else lands first, renumber, as
  V.6 did.

### 0.3 Files this runbook creates

| Repo | File | Step |
|---|---|---|
| `genomes_db_review` | `docs/assembly_relations_r0_record.md` | R.0 |
| | `sql/050_clear_orphan_mito_children.sql`, `sql/revert/050_…_revert.sql` | R.1 |
| | `archive/mito_orphans_260909/` (CSVs, `MANIFEST.md`, `SHA256SUMS`) | R.1 |
| | `sql/051_v3_mitogenome.sql`, revert | R.2 |
| | `scripts/sync_v3.sql`, `scripts/sync_v3.sh` | R.2, R.3 |
| | `sql/052_v3_draft_genome.sql`, revert | R.3 |
| | `sql/053_v3_sequencing_run.sql`, revert | R.4 |
| | `sql/054_sample_fks.sql`, revert | R.4 |
| | `docs/assembly_relations_rehearsal_r5.md` | R.5 |
| `Oceanomics-OceanGenomes-Mitogenomes` | branch `phase-r-v3`: `bin/push_mtdna_assm_results.py`, `bin/push_emma_annotation_results.py`, two unit tests, reader fixes | R.5 |
| `OceanOmics-OceanGenomes-Draft-Genomes` | branch `phase-r-v3`: `bin/draft_genome_stats.py`, `tests/test_draft_genome_stats_backfill.py` | R.5 |
| `OceanOmics-Database` | `import_v2.py` (`seq_type`) | S.1 |

## R.0 — Measure, list readers, close the last unknowns

Goal: every figure the migrations assert, re-measured on live within a day of writing them, and
the four open checks answered. Output: `docs/assembly_relations_r0_record.md`, one section per
task, each with the query, the result and the date.

1. **Re-run the plan's §6 R.0 queries on live,** read-only. Record the numbers `050` will
   assert. They may have moved since 2026-10-16:
   - orphaned rows per child table (expected 1 / 8 / 74 / 443 / 5 / 0), plus `_rgj` ENA
     attempts with an existing assembly (expected 1, OG562);
   - `mitogenome_data` rows (2,371) and annotated rows;
   - `draft_genomes` rows (1,720) and rows with any value per §4.2 table;
   - draft → Illumina run matches with the `mach` rule (expected: every draft at least one;
     1,715 one, 5 two);
   - mito assembly → sequencing matches (1,977 / 1,985 `(og_id, seq_date)` on 2026-10-16), by
     `tech`. Write down the `tech` → `technology` mapping that gives that match: `ilmn` →
     `Illumina`, `hifi` → `PacBio HIFI`/`PacBio`, `hic` → `Hi-C`. `051` uses it.
   - BUSCO vs gfastats N50, with the L50 bounds test.
2. **`ENA-draft-genomes`:** clone it. Record:
   - every SQL statement that touches `draft_genomes`, and its `ON CONFLICT` target;
   - that it reads none of the 17 columns dropped in §4.3.

   If it reads any, stop and raise it before `052`.
3. **Readers that assume one row per assembly** (§3.7). Go through each reader of
   `mitogenome_data` in the mitogenome pipeline and note whether it selects or groups without
   `annotation`:
   - `bin/`: `audit_ena_readiness.py`, `backfill_ena_specimen_accessions.py`,
     `build_source_modifiers.py`, `compile_held_completeness.py`, `compile_upload_report.py`,
     `depth_tsv.py`, `mitogenome_assembly_summary.py`, `prepare_ena_metadata.py`;
   - `modules/local/mitogenome_coverage/main.nf`;
   - `subworkflows/local/{ena_submission_prep,mitogenome_qc,mitogenome_assembly/getorganelle,upload_results_mito}/main.nf`;
   - `workflows/oceangenomesmitogenomes.nf`, `qc_only_from_annotations.nf`.

   In `public`, list the views that read it, from `pg_depend` (`summary`,
   `mitogenome_submission_view` and others). Output: a table of reader, keyed on annotation
   (yes/no), and the fix needed. R.5 does the fixes.
4. **BUSCO JSONs** (§4.2): on Pawsey, open the short-summary JSON for OG2649 260909 (value is a
   count) and OG2033 251215 (value equals gfastats). Record the BUSCO version and the exact keys
   holding N50 and L50. This decides the `BUSCO_KEYMAP` fix in R.5.
5. **Triage** the 7 `hifi_reads_qc` and 22 `hic_reads_qc` rows whose `run_id` is not in
   `sequencing`, and the 30 `raw_data` rows with a blank `og_id`. Record each as "lab fixes the
   workbook", "typo we can map" or "leave unlinked". `053` reports on these, and `054`'s
   `raw_data` FK waits on the blanks.

**Gate:** the record is committed, and every number `050`–`054` will assert is in it.

## R.1 — Clear the orphaned LCA and ENA rows (`050`)

Removes the 532 rows in §3.6 from `public`: 531 orphans plus OG562's `_rgj` ENA attempt.

### Archive first

1. Build the key list in a scratch SQL file from the R.0 queries: the eight orphan annotations
   plus the four `_rgj` ENA `full_seqid`s.
2. Export every affected row, all columns, with `\copy (SELECT … ORDER BY <pk>) TO … CSV HEADER`,
   one file per table, into `archive/mito_orphans_260909/`.
3. Compute each table's fingerprint the way `049` does:
   `md5(string_agg(to_jsonb(t)::text, E'\n' ORDER BY <pk>))`.
4. Write `MANIFEST.md` (what, why, row counts, fingerprints) and `SHA256SUMS`.

### `sql/050_clear_orphan_mito_children.sql`

Model it on `049`:

- **Header:** why (§3.6, owner decisions 6 and 10), what was rejected (stubs, which the first
  draft proposed), the guards, the archive and the revert.
- **Keys:** a temp table of explicit keys, not a generic `NOT EXISTS`. A future orphan must not
  be swept up by a replay.
  - LCA: `(og_id, tech, seq_date, code, annotation)` for the 3 replaced annotations (OG2628,
    OG3050, OG3060 `getorg1770.mitos2110`).
  - ENA: the 6 `ena_validation_attempts.full_seqid`s: OG2951 and OG3000
    `getorg1770.mitos2110`, the three 260909 `_rgj` codes, and OG562's.
- **Guards, before any delete:**
  1. Replay: if none of the keyed rows is present, return.
  2. Opt-in: refuse unless `oceanomics.clear_mito_orphans = 532`.
  3. Per-table counts equal the archived ones: 1 / 8 / 74 / 443 / 6 / 0.
  4. The LCA keys are still orphaned: no `mitogenome_data` row has that
     `(assembly, annotation)`. If one has reappeared, it is not an orphan any more, so refuse.
  5. Per-table md5 equals the archive's. If a writer has touched the rows since, re-export
     first.
- **Copy into the archive schema:** `CREATE SCHEMA IF NOT EXISTS pre_v3_archive`, then
  `CREATE TABLE pre_v3_archive.<table>_orphans_260909 AS SELECT …` for each of the five
  tables. These copies are what the revert restores from.
- **Delete,** then verify inside the transaction that 0 keyed rows remain and that the R.0
  orphan query returns 0 for every child table.
- **Not touched:** the 35 `_rgj` assemblies and their LCA rows. Assert their counts are
  unchanged (25 / 58 / 366 / 715).

### `sql/revert/050_…_revert.sql`

1. Re-insert from `pre_v3_archive.<table>_orphans_260909`, then drop those tables.
2. Watch two things:
   - **`ena_validation_attempts.id` is `GENERATED ALWAYS AS IDENTITY`.** Insert with
     `OVERRIDING SYSTEM VALUE`. Its `og_num` is a generated column, so leave it out of the
     column list.
   - **`lca` and `lca_raw_results` have the `lca_set_content_hash` trigger.** Rehearsal must show
     that a re-insert reproduces the archived hash exactly, i.e. the md5 matches. If it doesn't,
     disable the trigger for the insert, inside the revert.
3. Verify the md5s match the archive.

### Rehearse, then apply

```sh
# rehearsal restore: apply, check, revert, compare, re-apply, replay
PGOPTIONS="-c oceanomics.clear_mito_orphans=532" bin/apply_migrations.py
# live, after a clean rehearsal
PGOPTIONS="-c oceanomics.clear_mito_orphans=532" bin/apply_migrations.py
```

**Post-check on live:**
- orphan query 0 on all six tables;
- no `_rgj` row in `ena_validation_attempts`;
- `ena_validation_latest`, `ena_submission_status` and `mitogenome_submission_view` no longer
  show the six;
- the next mitogenome pipeline run exits 0.

## R.2 — Mitogenome tables in `v3` (`051`)

### `sql/051_v3_mitogenome.sql`

1. **Schema and grants.** Create `v3`. Grant `readonly` `USAGE` on it and `SELECT` on all its
   tables, with default privileges so later objects are covered too.
2. **Tables,** per §3.1–3.4, in `v3`, FKs into `public.sample` / `public.sequencing` only:
   - `mito_assembly`, `mito_assembly_depth` and `mito_annotation`, the last with
     `is_selected`, `selected_by`, `selected_at` and the partial unique index;
   - `mito_gene`: seed 39 genes, with `gene_class`, the legacy length column name and, for the
     15 protein-coding genes, the translated-length column name. Write the seed explicitly in
     the file; do not derive it from `information_schema`.
   - `mito_annotation_gene`;
   - `mito_assembly_run` (`assembly_id`, `sequencing_id`), FK to `public.sequencing`.

   Column types copy `public.mitogenome_data` exactly. Take each from `\d+` on live, not
   from memory.
3. **Backfill,** in one statement block, keyed on natural keys so `scripts/sync_v3.sql` can reuse
   it:
   - `mito_assembly`: all 2,371 rows;
   - `mito_assembly_depth`: where `depth_method` is a measured method (`remap_full_v1` today,
     1,954 rows);
   - `mito_annotation`: where `annotation IS NOT NULL` (1,997), with `is_selected = false`;
   - `mito_annotation_gene`: unpivot with `LATERAL (VALUES …)` from the `mito_gene` list,
     keeping non-NULL values (72,063 rows on 2026-10-15);
   - `mito_assembly_run`: by `(og_id, seq_date)` and the R.0.1 `tech` mapping.
4. **Views:**
   - `v3.v_mito_annotation_genes`: one row per annotation, genes pivoted.
   - `v3.mitogenome_data`: today's 102 columns, in today's order. One row per
     (assembly, annotation), plus unannotated assemblies. It does not show `is_selected`.
   - `v3.mitogenome_submission_view`: rebuilt from today's definition
     (`pg_get_viewdef('public.mitogenome_submission_view')`), joining on `annotation_id`.
   - `v3.rebuild_mito_gene_views()`: regenerates the two pivoting views from `mito_gene`.
5. **Checks before `COMMIT`:**
   - `v3.mitogenome_data` `EXCEPT ALL` `public.mitogenome_data` (102 columns), both ways, 0
     rows;
   - `v3.mitogenome_submission_view` equals `public.mitogenome_submission_view` the same way;
   - every row of `lca`, `lca_raw_results`, `blast_filtered_lca`, `lca_validation`,
     `ena_validation_attempts` and `ena_submissions` resolves to exactly one
     `v3.mito_annotation` by its five natural columns. This is 0 unresolved only because `050`
     ran.
   - 0 `mito_annotation` rows with `is_selected`.
6. **Revert:** `DROP SCHEMA v3 CASCADE`, valid only while `052`/`053` are not applied. Their
   reverts run first.

### `scripts/sync_v3.sql` and `scripts/sync_v3.sh`

- The sync re-runs `051`'s backfill as upserts on the natural keys, so ids stay stable. It also
  deletes `v3` rows whose `public` source has gone: assemblies, annotations, gene rows no longer
  present, depth rows now `not_measured`.
- Then it re-runs the `051` equality check and exits non-zero on any difference.
- `sync_v3.sh` runs it with the same credentials resolution as `bin/`. Add it to the `tyler`
  crontab at **19:00 UTC**, after the 18:00 import and before the next morning's drift check.
  Write a failure marker like `~/log/fetch_excel.FAILING`, so a broken sync is visible.
- **The sync is the only thing that writes `v3` on live.**

### Rehearse, then apply

1. On the rehearsal restore, check that:
   - `051` applies, its checks pass, `sync_v3.sql` is a no-op straight after, and the revert
     leaves no `v3` object;
   - the sync stays clean after simulated pipeline changes. Update one `mitogenome_data` row's
     depth, change another's annotation (annotator and gene lengths), add a new assembly, and
     delete one. Then sync, and the equality check must pass.
2. Apply to live and run the sync once by hand.
3. Turn on the cron.

## R.3 — Draft-genome tables in `v3` (`052`)

### `sql/052_v3_draft_genome.sql`

1. **Tables,** per §4.1–4.2, with types copied from live `draft_genomes`:
   - `draft_genome`, with `og_num` generated as on today's table:
     `(SUBSTRING(og_id FROM 3))::integer`;
   - `draft_genome_run`, plus the trigger that rejects a non-Illumina `sequencing_id`;
   - the nine process tables: `draft_fastp`, `draft_genomescope` (with `host_assembly_size`,
     `host_assembly_fraction` and `genomescope_version`), `draft_tiara`,
     `draft_contamination` (`num_contigs_lt_500bp`), `draft_busco`, `draft_merqury`,
     `draft_gfastats`, `draft_depthsizer` and `draft_submission`.
2. **Backfill:**
   - a process row only where its block has any non-NULL value;
   - `genomescope_version` from whether the extended columns are filled;
   - `draft_genome_run` by `(og_id, seq_date)`, Illumina, instrument matching `mach`;
   - `COMMENT ON TABLE v3.draft_depthsizer` saying it is retired and closed, and a comment on
     `draft_busco.scaffold_n50` / `contigs_n50` saying they are unreliable (§4.2).
3. **Views:**
   - `v3.draft_genomes`: today's columns less the 17 in §4.3 (103), in today's order;
   - `v3.v_genome_size_comparison`: today's definition, re-pointed;
   - `v3.v_draft_genome_status`, without DepthSizer.
4. **Checks before `COMMIT`:**
   - `v3.draft_genomes` against `public.draft_genomes` on the 103 columns, `EXCEPT ALL` both
     ways, 0 rows;
   - `v3.v_genome_size_comparison` equal the same way;
   - every draft has at least one `draft_genome_run` row;
   - 0 all-NULL rows in any process table.
5. **Revert:** drop the draft objects from `v3`, leaving `051`'s.

**`scripts/sync_v3.sql`:** add the draft half the same way. It skips `draft_depthsizer` after
the backfill and asserts its row count never changes.

**Rehearse and apply** as in R.2. The cron already runs the whole script.

## R.4 — Run entity in `v3`; FKs between existing tables (`053`, `054`)

### `sql/053_v3_sequencing_run.sql`

1. `v3.sequencing_run` (`run_id` PK, `instrument`, `run_date`, `mach`, `initial`), seeded from
   the distinct `public.sequencing.run_id` (214 on 2026-10-16). Parse `mach`, `seq_date` and
   `initial` from the ID, as `MACH_DATE_INITIAL`. A run ID that does not parse gets NULL parts
   and is listed by the check below, not rejected.
2. **Add no FK.** `public` must not point into `v3` before the merge. Instead, add a view,
   `v3.v_sequencing_run_fk_readiness`, with one row per would-be FK:
   - `sequencing`, `raw_data`, `hifi_reads_qc` and `hic_reads_qc` → `sequencing_run`;
   - rows that would fail, and their `run_id`s.

   R.7 adds the FKs when this shows 0, or the R.0.5 triage has been dealt with.
3. Add `sequencing_run` to the sync, as an upsert on `run_id`.

### `sql/054_sample_fks.sql`

FKs between tables already in `public`. Nothing new is created, so this can land any time after
R.0:

| FK | Rows | Expect |
|---|---:|---|
| `ena_specimen_accessions(og_id) → sample(og_id)` | 2,848 | all match |
| `og_workflow_recommendation(og_id) → sample(og_id)` | 0 | trivially valid |
| `og_workflow_assignment_log(og_id) → sample(og_id)` | 0 | trivially valid |
| `og_workflow_notification(og_id) → sample(og_id)` | 0 | trivially valid |
| `raw_data(og_id) → sample(og_id)` | 8,010 | **only if** the 30 blank `og_id`s are resolved (R.0.5); otherwise leave it out of `054` |

- Each FK is `ADD CONSTRAINT … NOT VALID`, then `VALIDATE CONSTRAINT`, in the same file. Each
  child column gets an index if it has none.
- No `ON DELETE` action, matching the other FKs to `sample`.
- **The `og_workflow_*` tables belong to OceanGenom_Web.** Check that the app does not insert an
  `og_id` before its `sample` row exists. The tables are empty, so the first insert after `054`
  is the test.
- **Revert:** drop the constraints and the indexes `054` created.

## R.5 — Writers and readers, tested against `v3`

Nothing here deploys to production. Both pipelines get a `phase-r-v3` branch that is merged and
deployed on R.6's day.

### R.5.1 Mitogenome pipeline (`Oceanomics-OceanGenomes-Mitogenomes`)

- **`bin/push_mtdna_assm_results.py`:**
  - `INSERT … ON CONFLICT (og_id, tech, seq_date, code)` into `mito_assembly`,
    `RETURNING assembly_id`;
  - depth goes to `mito_assembly_depth`, `ON CONFLICT (assembly_id)`. `not_measured` writes
    nothing.
  - `decide_write` and the depth-only path keep their meaning. Only their targets change.
- **`bin/push_emma_annotation_results.py`:**
  - look up `assembly_id`;
  - upsert `mito_annotation` on `(assembly_id, annotation)`;
  - `DELETE` that annotation's `mito_annotation_gene` rows, then insert the new ones;
  - all in one transaction. **It never reads or writes `is_selected`.**
- **Unqualified table names only, no `v3.`** The schema comes from `search_path`.
- **Tests:**
  - `tests/unit/test_push_mtdna_assm_decide_write.py`: same cases, new targets.
  - `tests/unit/test_push_emma_column_parity.py`: becomes "every annotation output column lands
    in exactly one of `mito_annotation` and `mito_annotation_gene`".
  - Add one test: a second annotation of the same assembly inserts a second row, and the first
    row is unchanged.
- **Reader fixes from R.0.3:** each reader that assumes one row per assembly groups or chooses
  in its own logic. None may use `is_selected`.
- **Not in R.5:** `push_lca_*`, `push_species_validation.py` and
  `push_ena_validation_results.py`. They keep writing the natural columns until R.7.

### R.5.2 Draft pipeline (`OceanOmics-OceanGenomes-Draft-Genomes`)

All in `bin/draft_genome_stats.py`:
- `FAMILY_COLUMNS` becomes a map from family to the target table(s) and columns:
  - `busco` → `draft_busco` (all 15);
  - `decontamination` → `draft_tiara` and `draft_contamination`, with `num_contigs` written as
    `num_contigs_lt_500bp`;
  - `assembly` → `draft_genomescope`, including the two host columns.
- `upsert_record()`:
  - `INSERT INTO draft_genome (og_id, seq_date, mach, initial) … ON CONFLICT (og_id, seq_date)`,
    `RETURNING draft_id` (`mach`/`initial` only from `fastp`; others `DO NOTHING` on them);
  - then upsert each target table `ON CONFLICT (draft_id)`, updating only the columns the
    record carries. Today's merge-by-upsert behaviour, where two records for the same draft
    merge into one row, must survive.
- `draft_genome_run`: written at the `fastp` step from the run ID in the filename
  (`MACHINE_DATE_INITIAL`). The trigger rejects a non-Illumina run, so a Hi-C draft fails at
  write time.
- `fetch_database_record()` keeps reading `draft_genomes`, which is now the view. The view keeps
  the old column names, including `num_contigs`, so build its column list from the legacy
  names, not from the new table map.
- `BUSCO_KEYMAP`: apply the R.0.4 finding. Either stop mapping the N50 keys, or map the
  version-specific keys correctly.
- `tests/test_draft_genome_stats_backfill.py`: assert rows land in the right tables, and that
  two records for one draft merge.
- The six `push_*_to_sqldb.py` CLIs and the Nextflow modules need no change.

### R.5.3 Rehearsal with the new writers

On a fresh restore of live with `050`–`054` applied. Record the results in
`docs/assembly_relations_rehearsal_r5.md`.

All of this runs with `PGOPTIONS='-c search_path=v3,public'`:

1. **Mitogenome:**
   - run both push scripts on real outputs of one recent sample;
   - run the annotation push twice for one assembly, with different annotators;
   - expect two `mito_annotation` rows, both visible in `mitogenome_data`, none selected, the
     first unchanged.
2. **Draft:**
   - run the six CLIs on one sample's published outputs, and `backfill_draft_genome_stats.py`
     on a small archive;
   - expect `v3.draft_genomes` for that draft equal to what the old code writes to
     `public.draft_genomes` on the same restore from the same inputs. Compare row by row.
3. **Failure cases:**
   - a Hi-C run ID into `draft_genome_run`: rejected;
   - an old writer pointed at a copy where `mitogenome_data` is a view: fails with "cannot
     insert into view". Simulate the R.6 rename on the restore.
4. **`is_selected` isolation:**
   - set it on one annotation, and confirm no view's output changes except
     `v_mito_annotation_genes`;
   - check `pg_depend` and a grep of both branches for any other reference.

### R.5.4 Readers on live, read-only

On live, with `PGOPTIONS='-c default_transaction_read_only=on -c search_path=v3,public'`, run:
- the mitogenome readers from R.0.3, with fixes applied: `prepare_ena_metadata.py`,
  `audit_ena_readiness.py`, `compile_upload_report.py`, `mitogenome_assembly_summary.py`, …;
- the samplesheet builders;
- `SELECT` from `summary`, `v_genome_size_comparison` and `mitogenome_submission_view`.

Compare each output with the same run using the default `search_path`. They should be
identical, because no assembly yet has two annotations. Any difference is a bug in a `v3` view.

## S.1 — `import_v2.py` derives `seq_type` again (owner decision 13)

Independent of R. In `OceanOmics-Database`:

1. Derive `seq_type` from `technology` and the tube suffix with the plan's §2.3 rule, ported
   from `import_data.py` lines 135–165. A row matching no branch is quarantined, never raised.
   Leave `name_convert_v2.py:30`'s removed mapping removed.
2. Dry-run against live:
   - 193 updates, all `NULL` → `Illumina`;
   - 0 changes to the 4,267 rows that already have a value;
   - no new quarantine records.
3. Let the 18:00 run apply it. Next morning, check: `SELECT count(*) FROM sequencing WHERE
   seq_type IS NULL` is 0.

## Gate for R.6 (not part of this runbook)

All of these hold:

- The sync has run clean every night for at least a week (owner's call on the length).
- The R.5.3 rehearsal is recorded and all its checks passed.
- Every R.0.3 reader is fixed on its branch, and R.5.4 showed identical output.
- `ENA-draft-genomes` is accounted for (R.0.2), with a branch if it writes `draft_genomes`.
- The downstream ENA owner has been asked about `annotation_id` on `ena_submissions` (R.7). R.6
  does not need the answer, but R.7 does.
- `bin/check_drift.py` is clean, and `--verify` is clean.

Then write the R.6 runbook: the merge (§6.1), with V.6's rehearsal shape.
