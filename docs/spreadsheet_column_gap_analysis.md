# Spreadsheet → Database Column Gap Analysis

Status: Review complete 2026-08-04. Source spreadsheet:
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

## Likely explains an existing backlog item

`docs/data_dictionary.md`'s Column Classification Backlog already flags `status_overwrite` as
"fully empty but referenced by `summary`" across most lab tables. This review's most likely
explanation: the source columns that should feed it — `Status Overwrite` / `Overwrite Status`
/ `Latest` — exist on nearly every sheet but were never added to `name_convert.py`. Not fixed
here since `summary`'s view logic already reads `status_overwrite`; wiring it up is a
deliberate decision, not a drive-by fix.

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
