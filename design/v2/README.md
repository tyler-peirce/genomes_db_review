# `v2` redesign — design history; the DDL has moved to `sql/`

Status: **promoted to numbered migrations 2026-10-06 (Phase V.3).** The DDL that used to live
here is now `sql/035`–`040`, with reverts in `sql/revert/`, applied with
`bin/apply_migrations.py`. The `deploy/`, `verify/` and `revert/` copies were deleted so there
is one copy to edit and to diff; git history has them. **Do not re-create them here.**

| Migration | Was | Content |
|---|---|---|
| `035_v2_schema.sql` | `deploy/create_v2_schema.sql` | the empty `v2` schema |
| `036_v2_lab_tables.sql` | `deploy/create_v2_lab_tables.sql` | 12 lab tables, the library registry, `prep_automation` |
| `037_v2_browse_views.sql` | `deploy/create_v2_browse_views.sql` | the 12 browse views |
| `038_v2_quarantine.sql` | `deploy/create_v2_quarantine.sql` | quarantine and `workbook_attempt_keys` |
| `039_v2_lca_tables.sql` | `deploy/create_v2_lca_tables.sql` | the 5 LCA / mitogenome tables and their `content_hash` trigger |
| `040_v2_summary_view.sql` | `deploy/create_v2_summary_view.sql` | `v2.summary`, `v2.goat_species_v1` |

What changed in the port, and nothing else did: every `CREATE` is guarded so a replay is a
no-op; the `prep_automation` seed is `ON CONFLICT DO NOTHING`; the two triggers are guarded on
`pg_trigger`; and each former verify script now runs inside its migration's transaction, so a
failed check rolls the deploy back. The emptiness and quarantine-count assertions hold only
at creation — these migrations must not be replayed after the V.4 backfill.

**The backfill is not a migration.** It moved to `scripts/backfill_v2.sql`: it needs
`import_v2.py --stage-attempt-keys` first, which `bin/apply_migrations.py` cannot run, and it
is designed to be re-run while the lab fixes rows, which a ledgered file cannot be. Phase V.4
runs it. **It ran on live 2026-10-06 (V.4)**, after two silent-loss fixes found by
`scripts/reconcile_v2.py`; see `docs/v2_reconciliation.md`.

`scripts/diff_v2_against_live.py` now reads the `sql/NNN_v2_*.sql` files.

Rehearsed 2026-10-06 on a fresh restore of live before promotion: apply, replay (ledger rows
deleted, re-applied as no-ops), revert `040`→`035` and re-apply, then stage, backfill twice
and import twice from `OceanGenomes_Database_261006.xlsx` — identical to the V.2 rehearsal (65
tied rows quarantined, 1,333 open quarantine, `rna_library_ilmn` / `ont_library` 389 / 98).
See `docs/phase_v3_plan.md`.

The sections below are the pre-promotion history of this DDL, kept because they record why it
looks the way it does. File paths in them refer to the deleted `deploy/` copies.

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

**One gap left open, deliberately — closed 2026-10-13 by `sql/043`.** `mitogenome_submission_view`
reads `mitogenome_data.og_num`, which `v2` removes, and the August cutover audit never covered it.
`043_v2_mitogenome_submission_view.sql` adds `v2.mitogenome_submission_view`, which takes
`og_num` from `v2.sample`; it is identical to the public view on live.

## Background

- `docs/v2_scaffold_design_review.md` — the design review, decisions 1–11.
- `docs/v2_cutover_dependencies.md` — what reads the twelve lab tables, and what each needs at
  cutover. Eleven views audited down to two needing a rebuild; the other eight are
  cutover-neutral and are captured in `sql/033_catchup_core_views.sql`.
- `docs/lab_key_strategy.md`, `docs/spreadsheet_column_gap_analysis.md`.
