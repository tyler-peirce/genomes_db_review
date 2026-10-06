#!/usr/bin/env python3
"""Diff the `v2` DDL in sql/035-040 against the live `public` catalog.

Why this exists
---------------
The v2 scaffold was designed, built and constraint-tested on 2026-08-05 and
then left untouched while the live database moved: migrations 017 through 034
landed, including the whole LCA rebuild. Phase V.1 of database_review.md will
not promote that DDL to numbered migrations on the strength of the August
review, and items 1 and 4 of its worklist are a column-by-column re-diff of
the five LCA/mitogenome tables and the twelve lab tables against
information_schema -- explicitly not against the August document.

Doing that by eye is how columns get missed. Running it as a script also means
Phase V.4's reconciliation, which needs the same comparison, does not have to
reinvent it.

What it reports, per table
--------------------------
  live-only      a column live has that the v2 DDL does not declare. v2 would
                 silently drop it at cutover. Each is classified (below);
                 anything landing in UNEXPLAINED is the finding.
  v2-only        a column v2 adds. Expected -- the redesign adds constraints,
                 surrogate keys and the hic_lysate proximity-ligation columns.
  retyped        a column both have with different types. Mostly deliberate
                 (F8 varchar->text, Finding 7 text->date/real/integer, F4a
                 text->boolean), so these are classified too.

Classification
--------------
Every live-only column is matched against EXPLAINED below, which cites the
August finding that removed it. The point of the registry is that the script
gets quieter as the re-review resolves things: a column with a citation is a
recorded decision, a column without one is unfinished work. "Zero UNEXPLAINED"
is the exit criterion for V.1 items 1 and 4.

A column added to the v2 DDL leaves this report entirely -- that is the other
way to resolve one, and the preferred way for anything the lab hand-enters.

Usage
-----
    scripts/diff_v2_against_live.py              # unexplained findings only
    scripts/diff_v2_against_live.py --all        # every difference, classified
    scripts/diff_v2_against_live.py --table lca  # one table

Connection: same resolution as bin/apply_migrations.py -- $DATABASE_URL, then
DB_* environment variables, then ~/postgresql_details/oceanomics.cfg. Reads
only; it never writes to the database it inspects.
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# The v2 DDL lives in the numbered migrations since Phase V.3 (2026-10-06); design/v2/deploy
# was deleted then, so there is one copy to diff.
SQL_DIR = REPO / "sql"
V2_MIGRATIONS = re.compile(r"^\d{3}_v2_.*\.sql$")

_spec = importlib.util.spec_from_file_location(
    "apply_migrations", REPO / "bin" / "apply_migrations.py")
_am = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_am)
query = _am.query

# The twelve lab tables and the five LCA/mitogenome tables: the seventeen
# objects v2 recreates and the seventeen that have no catch-up migration.
LAB_TABLES = [
    "sample", "tissue", "dna_extraction", "rna_extraction", "hic_lysate",
    "library", "illumina_library", "pacbio_library", "ont_library",
    "hic_library", "rna_library_ilmn", "rna_library_kinx", "sequencing",
    "prep_automation",
]
LCA_TABLES = [
    "mitogenome_data", "lca", "lca_validation", "lca_raw_results",
    "blast_filtered_lca",
]

# v2-only tables: the registry (decision 4 / F6) and the automation lookup
# (decision 10 / F12) have no live counterpart, so they are not diffable.
V2_ONLY_TABLES = {"library", "prep_automation"}

# ---------------------------------------------------------------------------
# Why each live column is absent from v2. Key is table.column, or '*.column'
# for a column removed from every table that has it.
# ---------------------------------------------------------------------------
EXPLAINED: dict[str, str] = {
    # F1 -- regexp-derived og_id on child tables contradicts lab_key_strategy
    # 6.0. Ancestry routes through tissue instead.
    "tissue.og_num": "F2 generated og_num raises on an unparseable og_id",
    "dna_extraction.og_id": "F1 derived og_id; reach it via tissue",
    "dna_extraction.og_num": "F2",
    "rna_extraction.og_id": "F1",
    "hic_lysate.og_id": "F1",
    "illumina_library.og_id": "F1",
    "pacbio_library.og_id": "F1",
    "ont_library.og_id": "F1",
    "hic_library.og_id": "F1",
    "rna_library_ilmn.og_id": "F1",
    "rna_library_kinx.og_id": "F1",
    "sequencing.og_id": "F1",
    "sequencing.og_num": "F2",
    # F2 -- og_num is SUBSTRING(og_id FROM 3)::integer, which raises rather
    # than nulls. Available from v2.sample, one indexed join away.
    "lca.og_num": "F2",
    "lca_raw_results.og_num": "F2",
    "lca_validation.og_num": "F2",
    "blast_filtered_lca.og_num": "F2",
    "mitogenome_data.og_num": "F2",
    # F4 -- columns already classified as dead, 0/2675 populated. The live
    # summary view's guards against them have never fired.
    "sample.illumina_sequencing": "F4 dead column, 0/2675 populated",
    "sample.hifi_sequencing": "F4",
    "sample.hic_sequencing": "F4",
    "sample.nanopore_sequencing": "F4",
    "sample.rna_extraction": "F4",
    "sample.rna_ilmn_sequencing": "F4",
    "sample.rna_kinnex_sequencing": "F4",
    "sample.summary_comments": "F4",
    # F5 / decision 5 -- 100%-formula columns from the derived Summary sheet.
    # v2.summary computes them instead.
    "sample.tissues": "F5 100% formula on the Summary sheet; v2.summary derives it",
    "sample.extracted": "F5",
    "sample.extraction_queue": "F5",
    "sample.il_status": "F5",
    "sample.pb_status": "F5",
    "sample.hic_status": "F5",
    "sample.ont_num": "F5 holds NanoPore Status text, not a number",
    "sample.rna_status": "F5",
    "sample.ilrna_status": "F5",
    # Documented as DROPPED notes in the v2 DDL itself rather than in a numbered
    # finding, which is why an earlier pass of this script reported them as
    # unexplained. Each claim was re-verified against live on 2026-10-05 and the
    # numbers are recorded here so the next reader does not have to re-derive them.
    "sample.illumina_public":
        "F4/F5 dead column, verified 0/3294 populated (hifi_public, which v2 keeps, has 8)",
    "tissue.field_id":
        "formula lookup of sample.field_id, verified: 7202/7241 rows match it exactly and "
        "the 27 that differ are the spreadsheet formula returning 0 against a null",
    "rna_library_ilmn.kinnex_primers":
        "F4/6.4 Kinnex fields duplicated onto the Illumina table; verified all 16 populated "
        "rows carry values identical to their rna_library_kinx row, which has 160. No data "
        "is lost by dropping them here; v2.rna_library_kinx keeps both columns",
    "rna_library_ilmn.kinnex_barcode": "F4/6.4, see kinnex_primers",
    "rna_library_kinx.created_at":
        "deliberate: they existed on this table alone out of twelve. NOTE this also retires "
        "the set_updated_at trigger -- see revision 2, do not let it lapse unnoticed",
    "rna_library_kinx.updated_at": "deliberate, see created_at",

    # F6 / decision 4 -- the five nullable polymorphic library columns are
    # replaced by a single FK into the v2.library registry.
    "sequencing.illumina_library_tube_id": "F6 replaced by v2.library registry",
    "sequencing.pacbio_library_tube_id": "F6",
    "sequencing.ont_library_tube_id": "F6",
    "sequencing.hic_library_tube_id": "F6",
    "sequencing.rna_library_tube_id": "F6",
}

# Retypes that cite a finding. Deliberately NARROW: an earlier version of this
# table explained ("text", "integer") and ("double precision", "real") as routine
# Finding 7 conversions, and that blanket rule hid two real defects -- v2 reverting
# migration 022 on blast_filtered_lca.taxon_id and on both confidence columns. A
# retype is only "intended" if it widens or if it converts text to a real type.
# Narrowing anything is a finding until someone says otherwise.
RETYPE_INTENDED = {
    # F8 -- character varying becomes text throughout.
    ("character varying", "text"): "F8 varchar -> text",
    # Finding 7 -- live stores dates and measurements as text.
    ("text", "date"): "Finding 7 text -> real type",
    ("text", "real"): "Finding 7",
    # NOT ("text", "integer") in general -- blast_filtered_lca.taxon_id is text on
    # live because 1,009 rows hold semicolon-separated taxon lists. Listed per
    # column instead, below.
    ("text", "double precision"): "Finding 7",
    ("text", "numeric"): "Finding 7",
    ("text", "timestamp with time zone"): "Finding 7",
    # F4a -- status_overwrite holds 'Y' only; it becomes a real boolean.
    ("text", "boolean"): "F4a / decision 9 Y/N flag -> boolean",
    ("character varying", "boolean"): "F4a / decision 9",
    ("character varying", "date"): "Finding 7 + F8",
    ("character varying", "real"): "Finding 7 + F8",
    ("character varying", "double precision"): "Finding 7 + F8",
    # lca_raw_results.lca_run_date is integer live and text on lca; v2 makes
    # both text so the uniqueness constraints agree (F8).
    ("integer", "text"): "F8 lca_run_date aligned to text across both tables",
    # Measurements the redesign widens from counts to real values (Finding 7).
    ("integer", "real"): "Finding 7 measurement stored as an integer count",
}

# Per-column retypes, where the general rule above is too blunt either way.
RETYPE_INTENDED_COLUMN: dict[str, str] = {
    "sample.workflow": "F8 enum-like varchar -> text",
    "sample.embargo_status": "F8",
    # Storage location. tissue.shelf/rack and dna_extraction.dna_shelf/dna_rack are
    # already integer on live; rna_extraction alone stores them as text, which is the
    # F8/Finding 7 drift the redesign exists to remove. Verified: only 6 of 270 rows
    # are populated and all six hold Excel decimal strings ('4.0', '1.0'), so the
    # backfill must route them through pg_temp.try_int -- a bare ::integer raises.
    "rna_extraction.rna_shelf": "Finding 7 + F8, aligning with the other three tables",
    "rna_extraction.rna_rack": "Finding 7 + F8, aligning with the other three tables",
}

CREATE_RE = re.compile(r"^CREATE TABLE (?:IF NOT EXISTS )?v2\.(\w+)", re.I)
COL_RE = re.compile(
    # Quoted identifiers matter here: lca."order" is a reserved word, and an
    # unquoted pattern silently reads it as absent from the v2 DDL.
    r'^\s+"?(\w+)"?\s+'
    r"(text|boolean|date|real|integer|bigint|numeric(?:\([^)]*\))?|"
    r"double precision|timestamp with time zone|timestamp without time zone|"
    r"character varying(?:\([^)]*\))?|jsonb|uuid|smallint)",
    re.I)
NOT_A_COL = {"constraint", "primary", "foreign", "unique", "check",
             "references", "exclude", "like"}


def parse_v2_ddl() -> dict[str, dict[str, str]]:
    """Declared columns per v2 table, read from the v2 migrations."""
    tables: dict[str, dict[str, str]] = {}
    for path in sorted(p for p in SQL_DIR.glob("*.sql") if V2_MIGRATIONS.match(p.name)):
        current = None
        for line in path.read_text().splitlines():
            if line.lstrip().startswith("--"):
                continue
            m = CREATE_RE.match(line)
            if m:
                current = m.group(1)
                tables[current] = {}
                continue
            if current is None:
                continue
            if line.startswith(")"):
                current = None
                continue
            m = COL_RE.match(line)
            if m and m.group(1).lower() not in NOT_A_COL:
                tables[current][m.group(1)] = normalise(m.group(2))
    return tables


def normalise(t: str) -> str:
    t = t.strip().lower()
    t = re.sub(r"\(.*\)", "", t)
    return {"varchar": "character varying"}.get(t, t).strip()


def live_columns(tables: list[str]) -> dict[str, dict[str, str]]:
    rows = query(
        "SELECT table_name, column_name, data_type FROM information_schema.columns "
        "WHERE table_schema = 'public' AND table_name IN ("
        + ",".join(f"'{t}'" for t in tables) + ") ORDER BY table_name, ordinal_position")
    out: dict[str, dict[str, str]] = {}
    for table, column, dtype in rows:
        out.setdefault(table, {})[column] = normalise(dtype)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true",
                    help="show every difference, not just unexplained ones")
    ap.add_argument("--table", metavar="NAME", help="restrict to one table")
    args = ap.parse_args()

    v2 = parse_v2_ddl()
    if not v2:
        sys.exit(f"No CREATE TABLE v2.* found in {SQL_DIR}/NNN_v2_*.sql")

    wanted = LAB_TABLES + LCA_TABLES
    if args.table:
        if args.table not in wanted:
            sys.exit(f"{args.table} is not one of the seventeen v2 tables")
        wanted = [args.table]

    diffable = [t for t in wanted if t not in V2_ONLY_TABLES]
    live = live_columns(diffable)

    unexplained_total = 0
    missing_from_v2 = []

    for table in wanted:
        if table in V2_ONLY_TABLES:
            if args.all:
                print(f"\n=== {table} ===")
                print("  v2-only table (no live counterpart) -- nothing to diff")
            continue
        if table not in v2:
            missing_from_v2.append(table)
            continue
        lcols, vcols = live.get(table, {}), v2[table]

        live_only = [c for c in lcols if c not in vcols]
        v2_only = [c for c in vcols if c not in lcols]
        retyped = [(c, lcols[c], vcols[c]) for c in lcols
                   if c in vcols and lcols[c] != vcols[c]]

        unexplained = [c for c in live_only
                       if f"{table}.{c}" not in EXPLAINED
                       and f"*.{c}" not in EXPLAINED]
        # A silently narrowed type loses data exactly as surely as a dropped
        # column, so it counts toward the same exit criterion.
        bad_retypes = [(c, lt, vt) for c, lt, vt in retyped
                       if f"{table}.{c}" not in RETYPE_INTENDED_COLUMN
                       and (lt, vt) not in RETYPE_INTENDED]
        unexplained_total += len(unexplained) + len(bad_retypes)

        if not args.all and not unexplained and not bad_retypes:
            continue

        print(f"\n=== {table} ===  live {len(lcols)} cols / v2 {len(vcols)} cols")

        if unexplained:
            print(f"  UNEXPLAINED live-only ({len(unexplained)}) "
                  "-- v2 drops these and no finding says why:")
            for c in unexplained:
                print(f"    {c:38} {lcols[c]}")

        if bad_retypes and not args.all:
            print(f"  UNEXPLAINED retype ({len(bad_retypes)}) "
                  "-- no finding says why the type changes:")
            for c, lt, vt in bad_retypes:
                print(f"    {c:38} {lt} -> {vt}")

        if args.all:
            explained = [c for c in live_only if c not in unexplained]
            if explained:
                print(f"  explained live-only ({len(explained)}):")
                for c in explained:
                    why = EXPLAINED.get(f"{table}.{c}") or EXPLAINED[f"*.{c}"]
                    print(f"    {c:38} {why}")
            if v2_only:
                print(f"  v2-only ({len(v2_only)}):")
                for c in v2_only:
                    print(f"    {c:38} {vcols[c]}")
            if retyped:
                print(f"  retyped ({len(retyped)}):")
                for c, lt, vt in retyped:
                    why = (RETYPE_INTENDED_COLUMN.get(f"{table}.{c}")
                           or RETYPE_INTENDED.get((lt, vt))
                           or "UNEXPLAINED retype")
                    print(f"    {c:38} {lt} -> {vt}   {why}")

    if missing_from_v2:
        print("\n=== tables the v2 DDL does not declare at all ===")
        for t in missing_from_v2:
            print(f"    {t}")

    print(f"\n{'-' * 70}")
    print(f"UNEXPLAINED differences (dropped columns + narrowed types): "
          f"{unexplained_total}")
    if unexplained_total:
        print("Each needs a keep/drop decision recorded in "
              "docs/v2_scaffold_design_review.md revision 2.\n"
              "Keep it  -> add the column to the v2 DDL, and it leaves this report.\n"
              "Drop it  -> add it to EXPLAINED above with the reason.")
    return 1 if unexplained_total else 0


if __name__ == "__main__":
    sys.exit(main())
