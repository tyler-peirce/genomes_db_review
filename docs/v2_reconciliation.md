# `v2` reconciliation against `public` — Phase V.4

Run 2026-10-06 against live (`oceanomics_genomes` @ 146.118.120.134), after the backfill and
before any import. Workbook for every figure: `OceanGenomes_Database_261006.xlsx`.
Tool: `scripts/reconcile_v2.py` (read-only; exits non-zero on anything UNEXPLAINED).

## Result

**Zero UNEXPLAINED.**
- Every one of the 12 lab tables accounts for every `public` row by key, either loaded into
  `v2` or blocked with an open quarantine record. Nothing is LOST and nothing is INVENTED.
- All 17 tables are identical on the columns that survive unchanged, compared with `EXCEPT ALL`
  in both directions.
- Every value the backfill could not cast has a `type_cast` record naming the field and keeping
  the raw value.
- Every quarantine class has a recorded cause.

## The reconciliation found two backfill bugs first

The first run was on a fresh restore of live, and it failed. Neither bug is visible in row
counts, and both had passed the V.2 and V.3 rehearsals.

1. **`dna_extraction.ratioqubit_nanodrop` was never copied.**
   - V.1 kept the column in the `v2` DDL precisely so that the backfill would carry its 987
     hand-entered measurements, but the backfill never referenced it.
   - All 986 values on loaded rows would have arrived NULL.
   - The 987th value is on a blocked row, and is kept in that row's quarantine `raw_row`.
2. **Values that would not cast were nulled silently.** The backfill's header promises a
   quarantine record "naming the field".
   - Only `sample` (minus `lengthtl_and_lengthfl`) and `dna_extraction.extraction_date` did
     that.
   - Everywhere else, values such as `>1.8`, `pooled library = 2.60ng/ul`, `7.0 and 5.8` or
     well IDs in `library_molarity` became NULL with no trace.
   - `dna_extraction`'s two `type_cast` statements also overwrote each other, because
     `v2.quarantine()` keeps one open row per (table, key, type).
   - Fixed with one combined `type_cast` record per row, naming every failed field.

Both were fixed in `scripts/backfill_v2.sql` (commit `c0d59d6`) and re-rehearsed before
anything touched live.

## Sequence on live

| Step | Result |
|---|---|
| `import_v2.py --stage-attempt-keys` | 6,578 keys, identical to the rehearsal |
| `scripts/run_backfill.py`, pass 1 | 8 s on the rehearsal; counts below |
| pass 2 | 0 rows inserted; report identical to pass 1 |
| `scripts/reconcile_v2.py` | exit 0 (output below) |
| `import_v2.py -e`, once | exit 0, nothing displaced, output identical to the rehearsal import |
| open quarantine after the import | **1,352** (V.3 rehearsal: 1,333; the +19 are the new `type_cast` records, e.g. 15 for `run_date = 'None'`) |

`apply_migrations.py --verify` (41), `diff_v2_against_live.py` (0) and `check_drift.py` (only
the `og_workflow_*` three) are unchanged.

## Things for the lab and the owner

- **`v2.v_quarantine_open` is now the lab's worklist.** Several classes are recoverable, not
  just fixable:
  - 84 `illumina_library` rows hold `pooled library = 2.60ng/ul`, a parseable value in a
    sentence.
  - 29 `rna_library_ilmn.library_molarity` values are plate-well IDs, which suggests a column
    shift on those rows.
  - About 50 sample coordinates are written in degrees/minutes/seconds.

  Whether to parse any of these is an owner decision. The backfill does not guess.
- **Re-running the backfill after the lab fixes rows** loads newly passing rows. It does not
  rewrite rows already loaded, which is `ON CONFLICT DO NOTHING` by design. Once the nightly
  `import_v2.py` runs, the workbook is the source for those rows.

## Live reconcile output

