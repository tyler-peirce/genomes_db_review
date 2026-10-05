# Decision: one migration system

Date: 2026-10-05
Status: **Accepted**
Supersedes: `migrations/README.md`'s "Status: Adopted — Sqitch" (2026-08-04)
Closes: Phase B.1; the tool half of open question 8; Appendix B Workshop 1
Review source: `database_review.md` Finding 1, Finding 10

## Decision

**All schema changes to `oceanomics_genomes` go through numbered SQL files in `sql/`,
applied with `bin/apply_migrations.py`, recorded in the `schema_migrations` table.**

Sqitch is retired as a tool. `sqitch.conf` and `sqitch.plan` are deleted. There is no
longer a runnable second migration system in this repository.

## Why this one

Three systems were in use when revision 2 of the review was written: the numbered files in
`sql/`, a Sqitch project at the repo root, and direct DDL. The numbered set won on evidence,
not preference:

| | `sql/` + `schema_migrations` | Sqitch |
|---|---|---|
| Changes applied to this database | 32 | **0** |
| Registry present on the live database | yes (`schema_migrations`, 32 rows) | **no** |
| Per-file integrity check | SHA-256 per file, enforced by the apply script | — |
| Apply-and-ledger in one step | `bin/apply_migrations.py` | — |
| Drift detection against source control | `bin/check_drift.py` | — |
| Rationale recorded per change | prose header in every file | one-line plan comment |

Two further points settled it. First, `add_core_lookup_indexes` — a Sqitch change written in
July — was deployed on 2026-10-02 by porting it into this convention as
`030_core_lookup_indexes.sql`, because that was the path with a ledger behind it. That was a
decision in practice before it was one on paper. Second, the strongest schema work in the
project (`001`–`032`: the mitogenome/ENA pipeline, the content-addressed LCA rework, the
verified table rebuilds) is already in this convention, including `019`, which found, explained
and repaired a silent data corruption introduced by a replayed migration. That only happens
where there is a written record to reason against.

Sqitch is the better-engineered tool in the abstract — real dependency ordering, automatic
verify-after-deploy, generated revert scaffolding. It lost because none of that was ever
exercised here, and adopting it now would mean re-homing 32 applied migrations and
reconstructing a registry to match a ledger that already works.

## What this does not decide

**The `v2` redesign is a separate, still-open decision.** Open question 8 bundled two
questions — which tool, and whether `v2` is still the plan. Only the first is answered here.
They are unbundled deliberately so the `v2` answer is not inferred from this document.

`v2` is blocked on open question 7: which downstream users and scripts query this database
from outside the two repositories. `pg_stat_activity` shows at least two human consumers on
DBeaver connecting as `postgres` from external IPs, and cutover is a `search_path` swap, so a
client with hardcoded `public.` prefixes is a real risk. Closing that question needs
`pg_stat_statements` or `log_statement = 'mod'` enabled for a fortnight — a live
`postgresql.conf` change that has deliberately not been made.

Until it is answered, **17 live objects stay uncovered by any migration** (the 12 lab tables,
the four live LCA tables, and `goat_species_v1`). Writing `public` catch-up migrations for
them would duplicate DDL that is already written, reviewed, constraint-tested and exercised
end to end by `import_v2.py`, and would be wasted if cutover proceeds. That DDL now lives in
`design/v2/` as reference material — see `design/v2/README.md`.

## Consequences

- `deploy/`, `revert/`, `verify/` and `scripts/backfill_v2.sql` moved to `design/v2/`,
  non-executable. The two superseded non-`v2` changes moved to `migrations/legacy/`.
- `migrations/` is now a historical directory only. Nothing is applied from it.
- `migrations/README.md`, `sql/README.md` and `schema/README.md` rewritten to match.
- The working rule is in `docs/database_change_checklist.md` under "Migration Governance".
- `sql/` reverts remain partial: `001`–`026` have no rollback scripts and will not get them
  retroactively. Accepted — they are applied history, and `sql/README.md` says so.
