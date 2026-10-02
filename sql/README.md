# Numbered SQL Migrations (deployed)

Status: **applied to the live database.** These 29 files are the deployed system
of record for the mitogenome/ENA schema work. The Sqitch project at the repo root
(`sqitch.plan` / `deploy/` / `revert/` / `verify/`) is **declared but has never
been deployed** — do not read `migrations/README.md`'s "Status: Adopted — Sqitch"
as a description of what is running.

Which of the two systems should be canonical is **undecided**. See open question
8 in `database_review.md`. This directory exists to put the deployed migrations
under version control, not to settle that question.

## Do not reformat an applied file

Each file's contents are hash-checked by a SHA-256 recorded in the live
`schema_migrations` table. Editing an applied file — including reformatting,
fixing a typo in a header, or changing line endings — invalidates that check and
leaves the ledger disagreeing with the tree.

To correct an applied migration, **supersede it with a new numbered file.**
`028_mitogenome_submission_view_annotation_key.sql` →
`029_mitogenome_submission_view_join_base_table.sql` is the worked example: 029
retains 028's fix, corrects its stated rationale, and explains both in its
header.

## Per-file conventions

Each migration opens with a prose header explaining why the change was made,
what was rejected, and what must not be done later. Keep that up — these headers
carry design rationale that is not recoverable from the schema itself.

Migrations are idempotent and guarded with `to_regclass()` so they replay safely
against a partial schema.

## Known gaps

- **The ledger is populated out of band.** No migration file inserts its own
  `schema_migrations` row; the row is added separately after the apply. That is
  why `026_mitogenome_data_annotation_integrity.sql` is applied — all 16 of its
  columns are live — but has no ledger row. The ledger is what makes this
  approach trustworthy, so an unrecorded apply is a real defect, not a cosmetic
  one. There is no apply/ledger script in the repo yet.
- **Reverts are partial.** `revert/` covers `027`–`029` only. `001`–`026` have no
  rollback scripts.

## Connecting to a target

No credentials are committed. Standard libpq environment variables, or a local
`.env.db` outside the repo.
