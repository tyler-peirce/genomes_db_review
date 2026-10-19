# Phase RG runbook, RG.0 to RG.5: reference-genome tables in schema `v4`

Status: **RG.0 done 2026-10-19** ([`ref_genomes_rg0_record.md`](ref_genomes_rg0_record.md)); RG.1 next.
Written 2026-10-19, from read-only measurements on live taken the same day.

Corrections from RG.0, which take precedence over the text below:
- the hifi1 OMNIC rows are 140, on 70 assemblies; they are real, and kept;
- OG90 also has `seq_date = 'bc2008'` (6 rows), which is excluded with OG90_bc2008;
- the `*_size_mb` columns stay stored: the generated-column test failed;
- `k_mer_set` is empty everywhere, so, like `hap2_chr_level_max_len`, it is only a NULL in the
  compatibility view;
- run links: exact matches only, and every match is linked (407 assemblies, 434 links);
- the date in `ncbi_status` becomes `status_date`;
- `oceangenom_web` also reads `ref_genomes_assembly_uploads`. This is the reference-genome counterpart of
[`assembly_relations_runbook_r0_r5.md`](assembly_relations_runbook_r0_r5.md). It stops before
RG.6, the move of `v4` into `public`, which gets its own runbook once the gate at the end is met.

**What is true when RG.5 is done:**
- `public` is unchanged. Production writers and readers carry on as before.
- Schema `v4` holds the new reference-genome design, separate from the `v3` draft and
  mitogenome tables. It is backfilled, kept current by a nightly sync, and proved equal to
  `public` through compatibility views.
- Both pipelines that write these tables (`OceanOmics-OceanGenomes-ref-genomes` and
  `OceanOmics-OceanGenomes-post-curation`) have a `phase-rg-v4` branch that writes `v4`, tested
  on a rehearsal restore.

## 0. Why

The reference-genome pipeline writes to one wide table, `public.ref_genomes`: 58 columns, primary key
`(og_id, seq_date, stage, haplotype, version)`. Each tool (gfastats, BUSCO, Merqury QV, Merqury
completeness, OMNIC, seqkit, chromosome stats) upserts only its own columns at that key. A row
therefore holds whichever tools happened to run at that key, and every other column is NULL.

Live figures (measured read-only on 2026-10-19):
- 2,036 rows: 251 OGs, 473 assemblies.
- **70,741 of 107,908 non-key cells are NULL (66%).**
- 26 different fill patterns. 521 rows are gfastats only, 359 are Merqury only and 181 are OMNIC only.

`raw_qc`, `hifi_reads_qc`, `hic_reads_qc` and the two `ref_genomes_*_uploads` tables have the
same problems:
- no foreign keys to `sample` or `sequencing`;
- `raw_qc` is keyed on `og_id` alone, so a re-sequenced OG overwrites its older GenomeScope result
  (47 OGs have more than one `seq_date`).

Phase R did this for the draft and mitogenome tables in `v3`
([`assembly_relations_runbook_r0_r5.md`](assembly_relations_runbook_r0_r5.md)). Phase RG does the same for the
reference-genome tables, under these constraints:

- **Separate tables for the reference pipeline.** Nothing is merged with `v3.draft_*`.
- **Everything new goes in schema `v4`.** `public` is not changed at all, so production keeps
  working. `v4` does not depend on `v3`; it references only `public.sample` and
  `public.sequencing`.
- **Kept current by a nightly sync from `public`, with an equality check,** as `v3` is.
- **Scope (owner decisions, 2026-10-19):**
  - all six reference tables, including `hifi_reads_qc` and `hic_reads_qc`, which move out of R.7;
  - GenomeScope and HiFiAdapterFilt keyed per read set, `(og_id, seq_date)`;
  - the stage-3 seqkit and chromosome stats kept: their writer is the post-curation pipeline.
- **Swapping into `public` (RG.6) is a later runbook,** written once the owner is happy with `v4`.


## 1. Facts the design rests on (live, 2026-10-19)

