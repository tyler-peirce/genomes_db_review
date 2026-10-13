# Phase V.5 plan — cut over to `v2`

Status: **applied to live 2026-10-13 06:06:49–06:07:00 UTC as migration `045_v2_cutover.sql`.** Pre-flight, rehearsal on a fresh copy of live, and post-checks all passed; see the record at the end. Source step:
`database_review.md` §9, Phase V.5. Previous step: V.4 and migration `043`, done. Next step:
V.6 (move `v2` into `public`), after a quiet period.

The cutover is `sql/cutover/v2_cutover.sql`, reversed by
`sql/cutover/v2_cutover_revert.sql`. Its header explains each step. It stays outside the
numbered sequence until the day, because the migration runner applies pending files in order
and a numbered cutover would block every migration written after it. It gets its number
when it runs; see Apply. This document covers
what has to be true before it runs, how to run it, and how to check it worked.

## What changes for everyone

After the cutover:

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

1. **Done 2026-10-13: `import_v2.py` is the only nightly writer.** `fetch_excel.sh` runs
   `import_v2.py` alone, from the `tyler` crontab at 18:00 UTC, and the 2026-10-13 run exited 0.
   `import_data.py` no longer runs. Kept for the record: the rehearsal ran `import_data.py`
   against a cut-over copy, and it overwrote about 2,200 `v2.dna_extraction` rows and similar
   numbers in eight other lab tables with raw workbook values, skipping quarantine and the
   value rules, and **exited 0**. Do not reinstate it.
2. **Since 2026-10-13, `public`'s lab tables are frozen and readers see stale data.** Nothing
   writes them now, so DBeaver users, the web app and `public.summary` see the lab as it was on
   2026-10-05 until the cutover. On 2026-10-13 `v2.sample` held 3,401 samples and
   `public.sample` 3,294. **This argues for cutting over soon.** It also means
   `scripts/reconcile_v2.py` no longer measures anything useful: it compares `v2` with a
   `public` that has stopped moving, so it now reports new data as differences. The
   pre-flight uses the import's own result instead.
3. **The three samplesheet scripts in `OceanOmics-OceanGenomes-ref-genomes` are updated**
   (handed over 2026-10-13, `~/v2_samplesheet_updates/`). They are safe to deploy before the
   cutover. The post-curation, genome-notes and RNA Kinnex builders under
   `/scratch/pawsey0964/lhuet/` need their one-line changes too. Details are in
   `docs/v2_cutover_dependencies.md`, "Functions".
4. **The mitogenome / LCA pipeline runs from branch `v2-cutover`** of
   `Oceanomics-OceanGenomes-Mitogenomes` (commit `9d70d01`, local, not pushed). Checked
   2026-10-13 by running `EXPLAIN` on every statement it sends against live under both
   `search_path`s. Five fail under `v2`; the branch fixes all five, and they still work before
   the cutover, so it can be deployed now:
   - `sequencing` reads by `og_id` (`create_samplesheet.py`, `build_source_modifiers.py`, the
     `HIFI_DATE_QUERY` module) and by `hic_library_tube_id` (`create_samplesheet.py`,
     `HIC_DATE_QUERY`) use `v_sequencing_browse` when it is visible. On live, every OG's latest
     PacBio date and every HiC tube's runs come out the same either way.
   - The `lca` and `lca_raw_results` upserts named the constraints `lca_content_unique` and
     `lca_raw_results_content_unique`, which `v2` does not have: it keys the same columns
     under `lca_pkey` and `lca_raw_results_pkey`. They now name the columns. On a scratch
     copy a repeated result refreshes one row's run date in either schema.
   - Every column the pipeline writes exists in `v2`, none of them is `og_num`, and `v2`'s
     content-hash trigger is identical to `public`'s.
   - The pipeline has not written since 2026-10-05, before the backfill, so its five tables
     match `v2` row for row and the cutover's precondition passes.

   Found along the way, not cutover blockers:
   - **The GenBank coordinates for OG835, OG836 (HiC and HiFi), OG840 and OG841 were wrong.**
     `build_source_modifiers.py` read the Exmouth Gulf degree-minute values as
     "22.00000 S 6.49300 E". Under `v2` it gets the converted decimals and produces the right
     coordinates. If those records were submitted, they need correcting at ENA / GenBank. In
     total, 46 samples whose coordinates Excel had turned into dates now produce coordinates,
     where before they produced none.
   - **OG184 (Elat) stops producing coordinates.** The workbook's "29° 33' N" becomes +29.55,
     which the script deliberately refuses: the lab also types southern latitudes unsigned.
     The original text, N included, is in `value_conversions`.
   - The pipeline carries its own copy of `sql/001`–`026` and its own runner,
     `bin/apply_ena_migrations.py`, which writes the same `schema_migrations` ledger. Its
     `026` differs from this repository's ledgered one (`026` was amended before ledgering, in
     Phase A), and several of its files name `public.` tables explicitly. Do not run it;
     `docs/migration_system_decision.md` makes this repository's `sql/` the only migration
     system.
