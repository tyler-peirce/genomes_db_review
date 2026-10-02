# Spreadsheet → Database Column Gap Analysis

Status: First pass 2026-08-04. **Re-reviewed 2026-08-05 — the first pass was incomplete; see
"Additional gaps found on re-review" below.** Source spreadsheet:
`OceanGenomes_Databasev5.Feb24_260804.xlsx` (checked into this repo). Source of truth for the
current mapping: `name_convert.py:DB_TO_EXCEL` in the sibling `OceanOmics-Database` repo,
which `import_data.py` runs against nightly.

## How the gap happens

`import_data.py` maps spreadsheet columns to database columns by **exact header string
match** against `name_convert.py`'s `DB_TO_EXCEL` dict — no fuzzy matching, no
lowercasing/whitespace normalization, no fallback. Any spreadsheet column whose header isn't a
literal key in that map is silently dropped every night: nothing errors, nothing logs, the
column's data just never reaches the database. This review compared the real header row of
every sheet in the current spreadsheet (parsed directly from the sheet XML) against
`DB_TO_EXCEL` to find what's currently falling through.

## New spreadsheet columns with no DB mapping

These are the columns present in the spreadsheet that have never been added to
`name_convert.py` — they are dropped on every import.

| DB table | Sheet | New column(s) | Suggested DB column | Suggested type | Notes |
|---|---|---|---|---|---|
| `sample` | `1.MetaData` | `Sample Condition upon preservation` | `sample_condition_upon_preservation` | `text` | |
| `sample` | `1.MetaData` | `Ethics_Permit` | `ethics_permit` | `text` | |
| `sample` | `1.MetaData` | `Collection_Permit` | `collection_permit` | `text` | |
| `sample` | `1.MetaData` | `Import_Permit` | `import_permit` | `text` | |
| `sample` | `1.MetaData` | `Cultural_Significance` | `cultural_significance` | `text` | |
| `sample` | `1.MetaData` | `CITES` | `cites` | `text` | Regulatory/compliance — recommend prioritizing this group |
| `sample` | `1.MetaData` | `CMS` | `cms` | `text` | Regulatory/compliance |
| `sample` | `1.MetaData` | `IUCN` | `iucn` | `text` | Regulatory/compliance |
| `sample` | `1.MetaData` | `EPBC` | `epbc` | `text` | Regulatory/compliance |
| `sample` | `1.MetaData` | `Sample Receipt Date` | `sample_receipt_date` | `date` | Stored as an Excel date serial in the sheet, same as `Date_Collected` — importer will need the same serial→date handling |
| `sample` | `Summary` | `RNA processing comment ` | `rna_processing_comment` | `text` | Trailing space is part of the real header string |
| `sample` | `Summary` | `RNA Kinnex Status` | `rna_kinnex_status` | `text` | |
| `tissue` | `2.Tissue` | `Preservation` | `preservation` | `text` | Distinct from `sample.preservation_method` — this is tissue-level |
| `hic_library` | `4.HiCLibrary` | `Processing notes ` | `processing_notes` | `text` | Trailing space is part of the real header string |
| `hic_library` | `4.HiCLibrary` | `Index i5` | `index_i5` | `text` | |
| `hic_library` | `4.HiCLibrary` | `Index i7` | `index_i7` | `text` | |
| `hic_library` | `4.HiCLibrary` | `Library yield (ng)` | `library_yield` | `real` | |
| `hic_library` | `4.HiCLibrary` | `PCR Dup Read Pairs` | `pcr_dup_read_pairs` | `real` | QC metric, currently dropped |
| `hic_library` | `4.HiCLibrary` | `No-Dup Cis Read Pairs >= 1kb` | `nodup_cis_read_pairs_1kb` | `real` | QC metric, currently dropped |
| `hic_library` | `4.HiCLibrary` | `EXPECTED_DISTINCT at 30M reads (M)` | `expected_distinct_30m_reads` | `bigint` | QC metric, currently dropped |
| `sequencing` | `5.Sequencing` | `HiC Depth` | `hic_depth` | `text` | |

## Additional gaps found on re-review (2026-08-05)

The first pass compared only some sheets and excluded a block of columns as "duplicate
identifying info" without checking them individually. Re-running the comparison
programmatically — every header of every sheet against `EXCEL_TO_DB_COLS` — found a further
14 columns of **hand-entered lab data** being dropped nightly.

