# Phase V.5 plan — cut over to `v2`

Status: **written and rehearsed 2026-10-13; not applied to live.** Source step:
`database_review.md` §9, Phase V.5. Previous step: V.4 and migration `043`, done. Next step:
V.6 (move `v2` into `public`), after a quiet period.

The cutover is migration `sql/044_v2_cutover.sql`, reversed by
`sql/revert/044_v2_cutover_revert.sql`. Its header explains each step. This document covers
what has to be true before it runs, how to run it, and how to check it worked.

## What changes for everyone

After `044`:

- Unqualified names (`sample`, `sequencing`, `summary`, ...) resolve to `v2` for every new
  session, through a database-level `search_path = v2, public`.
- `public.sample` and the other 19 replaced objects become `*_pre_v2`. A query that names
  them with `public.` fails with `relation "public.sample" does not exist`.
- The seven views that read them (`sample_view`, `embargo_assignment_view`, `lca_results_view`,
  `filtered_lca_view`, `lca_pivot_view`, `lca_validation_report_view`,
  `v_genome_size_comparison`) keep their names and read `v2`. Their row counts did not change
  in the rehearsal.
- Writing through `embargo_assignment_view` and `lca_validation_report_view` updates `v2`.
- `readonly` can read all of `v2`. `oceangenom_web` gets on `v2` exactly the grants it had on
  the objects that were replaced.
- **Sessions already open keep their old `search_path`.** They fail on every replaced table
  until they reconnect. That is intended: it is loud, and reconnecting fixes it.

## Hard prerequisites — do not cut over until all are done

1. **`import_data.py` must be switched off, and `import_v2.py` must be the only nightly
   writer.** This is the most important item. The rehearsal ran `import_data.py` against a
   cut-over copy. It does not fail cleanly:
   - It commits row by row and catches every error, so it overwrote about 2,200
     `v2.dna_extraction` rows and similar numbers in eight other lab tables with raw workbook
     values. Those writes skip `import_v2.py`'s quarantine and its value-conversion rules.
   - Only `sample` and `sequencing` failed outright, on columns that `v2` removes.
   - **It exited 0.** A cron job would report success.

   Remove it from `fetch_excel.sh` on Amphi before `044` runs, and confirm no other job
   calls it. Better still, make it refuse to start when `public.sample_pre_v2` exists, so a
   forgotten copy cannot do this either.
2. **Both nightly imports must be running again and caught up.** Since 2026-10-05,
   `public.rna_library_kinx` has not changed (see the review, V.5). `044` checks that the
   five pipeline-fed tables match row for row and refuses if they do not. It cannot check
   the lab tables, so run `scripts/reconcile_v2.py` (pre-flight, below).
3. **The three samplesheet scripts in `OceanOmics-OceanGenomes-ref-genomes` are updated**
   (handed over 2026-10-13, `~/v2_samplesheet_updates/`). They are safe to deploy before the
   cutover. The post-curation, genome-notes and RNA Kinnex builders under
   `/scratch/pawsey0964/lhuet/` need their one-line changes too. Details are in
   `docs/v2_cutover_dependencies.md`, "Functions".
4. **Whoever writes the mitogenome and LCA tables knows the date.** Those pipelines are not on
   this host. After cutover their unqualified writes land in `v2`, where `og_num` no longer
   exists on these tables and `content_hash` is set by `v2`'s own trigger. Confirm that their
   `INSERT`s do not name `og_num`, or they fail after the cutover.
5. **The web application's owner knows the date.** `oceangenom_web` reads `sample`,
   `sequencing`, `tissue`, `lca_validation` and `mitogenome_data`, all of which are replaced.
   Its access carries over, but any query that uses a removed column breaks, for example
   `sequencing.og_id` or the sixteen removed `sample` columns. Its `og_workflow_*` tables are
   untouched.
6. **DBeaver users are told**, in the same message, that most fixes are one word:
   `illumina_library` becomes `v_illumina_library_browse`, which brings back `og_id`.

## Pre-flight — the morning of

1. `bin/check_drift.py`. Expect only the three known `og_workflow_*` lines.
2. `scripts/audit_v2_dependents.py`. Expect the seven views above plus `summary`,
   `goat_species_v1` and `mitogenome_submission_view`, and no function marked UNREVIEWED.
   A new dependent view means `044`'s list needs updating first.
