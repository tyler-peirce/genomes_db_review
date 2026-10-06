# `v2` redesign — reference DDL, not a migration

Status: **written, re-reviewed 2026-10-05 against the live catalog, constraint-tested, not deployed.**
Nothing in this directory is applied by any tool. There is no `v2` schema on the live database.

These files were authored as a Sqitch project at the repo root. Sqitch was retired as a tool
on 2026-10-05 (`docs/migration_system_decision.md`), so they moved here rather than being
deleted.

## The direction is approved; this DDL is not yet cleared to deploy

**2026-10-05: `v2` is the agreed foundation for the schema** and the project is going ahead
with it (`database_review.md` open question 8). That is a decision about direction, not a
green light for these files. Two gates stand in front of them, tracked as **Phase V** in
`database_review.md` §9:

- ~~**Phase V.0 — open question 7 is the hard blocker.**~~ **Dropped 2026-10-05 at the
  owner's direction.** The fortnight of statement logging will not be run. Consumers that
  hardcode `public.` prefixes in their own queries are accepted breakage, to be fixed when
  they fail after cutover. See "Why it is no longer parked" below for what that trades away.
- **Phase V.1 — this DDL must be re-reviewed before any of it becomes a migration.**
  **Done 2026-10-05.** See `docs/v2_scaffold_design_review.md` revision 2. It found 40
  columns added by migrations `017`-`026` that this DDL had silently dropped, three types
  reverted to pre-migration-`022` definitions (two of which made the backfill *abort*), one
  primary key that live data cannot satisfy, two triggers dropped on the floor, and 100 rows
  the lab backfill was discarding without a quarantine record.

## Why it is no longer parked

Open question 7 — which downstream users and scripts query this database from outside
`genomes_db_review` and `OceanOmics-Database` — is **closed by decision rather than answered**,
2026-10-05. The fortnight of `log_statement = 'all'` logging will not be run. A consumer with
hardcoded `public.` prefixes will break at cutover and be fixed then.

**What that trades away, stated plainly:** the logging was the only proposed way to find a
broken consumer *before* breaking it. Without it the first signal is someone reporting a
failure. That is the accepted cost, and Phase V.5's design is what makes it tolerable —
superseded tables are renamed so they fail loudly rather than serving stale data.

**What it does not trade away, which is most of it.** Everything *inside* the database was
always discoverable from the catalog without waiting two weeks, and
`scripts/audit_v2_dependents.py` now does it in a second: ten dependent views, seven triggers,
and eleven functions that follow the `search_path` silently — including six
`build_*_samplesheet*` functions feeding Nextflow that nobody had looked at. V.0 would have
added only the external clients, which is exactly the category being accepted as breakage. So
dropping it costs considerably less than the "hard blocker" framing suggested, provided the
catalog sweep actually gets run.

Consequence for coverage: **17 live objects have no catch-up migration and will not get one
before cutover** — the 12 lab tables, the four live LCA tables, and `goat_species_v1`. Their
DDL is here, so writing `public` catch-up migrations for them would duplicate it and be thrown
away.

## When Phase V.1 clears them

These become numbered migrations in `sql/`, in plan order, applied with
`bin/apply_migrations.py`. Do not resurrect Sqitch to deploy them. Original plan order:

| # | File |
|---|---|
| 1 | `deploy/create_v2_schema.sql` |
| 2 | `deploy/create_v2_lab_tables.sql` |
| 3 | `deploy/create_v2_browse_views.sql` |
| 4 | `deploy/create_v2_quarantine.sql` |
| 5 | `deploy/create_v2_lca_tables.sql` |
| 6 | `deploy/create_v2_summary_view.sql` |
| 7 | `import_v2.py --stage-attempt-keys -e <workbook>` (in `OceanOmics-Database`) |
| 8 | `backfill_v2.sql` (data load, not DDL; re-runnable and idempotent) |

**Step 7 added 2026-10-06 (Phase V.2).** When two tubes in live share a
`(parent, attempt number)`, the backfill keeps the one the workbook carries. If the workbook
carries neither, or both, it keeps neither and quarantines them all. It used to keep the
alphabetically-first tube ID. Step 7 copies the workbook's attempt keys into
`v2.workbook_attempt_keys`, and the backfill refuses to run while that table is empty.

**Steps 5 and 6 swapped on 2026-10-05.** `v2.summary` now reads `v2.lca_validation` rather
than `public.lca_validation` (Phase V.1 item 3), so the LCA tables have to exist before the
summary view. The `-- requires:` headers carry the same dependency.

