#!/usr/bin/env python3
"""Reconcile the backfilled `v2` tables against the live `public` tables (Phase V.4).

Why this exists
---------------
Phase V.4 of database_review.md fills `v2` from `public` with scripts/backfill_v2.sql and
then has to PROVE the copy is faithful before V.5 deprecates anything. The backfill's own
report gives row counts, and row counts cannot tell a quarantined row from a lost one. This
script accounts for every row by key, and compares values column by column.

Run it AFTER the backfill and BEFORE any import_v2.py run. The importer makes `v2` differ
from `public` on purpose -- the workbook wins, and its newer mappings recover data the live
importer drops -- so after an import, differences here stop meaning "backfill bug".

What it checks
--------------
  1. accounting   (12 lab tables) every public key is LOADED (in v2) or BLOCKED (not in
                  v2, with an open quarantine row under that key). A key in neither is
                  LOST -- the outcome decision 6 exists to prevent. A v2 key that is not in
                  public is INVENTED. Both are failures with no exceptions.
  2. values       columns with the same name and normalised type on both sides, compared
                  with EXCEPT ALL in both directions: per key on the lab tables, as a
                  multiset on the LCA tables (no shared key: content_hash differs by
                  design, see 039_v2_lca_tables.sql). Differences per column are failures
                  unless VALUE_EXPLAINED names the transformation that produced them.
  3. retyped      text -> date/real/integer/boolean columns. A value that is non-blank (and
                  not an explicit NA) in public but NULL in v2 is one the backfill could not
                  cast. Each must have an open type_cast record for that key naming the
                  field; one without is a silent loss and a failure.
  4. quarantine   open quarantine grouped by (table, violation_type). Each class must have a
                  recorded cause in QUARANTINE_CAUSES; a class without one is a failure.

Exit status: 0 when nothing is UNEXPLAINED, 1 otherwise.

Usage
-----
    scripts/reconcile_v2.py            # the report
    scripts/reconcile_v2.py --detail   # also print up to 5 example keys per difference

Connection: same resolution as bin/apply_migrations.py. Reads only.
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location(
    "diff_v2_against_live", REPO / "scripts" / "diff_v2_against_live.py")
_diff = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_diff)
query = _diff.query

# Source primary key of each lab table. It is also the source_row_key the backfill passes
# to v2.quarantine(), which is what makes per-key accounting possible.
KEYS = {
    "sample": "og_id",
    "tissue": "tissue_id",
    "dna_extraction": "dna_id",
    "rna_extraction": "rna_id",
    "hic_lysate": "lysate_id",
    "illumina_library": "illumina_library_tube_id",
    "pacbio_library": "pacbio_library_tube_id",
    "ont_library": "ont_library_tube_id",
    "hic_library": "hic_library_tube_id",
    "rna_library_ilmn": "rna_library_tube_id",
    "rna_library_kinx": "rna_library_tube_id",
    "sequencing": "sequencing_id",
}
# A row can also be blocked under the registry: the backfill quarantines an RNA tube that
# appears in both RNA library tables as source_table 'library'.
ALSO_BLOCKED_UNDER = {"rna_library_ilmn": ["library"], "rna_library_kinx": ["library"]}

# Value differences on unchanged columns that are deliberate. Key is table.column; the value
# is (SQL predicate over p.<col> and v.<col> that every differing row must satisfy, reason).
# A difference is only explained if EVERY differing row matches the predicate.
VALUE_EXPLAINED: dict[str, tuple[str, str]] = {
    # Owner decision 2026-10-13: OceanGenom_Web owns sample.workflow. Until the cutover it
    # writes public.sample, and import_v2.py sets the column in v2 only on INSERT, so the two
    # diverge wherever the web app has assigned a workflow. 044 carries public's value across.
    # Explained only where the app logged that assignment.
    "sample.workflow": (
        "EXISTS (SELECT 1 FROM public.og_workflow_assignment_log a WHERE a.og_id = p.og_id)",
        "assigned in OceanGenom_Web (web-owned; 044 carries it to v2)"),
}

# Every open quarantine class needs a recorded cause. Keyed (table, violation_type).
QUARANTINE_CAUSES: dict[tuple[str, str], str] = {
    ("dna_extraction", "unique"):
        "attempt-key ties: two tubes share (tissue_id, ext_num). Seated by the workbook where "
        "it carries exactly one (V.2 decision); the rest are renamed tubes and the "
        "OG2274H_D_D / OG2274H_D2 typo pair",
    ("hic_lysate", "unique"): "attempt-key ties, as dna_extraction",
    ("illumina_library", "unique"): "attempt-key tie against a placeholder tube ID '0'",
    ("pacbio_library", "unique"): "attempt-key ties against placeholder tube ID '0'",
    ("rna_library_kinx", "unique"): "attempt-key tie against a placeholder tube ID",
    ("dna_extraction", "foreign_key"): "extraction with a null tissue_id (F7: parent FK is NOT NULL)",
    ("pacbio_library", "foreign_key"):
        "no registry row for (tube, parent): parent extraction missing or tube registered "
        "to a different parent",
    # type_cast: the row loads with the field null, and the record names the field and keeps the
    # raw value (backfill 'Cast failures', V.4). All are text the lab typed into a numeric or
    # date column; the examples are from live, 2026-10-06.
    ("sample", "type_cast"):
        "text in measurement/coordinate columns: weight 'pup', length ranges, DMS coordinates, "
        "Excel date-times in latitude, depth '<1'",
    ("dna_extraction", "type_cast"):
        "inequalities in ratios ('>1.8', '>2'), size descriptions in av_size ('UHMW', "
        "'12605bp (PEAK) ~50% >10kbp'), partial dates ('2026-03-')",
    ("rna_extraction", "type_cast"): "inequalities in ratios ('>2.0'), two values or 'Fail' in rin",
    ("illumina_library", "type_cast"): "'pooled library = 2.60ng/ul' (84 rows) and 'FAIL' in library_qubit_conc",
    ("hic_library", "type_cast"): "free-text notes typed into library_date",
    ("rna_library_ilmn", "type_cast"): "plate-well IDs ('F07', 'E09') in library_molarity",
    ("sequencing", "type_cast"): "the literal text 'None' in run_date",
    ("hic_lysate", "conflicting_value"):
        "F13: libraries of one lysate disagree on proximity-ligation concentration, so the "
        "value is not promoted; row loads",
    ("rna_library_ilmn", "conflicting_value"):
        "F4/§6.4: Kinnex primer/barcode values on the Illumina RNA table, dropped in v2 and "
        "identical to the rna_library_kinx copies; row loads",
    ("library", "duplicate_source_row"):
        "§4.4: tube ID in both RNA library tables, so it cannot be one registry key",
    ("sequencing", "not_null"): "F6: sequencing rows linked to no library in any of the five live columns",
    ("tissue", "not_null"): "tissue_id blank or the placeholder 0 (lab_key_strategy.md §2)",
    # Written by import_v2.py, never by the backfill. Listed so this script can also be run
    # (for the accounting only) after an import without crying wolf on these.
    ("dna_extraction", "displaced"): "import_v2.py: seated row replaced by the workbook's (V.2)",
}


def qi(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def scalar(sql: str) -> int:
    return int(query(sql)[0][0])


def column_sets():
    v2 = _diff.parse_v2_ddl()
    tables = list(KEYS) + _diff.LCA_TABLES
    live = _diff.live_columns(tables)
    same, retyped = {}, {}
    for t in tables:
        lc, vc = live.get(t, {}), v2.get(t, {})
        same[t] = [c for c in lc if c in vc and lc[c] == vc[c]]
        retyped[t] = [(c, lc[c], vc[c]) for c in lc if c in vc and lc[c] != vc[c]]
    return same, retyped


def accounting(detail: bool) -> int:
    print("=== 1. accounting: every public key loaded or blocked ===")
    print(f"  {'table':18} {'public':>7} {'loaded':>7} {'blocked':>7} {'degraded':>8} "
          f"{'LOST':>5} {'INVENTED':>8}")
    bad = 0
    for t, k in KEYS.items():
        under = ",".join(f"'{s}'" for s in [t] + ALSO_BLOCKED_UNDER.get(t, []))
        base = f"""
            WITH p AS (SELECT DISTINCT {qi(k)} AS k FROM public.{qi(t)}),
                 v AS (SELECT {qi(k)} AS k FROM v2.{qi(t)}),
                 q AS (SELECT DISTINCT source_row_key AS k FROM v2.import_quarantine
                        WHERE resolved_at IS NULL AND source_table IN ({under})
                          AND violation_type <> 'displaced'),
                 d AS (SELECT DISTINCT source_row_key AS k FROM v2.import_quarantine
                        WHERE resolved_at IS NULL AND source_table = '{t}'
                          AND violation_type = 'type_cast')"""
        row = query(base + """
            SELECT (SELECT count(*) FROM p),
                   (SELECT count(*) FROM p WHERE k IN (SELECT k FROM v)),
                   (SELECT count(*) FROM p WHERE k NOT IN (SELECT k FROM v)
                                             AND (k IN (SELECT k FROM q WHERE k IS NOT NULL)
                                                  OR (k IS NULL AND EXISTS (SELECT 1 FROM q WHERE k IS NULL)))),
                   (SELECT count(*) FROM v WHERE k IN (SELECT k FROM d)),
                   (SELECT count(*) FROM p WHERE (k IS NULL OR k NOT IN (SELECT k FROM v))
                                             AND NOT (k IN (SELECT k FROM q WHERE k IS NOT NULL)
                                                      OR (k IS NULL AND EXISTS (SELECT 1 FROM q WHERE k IS NULL)))),
                   (SELECT count(*) FROM v WHERE k NOT IN (SELECT k FROM p WHERE k IS NOT NULL))""")[0]
        pub, loaded, blocked, degraded, lost, invented = map(int, row)
        flag = "  <-- UNEXPLAINED" if lost or invented else ""
        print(f"  {t:18} {pub:7} {loaded:7} {blocked:7} {degraded:8} {lost:5} {invented:8}{flag}")
        bad += lost + invented
        if detail and (lost or invented):
            for label, sql in (
                ("LOST", base + " SELECT coalesce(k, '<null>') FROM p WHERE (k IS NULL OR k NOT IN (SELECT k FROM v)) AND (k IS NULL OR k NOT IN (SELECT k FROM q WHERE k IS NOT NULL)) LIMIT 5"),
                ("INVENTED", base + " SELECT k FROM v WHERE k NOT IN (SELECT k FROM p WHERE k IS NOT NULL) LIMIT 5"),
            ):
                for r in query(sql):
                    print(f"      {label}: {r[0]}")

    for t in ("illumina_library", "pacbio_library", "ont_library", "hic_library",
              "rna_library_ilmn", "rna_library_kinx"):
        k = KEYS[t]
        orphans = scalar(f"SELECT count(*) FROM v2.{qi(t)} x WHERE NOT EXISTS "
                         f"(SELECT 1 FROM v2.library l WHERE l.library_tube_id = x.{qi(k)})")
        if orphans:
            print(f"  {t}: {orphans} rows with no v2.library registry row  <-- UNEXPLAINED")
            bad += orphans
    return bad


def values(same: dict, detail: bool) -> int:
    print("\n=== 2. values on unchanged columns (EXCEPT ALL, both directions) ===")
    bad = 0
    for t, cols in same.items():
        k = KEYS.get(t)
        if t in _diff.LCA_TABLES:
            cols = [c for c in cols if c != "content_hash"]
        if not cols:
            continue
        clist = ", ".join(qi(c) for c in cols)
        if k:
            scope = f"WHERE {qi(k)} IN (SELECT {qi(k)} FROM v2.{qi(t)})"
            p_minus_v = scalar(f"SELECT count(*) FROM (SELECT {clist} FROM public.{qi(t)} {scope} "
                               f"EXCEPT ALL SELECT {clist} FROM v2.{qi(t)}) x")
            v_minus_p = scalar(f"SELECT count(*) FROM (SELECT {clist} FROM v2.{qi(t)} "
                               f"EXCEPT ALL SELECT {clist} FROM public.{qi(t)} {scope}) x")
        else:
            p_minus_v = scalar(f"SELECT count(*) FROM (SELECT {clist} FROM public.{qi(t)} "
                               f"EXCEPT ALL SELECT {clist} FROM v2.{qi(t)}) x")
            v_minus_p = scalar(f"SELECT count(*) FROM (SELECT {clist} FROM v2.{qi(t)} "
                               f"EXCEPT ALL SELECT {clist} FROM public.{qi(t)}) x")
        status = "ok" if p_minus_v == v_minus_p == 0 else "DIFFERS"
        print(f"  {t:20} {len(cols):3} cols   public-v2 {p_minus_v:6}   v2-public {v_minus_p:6}   {status}")
        if status == "ok":
            continue
        if not k:
            print("      no shared key; per-column breakdown not possible  <-- UNEXPLAINED")
            bad += 1
            continue
        for c in cols:
            if c == k:
                continue
            n = scalar(f"SELECT count(*) FROM public.{qi(t)} p JOIN v2.{qi(t)} v USING ({qi(k)}) "
                       f"WHERE p.{qi(c)} IS DISTINCT FROM v.{qi(c)}")
            if not n:
                continue
            rule = VALUE_EXPLAINED.get(f"{t}.{c}")
            if rule:
                pred, why = rule
                outside = scalar(f"SELECT count(*) FROM public.{qi(t)} p JOIN v2.{qi(t)} v USING ({qi(k)}) "
                                 f"WHERE p.{qi(c)} IS DISTINCT FROM v.{qi(c)} AND NOT ({pred})")
                if not outside:
                    print(f"      {c:32} {n:6} differ   explained: {why}")
                    continue
                print(f"      {c:32} {n:6} differ, {outside} outside the explained rule  <-- UNEXPLAINED")
            else:
                print(f"      {c:32} {n:6} differ  <-- UNEXPLAINED")
            bad += 1
            if detail:
                for r in query(f"SELECT {qi(k)}, p.{qi(c)}::text, v.{qi(c)}::text FROM public.{qi(t)} p "
                               f"JOIN v2.{qi(t)} v USING ({qi(k)}) WHERE p.{qi(c)} IS DISTINCT FROM v.{qi(c)} LIMIT 5"):
                    print(f"          {r[0]}: {r[1]!r} -> {r[2]!r}")
    return bad


def retyped_check(retyped: dict, detail: bool) -> int:
    print("\n=== 3. retyped columns: every value the backfill could not cast is recorded ===")
    bad = 0
    for t, cols in retyped.items():
        k = KEYS.get(t)
        if not k or not cols:
            continue
        for c, lt, vt in cols:
            # Same rule as the backfill's pg_temp.cast_failed: blank and explicit NA are
            # "no value", not a failure. Anything else that arrived null was a real value.
            nulled = (f"FROM public.{qi(t)} p JOIN v2.{qi(t)} v USING ({qi(k)}) "
                      f"WHERE nullif(btrim(p.{qi(c)}::text), '') IS NOT NULL "
                      f"AND upper(btrim(p.{qi(c)}::text)) NOT IN ('NA','N/A','-','?') "
                      f"AND v.{qi(c)} IS NULL")
            n = scalar(f"SELECT count(*) {nulled}")
            if not n:
                continue
            unrecorded = f"""{nulled} AND NOT EXISTS (
                SELECT 1 FROM v2.import_quarantine z
                 WHERE z.resolved_at IS NULL AND z.source_table = '{t}'
                   AND z.violation_type = 'type_cast' AND z.source_row_key = p.{qi(k)}::text
                   AND z.violation_detail ~ '(^|; ){c} ?=')"""
            m = scalar(f"SELECT count(*) {unrecorded}")
            flag = "  <-- UNEXPLAINED: nulled with no quarantine record" if m else ""
            print(f"  {t + '.' + c:40} {lt} -> {vt}: {n:4} nulled, {m:4} unrecorded{flag}")
            if m:
                bad += 1
                if detail:
                    for r in query(f"SELECT p.{qi(k)}, p.{qi(c)}::text {unrecorded} LIMIT 5"):
                        print(f"          {r[0]}: {r[1]!r}")
    return bad


def quarantine() -> int:
    print("\n=== 4. open quarantine by class ===")
    bad = 0
    for t, vt, n in query("SELECT source_table, violation_type, count(*) FROM v2.import_quarantine "
                          "WHERE resolved_at IS NULL GROUP BY 1, 2 ORDER BY 1, 2"):
        cause = QUARANTINE_CAUSES.get((t, vt))
        if cause is None:
            bad += 1
        print(f"  {t:18} {vt:21} {int(n):5}   {cause or '<-- UNEXPLAINED: no recorded cause'}")
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--detail", action="store_true", help="print example keys per difference")
    args = ap.parse_args()

    db = query("SELECT current_database(), coalesce(inet_server_addr()::text, 'local socket')")[0]
    print(f"Database: {db[0]} @ {db[1]}\n")
    same, retyped = column_sets()
    bad = accounting(args.detail)
    bad += values(same, args.detail)
    bad += retyped_check(retyped, args.detail)
    bad += quarantine()
    print(f"\n{'-' * 70}\nUNEXPLAINED: {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