5. **The web application, OceanGenom_Web, is checked against `v2` before the date.** What
   the database shows about it (2026-10-13):
   - It runs on `146.118.122.158`, connects as `oceangenom_web` with
     `application_name = 'oceangenom_web'`, and holds a pool of open connections. It
     reconnects with the new `search_path` only when that pool recycles, so **restart it right
     after the cutover**.
   - It reads `sample`, `sequencing`, `tissue`, `lca_validation` and `mitogenome_data`, which
     are all replaced. It also reads `draft_genomes`, `ena_submissions`, `master_species`,
     `ref_genomes` and `ref_genomes_assembly_uploads`, which are not.
   - **It writes one column of a replaced table: `sample.workflow`**, through a column-level
     `UPDATE` grant. That is its "Unassigned Workflows" tab's Assign button. The cutover carries
     the grant over to `v2.sample.workflow` and checks it. The first draft did not, and the
     button would have failed with `permission denied`.
   - It also writes its three `og_workflow_*` tables and five `master_species` columns. None
     of these is affected.
   - **Its code is not on this host, so which columns it reads is unknown.** The ones that
     disappear:
     - `sequencing`: `og_id`, `og_num` and the five per-technology library tube IDs. Use
       `v_sequencing_browse`, or join through `library_tube_id`.
     - `sample`: `tissues`, `extracted`, `extraction_queue`, the eight `*_status` and
       `*_sequencing` rollups, `summary_comments`, `ont_num`, `illumina_public`,
       `depth_collection` and `lengthtl_and_lengthfl`. The last two became `depth_min_m` /
       `depth_max_m` and `length_tl_mm` / `length_fl_mm` / `length_unspecified_mm`.
     - `tissue`: `field_id` and `og_num`.
     - `lca_validation`, `mitogenome_data`: `og_num`.

     The rollups are available from the `summary` view, which the web role is not granted
     today.

     Its owner should run its queries against `v2` before the date: a session with
     `SET search_path = v2, public` sees exactly what the app will see.
   - **`sample.workflow` is owned by the web app** (owner decision 2026-10-13). Both
     importers now set it only when a sample is first created and never overwrite it
     afterwards (`INSERT_ONLY` in `import_v2.py`; `queries.upsert_sample` for
     `import_data.py`). Until the cutover the app writes `public.sample`, so the cutover copies any
     differing `workflow` from `public` to `v2`, and the revert copies it back.
     `scripts/reconcile_v2.py` treats a difference as explained only where the app logged an
     assignment. **Tell the lab** that changing the Workflow column in the workbook no longer
     changes an existing sample; it is only used for new ones.
6. **DBeaver users are told**, in the same message, that most fixes are one word:
   `illumina_library` becomes `v_illumina_library_browse`, which brings back `og_id`.

## Pre-flight — the morning of

1. `bin/check_drift.py`. Expect no drift. It has been clean since 2026-10-13, when the `og_workflow_*` tables were captured in `044`.
2. `scripts/audit_v2_dependents.py`. Expect the seven views above plus `summary`,
   `goat_species_v1` and `mitogenome_submission_view`, and no function marked UNREVIEWED.
   A new dependent view means the cutover's list needs updating first.
3. The previous night's import: `~/lab_db_updates/out.YYMMDD.txt` shows a completed run and
   `~/log/fetch_excel.FAILING` does not exist. (`scripts/reconcile_v2.py` no longer applies;
   see prerequisite 2.)
