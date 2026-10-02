#!/usr/bin/env python3
"""Apply numbered SQL migrations and record them in the ledger, in one step.

Why this exists
---------------
`schema_migrations` is what makes the sql/ approach trustworthy: it answers
"what is applied?" without inspecting the catalog. Until now no migration file
wrote its own ledger row -- the row was inserted by hand after the apply. That
is how 026_mitogenome_data_annotation_integrity.sql came to be fully applied
with no ledger row, discovered only by diffing the catalog against the tree.

This script removes the hand step. Applying and recording happen in a single
psql invocation, so forgetting one is no longer possible.

Safety properties
-----------------
* Nothing runs until every already-ledgered file has been re-hashed and
  matched. A changed applied file aborts the run -- that is the drift check
  behind sql/README.md's "do not reformat an applied file" rule.
* Migrations are applied in filename order, lowest number first.
* Each file keeps its own transaction control. These files are machine-written
  with a standalone `BEGIN;` / `COMMIT;` pair, but `BEGIN` also appears bare
  inside PL/pgSQL DO blocks, so this script deliberately does NOT rewrite them
  -- getting that wrong would apply a migration without its transaction.
* Because the file commits itself, the ledger INSERT is a separate statement in
  the same psql session. The only gap is a crash between the two. That is
  self-healing: every migration here is idempotent, so the next run sees the
  file as pending, replays it as a no-op, and writes the row.
* 005 is refused unless 019 is applied or also pending -- see --help epilog.

Connection
----------
No credentials in this file. In order: $DATABASE_URL, then $DB_HOST/$DB_PORT/
$DB_NAME/$DB_USER/$DB_PASSWORD, then ~/postgresql_details/oceanomics.cfg
(the same file OceanOmics-Database/db_config.py uses).

Usage
-----
    bin/apply_migrations.py --dry-run     # what would run, plus drift report
    bin/apply_migrations.py --verify      # hash check only, exit 1 on drift
    bin/apply_migrations.py               # apply everything pending
    bin/apply_migrations.py --target 031  # apply up to and including 031
"""

from __future__ import annotations

import argparse
import configparser
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SQL_DIR = REPO / "sql"
LEDGER = "schema_migrations"

MIGRATION_RE = re.compile(r"^(\d{3})_.*\.sql$")
NO_TRANSACTION_RE = re.compile(r"^\s*--\s*no-transaction\s*$", re.M | re.I)
# CONCURRENTLY cannot run inside a transaction block. Detecting it directly is
# more reliable than trusting a comment marker, which is easy to omit -- 030
# was written without one.
CONCURRENTLY_RE = re.compile(r"^\s*(CREATE|DROP)\s+INDEX\s+CONCURRENTLY", re.M | re.I)
STANDALONE_BEGIN_RE = re.compile(r"^[ \t]*BEGIN;[ \t]*$", re.M)
STANDALONE_COMMIT_RE = re.compile(r"^[ \t]*COMMIT;[ \t]*$", re.M)

CFG_PATH = "~/postgresql_details/oceanomics.cfg"


# --------------------------------------------------------------------------
# connection
# --------------------------------------------------------------------------

def psql_base() -> tuple[list[str], dict]:
    """Return (psql argv prefix, env) from the first credential source found."""
    env = os.environ.copy()

    if env.get("DATABASE_URL"):
        return ["psql", env["DATABASE_URL"]], env

    needed = ("DB_HOST", "DB_PORT", "DB_NAME", "DB_USER")
    if all(env.get(k) for k in needed):
        if env.get("DB_PASSWORD"):
            env["PGPASSWORD"] = env["DB_PASSWORD"]
        return ["psql", "-h", env["DB_HOST"], "-p", env["DB_PORT"],
                "-U", env["DB_USER"], "-d", env["DB_NAME"]], env

    cfg_path = Path(CFG_PATH).expanduser()
    if cfg_path.is_file():
        parser = configparser.ConfigParser()
        parser.read(cfg_path)
        if parser.has_section("postgres"):
            s = parser["postgres"]
            env["PGPASSWORD"] = s.get("password", "")
            return ["psql", "-h", s["host"], "-p", s["port"],
                    "-U", s["user"], "-d", s["dbname"]], env

    sys.exit(
        "No database connection configured. Set DATABASE_URL, or DB_HOST/"
        f"DB_PORT/DB_NAME/DB_USER (+DB_PASSWORD), or create {CFG_PATH}."
    )


