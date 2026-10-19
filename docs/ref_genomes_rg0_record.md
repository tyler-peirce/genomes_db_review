# Phase RG, RG.0 record: measurements and triage

Measured 2026-10-19 between 04:06 and 04:30 UTC, read-only on live
(`PGOPTIONS="-c default_transaction_read_only=on"`). Runbook:
[`ref_genomes_runbook_rg0_rg5.md`](ref_genomes_runbook_rg0_rg5.md) RG.0. The queries are in
[`../archive/rg0_measure_261019.sql`](../archive/rg0_measure_261019.sql). Each section names the
query block (A–S) it comes from.

**Status: done 2026-10-19.** Measurements, desk checks and owner triage are complete. The RG.0
gate is met (§4).

## 1. Measurements

### 1.1 Counts (A, B, D)

| Object | Rows |
|---|---:|
| `ref_genomes` | 2,036: 251 OGs, 473 assemblies `(og_id, seq_date, version)`, 2,036 parts |
| `raw_qc` | 252 |
| `hifi_reads_qc` | 277 |
| `hic_reads_qc` | 552 |
| `ref_genomes_assembly_uploads` | 88 |
| `ref_genomes_sra_uploads` | 304 |

- `ref_genomes` non-key cells: **70,741 NULL of 107,908 (66%)**.
- 26 distinct fill patterns.

### 1.2 Rows per tool: the v4 tool-table counts before triage (C, E)

| v4 table | Rows | Notes |
|---|---:|---|
| `ref_gfastats` | 1,298 | `num_gaps` is filled on 295 of them and never without gfastats |
| `ref_busco` | 785 | |
| `ref_merqury_qv` | 974 | |
| `ref_merqury_completeness` | 881 | **`k_mer_set` is NULL on every row**, and no writer sets it |
| `ref_omnic` | 581 | |
| `ref_seqkit_stats` | 300 | `format` is always `FASTA` and `type` always `DNA` |
| `ref_chromosome_stats` | 300 | |
| (none) | 0 | **`hap2_chr_level_max_len`: 0 values, no writer** |
| (no tool at all) | 1 | OG763 251117 hifi1 stage 1 `dual` |

By haplotype:
- `dual` (454 rows) carries only Merqury QV (334), Merqury completeness (301) and OMNIC (117).
- `p_ctg`/`a_ctg` (486) carry only gfastats.

**Decision (no owner input needed):**
- `k_mer_set` and `hap2_chr_level_max_len` are not carried as table columns. The
  `v4.ref_genomes` compatibility view shows them as typed NULLs.
- `format`/`type` are kept, because the post-curation writer sets them.

### 1.3 Key domains (F)

- `stage`: 0 (592), 1 (512), 2 (473), 3 (459).
- `haplotype`: hap1 548, hap2 548, dual 454, a_ctg 245, p_ctg 241.
- `version`: hic1 947, hifi1 845, hic2 227, ont1 8, hic3 3; **`231027` 3, `hi1` 3**.
- `seq_date` not six digits: **`bc2008` 6 rows** (OG90), **`''` 2 rows** (OG906).

### 1.4 Oddities, in detail (G, H, I, J)