4. `pg_dump -Fc` of live. Restore it into a throwaway cluster and rehearse the cutover there:
   apply, run the post-checks below, revert, re-apply. The 2026-10-12 rehearsal is not a
   substitute, because the point is to catch whatever has changed since.
   **Check disk first.** The host's root filesystem was at 100% during the 2026-10-13
   rehearsal (a restore plus WAL is about 1 GB), and that filesystem is shared with live
   tooling.
5. Confirm `import_data.py` is still not scheduled (`crontab -l`), and the pipeline runs from
   `v2-cutover` (prerequisite 4).

## Apply

In a quiet window, with nobody mid-import:

```sh
N=$(ls sql | grep -E '^[0-9]{3}_' | tail -1 | cut -c1-3); N=$(printf '%03d' $((10#$N + 1)))
git mv sql/cutover/v2_cutover.sql sql/${N}_v2_cutover.sql
git mv sql/cutover/v2_cutover_revert.sql sql/revert/${N}_v2_cutover_revert.sql
git commit -m "Number the v2 cutover as ${N}"
PGOPTIONS="-c oceanomics.v2_cutover=go" bin/apply_migrations.py
```

Apply any other pending migration first, so the cutover is the only one pending.

Without the `PGOPTIONS` opt-in, the cutover refuses to run. That stops an unrelated
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
psql ... -f sql/revert/NNN_v2_cutover_revert.sql
psql ... -c "DELETE FROM schema_migrations WHERE filename = 'NNN_v2_cutover.sql'"
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
| `oceangenom_web`: `UPDATE (workflow)` on `v2.sample` (re-test 2026-10-13, schema-only restore) | Granted. Updating any other column is still refused. Revert identical; re-apply clean |
| Replay with the ledger row deleted | No-op |
| Revert, then a full `pg_dump -s` against the pre-cutover copy | Identical, apart from `pg_dump`'s random session tokens |
| `import_v2.py` after cutover | Exit 0; same 702 open quarantine records |
| `import_data.py` after cutover | **Exit 0 while writing into nine `v2` lab tables.** Prerequisite 1 exists because of this. |

The rehearsals found three defects in the first draft of the cutover, and all three are fixed:

- `embargo_assignment_view` and `lca_validation_report_view` cannot take
  `CREATE OR REPLACE`, because `v2` changes column types from `varchar` to `text`. They are
  now dropped and recreated, and their triggers, grants and comments are restored and
  verified.
- `readonly`'s `USAGE` on `v2` was only copied from `public`'s schema grants. It is now
  granted explicitly.
- Column-level grants were not copied, because they live in `pg_attribute`, not in the table's
  ACL. That would have broken the web app's Assign button. They are now copied and
  verified, and a column grant on a column that `v2` removes stops the cutover.

The opt-in guard was added after the full rehearsal. It was tested on its own: it refuses
without the setting, and with the setting it goes on to the normal precondition checks. Each
cutover-morning rehearsal therefore covers the final file.

## Cutover record — 2026-10-13

| Step | Result |
|---|---|
| Pre-flight: drift, ledger | No drift; 45 applied, nothing pending |
| Pre-flight: dependents | The same 10 views; every function has a disposition |
| Pre-flight: import | `out.261013.txt` complete; no `fetch_excel.FAILING` |
| Pre-flight: sessions | 4, all idle: two `oceangenom_web` pool connections, one `postgres` session from 130.95.189.83 with `application_name` `oceangenom_web`, and this host |
| Rehearsal on a 06:05 UTC dump of live | Applied in about 10 s; all post-checks passed; revert identical (`pg_dump -s`); re-apply clean |
| **Applied to live** | `045_v2_cutover.sql`, 06:06:49–06:07:00 UTC. 20 objects renamed, 7 views rebound, 0 `workflow` values to carry |
| Post-checks on live | `search_path` `v2, public`; `sample` is `v2.sample` (3,401); both write paths land in `v2`; `readonly` reads `sample` and `summary`; `oceangenom_web` can update `workflow` only; `public.sample` gone; test writes rolled back (0 left) |
| View row counts | Unchanged except `embargo_assignment_view`, 3,294 to 3,401: it now reads `v2.sample` |
| Drift baseline | Exactly the 20 renames (+20 / -20), accepted; the cron wrapper passes |

