#!/usr/bin/env python3
"""Inventory everything in the database that reads the seventeen tables v2 replaces.

Why this exists
---------------
Phase V.1 item 5 re-audits the views that depend on the tables v2 recreates.
`docs/v2_cutover_dependencies.md` did that once, in August, by reading view
definitions by eye, and it missed things an eye will always miss:

  - it audited the views reading the TWELVE lab tables, but v2 recreates
    SEVENTEEN -- the five LCA/mitogenome tables count too, which is how
    `mitogenome_submission_view` escaped the audit entirely while selecting
    `m.og_num` straight out of `mitogenome_data`, a column v2 removes;
  - it classified `embargo_assignment_view` as a plain reader of seven sample
    columns. It carries an INSTEAD OF UPDATE trigger and writes to `sample`;
  - it did not look at functions at all. Eleven of this database's own
    functions reference these tables with unqualified names and none pins a
    search_path, so every one of them silently follows the cutover -- including
    six `build_*_samplesheet*` functions that generate Nextflow samplesheets.

So this is a catalog sweep rather than a reading exercise. It is also the half
of the abandoned Phase V.0 that never needed a fortnight of logging: anything
inside the database is already in pg_depend, pg_trigger and pg_proc, and only
EXTERNAL clients needed the log_statement work.

Phase V.5 should re-run this on the morning of the cutover. The set of
dependents is not static, and "what reads this table?" is a question worth
having a command for.

Usage
-----
    scripts/audit_v2_dependents.py                # the full report
    scripts/audit_v2_dependents.py --unpinned     # just the search_path risks

Connection: same resolution as bin/apply_migrations.py. Reads only.
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location(
    "apply_migrations", REPO / "bin" / "apply_migrations.py")
_am = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_am)
query = _am.query

REPLACED = [
    "sample", "tissue", "dna_extraction", "rna_extraction", "hic_lysate",
    "illumina_library", "pacbio_library", "ont_library", "hic_library",
    "rna_library_ilmn", "rna_library_kinx", "sequencing",
    "mitogenome_data", "lca", "lca_validation", "lca_raw_results",
    "blast_filtered_lca",
]
IN_LIST = ",".join(f"'{t}'" for t in REPLACED)

# Dispositions recorded by the Phase V.1 re-review, 2026-10-05. A function
# missing from this table is an unreviewed search_path risk, which is the point
# of listing them: the report nags until each has an answer.
DISPOSITION = {
    "lca_validation_report_view_upd":
        "FOLLOW -- writes the four editable columns of lca_validation, all of which exist "
        "in v2.lca_validation. Must not be pinned: after cutover the edit belongs in v2.",
    "embargo_assignment_view_upd":
        "FOLLOW -- writes sample columns that all survive into v2.sample.",
    "test_embargo_assignment_view_upd":
        "FOLLOW -- test harness for the above; follows it either way.",
    "lca_set_content_hash":
        "PIN to public. v2 has its own v2.lca_set_content_hash() with a pinned search_path, "
        "so the public one should stay bound to public and retire with the public tables.",
    "set_updated_at":
        "PIN to public. Its only trigger is on public.rna_library_kinx.updated_at, and v2 "
        "drops created_at/updated_at deliberately -- so this function has no v2 counterpart "
        "and must not follow the swap into a table without the column.",
    "build_final_data_compile":
        "REVIEW -- reads lca_validation and sample. Needs the column check below before "
        "cutover; pipeline-facing, so it needs the pipeline owners' sign-off either way.",
    "build_nfcore_samplesheet_rows":
        "REVIEW -- reads sample and sequencing. sequencing loses its five library tube-ID "
        "columns under F6, so this is the most likely to need a rewrite.",
    "build_hicpost_samplesheet_rows": "REVIEW -- as build_nfcore_samplesheet_rows.",
    "build_postcuration_samplesheet_rows": "REVIEW -- as build_nfcore_samplesheet_rows.",
    "build_rna_kinx_samplesheet_from_run":
        "REVIEW -- reads rna_library_kinx and sequencing.",
    "build_rna_kinx_samplesheet_rows": "REVIEW -- reads rna_library_kinx.",
}


def rows(sql):
    return query(sql)


def views():
    return rows(f"""
        SELECT v.relname,
               string_agg(DISTINCT t.relname, ', ' ORDER BY t.relname),
               (SELECT count(*) FROM pg_trigger g
                 WHERE g.tgrelid = v.oid AND NOT g.tgisinternal)::text
        FROM pg_class v
        JOIN pg_rewrite r ON r.ev_class = v.oid
        JOIN pg_depend d ON d.objid = r.oid
             AND d.classid = 'pg_rewrite'::regclass
             AND d.refclassid = 'pg_class'::regclass
        JOIN pg_class t ON t.oid = d.refobjid AND t.oid <> v.oid
        WHERE v.relkind = 'v' AND v.relnamespace = 'public'::regnamespace
          AND t.relname IN ({IN_LIST})
          AND v.relname NOT LIKE '%\\_SS260818'
        GROUP BY v.relname, v.oid
        ORDER BY v.relname""")


def triggers():
    return rows(f"""
        SELECT g.tgrelid::regclass::text, g.tgname, p.proname
        FROM pg_trigger g
        JOIN pg_proc p ON p.oid = g.tgfoid
        JOIN pg_class c ON c.oid = g.tgrelid
        WHERE NOT g.tgisinternal
          AND g.tgrelid::regclass::text NOT LIKE '%SS260818%'
          AND c.relnamespace = 'public'::regnamespace
        ORDER BY 1, 2""")


def functions():
    clauses = " OR ".join(
        f"p.prosrc ~ '\\m{t}\\M'" for t in REPLACED)
    return rows(f"""
        SELECT p.proname,
               coalesce(array_to_string(p.proconfig, ', '), ''),
               (SELECT string_agg(x, ', ' ORDER BY x) FROM unnest(ARRAY[{IN_LIST}]) x
                 WHERE p.prosrc ~ ('\\m' || x || '\\M'))
        FROM pg_proc p
        WHERE p.pronamespace = 'public'::regnamespace
          AND p.prolang <> (SELECT oid FROM pg_language WHERE lanname = 'c')
          AND (({clauses})
               -- A trigger function can touch a replaced table without naming it:
               -- set_updated_at only ever references NEW. Catch those by attachment.
               OR EXISTS (SELECT 1 FROM pg_trigger g
                          JOIN pg_class c ON c.oid = g.tgrelid
                          LEFT JOIN pg_rewrite r ON r.ev_class = c.oid
                          LEFT JOIN pg_depend d ON d.objid = r.oid
                               AND d.classid = 'pg_rewrite'::regclass
                               AND d.refclassid = 'pg_class'::regclass
                          LEFT JOIN pg_class bt ON bt.oid = d.refobjid
                          WHERE g.tgfoid = p.oid AND NOT g.tgisinternal
                            AND c.relnamespace = 'public'::regnamespace
                            AND (c.relname IN ({IN_LIST})
                                 OR bt.relname IN ({IN_LIST}))))
        ORDER BY p.proname""")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--unpinned", action="store_true",
                    help="only the functions with no pinned search_path")
    args = ap.parse_args()

    fns = functions()
    unreviewed = [f for f in fns if f[0] not in DISPOSITION]
    unpinned = [f for f in fns if not f[1]]

    if not args.unpinned:
        vs = views()
        print(f"=== views reading the seventeen replaced tables ({len(vs)}) ===")
        print("A view binds to table OIDs, so none of these follows a search_path change on")
        print("its own. Every one needs CREATE OR REPLACE at cutover (not DROP -- that takes")
        print("the INSTEAD OF triggers with it).\n")
        for name, reads, trg in vs:
            mark = "  WRITABLE" if trg != "0" else ""
            print(f"  {name:34}{mark}")
            print(f"      reads: {reads}")

        trg = triggers()
        print(f"\n=== triggers on public objects ({len(trg)}) ===")
        for rel, name, fn in trg:
            print(f"  {rel:30} {name:38} -> {fn}")

    print(f"\n=== functions referencing the replaced tables ({len(fns)}) ===")
    print("Unqualified references in an unpinned function resolve against the CALLER's")
    print("search_path at execution time, so these follow the cutover whether or not")
    print("anyone intends it.\n")
    for name, cfg, reads in fns:
        state = cfg if cfg else "NOT PINNED"
        print(f"  {name:38} {state}")
        print(f"      reads:       {reads}")
        print(f"      disposition: {DISPOSITION.get(name, '*** UNREVIEWED ***')}")

    print(f"\n{'-' * 70}")
    print(f"functions referencing replaced tables: {len(fns)}")
    print(f"  with no pinned search_path:          {len(unpinned)}")
    print(f"  with no recorded disposition:        {len(unreviewed)}")
    if unreviewed:
        print("\nEach unreviewed function needs one of pin / follow / rewrite recorded in")
        print("docs/v2_scaffold_design_review.md before Phase V.5.")
        for f in unreviewed:
            print(f"    {f[0]}")
    return 1 if unreviewed else 0


if __name__ == "__main__":
    sys.exit(main())