Each column below was classified by measuring what fraction of its cells contain an Excel
formula (`<f>` elements in the sheet XML). Columns that are ~100% formula are lookups from
another sheet and are correctly ignored; columns with no formulas are typed in by the lab and
exist nowhere else.

| DB table | Sheet | Column | Rows filled | Suggested DB column | Suggested type |
|---|---|---|---|---:|---|---|
| `rna_extraction` | `3.RNAExtractions` | `gDNA? >7,000bp %` | 185 | `gdna_over_7kb_perc` | `real` |
| `pacbio_library` | `4.PacBio` | `SRE Kit` | 394 | `sre_kit` | `text` |
| `pacbio_library` | `4.PacBio` | `Post-SRE Conc. (ng/uL)` | 191 | `post_sre_conc` | `real` |
| `pacbio_library` | `4.PacBio` | `Final Pre-Library Prep Conc. (ng/uL)` | 194 | `final_pre_library_conc` | `real` |
| `pacbio_library` | `4.PacBio` | `Manual/ Automated Method` | 365 | `prep_automation` | `text` |
| `illumina_library` | `4.Illumina` | `Manual/ Automated Method` | 1,607 | `prep_automation` | `text` |
| `illumina_library` | `4.Illumina` | `Library Plate Well` | 1,523 | `library_plate_well` | `text` |
| `illumina_library` | `4.Illumina` | `Index Plate` | 1,297 | `index_plate` | `text` |
| `rna_library_kinx` | `4.RNAkinnex` | `Sequencing Sample ID` | 148 | `sequencing_sample_id` | `text` |
| `hic_lysate` | `4.HiCLysate` | `Prep Method` | 386 | `lysate_method` | `text` |
| `hic_lysate` | `4.HiCLysate` | `Proximity Ligation prep date` | 356 | `prox_ligation_date` | `date` |
| `hic_lysate` | `4.HiCLysate` | `Proximity Ligation Conc. (ng/uL)` | 80 | `prox_ligation_conc` | `real` |
| `sequencing` | `5.Sequencing` | `Status` | 4,004 | `status` | `text` |

Notes:

- **`illumina_library`** loses the most: `Manual/ Automated Method` and `Library Plate Well`
  are populated on the large majority of rows.
