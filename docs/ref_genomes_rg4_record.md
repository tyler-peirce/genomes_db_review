# Phase RG, RG.4 record: writers and readers on `phase-rg-v4`

Runbook: [`ref_genomes_runbook_rg0_rg5.md`](ref_genomes_runbook_rg0_rg5.md) RG.4. Done 2026-10-19. Nothing is
pushed or deployed, and nothing here touched a database: the database run is RG.5.

## Branches

| Repo | Branch (from `master`) | Commit | Change |
|---|---|---|---|
| `OceanOmics-OceanGenomes-ref-genomes` | `phase-rg-v4` | `47fd998` | `scripts/lib/refdb.py`; `scripts/03_compile_results/{01a,0a,0b,02b,02d,03a,04a,04b,05a}_*.py`; `scripts/06_post_assembly/query_hichifi_results.py`; `tests/`; `docs/manual_hichifi_run.md` |
| `OceanOmics-OceanGenomes-post-curation` | `phase-rg-v4` | `cd2001f` | `scripts/lib/refdb.py`; `scripts/compile_results/{02b,02d,03a,04a,05a,06b}_*.py`; `tests/` |

Both commits use the repos' established identity (Tyler Peirce), passed per commit. No git config
was changed.

## What changed

**`scripts/lib/refdb.py`** is byte-identical in both repos; `tests/test_refdb_copies.py` fails if
the copies drift. It contains:
- **Input:** `load_db_config`, `parse_int`/`parse_float`, `clean` (numpy scalars, NaN, pandas NA)
  and `load_samplesheet`.
- **Key check:** `check_part_key` names every bad part of a key before any SQL runs.
- **Writes:**
  - `ensure_assembly`, `ensure_part` and `upsert_metrics` (part-keyed tool tables);
  - `upsert_read_set` (GenomeScope, HiFiAdapterFilt);
  - `upsert_hifi_read_qc`, which links the one matching sequencing row, as the sync does.
- **One transaction per file:** `write_tool_rows`, `write_read_set_rows` and
  `write_hifi_read_qc_rows`. `main_guard` prints the error and exits 1.

Table names are unqualified. Until RG.6 the branch must run with
`PGOPTIONS='-c search_path=v4,public'`; with the default `search_path` it fails, because the tables
do not exist in `public`, rather than writing anywhere.

**`upsert_metrics` semantics**, matching the old wide-table upsert:
- Values given: create the assembly and part if needed, and upsert only the columns the record
  carries.
- **Every value None:** delete that tool's row for the part, then any part or assembly left with
  nothing. The old upsert blanked the block; here no empty row remains.

**Push scripts.** Each keeps its own file parsing unchanged, and only the database section was
replaced:
- The five tool scripts of each repo were rewritten mechanically: the loop and its `params`
  dict are kept as written, split into key and values, and handed to `refdb.write_tool_rows`.
- `01a`, `0a`, `0b` and `04b` were edited by hand.

| Script | Writes | Notes |
|---|---|---|
| ref `02b`, `02d`, `03a`, `04a`, `05a` | `ref_merqury_qv`, `ref_merqury_completeness`, `ref_busco`, `ref_gfastats`, `ref_omnic` | The samplesheet version and the "not in current samplesheet" skip are unchanged |
| ref `04b` | `ref_gfastats` | Skips the excluded OG90_bc2008 variant with a message (RG.0 §3) and no longer writes it. OG906's dateless names still map to 250212, as the triage did |
| ref `01a` | `ref_genomescope` | `seq_date` from the samplesheet `date` (vYYMMDD), else NULL. The fish 1 Gb default is unchanged |
| ref `0a` | `ref_hifi_adapter_filter` | New optional samplesheet argument, for `seq_date`. The run-time `CREATE UNIQUE INDEX` is gone |
| ref `0b` | `hifi_read_qc` | SMRT-cell summing unchanged; `sequencing_id` resolved |
| ref `query_hichifi_results.py` | reads `v_ref_assembly_summary` | Same columns and report layout: one row per assembly and haplotype at its latest stage. Exit-code meaning unchanged |
| post-curation `02b`, `02d`, `03a`, `04a`, `05a`, `06b` | `ref_merqury_qv`, `ref_merqury_completeness`, `ref_busco`, `ref_gfastats` (+ `num_gaps`), `ref_seqkit_stats`, `ref_chromosome_stats` | `post_pipeline.sh` already checks exit codes, so failures now reach its `[WARN]` |

**Defects fixed by the change:**
- Every script caught exceptions, printed them and exited 0. Now any error rolls back the whole
  file and exits 1.
- Commits were made per row, so a failure left half a file written. Now there is one
  transaction per file.
- `04a` could send `haplotype` None into a `NOT NULL` key and fail silently. Now it is reported
  by name.
- `0a` ran DDL at run time. Removed.

**Not changed:**
- `stage3_backfill_push.py` (a one-off, RG.0 §2);
- the samplesheet scripts and `stage_previous_hic.py`, which work through the compatibility
  views;
- every Nextflow module and compile shell script.

## Tests

Run with `python -m unittest discover tests` in each repo, using the venv `~/venvs/oceanomics-db`,
which has no pytest.

| Repo | Tests | Result |
|---|---:|---|
| ref-genomes | 31 | OK |
| post-curation | 28 | OK |

**Unit tests** (`test_refdb.py`, shared):
- parsing and NaN handling;
- key validation, naming each problem;
- the SQL emitted for upsert, delete-and-prune, and an unchanged no-op;
- the read-set conflict on `coalesce(seq_date, '')`;
- `"type"` quoted;
- one commit per file, and rollback on error;
- `main_guard` exits 1.

**Script tests** (`test_push_scripts.py`, one per repo): every push script runs as `__main__` on
fixtures, with a fake connection. The ref fixtures are real compiled TSVs from
`OceanOmics-Database/SS/ref_genomes_table`; the post-curation ones are OG762 hic1 241019 stage-3
values. They assert:
- rows go only to the script's own table, plus `ref_assembly`/`ref_assembly_part`, never
  `ref_genomes`;
- the row counts equal the fixture rows for samplesheet OGs, and OG85 is skipped;
- OMNIC stage names map to 0 and 2;
- `dual` parts are written;
- BUSCO's `chr_level` hap2 name is handled;
- GenomeScope and HiFiAdapterFilt are dated from the samplesheet, and undated without one;
- SMRT cells are summed;
- a database error, or a bad name or version, exits 1 with no commit.

## Open for RG.5

RG.5 runs these branches against a restore and compares them with `master`'s writers row by row.
OceanGenom_Web stays unchecked until its queries are available (RG.0 §3).
