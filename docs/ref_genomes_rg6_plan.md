# Phase RG.6 plan — move `v4` into `public`

Status: **plan, 2026-11-02.** Nothing here has run. Source: `docs/ref_genomes_runbook_rg0_rg5.md`
("Gate for RG.6"). RG.0–RG.5 and migrations `057`–`065` and `069`–`071` built and filled `v4`; this is
the swap that makes it the reference-genome schema of record.

## Where things stand

`v4` holds the reference-genome data in relational form, beside `public`, kept equal to it by
`scripts/sync_v4.sh` (19:00 UTC). On 2026-11-02:

- **17 nightly syncs clean** since `062`; no `sync_v4` failure marker.
- **Tables:** `ref_assembly` / `ref_assembly_part` / `ref_assembly_run` and seven per-tool tables; read
  sets (`ref_read_set`, `ref_read_set_run`, `ref_read_set_external`, `ref_genomescope`, `ref_hifi_adapter_filter`); read QC
  (`hifi_read_qc`, `hic_read_qc`); submissions (`ref_submission`, `ref_submission_haplotype`,
  `ref_sra_upload`, `ref_sra_upload_run`, `ref_sra_upload_unlinked`).
- **Links:** 244 of 248 read sets dated (all 248 once `071` is applied: OG906 recorded as external
  reads, OG763 dated but waiting for its DNA row), 290 of 304 SRA uploads linked, 166 of 174 submitted haplotypes
  tied to their curated part, no link to a failed run.
- **Compatibility views** under the old names (`ref_genomes`, `raw_qc`, `hifi_reads_qc`, `hic_reads_qc`,
  `ref_genomes_assembly_uploads`, `ref_genomes_sra_uploads`, `coverage_summary`, `goat_species_v1`)
  equal `public` row for row, checked every night.
- **Writer branches pushed, not deployed:** `phase-rg-v4` in `OceanOmics-OceanGenomes-ref-genomes`
  (`c702f59`), `-post-curation` (`36db095`) and `ENA-ref-genomes` (`3f245cf`).

## The gate

RG.6 runs when every row below is done. The middle column is what is still open.

| # | Gate item | Open on 2026-11-02 | Who |
|---|---|---|---|
| G1 | The nightly sync clean for a period the owner chooses | 17 nights so far; **owner to set the period** | owner |
| G2 | Every writer of the six replaced objects ported | **One not ported:** `push_hic_yield.py` ported 2026-11-02, the GCA resolver waits for its repo (below) | Claude, then their owners |
| G3 | Every reader checked against `search_path=v4,public` | **OceanGenom_Web unchecked** (code not on this host) | web app owner |
| G4 | Undated read sets dated or removed | **`071` written and rehearsed, not applied.** Owner, 2026-11-02: OG906 250212 external (`SSB/SSC` cells, supplier unknown), OG845 241023, OG781 260421, OG763 251117 (its DNA row on `PACB_251117_LAAMD` is missing from the workbook) | owner applies |
| G5 | R.6 and RG.6 ordered | **Decision needed** (below) | owner |
| G6 | `check_drift.py` and `--verify` clean apart from the colleague's known drift | Clean | — |
| G7 | A rehearsal on a restore of live, as RG.5 | Not yet | Claude |

### G2: the two writers that write the replaced tables