| Item | Finding |
|---|---|
| Keys | `version`: hic1/2/3, hifi1, ont1, plus `231027` (OG108) and `hi1` (OG820). `haplotype`: hap1, hap2, dual, p_ctg, a_ctg. `stage`: 0–3. 2 rows have `seq_date = ''` (OG906) |
| Stages, from file names | 0 `.0.hifiasm`; 1 `.1.yahs`/`.1.salsa` (scaffolded); 2 `.2.tiara` (decontaminated); 3 `.3.curated` |
| `dual` rows | Hold only the Merqury result for both haplotypes together, or OMNIC on the combined scaffold set |
| Orphan `og_id` | `ref_genomes`: OG88G (2 rows), OG90_bc2008 (2). `raw_qc`: OG750_PD, OG90_bc2008, OG90ULI |
| `raw_qc` (252 rows) | 106 rows have GenomeScope only, 2 have contamination only. A writer also runs a redundant `CREATE UNIQUE INDEX` at run time |
| `hifi_reads_qc` 277, `hic_reads_qc` 552 | No FKs. 26 Hi-C rows have a blank `lane`. **No writer for `hic_reads_qc` in any cloned repo** |
| Uploads | `ref_genomes_assembly_uploads`: 88 rows, one per OG, with hap1/hap2 columns side by side. `ref_genomes_sra_uploads`: 304 rows; `ncbi_status` mixes statuses and dates. No writer in any repo |
| Columns with no data | `hap2_chr_level_max_len`: 0 values and no writer |
| Run match | 410 of 473 assemblies match a PacBio run on `(og_id, seq_date)`; 25 match more than one |
| Postgres | 14.24, so no `NULLS NOT DISTINCT`. Unique indexes use expressions instead |

**Writers:**
- `OceanOmics-OceanGenomes-ref-genomes/scripts/03_compile_results/`:
  - `01a` and `0a` write `raw_qc`;
  - `0b` writes `hifi_reads_qc`;
  - `02b`, `02d`, `03a`, `04a`, `04b`, `05a` and `stage3_backfill_push.py` write `ref_genomes`.
- `OceanOmics-OceanGenomes-post-curation/scripts/compile_results/` writes stage 3 of
  `ref_genomes`:
  - `02b`, `02d`, `03a`;
  - `04a`: gfastats plus `num_gaps`;
  - `05a`: seqkit stats;
  - `06b`: chromosome stats.
- `OceanOmics-Database/SS/ref_genomes_table/*` looks like older copies of the same scripts.

**Defects shared by the writers:**
- They catch an exception, print it, and exit 0. `post-hichifi-assembly.py` never sees a failure.
- They commit once per row.
- The five name parsers differ from one another.
- `04a` says `haplotype` "may be None", but the column is `NOT NULL`, so that insert would fail
  silently.

**Readers:**
- views: `public.coverage_summary` (`raw_qc.genomesize`, the two yields) and
  `public.goat_species_v1`;
- functions: `build_nfcore_samplesheet_rows`, `build_hicpost_samplesheet_rows`,
  `build_postcuration_samplesheet_rows`, `build_final_data_compile`. They use only `og_id`,
  `version`, `seq_date` and `stage = 3`.
- `v3.v_sequencing_run_fk_readiness`;
- the `oceangenom_web` role, which has `SELECT` on `ref_genomes`;
- ref repo scripts: the three samplesheet scripts, `stage_previous_hic.py` and
  `query_hichifi_results.py`;
- the post-curation samplesheet script.

## 2. Target design (`v4`)

**Identity.** One assembly, its parts, and the runs it was built from:
- `v4.ref_assembly`:
  - columns: `assembly_id` identity PK; `og_id` FK `public.sample`; `seq_date` (checked against
    `^\d{6}$`); `version` (checked against `^(hic|hifi|ont)\d+$`);
  - generated: `strategy` (hic/hifi/ont), `attempt` (int) and `og_num`;
  - `UNIQUE (og_id, seq_date, version)`.
- `v4.ref_stage`: a lookup for stages 0–3, with name and description (seeded explicitly).
- `v4.ref_assembly_part`:
  - columns: `part_id` PK; `assembly_id` FK, `ON DELETE CASCADE`; `stage` FK `ref_stage`;
    `haplotype` CHECK in hap1/hap2/dual/p_ctg/a_ctg;
  - `UNIQUE (assembly_id, stage, haplotype)`;
  - `dual` is commented as "hap1 and hap2 together".
- `v4.ref_assembly_run (assembly_id, sequencing_id)`:
  - FK `public.sequencing`, `ON DELETE CASCADE`, matched as in `052`;
  - HiFi and ONT runs come from `(og_id, seq_date)`; Hi-C runs come from writers later;
  - `v4.v_ref_assembly_run_readiness` lists assemblies with no match.

