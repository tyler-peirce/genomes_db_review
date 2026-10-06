#!/usr/bin/env python3
"""Convert the easy unconvertible values already sitting NULL in v2, once (Phase V.4 follow-up).

Why this exists
---------------
import_v2.py now converts mechanical values by rule (OceanOmics-Database/v2_value_rules.py:
'3.44g', '>1.8', DMS coordinates, Excel-formatted coordinates, ...) and closes the quarantine
records that no longer apply. That covers every row the workbook still carries, on the next
nightly run. It cannot reach rows the workbook no longer carries, whose only copy of the raw
text is the raw_row of their type_cast quarantine record (written by scripts/backfill_v2.sql).
This applies the same rules to those.

For every open type_cast record whose row is in v2, and every typed column of its raw_row
where the v2 cell is NULL and a rule matches:
  - sets the cell (WHERE ... IS NULL, so a value the importer or the lab has since set wins);
  - logs the conversion in v2.value_conversions (migration 041), converted_by
    'apply_value_rules.py';
then closes the record if nothing in it still fails, or rewrites its detail to what does.

Default is a dry run: counts per table, column and rule, with examples. --apply writes, in one
transaction. Re-runnable: a second run finds nothing to do.

Run it with the importer's environment, which has openpyxl (needed by the coordinate rule):

    ~/.venvs/oceanomics/bin/python scripts/apply_value_rules.py            # dry run
    ~/.venvs/oceanomics/bin/python scripts/apply_value_rules.py --apply

Connection: same resolution as bin/apply_migrations.py.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_IMPORTER_REPO = REPO.parent / "OceanOmics-Database"
_spec = importlib.util.spec_from_file_location(
    "apply_migrations", REPO / "bin" / "apply_migrations.py")
_am = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_am)
query = _am.query

TYPED = {"real", "int", "date"}


def lit(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    return "'" + str(v).replace("'", "''") + "'"


def blank(v) -> bool:
    return v is None or str(v).strip() == "" or str(v).strip().upper() in ("NA", "N/A", "-", "?")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write the conversions (default: dry run)")
    ap.add_argument("--importer-repo", type=Path, default=DEFAULT_IMPORTER_REPO)
    args = ap.parse_args()

    sys.path.insert(0, str(args.importer_repo))
    import name_convert_v2 as nc          # noqa: E402
    import v2_value_rules as rules        # noqa: E402

    if query("SELECT to_regclass('v2.value_conversions') IS NOT NULL")[0][0] != "t":
        sys.exit("v2.value_conversions is missing: apply migration 041 first.")
    db = query("SELECT current_database(), coalesce(inet_server_addr()::text, 'local socket')")[0]
    print(f"Database: {db[0]} @ {db[1]}   ({'APPLY' if args.apply else 'dry run'})\n")

    # Already converted: skip. Needed for rule no_value, which leaves the cell NULL and so would
    # otherwise be found again on every run.
    done = {(t, k, c) for t, k, c in query(
        "SELECT source_table, row_key, column_name FROM v2.value_conversions")}

    records = defaultdict(list)            # table -> [(quarantine_id, key, raw_row)]
    for qid, table, key, raw in query(
            "SELECT quarantine_id, source_table, source_row_key, raw_row::text "
            "FROM v2.import_quarantine WHERE resolved_at IS NULL AND violation_type = 'type_cast' "
            "AND source_row_key IS NOT NULL ORDER BY source_table, source_row_key"):
        records[table].append((qid, key, json.loads(raw)))

    counts, examples = Counter(), defaultdict(list)
    sql, closed, rewritten = [], 0, 0
    for table, recs in records.items():
        types = {c: k for c, k in nc.COLUMN_TYPES.get(table, {}).items() if k in TYPED}
        # Split columns (migration 042) are filled by import_v2.py only, but a record whose
        # split cell still cannot be parsed is still open -- it must not be closed from here.
        splits = [c for c, k in nc.COLUMN_TYPES.get(table, {}).items() if k == "split"]
        pk = nc.PRIMARY_KEYS.get(table)
        if not types or not pk:
            continue
        keys = ",".join(lit(k) for _, k, _ in recs)
        current = {r[0]: json.loads(r[1]) for r in query(
            f"SELECT {pk}::text, to_jsonb(t)::text FROM v2.{table} t WHERE {pk}::text IN ({keys})")}
        for qid, key, raw_row in recs:
            row = current.get(key)
            if row is None:
                continue                    # the row is blocked, not loaded: nothing to fill
            still_failing, converted_any = [], False
            for col, kind in types.items():
                raw = raw_row.get(col)
                if blank(raw) or row.get(col) is not None or (table, key, col) in done:
                    continue
                hit = rules.fallback(table, col, kind, raw)
                if hit is None:
                    still_failing.append(f"{col} = {raw}")
                    continue
                value, rule = hit
                converted_any = True
                counts[(table, col, rule)] += 1
                if len(examples[(table, col, rule)]) < 3:
                    examples[(table, col, rule)].append(f"{key}: {raw!r} -> {value!r}")
                if value is not None:
                    sql.append(f"UPDATE v2.{table} SET {col} = {lit(value)} "
                               f"WHERE {pk}::text = {lit(key)} AND {col} IS NULL;")
                sql.append(
                    "INSERT INTO v2.value_conversions (source_table, row_key, column_name, raw_value, "
                    "stored_value, rule, converted_by) VALUES "
                    f"({lit(table)}, {lit(key)}, {lit(col)}, {lit(str(raw))}, "
                    f"{lit(None if value is None else str(value))}, {lit(rule)}, 'apply_value_rules.py') "
                    "ON CONFLICT (source_table, row_key, column_name) DO UPDATE SET "
                    "raw_value = EXCLUDED.raw_value, stored_value = EXCLUDED.stored_value, "
                    "rule = EXCLUDED.rule, converted_by = EXCLUDED.converted_by, last_seen = now();")
            for col in splits:
                raw = raw_row.get(col)
                if blank(raw):
                    continue
                try:
                    rules.split(table, col, raw)
                except ValueError:
                    still_failing.append(f"{col} = {raw}")
            if not converted_any:
                continue                    # nothing done here: leave the record as it is
            if not still_failing:
                closed += 1
                sql.append("UPDATE v2.import_quarantine SET resolved_at = now(), "
                           "resolution_note = 'converted by rule, apply_value_rules.py ' || current_date "
                           f"WHERE quarantine_id = {qid} AND resolved_at IS NULL;")
            else:
                rewritten += 1
                detail = "; ".join(still_failing) + " -- did not convert; loaded as null"
                sql.append(f"UPDATE v2.import_quarantine SET violation_detail = {lit(detail)} "
                           f"WHERE quarantine_id = {qid} AND resolved_at IS NULL;")

    print(f"{'table':18} {'column':24} {'rule':24} {'values':>6}")
    for (t, c, r), n in sorted(counts.items()):
        print(f"{t:18} {c:24} {r:24} {n:6}")
        for ex in examples[(t, c, r)]:
            print(f"    {ex}")
    print(f"\nvalues converted: {sum(counts.values())}   records closed: {closed}   "
          f"records rewritten: {rewritten}")

    if not args.apply:
        print("\nDry run: nothing written. Re-run with --apply.")
        return 0
    if not sql:
        print("\nNothing to apply.")
        return 0
    proc = _am.run_psql("BEGIN;\n" + "\n".join(sql) + "\nCOMMIT;\n")
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        sys.exit("FAILED: rolled back, nothing written.")
    print("\nApplied and committed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
