#!/usr/bin/env python3
"""Write migration 093's data: sql/data/093_*.tsv and the VALUES blocks the migration inlines.

Usage: python3 scripts/build_093_data.py DIR
DIR holds the outputs of scripts/match_adapter_filter_runs.py, scripts/acacia_assembly_kmers.py and
scripts/build_assembly_read_sets.py (and their db_*.tsv inputs). Read-only on the database.

HiFiAdapterFilt per run (ref_hifi_adapter_filter_run), from the first source that gives a count:
  acacia        the run's backed-up .stats files, summed (adapter_filter_run.tsv)
  single_run    a read set of that one run: ref_hifi_adapter_filter.contam_reads is the run's count
  zero_total    a read set whose stored total is 0: each of its runs removed 0 reads
A run whose sources disagree is refused, except OG57G_D_SBL_PACB_231027_ADLA: both Acacia copies of
movie m64497e_231104_125241 report 1 contaminated read, the stored read-set total is 0, and the
per-cell file is the primary record (owner to confirm).
"""
import csv
import sys
from collections import defaultdict
from pathlib import Path

D = Path(sys.argv[1])
OUT = Path(__file__).resolve().parents[1] / "sql" / "data"
ACCEPTED_DIFFERENCES = {"OG57G_D_SBL_PACB_231027_ADLA"}


def rd(name):
    with open(D / name) as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def q(s):
    return "NULL" if s is None else "'" + str(s).replace("'", "''") + "'"


def arr(items):
    return "ARRAY[" + ", ".join(q(i) for i in items) + "]::text[]" if items else "'{}'::text[]"


# --- per-run adapter counts -----------------------------------------------------------------------
runs = {}
for r in rd("adapter_filter_run.tsv"):
    runs[r["sequencing_id"]] = (int(r["contam_reads"]), "acacia", r["source"])
for r in rd("db_haf.tsv"):
    ids = [s for s in (r["runs"] or "").split(",") if s]
    if r["contam_reads"] == "" or not ids:
        continue
    n = int(r["contam_reads"])
    for sid in ids:
        if len(ids) == 1:
            cand = (n, "single_run", f"ref_hifi_adapter_filter: read set {r['read_set_id']} "
                                     f"({r['og_id']} {r['seq_date']}), its only run")
        elif n == 0:
            cand = (0, "zero_total", f"ref_hifi_adapter_filter: read set {r['read_set_id']} "
                                     f"({r['og_id']} {r['seq_date']}) total 0 over {len(ids)} runs")
        else:
            continue
        if sid in runs:
            if runs[sid][0] != cand[0] and sid not in ACCEPTED_DIFFERENCES:
                sys.exit(f"{sid}: {runs[sid][1]} says {runs[sid][0]}, {cand[1]} says {cand[0]}")
            continue
        runs[sid] = cand

with open(OUT / "093_adapter_filter_run.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["sequencing_id", "contam_reads", "from", "source"])
    for sid in sorted(runs):
        w.writerow([sid, *runs[sid]])

# --- assemblies and read sets ---------------------------------------------------------------------
kmer = {r["assembly_id"]: r for r in rd("assembly_kmers.tsv")}
asm = rd("assembly_read_set.tsv")
with open(OUT / "093_assembly_read_set.tsv", "w", newline="") as fh:
    cols = list(asm[0]) + ["kmer_source", "kmer_total", "kmer_nearest_ratio"]
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(cols)
    for a in asm:
        k = kmer.get(a["assembly_id"], {})
        w.writerow([a[c] for c in asm[0]] + [k.get("source", ""), k.get("kmer_total", ""),
                                              k.get("nearest_ratio", "")])
changes = rd("read_set_changes.tsv")
with open(OUT / "093_read_set_changes.tsv", "w", newline="") as fh:
    w = csv.DictWriter(fh, list(changes[0]), delimiter="\t", lineterminator="\n")
    w.writeheader()
    w.writerows(changes)

split = lambda s: [x for x in (s or "").split(",") if x]

blocks = {}
blocks["adapter"] = ",\n".join(f"  ({q(sid)}, {n}, {q(src + ': ' + detail)})"
                               for sid, (n, src, detail) in sorted(runs.items()))
blocks["read_sets"] = ",\n".join(
    f"  ({q(c['og_id'])}, {q(c['seq_date'])}, {q(c['action'])}, "
    f"{c['read_set_id'] or 'NULL'}, {arr(split(c['runs_before']))}, {arr(split(c['runs_after']))})"
    for c in changes)
blocks["assemblies"] = ",\n".join(
    f"  ({a['assembly_id']}, {q(a['og_id'])}, {q(a['seq_date'])}, {q(a['version'])}, "
    f"{q(a['read_set_date'])}, {arr(split(a['runs']))}, {q(a['runs_from'])})"
    for a in asm)
removed = [(a["assembly_id"], s) for a in asm for s in split(a["pb_links_removed"])]
added = [(a["assembly_id"], s) for a in asm for s in split(a["pb_links_added"])]
blocks["links_removed"] = ",\n".join(f"  ({i}, {q(s)})" for i, s in removed)
blocks["links_added"] = ",\n".join(f"  ({i}, {q(s)})" for i, s in added)
for name, text in blocks.items():
    (D / f"093_{name}.sql").write_text(text + "\n")

src = defaultdict(int)
for n, s, _ in runs.values():
    src[s] += 1
print("adapter runs", len(runs), dict(src), "| assemblies", len(asm), "| read set changes",
      len(changes), "| links added", len(added), "removed", len(removed))
