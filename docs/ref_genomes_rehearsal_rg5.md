# Phase RG, RG.5 record: writers and readers against `v4`

Run 2026-10-20 (00:06–00:40 UTC). Runbook: [`ref_genomes_runbook_rg0_rg5.md`](ref_genomes_runbook_rg0_rg5.md)
RG.5.

- **Writers:** run on a throwaway PostgreSQL 14 cluster restored from a `pg_dump -Fc` of live taken at
  00:06 UTC, with `057`–`059` applied (`en_AU.UTF-8`; roles `readonly` and `oceangenom_web`
  recreated).
- **Readers:** the database functions and views were run on live, read-only. The samplesheet scripts
  run DDL (below), so they were run on the restore.
- **Pairing:** each old writer is the `master` version, writing `public`. Each new one is the
  `phase-rg-v4` branch (ref-genomes `47fd998`, post-curation `cd2001f`), run with
  `PGOPTIONS='-c search_path=v4,public'`. Both write from the same input files, exported with
  `git archive` so the repos were not touched. **No sync ran between them,** so v4 holds only what the
  new writers wrote.
- **Inputs:** the RG.4 test fixtures (real compiled TSVs from `OceanOmics-Database/SS/ref_genomes_table`,
  and OG762 stage-3 values for post-curation). They were rewritten to a **rehearsal key that cannot
  collide with real rows:** OG762 `seq_date` 991231, and HiFi run `PACB_991231_XX`. Pawsey was
  unreachable (RG.0 §2).

## RG.5.1 Writers: old against new

| Script | Old (`master`) → `public` | New (`phase-rg-v4`) → `v4` |
|---|---|---|
| ref `04a` gfastats | exit 0, 2 rows | exit 0, `ref_gfastats` 2 |
| ref `03a` BUSCO | exit 0, 6 rows | exit 0, `ref_busco` 6 |
| ref `02b` Merqury QV | exit 0, 3 rows | exit 0, `ref_merqury_qv` 3 |
| ref `02d` Merqury completeness | exit 0, 3 rows | exit 0, `ref_merqury_completeness` 3 |
| ref `05a` OMNIC | exit 0, 5 rows | exit 0, `ref_omnic` 5 |
| ref `04b` HiFi gfastats | exit 0, 2 rows | exit 0, `ref_gfastats` 2 |
| ref `01a` GenomeScope | exit 0, 1 row (`raw_qc`) | exit 0, `ref_genomescope` 1 (dated 991231) |
| ref `0a` HiFiAdapterFilt | exit 0, 1 row (`raw_qc`) | exit 0, `ref_hifi_adapter_filter` 1 |
| ref `0b` HiFi yield | exit 0, 1 row | exit 0, `hifi_read_qc` 1 |
| post-curation `02b`, `02d`, `03a`, `04a`, `05a`, `06b` | exit 0, 2 rows each | exit 0: `ref_merqury_qv`, `ref_merqury_completeness`, `ref_busco`, `ref_gfastats`, `ref_seqkit_stats`, `ref_chromosome_stats`, 2 each |

| Comparison, before any sync | Result |
|---|---|
| `v4.ref_genomes` against `public.ref_genomes`, OG762 991231 | **10 rows each, 0 differ either way.** That is hic1 stages 0/2/3 including the dual parts, plus hifi1 stage 0 p_ctg/a_ctg. In v4: 2 assemblies, 10 parts |
| `v4.raw_qc` against `public.raw_qc`, OG762 | **Identical.** v4 also keeps OG762's earlier undated GenomeScope row (genomesize 608,223,064) beside the new 991231 one. `public` overwrote it |
| `v4.hifi_reads_qc` against `public`, run `PACB_991231_XX` | **0 differ either way** (2 SMRT cells summed into 1 row) |
| `sync_v4.sql` afterwards | **The only change was 1 `ref_genomescope` row:** the undated OG762 row, refreshed from the per-OG `raw_qc` row the old writer had rewritten. Every other table was already equal, so the new writers write what the sync would. All 15 checks 0 |

## RG.5.2 Behaviour on the restore

| Case | Result |
|---|---|
| A Merqury QV record with every value blank (hic1 stage 0 hap1) | New: `ref_merqury_qv: 1 deleted`. The part was kept, because BUSCO and OMNIC remain. v4 against public: still 0 differences (the old writer blanked the columns) |
| The same BUSCO file run again (new writer) | Exit 0; v4 values unchanged (md5 identical) |
| An orphan `og_id` (OG999999) in a gfastats file | **New:** `ForeignKeyViolation` on `ref_assembly`, exit 1, nothing written. **Old:** exit 0, and the orphan row landed in `public.ref_genomes`, which has no FK. The next sync then failed on it as an untriaged key, as designed |
| Simulated RG.6, on a clone: `public.ref_genomes` renamed and replaced by a view of `v4.ref_genomes` | **Old ref `03a` and old post-curation `04a`:** print `cannot insert into view "ref_genomes"` **but exit 0**. New `03a` on the same clone: exit 0, 6 rows written |

