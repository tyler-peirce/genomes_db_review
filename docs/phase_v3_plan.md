# Phase V.3 plan — promote the `v2` DDL to numbered migrations

Status: **executed 2026-10-06, all five steps; `035`–`040` are applied to live.** Results are recorded under V.3 in `database_review.md`. Source step: `database_review.md` §9,
Phase V.3. Previous step: V.2, done 2026-10-06. Next step: V.4 (backfill and reconcile).

## What V.3 is, and what it is not

V.3 turns the six reviewed `design/v2/deploy/*.sql` files into numbered migrations in `sql/`.
They are then applied to live with `bin/apply_migrations.py`. The result is an **empty** `v2`
schema on live, next to `public`. Nothing reads it and nothing writes to it.

Out of scope, and owned by later steps:

- **Running the backfill.** That is V.4. See decision 1: the backfill should not become a
  numbered migration at all.
- The `search_path` change, the `_pre_v2` renames, recreating dependent views, and writing
  `mitogenome_submission_view`'s `v2` equivalent. All of these are V.5.

## State going in

| | |
|---|---|
| Live ledger | 35 files, `000`–`034`, all hashes match, nothing pending (`apply_migrations.py --dry-run`, 2026-10-06) |
| New migration numbers | `035`–`040` |
| Current workbook | `OceanGenomes_Database_261006.xlsx` |
| Last rehearsal | V.2, from a 2026-10-06 `pg_dump` of live. 65 tied rows quarantined by the backfill, 1,333 open quarantine after import, zero UNEXPLAINED (from `OceanGenomes_Database_261006.xlsx`) |

## Decisions this plan takes

These are recommendations. If you disagree with any of them, the steps below change.

**1. The backfill stays a script. It does not become migration `041`.** The V.3 text lists it
last in plan order, but three things argue against ledgering it:

- It refuses to run until `import_v2.py --stage-attempt-keys` has been run. That is a Python
  step in another repo. `apply_migrations.py` cannot run it, so a pending `041` would make
  every future `apply_migrations.py` run fail until someone staged keys by hand.
- It is designed to be run repeatedly: run it, let the lab fix rows, run it again. The ledger
  runs a file exactly once.
- Its own header says it is "data movement, not schema".

Move it from `design/v2/backfill_v2.sql` to `scripts/backfill_v2.sql`, the path its header
already names. V.4 runs it. Amend V.3's wording in the review so it no longer says "then the
backfill".

**2. Make the files idempotent with a guard on each statement**, as the repo convention
requires (`sql/README.md`: "idempotent, guarded… replay safely"). The deploy files are
Sqitch-style today: bare `CREATE SCHEMA` and `CREATE TABLE`, which fail on replay. A replay
does happen: if the file commits and the ledger row does not land, `apply_migrations.py`
recovers by running the file again. Use the same idioms as `015`, `026` and `033`:

| Object | Guard |
|---|---|
| schema, table, index | `IF NOT EXISTS` |
| view, function | `CREATE OR REPLACE` |
| trigger (PG14 has no `IF NOT EXISTS`) | `DO` block that checks `pg_trigger` first, as in `033` |
| `COMMENT` | needs no guard |

A guard can silently skip an object whose shape is wrong. Decision 3 is what catches that.

**3. Each migration runs its own verify before `COMMIT`.** Port each `verify/*.sql` into a
`DO` block at the end of its migration. A failed check then rolls back the deploy itself,
which is stronger than Sqitch, where verify ran after the commit. Two adjustments:

- **Emptiness assertions** (`lab_tables`, `lca_tables`) are correct inside the creating
  transaction. Keep them, and add a comment saying they hold only at creation.
- **The quarantine verify writes rows.** It calls `v2.quarantine()` and then counts the
  results. Wrap that part in `SAVEPOINT verify; … ROLLBACK TO SAVEPOINT verify;` so the test
  rows do not commit. The identity sequence still advances by about three, which is harmless.
  Say so in a comment, so nobody "fixes" it.