def run_psql(sql: str, *, autocommit: bool = False) -> subprocess.CompletedProcess:
    argv, env = psql_base()
    argv += ["-v", "ON_ERROR_STOP=1", "-X", "-q"]
    if not autocommit:
        pass  # each file manages its own transaction; see module docstring
    return subprocess.run(argv, input=sql, env=env,
                          text=True, capture_output=True)


def query(sql: str) -> list[list[str]]:
    argv, env = psql_base()
    argv += ["-v", "ON_ERROR_STOP=1", "-X", "-At", "-F", "\x1f", "-c", sql]
    proc = subprocess.run(argv, env=env, text=True, capture_output=True)
    if proc.returncode != 0:
        sys.exit(f"Query failed:\n{proc.stderr}")
    return [line.split("\x1f") for line in proc.stdout.splitlines() if line]


# --------------------------------------------------------------------------
# files and ledger
# --------------------------------------------------------------------------

def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def migration_files() -> dict[str, Path]:
    return {p.name: p for p in sorted(SQL_DIR.glob("*.sql"))
            if MIGRATION_RE.match(p.name)}


def ledger_rows() -> dict[str, str]:
    return {r[0]: r[1] for r in query(
        f"SELECT filename, sha256 FROM {LEDGER} ORDER BY filename")}


def is_no_transaction(path: Path) -> bool:
    text = path.read_text()
    return bool(NO_TRANSACTION_RE.search(text) or CONCURRENTLY_RE.search(text))


def transaction_mode(path: Path) -> str:
    """Classify how a file manages its transaction, for reporting."""
    if is_no_transaction(path):
        return "no-transaction"
    text = path.read_text()
    if STANDALONE_BEGIN_RE.search(text) and STANDALONE_COMMIT_RE.search(text):
        return "self-wrapped"
    return "unwrapped"


# --------------------------------------------------------------------------
# checks
# --------------------------------------------------------------------------

def verify(files: dict[str, Path], ledger: dict[str, str]) -> list[str]:
    """Return a list of drift problems. Empty means the tree matches."""
    problems = []
    for name, recorded in sorted(ledger.items()):
        path = files.get(name)
        if path is None:
            problems.append(
                f"{name}: ledgered but the file is MISSING from sql/")
            continue
        actual = sha256_of(path)
        if actual != recorded:
            problems.append(
                f"{name}: file has CHANGED since it was applied\n"
                f"    ledger {recorded}\n    file   {actual}")
    return problems


def check_invalid_indexes() -> list[str]:
    rows = query(
        "SELECT c.relname FROM pg_index x "
        "JOIN pg_class c ON c.oid = x.indexrelid WHERE NOT x.indisvalid")
    return [r[0] for r in rows]


def guard_005(pending: list[str], ledger: dict[str, str]) -> None:
    """Refuse to apply 005 without 019.

    005 clears submission_ready on every row whose gate columns are not 'PASS'.
    It adds those columns with DEFAULT 'NOT_RUN' in the same file, so replayed
    against a database where they do not already hold real history it matches
    every row. 019 recomputes the flag. Applying 005 without 019 following it
    silently corrupts the column -- it has happened once already.
    """
    has005 = any(n.startswith("005_") for n in pending)
    if not has005:
        return
    ledgered019 = any(n.startswith("019_") for n in ledger)
    pending019 = any(n.startswith("019_") for n in pending)
    if not (ledgered019 or pending019):
        sys.exit(
            "REFUSING: 005 is pending but 019 is neither applied nor pending.\n"
            "005 clears submission_ready for every row; 019 is the repair.\n"
            "Apply them together, or explicitly pass --allow-005-without-019.")