| Rows | Key | Tools | Context |
|---|---|---|---|
| 3 | OG108 231027 `231027` stage 1 dual/hap1/hap2 | Merqury QV | OG108 231027 also has `hic1` (stages 2, 3) and `hifi1` (stage 0). Neither has stage 1 |
| 3 | OG820 240501 `hi1` stage 1 dual/hap1/hap2 | Merqury QV and completeness | OG820 240501 `hic1` has stage 2 only |
| 2 | OG906 `''` hic1 stage 2 hap1/hap2 | gfastats, BUSCO | OG906's only other assembly is `250212 hifi1` (stage 0) |
| 6 | OG90 `bc2008` hic1 stage 2 and hifi1 stage 1 | gfastats/BUSCO/OMNIC; Merqury | OG90 240821 hic1 and hifi1 exist separately |
| 2 | **orphan** OG90_bc2008 240821 hifi1 stage 0 a_ctg/p_ctg | gfastats | **Collides with** OG90 240821 hifi1 stage 0 a_ctg/p_ctg: it cannot be remapped to OG90 |
| 2 | **orphan** OG88G 230728 hifi1 stage 1 hap1/hap2 | Merqury completeness | OG88 230728 has hic1 only, so no collision |
| 1 | OG763 251117 hifi1 stage 1 dual | none | all-empty row |
| 140 | hifi1 stage 1 hap1/hap2 on **70 assemblies** | OMNIC (plus Merqury, and BUSCO on some) | Every one of the 70 OGs has a `hic*` assembly on the same or the next date |

`raw_qc`:

| `og_id` | Content | Parent OG has `raw_qc` |
|---|---|---|
| OG750_PD (orphan) | `contam_reads = 0` only | yes |
| OG90_bc2008 (orphan) | `contam_reads = 0` only | yes |
| OG90ULI (orphan) | full GenomeScope | yes |
| OG760 | **every value NULL** | n/a |

### 1.5 Run links (K, L)

Matching on `(og_id, seq_date)` against PacBio HiFi/PacBio/ONT rows in `v_sequencing_browse`.
Kinnex is excluded: its RNA libraries are `rna_kinx`.

| Strategy | Assemblies | 1 run row | >1 run rows | none |
|---|---:|---:|---:|---:|
| hic | 187 | 151 | 10 | 26 |
| hifi | 283 | 233 | 13 | 37 |
| ont | 1 | 0 | 0 | 1 |
| oddballs | 2 | 2 | 0 | 0 |
| **all** | **473** | **386** | **23** | **64** |

- **More than one match:** several SMRT cells or libraries on the same date (OG1161 D4/D5,
  OG2105 SBL/SBL2, …). The assembly was built from all of them, so all are linked.
- **No match:** mostly an assembly `seq_date` a day or more after the run, e.g. OG113 231028
  against `PACB_231027`, OG12 230516 against `PACB_230512`, OG16 240417 against `PACB_240427`.
  - 7 HiFi assemblies dated 230915 or 250717 point at runs months away. That is a batch date,
    not a run date.
  - OG763 has ONT rows only.

**Decision:**
- Link exact matches only.
- The 64 stay unlinked and are listed by `v4.v_ref_assembly_run_readiness`.
- Writers link explicitly from the samplesheet's read directories from RG.4 onwards.
- No fuzzy date matching: a wrong link is worse than none.

### 1.6 `*_size_mb` columns (M)

| Column | Rows that differ from `round(bp/1e6, 2)` |
|---|---:|
| `contig_n50_size_mb` | 0 of 1,277 |
| `scaffold_n50_size_mb` | 2 |
| `largest_scaffold_size_mb` | 9 |
| `total_scaffold_length_size_mb` | 42 |
| `_size_mb` = 0.00 with the bp column NULL | 21 (hifi1 stage 0, OG1, OG2, …) |

The differences are the tool's own rounding from 3 decimals: 607,024,909 bp → `607.025` →
stored as 607.03.

**Decision:** the `_size_mb` columns stay stored, not generated, so the compatibility view
reproduces them exactly.

### 1.7 `raw_qc` split (N)

- 249 rows have GenomeScope values → `ref_genomescope`.
- 145 rows have `contam_reads` → `ref_hifi_adapter_filter`.
- 1 row is empty (OG760).

### 1.8 Read QC → `sequencing` (O, P)

**`hifi_reads_qc`** (277 rows):
- The tube rebuilds as `og_id||tissue||'_'||ext_type||'_'||lib_code` and exists in `library` on
  273 rows.
- `(tube, run)` gives exactly one `sequencing` row on **262**, and more than one on 0.
- 7 rows are on `PACB_250717_AD`, a run absent from `sequencing` (as R.0 found).
- 0 orphans.

