#!/usr/bin/env python3
"""Map HiFiAdapterFilt .stats files (one per cell BAM) to PacBio sequencing rows. Read-only.

Inputs in DIR:
  hifiadapt_stats.tsv   scripts/acacia_read_set_inventory.py DIR
  db_pacbio.tsv         SELECT b.og_id, s.sequencing_id, s.run_id, s.seq_date, s.cell_id, s.status,
                               q.barcode
                        FROM v_sequencing_browse b JOIN sequencing s USING (sequencing_id)
                        LEFT JOIN hifi_read_qc q USING (sequencing_id)
                        WHERE s.technology IN ('PacBio', 'PacBio HIFI') AND b.library_type = 'pacbio'
  db_haf.tsv            SELECT s.read_set_id, s.og_id, s.seq_date, h.contam_reads,
                               string_agg of ref_read_set_run.sequencing_id (comma-separated) AS runs
                        FROM ref_read_set s LEFT JOIN ref_hifi_adapter_filter h USING (read_set_id)
Outputs in DIR:
  adapter_filter_files.tsv  one row per distinct .stats file and the sequencing row it maps to
  adapter_filter_run.tsv    one row per sequencing row: contam_reads summed over its files
  adapter_filter_check.tsv  per read set: the stored contam_reads against the per-run sum

Rules (as scripts/match_read_sets.py, 062):
- hifi/ and hifi/qc_stats/ hold copies of one file: deduplicated on (OG, movie, barcode tag),
  and refused if the copies disagree.
- A barcoded file maps to the OG's non-failed PacBio row with that barcode (hifi_read_qc) whose
  seq_date is nearest the movie date, within 21 days. Otherwise to the nearest-dated non-failed
  row within 21 days. A tie is ambiguous and left out.
- An unassigned or unbarcoded file follows the barcoded file of the same movie, else the nearest
  row as above. HiFiAdapterFilt ran on it as part of the OG's reads, so it counts toward the run.
  A zero-count one whose movie's barcoded files map to several rows adds nothing and is skipped.
- Backup directories such as OG90_bc2008/ belong to the OG named by their OG prefix.
- A sequencing row can span several cells ("A01, B01"): its count is the sum over its movies.
"""
import csv
import re
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

D = Path(sys.argv[1])
WINDOW = 21


def rd(name):
    with open(D / name) as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def days(a, b):
    return abs((datetime.strptime(a, "%y%m%d") - datetime.strptime(b, "%y%m%d")).days)


rows = defaultdict(list)          # og -> non-failed PacBio rows
for r in rd("db_pacbio.tsv"):
    if r["status"] != "Failed" and r["seq_date"]:
        rows[r["og_id"]].append(r)


def nearest(cands, movie_date):
    best = sorted((days(c["seq_date"], movie_date), c["sequencing_id"]) for c in cands)
    best = [b for b in best if b[0] <= WINDOW]
    if not best:
        return None, "no row within 21 days"
    ties = sorted({b[1] for b in best if b[0] == best[0][0]})
    if len(ties) > 1:
        return None, "tie: " + ",".join(ties)
    return ties[0], ""


files = {}
for f in rd("hifiadapt_stats.tsv"):
    if not f["movie"] or f["contam_reads"] == "":
        continue
    m = re.search(r"\.(bc\d+(?:--bc\d+)?|unassigned)\.stats$", f["path"])
    tag = m.group(1) if m else "none"
    og = re.match(r"OG\d+", f["og_id"]).group(0)   # OG90_bc2008/ holds OG90's second library
    key = (og, f["movie"], tag)
    if key in files and files[key]["contam_reads"] != f["contam_reads"]:
        sys.exit(f"copies disagree: {key}")
    files.setdefault(key, f)

by_movie = defaultdict(dict)
for (og, movie, tag), f in files.items():
    by_movie[(og, movie)][tag] = f

out = []
for (og, movie), tags in sorted(by_movie.items()):
    movie_date = next(iter(tags.values()))["movie_date"]
    barcoded = {}
    for tag, f in tags.items():
        if tag.startswith("bc"):
            bc = tag.split("--")[-1]
            cands = [c for c in rows[og] if c["barcode"] == bc]
            sid, why = nearest(cands, movie_date) if cands else (None, "barcode not in hifi_read_qc")
            if sid is None and not cands:
                sid, why = nearest(rows[og], movie_date)
                why = why or "by date (barcode not in hifi_read_qc)"
            barcoded[tag] = sid
            out.append((og, movie, tag, f, sid, why))
    for tag, f in tags.items():
        if tag.startswith("bc"):
            continue
        sids = {s for s in barcoded.values() if s}
        if len(sids) == 1:
            out.append((og, movie, tag, f, sids.pop(), "follows the movie's barcoded file"))
        elif len(sids) > 1 and int(f["contam_reads"]) == 0:
            continue                       # adds nothing to either row
        elif len(sids) > 1:
            out.append((og, movie, tag, f, None, "movie's barcoded files map to several rows"))
        else:
            sid, why = nearest(rows[og], movie_date)
            out.append((og, movie, tag, f, sid, why or "by date"))

per_run = defaultdict(lambda: [0, 0, []])
with open(D / "adapter_filter_files.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["og_id", "movie", "tag", "path", "contam_reads", "sequencing_id", "note"])
    for og, movie, tag, f, sid, why in out:
        w.writerow([og, movie, tag, f["path"], f["contam_reads"], sid or "", why])
        if sid:
            pr = per_run[sid]
            pr[0] += int(f["contam_reads"])
            pr[1] += 1
            pr[2].append(f["path"])

with open(D / "adapter_filter_run.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["sequencing_id", "contam_reads", "n_files", "source"])
    for sid, (n, k, paths) in sorted(per_run.items()):
        w.writerow([sid, n, k, "oceanomics-filtered-reads:" + ";".join(sorted(paths))])

agree = disagree = nodb = missing = 0
with open(D / "adapter_filter_check.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["read_set_id", "og_id", "seq_date", "n_runs", "db_contam_reads", "per_run_sum",
                "runs_without_file", "result"])
    for r in rd("db_haf.tsv"):
        runs = [s for s in (r["runs"] or "").split(",") if s]
        lacking = [s for s in runs if s not in per_run]
        total = sum(per_run[s][0] for s in runs if s in per_run)
        if not runs:
            res = "no runs"
        elif lacking:
            res = "run(s) without a file"
            missing += 1
        elif r["contam_reads"] == "":
            res = "no stored value"
            nodb += 1
        elif int(r["contam_reads"]) == total:
            res = "equal"
            agree += 1
        else:
            res = "differs"
            disagree += 1
        w.writerow([r["read_set_id"], r["og_id"], r["seq_date"], len(runs), r["contam_reads"],
                    total if runs and not lacking else "", ",".join(lacking), res])

print(f"files {len(files)}, mapped {sum(1 for o in out if o[4])}, unmapped "
      f"{sum(1 for o in out if not o[4])}, runs {len(per_run)}")
print(f"read sets: equal {agree}, differs {disagree}, no stored value {nodb}, "
      f"run(s) without a file {missing}")