**One table per tool, keyed on `part_id`.** Each has `CHECK (num_nonnulls(...) > 0)`, so a tool
that did not run has no row rather than a row of NULLs:

| Table | Columns | Rows today |
|---|---|---:|
| `ref_gfastats` | contigs, scaffolds, N50s, largest, total, GC, `num_gaps` | 1,298 |
| `ref_busco` | dataset … `number_of_scaffolds` (BUSCO N50s commented as unreliable, as in `052`) | 785 |
| `ref_merqury_qv` | `unique_k_mers_assembly`, `k_mers_total`, `qv`, `error` | 974 |
| `ref_merqury_completeness` | `k_mer_set`, `solid_k_mers`, `total_k_mers`, `completeness` | 881 |
| `ref_omnic` | `total` … `trans` | 581 |
| `ref_seqkit_stats` | `format`, `type`, `num_seqs` … `max_len` | 300 |
| `ref_chromosome_stats` | `num_chromosomes`, `pct_assigned`, `pct_no_super`, `num_seq_no_super`, `max_len_no_super` | 300 |

The `*_size_mb` columns become `GENERATED` from their bp column if RG.0 shows they always equal
`round(bp/1e6, 2)`. Otherwise they stay stored.

**Read sets.** Data that describes sequencing reads, not an assembly:
- `v4.ref_genomescope`:
  - `og_id` FK `sample`, `seq_date` NULL, then the GenomeScope columns;
  - unique on `(og_id, coalesce(seq_date, ''))`;
  - backfilled rows have `seq_date` NULL, meaning unknown, because public never kept it.
- `v4.ref_hifi_adapter_filter`: `contam_reads`, with the same key.
- `v4.hifi_read_qc`:
  - a surrogate PK, today's natural key kept `UNIQUE`, and `og_id` FK `sample`;
  - `sequencing_id` FK `public.sequencing`, nullable, resolved by (library tube, run);
  - a readiness view lists rows that do not resolve.
- `v4.hic_read_qc`: the same, with `lane`. Blank `lane`/`run_id` become NULL.

**Submissions:**
- `v4.ref_submission`:
  - `submission_id`; `og_id` FK `sample`; `assembly_id` FK, nullable, set where the OG has one
    curated assembly;
  - `biosample`, `bioproject_umbrella`, `bioproject_rawdata`, `embargo_status`.
- `v4.ref_submission_haplotype`: `(submission_id, haplotype)`, plus `bioproject`,
  `assembly_accession` and `gca_accession`. This replaces the side-by-side hap1/hap2 columns.
- `v4.ref_sra_upload`:
  - `srr_accession` PK; `og_id` FK `sample`;
  - `data_type` CHECK in hifi/hic/ont/illumina;
  - `ncbi_status` split into a status and a `release_date`;
  - `filenames`.

**Kept out of `v4`, with explicit lists:**
- `v4.ref_key_map`: public key → v4 key, for remapped rows such as OG906's blank date.
- `v4.ref_excluded_rows`: public key and reason, for orphans and the one empty row.

The sync and the check both use these two tables. Rows are added only through RG.0's record.

**Compatibility views** have the same names and columns as `public`, so
`search_path=v4,public` swaps them in for testing:
- `v4.ref_genomes` (all 58 columns, `hap2_chr_level_max_len` as `NULL::bigint`);
- `v4.raw_qc` (latest read set per OG);
- `v4.hifi_reads_qc` and `v4.hic_reads_qc`;
- `v4.ref_genomes_assembly_uploads` and `v4.ref_genomes_sra_uploads`;
- `v4.coverage_summary` and `v4.goat_species_v1` (today's definitions, re-pointed).

The four `build_*` functions resolve table names through `search_path` when called, so they need
no copy.

**New views for the owner:**
- `v4.v_ref_assembly_status`: one row per assembly, a flag per stage × tool.
- `v4.v_ref_assembly_summary`: the final metrics per assembly. This is what
  `query_hichifi_results.py` assembles by hand today.

## 3. Steps

Rules: the same as R.0 §0.1, the repo's standing rules (`sql/README.md`,
`docs/database_change_checklist.md`):
- every change is a numbered migration applied by `bin/apply_migrations.py`, with a header,
  guards, self-checks and a revert;
