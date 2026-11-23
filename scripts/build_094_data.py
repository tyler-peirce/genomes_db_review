#!/usr/bin/env python3
"""Write migration 094's data: sql/data/094_*.tsv and the VALUES blocks the migration inlines
(sql/data/094_values.sql).

Usage: python3 scripts/build_094_data.py DIR
DIR (sql/data/094_evidence) holds the outputs of scripts/s3_hic_run_flowcells.py and
scripts/acacia_hic_flowcells.py, and these read-only exports of live (psql -A -F $'\\t' -P footer=off):
  db_hic_sequencing.tsv  SELECT og_id, run_id, sequencing_id, coalesce(status, '') AS status, seq_date
                         FROM v_sequencing_browse WHERE technology = 'Hi-C' AND library_type = 'hic'
  db_omnic.tsv           SELECT a.og_id, a.seq_date, a.version, min(o.total) AS tmin, max(o.total) AS tmax
                         FROM ref_assembly a JOIN ref_assembly_part p USING (assembly_id)
                         JOIN ref_omnic o USING (part_id) WHERE a.version ~ '^hic' GROUP BY 1, 2, 3
  db_hic_qc.tsv          SELECT og_id, run_id, sum(totalclusterspf) AS clusters FROM hic_read_qc GROUP BY 1, 2
  db_runs.tsv            SELECT run_id FROM sequencing_run

Run flowcells (sequencing_run.flowcell): a run folder's flowcell from its FASTQ read names, which must
be one flowcell, must equal the saved BaseSpace FlowcellBarcode where there is one, and must not be
another run's.

Assembly Hi-C runs (ref_assembly_run), first rule that applies:
  bam     the flowcells in the assembly's Hi-C BAM -> their runs -> the OG's non-failed Hi-C
          sequencing rows on those runs (every library of the OG on the run: the pipeline stages the
          OG's whole run folder). Refused, and listed, when a run has no such row.
  iseq    within bam: an iSeq flowcell (FS instrument) is on no S3 run folder; it is the OG's one
          non-failed iSeq Hi-C row dated on or before the assembly (OG88 v230728.hic1), and that
          run's flowcell is recorded as inferred.
  omnic   no BAM: ref_omnic's total read pairs over the OG's runs' BaseSpace clusters is in
          [0.95, 1.0005] for exactly one set of runs; those runs' flowcells are its evidence. Checked against the BAM answer on every
          assembly with both: 85 of 85 unique sets agree, none disagree.
Anything else is listed in 094_hic_unlinked.tsv with its reason.
"""
import csv
import itertools
import sys
from collections import Counter, defaultdict
from pathlib import Path

D = Path(sys.argv[1])
OUT = Path(__file__).resolve().parents[1] / "sql" / "data"
BAND = (0.95, 1.0005)


def rd(name):
    with open(D / name) as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def q(s):
    return "NULL" if s is None else "'" + str(s).replace("'", "''") + "'"


# --- run flowcells ------------------------------------------------------------------------------
fastq = defaultdict(Counter)
for r in rd("s3_hic_fastq_flowcells.tsv"):
    if r["flowcell"]:
        fastq[r["run_folder"]][(r["instrument"], r["run_number"], r["flowcell"])] += 1
saved = defaultdict(set)
for r in rd("s3_hic_run_json.tsv"):
    if r["experiment_name"] == r["run_folder"]:
        saved[r["run_folder"]].add((r["instrument"], r["run_number"], r["flowcell"]))
known_runs = {r["run_id"] for r in rd("db_runs.tsv")}
run_fc = {}
for run, c in sorted(fastq.items()):
    if len(c) != 1:
        sys.exit(f"{run}: {len(c)} flowcells in its FASTQ read names: {dict(c)}")
    (fc,) = c
    if saved.get(run) and saved[run] != {fc}:
        sys.exit(f"{run}: read names say {fc}, BaseSpace says {saved[run]}")
    if run not in known_runs:
        sys.exit(f"{run}: not in sequencing_run")
    run_fc[run] = (fc, "fastq+basespace" if saved.get(run) else "fastq", sum(c.values()))
by_fc = defaultdict(list)
for run, (fc, _, _) in run_fc.items():
    by_fc[":".join(fc)].append(run)
dup = {k: v for k, v in by_fc.items() if len(v) > 1}
if dup:
    sys.exit(f"flowcells on several runs: {dup}")
fc_run = {k: v[0] for k, v in by_fc.items()}

# --- assembly Hi-C runs -------------------------------------------------------------------------
hic_rows = defaultdict(list)                       # (og, run) -> [sequencing_id]
og_iseq = defaultdict(list)                        # og -> [(seq_date, run, sequencing_id)]
for r in rd("db_hic_sequencing.tsv"):
    if r["status"] == "Failed":
        continue
    hic_rows[(r["og_id"], r["run_id"])].append(r["sequencing_id"])
    if r["run_id"].upper().startswith("ISEQ"):
        og_iseq[r["og_id"]].append((r["seq_date"], r["run_id"], r["sequencing_id"]))
omnic = {(r["og_id"], r["seq_date"], r["version"]): (int(r["tmin"]), int(r["tmax"])) for r in rd("db_omnic.tsv")}
clusters = defaultdict(dict)
for r in rd("db_hic_qc.tsv"):
    if r["clusters"]:
        clusters[r["og_id"]][r["run_id"]] = int(r["clusters"])