**RG.6 requirement from the last row.** After the swap, an old writer fails without the pipeline
noticing, because it still exits 0. RG.6 must deploy both `phase-rg-v4` branches on Pawsey **before**
the swap, and confirm the deployed scripts are the new ones, e.g. that `scripts/lib/refdb.py` is
present. Exit codes alone will not reveal stale code.

## RG.5.3 Readers

**Database functions and views, on live, read-only.** Each was run under the default `search_path`
and again with `SET search_path = v4, public`, and the outputs compared by md5. The input was every
OG in `ref_genomes` and `ref_genomes_assembly_uploads`, plus OG2613, OG1 and OG13.

| Reader | Rows | Result |
|---|---:|---|
| `build_final_data_compile(NULL)` | 29 | identical |
| `coverage_summary` (resolves to `v4.coverage_summary`) | 252 | identical |
| `goat_species_v1` (resolves to `v4.goat_species_v1`) | 19,817 | identical |
| `build_postcuration_samplesheet_rows` | 252 | **1 row differs, explained:** OG906. Default: version and date blank, because public's OG906 hic1 has `seq_date ''`, which the function filters out. v4: `hic1`, `v250212`, the RG.0 remap (`ref_key_map`). This is the triage correction, visible to a reader |
| `build_nfcore_samplesheet_rows`, `build_hicpost_samplesheet_rows` | — | **Fail under both paths, an existing defect:** `column seq.og_id does not exist`. They join `sequencing.og_id`, which the v2 cutover removed. Not comparable, and not caused by RG |

A first pass of this table was invalid and is not reported. The read-only helper set `PGOPTIONS`
itself and overrode the `search_path`. The rerun sets the path inside the session and confirms it
(`to_regclass('ref_genomes')` resolves to v4).

**Samplesheet scripts, on the restore** (`master` code; RG.4 did not change them). Each was run
under both paths, and the CSV outputs compared, for 15 OGs covering the RG.0 edge cases (OG762,
OG820, OG906, OG88, OG108, OG90, OG113, OG637, OG910, OG645, OG2613, OG1, OG13, OG57, OG749):

| Script | Result |
|---|---|
| post-curation `create_samplesheet_from_config.py` | 15 rows. Identical except OG906 (`hic1,v250212` under v4), the same explained difference as above |
| ref `create_samplesheet_from_config.py`, `_hifi_hic.py`, `_hifi_only.py` | **Exit 1 under both paths, an existing defect:** the same `seq.og_id` join. **The ref pipeline's samplesheet step cannot run against today's database,** unless Pawsey runs newer code than this clone |

**Two facts about these scripts, for RG.6:**
- **They run DDL.** Each run does `DROP FUNCTION IF EXISTS` and `CREATE OR REPLACE FUNCTION` in the
  live database. The three ref scripts all overwrite the same `public.build_nfcore_samplesheet_rows`,
  so live holds whichever variant ran last.
- **Under `search_path=v4,public` the DDL lands in v4.** On the restore, the post-curation script's
  `DROP` resolved to the public function and dropped it, and its `CREATE` then made
  `v4.build_postcuration_samplesheet_rows`. **Never run these scripts with the v4 path on live.**
  After RG.6 the question disappears, since there is no v4 path any more. The functions should then
  become migrations rather than objects a pipeline script recreates.

**`query_hichifi_results.py`, on live, read-only.** The old version (`master`, `public`) was compared
with the new (`phase-rg-v4`, v4) for OG762, OG820, OG88 and OG2613:
- Both exit 0.
- The old report lists every stage: 32 rows. The new one lists each assembly and haplotype at its
  latest stage: 18 rows. That is the intended change of view.
- The remapped keys show under their corrected assemblies (OG820 240501 hic1, OG88 230728 hifi1).
- The Hi-C yield section is identical.

**Not checked:** OceanGenom_Web (queries not available, RG.0 §3).

## Gate for RG.6

| Condition | State 2026-10-20 |
|---|---|
| Sync clean nightly for a period the owner chooses | 1 unattended night (2026-10-19 19:00 UTC) plus 3 hand runs, all `sync_v4 ok`; no `.FAILING`. **Owner to set the length** |
| RG.5 recorded and passed | **Yes** (this record) |
| Every reader accounted for | **Yes, except OceanGenom_Web**, which is still a condition. The two broken functions and three broken ref samplesheet scripts are an existing defect, to fix in their own change |
| `check_drift.py` and `--verify` clean | **Yes:** no inventory drift; ledger 60, all hashes match |

**Carried into the RG.6 runbook:**
1. Deploy both `phase-rg-v4` branches before the swap, and verify by file, not exit code.
2. The samplesheet functions: fix the `sequencing.og_id` join (a v2-cutover leftover), and move
   the functions into migrations so pipeline scripts stop running DDL.
3. The open writers: `hic_reads_qc` and the upload tables (RG.0 §3), and the meaning of
   `status_date`.
4. OceanGenom_Web's queries.
5. Whether to fold the split hifi1 assemblies (RG.1 record, the observation section).
