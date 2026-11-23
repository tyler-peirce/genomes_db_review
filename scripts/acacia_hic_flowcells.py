#!/usr/bin/env python3
"""Which flowcells each reference assembly's Hi-C reads came from, from its Hi-C BAM on Acacia.
Read-only: rclone lsf / cat --count against pawsey0964:oceanomics-refassemblies (migration 094).

Method. An Illumina read name starts instrument:run_number:flowcell:lane. The pipeline maps the
fastp-filtered Hi-C reads with bwa mem and keeps the names through pairtools (the BAM header's @PG
lines), so the flowcells among an assembly's BAM records are the sequencing runs that went in. The
BAM is coordinate-sorted, so its first ~50,000 records (4 MB) sample every input run; a run giving
1 % of the reads shows as ~500 records. Each flowcell is one run (scripts/s3_hic_run_flowcells.py).

Usage: acacia_hic_flowcells.py hic_assemblies.tsv acacia_ls.txt out.tsv
  hic_assemblies.tsv  assembly_id, og_id, seq_date, version (header row)
  acacia_ls.txt       rclone lsf -R --files-only of the bucket (fasta, png and meryldb excluded)
Out: assembly_id, og_id, seq_date, version, bam, records, flowcells (instrument:number:flowcell=count;...)
"""
import collections
import csv
import re
import struct
import subprocess
import sys
import zlib
from concurrent.futures import ThreadPoolExecutor

REF = "pawsey0964:oceanomics-refassemblies"
CHUNK = 4_000_000


def bam_flowcells(data):
    """(records, Counter of instrument:number:flowcell) from the leading bytes of a BAM."""
    out = bytearray()
    i = 0
    while i + 18 <= len(data) and data[i:i + 4] == b"\x1f\x8b\x08\x04":
        bsize = struct.unpack("<H", data[i + 16:i + 18])[0] + 1
        if i + bsize > len(data):
            break
        out += zlib.decompress(data[i + 18:i + bsize - 8], -15)
        i += bsize
    p = 4
    p += 4 + struct.unpack("<i", out[p:p + 4])[0]
    n_ref = struct.unpack("<i", out[p:p + 4])[0]
    p += 4
    for _ in range(n_ref):
        p += 4 + struct.unpack("<i", out[p:p + 4])[0] + 4
    c = collections.Counter()
    n = 0
    while p + 4 <= len(out):
        bs = struct.unpack("<i", out[p:p + 4])[0]
        if p + 4 + bs > len(out):
            break
        l_name = out[p + 12]
        f = bytes(out[p + 36:p + 36 + l_name - 1]).decode(errors="replace").split(":")
        c[":".join(f[:3]) if len(f) >= 7 else "other"] += 1
        n += 1
        p += 4 + bs
    return n, c


def pick(paths):
    """The scaffolding BAM in the assembly's own folder first, then any Hi-C BAM of it."""
    for pat in (r"/bam/[^/]*\.hap1\.mapped\.PT\.bam$", r"\.hap1\.mapped\.PT\.bam$", r"\.dual\.mapped\.PT\.bam$",
                r"hap1\.hic\.mapped", r"\.bam$"):
        hits = sorted(p for p in paths if re.search(pat, p))
        if hits:
            return hits[0]
    return None


asm = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
bams = collections.defaultdict(list)
for p in open(sys.argv[2]):
    p = p.strip()
    m = re.search(r"(OG\d+)_v(\d{6})\.(hic\d+)", p.rsplit("/", 1)[-1])
    if p.endswith(".bam") and m:
        bams[m.groups()].append(p)


def one(a):
    bam = pick(bams.get((a["og_id"], a["seq_date"], a["version"]), []))
    n, c = 0, collections.Counter()
    if bam:
        r = subprocess.run(["rclone", "cat", "--count", str(CHUNK), f"{REF}/{bam}"], capture_output=True)
        try:
            n, c = bam_flowcells(r.stdout)
        except (struct.error, zlib.error, IndexError):
            pass
    return [a["assembly_id"], a["og_id"], a["seq_date"], a["version"], bam or "", n,
            ";".join(f"{k}={v}" for k, v in c.most_common())]


with ThreadPoolExecutor(8) as ex, open(sys.argv[3], "w") as out:
    print("assembly_id", "og_id", "seq_date", "version", "bam", "records", "flowcells", sep="\t", file=out)
    for row in ex.map(one, asm):
        print(*row, sep="\t", file=out)
