#!/usr/bin/env python3
"""Read-only inventory of GenomeScope / HiFiAdapterFilt evidence on Acacia.

Uses only `rclone lsjson` and `rclone cat` (stdout), against the `pawsey0964:` remote. Writes
genomescope.tsv, hifiadapt_stats.tsv and versions.tsv into the directory given; feed them to
scripts/match_read_sets.py. Backup layout: OceanOmics-OceanGenomes-ref-genomes
scripts/04_backup_scripts/{full,hifi_only}_assembly_backup.sh.

Usage: python3 scripts/acacia_read_set_inventory.py OUT_DIR
"""
import csv
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
REF = "pawsey0964:oceanomics-refassemblies"
FILT = "pawsey0964:oceanomics-filtered-reads"


def lsjson(remote, *includes, files=True):
    cmd = ["rclone", "lsjson", "-R"] + (["--files-only"] if files else ["--dirs-only"])
    for inc in includes:
        cmd += ["--include", inc]
    return json.loads(subprocess.run(cmd + [remote], check=True, capture_output=True, text=True).stdout)


def cat(path):
    r = subprocess.run(["rclone", "cat", path], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def gs_values(text):
    """The 'max' column, as 01_genomescope-compile.sh reads it."""
    rows = [re.split(r"\s{2,}", l.strip()) for l in text.splitlines() if l.strip()]
    vals = [r[2].split()[0] if len(r) > 2 else "" for r in rows][-8:]
    keys = ["header", "homozygosity", "heterozygosity", "genomesize", "repeatsize",
            "uniquesize", "modelfit", "errorrate"]
    return dict(zip(keys, vals))


def main():
    gs = lsjson(REF, "/OG*/genomescope/*_summary.txt")
    with ThreadPoolExecutor(16) as ex:
        texts = list(ex.map(lambda f: cat(f"{REF}/{f['Path']}"), gs))
    with open(OUT / "genomescope.tsv", "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["og_id", "path", "modtime", "homozygosity", "heterozygosity", "genomesize",
                    "repeatsize", "uniquesize", "modelfit", "errorrate"])
        for f, t in zip(gs, texts):
            v = gs_values(t or "")
            w.writerow([f["Path"].split("/")[0], f["Path"], f["ModTime"]] +
                       [v.get(k, "") for k in ["homozygosity", "heterozygosity", "genomesize",
                                               "repeatsize", "uniquesize", "modelfit", "errorrate"]])

    st = lsjson(FILT, "/OG*/hifi/**.stats")
    with ThreadPoolExecutor(16) as ex:
        texts = list(ex.map(lambda f: cat(f"{FILT}/{f['Path']}"), st))
    with open(OUT / "hifiadapt_stats.tsv", "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["og_id", "path", "modtime", "movie", "movie_date", "contam_reads"])
        for f, t in zip(st, texts):
            m = re.search(r"(m\d+[a-z]?_(\d{6})_\d{6}(?:_s\d)?)", f["Name"])
            c = re.search(r"Number of adapter contaminated ccs reads:\s*(\d+)", t or "")
            w.writerow([f["Path"].split("/")[0], f["Path"], f["ModTime"],
                        m.group(1) if m else "", m.group(2) if m else "", c.group(1) if c else ""])

    # Version evidence: meryl files and assembly folders carry {OG}_v{YYMMDD}.{ver}
    me = lsjson(REF, "/OG*/meryl/**")
    dirs = lsjson(REF, "/OG*/OG*_v*/**", files=False)
    with open(OUT / "versions.tsv", "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["og_id", "kind", "path", "modtime", "seq_date", "version"])
        seen = set()
        for kind, items in (("meryl", me), ("asm_dir", dirs)):
            for f in items:
                m = re.search(r"_v(\d{6})[._]?((?:hic|hifi|ont)\d+)?", f["Path"])
                if not m:
                    if kind == "meryl":
                        m2 = re.search(r"_v?(\d{6})_meryl", f["Path"])
                        if m2:
                            w.writerow([f["Path"].split("/")[0], kind, f["Path"], f["ModTime"], m2.group(1), ""])
                    continue
                key = (kind, f["Path"].split("/")[0], m.group(1), m.group(2))
                if kind == "asm_dir" and key in seen:
                    continue
                seen.add(key)
                w.writerow([f["Path"].split("/")[0], kind, f["Path"], f["ModTime"], m.group(1), m.group(2) or ""])
    print("genomescope", len(gs), "stats", len(st), "meryl", len(me), "dirs", len(dirs))


main()
