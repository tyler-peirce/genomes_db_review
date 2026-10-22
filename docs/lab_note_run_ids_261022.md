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

## 3. PacBio run `PACB_250717_AD` (4 rows to correct, 3 to add)

This is a separate Revio run on 17 July 2025. The instrument calls it `PACB_250717_AD`, and its
data is in `s3://ocom.oceangenomes/pacbio/PACB_250717_AD/`. The workbook has no rows for it.
Instead, four of its libraries are recorded as Plate 2 of `PACB_250704_AD`, but 250704 only ran
Plate 1, and none of their reads are in its data.

| Library | Barcode | In 250704's data | In 250717's data | Workbook now | Change |
|---|---|---|---|---|---|
| `OG750G_D_SBL` | bc2073 | no | cell B01 | `PACB_250704_AD`, Plate 2 D01 | run ID to `PACB_250717_AD`, cell B01 |
| `OG819H_D_SBL` | bc2012 | no | cell D01 | `PACB_250704_AD`, Plate 2 C01 | run ID to `PACB_250717_AD`, cell D01 |
| `OG852O_D_SBL` | bc2013 | no | cell D01 | `PACB_250704_AD`, Plate 2 B01 | run ID to `PACB_250717_AD`, cell D01 |
| `OG853O_D_SBL` | bc2014 | no | cell B01 | `PACB_250704_AD`, Plate 2 D01 | run ID to `PACB_250717_AD`, cell B01 |
| `OG716O_D_SBL` | bc2007 | cell D01 | cell A01 | `PACB_250704_AD` only | **add** a `PACB_250717_AD` row, cell A01 |
| `OG756G_D_SBL` | bc2008 | cell C01 | cell C01 | `PACB_250704_AD` only | **add** a `PACB_250717_AD` row, cell C01 |
| `OG804G_D_SBL` | bc2010 | no | cell C01 | no row for either run | **add** a `PACB_250717_AD` row, cell C01 |

OG716 and OG756 really were sequenced on both runs; keep their 250704 rows.

**`pacbio/PACB_250704_AD2/` is a byte-for-byte copy of `pacbio/PACB_250704_AD/`** (254 files,
171 GiB, every hash identical). If nobody needs it, it can be deleted. It also holds two run
set-ups from 4 July with no reads (`r84154_20250704_040418` and `_052951`, transfer tests only).

## 4. One missing library row

- **`OG650L-1_HICL` on `NOVA_240501_LA`.** Reads from this run were submitted to the SRA, but the
  workbook only has this library's iSeq run (`ISEQ_240426_LA`). Please add the NovaSeq row.

(Answered 2026-10-22: sample sheets call a tube's first Hi-C library `HICL1`, the workbook calls it
`HICL`. The database now treats them as the same, so no workbook change is needed.)

Once 1–3 are in, the next nightly import updates the Sequencing table, and the QC results link up
on their own. The SRA submissions are re-linked on the database side afterwards. Questions to Tyler.