The `revert/` and `verify/` pairs are retained. The verify scripts are executable checks worth
porting into the migrations' own verification; Sqitch ran them automatically after each deploy
and `bin/apply_migrations.py` does not.

## Known defects — all three closed 2026-10-05, and six more found

The August list had three items. Phase V.1 closed all three and the re-diff that closed the
first one turned up six further defects, every one of which would have caused data loss or an
outright failure at cutover. Full account in `docs/v2_scaffold_design_review.md` revision 2.

**The three that were known:**

0. ~~`create_v2_lca_tables.sql`'s scope boundary is out of date.~~ **Fixed.** The `lca_new`
   premise is gone: that rebuild landed and those tables are the live LCA tables this file
   builds `v2` equivalents of. The stale `*_new` assertion in the verify script is replaced by
   assertions about the columns the re-diff found missing.
1. ~~The five `v2` LCA tables have DDL but no backfill.~~ **Written.** `backfill_v2.sql` now
   covers all seventeen tables; the LCA half loads 298,076 rows with zero quarantined.
2. ~~`v2.summary` reads `public.lca_validation`.~~ **Repointed** at `v2.lca_validation`. The
   qualification *was* deliberate, and documented twice in that file — but decision 1's
   premise expired when `create_v2_lca_tables.sql` started building the table. Note this
   **inverts build steps 5 and 6**: the LCA tables must now exist before the summary view.

**The six that were not:**

3. **40 columns added by migrations `017`–`026` were missing from the `v2` DDL** — 34 on
   `mitogenome_data` (the depth, trna-advisory, order-variant and annotation-integrity
   families), plus `content_hash` and `taxon_rank_db` on `lca` and `lca_raw_results`, and
   `validated_rank` and `lca_genus` on `lca_validation`. A cutover would have dropped all of
   them. This is the whole reason the re-review was required, and it is the largest finding.
4. **Three column types reverted migration `022`, and two of them abort the backfill.**
   `lca.top_confidence_score` and `lca_raw_results.confidence_score` were `real`; `022` had
   widened them to `double precision` precisely because `real` underflows below ~1.18e-38 and
   HiFi hits reach 5.27e-163. 30 live rows raise `value out of range` on a `::real` cast — not
   a precision loss, a hard failure. `blast_filtered_lca.taxon_id` was `integer`; it is `text`
   on live because 1,009 rows hold semicolon-separated multi-taxon lists.
5. **`v2.lca_raw_results`'s primary key is not satisfiable by live data.** It keyed on
   `lca_run_date`; 33 of 46,644 rows collide under it, because one BLAST accession can yield
   several HSPs in a run. Live's key is content-addressed (`017`) and has no collisions. Now
   matches live.
6. **`content_hash` had no source.** It is `NOT NULL` and in two keys, and the trigger that
   maintains it on live was not carried into `v2`. Added as `v2.lca_set_content_hash()`, with
   a pinned `search_path` so the hash cannot vary by caller.
7. **`v2.mitogenome_data.annotation` was `NOT NULL`**, which no finding asked for and live
   does not enforce. It would have quarantined 374 of 2,349 rows — all of them simply not yet
   annotated, which the data states unambiguously (all 374 have every annotation-derived field
   null; all 1,975 annotated rows have every one populated). Relaxed to nullable.
8. **The lab backfill was silently discarding 100 rows** — neither loaded nor quarantined,
   the one outcome decision 6 exists to prevent. Two causes: the registry guards tested
   `library_tube_id` alone while the FK is on `(library_tube_id, parent_id)`, which also
   *aborted* the whole backfill on current data; and attempt-key ties were filtered out with
   no quarantine record, despite the DDL's own comment promising they "quarantine for the lab
   to renumber". Both fixed.

**One gap left open, deliberately:** `mitogenome_submission_view` reads
`mitogenome_data.og_num`, which `v2` removes, and the August cutover audit never covered it.
It needs a `v2` equivalent or a rewrite. That is view-recreation work and belongs with the
other ten at Phase V.5, not here — but it is DDL that does not exist yet, so it is called out
rather than left to be discovered.

## Background

- `docs/v2_scaffold_design_review.md` — the design review, decisions 1–11.
- `docs/v2_cutover_dependencies.md` — what reads the twelve lab tables, and what each needs at
  cutover. Eleven views audited down to two needing a rebuild; the other eight are
  cutover-neutral and are captured in `sql/033_catchup_core_views.sql`.
- `docs/lab_key_strategy.md`, `docs/spreadsheet_column_gap_analysis.md`.