**`hic_reads_qc`** (552 rows), against a Hi-C row of the same OG and tissue on the same run:
- exactly one on **475**;
- more than one on **51** (HICL and HICL2 on one run; `lib_code` cannot tell them apart);
- 22 rows on runs absent from `sequencing` (`NOVA_240719_AD`, `NOVA_250114_AD`, as R.0 found);
- 26 blank `lane`, 8 blank `ext_type`/`lib_code`, 0 blank `run_id`, 0 orphans.

**Decision:** `sequencing_id` is set only where exactly one row matches: 262 HiFi, 475 Hi-C. The
rest stay NULL and are listed by the readiness view.

### 1.9 Uploads (Q)

**`ref_genomes_sra_uploads.ncbi_status`:**
- `Released` 116, `ToBeReleased` 48, NULL 8;
- **a date on 132 rows**: 2026-09-03 to 2026-10-01, seven distinct dates.

`data_type`: hic 152, hifi 102, ont 26, illumina 15, NULL 9. 0 orphans.

**`ref_genomes_assembly_uploads`** (88 rows):
- hap1 and hap2 columns fill together: bioproject 87/87, assembly accession 78/78, GCA 74/74.
  1 row has neither haplotype.
- `embargo_status`: Release 76, Embargo 12.
- OGs with exactly one curated (stage-3) assembly: **84**. More than one: 3. None: 1. That is
  how many `ref_submission.assembly_id` links can be set.

### 1.10 Readers and grants (R, S)

- **Views:** `public.coverage_summary` (`raw_qc`, `hifi_reads_qc`, `hic_reads_qc`),
  `public.goat_species_v1` (`ref_genomes`), `v3.v_sequencing_run_fk_readiness` (both read-QC
  tables), and `pre_v2_archive.goat_species_v1_pre_v2` (archive; ignored).
- **Functions:** `build_hicpost_samplesheet_rows`, `build_final_data_compile`,
  `build_nfcore_samplesheet_rows`, `build_postcuration_samplesheet_rows`. All four are
  `LANGUAGE sql` with no `proconfig`, so they resolve table names through the caller's
  `search_path`. Confirmed: no copies are needed for the RG.5 reader test.
- **Grants:**
  - `readonly`: `SELECT` on all six tables;
  - `oceangenom_web`: `SELECT` on **`ref_genomes` and `ref_genomes_assembly_uploads`**. The
    second was not in the runbook.

## 2. Desk checks

| Check | Result |
|---|---|
| Writer of `hic_reads_qc` | **None found.** Grepped every repo under `~` for the table and for its BaseSpace-style columns (`totalreadspf`, `isfiledeleted`). The postgres logs are not readable by `tyler` |
| Writer of the two upload tables | **None found** in any repo |
| `stage3_backfill_push.py` | One-off: a hard-coded list of 13 OGs. Not changed in RG.4 |
| `OceanOmics-Database/SS/ref_genomes_table/*` | Last commit 2026-01-20; the same scripts as the ref repo's `03_compile_results`, before samplesheet versioning. Treated as retired. Its compiled TSVs (OG762 hic1 241019, stages 0 and 2) are the RG.5 fixtures |
| Pawsey, for RG.5 inputs | **Unreachable** (`setonix-08` SSH timed out), as in R.0. RG.5 uses the local fixtures, plus stage-3 TSVs rebuilt from one curated OG's live values |
| Stage meanings, from file names in the ref repo | 0 `.0.hifiasm`, 1 `.1.yahs` / `.1.salsa` / `.1.hifiasm`, 2 `.2.tiara` / `.2.yahs`, 3 `.3.curated` |

## 3. Triage decisions (owner, 2026-10-19)

`public` is not changed by any of these. "Map" means a row in `v4.ref_key_map`; "exclude"
means a row in `v4.ref_excluded_rows`. Excluded rows stay in `public` until RG.6 archives them.