- **`hic_lysate`** has no method column and no proximity-ligation columns at all today. The
  proximity-ligation step is currently captured only via `hic_library.prox_ligation_conc`
  (mapped from a *differently cased* header on `4.HiCLibrary` — `(ng/ul)` vs the lysate
  sheet's `(ng/uL)`). The lysate-side measurements are dropped.
- **`sequencing.Status`** has no destination column at all — `sequencing` has no status
  field. 4,004 of ~4,014 rows carry one.
- `4.RNAIllumina`'s `Final Storage Plate Name` and `Well Position` are headers with **zero**
  populated cells. No action needed.

### Confirmed lookups — correctly not imported

These are ~100% formula cells, i.e. Excel pulling a value from the parent sheet. They should
stay out of the database, and are recorded here so they aren't re-flagged:

`DNA Conc. (ng/uL)` and `Average size (bp)` on `4.ONT` / `4.PacBio` / `4.Illumina`;
`RNA Conc. (ng/uL)` and `RIN ` on `4.RNAIllumina` / `4.RNAkinnex`; `Sequencing Sample ID` on
`4.RNAIllumina` (formula-driven, unlike the Kinnex one); `Proximity Ligation yield (ng)` on
`4.HiCLysate`; and the `Specimen ID` / `Project ID` / `Nominal Species ID` / `Common Name/s` /
`Tissue Box` / `Field Identifier` block repeated across child sheets.

### Source-side duplicate library tube IDs

`4.RNAIllumina` has 321 rows but only 312 distinct `Library Tube ID` values (9 repeats);
`4.RNAkinnex` has 175 rows and 174 distinct (1 repeated). Because `queries.py` upserts
`ON CONFLICT (rna_library_tube_id) DO UPDATE`, the last row processed silently wins and the
earlier row is lost with no warning. Duplicated IDs on `4.RNAIllumina`:

`OG645M_R_dIL`, `OG649M_R_dIL`, `OG654M_R_dIL`, `OG657M_R_dIL`, `OG664G_R_dIL`,
`OG680G_R_IL`, `OG681G_R_dIL`, `OG683M_R_dIL`; on `4.RNAkinnex`: `OG108G_R_KL`.

These are quarantine-table candidates rather than schema issues.

## Pre-existing broken mappings (not new columns — data-quality bugs)

These are already in `name_convert.py` but the mapped header no longer matches the real
spreadsheet, so the DB column has been silently `NULL` for some time. Fix is a one-line
header-string change in `name_convert.py` (in `OceanOmics-Database`, not this repo):

- **`rna_library_kinx.synthesis_conc`** — mapped to `"cDNA Concentration (end of section 1
  conc)"`; the real header on `4.RNAkinnex` contains an embedded newline:
  `"cDNA Concentration \n(end of section 1 conc)"`. Never matches → always `NULL`.
- **`rna_library_ilmn.perc_product`** — mapped to `"% Product"`; no column with that header
  exists anywhere on `4.RNAIllumina` today. Always `NULL`.
- **`dna_extraction.ratioqubit_nanodrop`** — mapped to `"Qubit:NanoDrop Ratio"`, which doesn't
  exist on `3.DNAExtractions`. Dead on both ends: the DB column exists
  (`schema/current_schema.sql`) but `queries.py`'s insert for `dna_extraction` doesn't even
  reference this field, so fixing the header alone wouldn't be enough to populate it.
- **`sequencing.seq_type`** (found on re-review) — mapped to `"Type"`, which does not exist on
  `5.Sequencing`. Unlike the three above this does *not* cause data loss, because
  `import_data.py` sets `seq_type` itself in the sequencing-specific branch
  (`import_data.py:135-165`). The dead entry in `name_convert.py` is misleading and should be
  removed: it implies a spreadsheet source that does not exist, and would start silently
  overriding the computed value if a `Type` header were ever added.

## Likely explains an existing backlog item

`docs/data_dictionary.md`'s Column Classification Backlog already flags `status_overwrite` as
"fully empty but referenced by `summary`" across most lab tables. This review's most likely
explanation: the source columns that should feed it — `Status Overwrite` / `Overwrite Status`
/ `Latest` — exist on nearly every sheet but were never added to `name_convert.py`. Not fixed
here since `summary`'s view logic already reads `status_overwrite`; wiring it up is a
deliberate decision, not a drive-by fix.

## The `Summary` sheet is a derived sheet being imported as if it were source data

`name_convert.py` maps `sample` to **two** sheets — `["Summary", "1.MetaData"]` — and the
reverse map applies every `sample` column mapping to both. Seventeen `sample` columns are
therefore fed from `Summary`, which is a formula sheet, not a data-entry sheet.

Formula fraction per `Summary` column (share of populated cells containing an Excel formula):

| Column | → DB column | Cells | Formula | Reading |
|---|---|---:|---:|---|
| `OGID` | `og_id` | 2,627 | 100% | lookup |
| `Project ID` | `project_id` | 2,627 | 99% | lookup |
| `Tissues` | `tissues` | 2,335 | 100% | derived count |
| `Extracted` | `extracted` | 2,627 | 100% | derived count |
| `DNA Extraction Status` | `extraction_queue` | 2,627 | 100% | derived rollup |
| `Illumina Status` | `il_status` | 1,709 | 100% | derived rollup |
| `PacBio Status` | `pb_status` | 2,627 | 100% | derived rollup |
| `HiC Status` | `hic_status` | 2,627 | 100% | derived rollup |
| `NanoPore Status` | **`ont_num`** | 2,627 | 100% | derived rollup |
| `RNA Extraction Status` | `rna_status` | 1,641 | 100% | derived rollup |
| `Illumina RNA Status` | `ilrna_status` | 1,639 | 100% | derived rollup |
| `Field_Identifier` | `field_id` | 2,627 | 100% | lookup |
| `Nominal Species ID` | `nominal_species_id` | 2,627 | 100% | lookup |
| `Common name/s` | `common_name` | 2,627 | 100% | lookup |
| `Collector` | `collector` | 2,627 | 100% | lookup |
| `Contact` | `contact` | 2,627 | 100% | lookup |
| `Workflow` | `workflow` | 2,591 | **7%** | **entered** |
| `Priority` | `priority` | 2,458 | **5%** | **entered** |
| `ilmn` / `hifi` / `hic` / `nano` / `rna` / `ilrna` | same names | 23–2,627 | 0–38% | **mixed / mostly entered** |

Consequences:

1. Every 100%-formula column above is a **stored copy of a value the database can compute**,
   and is the direct cause of Finding 7's status-value chaos in `database_review.md`: the 47
   distinct `sample.rna_status` values and the comma-combined statuses are Excel string
   concatenation being persisted as data.
2. **`sample.ont_num` does not hold a number.** It is mapped to `NanoPore Status` and holds
   status text. Its name is why `database_review.md` Finding 7 lists it as "a numeric-like
   field stored as text" — it is not numeric, it is misnamed. `sample.nano` holds the count.
3. `Workflow` and `Priority` are **hand-entered on the Summary sheet** and exist nowhere
   else. They are real source data and must keep a home in `sample`, despite living on a
   derived sheet.
4. The six count columns (`ilmn`, `hifi`, `hic`, `nano`, `rna`, `ilrna`) are mostly
   hand-entered rather than formula-driven. Before treating them as derivable, confirm
   whether they record *planned* counts (intent) rather than *actual* library counts —
   the database can derive the latter but not the former.

## `5.Sequencing` proves the library-registry model

`5.Sequencing` has a single `Library Tube ID` column (4,014 populated rows). It is not in
`name_convert.py`; instead `import_data.py:129-167` fans it out into the five nullable
`sequencing.*_library_tube_id` columns by branching on `technology` and testing for the
substrings `_D` and `_R` in the ID.

Two things follow:

- The **source system already uses the single-FK model** that `docs/lab_key_strategy.md` §6.4
  proposes. The five-column polymorphic design is introduced by the importer, not inherited
  from the spreadsheet. A `library` registry restores the source's own shape.
- `rna_library_tube_id` receives libraries from *both* the Illumina RNA and PacBio Kinnex
  branches, which is precisely why it is the one library column on `sequencing` with no
  foreign key.

Because this mapping lives in `import_data.py` rather than `name_convert.py`, it is invisible
to any review of the mapping table, and the `_D`/`_R` substring test will misfire on any tube
ID that does not follow the convention.

## Evidence gathered to close the four open questions (2026-08-05)

Measured directly from `OceanGenomes_Databasev5.Feb24_260804.xlsx`.

### `Latest` is derived, and its formula is identical on every sheet

Every `Latest` column is 100% formula, and after normalising row numbers the formula is
byte-identical across `3.DNAExtractions`, `4.Illumina`, `4.PacBio` and `4.HiCLibrary`:

```excel
IF($B2="","",IF(MAX(IF($B:$B=$B2,$C:$C))=$C2,"Y","N"))
```

Column `B` is the parent ID (`Sample ID`, `DNA Tube ID`, `Lysate Tube ID`), column `C` is `#`
— the attempt number. So `Latest` means exactly: **this row has the highest attempt number
for its parent**. It is not lab judgement, it is a window function:

```sql
row_number() over (partition by <parent_id> order by ext_num desc) = 1
```

It therefore needs no column in `v2` and no importer mapping. It should be a column on the
browse views.

The formula also *depends on* `#` being unique per parent — a tie in `MAX` marks two rows
`Y`. Measured, that mostly holds:

| Sheet | (parent, #) pairs | Duplicated |
|---|---:|---:|
| `4.RNAIllumina` | 321 | **53** |
| `3.DNAExtractions` | 2,223 | 5 |
| `4.ONT` | 97 | 3 |
| `4.HiCLysate` | 386 | 1 |
| `4.HiCLibrary` | 312 | 1 |
| `4.RNAkinnex` | 175 | 1 |
| `3.RNAExtractions`, `4.Illumina`, `4.PacBio` | 2,413 | 0 |

64 rows in total. `unique(parent_id, ext_num)` from `lab_key_strategy.md` §6.3 is enforceable,
but `4.RNAIllumina` needs work first: a sixth of its rows reuse an attempt number, which also
means the workbook's own `Latest` column is wrong for them — `MAX(#)` ties and marks several
rows as latest at once. On a trial import 259 of its 321 rows load and the rest quarantine.

> **Correction, 2026-08-05.** An earlier revision reported 10 duplicates in total, omitting
> `4.RNAIllumina` and `4.RNAkinnex`; the RNA sheets were truncated out of that run's output.

### `Status Overwrite` is a clean `Y` flag that has never been imported

Hand-entered, never mapped, and holding exactly one value:

| Sheet | Header spelling | `Y` |
|---|---|---:|
| `4.HiCLibrary` | `Status Overwrite` | 48 |
| `3.DNAExtractions` | `Status Overwrite` | 36 |
| `4.PacBio` | `Overwrite Status` | 20 |
| `4.Illumina` | `Overwrite Status` | 17 |
| `3.RNAExtractions` | `Overwrite Status` | 7 |
| `4.RNAIllumina` | `Overwrite Status` | 1 |
| `4.ONT` | `Status Overwrite` | 0 (column exists, empty) |
| `4.RNAkinnex` | `Overwrite Status` | 0 (column exists, empty) |
| **Total** | | **129** |

No other value appears anywhere. `summary` already tests `status_overwrite::text = 'Y'`, so
`boolean` is the right type in `v2` and the import needs both header spellings.

> **Correction, 2026-08-05.** An earlier revision of this document reported ~2,054 stray
> numeric values in this column. That was an artefact of the hand-rolled XML reader used for
> the first analysis: it could not match self-closing empty cells (`<c r="Y2" s="2"/>`), so it
> ran on and attributed the *next* cell's contents to the empty column — and because the empty
> cell's attributes carry no `t="s"`, it read the neighbour's shared-string **index** as a
> literal number. Re-derived with openpyxl, the column is clean. The same artefact affected two
> other findings, corrected below.

### `Manual/ Automated Method` — one vocabulary, with a typo on one sheet

Hand-entered on both sheets, two values each, no formulas:

| Sheet | Filled | Values |
|---|---:|---|
| `4.PacBio` | 362 | `Manual` (258), `Automated Biomek i7` (104) |
| `4.Illumina` | 1,723 | `Auomated Biomek i7` (941), `Manual` (782) |

Same vocabulary, but `4.Illumina` spells it **`Auomated`** — missing the `t` — in all 941
rows. A shared lookup table or `check` constraint catches this on the first import; two
independent free-text columns would carry it forward permanently.

### Proximity ligation: the same measurement, recorded in two places over time

| Where | Rows filled | Formula |
|---|---:|---:|
| `4.HiCLysate` → `Proximity Ligation Conc. (ng/uL)` | 80 | 9 |
| `4.HiCLibrary` → `Proximity Ligation Conc. (ng/ul)` | 275, across 251 lysates | 0 |

Joined on `Lysate Tube ID`, where both sheets carry a value they agree **50 times out of 52**.
They are the same measurement.

The split is chronological, not semantic:

| | n | Median prep date |
|---|---:|---|
| Lysate rows *with* prox conc | 83 | 2026-03-31 |
| Lysate rows *without* | 283 | 2024-11-15 |
| Library rows with prox conc | 74 | 2025-05-28 |

The lab moved the record from the library sheet to the lysate sheet. Current practice puts it
on the lysate, which is also where `Proximity Ligation prep date` and the (formula-derived)
`Proximity Ligation yield (ng)` live.

19 lysates have more than one Hi-C library, and **10 of them disagree** on the value — e.g.
`OG767G-1` has `33.3` and `4.36`; `OG1161B-1` has `0.2`, `0.65` and `6.58`. Not rounding
differences. But **none of the 19 — conflicting or agreeing — has a lysate-sheet value**:
every conflict sits in the pre-lysate-column era, and there is no conflict at all among rows
where the lysate column is in use. The disagreements are transcription noise from when the
value was written onto each library row, not evidence of per-library measurement.

Confirming that the value is a lysate attribute: 28 lysates carry a prox conc while no library
of theirs carries one at all — several have no Hi-C library on the sheet whatsoever
(`OG73W-1`, `OG675L-1`, `OG109M-2`). It is recorded before the library exists.

Conclusion: `hic_lysate` is the live home for this measurement;
`hic_library.prox_ligation_conc` is retained as a legacy read-only column holding the 226
historical values that have no lysate-row equivalent and cannot be migrated up while those 10
conflicts stand.

## Intentionally excluded (reviewed, not gaps)

Noted so these aren't re-flagged in a future pass:
- Excel-native scratch columns: bare `Column1`, bare `#` row counters.
- Columns that duplicate identifying info already captured via `sample`/`Summary`: `Project
  ID`, `Nominal Species ID`, `Common Name/s`, `Tissue Box` repeated on several child sheets.

## Next steps (not implemented in this pass)

1. Decide DB types/priorities for the new columns above (compliance fields are likely
   time-sensitive).
2. Fix the three broken mappings in `name_convert.py`/`queries.py` (`OceanOmics-Database`
   repo).
3. Once the `v2_` table scaffold (see `deploy/create_v2_lab_tables.sql`) is agreed, update the
   importer to write into the `v2_` tables, backfill history, and only then plan cutover.