- rehearse on a fresh restore of live first;
- after each apply, run `--verify`, `check_drift.py --update` and `export_schema_baseline.sh`;
- avoid 18:00 UTC.

Migration numbers are taken in landing order: 057–059 if nothing else lands first. R.6 and R.7
renumber around them, as the runbook says to.

**RG.0: measure and triage.** Output: `docs/ref_genomes_rg0_record.md`.
1. Re-measure every figure above, read-only on live. These are the numbers the migrations
   assert.
2. Triage each oddity as "map", "exclude" or "lab fixes" (this fills `ref_key_map` and
   `ref_excluded_rows`):
   - OG108 `231027` and OG820 `hi1`;
   - OG906's blank date;
   - the 5 orphan rows and the 1 all-empty row;
   - 70 `hifi1` stage-1 rows that carry OMNIC (Hi-C) values;
   - assemblies with no run match, or more than one.
3. Confirm the stage meanings and `dual` with the owner.
4. Find the `hic_reads_qc` writer (a BaseSpace export? 39 runs, 2023-08 to 2026-07) and the
   upload tables' writer. Confirm that `SS/ref_genomes_table/*` and `stage3_backfill_push.py` are
   retired.
5. List the queries OceanGenom_Web runs against these tables.
6. Run the `*_size_mb` = `round(bp/1e6, 2)` test.
7. Count how many read-QC rows resolve to `sequencing` (R.0 found 262/277 and 526/552).
8. List the distinct `ncbi_status` values, so the split recombines exactly.
9. Edit `assembly_relations_plan.md`: move `hifi_reads_qc` and `hic_reads_qc` from R.7 to RG.

**RG.1: `057_v4_ref_assembly.sql`.**
- Schema `v4`, with grants that mirror public: `readonly` on everything, `oceangenom_web` on
  `ref_genomes`, plus default privileges.
- The identity tables, the 7 tool tables, `ref_key_map` and `ref_excluded_rows`.
- `v4.sync_ref_assembly()`: upserts on natural keys, so ids stay stable, and deletes rows whose
  source has gone.
- `v4.check_ref_assembly()`: `v4.ref_genomes` `EXCEPT ALL` (public, mapped and excluded) both
  ways, 0 rows.
- The views `ref_genomes`, `goat_species_v1`, `v_ref_assembly_status`, `v_ref_assembly_summary`
  and `v_ref_assembly_run_readiness`.
- Revert: drop the schema, which is only valid while `058` and `059` are reverted.

**RG.2: `058_v4_ref_read_qc.sql`.**
- Tables: `ref_genomescope`, `ref_hifi_adapter_filter`, `hifi_read_qc`, `hic_read_qc`.
- Compatibility views: `raw_qc`, `hifi_reads_qc`, `hic_reads_qc`, `coverage_summary`.
- A readiness view for read QC → `sequencing`.
- Its own sync and check functions.

**RG.3: `059_v4_ref_submission.sql`.**
- Tables: `ref_submission`, `ref_submission_haplotype`, `ref_sra_upload`.
- The two upload compatibility views.
- Its own sync and check functions.

**Sync:** `scripts/sync_v4.sql` and `scripts/sync_v4.sh`, copied from `sync_v3.*` and kept
separate from them, so `v4` stands alone.
- Cron at **19:00 UTC**, after `sync_v3` at 18:30.
- Log at `~/log/genomes_db_sync_v4.log`, with a `.FAILING` marker while the last run failed.
- It is the only thing that writes `v4` on live.

**RG.4: writers and readers on branch `phase-rg-v4`, in both pipeline repos.**
- New shared helper `scripts/lib/refdb.py`, vendored in both repos, with a test that the two
  copies are identical. It contains:
  - `load_db_config`, `parse_int` and `parse_float`, replacing about 15 duplicate copies;
  - one `parse_assembly_name()` → `(og_id, seq_date, version, stage, haplotype)`;
  - `ensure_assembly()` and `ensure_part()`, each `INSERT … ON CONFLICT … RETURNING id`;
  - `upsert_metrics(table, part_id, values)`, which writes only the columns given and skips
    all-None, so no empty rows.
