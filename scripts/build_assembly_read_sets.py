#!/usr/bin/env python3
"""Choose each reference assembly's HiFi read set and runs (migration 093). Read-only.

Inputs in DIR (read-only exports of live, psql -A -F $'\\t' -P footer=off):
  db_asm.tsv     assembly_id, og_id, seq_date, version, pb_links, other_links
                 (pb_links: its PacBio ref_assembly_run rows, comma-separated)
  db_rs.tsv      read_set_id, og_id, seq_date, runs, external, has_gs
  db_pacbio.tsv  as scripts/match_adapter_filter_runs.py
  adapter_filter_files.tsv  scripts/match_adapter_filter_runs.py (each cell's movie -> row)
  assembly_kmers.tsv        scripts/acacia_assembly_kmers.py (runs from merqury k-mer totals)
Outputs in DIR:
  assembly_read_set.tsv     one row per assembly: its runs, where they came from, its read set
  read_set_changes.tsv      read sets to create, and existing read sets whose runs change

Owner, 2026-11-23: every assembly has exactly one read set, the pool of PacBio runs its pipeline
run took in; GenomeScope is per read set. Before choosing, the owner asked for evidence instead of
a default pool, so the assembly's runs come from the first of:

  kmer         merqury's 31-mer total equals sum(hifi_yield - 30 * hifi_reads) over exactly one
               subset of the OG's runs (exact to the base; 91 assemblies whose links already
               matched a read set check out this way)
  kmer_approx  no exact subset, but one subset is within -1%/+6% (hifi_read_qc yields run up to 5%
               short of the reads used on older runs), and every candidate run has hifi_read_qc
  sibling      an assembly of the same OG and date has kmer/kmer_approx runs (all such agree)
  links        its PacBio links equal an existing read set's runs (the 080 date rule)
  same_date    the OG's read set with the assembly's date (its samplesheet, 062)
  cumulative   a read set whose runs equal the OG's non-failed runs available by the assembly's
               date (from its seq_date, or its earliest backed-up movie: OG16 240417 is a movie
               of PACB_240427_LA)
  links_only   its PacBio links, which match no read set
  none         nothing, or an ONT assembly without evidence: a read set with no runs (RG.0: a
               wrong link is worse than none)

k-mer evidence naming a run dated more than 21 days after the assembly's date is not used and is
flagged (OG750 v241004.hic1 matches PACB_250717: the backup was overwritten by a later run).

Read set, for those runs: the OG's read set with exactly those runs; else the read set with the
writers' key for them (the latest seq_date of the runs, or the assembly's date if none), whose runs
are corrected when they come from k-mer evidence (GenomeScope ran in the same pipeline run; OG838
240813's GenomeScope input histogram confirms its single run); else a new read set with that key.
"""
import csv
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

D = Path(sys.argv[1])
EVIDENCE = ("kmer", "kmer_approx", "sibling")


def rd(name):
    with open(D / name) as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def runs(s):
    return tuple(sorted(x for x in (s or "").split(",") if x))


def days(a, b):
    return (datetime.strptime(a, "%y%m%d") - datetime.strptime(b, "%y%m%d")).days


first_movie = {}
for f in rd("adapter_filter_files.tsv"):
    if f["sequencing_id"] and f["tag"].startswith("bc"):
        d = f["movie"].split("_")[1]
        first_movie[f["sequencing_id"]] = min(d, first_movie.get(f["sequencing_id"], d))

available = {}
pb = defaultdict(list)
for r in rd("db_pacbio.tsv"):
    if r["status"] != "Failed" and r["seq_date"]:
        sid = r["sequencing_id"]
        available[sid] = min(r["seq_date"], first_movie.get(sid, r["seq_date"]))
        pb[r["og_id"]].append(sid)

read_sets = defaultdict(list)
for r in rd("db_rs.tsv"):
    r["runs_t"] = runs(r["runs"])
    read_sets[r["og_id"]].append(r)

kmer = {r["assembly_id"]: r for r in rd("assembly_kmers.tsv")}
asm = rd("db_asm.tsv")

# 1. Evidence from the assembly's own k-mers.
ev, flags = {}, defaultdict(list)
for a in asm:
    k = kmer.get(a["assembly_id"])
    if not k or not k["kmer_total"]:
        continue
    if k["matched_runs"]:
        got, src = runs(k["matched_runs"]), "kmer"
    elif (k["nearest_ratio"] and 0.99 <= float(k["nearest_ratio"]) <= 1.06
          and not k["runs_without_qc"]):
        got, src = runs(k["nearest_runs"]), "kmer_approx"
    else:
        if k["nearest_ratio"]:
            flags[a["assembly_id"]].append(f"k-mers unresolved (nearest {k['nearest_runs']} "
                                           f"x{k['nearest_ratio']}; no QC: {k['runs_without_qc']})")
        continue
    late = [s for s in got if days(available.get(s, "991231"), a["seq_date"]) > 21]
    if late:
        flags[a["assembly_id"]].append("k-mers name a run dated after the assembly: " + ",".join(late))
        continue
    ev[a["assembly_id"]] = (got, src)

# 2. Siblings (same OG and date) share evidence when it agrees.
by_run = defaultdict(list)
for a in asm:
    by_run[(a["og_id"], a["seq_date"])].append(a["assembly_id"])
