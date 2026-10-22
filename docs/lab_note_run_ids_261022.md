# Workbook fixes: three sequencing runs and two libraries (2026-10-22)

For: whoever maintains the Sequencing sheet of the OceanGenomes workbook.

The database links each submitted read file, and each read-QC result, to its row on the Sequencing
sheet. These rows don't match the raw data, so 13 SRA submissions and 29 QC results can't be
linked. Each fix is a cell edit in the workbook; the nightly import carries it into the database.

## 1. `NOVA_240718_AD` should be `NOVA_240719_AD` (5 rows)

The raw-data folder (`illumina-hic/NOVA_240719_AD/`) and the Hi-C QC both say 240719. The
workbook has 240718 for exactly the same five libraries:

`OG8G-1_HICL`, `OG105G-2_HICL`, `OG759G-1_HICL`, `OG777G-1_HICL`, `OG820G-1_HICL2`

Please check the run sheet and correct the run ID on these five rows.

## 2. `PACB_250114_AD` should be `NOVA_250114_AD` (6 rows)

These are Hi-C libraries, sequenced on the NovaSeq, but the workbook gives them a PacBio run ID.
The raw data is in `illumina-hic/NOVA_250114_AD/`:

`OG665L-1_HICL`, `OG673L-1_HICL`, `OG676G-1_HICL`, `OG678G-1_HICL`, `OG683L-1_HICL`, `OG702G-1_HICL`

## 3. PacBio run `PACB_250717_AD` is missing (7 rows to add)

The run's raw data is in `pacbio/PACB_250717_AD/` and its HiFi QC exists, but the workbook has
no rows for it. Libraries and barcodes from the QC:

| Library | Barcode |
|---|---|
| `OG716O_D_SBL` | bc2007 |
| `OG750G_D_SBL` | bc2073 |
| `OG756G_D_SBL` | bc2008 |
| `OG804G_D_SBL` | bc2010 |
| `OG819H_D_SBL` | bc2012 |
| `OG852O_D_SBL` | bc2013 |
| `OG853O_D_SBL` | bc2014 |

Several of these were also sequenced on `PACB_250704_AD`; this is a second run, not a duplicate.

## 4. Two library questions

- **`OG650L-1_HICL` on `NOVA_240501_LA`.** Reads from this run were submitted to the SRA, but the
  workbook only has this library's iSeq run (`ISEQ_240426_LA`). Please add the NovaSeq row.
- **OG706's `HICL1` files.** The submitted files are named `OG706L-7_HICL1_…` and `OG706L-8_HICL1_…`,
  but the workbook records `OG706L-7_HICL`, `_HICL2`, `OG706L-8_HICL` and `_HICL2`. Which library is
  `HICL1`?

Once 1–3 are in, the next nightly import updates the Sequencing table, and the QC results link up
on their own. The SRA submissions are re-linked on the database side afterwards. Questions to Tyler.
