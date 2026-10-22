#!/usr/bin/env python3
"""Trace each v4.ref_sra_upload to the sequencing rows its files came from. Read-only.

Inputs in DIR:
  s3_illumina_hic.json  rclone lsjson -R --files-only --include "*.fastq.gz" --include "*.fq.gz"
                        s3:ocom.oceangenomes/illumina-hic          (one folder per Hi-C run)
  s3_dovetail.json      rclone lsjson -R --files-only --include "/*/*/genomic_data/dovetail/*"
                        s3:ocom.oceangenomes/analysed-data/reference-genomes   (ENA staging copies)
  s3_pacbio_bams.json   rclone lsjson -R --files-only --include "*/hifi_reads/*.bam"
                        s3:ocom.oceangenomes/pacbio                (one folder per PacBio run)
  db_sra_uploads.tsv    SELECT u.srr_accession, s.og_id, coalesce(u.data_type, ''), coalesce(u.filenames, '')
                        FROM v4.ref_sra_upload u JOIN v4.ref_submission s USING (submission_id)
  db_seq_all.tsv        SELECT og_id, sequencing_id, library_tube_id, run_id, technology, library_type,
                        seq_date FROM public.v_sequencing_browse
  db_hifi_bc.tsv        SELECT og_id, barcode, run_id, coalesce(sequencing_id, '') AS sequencing_id,
                               og_id || tissue || '_' || ext_type || '_' || lib_code AS tube
                        FROM v4.hifi_read_qc WHERE barcode IS NOT NULL
Output: DIR/sra_upload_runs.tsv (srr_accession, og_id, data_type, runs, sequencing_ids, status, note).

Rules, per data type (one upload is one submission, from one OG):
  hic       run: a run ID leading the file name; else the illumina-hic/{run}/ folder holding that
            file (by name; by the staged copy's size when the name is in several runs; else by
            elimination: the run whose lanes equal the OG's unprefixed uploads of that library and
            that no run-prefixed upload already claims). Rows: the OG's Hi-C rows on the run whose
            library_tube_id is in a file name (followed by _ or .); else the OG's only Hi-C row on
            the run (older sample sheets named libraries differently: OG11G_HICL for OG11G-1_HICL).
  hifi      the movie (m84154_250307_101432_s2) and barcode in each file name. Rows: the OG's PacBio
            row on the pacbio/{run}/ folder holding that movie, when the OG has one there; else by
            (OG, barcode) through v4.hifi_read_qc on a run within 21 days of the movie; else the OG's
            PacBio rows with the nearest seq_date within 21 days.
  ont,      the run ID in the file name (OG637B_D7_LSKL.ONT_240819_AD....). Rows: the OG's rows on
  illumina  that run whose library_tube_id is in a file name; else its only row of that kind there.
"""
import csv
import json
import re
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

D = Path(sys.argv[1])
WINDOW = 21
RUN_ID = r"(?:NOVA|NEXT|ISEQ|PACB|ONT)[A-Za-z-]*_[0-9]{6}_[A-Za-z0-9]+"
RUN_PREFIX = re.compile(rf"^({RUN_ID})_")
RUN_ANYWHERE = re.compile(rf"(?:^|[._])({RUN_ID})(?=[._])")
LANE = re.compile(r"^(.*)_L(\d{3})_R[12]_001\.f(?:ast)?q\.gz$")
MOVIE = re.compile(r"(m\d+[a-z]?_(\d{6})_\d{6}(?:_s\d)?)")
BARCODE = re.compile(r"\.(bc\d+)(?:--bc\d+)?\.")


def rd(name):
    with open(D / name) as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def ymd(s):
    return datetime.strptime(s, "%y%m%d")


def bare(name):
    return RUN_PREFIX.sub("", name)


def tube_in(tube, files):
    # File names call a tube's first Hi-C library HICL1; the workbook calls it HICL (owner,
    # 2026-10-22: "HICL1 are the HICL files"). No workbook tube ends in HICL1.
    return any(re.search(re.escape(tube) + r"[_.]", re.sub(r"_HICL1(?=[_.])", "_HICL", fn)) for fn in files)


seq = defaultdict(list)
for r in rd("db_seq_all.tsv"):
    seq[r["og_id"]].append(r)
by_barcode = defaultdict(list)
for r in rd("db_hifi_bc.tsv"):
    by_barcode[(r["og_id"], r["barcode"])].append(r)

# Hi-C evidence ------------------------------------------------------------------------------
dovetail = defaultdict(set)
for f in json.load(open(D / "s3_dovetail.json")):
    dovetail[bare(f["Name"])].add(f["Size"])
raw_by_size, raw_by_name, raw_lanes = defaultdict(set), defaultdict(set), defaultdict(set)
for f in json.load(open(D / "s3_illumina_hic.json")):
    run = f["Path"].split("/")[0]
    raw_by_size[f["Size"]].add(run)
    raw_by_name[bare(f["Name"])].add((run, f["Size"]))
    m = LANE.match(bare(f["Name"]))
    if m:
        raw_lanes[(run, m.group(1))].add(m.group(2))