- Each push script:
  - keeps its parsing and swaps its `INSERT INTO ref_genomes` for the helper's calls into its own
    tool table;
  - runs one transaction per file;
  - exits non-zero on error;
  - uses unqualified table names, so `search_path` decides.

  Representative files: `03a_push_busco_results_to_sqldb.py` → `ref_busco`;
  `01a_push_genomescope…` → `ref_genomescope`, with `seq_date` from the sample name;
  post-curation `06b_push_percentage_stats…` → `ref_chromosome_stats`.
- `0a` loses its run-time `CREATE INDEX`. `0b` writes `hifi_read_qc` with `sequencing_id`.
- Readers:
  - `query_hichifi_results.py` → `v_ref_assembly_summary`;
  - the samplesheet scripts work unchanged through the compatibility view, and are switched to
    `ref_assembly` where that is simpler;
  - any OceanGenom_Web queries found in RG.0.5 get a fix list.
- Unit tests, one per script:
  - rows land in the right tool table;
  - a second tool for the same part adds a row and leaves the first row unchanged;
  - an all-None record writes nothing;
  - a bad name exits non-zero.

**RG.5: rehearsal.** Record: `docs/ref_genomes_rehearsal_rg5.md`. On a fresh restore of live with
`057`–`059` applied:
1. The checks pass; the sync is a no-op straight after; the revert leaves no `v4` objects; the
   migrations re-apply.
2. Simulate pipeline changes in `public` (a new assembly, an updated BUSCO, a deleted row, a new
   SRA upload), sync, and check the equality still holds.
3. Run the old writers into `public` and the new writers with `search_path=v4,public`, on the same
   outputs of one recent hic run and one post-curation run. Compare `v4.ref_genomes` with
   `public.ref_genomes` row by row.
4. Failure cases:
   - an orphan `og_id`: the FK rejects it and the script exits non-zero;
   - an all-None record: no row written.
5. On live, read-only, with `search_path=v4,public`, run the samplesheet functions and scripts,
   `coverage_summary`, `goat_species_v1` and `query_hichifi_results.py`. Output must be
   identical to the default `search_path`.

**Gate for RG.6 (separate runbook, written later):**
- the sync clean every night for a period the owner chooses;
- RG.5 recorded and passed;
- every reader accounted for;
- `check_drift.py` and `--verify` clean.

RG.6 is when it moves into `public`: the old tables go to `pre_v4_archive`, the `v4` tables move
into `public`, and the writers switch on that day.

## 4. Files

| Repo | Files |
|---|---|
| `genomes_db_review` | `docs/ref_genomes_runbook_rg0_rg5.md`, `docs/ref_genomes_rg0_record.md`, `docs/ref_genomes_rehearsal_rg5.md`; `sql/057–059_v4_*.sql` plus reverts; `scripts/sync_v4.{sql,sh}`; edit to `docs/assembly_relations_plan.md` (R.7 scope) |
| `OceanOmics-OceanGenomes-ref-genomes` | branch `phase-rg-v4`: `scripts/lib/refdb.py`; `scripts/03_compile_results/*push*.py`; `scripts/06_post_assembly/query_hichifi_results.py`; tests |
| `OceanOmics-OceanGenomes-post-curation` | branch `phase-rg-v4`: `scripts/lib/refdb.py`; `scripts/compile_results/*push*.py`; tests |

Reuse:
- `sql/052_v3_draft_genome.sql`: header, guards, the `sync_*`/`check_*` function shape, the run
  matching through `public.v_sequencing_browse`;
- `scripts/sync_v3.sh`: credentials through `apply_migrations.psql_base()`, the failure marker;
- `049`/`050`: the opt-in `PGOPTIONS` guard pattern, if any step ever becomes destructive. None
  is planned, since `public` is untouched.

## 5. Verification

- Each migration checks itself before `COMMIT`: compatibility view against public, `EXCEPT ALL`
  both ways, 0 rows; FK and CHECK counts asserted.
- RG.5 rehearsal as above: apply → check → sync no-op → simulated changes → revert → re-apply.
- Writer unit tests: `pytest` in both repos.
- Old and new writer output compared row by row on the restore.
- Live readers, read-only, give identical output under `search_path=v4,public`.
- After the live apply: `bin/apply_migrations.py --verify`, `bin/check_drift.py`, and a week of
  clean `~/log/genomes_db_sync_v4.log`.