**`ref_genomes`:**

| Rows | Key | Decision |
|---|---|---|
| 3 | OG820 240501 `hi1` | **Map** → OG820 240501 `hic1` |
| 2 | OG906 `''` hic1 | **Map** → OG906 250212 hic1 |
| 2 | OG88G 230728 hifi1 | **Map** → OG88 230728 hifi1 |
| 3 | OG108 231027 `231027` | **Exclude** (assembly unclear) |
| 6 | OG90 `bc2008` hic1/hifi1 | **Exclude** (barcode variant) |
| 2 | OG90_bc2008 240821 hifi1 | **Exclude** (same variant; collides with OG90 240821) |
| 1 | OG763 251117 hifi1 stage 1 dual | **Exclude** (empty) |
| 140 | hifi1 stage 1 hap1/hap2 with OMNIC | **Keep as is:** a real step (Hi-C mapped to the HiFi-only haplotypes before scaffolding) |

**`raw_qc`:**

| `og_id` | Decision |
|---|---|
| OG90_bc2008 | **Exclude** (owner decision, with the OG90 variant) |
| OG750_PD, OG90ULI | **Exclude.** Same rule: their `og_id` is not in `sample`, so the v4 FK cannot hold them, and the parent OG has its own row. This was not put to the owner separately; raise it if it is wrong |
| OG760 | **Exclude** (empty) |

**Open questions, carried to RG.6, none blocking `057`–`059`:**

| Item | Answer | Effect |
|---|---|---|
| Writer of `hic_reads_qc` | "Another repo, not sure which" | Synced as is. Its writer changes once the repo is found |
| Writer of the upload tables | "Another repo" (not named) | Synced as is, likewise |
| Meaning of the date in `ncbi_status` | Unknown | v4 splits it into `ncbi_status` (`Released`/`ToBeReleased`) and a neutral **`status_date`**. The compatibility view recombines them exactly |
| OceanGenom_Web queries | Not available now | Recorded as unchecked in RG.5. **Checking them is a condition of the RG.6 gate.** The role's grants are mirrored in `v4` (`ref_genomes`, `ref_genomes_assembly_uploads`) |

## 4. Figures `057`–`059` will assert

Measured with the triage applied (archive `rg0_measure_261019.sql`, post-triage block), live at
2026-10-19 04:30 UTC. The migrations re-measure them at apply time. Any change since must be
explained by pipeline writes, and be re-recorded here before applying.

**`057`:**

| Item | Value |
|---|---:|
| Rows excluded from `ref_genomes` | 12 |
| `ref_assembly` | 468 (249 OGs) |
| `ref_assembly_part` | 2,024 |
| `ref_gfastats` | 1,294 |
| `ref_busco` | 781 |
| `ref_merqury_qv` | 968 |
| `ref_merqury_completeness` | 878 |
| `ref_omnic` | 576 |
| `ref_seqkit_stats` | 300 |
| `ref_chromosome_stats` | 300 |
| Parts with no tool row | 0 |
| Orphan `og_id`, bad keys, duplicate parts | 0, 0, 0 |
| Assemblies with a run link / link rows | 407 / 434 (61 assemblies unlinked) |

**`058`:**

| Item | Value |
|---|---:|
| `ref_genomescope` | 248 |
| `ref_hifi_adapter_filter` | 143 |
| `hifi_read_qc` | 277, with `sequencing_id` set on 262 |
| `hic_read_qc` | 552, with `sequencing_id` set on 475 |

**`059`:**

| Item | Value |
|---|---:|
| `ref_submission` | 88, with `assembly_id` set on 84 |
| `ref_submission_haplotype` | 174 (87 × 2) |
| `ref_sra_upload` | 304: status 164, `status_date` 132, neither 8 |

**Gate: met.** Every number is recorded and every triage row has a decision.