uploads = rd("db_sra_uploads.tsv")
for u in uploads:
    u["files"] = [x.strip() for x in u["filenames"].split(",") if x.strip()]

claimed, unprefixed_lanes = defaultdict(set), defaultdict(set)
for u in uploads:
    if u["data_type"] != "hic":
        continue
    for fn in u["files"]:
        m = RUN_PREFIX.match(fn)
        if m:
            claimed[(u["og_id"], bare(fn))].add(m.group(1))
        else:
            lm = LANE.match(fn)
            if lm:
                unprefixed_lanes[(u["og_id"], lm.group(1))].add(lm.group(2))


def hic_file_run(fn):
    m = RUN_PREFIX.match(fn)
    if m:
        return m.group(1), None
    name = bare(fn)
    named = raw_by_name.get(name, set())
    if len({r for r, _ in named}) == 1:
        return next(iter(named))[0], None
    sizes = dovetail.get(name, set())
    if named and sizes:
        hit = {r for r, s in named if s in sizes}
        if len(hit) == 1:
            return hit.pop(), None
        return None, f"{fn}: in {len({r for r, _ in named})} runs, sizes do not decide"
    if sizes:
        hit = set().union(*(raw_by_size.get(s, set()) for s in sizes))
        if len(hit) == 1:
            return hit.pop(), None
        return None, f"{fn}: staged copy matches {len(hit)} raw files by size"
    if named:
        return None, f"{fn}: in {len({r for r, _ in named})} runs, no staged copy to compare"
    return None, f"{fn}: not in illumina-hic and no staged copy"


def hic_by_elimination(og_id, files):
    stems = set()
    for fn in files:
        m = LANE.match(bare(fn))
        if not m:
            return None
        stems.add(m.group(1))
    cands = set.intersection(*({r for r, _ in raw_by_name.get(bare(fn), set())} for fn in files))
    cands = {r for r in cands if all(raw_lanes.get((r, s)) == unprefixed_lanes.get((og_id, s)) for s in stems)}
    cands -= set().union(*(claimed.get((og_id, bare(fn)), set()) for fn in files))
    return cands.pop() if len(cands) == 1 else None


def rows_on(og_id, runs, files, kind):
    on = [r for r in seq[og_id] if r["run_id"] in runs and kind(r)]
    named = [r for r in on if tube_in(r["library_tube_id"], files)]
    if named:
        return named, None
    if len(on) == 1:
        return on, "file names do not carry the library_tube_id; the OG's only row of this kind on the run"
    return [], None


def hic(u):
    runs, why, open_files = set(), [], []
    for fn in u["files"]:
        run, reason = hic_file_run(fn)
        if run:
            runs.add(run)
        else:
            why.append(reason)
            open_files.append(fn)
    how = "file"
    if open_files and len(runs) == 1 and all(
            next(iter(runs)) in {r for r, _ in raw_by_name.get(bare(fn), set())} for fn in open_files):
        why = []
    elif open_files and not runs:
        run = hic_by_elimination(u["og_id"], open_files)
        if run:
            runs, why, how = {run}, [], "elimination"
    if why:
        return runs, [], "untraced", "; ".join(why[:2])
    rows, note = rows_on(u["og_id"], runs, u["files"], lambda r: r["technology"] == "Hi-C")
    if not rows:
        return runs, [], "run_not_in_sequencing" if not any(r["run_id"] in runs for r in seq[u["og_id"]]) \
            and not any(s["run_id"] in runs for rs in seq.values() for s in rs) else "no_row_for_library", ""
    return runs, rows, "traced_only_row_on_run" if note else f"traced_{how}", note or ""


# HiFi evidence ------------------------------------------------------------------------------
movie_runs = defaultdict(set)        # (movie, barcode) -> PACB_ run folders
for f in json.load(open(D / "s3_pacbio_bams.json")):
    top = f["Path"].split("/")[0]
    m, b = MOVIE.search(f["Name"]), BARCODE.search(f["Name"])
    if m and top.startswith("PACB_"):
        movie_runs[(m.group(1), b.group(1) if b else None)].add(top)


def is_pacbio(r):
    return r["technology"] in ("PacBio", "PacBio HIFI") and r["library_type"] == "pacbio"


def by_bc(og, bc, cands):
    """Several libraries of the OG fit: keep the one whose read QC carries this barcode, by its
    sequencing link or by the library tube the QC row names. Still several -> none (ambiguous)."""
    if len(cands) <= 1 or not bc:
        return cands
    qc = by_barcode.get((og, bc), [])
    ids = {r["sequencing_id"] for r in qc if r["sequencing_id"]}
    tubes = {r["tube"] for r in qc}
    narrowed = [r for r in cands if r["sequencing_id"] in ids] or \
               [r for r in cands if r["library_tube_id"] in tubes]
    return narrowed if len(narrowed) == 1 else []


