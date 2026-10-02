#!/usr/bin/env python3
"""Compare the live database's object inventory against a tracked baseline.

Why this exists
---------------
The ledger in `schema_migrations` answers "which migration files ran?". It
cannot answer "does the database match source control?", because objects can
be -- and have been -- created by direct DDL that no migration file describes.
22 tables and 6 views reached this database that way, including the whole
data_package_* subsystem and every *_SS260818 snapshot. A rebuild from sql/
would silently produce a different database.

This script closes that gap with two independent checks.

  1. INVENTORY DRIFT. Live tables and views vs schema/object_inventory.tsv.
     Catches anything created or dropped since the baseline was last approved.
     This is the one to run in cron -- it is cheap and exact.

  2. SOURCE COVERAGE. Where each live object can be reproduced from:
       migration     - created by a file in sql/. Fully managed: the change
                       history explains how it got to its current shape.
       baseline-only - present in the schema/ pg_dump snapshot but created by
                       NO migration. Reproducible, but only as a point-in-time
                       dump with no history and no rationale. This is the
                       catch-up worklist for Finding 10 / Phase B.
       NEITHER       - in neither. Would be lost entirely on a rebuild. Should
                       always be zero immediately after a --update plus a
                       scripts/export_schema_baseline.sh run; anything here is
                       brand new direct DDL.
     Approximate by nature: it scans SQL text rather than executing it, so an
     object built by dynamic SQL reads as uncovered. A worklist, not a verdict.

Workflow
--------
    bin/check_drift.py              # report; exit 1 if inventory drifted
    bin/check_drift.py --coverage   # also show the migration-coverage worklist
    bin/check_drift.py --update     # accept the current live state as baseline

Run --update only when you have decided the live state is correct, and commit
the resulting schema/object_inventory.tsv in the same change as the migration
that explains it.

Connection: same resolution as bin/apply_migrations.py -- $DATABASE_URL, then
DB_* environment variables, then ~/postgresql_details/oceanomics.cfg.
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SQL_DIR = REPO / "sql"
MANIFEST = REPO / "schema" / "object_inventory.tsv"
BASELINE_DUMP = REPO / "schema" / "current_schema.sql"

# Reuse the connection handling rather than duplicating it.
_spec = importlib.util.spec_from_file_location(
    "apply_migrations", Path(__file__).resolve().parent / "apply_migrations.py")
_am = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_am)
query = _am.query

INVENTORY_SQL = """
SELECT CASE c.relkind
         WHEN 'r' THEN 'table'
         WHEN 'p' THEN 'table'
         WHEN 'v' THEN 'view'
         WHEN 'm' THEN 'matview'
       END AS kind,
       c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'v', 'm')
ORDER BY 1, 2
"""

CREATE_RE = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?(?:TEMP\s+|TEMPORARY\s+|UNLOGGED\s+)?"
    r"(?:MATERIALIZED\s+)?(TABLE|VIEW)\s+(?:IF\s+NOT\s+EXISTS\s+)?"
    r"(?:public\.)?\"?([A-Za-z_][A-Za-z0-9_]*)\"?",
    re.I)


def live_inventory() -> set[tuple[str, str]]:
    return {(r[0], r[1]) for r in query(INVENTORY_SQL)}


def read_manifest() -> set[tuple[str, str]]:
    if not MANIFEST.is_file():
        return set()
    out = set()
    for line in MANIFEST.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        kind, _, name = line.partition("\t")
        out.add((kind.strip(), name.strip()))
    return out


def write_manifest(inv: set[tuple[str, str]]) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Approved object inventory for public schema of oceanomics_genomes.",
        "# Regenerate with: bin/check_drift.py --update",
        "# Commit changes here together with the migration that explains them.",
        "#",
        "# kind\tname",
    ]
    lines += [f"{k}\t{n}" for k, n in sorted(inv)]
    MANIFEST.write_text("\n".join(lines) + "\n")


def created_names(paths) -> set[str]:
    """Object names appearing in a CREATE TABLE/VIEW in the given SQL files."""
    names = set()
    for path in paths:
        if path.is_file():
            for _kind, name in CREATE_RE.findall(path.read_text()):
                names.add(name.lower())
    return names


def migration_created_names() -> set[str]:
    return created_names(sorted(SQL_DIR.glob("*.sql")))


def baseline_created_names() -> set[str]:
    # The pg_dump baseline also records views in current_views.sql.
    return created_names([BASELINE_DUMP,
                          BASELINE_DUMP.with_name("current_views.sql")])


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Check live database objects against the tracked baseline.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    ap.add_argument("--update", action="store_true",
                    help="accept the live state as the new baseline")
    ap.add_argument("--coverage", action="store_true",
                    help="also list objects no migration file creates")
    args = ap.parse_args()

    live = live_inventory()

    if args.update:
        before = read_manifest()
        write_manifest(live)
        added, removed = live - before, before - live
        print(f"Baseline updated: {MANIFEST.relative_to(REPO)}")
        print(f"  {len(live)} objects "
              f"(+{len(added)} / -{len(removed)} vs previous baseline)")
        return 0

    baseline = read_manifest()
    if not baseline:
        print(f"No baseline at {MANIFEST.relative_to(REPO)}.")
        print("Create one with: bin/check_drift.py --update")
        return 1

    new = sorted(live - baseline)
    gone = sorted(baseline - live)

    print(f"Live objects: {len(live)}   Baseline: {len(baseline)}")

    if not new and not gone:
        print("No inventory drift.")
    else:
        print(f"\nINVENTORY DRIFT: +{len(new)} / -{len(gone)}")
        for kind, name in new:
            print(f"  + {kind:8s} {name}   (live, not in baseline)")
        for kind, name in gone:
            print(f"  - {kind:8s} {name}   (in baseline, not live)")

    if args.coverage:
        in_migrations = migration_created_names()
        in_baseline = baseline_created_names()

        tiers = {"migration": [], "baseline-only": [], "NEITHER": []}
        for kind, name in sorted(live):
            low = name.lower()
            if low in in_migrations:
                tiers["migration"].append((kind, name))
            elif low in in_baseline:
                tiers["baseline-only"].append((kind, name))
            else:
                tiers["NEITHER"].append((kind, name))

        print("\nSOURCE COVERAGE")
        for tier in ("migration", "baseline-only", "NEITHER"):
            print(f"  {tier:14s} {len(tiers[tier]):3d}")

        if tiers["NEITHER"]:
            print("\n  In NEITHER sql/ nor the schema/ baseline. A rebuild "
                  "would lose these entirely:")
            for kind, name in tiers["NEITHER"]:
                print(f"    {kind:8s} {name}")
            print("  Re-run scripts/export_schema_baseline.sh to capture them,"
                  " then write catch-up migrations.")

        if tiers["baseline-only"]:
            print(f"\n  No migration describes these {len(tiers['baseline-only'])}"
                  " objects -- they exist only as a dump snapshot.")
            print("  This is the Phase B catch-up worklist:")
            for kind, name in tiers["baseline-only"]:
                print(f"    {kind:8s} {name}")

        print("\n  (Approximate: scans SQL text, so anything built by dynamic"
              " SQL appears uncovered too.)")

    return 1 if (new or gone) else 0


if __name__ == "__main__":
    sys.exit(main())