**4. Keep one copy of the DDL.** Once `035`–`040` exist, the `design/v2/` files must not stay
editable, or the two copies will drift apart.

- Delete `design/v2/{deploy,verify,revert}/`, since git keeps the history.
- Reduce `design/v2/README.md` to a pointer.
- Repoint `scripts/diff_v2_against_live.py`, whose `DEPLOY` constant reads
  `design/v2/deploy`, at `sql/03[5-9]_v2_*.sql` and `sql/040_v2_*.sql`.

**5. Rehearse on a fresh restore before live, every time.** After the files are applied to
live, their hashes are frozen. Any fix after that point costs a new `041+` migration. A
mistake caught on a throwaway cluster costs nothing.

## Steps

### 1. Pre-flight against live and the current workbook

Run all of these on the day, not from memory:

```bash
bin/apply_migrations.py --dry-run           # anything landed since 034? expect "Nothing pending"
bin/check_drift.py                          # the og_workflow_* drift is expected; anything else is not
scripts/diff_v2_against_live.py             # expect zero UNEXPLAINED
scripts/audit_v2_dependents.py              # compare with the V.1 counts: 10 views, 7 triggers, 11 functions
scripts/check_v2_mappings.py -e <newest OceanGenomes_Database_*.xlsx>   # expect exit 0
```

- **If a migration has landed since `034`, stop.** Re-run the diff and fold any new column
  into the `v2` DDL before porting. This is how `017`–`026` caused 40 dropped columns.
- **If a newer workbook exists**, quote its filename beside every figure you take from it.
- Confirm with the owner that the scheduled `import_v2.py` run (on the other HPC) is **not**
  pointed at live yet. Rows imported into an empty `v2` before V.4's backfill would take
  precedence over live rows through `ON CONFLICT DO NOTHING`. The rehearsal only proved the
  order backfill → import.

### 2. Port the six files

| Migration | From `design/v2/deploy/` | Revert to `sql/revert/` |
|---|---|---|
| `035_v2_schema.sql` | `create_v2_schema.sql` | `035_v2_schema_revert.sql` |
| `036_v2_lab_tables.sql` | `create_v2_lab_tables.sql` | `036_…_revert.sql` |
| `037_v2_browse_views.sql` | `create_v2_browse_views.sql` | `037_…_revert.sql` |
| `038_v2_quarantine.sql` | `create_v2_quarantine.sql` | `038_…_revert.sql` |
| `039_v2_lca_tables.sql` | `create_v2_lca_tables.sql` | `039_…_revert.sql` |
| `040_v2_summary_view.sql` | `create_v2_summary_view.sql` | `040_…_revert.sql` |

For each file:

- Keep the prose header. Replace `-- Deploy genomes_db:…` and `-- requires:` with the repo's
  sentence form, e.g. "Run after `036_v2_lab_tables.sql`. Idempotent."
- Add the guards (decision 2) and the embedded verify (decision 3). Keep the standalone
  `BEGIN;` and `COMMIT;` lines, because `apply_migrations.py` uses them to detect
  self-wrapping.
- Port the revert unchanged in substance. The no-`IF EXISTS`, fail-loudly style is right for
  these reverts. They genuinely create objects, unlike the catch-up migrations `033`/`034`, so
  the no-op revert pattern does not apply. Check that `039`'s revert drops
  `v2.lca_set_content_hash()`.
- In `040`, keep the deliberate `public.ref_genomes` and `public.master_species`
  qualifications and their comments.

Then make the changes from decisions 1 and 4: move the backfill, delete the `design/v2` copies,
and repoint the diff script. Re-run `scripts/diff_v2_against_live.py` against live to confirm
the repointed script still reports zero UNEXPLAINED.

### 3. Rehearse on a fresh restore of live

Take a new `pg_dump`. Do not reuse the V.2 dump, because the point is to catch anything that
landed since. Then:

