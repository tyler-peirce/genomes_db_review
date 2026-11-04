# RG.6 record: `v4` swapped into `public` (`073`), 2026-11-02

Plan: [`ref_genomes_rg6_plan.md`](ref_genomes_rg6_plan.md). R.6 (`072`) ran first the same day, which settled G5.

## Gate on the day

| # | Item | State |
|---|---|---|
| G1 | Clean nightly syncs | 17 nights clean (owner: ready) |
| G2 | Writers ported | All but `OcOm_B219`'s GCA resolver, which the owner left to its maintainer |
| G3 | OceanGenom_Web | Not checked; the owner chose to go ahead, as at R.6 |
| G4 | Undated read sets | 0 (`071`; and today's pushes, below) |
| G5 | Order | R.6 first (`072`) |
| G6 | Drift | Only the colleague's three objects |
| G7 | Rehearsal | Three restores of live, last one taken 08:04 UTC |

## Found while preparing

- **A writer the plan missed:** `ref_gen_automation` (the HiFi-only automation). Its `post-assembly.py` runs the ref-genomes push scripts from lhuet's production clone (`SCRIPTS_DIR`), but called the GenomeScope push without the samplesheet the ported script needs for the read-set date. Fixed on `phase-rg-v4` (`fc75e7f`). Its own `compile_push/` copies are not what the automation runs.
- **lhuet's production clone** (`/scratch/pawsey0964/lhuet/ref-gen/OceanOmics-OceanGenomes-ref-genomes`) moved to `fix/samplesheet-sequencing-view` today (`50f73db`). That branch made the same samplesheet change as `phase-rg-v4`. It is now merged into `phase-rg-v4` (`b330b00`), keeping the `phase-rg-v4` version, which also skips failed runs and malformed dates, so the clone fast-forwards.
- **Old writers exit 0 on failure.** The old GenomeScope push prints "cannot insert into view" and exits 0, so a clone left behind fails silently. The clones must update together with the swap.
- **`sequencing_run` has no maintainer since `072`.** R.6 dropped its sync and nothing inserts new runs, so `073` does not add the planned read-QC `run_id` FKs: they would refuse the Hi-C yield of a run the workbook has not reached. Left to R.7.
- **lhuet's genome-size pushes, 05:00–07:50 UTC,** through the old `raw_qc`, for OG114, OG1573, OG2151, OG2202, OG62, OG665 and OG760. Only `genomesize` changed, with no new runs. The owner confirmed they are real and must persist. `073` step 0 writes them onto each OG's latest dated read set. OG760 had been excluded at RG.0 ("no value in any column"); it gets its first read set, `240520`, on its only PacBio run, and the exclusion is removed. Without this step, the final sync's checks failed, and tonight's sync would have failed too.
- **Already broken before RG.6:** `build_nfcore_samplesheet_rows` and `build_hicpost_samplesheet_rows` query `sequencing.og_id`, which the v2 cutover removed. Untouched here.

## Rehearsal (restore of live; final run on the 08:04 UTC dump)

| Check | Result |
|---|---|
| Apply without `oceanomics.rg6_swap=go` | Refused; nothing changed |
| Apply | v4 dropped; 6 old tables, 2 views and `ref_key_map` / `ref_excluded_rows` in `pre_v4_archive`; 23 tables, 14 views, 6 functions in `public` |
| Compatibility views | All 8 byte-identical to their v4 versions before the swap |
| Views | 52 select (`public` and the three archives) |
| Grants | `readonly` reads the moved objects; `oceangenom_web` reads `ref_genomes` and `ref_genomes_assembly_uploads` |
| New writers, default `search_path` | `push_hic_yield.py` (30 rows equal), `0b` HiFi yield, `01a` GenomeScope (updates OG845's dated read set in place) |
| Old writer | `cannot insert into view "raw_qc"` (exit 0, see above) |
| Triggers and resolver | Haplotype push-down and the external-read-set refusal work; the resolver gives the same answer for all 290 linked uploads as before the swap |
| `build_postcuration_samplesheet_rows` | Same output, except OG906 now gets `hic1, v250212` (its corrected key from `ref_key_map`) instead of blanks |
| Revert | Schema identical; rows identical (sequence counters aside, which the final sync's upserts advance) |
| Re-apply, then replay with the ledger row deleted | Identical schema; the replay is a no-op |

## Live

- **Pre-change dump:** `~/oceanomics_genomes_pre_073_261102.dump` (24 MB), 08:05 UTC.
- **Applied:** about 08:06 UTC with `PGOPTIONS="-c oceanomics.rg6_swap=go" bin/apply_migrations.py`. The ledger has 74 rows and verifies.
- **Post-checks (read-only):** schemas `public`, `pre_v2_archive`, `pre_v3_archive` and `pre_v4_archive`; the eight old names are views; rows `ref_genomes` 2,024, `raw_qc` 249, `hifi_reads_qc` 277, `hic_reads_qc` 552, uploads 88 / 304; 249 read sets, none undated; readiness: read sets 1 (OG763), SRA 14, assemblies 61; no public function names `v4`; 52 views select; grants hold.
- **Cron:** the 19:00 UTC `sync_v4.sh` line removed. Backup: `~/crontab_backup_pre_073_261102.txt`.
- **Baseline:** `schema/` updated with exactly `073`'s delta, taken from a restore exported before and after the swap. Drift shows only the colleague's three objects.
- **Writers pushed to GitHub, `phase-rg-v4`:** ref-genomes `b330b00`, `ref_genomes_hic_automation` `4180383`, `ref_gen_automation` `fc75e7f`. Post-curation (`36db095`) and `ENA-ref-genomes` (`3f245cf`) were already there. Every default branch fast-forwards to its `phase-rg-v4`.
- **Deploy:** lhuet updates her Pawsey clones (ref-gen ref-genomes, post_curation, `ref_genomes_hic_automation`, `ref_gen_automation`) to `phase-rg-v4`. Until then, their pushes into the old names fail ("cannot insert into view"), and the GenomeScope push fails silently. Their result files stay in place and can be re-pushed.

## Left for later

- **RG.7:** after a quiet period, drop `pre_v4_archive`, with a `pg_dump` taken the morning of, kept outside git.
- **R.7** (migration numbers from `074`): FKs to `sequencing_run` for `sequencing`, `raw_data`, `hifi_read_qc` and `hic_read_qc`, once something maintains `sequencing_run`. `v_sequencing_run_fk_readiness` now reads the new read-QC tables.
- **Default branches:** done 2026-11-04. All five fast-forwarded to `phase-rg-v4` and pushed (ref-genomes `master` `b330b00`, post-curation `master` `36db095`, `ENA-ref-genomes` `main` `3f245cf`, `ref_genomes_hic_automation` `main` `4180383`, `ref_gen_automation` `master` `fc75e7f`), with tests passing (33, 30, 10). On Pawsey, lhuet's ref-genomes, Hi-C and HiFi-only clones are on `phase-rg-v4`. **Her `post_curation` clone was still on the old `master` (`76215a5`) on 2026-11-04:** its pushes fail on the views until she pulls.
- **`OcOm_B219`'s GCA resolver** fails on `ref_genomes_assembly_uploads` until ported. The view's comment names the tables to write.
- **The two broken `build_*` functions** (above).