3. `scripts/reconcile_v2.py`. Expect zero UNEXPLAINED.
4. `pg_dump -Fc` of live. Restore it into a throwaway cluster and rehearse `044` there:
   apply, run the post-checks below, revert, re-apply. The 2026-10-12 rehearsal is not a
   substitute, because the point is to catch whatever has changed since.
   **Check disk first.** The host's root filesystem was at 100% during the 2026-10-13
   rehearsal (a restore plus WAL is about 1 GB), and that filesystem is shared with live
   tooling.
5. Confirm `import_data.py` is disabled (prerequisite 1).

## Apply

In a quiet window, with nobody mid-import:

```sh
PGOPTIONS="-c oceanomics.v2_cutover=go" bin/apply_migrations.py --target 044
```

Without the `PGOPTIONS` opt-in, `044` refuses to run. That stops an unrelated
`apply_migrations.py` run from cutting over by accident. It takes about 10 seconds on current
data. Most of that is the pipeline-table comparison. It holds exclusive locks on the renamed
tables until it commits.

## Post-checks

From a **new** session:

- `SHOW search_path` gives `v2, public`.
- `SELECT count(*) FROM public.sample` fails; `SELECT count(*) FROM sample` gives the `v2` count.
- Inside a transaction you roll back: update one row through `embargo_assignment_view` and one
  through `lca_validation_report_view`, and confirm that the `v2` row changed and the
  `_pre_v2` row did not.
- `SET ROLE readonly; SELECT count(*) FROM summary;` works.
- `bin/apply_migrations.py --verify` and `bin/check_drift.py`. The drift baseline describes
  `public` and now differs by the renames. Re-baseline with
  `scripts/export_schema_baseline.sh` once the cutover is accepted.
- The next nightly `import_v2.py` exits 0.

## Rollback

```sh
psql ... -f sql/revert/044_v2_cutover_revert.sql
psql ... -c "DELETE FROM schema_migrations WHERE filename = '044_v2_cutover.sql'"
```

The rollback takes effect immediately. **Anything written to `v2` after the cutover is not
copied back** to `public`. That includes nightly imports, pipeline runs and edits through the
two writable views. Carry those over by hand.

## Rehearsal record — 2026-10-13

On a restore of live from 2026-10-12, with `043` applied and `oceangenom_web` recreated with
live's grants:

| Check | Result |
|---|---|
| Apply | Clean, about 10 s |
| Seven rebound views: row counts, grants, triggers | Identical to before |
| `public.sample` | `relation "public.sample" does not exist` |
| `sample` from a new session | `v2.sample` |
| Write through `embargo_assignment_view` | Landed in `v2.sample`, not in `sample_pre_v2` |
| Write through `lca_validation_report_view` | Landed in `v2.lca_validation`, not in `_pre_v2` |
| `readonly`: `sample`, `summary`, `v_sequencing_browse`, `sample_view` | Readable |
| `oceangenom_web`: its five tables | Readable; `og_workflow_*` still writable; no new access |
| Replay with the ledger row deleted | No-op |
| Revert, then a full `pg_dump -s` against the pre-cutover copy | Identical, apart from `pg_dump`'s random session tokens |
| `import_v2.py` after cutover | Exit 0; same 702 open quarantine records |
| `import_data.py` after cutover | **Exit 0 while writing into nine `v2` lab tables.** Prerequisite 1 exists because of this. |

The rehearsal found two defects in the first draft of `044`, and both are fixed:

- `embargo_assignment_view` and `lca_validation_report_view` cannot take
  `CREATE OR REPLACE`, because `v2` changes column types from `varchar` to `text`. They are
  now dropped and recreated, and their triggers, grants and comments are restored and
  verified.
- `readonly`'s `USAGE` on `v2` was only copied from `public`'s schema grants. It is now
  granted explicitly.

The opt-in guard was added after the full rehearsal. It was tested on its own: it refuses
without the setting, and with the setting it goes on to the normal precondition checks. Each
cutover-morning rehearsal therefore covers the final file.