1. Restore into a throwaway cluster and run `bin/apply_migrations.py`. Expect `035`–`040` to
   apply and their embedded verifies to pass.
2. **Replay test.** Delete the six ledger rows and run `apply_migrations.py` again. Every file
   must re-apply as a no-op, and its verify must still pass. This is the crash-recovery path
   decision 2 exists for.
3. **Revert test.** Run the reverts `040` → `035` in order, delete the ledger rows, and
   re-apply. Afterwards `\dn v2` should show the schema, and the object counts should match
   the first apply.
4. **Equivalence with the V.2 rehearsal.** Run `--stage-attempt-keys`, then
   `scripts/backfill_v2.sql` twice, then `import_v2.py` twice. Expect identical passes and the
   V.2 figures: 65 tied rows quarantined, `rna_library_ilmn` / `ont_library` at 389 / 98, and
   1,333 open quarantine. Any difference comes either from the port or from live having moved;
   find out which before going on.
5. Run `scripts/diff_v2_against_live.py` against the clone. Expect zero UNEXPLAINED.

### 4. Commit, then apply to live

Commit the migrations, reverts, backfill move, diff-script change and doc updates (step 5)
together, before applying, so the ledger hashes match a committed tree. Then:

```bash
bin/apply_migrations.py --dry-run     # exactly 035–040 pending, all "self-wrapped"
bin/apply_migrations.py
bin/apply_migrations.py --verify
scripts/audit_v2_dependents.py        # unchanged from pre-flight: nothing in public depends on v2 yet
bin/check_drift.py                    # unchanged from pre-flight (see below)
```

This change is additive. No `public` object is altered. `040` creates views that read
`public.ref_genomes` and `public.master_species`, and that takes only light locks.

`check_drift.py` inventories `public` only, so the new `v2` objects will not register there.
That is not a gap to fix now: V.6 moves them into `public`, and V.7 re-baselines. **Do not run
`check_drift.py --update`** as part of this step. It would also accept the unowned
`og_workflow_*` tables, which open question 16 deliberately keeps alarming.

### 5. Documentation, in the same commit

- `database_review.md`:
  - Mark V.3 done, with the date and figures (quoting the workbook filename).
  - Amend the "then the backfill" wording (decision 1).
  - Add a revision 3.3 row.
- `design/v2/README.md`: reduce to a pointer to `sql/035`–`040` and `scripts/backfill_v2.sql`,
  keeping the known-defects history.
- `sql/README.md`: change "Reverts are partial… `027`–`034`" to `027`–`040`.
- `docs/migration_system_decision.md` lines 62–68: these say the `v2` DDL lives in
  `design/v2/`, which will no longer be true.
- The backfill's header: its usage line still says `-f design/v2/backfill_v2.sql`.

## Done when

- `035`–`040` are ledgered on live, `--verify` is clean, and every embedded verify passed.
- The replay, revert and equivalence tests passed on a restore taken the same week.
- `diff_v2_against_live.py` reads `sql/`, and reports zero UNEXPLAINED against live.
- No `.sql` copy of the `v2` DDL remains outside `sql/`.
- The import schedule is confirmed off for live until V.4's backfill has run.

## Risks

| Risk | Mitigation |
|---|---|
| A migration lands between pre-flight and apply, and the `v2` DDL silently lacks its columns | Re-run `--dry-run` and the diff immediately before step 4, not just at step 1 |
| A guarded `CREATE … IF NOT EXISTS` skips a wrongly shaped object | The embedded verify asserts shape, not just existence |
| A defect is found after the live apply | Fix forward with `041+`. Never edit an applied file (`sql/README.md`) |
| `import_v2.py` writes to live `v2` before the backfill | Step 1 gate, and the "Done when" criterion |
| `mitogenome_submission_view` is forgotten | Still owed before V.5. It is not part of this step, so it is listed here to keep it visible |