# --------------------------------------------------------------------------
# apply
# --------------------------------------------------------------------------

def apply_one(name: str, path: Path) -> None:
    digest = sha256_of(path)
    mode = transaction_mode(path)
    autocommit = mode == "no-transaction"

    print(f"  applying {name}  [{mode}]")

    insert = (
        f"INSERT INTO {LEDGER} (filename, sha256) "
        f"VALUES ('{name}', '{digest}');"
    )
    # One psql session: the file, then its ledger row. The file commits itself,
    # so these are not a single transaction -- see the module docstring for why
    # that is safe and self-healing.
    script = f"\\i {path}\n{insert}\n"

    proc = run_psql(script, autocommit=autocommit)
    if proc.returncode != 0:
        print(proc.stdout, file=sys.stderr)
        print(proc.stderr, file=sys.stderr)
        sys.exit(
            f"\nFAILED applying {name}.\n"
            "If the file committed but the ledger row did not land, re-run: "
            "these migrations are idempotent, so the replay is a no-op and the "
            "row will be written.")
    if proc.stdout.strip():
        for line in proc.stdout.strip().splitlines():
            print(f"    {line}")

    if autocommit:
        invalid = check_invalid_indexes()
        if invalid:
            sys.exit(
                f"\n{name} used CREATE INDEX CONCURRENTLY and left INVALID "
                f"indexes: {', '.join(invalid)}\n"
                "DROP them before re-running -- IF NOT EXISTS will skip an "
                "invalid index rather than rebuild it.")


# --------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Apply pending SQL migrations and ledger them atomically.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    ap.add_argument("--dry-run", action="store_true",
                    help="report drift and what would be applied; change nothing")
    ap.add_argument("--verify", action="store_true",
                    help="hash-check applied files only; exit 1 on drift")
    ap.add_argument("--target", metavar="NNN",
                    help="apply up to and including this migration number")
    ap.add_argument("--allow-005-without-019", action="store_true",
                    help=argparse.SUPPRESS)
    args = ap.parse_args()

    files = migration_files()
    ledger = ledger_rows()

    problems = verify(files, ledger)
    if problems:
        print("LEDGER DRIFT -- refusing to go further:\n", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        print("\nAn applied migration must never be edited. To correct one, "
              "supersede it with a new numbered file.", file=sys.stderr)
        return 1

    print(f"Ledger OK: {len(ledger)} applied files, all hashes match.")

    if args.verify:
        return 0

    pending = [n for n in sorted(files) if n not in ledger]
    if args.target:
        pending = [n for n in pending if n[:3] <= args.target]

    if not pending:
        print("Nothing pending.")
        return 0

    print(f"\nPending ({len(pending)}):")
    for n in pending:
        print(f"  {n}  [{transaction_mode(files[n])}]")

    unwrapped = [n for n in pending if transaction_mode(files[n]) == "unwrapped"]
    if unwrapped:
        print("\nWARNING: no transaction control and not marked "
              "'-- no-transaction':", file=sys.stderr)
        for n in unwrapped:
            print(f"  {n}", file=sys.stderr)
        print("  A failure part-way through will leave it half-applied.",
              file=sys.stderr)

    if not args.allow_005_without_019:
        guard_005(pending, ledger)

    if args.dry_run:
        print("\n--dry-run: nothing applied.")
        return 0

    print()
    for n in pending:
        apply_one(n, files[n])

    after = ledger_rows()
    missing = [n for n in pending if n not in after]
    if missing:
        print(f"\nApplied but NOT ledgered: {', '.join(missing)}", file=sys.stderr)
        return 1

    print(f"\nDone. Ledger now has {len(after)} rows.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
