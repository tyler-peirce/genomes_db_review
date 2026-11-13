#!/usr/bin/env python3
"""Read-only inventory of draft-genome results: what is in the database, on Acacia, on S3.

Two steps, because the listings live on Setonix and the database is reached from here.

  summarise  (on Setonix) reduces the rclone listings to one row per (og_id, seq_date) with a
             count per result family. Listings come from
               rclone lsf -R --files-only pawsey0964:oceanomics-draftgenomes/genomes.v2/
               rclone lsf -R --files-only s3:ocom.oceangenomes/analysed-data/draft-genomes/
  classify   (here) joins that table with live v_draft_genome_status and draft_genomes in a
             read-only session, and says per draft and family whether the gap can be
             backfilled, needs a cheap re-run, needs re-assembly, or is lost.

Usage:
  python3 draft_acacia_inventory.py summarise ACACIA_LISTING S3_LISTING OUT.tsv
  python3 draft_acacia_inventory.py classify PRESENCE.tsv OUT_DIR [--raw-listing RAW] [--db-config CFG]
"""
import argparse
import configparser
import csv
import io
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

# Paths relative to genomes.v2/<OG>/. Each family is the file the draft pipeline's parser
# (bin/draft_genome_stats.py) or a re-run mode (depth-only, genome-size-only) reads.
ACACIA_FAMILIES = {
    "fna": r"^assemblies/genome/[^/]+\.fna$",
    "bam": r"^assemblies/genome/bwa/[^/]+\.sorted\.bam$",
    "busco_summary": r"^assemblies/genome/busco[^/]*/(?:[^/]+/)?[^/]*short_summary[^/]*\.json$",
    "busco_full_table": r"^assemblies/genome/busco[^/]*/(?:[^/]+/)?[^/]*full_table[^/]*\.tsv$",
    "tiara": r"^assemblies/genome/tiara/[^/]*tiara_filter_summary\.txt$",
    "filter_report": r"^assemblies/genome/NCBI/[^/]*filter_report\.txt$",
    "contigs_lt500": r"^assemblies/genome/NCBI/[^/]*contig_count_500bp\.txt$",
    "merqury_qv": r"^kmers/[^/]*\.merqury\.qv$",
    "merqury_completeness": r"^kmers/[^/]*completeness\.stats$",
    "genomescope_summary": r"^kmers/[^/]+/[^/]*genomescope[^/]*summary\.txt$",
    "genomescope_model": r"^kmers/[^/]+/[^/]*model\.txt$",
    "gfastats": r"^assemblies/genome/gfastats/[^/]*assembly_summary",
    "coverage_summary": r"^coverage/[^/]*_coverage_summary\.json$",
    "kmer_depth": r"^coverage/[^/]*_kmer_depth\.json$",
    "seqkit": r"seqkit_stats\.tsv$",
    "fastp": r"fastp\.json$",
    "scdepth": r"^assemblies/genome/depthsizer/[^/]*\.scdepth$",
}
S3_FAMILIES = {
    "s3_fna": r"\.fna$",
    "s3_reads": r"\.R1\.fastq\.gz$",
    "s3_fastp": r"fastp\.json$",
}
# Files that carry no seq_date (the BAM, DepthSizer's scdepth): counted against the OG, and
# attributed to a draft only when the OG has one draft.
UNDATED = {"bam", "scdepth"}
FAMILIES = list(ACACIA_FAMILIES) + list(S3_FAMILIES)

# The draft key in a filename: <OG>.ilmn.<seq_date>, or <OG>.ilmn.NOVA_<seq_date>_<initials>.
DATE_RE = re.compile(r"\.ilmn\.(?:[A-Z]+_)?(\d{6})(?=[._-]|$)")
NULL_SEQKIT = re.compile(r"(^|/)null\.seqkit_stats\.tsv$")


def draft_date(rel):
    """seq_date from the filename, else from the nearest directory that names one."""
    for part in reversed(rel.split("/")):
        m = DATE_RE.search(part)
        if m:
            return m.group(1)
    return None