def hifi(u):
    og, rows, notes, runs = u["og_id"], {}, set(), set()
    # An upload is one library: its unassigned/unbarcoded files take the upload's one barcode.
    upload_bcs = {b.group(1) for fn in u["files"] for b in [BARCODE.search(fn)] if b}
    upload_bc = next(iter(upload_bcs)) if len(upload_bcs) == 1 else None
    for fn in u["files"]:
        m, b = MOVIE.search(fn), BARCODE.search(fn)
        if not m:
            continue
        movie, mdate, bc = m.group(1), m.group(2), b.group(1) if b else upload_bc
        folders = movie_runs.get((movie, bc), set()) | (movie_runs.get((movie, None), set()) if not bc else set())
        in_folder = [r for r in seq[og] if is_pacbio(r) and r["run_id"] in folders]
        if in_folder:
            on = by_bc(og, bc, in_folder)
            if not on:
                notes.add(f"{movie}: {len(in_folder)} libraries of the OG on {in_folder[0]['run_id']}, barcode does not decide")
                continue
            rows[on[0]["sequencing_id"]] = on[0]
            notes.add("run folder")
            continue
        hits = [r for r in by_barcode.get((og, bc), []) if r["sequencing_id"] and r["run_id"][5:11].isdigit()
                and abs((ymd(mdate) - ymd(r["run_id"][5:11])).days) <= WINDOW]
        if len(hits) == 1:
            r = next(x for x in seq[og] if x["sequencing_id"] == hits[0]["sequencing_id"])
            rows[r["sequencing_id"]] = r
            notes.add("barcode")
            continue
        near = [(abs((ymd(mdate) - ymd(r["seq_date"])).days), r) for r in seq[og]
                if is_pacbio(r) and r["seq_date"] and abs((ymd(mdate) - ymd(r["seq_date"])).days) <= WINDOW]
        if near:
            best = min(g for g, _ in near)
            tied = [r for g, r in near if g == best]
            picked = by_bc(og, bc, tied)
            if not picked:
                notes.add(f"{movie}: {len(tied)} libraries of the OG on the nearest run, barcode does not decide")
                continue
            rows[picked[0]["sequencing_id"]] = picked[0]
            notes.add("nearest date")
        else:
            notes.add(f"{movie}: no PacBio row within {WINDOW} days" + (f" (raw folder {sorted(folders)})" if folders else ""))
    runs = {r["run_id"] for r in rows.values()}
    unresolved = [n for n in notes if ":" in n]
    if not rows:
        return runs, [], "untraced", "; ".join(sorted(notes)) or "no movie in the file names"
    status = "traced" if not unresolved and notes <= {"run folder"} else (
        "traced_partly" if unresolved else "traced_" + "_".join(sorted(n.replace(" ", "_") for n in notes if n != "run folder")))
    return runs, list(rows.values()), status, "; ".join(sorted(notes))


def by_run_in_name(u, kind):
    runs = {m.group(1) for fn in u["files"] for m in [RUN_ANYWHERE.search(fn)] if m}
    if not runs:
        return set(), [], "untraced", "no run ID in the file names"
    rows, note = rows_on(u["og_id"], runs, u["files"], kind)
    if not rows:
        # File names can carry a longer run token than the workbook (ONT_240306_ADAK for
        # ONT_240306_AD): fall back to the OG's only row of this kind with the same run date.
        dates = {r.split("_")[1] for r in runs}
        same = [r for r in seq[u["og_id"]] if kind(r) and r["run_id"].split("_")[1:2] and r["run_id"].split("_")[1] in dates]
        if len(same) == 1:
            return {same[0]["run_id"]}, same, "traced_same_run_date", \
                f"file run token {','.join(sorted(runs))} is not a sequencing run_id; the OG's only row with that run date"
        known = any(s["run_id"] in runs for rs in seq.values() for s in rs)
        return runs, [], "no_row_for_library" if known else "run_not_in_sequencing", ""
    return runs, rows, "traced_only_row_on_run" if note else "traced", note or ""


out, tally = [], defaultdict(int)
for u in uploads:
    dt = u["data_type"]
    if not u["files"]:
        runs, rows, status, note = set(), [], "no_filenames", ""
    elif dt == "hic":
        runs, rows, status, note = hic(u)
    elif dt == "hifi":
        runs, rows, status, note = hifi(u)
    elif dt == "ont":
        runs, rows, status, note = by_run_in_name(u, lambda r: r["technology"] == "ONT")
    elif dt == "illumina":
        runs, rows, status, note = by_run_in_name(u, lambda r: r["technology"] == "Illumina")
    else:
        runs, rows, status, note = set(), [], "no_data_type", ""
    tally[(dt or "-", status)] += 1
    out.append([u["srr_accession"], u["og_id"], dt, ",".join(sorted(runs)),
                ",".join(sorted(r["sequencing_id"] for r in rows)), status, note])

with open(D / "sra_upload_runs.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t")
    w.writerow(["srr_accession", "og_id", "data_type", "runs", "sequencing_ids", "status", "note"])
    w.writerows(out)
for k in sorted(tally):
    print(*k, tally[k], sep="\t")
