#!/usr/bin/env python3
"""The flowcell of every Hi-C run on S3. Read-only: rclone lsjson / lsf / cat against
s3:ocom.oceangenomes/illumina-hic (one folder per run, as scripts/match_sra_uploads.py).

Two independent sources per run (migration 094):
  - the first read name of every R1 FASTQ under the run folder: instrument:run_number:flowcell:lane;
  - the BaseSpace run record saved beside it (<run>/<run>_<id>.json): FlowcellBarcode,
    InstrumentName, Number, ExperimentName.
On 2026-11-23 every run folder had exactly one flowcell in its read names, and for the 31 runs with a
saved record it equalled FlowcellBarcode. The 6 newest runs have no saved record.

Usage: s3_hic_run_flowcells.py OUTDIR
Writes OUTDIR/s3_hic_fastq_flowcells.tsv (one row per R1 FASTQ) and OUTDIR/s3_hic_run_json.tsv.
"""
import json
import subprocess
import sys
import zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BASE = "s3:ocom.oceangenomes/illumina-hic"
OUT = Path(sys.argv[1])


def rclone(*args, text=True):
    return subprocess.run(["rclone", *args], capture_output=True, text=text, check=False)


def is_r1(path):
    name = path.rsplit("/", 1)[-1]
    return any(t in name for t in ("_R1_", "_R1.", ".R1.", "_1.f"))


def first_read(f):
    r = rclone("cat", "--count", "65536", f"{BASE}/{f['Path']}", text=False)
    try:
        line = zlib.decompressobj(31).decompress(r.stdout).decode(errors="replace").split("\n", 1)[0]
        parts = line.lstrip("@").split()[0].split(":")
        fc = ":".join(parts[:4]) if len(parts) >= 7 else ""
    except Exception:  # noqa: BLE001 - an empty or truncated file: no flowcell
        fc = ""
    instrument, number, flowcell, lane = (fc.split(":") + ["", "", "", ""])[:4]
    return f["Path"], f["Path"].split("/")[0], f["Size"], instrument, number, flowcell, lane


files = json.loads(rclone("lsjson", "-R", "--files-only", "--include", "*.fastq.gz", "--include", "*.fq.gz",
                          BASE).stdout)
with ThreadPoolExecutor(16) as ex, open(OUT / "s3_hic_fastq_flowcells.tsv", "w") as out:
    print("path", "run_folder", "size", "instrument", "run_number", "flowcell", "lane", sep="\t", file=out)
    for row in ex.map(first_read, [f for f in files if is_r1(f["Path"])]):
        print(*row, sep="\t", file=out)

with open(OUT / "s3_hic_run_json.tsv", "w") as out:
    print("run_folder", "file", "experiment_name", "run_name", "instrument", "run_number", "flowcell",
          sep="\t", file=out)
    for p in rclone("lsf", "-R", "--files-only", "--max-depth", "2", "--include", "/*/*.json", BASE).stdout.split():
        try:
            d = json.loads(rclone("cat", f"{BASE}/{p}").stdout)
        except ValueError:
            continue
        if "FlowcellBarcode" in d:
            print(p.split("/")[0], p, d.get("ExperimentName"), d.get("Name"), d.get("InstrumentName"),
                  d.get("Number"), d.get("FlowcellBarcode"), sep="\t", file=out)