def scan(listing, families, counts, undated):
    compiled = {f: re.compile(p) for f, p in families.items()}
    with open(listing) as fh:
        for line in fh:
            path = line.rstrip("\n")
            og, _, rel = path.partition("/")
            if not rel or "/logs/" in rel or NULL_SEQKIT.search(rel):
                continue
            for fam, rx in compiled.items():
                if rx.search(rel):
                    if fam in UNDATED:
                        undated[(og, fam)] += 1
                    else:
                        counts[(og, draft_date(rel) or "", fam)] += 1


def summarise(args):
    counts, undated = Counter(), Counter()
    scan(args.acacia, ACACIA_FAMILIES, counts, undated)
    scan(args.s3, S3_FAMILIES, counts, undated)
    keys = sorted({(og, sd) for og, sd, _ in counts} | {(og, "") for og, _ in undated})
    with open(args.out, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["og_id", "seq_date"] + FAMILIES)
        for og, sd in keys:
            row = [og, sd]
            for fam in FAMILIES:
                row.append(undated[(og, fam)] if fam in UNDATED and not sd
                           else counts[(og, sd, fam)])
            w.writerow(row)
    print(f"{len(keys)} rows -> {args.out}")


DB_QUERY = """
SELECT s.og_id, s.seq_date, s.reads_only,
       s.has_fastp, s.has_genomescope, s.has_tiara, s.has_contamination,
       s.has_busco, s.has_merqury, s.has_gfastats,
       d.genome_size_reliable IS NOT NULL AS has_verdict,
       d.busco_read_depth IS NOT NULL AS has_depth,
       dz.draft_id IS NOT NULL AS has_scdepth,
       (SELECT string_agg(sq.run_id || '/' || sq.library_tube_id || '|' ||
                          sq.run_id || '/' || coalesce(sm.field_id, '') || '_D_IL|' ||
                          sq.run_id || '/' || coalesce(sm.field_id, ''), ';')
          FROM draft_genome_run r JOIN sequencing sq USING (sequencing_id)
         WHERE r.draft_id = g.draft_id) AS raw_libraries
  FROM v_draft_genome_status s
  JOIN sample sm ON sm.og_id = s.og_id
  JOIN draft_genome g ON (g.og_id, g.seq_date) = (s.og_id, s.seq_date)
  JOIN draft_genomes d ON (d.og_id, d.seq_date) = (s.og_id, s.seq_date)
  LEFT JOIN draft_depthsizer dz ON dz.draft_id = g.draft_id
 ORDER BY s.og_num, s.seq_date
"""


def query_live(cfg_path):
    cfg = configparser.ConfigParser()
    cfg.read(cfg_path)
    p = cfg["postgres"]
    env = dict(os.environ, PGHOST=p["host"], PGPORT=p["port"], PGUSER=p["user"],
               PGPASSWORD=p["password"], PGDATABASE=p["dbname"],
               PGOPTIONS="-c default_transaction_read_only=on")
    out = subprocess.run(["psql", "-X", "--csv", "-v", "ON_ERROR_STOP=1", "-c", DB_QUERY],
                         env=env, check=True, capture_output=True, text=True).stdout
    return list(csv.DictReader(io.StringIO(out)))


# A database family, and the Acacia files its backfill needs (all of them).
BACKFILL = {
    "genomescope": ("has_genomescope", ["genomescope_summary"]),
    "tiara": ("has_tiara", ["tiara"]),
    "contamination": ("has_contamination", ["filter_report", "contigs_lt500"]),
    "busco": ("has_busco", ["busco_summary"]),
    "merqury": ("has_merqury", ["merqury_qv", "merqury_completeness"]),
    "gfastats": ("has_gfastats", ["gfastats"]),
    "depth": ("has_depth", ["kmer_depth"]),
    "verdict": ("has_verdict", ["coverage_summary"]),
}
# What a cheap re-run of a family needs on Acacia/S3 (an existing pipeline entry or a small new one).
RERUN_INPUTS = {
    "gfastats": ["fna|s3_fna"],
    "depth": ["fna|s3_fna", "bam", "busco_full_table", "genomescope_model", "fastp|s3_fastp"],
    "verdict": ["genomescope_model", "kmer_depth"],
    "busco": ["fna|s3_fna"], "merqury": ["fna|s3_fna", "s3_reads|raw_reads"], "tiara": ["fna|s3_fna"],
    "contamination": ["fna|s3_fna"],
    "genomescope": ["s3_reads|raw_reads"],
}