```
Database: oceanomics_genomes @ 146.118.120.134/32

=== 1. accounting: every public key loaded or blocked ===
  table               public  loaded blocked degraded  LOST INVENTED
  sample                3294    3294       0      756     0        0
  tissue                7241    7240       1        0     0        0
  dna_extraction        2636    2584      52      230     0        0
  rna_extraction         270     270       0       20     0        0
  hic_lysate             439     430       9        0     0        0
  illumina_library      2080    2079       1       88     0        0
  pacbio_library         439     436       3        0     0        0
  ont_library             98      98       0        0     0        0
  hic_library            326     326       0        4     0        0
  rna_library_ilmn       389     389       0       29     0        0
  rna_library_kinx       189     188       1        0     0        0
  sequencing            4765    4725      40       14     0        0

=== 2. values on unchanged columns (EXCEPT ALL, both directions) ===
  sample                40 cols   public-v2      0   v2-public      0   ok
  tissue                11 cols   public-v2      0   v2-public      0   ok
  dna_extraction        20 cols   public-v2      0   v2-public      0   ok
  rna_extraction        19 cols   public-v2      0   v2-public      0   ok
  hic_lysate            10 cols   public-v2      0   v2-public      0   ok
  illumina_library      10 cols   public-v2      0   v2-public      0   ok
  pacbio_library        15 cols   public-v2      0   v2-public      0   ok
  ont_library            9 cols   public-v2      0   v2-public      0   ok
  hic_library           12 cols   public-v2      0   v2-public      0   ok
  rna_library_ilmn      13 cols   public-v2      0   v2-public      0   ok
  rna_library_kinx       8 cols   public-v2      0   v2-public      0   ok
  sequencing            10 cols   public-v2      0   v2-public      0   ok
  mitogenome_data      103 cols   public-v2      0   v2-public      0   ok
  lca                   26 cols   public-v2      0   v2-public      0   ok
  lca_validation        10 cols   public-v2      0   v2-public      0   ok
  lca_raw_results       26 cols   public-v2      0   v2-public      0   ok
  blast_filtered_lca    28 cols   public-v2      0   v2-public      0   ok

=== 3. retyped columns: every value the backfill could not cast is recorded ===
  sample.weight                            text -> real:  182 nulled,    0 unrecorded
  sample.lengthtl_and_lengthfl             text -> real:  305 nulled,    0 unrecorded
  sample.latitude_collection               text -> double precision:  285 nulled,    0 unrecorded
  sample.longitude_collection              text -> double precision:  297 nulled,    0 unrecorded
  sample.depth_collection                  text -> real:  301 nulled,    0 unrecorded
  dna_extraction.extraction_date           text -> date:    9 nulled,    0 unrecorded
  dna_extraction.ratio_260_280             text -> real:   33 nulled,    0 unrecorded
  dna_extraction.ratio_260_230             text -> real:   43 nulled,    0 unrecorded
  dna_extraction.av_size                   text -> real:  185 nulled,    0 unrecorded
  rna_extraction.ratio_260_280             text -> real:   10 nulled,    0 unrecorded
  rna_extraction.ratio_260_230             text -> real:   15 nulled,    0 unrecorded
  rna_extraction.rin                       text -> real:    3 nulled,    0 unrecorded
  illumina_library.library_qubit_conc      text -> real:   88 nulled,    0 unrecorded
  hic_library.library_date                 text -> date:    4 nulled,    0 unrecorded
  rna_library_ilmn.library_molarity        text -> real:   29 nulled,    0 unrecorded
  sequencing.run_date                      text -> date:   14 nulled,    0 unrecorded

=== 4. open quarantine by class ===
  dna_extraction     foreign_key               1   extraction with a null tissue_id (F7: parent FK is NOT NULL)
  dna_extraction     type_cast               231   inequalities in ratios ('>1.8', '>2'), size descriptions in av_size ('UHMW', '12605bp (PEAK) ~50% >10kbp'), partial dates ('2026-03-')
  dna_extraction     unique                   51   attempt-key ties: two tubes share (tissue_id, ext_num). Seated by the workbook where it carries exactly one (V.2 decision); the rest are renamed tubes and the OG2274H_D_D / OG2274H_D2 typo pair
  hic_library        type_cast                 4   free-text notes typed into library_date
  hic_lysate         conflicting_value        10   F13: libraries of one lysate disagree on proximity-ligation concentration, so the value is not promoted; row loads
  hic_lysate         unique                    9   attempt-key ties, as dna_extraction
  illumina_library   type_cast                88   'pooled library = 2.60ng/ul' (84 rows) and 'FAIL' in library_qubit_conc
  illumina_library   unique                    1   attempt-key tie against a placeholder tube ID '0'
  library            duplicate_source_row     24   §4.4: tube ID in both RNA library tables, so it cannot be one registry key
  pacbio_library     foreign_key               1   no registry row for (tube, parent): parent extraction missing or tube registered to a different parent
  pacbio_library     unique                    3   attempt-key ties against placeholder tube ID '0'
  rna_extraction     type_cast                20   inequalities in ratios ('>2.0'), two values or 'Fail' in rin
  rna_library_ilmn   conflicting_value        16   F4/§6.4: Kinnex primer/barcode values on the Illumina RNA table, dropped in v2 and identical to the rna_library_kinx copies; row loads
  rna_library_ilmn   type_cast                29   plate-well IDs ('F07', 'E09') in library_molarity
  rna_library_kinx   unique                    1   attempt-key tie against a placeholder tube ID
  sample             type_cast               756   text in measurement/coordinate columns: weight 'pup', length ranges, DMS coordinates, Excel date-times in latitude, depth '<1'
  sequencing         not_null                 40   F6: sequencing rows linked to no library in any of the five live columns
  sequencing         type_cast                15   the literal text 'None' in run_date
  tissue             not_null                  1   tissue_id blank or the placeholder 0 (lab_key_strategy.md §2)

----------------------------------------------------------------------
UNEXPLAINED: 0
```
