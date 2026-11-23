#!/usr/bin/env python3
"""Which PacBio runs each reference assembly was built from, from its k-mer counts on Acacia. Read-only.

Uses only `rclone lsf`/`rclone cat` against pawsey0964:oceanomics-refassemblies (as
scripts/acacia_read_set_inventory.py).

Method. Merqury counts the 31-mers of the HiFi reads an assembly was built from. A read of length L
has L - 30 of them, so the total over the read histogram is sum(hifi_yield) - 30 * sum(hifi_reads)
over the reads that went in. On OG90 v240821.hic1 that equals OG90H_D2_SBL2_PACB_240821_AD's
hifi_read_qc row to the base (29,867,523,238). So an assembly's runs are the subset of its OG's
PacBio rows whose (yield - 30 * reads) sums to its k-mer total.

Sources of the total, first found:
  meryl/{OG}_v{date}.{ver}.hist               read histogram: sum(multiplicity * count)
  {OG}_v{date}.{ver}/merqury/*.spectra-cn.hist the same reads split by copy number: sum(col2 * col3)

Inputs in DIR: db_asm.tsv (scripts/build_assembly_read_sets.py) and
  db_qc.tsv   SELECT b.og_id, s.sequencing_id, s.seq_date, s.status, sum(q.hifi_yield) AS yield,
                     sum(q.hifi_reads) AS reads, count(q.*) AS qc_rows
              FROM v_sequencing_browse b JOIN sequencing s USING (sequencing_id)
              LEFT JOIN hifi_read_qc q USING (sequencing_id)
              WHERE s.technology IN ('PacBio', 'PacBio HIFI') AND b.library_type = 'pacbio'
              GROUP BY 1, 2, 3, 4
Output: DIR/assembly_kmers.tsv, one row per assembly.
"""
import csv
import itertools
import re
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

D = Path(sys.argv[1])
REF = "pawsey0964:oceanomics-refassemblies"
K = 31


def rd(name):
    with open(D / name) as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def lsf(*includes):
    cmd = ["rclone", "lsf", "-R", "--files-only"]
    for inc in includes:
        cmd += ["--include", inc]
    out = subprocess.run(cmd + [REF], check=True, capture_output=True, text=True).stdout
    return [l for l in out.splitlines() if l]


def total(path):
    r = subprocess.run(["rclone", "cat", f"{REF}/{path}"], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    t = 0
    for line in r.stdout.splitlines():
        f = line.split("\t")
        try:
            t += int(f[0]) * int(f[1]) if len(f) == 2 else int(f[1]) * int(f[2])
        except (ValueError, IndexError):
            continue
    return t


hists = lsf("/OG*/meryl/*_v*.hist")
spectra = lsf("/OG*/OG*_v*/merqury/*.spectra-cn.hist")
by_key = {}
for p in hists:
    m = re.match(r"(OG\d+)/meryl/OG\d+_v(\d{6})\.((?:hic|hifi|ont)\d+)\.hist$", p)
    if m:
        by_key.setdefault(m.groups(), p)
for p in spectra:
    if ".hap" in p.rsplit("/", 1)[1]:
        continue
    m = re.match(r"(OG\d+)/OG\d+_v(\d{6})\.((?:hic|hifi|ont)\d+)/merqury/", p)
    if m:
        by_key.setdefault(m.groups(), p)

asm = rd("db_asm.tsv")
wanted = [(a["og_id"], a["seq_date"], a["version"]) for a in asm]
paths = {k: by_key[k] for k in wanted if k in by_key}
with ThreadPoolExecutor(16) as ex:
    totals = dict(zip(paths, ex.map(total, paths.values())))

runs = defaultdict(list)
for r in rd("db_qc.tsv"):
    runs[r["og_id"]].append(r)


def kmers(r):
    return int(r["yield"]) - (K - 1) * int(r["reads"]) if r["yield"] and r["reads"] else None


with open(D / "assembly_kmers.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["assembly_id", "og_id", "seq_date", "version", "source", "kmer_total",
                "matched_runs", "n_solutions", "nearest_runs", "nearest_ratio", "runs_without_qc"])
    for a in asm:
        key = (a["og_id"], a["seq_date"], a["version"])
        t = totals.get(key)
        cands = runs[a["og_id"]]
        noqc = [c["sequencing_id"] for c in cands if kmers(c) is None]
        sols, best = [], (None, None)
        if t:
            known = [c for c in cands if kmers(c) is not None]
            for n in range(1, len(known) + 1):
                for combo in itertools.combinations(known, n):
                    s = sum(kmers(c) for c in combo)
                    ids = ",".join(sorted(c["sequencing_id"] for c in combo))
                    if s == t:
                        sols.append(ids)
                    ratio = t / s
                    if best[1] is None or abs(ratio - 1) < abs(best[1] - 1):
                        best = (ids, ratio)
        w.writerow([a["assembly_id"], *key, paths.get(key, ""), t or "",
                    sols[0] if len(sols) == 1 else "", len(sols),
                    best[0] or "", f"{best[1]:.6f}" if best[1] else "", ",".join(noqc)])
print("assemblies", len(asm), "with a k-mer total", sum(1 for v in totals.values() if v))