def raw_prefixes(listing):
    """<run_id>/<library_tube_id>_ prefixes present in a listing of s3:ocom.oceangenomes/illumina-raw/,
    where each library's reads sit at <run_id>/<library_tube_id>_L<lane>/<library_tube_id>_S*_R1_001.fastq.gz."""
    found = set()
    if listing:
        with open(listing) as fh:
            for line in fh:
                run, _, rel = line.rstrip("\n").partition("/")
                if rel.endswith("_R1_001.fastq.gz"):
                    found.add(f"{run}/{rel.rsplit('/', 1)[-1].split('_S')[0]}")
    return found


def classify(args):
    raw = raw_prefixes(args.raw_listing)
    pres = {}
    with open(args.presence) as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            pres[(r["og_id"], r["seq_date"])] = {f: int(r[f]) for f in FAMILIES}
    live = query_live(args.db_config)
    drafts_per_og = Counter(r["og_id"] for r in live)
    zero = dict.fromkeys(FAMILIES, 0)

    def files(og, sd):
        have = dict(pres.get((og, sd), zero))
        if drafts_per_og[og] == 1:
            undated = pres.get((og, ""), zero)
            for fam in UNDATED:
                have[fam] = undated[fam]
        return have

    def present(have, need):
        return all(any(have[alt] for alt in n.split("|")) for n in need)

    rows, tally = [], defaultdict(Counter)
    for r in live:
        og, sd = r["og_id"], r["seq_date"]
        have = files(og, sd)
        libraries = [lib for lib in (r["raw_libraries"] or "").split(";") if lib]
        # Older runs (e.g. NOVA_230607_LP) name the reads by field_id rather than library tube.
        have["raw_reads"] = int(bool(libraries) and
                                all(any(alt in raw for alt in lib.split("|")) for lib in libraries))
        t = lambda c: r[c] == "t"
        for fam, (col, need) in BACKFILL.items():
            if t(col):
                continue
            if fam == "depth" and t("has_scdepth"):
                state = "superseded_scdepth" if not present(have, need) else "backfill"
            elif present(have, need):
                state = "backfill"
            elif not have["fna"] and not have["s3_fna"]:
                state = "reassemble" if have["s3_reads"] or have["raw_reads"] else "lost"
            elif present(have, [n for n in RERUN_INPUTS[fam]]):
                state = "rerun"
            else:
                state = "rerun_missing_input"
            missing = [n for n in RERUN_INPUTS[fam] if not present(have, [n])]
            rows.append({"og_id": og, "seq_date": sd, "family": fam, "state": state,
                         "missing_inputs": ",".join(missing) if state.startswith("rerun") or
                         state in ("reassemble", "lost") else ""})
            tally[fam][state] += 1

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "draft_gaps.tsv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["og_id", "seq_date", "family", "state", "missing_inputs"],
                           delimiter="\t")
        w.writeheader()
        w.writerows(rows)
    states = ["backfill", "rerun", "rerun_missing_input", "reassemble", "lost", "superseded_scdepth"]
    print("family\t" + "\t".join(states))
    for fam in BACKFILL:
        print(fam + "\t" + "\t".join(str(tally[fam][s]) for s in states))
    unmatched = sorted(k for k in pres if k[1] and k not in {(r["og_id"], r["seq_date"]) for r in live})
    with open(out / "acacia_not_in_db.tsv", "w") as fh:
        fh.write("og_id\tseq_date\n" + "".join(f"{og}\t{sd}\n" for og, sd in unmatched))
    print(f"{len(live)} drafts on live; {len(rows)} gaps; "
          f"{len(unmatched)} (og, seq_date) keys on Acacia/S3 with no draft row")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("summarise")
    s.add_argument("acacia")
    s.add_argument("s3")
    s.add_argument("out")
    c = sub.add_parser("classify")
    c.add_argument("presence")
    c.add_argument("out_dir")
    c.add_argument("--raw-listing", help="rclone lsf -R --files-only of illumina-raw/<run>/ for the "
                   "runs to check, each line prefixed <run_id>/")
    c.add_argument("--db-config", default=str(Path.home() / "postgresql_details/oceanomics.cfg"))
    args = ap.parse_args()
    {"summarise": summarise, "classify": classify}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