for ids in by_run.values():
    found = {ev[i][0] for i in ids if i in ev}
    if len(found) == 1:
        got = found.pop()
        for i in ids:
            ev.setdefault(i, (got, "sibling"))
    elif len(found) > 1:
        for i in ids:
            flags[i].append("siblings' k-mers disagree")

# 3. Runs for every assembly.
out = []
for a in asm:
    og, date, links = a["og_id"], a["seq_date"], runs(a["pb_links"])
    cum = tuple(sorted(s for s in pb[og] if available[s] <= date))
    rs_og = read_sets[og]
    if a["assembly_id"] in ev:
        target, src = ev[a["assembly_id"]]
    elif a["version"].startswith("ont"):
        target, src = (), "none"          # an ONT assembly: no HiFi pool by date
    elif links and any(r["runs_t"] == links for r in rs_og):
        target, src = links, "links"
    elif any(r["seq_date"] == date for r in rs_og):
        target, src = next(r["runs_t"] for r in rs_og if r["seq_date"] == date), "same_date"
    elif cum and any(r["runs_t"] == cum for r in rs_og):
        target, src = cum, "cumulative"
    elif links:
        target, src = links, "links_only"
    else:
        target, src = (), "none"
    out.append(dict(a=a, target=target, src=src))

# 4. Read sets. A new or corrected read set takes the writers' key (refdb.ensure_read_set, and the
#    ref_read_set comment): the latest seq_date of its runs, or the assembly's date if it has none.
seq_date_of = {r["sequencing_id"]: r["seq_date"] for r in rd("db_pacbio.tsv")}
plan = {}                        # (og, key date) -> runs for a new or corrected read set
for o in out:
    a, target = o["a"], o["target"]
    og, date = a["og_id"], a["seq_date"]
    key = max((seq_date_of[s] for s in target), default=date)
    same = [r for r in read_sets[og] if r["runs_t"] == target]
    if same and (target or any(r["seq_date"] == key for r in same)):
        same.sort(key=lambda r: (r["seq_date"] == key, r["seq_date"]), reverse=True)
        o["rs"], o["action"] = same[0], "existing"
        continue
    at_key = [r for r in read_sets[og] if r["seq_date"] == key]
    if at_key and o["src"] not in EVIDENCE:
        sys.exit(f"{og} {key}: runs {target} from {o['src']} differ from read set "
                 f"{at_key[0]['read_set_id']}; only evidence may correct a read set")
    if at_key and at_key[0]["external"] == "t":
        sys.exit(f"{og} {key}: would correct an external read set")
    o["rs"] = at_key[0] if at_key else None
    o["action"] = "correct" if at_key else "new"
    o["key"] = key
    prev = plan.setdefault((og, key), target)
    if prev != target:
        sys.exit(f"{og} {key}: two assemblies need different runs for one read set")

# A corrected read set must not be one another assembly keeps as it is.
for o in out:
    if o["action"] == "existing":
        k = (o["a"]["og_id"], o["rs"]["seq_date"])
        if k in plan and plan[k] != o["target"]:
            sys.exit(f"{k}: corrected, but assembly {o['a']['assembly_id']} keeps its old runs")

cols = ["assembly_id", "og_id", "seq_date", "version", "runs_from", "runs", "read_set",
        "read_set_id", "read_set_date", "read_set_runs_before", "has_genomescope",
        "pb_links_before", "pb_links_added", "pb_links_removed", "flags"]
with open(D / "assembly_read_set.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(cols)
    for o in out:
        a, rs, target = o["a"], o["rs"], o["target"]
        links = runs(a["pb_links"])
        w.writerow([a["assembly_id"], a["og_id"], a["seq_date"], a["version"], o["src"],
                    ",".join(target), o["action"], rs["read_set_id"] if rs else "",
                    rs["seq_date"] if rs else o["key"],
                    ",".join(rs["runs_t"]) if rs else "",
                    (rs["has_gs"] == "t") if rs else False,
                    ",".join(links), ",".join(sorted(set(target) - set(links))),
                    ",".join(sorted(set(links) - set(target))),
                    "; ".join(flags.get(a["assembly_id"], []))])

with open(D / "read_set_changes.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["og_id", "seq_date", "action", "read_set_id", "runs_before", "runs_after", "has_gs"])
    for (og, date), target in sorted(plan.items()):
        at = [r for r in read_sets[og] if r["seq_date"] == date]
        w.writerow([og, date, "correct" if at else "new", at[0]["read_set_id"] if at else "",
                    ",".join(at[0]["runs_t"]) if at else "", ",".join(target),
                    (at[0]["has_gs"] == "t") if at else False])

c = defaultdict(int)
for o in out:
    c[(o["src"], o["action"])] += 1
print("assemblies", len(out))
for k in sorted(c):
    print(" ", k, c[k])
print("new read sets", sum(1 for k in plan if not any(r["seq_date"] == k[1] for r in read_sets[k[0]])),
      "corrected", sum(1 for k in plan if any(r["seq_date"] == k[1] for r in read_sets[k[0]])))
print("links added", sum(len(set(o["target"]) - set(runs(o["a"]["pb_links"]))) for o in out),
      "removed", sum(len(set(runs(o["a"]["pb_links"])) - set(o["target"])) for o in out),
      "flagged", sum(1 for o in out if flags.get(o["a"]["assembly_id"])))