links, unlinked, fc_evidence, counts = [], [], [], Counter()
for a in rd("acacia_hic_bam_flowcells.tsv"):
    key = (a["og_id"], a["seq_date"], a["version"])
    og = a["og_id"]
    reads = Counter()
    for item in filter(None, a["flowcells"].split(";")):
        fc, n = item.rsplit("=", 1)
        reads[fc] += int(n)
    total = sum(reads.values())
    if reads:
        runs, problems, iseq = {}, [], None
        for fc, n in reads.most_common():
            share = f"{100 * n / total:.1f}%"
            fc_evidence.append(key + (fc, n, "bam"))
            run = fc_run.get(fc)
            if run is None and fc.startswith("FS"):
                cands = [x for x in og_iseq.get(og, []) if x[0] <= a["seq_date"]]
                if len(cands) == 1:
                    iseq = cands[0][1]
                    runs[iseq] = "iseq"
                    if iseq in run_fc or fc in fc_run:
                        sys.exit(f"{key}: iSeq flowcell {fc} or run {iseq} already has a flowcell")
                    i, n_, f_ = fc.split(":")
                    run_fc[iseq] = ((i, n_, f_), "inferred: " + "%s %s.%s's only iSeq Hi-C row" % key, 0)
                    fc_run[fc] = iseq
                    continue
                problems.append(f"iSeq flowcell {fc} ({share} of reads) is on no S3 run and the OG has "
                                f"{len(cands)} iSeq Hi-C rows to choose from")
                continue
            if run is None:
                problems.append(f"flowcell {fc} ({share} of reads) is on no S3 run folder")
            elif not hic_rows.get((og, run)):
                problems.append(f"{share} of its Hi-C reads are from {run}, which has no {og} Hi-C sequencing row")
            else:
                runs[run] = "bam"
        if problems:
            unlinked.append(key + ("; ".join(problems),))
            counts["unlinked_bam"] += 1
            continue
        for run, src in sorted(runs.items()):
            for sid in hic_rows[(og, run)]:
                links.append(key + (sid, src))
        counts["bam"] += 1
        continue
    t = omnic.get(key)
    if t and t[0] == t[1]:
        runs = clusters.get(og, {})
        band = [c for n in range(1, len(runs) + 1) for c in itertools.combinations(sorted(runs), n)
                if sum(runs[x] for x in c) and BAND[0] <= t[0] / sum(runs[x] for x in c) <= BAND[1]]
        if len(band) == 1 and all(hic_rows.get((og, run)) for run in band[0]):
            for run in band[0]:
                for sid in hic_rows[(og, run)]:
                    links.append(key + (sid, "omnic"))
                fc_evidence.append(key + (":".join(run_fc[run][0]), "", "omnic"))
            counts["omnic"] += 1
            continue
        why = (f"no Hi-C BAM on Acacia; OMNIC's {t[0]:,} read pairs fit {len(band)} sets of the OG's runs"
               + (": " + " | ".join("+".join(c) for c in band) if band else ""))
    else:
        why = "no Hi-C BAM on Acacia and no single OMNIC total"
    unlinked.append(key + (why,))
    counts["unlinked_no_evidence"] += 1

# --- write ----------------------------------------------------------------------------------------
with open(OUT / "094_run_flowcell.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["run_id", "instrument", "run_number", "flowcell", "source", "r1_fastqs"])
    for run, (fc, src, n) in sorted(run_fc.items()):
        w.writerow([run, *fc, src, n])
with open(OUT / "094_hic_assembly_run.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["og_id", "seq_date", "version", "sequencing_id", "source"])
    w.writerows(sorted(links))
with open(OUT / "094_hic_assembly_flowcell.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["og_id", "seq_date", "version", "flowcell", "bam_records", "source"])
    w.writerows(sorted(fc_evidence))
with open(OUT / "094_hic_unlinked.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["og_id", "seq_date", "version", "reason"])
    w.writerows(sorted(unlinked))

with open(OUT / "094_values.sql", "w") as fh:
    fh.write("-- generated by scripts/build_094_data.py; pasted into sql/094_ref_assembly_hic_runs.sql\n")
    fh.write("-- d_flowcell (run_id, flowcell)\n")
    fh.write(",\n".join(f"  ({q(run)}, {q(fc[2])})" for run, (fc, _, _) in sorted(run_fc.items())) + "\n")
    fh.write("-- d_link (og_id, seq_date, version, sequencing_id, source)\n")
    fh.write(",\n".join("  (" + ", ".join(q(x) for x in l) + ")" for l in sorted(links)) + "\n")
    fh.write("-- d_evidence (og_id, seq_date, version, flowcell, bam_records, source)\n")
    fh.write(",\n".join(f"  ({q(k0)}, {q(k1)}, {q(k2)}, {q(fc.split(':')[2])}, {n if n != '' else 'NULL'}, {q(src)})"
                        for k0, k1, k2, fc, n, src in sorted(fc_evidence)) + "\n")
    fh.write("-- d_unlinked (og_id, seq_date, version, reason)\n")
    fh.write(",\n".join("  (" + ", ".join(q(x) for x in u) + ")" for u in sorted(unlinked)) + "\n")

print(f"runs with a flowcell: {len(run_fc)} ({sum(1 for v in run_fc.values() if v[1] == 'fastq+basespace')} also BaseSpace, "
      f"{sum(1 for v in run_fc.values() if v[1].startswith('inferred'))} inferred)")
print(f"assemblies: {dict(counts)}; links: {len(links)} "
      f"({Counter(l[4] for l in links)}); assemblies linked: {len({l[:3] for l in links})}")
