#!/usr/bin/env python3
"""Check the v2 importer's header mappings against a lab workbook.

Why this exists
---------------
`scripts/diff_v2_against_live.py` compares the v2 DDL to the database. Nothing
compared `name_convert_v2.py` to the workbook, and that is the gap four Phase V
defects came through (docs/v2_scaffold_design_review.md section 0.8): a header
the lab renamed, a header the lab removed, a mapping that spelled an embedded
newline as CRLF when the cell holds a bare LF, and a 383-row column mapped to
nothing. Every one of them reaches the database as a NULL, which looks exactly
like a value nobody entered -- so running the importer does not reveal them,
and neither does reading the database.

`import_v2.py`'s unmatched-header report is not a substitute. It lists headers
with no mapping; it says nothing about a mapping with no header, which is the
direction three of the four failed in.

What it reports
---------------
  dead           a (table, column) mapping none of whose headers appears on any
                 of the table's sheets. The column will load as NULL on every row.
  invisible      a mapping that matches a header only after whitespace is
                 normalised (CR/LF/tab/repeated spaces collapsed, ends stripped).
                 Exact-match importers silently miss these; it is reported even
                 once the importer normalises, because a mapping should say what
                 the workbook says.
  unmapped       a populated workbook header that no mapping reads. v2 never sees
                 that data. Empty unmapped headers are listed only with --all.

Classification
--------------
As in diff_v2_against_live.py, every finding is matched against EXPLAINED
below, and an entry must cite why it is acceptable. Anything left over is the
finding. "Zero UNEXPLAINED" is the exit criterion for Phase V.2's mapping fixes
and the pre-flight check for Phase V.3.

The workbook is not under version control and carries its date in its
filename, so the report header prints the filename. Quote it beside any figure
taken from this output.

Usage
-----
    scripts/check_v2_mappings.py -e OceanGenomes_Database_261006.xlsx
    scripts/check_v2_mappings.py -e <workbook> --all     # every mapping, with counts
    scripts/check_v2_mappings.py -e <workbook> --importer-repo ../OceanOmics-Database

Needs pandas and openpyxl, as import_v2.py does. Reads the workbook only; it
never connects to a database.
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
import warnings
from pathlib import Path

import pandas as pd

REPO = Path(__file__).resolve().parent.parent
DEFAULT_IMPORTER_REPO = REPO.parent / "OceanOmics-Database"

# openpyxl warns once per sheet about the workbook's data-validation extension.
warnings.filterwarnings("ignore", message="Data Validation extension is not supported")

# ---------------------------------------------------------------------------
# Why each finding is acceptable. Keys:
#   "dead table.column" / "invisible table.column" / "unmapped Sheet | header"
# Headers are written normalised (see normalise()). A '*' sheet matches every
# sheet, for the blocks of lookup columns repeated across the child sheets.
# ---------------------------------------------------------------------------
#
# "100% formula" below means every non-empty cell in the column is a formula
# and none is a typed value, measured cell by cell with openpyxl
# (data_only=False) on OceanGenomes_Database_261006.xlsx. Those columns are
# lookups or derivations; the data they show is stored where it is typed.
# ---------------------------------------------------------------------------
EXPLAINED: dict[str, str] = {
    # The lookup block repeated on the child sheets: identity of the specimen,
    # fetched from 1.MetaData / 2.Tissue by the row's parent ID.
    "unmapped * | OG": "100% formula (INDEX/MATCH into 1.MetaData) on every child sheet; "
                       "on 1.MetaData itself it is the numeric half of Specimen ID, which is mapped",
    "unmapped * | Specimen ID": "100% formula (XLOOKUP/VLOOKUP) on every child sheet; "
                                "v2 reaches it through the parent FK chain (F1)",
    "unmapped * | Project ID": "100% formula lookup into MetaData on every child sheet",
    "unmapped * | Nominal Species ID": "100% formula lookup into MetaData on every child sheet",
    "unmapped * | Common Name/s": "100% formula lookup into MetaData on every child sheet",
    "unmapped * | Tissue Box": "100% formula lookup into 2.Tissue[Box Label], which is mapped",
    "unmapped * | Latest": "100% array formula, MAX(#) per parent; v2 browse views derive it (F4a)",
    "unmapped 2.Tissue | Field Identifier": "formula lookup into MetaData on 7,132 of 7,150 rows; "
                                            "the 18 typed values are pasted-over lookups (diff "
                                            "script: tissue.field_id matches sample 7,202/7,241)",
    "unmapped 4.Illumina | Field Identifier": "100% formula lookup into MetaData",
    "unmapped 3.DNAExtractions | Column1": "100% formula, INDEX/MATCH into 1.MetaData -- the OG "
                                           "number under a default table-column name",
    "unmapped 4.Illumina | ": "100% formula, INDEX/MATCH into 1.MetaData -- the OG number under "
                              "a header that is a single space",
    "unmapped 4.RNAIllumina | Sample ID": "100% formula, derived from Library Prep Method",
    "unmapped 4.RNAkinnex | Sample ID": "100% formula, derived from Library Prep Method",
    "unmapped * | DNA Conc. (ng/uL)": "100% formula, XLOOKUP into 3.DNAExtractions Qubit Conc.",
    "unmapped * | Average size (bp)": "100% formula on the library sheets, XLOOKUP into "
                                      "3.DNAExtractions; hand-entered there and mapped",
    "unmapped * | RNA Conc. (ng/uL)": "100% formula, XLOOKUP into 3.RNAExtractions",
    "unmapped * | RIN": "100% formula on the RNA library sheets, XLOOKUP into "
                        "3.RNAExtractions RIN, which is mapped",
    "unmapped 4.HiCLysate | Proximity Ligation yield (ng)":
        "100% formula, =IF(R=\"NA\",\"NA\",R*40). The 306 cached values on rows with no "
        "concentration are all 0.0, not measurements; v2.hic_lysate.prox_ligation_yield "
        "generates conc*40 (F13). Corrects design review 0.8, which read them as data",
    # F5 / decision 5 -- the derived Summary-sheet rollups. v2.summary computes them.
    "unmapped Summary | Tissues": "F5, 100% formula (COUNTIF over 2.Tissue)",
    "unmapped Summary | Extracted": "F5, 100% formula (COUNTIFS over 3.DNAExtractions)",
    "unmapped Summary | DNA Extraction Status": "F5, 100% array formula",
    "unmapped Summary | Illumina Status": "F5, 100% array formula",
    "unmapped Summary | PacBio Status": "F5, 100% array formula",
    "unmapped Summary | HiC Status": "F5, 100% array formula",
    "unmapped Summary | NanoPore Status": "F5, 100% array formula",
    "unmapped Summary | RNA Extraction Status": "F5, 100% array formula",
    "unmapped Summary | Illumina RNA Status": "F5, 100% array formula",
    "unmapped Summary | RNA Kinnex Status": "F5, 100% array formula",
    # Hand-entered, and not stored by owner decision 2026-10-06.
    "unmapped Summary | RNA processing comment":
        "25 rows of free text; owner decision 2026-10-06 not to add a column",
    "unmapped 4.HiCLibrary | Column1":
        "2 free-text notes under an untitled column; owner decision 2026-10-06 not to store "
        "them -- the lab should move them into Comments",
    # Hand-entered, but deliberately not stored as its own column.
    "unmapped 2.Tissue | #": "hand-entered tissue index; it is the input to the Sample ID "
                             "formula, so it is already carried in tissue_id. A separate "
                             "tissue_index column is deferred to Phase H (lab_key_strategy.md "
                             "6.2) until v2 enforces the ID grammar",
}

NULLISH = {"", "na", "n/a", "-", "?", "none", "nan"}


def normalise(header: object) -> str:
    """Collapse every run of whitespace, including CR and LF, to one space."""
    return re.sub(r"\s+", " ", str(header)).strip()


def load_mapping(importer_repo: Path):
    path = importer_repo / "name_convert_v2.py"
    if not path.exists():
        sys.exit(f"{path} not found; pass --importer-repo")
    spec = importlib.util.spec_from_file_location("name_convert_v2", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def as_list(x):
    return x if isinstance(x, list) else [x]


def populated(series: pd.Series) -> int:
    return int(sum(1 for v in series
                   if not pd.isna(v) and str(v).strip().lower() not in NULLISH))


def explained(key: str) -> str | None:
    if key in EXPLAINED:
        return EXPLAINED[key]
    if key.startswith("unmapped "):
        sheet, _, header = key[len("unmapped "):].partition(" | ")
        return EXPLAINED.get(f"unmapped * | {header}")
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-e", "--excel", required=True, type=Path, help="lab workbook (.xlsx)")
    ap.add_argument("--importer-repo", type=Path, default=DEFAULT_IMPORTER_REPO,
                    help=f"checkout holding name_convert_v2.py (default {DEFAULT_IMPORTER_REPO})")
    ap.add_argument("--all", action="store_true",
                    help="also list every working mapping and every explained finding")
    args = ap.parse_args()

    nc = load_mapping(args.importer_repo)
    xls = pd.ExcelFile(args.excel)

    # sheet -> {raw header: populated count}
    sheets: dict[str, dict[str, int]] = {}
    for spec in nc.DB_TO_EXCEL.values():
        for sheet in as_list(spec["sheets"]):
            if sheet in sheets:
                continue
            if sheet not in xls.sheet_names:
                sheets[sheet] = {}
                continue
            df = pd.read_excel(xls, sheet)
            sheets[sheet] = {str(h): populated(df[h]) for h in df.columns
                             if not str(h).startswith("Unnamed")}

    findings: list[tuple[str, str]] = []      # (key, detail)
    working: list[str] = []
    read_exactly: dict[str, set[str]] = {s: set() for s in sheets}
    read_normalised: dict[str, set[str]] = {s: set() for s in sheets}

    print(f"Workbook: {args.excel.name}")
    print(f"Mapping:  {args.importer_repo / 'name_convert_v2.py'}\n")

    missing_sheets = [s for s in sheets if s not in xls.sheet_names]
    for s in missing_sheets:
        findings.append((f"sheet {s}", "sheet named in DB_TO_EXCEL is absent from the workbook"))

    for table, spec in nc.DB_TO_EXCEL.items():
        table_sheets = as_list(spec["sheets"])
        for col, headers in spec["cols"].items():
            exact, fuzzy = [], []
            for sheet in table_sheets:
                by_norm = {normalise(h): h for h in sheets[sheet]}
                for want in as_list(headers):
                    if want in sheets[sheet]:
                        exact.append((sheet, want, sheets[sheet][want]))
                        read_exactly[sheet].add(want)
                    elif normalise(want) in by_norm:
                        got = by_norm[normalise(want)]
                        fuzzy.append((sheet, want, got, sheets[sheet][got]))
                        read_normalised[sheet].add(got)
            if exact:
                n = sum(e[2] for e in exact)
                working.append(f"{table}.{col} <- "
                               + ", ".join(f"{s}:{h!r}" for s, h, _ in exact)
                               + f"  ({n} populated)")
            for sheet, want, got, n in fuzzy:
                findings.append((f"invisible {table}.{col}",
                                 f"mapped {want!r} matches {sheet}:{got!r} only after "
                                 f"whitespace normalisation ({n} populated)"))
            if not exact and not fuzzy:
                findings.append((f"dead {table}.{col}",
                                 "no header among " + repr(as_list(headers)) + " on "
                                 + ", ".join(table_sheets)))

    for sheet, headers in sheets.items():
        for h, n in headers.items():
            if h in read_exactly[sheet] or h in read_normalised[sheet]:
                continue
            if n == 0 and not args.all:
                continue
            findings.append((f"unmapped {sheet} | {normalise(h)}",
                             f"{n} populated" + (f"; raw header {h!r}" if h != normalise(h) else "")))

    unexplained = [(k, d) for k, d in findings if explained(k) is None]
    accepted = [(k, d, explained(k)) for k, d in findings if explained(k) is not None]

    if args.all:
        print(f"WORKING MAPPINGS ({len(working)})")
        for w in working:
            print(f"  {w}")
        print()
        print(f"EXPLAINED ({len(accepted)})")
        for k, d, why in accepted:
            print(f"  {k}: {d}\n      -> {why}")
        print()

    print(f"UNEXPLAINED ({len(unexplained)})")
    for k, d in unexplained:
        print(f"  {k}: {d}")
    if not unexplained:
        print("  (none)")

    stale = [k for k in EXPLAINED
             if not any(k == f or (k.startswith("unmapped * | ")
                                   and f.startswith("unmapped ")
                                   and f.endswith(" | " + k[len("unmapped * | "):]))
                        for f, _ in findings)]
    if stale:
        # Not a failure: an entry stops matching when the lab deletes a lookup
        # column or a mapping is fixed. Listed so the registry gets pruned.
        print(f"\nEXPLAINED entries that no longer match anything ({len(stale)}):")
        for k in stale:
            print(f"  {k}")

    return 1 if unexplained else 0


if __name__ == "__main__":
    sys.exit(main())