| Writer | Writes today | After RG.6 it writes | Notes |
|---|---|---|---|
| `OcOm_B219` `scripts/resolve_gca_accessions.py` (each quarterly report) | `UPDATE ref_genomes_assembly_uploads SET gca_accession_hapN` | `ref_submission_haplotype.gca_accession`, as `ENA-ref-genomes` step 10 already does | Found 2026-10-20 (RG.0 §5); RG.5 noted it, nothing ported. Not cloned on this host |
| `ref_genomes_hic_automation` `push_hic_yield.py`, from `poll-hic-multiqc.py` | `INSERT … ON CONFLICT DO NOTHING` into `hic_reads_qc`, per lane | `hic_read_qc`, with `sequencing_id` resolved as the sync does | **Ported** 2026-11-02, branch `phase-rg-v4` (`4180383`, local; the repo is LaurenHuet's). Also fixes a per-row `rollback()` that dropped earlier rows. Tested on a restore: 30 rows equal, sync no-op |

Unported, each fails on the swap day with `cannot insert into view` / `cannot update view`: loud, not
silent, but the quarterly report or the Hi-C poll stops until fixed. The other scripts in
`ref_genomes_hic_automation` only read `ref_genomes` and `hic_reads_qc`, which stay as views.

### G5: R.6 first, or RG.6 first

R.6 (merging `v3` into `public`) is being prepared in its own gate batch (`docs/r6_gate_plan.md`). The
two swaps touch different tables, but they meet in two places:

- `v3.sequencing_run` is the run entity. `hifi_read_qc.run_id` and `hic_read_qc.run_id` should FK to it,
  which can only happen once both are in `public`.
- `v3.v_sequencing_run_fk_readiness` reads `public.hifi_reads_qc` / `hic_reads_qc`, which RG.6 archives.

**Recommendation: R.6 first, RG.6 after.** R.6 puts `sequencing_run` in `public` and drops its
window-only readiness view, so RG.6 can add the read-QC `run_id` FKs in the same swap and has no `v3`
object to re-point. The three `PACB_250717_AD`, `NOVA_240719_AD` and `NOVA_250114_AD` runs are now in
`sequencing_run`, so all 829 read-QC rows would satisfy the FK.
If RG.6 must go first, its migration re-points `v3.v_sequencing_run_fk_readiness` to the moved tables and
leaves the `run_id` FKs to R.7.

## The swap migration (number taken on the day)

One migration, behind an opt-in (`PGOPTIONS="-c oceanomics.rg6_swap=go"`), as `045` was. The writers
deploy the same day, so there is no window for an old writer to write into a view.

1. **Pre-flight inside the migration.** `v4` checks all 0; the sync a no-op; no undated read set (G4);
   no row in `ref_key_map` / `ref_excluded_rows` that the sync has not already applied.
2. **Final sync,** then refuse to continue if it changed anything.
3. **Archive the old objects** into a new schema `pre_v4_archive`, because the `v4` compatibility views
   carry their names: tables `ref_genomes`, `ref_genomes_assembly_uploads`, `ref_genomes_sra_uploads`,
   `raw_qc`, `hifi_reads_qc`, `hic_reads_qc`; views `coverage_summary`, `goat_species_v1`.
   `pre_v2_archive.goat_species_v1_pre_v2` follows `ref_genomes` there by OID (an archive reading an
   archive); nothing live does.
4. **Move `v4` into `public`:** every table, sequence, compatibility view, readiness and status view,
   and the functions that outlive the window (`ref_assembly_run_genomic_only`,
   `ref_read_set_run_pacbio_only`, `ref_read_set_external_exclusive`, `ref_submission_haplotype_assembly`,
   `ref_submission_assembly_to_haplotypes`, `resolve_sra_upload_runs`).
5. **Rewrite what binds to `v4` by text:**
   - the two haplotype triggers (`070`) name `v4.ref_submission` / `v4.ref_submission_haplotype` in
     their bodies → `public.`;
   - `resolve_sra_upload_runs()` is `SET search_path = v4, public` → `public, pg_temp`;
   - anything else the migration finds by scanning `pg_proc.prosrc` and view definitions for `v4.`
     (the migration asserts none is left).
6. **Drop the window-only objects:** `sync_ref_*()`, `check_ref_*()`, the seven `sync_*` source views,
   `ref_key_map` and `ref_excluded_rows` (archived to `pre_v4_archive` first: they record why rows were
   remapped or left out). Remove the 19:00 UTC `sync_v4.sh` cron line the same day.
7. **If R.6 has run:** FK `hifi_read_qc.run_id` and `hic_read_qc.run_id` → `sequencing_run`
   (`NOT VALID`, then `VALIDATE`).
8. **Grants.** Grants travel with `SET SCHEMA`; the migration asserts `readonly` can read every moved
   object and `oceangenom_web` keeps `SELECT` on `ref_genomes` and `ref_genomes_assembly_uploads`.
9. **Drop schema `v4`.** Assert no object in `public` depends on `pre_v4_archive`, and no function body
   or view names `v4.`.

**Revert:** moves everything back (`public` → `v4`, `pre_v4_archive` → `public`), restores the
window-only functions from their migration texts, and re-adds the cron line by hand. Rehearsed like
`045`: apply, post-checks, revert, schema identical, re-apply.

## On the day

1. Pre-flight: last night's import and sync clean; `--dry-run` shows only the swap; pre-change dump.
2. Apply the swap.
3. Deploy the writers: merge `phase-rg-v4` in ref-genomes, post-curation and `ENA-ref-genomes`, and
   the two ports from G2, to their production branches; the owners update the clones on Pawsey.
4. Post-checks: `\dv` shows the compatibility views in `public`; `readonly` and `oceangenom_web` read
   them; `bin/apply_migrations.py --verify`; re-baseline only the objects the swap explains (the
   colleague's drift stays out, as now).
5. **Watch the first real runs:** the next GenomeScope/HiFiAdapterFilt push creates or updates a read set
   and its run links; the next step 09 writes `analysis_accession` and SRA links; the next Hi-C poll
   writes `hic_read_qc`.

## Rehearsal (G7)

As RG.5, on a restore of live taken the morning of:
- apply the swap; post-checks as above;
- run every new writer with real fixtures (`01a`, `0a`, `02b`–`05a`, `0b`, post-curation pushes, steps
  09/10, the two G2 ports) and compare with the old writers' output on the same inputs;
- run every reader at the default `search_path` and diff with today's output on live: the four
  `build_*` samplesheet functions, the three samplesheet scripts, `query_hichifi_results.py`,
  `coverage_summary`, `goat_species_v1`, `OcOm_B219` `queries.py`, the genome-notes script;
- revert, compare schema and rows with the pre-swap dump, re-apply.

## After RG.6

- **RG.7 (close-out):** after a quiet period, drop `pre_v4_archive`. A `pg_dump` the morning of goes outside git.
- **Labels the owner parked:** OG819 `250704.hic2` (built from 250717 reads), OG56 `250704.*` and OG73
  `250704.hic1` name a failed run, so they have no run link; re-stage or rename when the owner decides.
- **SRA uploads still unlinked (14):** mostly older uploads whose file names carry no run; they stay in
  `v_sra_upload_run_readiness` with their reasons.

## Other open threads (not RG.6)

| Thread | State | Next |
|---|---|---|
| R.6 merge `v3` → `public`, and R.7 FKs | Another session's gate batch (`docs/r6_gate_plan.md`) | Leave to it; agree the order (G5) |
| Samplesheet scripts on Pawsey | Repo versions read `v_sequencing_browse` and count Revio rows (`c702f59`); the v2 handover was never merged | The Pawsey user switches to the repo versions; until then the old copies fail on `seq.og_id` |
| `pacbio/PACB_250704_AD2/` | Byte-for-byte copy of `PACB_250704_AD` (171 GiB) | Owner decides whether to delete |
| `v3.mito_assembly_run` links to failed runs (3) | Left for R.6 | R.6 batch |

## Decisions needed from the owner

1. **G1:** how many clean nights before the swap.
2. **G4:** decided 2026-11-02 (`071`); apply it. Still open: who supplied OG906's SSB/SSC cells, and
   the lab adds OG763's DNA row.
3. **G5:** R.6 first (recommended) or RG.6 first.
4. **G2:** `OcOm_B219`'s resolver: Claude ports it once the repo is cloned here (owner fetching it).
   `push_hic_yield.py`: ported; its owner merges it on the swap day.
5. **G3:** who checks OceanGenom_Web's queries against `search_path=v4,public`.
