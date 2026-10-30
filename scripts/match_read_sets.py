#!/usr/bin/env python3
"""Date the v4 read sets (GenomeScope, HiFiAdapterFilt) from Acacia evidence. Read-only.

Inputs in DIR:
  genomescope.tsv, hifiadapt_stats.tsv, versions.tsv   scripts/acacia_read_set_inventory.py DIR
  db_*.tsv, read-only exports of live (psql -A -F $'\\t' -P footer=off -c ...):
    db_gs.tsv      SELECT read_set_id, og_id, seq_date, homozygosity, heterozygosity, genomesize,
                          repeatsize, uniquesize, modelfit, errorrate FROM v4.ref_genomescope
    db_haf.tsv     SELECT read_set_id, og_id, seq_date, contam_reads FROM v4.ref_hifi_adapter_filter
    db_pacbio.tsv  SELECT b.og_id, s.sequencing_id, s.library_tube_id, s.technology, s.run_id,
                          s.seq_date, s.cell_id
                   FROM public.v_sequencing_browse b JOIN sequencing s USING (sequencing_id)
                   WHERE s.technology IN ('PacBio', 'PacBio HIFI')
                     AND s.status IS DISTINCT FROM 'Failed'   -- since 069
    db_hifi_bc.tsv SELECT q.og_id, q.barcode, q.run_id, q.sequencing_id FROM v4.hifi_read_qc q
                   JOIN sequencing s USING (sequencing_id)
                   WHERE q.barcode IS NOT NULL AND s.status IS DISTINCT FROM 'Failed'
Output: DIR/read_set_matches.tsv, one row per OG read set. The 2026-10-20 run is
sql/data/062_read_set_dates.tsv; its Acacia evidence is in sql/data/062_evidence/.

Rules:
- public.raw_qc holds one row per OG, written by the same pipeline run for both tools, so an OG's
  GenomeScope and HiFiAdapterFilt rows describe one read set and get one date.
- Each backed-up HiFi movie (oceanomics-filtered-reads/{OG}/hifi[/qc_stats]/*.stats) maps to a
  PacBio sequencing row: by (OG, barcode) through v4.hifi_read_qc where its run is within 21 days of
  the movie, else to the OG's PacBio rows with the nearest seq_date (ties all kept).
  unassigned/unbarcoded files follow the barcoded file of the same movie.
- One PacBio run (date) among the OG's movies -> that run. Several -> the read set is every run up
  to the meryl/assembly version current when the GenomeScope summary was written; this needs the
  backed-up summary to equal the DB row (genomesize to the base pair), else it stays ambiguous.
- seq_date is the latest seq_date of the read set's sequencing rows (v4.ref_assembly's convention).
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


def num(s):
    s = (s or "").replace(",", "").replace("%", "").strip()
    try:
        return float(s)
    except ValueError:
        return None


def ts(s):
    return datetime.fromisoformat(s[:19])


def ymd(s):
    return datetime.strptime(s, "%y%m%d")


def days(a, b):
    return abs((ymd(a) - ymd(b)).days)


pacbio = defaultdict(list)
for r in rd("db_pacbio.tsv"):
    if r["seq_date"]:
        pacbio[r["og_id"]].append(r)
seq_date_of = {r["sequencing_id"]: r["seq_date"] for rs in pacbio.values() for r in rs}
by_barcode = defaultdict(list)
for r in rd("db_hifi_bc.tsv"):
    by_barcode[(r["og_id"], r["barcode"])].append(r["sequencing_id"])

movie_time = {}
# movie -> {barcodes}, deduplicating the hifi/ and hifi/qc_stats/ copies
movie_bc = defaultdict(lambda: defaultdict(set))
movie_date = {}
for r in rd("hifiadapt_stats.tsv"):
    if not r["movie"]:
        continue
    bc = re.search(r"\.(bc\d+)(?:--bc\d+)?\.", r["path"])
    movie_bc[r["og_id"]][r["movie"]].add(bc.group(1) if bc else None)
    movie_date[r["movie"]] = r["movie_date"]
    t = ts(r["modtime"])
    movie_time[r["movie"]] = min(t, movie_time.get(r["movie"], t))


def map_movie(og, movie):
    md = movie_date[movie]
    hits = []
    for bc in movie_bc[og][movie]:
        if bc is None:
            continue
        for sid in by_barcode.get((og, bc), []):
            if sid in seq_date_of and days(md, seq_date_of[sid]) <= WINDOW:
                hits.append((days(md, seq_date_of[sid]), sid))
    if hits:
        best = min(g for g, _ in hits)  # a barcode can be reused on a nearby run
        return {sid for g, sid in hits if g == best}, "barcode"
    near = [(days(md, p["seq_date"]), p["sequencing_id"]) for p in pacbio[og]
            if days(md, p["seq_date"]) <= WINDOW]
    if not near:
        return set(), "none"
    best = min(g for g, _ in near)
    return {sid for g, sid in near if g == best}, "date"


versions = defaultdict(dict)
for r in rd("versions.tsv"):
    t = ts(r["modtime"])
    if t.year < 2010:
        continue
    v = versions[r["og_id"]]
    if r["seq_date"] not in v or t < v[r["seq_date"]]:
        v[r["seq_date"]] = t

gs_summaries = defaultdict(list)
for r in rd("genomescope.tsv"):
    gs_summaries[r["og_id"]].append(r)
db_gs = {r["og_id"]: r for r in rd("db_gs.tsv")}
db_haf = {r["og_id"]: r for r in rd("db_haf.tsv")}
REL = 1e-5  # re-fits of the same histogram differ by a few bp


def same_fit(a, b):
    a, b = num(a), num(b)
    return a is not None and b is not None and abs(a - b) <= REL * max(a, b)


rows = []
for og in sorted(set(db_gs) | set(db_haf), key=lambda o: (len(o), o)):
    gs_id = db_gs[og]["read_set_id"] if og in db_gs else ""
    haf_id = db_haf[og]["read_set_id"] if og in db_haf else ""
    g = db_gs.get(og)
    # The summary this DB row came from: exact first, then a re-fit within REL; newest wins.
    cands = sorted(gs_summaries.get(og, []), key=lambda r: r["modtime"], reverse=True)
    a = next((r for r in cands if g and num(r["genomesize"]) == num(g["genomesize"])), None)
    gs_check = "equal" if a else ""
    if not a:
        a = next((r for r in cands if g and same_fit(r["genomesize"], g["genomesize"])), None)
        gs_check = "refit" if a else ""
    if not a:
        a = cands[0] if cands else None
        gs_check = ("no_db_row" if not g else "no_acacia_file" if not a else
                    f"differs (acacia {a['genomesize']} {a['modtime'][:10]}, db {g['genomesize']})")

    runs, how, unmapped = defaultdict(set), set(), []
    run_movies = defaultdict(set)
    for movie in movie_bc[og]:
        sids, h = map_movie(og, movie)
        if not sids:
            unmapped.append(movie)
            continue
        how.add(h)
        for sid in sids:
            runs[seq_date_of[sid]].add(sid)
            run_movies[seq_date_of[sid]].add(movie)

    def emit(status, dates, note):
        sids = sorted({s for d in dates for s in runs[d]})
        rows.append([og, gs_id, haf_id, max(dates) if dates else "", ",".join(sids), status,
                     gs_check, "+".join(sorted(how)), note +
                     (f"; unmapped movies {','.join(unmapped)}" if unmapped else "")])

    if not movie_bc[og]:
        # No backed-up reads: only safe when sequencing holds one PacBio run date for the OG.
        only = {p["seq_date"] for p in pacbio[og]}
        if len(only) == 1:
            d = only.pop()
            for p in pacbio[og]:
                runs[d].add(p["sequencing_id"])
            how.add("sequencing_only")
            emit("dated_from_sequencing", [d], "no HiFiAdapterFilt .stats on Acacia; "
                 "the OG's only PacBio run date")
        else:
            emit("no_acacia_reads", [], "no HiFiAdapterFilt .stats on Acacia; "
                 f"PacBio run dates in sequencing: {','.join(sorted(only)) or 'none'}")
        continue
    if not runs:
        emit("no_sequencing_match", [], "no PacBio sequencing row near the movies")
        continue
    dates = sorted(runs)
    if len(dates) == 1:
        emit("dated", dates, "one PacBio run date")
        continue
    if gs_check not in ("equal", "refit"):
        emit("ambiguous", [], f"{len(dates)} run dates {','.join(dates)}; GenomeScope backup {gs_check}")
        continue
    gs_time = ts(a["modtime"])
    # Movies backed up in the same job as the summary (within a day) are the reads it ran on.
    with_gs = [d for d in dates
               if any(abs((movie_time[m] - gs_time).total_seconds()) <= 86400 for m in run_movies[d])]
    if with_gs:
        emit("dated", with_gs, f"{len(dates)} run dates; movies backed up with the summary "
             f"{a['path'].rsplit('/', 1)[1]} ({a['modtime'][:10]})")
        continue
    before = [(t, v) for v, t in versions[og].items() if t <= gs_time]
    if not before:
        emit("ambiguous", [], f"{len(dates)} run dates {','.join(dates)}; no version dated before the summary")
        continue
    vdate = max(before)[1]
    upto = [d for d in dates if (ymd(d) - ymd(vdate)).days <= WINDOW]
    if not upto:
        emit("ambiguous", [], f"version v{vdate} predates every run")
        continue
    emit("dated", upto, f"{len(dates)} run dates; version v{vdate} current at {a['modtime'][:10]}")

with open(D / "read_set_matches.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t")
    w.writerow(["og_id", "genomescope_read_set_id", "hifi_adapter_read_set_id", "seq_date",
                "sequencing_ids", "status", "genomescope_backup", "run_match", "note"])
    w.writerows(rows)

tally = defaultdict(lambda: [0, 0, 0])
for x in rows:
    t = tally[x[5]]
    t[0] += 1
    t[1] += bool(x[1])
    t[2] += bool(x[2])
print("status\tOGs\tgenomescope_rows\thifiadapt_rows")
for k, (n, gsn, hn) in sorted(tally.items()):
    print(k, n, gsn, hn, sep="\t")
