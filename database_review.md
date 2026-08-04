# Ocean Genomes Database Review

Review date: 2026-07-07  
Database: PostgreSQL 14, configured application database  
Scope: Schema design, relationship quality, data completeness signals, view design, and improvement planning  
Status: Review only. No database or schema changes were made.

## 1. Executive Summary

The Ocean Genomes database is functional and contains a largely coherent central laboratory workflow, but it has grown organically and now shows several signs of schema drift:

- The live database has outgrown the original setup script.
- The species model is split across two overlapping tables.
- Some important relationships are implied by `og_id` but not enforced.
- Several columns are unused or nearly unused.
- Many date, numeric, and status fields are stored as free text.
- Reporting views contain hidden business logic and repeated correlated lookups.
- Documentation coverage is very low.

The most important recommendation is to first establish a schema baseline and data dictionary before making structural changes. Once the current state is documented, improvement work should proceed in phases: clean existing data, add indexes and constraints safely, normalize status/reference data, then redesign the sequencing and reporting areas.

Related design notes:

- `docs/lab_key_strategy.md`: recommendation for replacing concatenated lab-side primary keys with stable internal keys, unique human-readable identifiers, and browse-friendly views.

## 2. Review Goals

The goal of this review is to identify design and data-quality areas that can be improved so the database becomes:

- Easier to understand.
- More efficient for common reporting and API queries.
- More reliable through better constraints and clearer relationships.
- Tidier by removing or deprecating unused structures.
- Safer to evolve through versioned schema management.

This review intentionally does not apply any changes.

## 3. Methodology

The review used:

- Repository inspection under `goat_v3`.
- Review of the database bootstrap script at `create_database.py`.
- Review of checked-in SQL view definitions under `goat_v3/sql`.
- Review of FastAPI database access and router code under `goat_v3/api/app`.
- Read-only inspection of the live PostgreSQL schema using information schema and PostgreSQL catalog metadata.
- Read-only row-count, sparsity, relationship, and status-value checks.
- Read-only `EXPLAIN` checks for key reporting/API views.

No mutation statements were run against the database.

## 4. Current Architecture Snapshot

### 4.1 Application Layer

The checked-in API is a small FastAPI service. It currently exposes GoaT-facing endpoints:

- `/api/goat/project/`
- `/api/goat/species/`
- `/api/goat/species/count`

The API reads from two database views:

- `goat_project_metadata_v1`
- `goat_species_v1`

The API does not currently model the full operational database. It executes raw SQL strings through SQLAlchemy.

### 4.2 Repository Schema Coverage

The repository contains:

- `create_database.py`, an older database creation script.
- `goat_v3/sql/create_goat_view.sql`.
- `goat_v3/sql/create_project_metadata_view.sql`.

The live database contains many more tables, columns, constraints, and views than are represented by these files. This means the repository is not currently a reliable source of truth for the database.

### 4.3 Live Database Inventory

The live database contains 31 base tables and 11 views in the `public` schema.

Base tables observed:

| Table | Rows | Notes |
|---|---:|---|
| `blast_filtered_lca` | 191,888 | Analysis output. Has orphan `og_id` examples. |
| `design_description` | 2 | Lookup-like table. No FK links. |
| `dna_extraction` | 2,273 | Core lab workflow. FK to `tissue`. |
| `draft_genomes` | 1,448 | Assembly/QC data. No FK to `sample`. |
| `hic_library` | 326 | Core lab workflow. FK to `hic_lysate`. |
| `hic_lysate` | 439 | Core lab workflow. FK to `tissue`. |
| `hic_reads_qc` | 522 | QC data. No FK to `sample`. |
| `hifi_reads_qc` | 248 | QC data. No FK to `sample`. |
| `illumina_library` | 1,724 | Core lab workflow. FK to `dna_extraction`. |
| `lca` | 6,384 | Analysis output. FK to `mitogenome_data`. |
| `lca_old` | 2,895 | Legacy analysis output. |
| `lca_raw_results` | 20,170 | Analysis output. FK to `mitogenome_data`. |
| `lca_validation` | 2,021 | Analysis validation. FK to `mitogenome_data`. |
| `master_species` | 19,817 | Used by GoaT view. Overlaps with `species`. |
| `mitogenome_data` | 2,165 | Parent for LCA tables. |
| `ont_library` | 98 | Core lab workflow. FK to `dna_extraction`. |
| `pacbio_library` | 427 | Core lab workflow. FK to `dna_extraction`. |
| `raw_data` | 8,010 | Raw data inventory. No FK to `sample`. |
| `raw_qc` | 240 | QC data. No FK to `sample`. |
| `ref_genomes` | 1,835 | Reference genome data. No FK to `sample`. |
| `ref_genomes_assembly_uploads` | 54 | Upload tracking. |
| `ref_genomes_sra_uploads` | 153 | FK to `ref_genomes_assembly_uploads`. |
| `rna_extraction` | 262 | Core lab workflow. FK to `tissue`. |
| `rna_library_ilmn` | 271 | Core lab workflow. FK to `rna_extraction`. |
| `rna_library_kinx` | 177 | Core lab workflow, but no FK to `rna_extraction`. |
| `rna_qc_kinnex` | 96 | QC data. Implied links to `rna_library_kinx`. |
| `sample` | 2,675 | Core sample table. |
| `sequencing` | 4,212 | Sequencing events/runs. Polymorphic nullable library links. |
| `species` | 22,650 | Species/reference table. |
| `species_ncbi_assembly` | 0 | New or unused table. |
| `tissue` | 5,393 | Core lab workflow. FK to `sample`. |

Views observed:

| View | Purpose |
|---|---|
| `coverage_summary` | Aggregates HiFi/Hi-C yield and coverage. |
| `embargo_assignment_view` | Sample embargo/assignment reporting. |
| `filtered_lca_view` | Filtered LCA output by sample/region. |
| `goat_project_metadata_v1` | GoaT project metadata API view. |
| `goat_species_v1` | GoaT species API view. |
| `lca_pivot_view` | LCA region pivot. |
| `lca_results_view` | LCA validation helper. |
| `lca_validation_report_view` | Validation reporting. |
| `sample_view` | Sample metadata subset for validated samples. |
| `summary` | Operational workflow summary. |
| `v_genome_size_comparison` | Genome size comparison against NCBI assembly data. |

## 5. Existing Relationship Model

The strongest area of the database is the central sample and wet-lab workflow:

```text
sample
  -> tissue
      -> dna_extraction
          -> illumina_library
          -> pacbio_library
          -> ont_library
      -> rna_extraction
          -> rna_library_ilmn
          -> rna_library_kinx
      -> hic_lysate
          -> hic_library
```

The LCA workflow has a separate enforced chain:

```text
mitogenome_data
  -> lca
  -> lca_old
  -> lca_raw_results
  -> lca_validation
```

Several other tables carry `og_id` and are logically related to `sample`, but the relationship is not enforced:

```text
sample
  -> draft_genomes
  -> ref_genomes
  -> raw_data
  -> raw_qc
  -> hifi_reads_qc
  -> hic_reads_qc
  -> blast_filtered_lca
```

This split between enforced and implied relationships is one of the main design issues.

## 6. Major Findings

### Finding 1: The repository is not the schema source of truth

Severity: High  
Theme: Maintainability, safety

The live schema has many tables, views, and columns not represented in `create_database.py` or the checked-in SQL files.

Examples:

- The setup script defines `Species`, while the live GoaT view reads from `master_species`.
- The setup script does not define many live tables, including `draft_genomes`, `ref_genomes`, `raw_qc`, `mitogenome_data`, and LCA-related tables.
- The setup script does not reflect several live columns, such as `sample.workflow`.
- The setup script contains hardcoded PostgreSQL credentials and host details.

Why this matters:

- Developers cannot reliably recreate the database from source control.
- Schema changes are harder to review.
- Cleanup work risks breaking hidden dependencies.
- Production drift can continue unnoticed.

Recommendation:

Create a formal schema baseline from the live database and move toward migration-based schema management.

Suggested first artifacts:

- `schema/current_schema.sql`
- `schema/current_views.sql`
- `schema/current_indexes.sql`
- `schema/current_constraints.sql`
- `docs/database_review.md`
- `docs/data_dictionary.md`

### Finding 2: Species data has two competing authorities

Severity: High  
Theme: Data integrity, modeling

There are two species tables:

| Table | Rows |
|---|---:|
| `species` | 22,650 |
| `master_species` | 19,817 |

Observed overlap:

| Check | Count |
|---|---:|
| Rows in both tables | 19,817 |
| Rows in `species` but not `master_species` | 2,833 |
| Rows in `master_species` but not `species` | 0 |

The GoaT view uses `master_species`, while `species_ncbi_assembly` references `species`. Samples use text species fields without an enforced FK to either table.

Observed sample species issues:

| Check | Count |
|---|---:|
| `sample.nominal_species_id` blank/null | 33 |
| `sample.nominal_species_id` not in `species` | 645 |
| `sample.nominal_species_id` not in `master_species` | 706 |
| `sample.assigned_species` not in `species` | 25 |
| `sample.assigned_species` not in `master_species` | 25 |

Why this matters:

- Reports may disagree depending on which species table they use.
- GoaT output may omit species that exist in `species` but not `master_species`.
- Sample species names can drift from the reference taxonomy.
- Future constraints cannot be safely added until the authoritative model is chosen.

Recommendation:

Choose one canonical species table and treat the other as either a staging table, derived table, or deprecated table.

Likely target:

- `species` becomes the canonical species/taxonomy table.
- `master_species` is either retired, renamed as a view, or redefined as a curated subset.
- `sample.nominal_species_id` and `sample.assigned_species` are cleaned and then constrained.

### Finding 3: Some logical relationships are not enforced

Severity: High  
Theme: Data integrity

Several tables contain `og_id` but do not have a foreign key to `sample(og_id)`.

Observed orphan-like examples:

| Table | Total rows | Blank `og_id` | `og_id` not in `sample` |
|---|---:|---:|---:|
| `blast_filtered_lca` | 191,888 | 0 | 334 |
| `raw_qc` | 240 | 0 | 3 |
| `ref_genomes` | 1,835 | 0 | 4 |
| `raw_data` | 8,010 | 30 | 0 |
| `sequencing` | 4,212 | 2 | 0 |
| `dna_extraction` | 2,273 | 1 | 0 |

Example invalid `og_id` values found:

- `blast_filtered_lca`: `OG672L-1`, `OG9G-2`, `OG90M-4`, `OG76G-1`, `OG101G-1`, `OG000`
- `raw_qc`: `OG750_PD`, `OG90_bc2008`, `OG90ULI`
- `ref_genomes`: `OG88G`, `OG90_bc2008`

Why this matters:

- Reporting joins can silently drop records.
- Data imports may create identifiers that are not valid samples.
- Users may need to guess whether suffixes like `-1`, `_PD`, or barcode-style IDs are sample IDs, library IDs, or derived analysis IDs.

Recommendation:

Before adding FKs, classify non-sample identifiers:

- True sample IDs that need cleanup.
- Derived specimen/library identifiers that should move to a different column.
- Historical records that should be archived.
- Valid analysis IDs that require a separate entity table.

After cleanup, add staged constraints where appropriate.

### Finding 4: Foreign key columns are mostly not indexed

Severity: Medium to High  
Theme: Performance, operational safety

The database has primary key indexes, but most child-side FK columns do not have supporting indexes.

Observed missing index examples:

- `tissue.og_id`
- `dna_extraction.tissue_id`
- `rna_extraction.tissue_id`
- `hic_lysate.tissue_id`
- `illumina_library.dna_id`
- `pacbio_library.dna_id`
- `ont_library.dna_id`
- `hic_library.lysate_id`
- `rna_library_ilmn.rna_id`
- `sequencing.illumina_library_tube_id`
- `sequencing.pacbio_library_tube_id`
- `sequencing.ont_library_tube_id`
- `sequencing.hic_library_tube_id`
- `ref_genomes_sra_uploads.og_id`

Why this matters:

- Joins can be slower than necessary.
- Deletes or updates on parent tables can be expensive.
- Reporting views that repeatedly scan child tables become slower as data grows.

Recommendation:

Add supporting indexes after confirming common query patterns. These are usually low-risk improvements, but should still be added through migrations and tested.

Candidate indexes:

```sql
CREATE INDEX ON tissue (og_id);
CREATE INDEX ON dna_extraction (tissue_id);
CREATE INDEX ON dna_extraction (og_id);
CREATE INDEX ON rna_extraction (tissue_id);
CREATE INDEX ON rna_extraction (og_id);
CREATE INDEX ON illumina_library (dna_id);
CREATE INDEX ON illumina_library (og_id);
CREATE INDEX ON pacbio_library (dna_id);
CREATE INDEX ON pacbio_library (og_id);
CREATE INDEX ON ont_library (dna_id);
CREATE INDEX ON ont_library (og_id);
CREATE INDEX ON hic_lysate (tissue_id);
CREATE INDEX ON hic_library (lysate_id);
CREATE INDEX ON hic_library (og_id);
CREATE INDEX ON rna_library_ilmn (rna_id);
CREATE INDEX ON rna_library_ilmn (og_id);
CREATE INDEX ON rna_library_kinx (rna_id);
CREATE INDEX ON rna_library_kinx (og_id);
CREATE INDEX ON sequencing (og_id);
```

These are planning suggestions only, not applied changes.

### Finding 5: Sequencing is modeled with polymorphic nullable columns

Severity: High  
Theme: Modeling, query simplicity

The `sequencing` table has separate nullable columns for each library type:

- `rna_library_tube_id`
- `illumina_library_tube_id`
- `ont_library_tube_id`
- `pacbio_library_tube_id`
- `hic_library_tube_id`

Observed link counts:

| Number of linked library columns | Rows |
|---:|---:|
| 0 | 40 |
| 1 | 4,172 |

Technology values:

| Technology | Rows |
|---|---:|
| `Illumina` | 3,149 |
| `Hi-C` | 471 |
| `PacBio HIFI` | 287 |
| `PacBio Kinnex` | 138 |
| `ONT` | 92 |
| blank | 40 |
| `PacBio` | 35 |

Important design issue:

`sequencing` has no FK to `rna_library_kinx`, even though `PacBio Kinnex` appears as a sequencing technology.

Why this matters:

- Every query must handle several nullable columns.
- It is difficult to enforce "exactly one library link".
- Adding a new library type requires a table change.
- Some sequencing rows can exist without a library link.
- Kinnex records are treated inconsistently.

Recommendation:

Move toward one of these designs:

Option A: Unified library table

```text
library
  library_id
  library_type
  source_extraction_id
  source_lysate_id
  status
  method
  date

sequencing
  sequencing_id
  library_id
  run_id
  technology
  instrument
```

Option B: Sequencing run plus run-library junction

```text
sequencing_run
  sequencing_run_id
  run_id
  instrument
  run_date

sequencing_library
  sequencing_run_id
  library_table
  library_id
  technology
```

Option A is tidier long term. Option B may be easier as a transitional model.

### Finding 6: Some columns are unused or nearly unused

Severity: Medium  
Theme: Tidiness, usability

Several columns are completely empty in the live database.

Fully empty examples:

| Table | Column |
|---|---|
| `sample` | `illumina_sequencing` |
| `sample` | `hifi_sequencing` |
| `sample` | `hic_sequencing` |
| `sample` | `nanopore_sequencing` |
| `sample` | `rna_extraction` |
| `sample` | `rna_ilmn_sequencing` |
| `sample` | `rna_kinnex_sequencing` |
| `sample` | `illumina_public` |
| `sample` | `summary_comments` |
| `dna_extraction` | `status_overwrite` |
| `illumina_library` | `status_overwrite` |
| `pacbio_library` | `status_overwrite` |
| `hic_library` | `status_overwrite` |
| `ont_library` | `status_overwrite` |
| `rna_extraction` | `status_overwrite` |
| `rna_library_ilmn` | `status_overwrite` |
| `rna_library_kinx` | `status_overwrite` |
| `species` | `draft_genome_bioproject_id` |
| `master_species` | `draft_genome_bioproject_id` |
| `species_ncbi_assembly` | all table data, because table has 0 rows |

Near-empty examples:

| Table | Column | Filled |
|---|---|---:|
| `sample` | `eschmeyer_id` | 1 / 2,675 |
| `sample` | `ncbi_sample_name` | 5 / 2,675 |
| `sample` | `hifi_public` | 8 / 2,675 |
| `sample` | `ncbi_assembly_upload` | 41 / 2,675 |
| `sample` | `ncbi_bioproject_id_lvl_3_hifi` | 52 / 2,675 |
| `rna_library_kinx` | `comments` | 2 / 177 |

Why this matters:

- Empty fields confuse users and importers.
- Reports may rely on columns that no longer carry data.
- Empty `status_overwrite` columns are still referenced by the `summary` view, creating dead logic.

Recommendation:

Do not drop columns immediately. First assign each sparse column one of these statuses:

- Active but underused.
- Reserved for planned workflow.
- Derived and should become a view field.
- Deprecated and safe to remove later.
- Historical and should be archived.

Then document deprecations and remove only after downstream usage is checked.

### Finding 7: Dates, numbers, and status values are often stored as text

Severity: Medium  
Theme: Data quality, query reliability

Many date-like fields are stored as text:

- `dna_extraction.extraction_date`
- `draft_genomes.seq_date`
- `hic_library.library_date`
- `illumina_library.library_date`
- `lca.seq_date`
- `lca.lca_run_date`
- `mitogenome_data.seq_date`
- `ont_library.library_date`
- `pacbio_library.library_date`
- `ref_genomes.seq_date`
- `rna_library_ilmn.library_date`
- `sequencing.run_date`
- `sequencing.seq_date`
- `species.iucn_dateassessed`

Many numeric-like fields are stored as text:

- `sample.weight`
- `sample.depth_collection`
- `sample.lengthtl_and_lengthfl`
- `sample.ont_num`
- `dna_extraction.av_size`
- `dna_extraction.total_yield`
- `dna_extraction.ratio_260_280`
- `dna_extraction.ratio_260_230`
- `illumina_library.library_qubit_conc`
- `rna_extraction.ratio_260_280`
- `rna_extraction.ratio_260_230`

Status values are also uncontrolled. Examples:

| Field | Distinct values | Notes |
|---|---:|---|
| `sample.rna_status` | 47 | Includes comma-combined statuses. |
| `sample.pb_status` | 19 | Includes combined statuses. |
| `sample.hic_status` | 13 | Includes typos and combined statuses. |
| `sample.ilrna_status` | 10 | Includes repeated comma-combined statuses. |
| `pacbio_library.pacb_status` | 15 | Workflow stages and outcomes mixed. |
| `hic_library.hic_status` | 9 | Includes `State 3`/`Stage 4` inconsistency and typo variants. |

Observed typo examples:

- `Shallow Seqeunce - iSEQ`
- `Library Prep - Ilumina rRNA depletion`
- `Library Prep - Ilumina mRNA`
- `State 3 - Proximity Ligation`
- `Deep sequence - Illumina` vs `Deep Sequence - Illumina`

Why this matters:

- Sorting and filtering dates as text can give incorrect results.
- Numeric calculations require casts and may fail on unexpected values.
- Status rollups become fragile.
- Typos create false categories.

Recommendation:

- Convert date fields to `date` or `timestamp` where possible.
- Convert numeric fields to appropriate numeric types after profiling values.
- Split combined status strings into normalized event/history records where needed.
- Create canonical status lookup tables.

### Finding 8: Reporting views contain hidden business logic and performance risks

Severity: Medium to High  
Theme: Performance, maintainability

The `summary` view performs many correlated subqueries per sample. For example, for each sample it repeatedly looks up latest statuses in extraction and library tables.

The `goat_species_v1` view also performs repeated `EXISTS` checks against `sample` and `ref_genomes` for each species.

Observed `EXPLAIN` signals:

- `goat_species_v1` page query had a very high estimated cost due to correlated subplans and sorting.
- `summary` view showed repeated sequential scans against child tables for each sample.

Why this matters:

- Queries may be acceptable now but degrade as rows grow.
- Business rules live inside views without tests or documentation.
- Optimizing one report may accidentally change API behavior.

Recommendation:

- Preserve current public outputs.
- Rebuild heavy views using pre-aggregated CTEs or materialized views.
- Add supporting indexes.
- Move repeated status logic into documented helper views.
- Add smoke tests for GoaT API view outputs before refactoring.

### Finding 9: Documentation coverage is minimal

Severity: Medium  
Theme: Team knowledge, maintainability

Observed documentation coverage:

| Object type | Documented | Total |
|---|---:|---:|
| Table/view comments | 0 | 42 |
| Column comments | 12 | 934 |

Why this matters:

- New team members must infer meaning from names and reports.
- It is difficult to tell whether sparse columns are intentionally sparse or abandoned.
- Data import and cleanup rules are not explicit.

Recommendation:

Create a data dictionary before major cleanup. Use it to decide what to constrain, archive, rename, or remove.

## 7. Table-by-Table Review Notes

### `sample`

Role: Core biological sample table.

Strengths:

- Central hub for `og_id`.
- Used by operational views and GoaT reporting.
- Has a primary key on `og_id`.

Issues:

- Species links are text and not constrained.
- Many workflow/status columns duplicate information available in child tables.
- Several sequencing-related columns are fully empty.
- Many physical measurement fields are text.

Recommendation:

Keep as the sample hub, but reduce derived workflow/status fields over time. Prefer child tables or views for workflow status.

### `tissue`

Role: Physical tissue inventory under a sample.

Strengths:

- Strong FK to `sample`.
- Good row coverage: 5,393 tissue rows for 2,675 samples.

Issues:

- `og_id` should be indexed.
- Storage location fields may benefit from a structured location model if storage tracking becomes important.

Recommendation:

Keep. Add supporting indexes. Consider future freezer/storage normalization.

### `dna_extraction`

Role: DNA extraction records from tissue.

Strengths:

- FK to `tissue`.
- Strong usage: 2,273 rows.
- `og_id` denormalization currently matches tissue/sample links where present.

Issues:

- One row has blank `tissue_id`.
- Some numeric fields are text.
- `status_overwrite` is empty but used by `summary`.

Recommendation:

Keep. Clean the blank tissue link. Decide whether `og_id` is intentional denormalization or should be derived. Normalize numeric fields and statuses.

### `rna_extraction`

Role: RNA extraction records from tissue.

Strengths:

- FK to `tissue`.
- Status values are relatively controlled compared with sample-level RNA status.

Issues:

- Some storage columns are fully empty.
- Ratio fields are text.
- `status_overwrite` is empty.

Recommendation:

Keep. Normalize numeric fields and review unused storage/status-overwrite columns.

### Library tables

Tables:

- `illumina_library`
- `pacbio_library`
- `ont_library`
- `hic_library`
- `rna_library_ilmn`
- `rna_library_kinx`

Strengths:

- Most have clear parent relationships.
- Denormalized `og_id` values match upstream sample links in tested cases.

Issues:

- Different library tables use different column naming patterns.
- `rna_library_kinx` lacks an FK to `rna_extraction`, although its `rna_id` values currently match.
- `status_overwrite` columns are empty across all library tables.
- Status values need normalization.

Recommendation:

Keep short term. Add missing FK/index support. Long term, consider a unified `library` entity.

### `sequencing`

Role: Sequencing event/run records.

Strengths:

- Contains high-value run metadata.
- Most rows link to one library.

Issues:

- Polymorphic nullable library links.
- 40 rows have no library link.
- No `rna_library_kinx` link despite Kinnex sequencing records.
- `run_date` and `seq_date` are text.

Recommendation:

Redesign as a run plus library association model, or introduce a unified library ID.

### `species` and `master_species`

Role: Taxonomy/reference species data.

Strengths:

- Broad coverage.
- All `master_species` rows exist in `species`.

Issues:

- Two authorities create ambiguity.
- GoaT view and assembly table use different species sources.
- Sparse internal/project fields are duplicated across both.

Recommendation:

Select one canonical table. Convert the other to a curated subset view or retire it.

### `species_ncbi_assembly`

Role: NCBI assembly metadata for species.

Strengths:

- Good table design: PK, FK to species, chosen-assembly partial unique index.

Issues:

- 0 rows.

Recommendation:

Keep if NCBI assembly import is planned. Otherwise mark as planned/inactive in the data dictionary.

### `draft_genomes`, `ref_genomes`, and upload tables

Role: Assembly and reference genome tracking.

Strengths:

- High-value downstream project data.
- `ref_genomes_sra_uploads` links to `ref_genomes_assembly_uploads`.

Issues:

- No FK from `draft_genomes.og_id` or `ref_genomes.og_id` to `sample`.
- Some orphan `og_id` values exist in `ref_genomes`.
- `draft_genomes` is very wide, mixing raw read metrics, assembly metrics, BUSCO-like metrics, AWS paths, SRA metadata, and review fields.

Recommendation:

Keep, but consider splitting `draft_genomes` into thematic tables over time:

- sequencing/read metrics
- assembly metrics
- BUSCO/completeness metrics
- file locations
- public submission metadata

### LCA tables

Tables:

- `mitogenome_data`
- `lca`
- `lca_old`
- `lca_raw_results`
- `lca_validation`
- `blast_filtered_lca`

Strengths:

- `lca`, `lca_raw_results`, and `lca_validation` have composite links to `mitogenome_data`.
- LCA reporting views are useful and structured.

Issues:

- `lca_old` appears legacy and contains many empty columns.
- `blast_filtered_lca` has invalid `og_id` examples relative to `sample`.
- Some date fields are text.

Recommendation:

Keep active LCA tables. Mark `lca_old` as legacy/archive if no longer used. Clarify whether `blast_filtered_lca.og_id` should always be a sample ID.

### QC and raw data tables

Tables:

- `raw_data`
- `raw_qc`
- `hifi_reads_qc`
- `hic_reads_qc`
- `rna_qc_kinnex`

Strengths:

- Capture useful technical QC metrics.
- `rna_qc_kinnex` tube IDs currently match `rna_library_kinx`.

Issues:

- Most QC tables have no formal link to `sample` or library tables.
- `raw_qc` has invalid `og_id` examples.
- `raw_data` has blank `og_id` rows.

Recommendation:

Clarify whether QC records belong to samples, libraries, runs, lanes, or files. Add relationships at the correct level rather than forcing everything through `sample`.

## 8. Recommended Target Principles

The database should move toward these principles:

1. `sample` is the authoritative biological sample entity.
2. `species` is the authoritative taxonomy/species entity.
3. Tissue, extraction, library, sequencing, QC, and analysis records each have explicit parent links.
4. Status values are constrained and documented.
5. Derived status fields live in views, not duplicated free-text columns.
6. Dates and numbers use date/numeric types.
7. Import/staging data is separated from curated production tables.
8. Views are versioned and tested when used by APIs.
9. Schema changes are managed through migrations.
10. Deprecated columns and tables are documented before removal.

## 9. Phased Improvement Plan

### Phase 0: Freeze and baseline

Goal: Make the current database reproducible and reviewable.

Actions:

- Export current schema, views, indexes, and constraints.
- Store schema artifacts in the repo.
- Create migration tooling or a repeatable migration convention.
- Remove hardcoded credentials from setup scripts.
- Document which scripts are historical versus active.
- Add a database review checklist for future changes.

Deliverables:

- Baseline schema files.
- Migration folder.
- Initial data dictionary skeleton.
- Owner list for each table.

### Phase 1: Data dictionary and ownership

Goal: Decide what each table and column is for.

Actions:

- For every table, define purpose, owner, source, and lifecycle.
- For every column, define type, meaning, requiredness, and active/deprecated status.
- Identify derived columns and report-only columns.
- Identify staging/import-only tables.
- Add table and column comments for active entities.

Deliverables:

- `docs/data_dictionary.md`.
- Active/deprecated/planned classification.
- Glossary of statuses and workflow terms.

### Phase 2: Data quality cleanup

Goal: Clean data before adding stronger constraints.

Actions:

- Resolve blank and invalid `sample.nominal_species_id`.
- Resolve invalid `sample.assigned_species`.
- Classify orphan `og_id` values in analysis/QC tables.
- Fix or classify sequencing rows with no library link.
- Standardize obvious status typos.
- Decide what to do with empty `status_overwrite` columns.
- Decide whether `lca_old` is active or archival.

Deliverables:

- Data cleanup backlog.
- Approved mapping tables for renamed statuses/species IDs.
- Data-quality dashboard queries.

### Phase 3: Low-risk performance improvements

Goal: Improve query performance without changing behavior.

Actions:

- Add indexes for child-side FK columns.
- Add indexes for common `og_id` lookup columns.
- Add indexes supporting GoaT and summary view filters.
- Test current API endpoints before and after.

Deliverables:

- Index migration.
- Before/after `EXPLAIN` snapshots.
- API smoke-test results.

### Phase 4: Safe constraints

Goal: Protect important relationships after data cleanup.

Actions:

- Add missing FKs using staged validation where needed.
- Add check constraints for "exactly one library link" if retaining current sequencing design temporarily.
- Add uniqueness constraints where natural duplicates are invalid.
- Add not-null constraints only after confirming import flows.

Candidate future constraints:

- `sample.nominal_species_id -> species(species)` or chosen canonical species source.
- `sample.assigned_species -> species(species)`, if expected to be canonical.
- `draft_genomes.og_id -> sample(og_id)`, if all rows should be sample-level.
- `ref_genomes.og_id -> sample(og_id)`, after derived IDs are resolved.
- `raw_qc.og_id -> sample(og_id)`, if sample-level.
- `rna_library_kinx.rna_id -> rna_extraction(rna_id)`.
- `rna_qc_kinnex.rna_tube_id -> rna_library_kinx(rna_library_tube_id)`.

Deliverables:

- Constraint migration plan.
- Validation reports.
- Import/update process updates.

### Phase 5: Normalize status and workflow data

Goal: Make workflow reporting consistent.

Actions:

- Create status lookup tables or PostgreSQL enum/domain strategy.
- Separate workflow stage from outcome.
- Replace combined comma-separated statuses with event/history rows.
- Standardize spelling and capitalization.
- Update views to use canonical status codes and display labels.

Possible status model:

```text
workflow_status
  status_code
  display_label
  workflow_area
  status_type
  sort_order
  is_terminal
  is_active
```

Deliverables:

- Status dictionary.
- Status migration mappings.
- Updated summary/reporting views.

### Phase 6: Sequencing and library redesign

Goal: Remove polymorphic nullable links and simplify future extension.

Actions:

- Design a unified library model or sequencing-library junction.
- Include Kinnex consistently.
- Preserve old table outputs through compatibility views during transition.
- Backfill new structures from existing library/sequencing tables.
- Update reporting views to use the new model.

Deliverables:

- New sequencing/library model.
- Backfill scripts.
- Compatibility views.
- Deprecated columns/tables list.

### Phase 7: Reporting view refactor

Goal: Make reporting and API views easier to maintain and faster.

Actions:

- Refactor `summary` into pre-aggregated helper views.
- Refactor GoaT species status logic to use indexed joins or materialized helper tables.
- Add view-level regression tests.
- Version public views when output contracts change.

Deliverables:

- Refactored views.
- Performance comparison.
- API output regression checks.

## 10. Suggested Priority Backlog

### Highest priority

1. Create a live schema baseline in source control.
2. Build the first data dictionary.
3. Decide whether `species` or `master_species` is canonical.
4. Clean sample species IDs.
5. Add missing indexes for major FK and `og_id` lookup columns.
6. Document and classify empty/deprecated columns.

### Medium priority

1. Normalize statuses.
2. Add staged FKs to sample-level data tables.
3. Refactor the `summary` view.
4. Refactor the GoaT species view for performance.
5. Add FK from `rna_library_kinx.rna_id` to `rna_extraction`.
6. Clarify ownership of QC tables.

### Lower priority

1. Split very wide tables such as `draft_genomes`.
2. Archive or remove `lca_old`.
3. Convert historical date/text fields.
4. Introduce a unified library model.
5. Add full database comments.

## 11. Open Questions

These decisions should be answered before structural changes:

1. Which table is the authoritative species source: `species` or `master_species`?
2. Are IDs such as `OG672L-1`, `OG90_bc2008`, and `OG750_PD` invalid sample IDs, derived library IDs, or valid analysis identifiers?
3. Are sample-level workflow status columns intended to be user-entered, imported, or derived?
4. Should `status_overwrite` still exist if it is currently empty but referenced by `summary`?
5. Is `lca_old` still used by any reports or users?
6. Should `species_ncbi_assembly` be populated soon, or marked as planned/inactive?
7. Are QC records conceptually linked to samples, libraries, sequencing runs, lanes, or files?
8. Does each `sequencing` row represent a run, a library on a run, a lane, or an output file?
9. What are the required public contracts for GoaT API output?
10. Which downstream users or scripts query the database directly outside this repo?

## 12. Risk Assessment

### If no action is taken

- Schema drift will continue.
- New reports may rely on inconsistent species or status fields.
- Performance issues may worsen as data grows.
- Cleanup will become riskier because hidden dependencies will accumulate.
- The database will remain difficult to recreate or test.

### If cleanup is done too quickly

- Reports may break if sparse columns are dropped without usage checks.
- Historical analysis IDs may be incorrectly deleted or overwritten.
- Constraints may fail if data quality issues are not resolved first.
- API output may change unexpectedly.

### Safest approach

Use a staged approach:

1. Document.
2. Baseline.
3. Profile.
4. Clean data.
5. Add indexes.
6. Add constraints.
7. Refactor structures.

## 13. Proposed Success Criteria

The database improvement project should be considered successful when:

- The schema can be recreated from source-controlled migrations.
- Every active table has an owner and documented purpose.
- Every active column is documented or intentionally self-evident.
- There is one canonical species source.
- Sample species links are valid and constrained.
- Core child tables have indexed FK columns.
- Major `og_id`-based tables either have FKs or documented reasons not to.
- Workflow statuses use canonical values.
- Heavy views have acceptable query plans.
- Deprecated tables/columns are clearly marked and eventually removed.

## Appendix A: Key Evidence Summary

### Object counts

| Object type | Count |
|---|---:|
| Base tables | 31 |
| Views | 11 |
| Tables/views with database comments | 0 / 42 |
| Columns with database comments | 12 / 934 |

### Core sample coverage

| Metric | Count |
|---|---:|
| Samples total | 2,675 |
| Samples with tissue | 2,653 |
| Samples without tissue | 22 |
| Samples with DNA extraction | 1,931 |
| Samples with RNA extraction | 110 |
| Samples with Illumina library | 1,565 |
| Samples with PacBio library | 319 |
| Samples with Hi-C library | 205 |
| Samples with ONT library | 70 |
| Samples with RNA Illumina library | 87 |
| Samples with RNA Kinnex library | 98 |
| Samples with sequencing | 1,717 |
| Samples with LCA validation | 1,470 |
| Samples with draft genome | 1,418 |
| Samples with reference genome | 236 |

### Sequencing link distribution

| Linked library columns per sequencing row | Rows |
|---:|---:|
| 0 | 40 |
| 1 | 4,172 |

### Selected sparse columns

| Column | Filled |
|---|---:|
| `sample.illumina_sequencing` | 0 / 2,675 |
| `sample.hifi_sequencing` | 0 / 2,675 |
| `sample.hic_sequencing` | 0 / 2,675 |
| `sample.nanopore_sequencing` | 0 / 2,675 |
| `sample.rna_extraction` | 0 / 2,675 |
| `sample.rna_ilmn_sequencing` | 0 / 2,675 |
| `sample.rna_kinnex_sequencing` | 0 / 2,675 |
| `sample.summary_comments` | 0 / 2,675 |
| `dna_extraction.status_overwrite` | 0 / 2,273 |
| `illumina_library.status_overwrite` | 0 / 1,724 |
| `pacbio_library.status_overwrite` | 0 / 427 |
| `hic_library.status_overwrite` | 0 / 326 |
| `ont_library.status_overwrite` | 0 / 98 |
| `rna_library_kinx.status_overwrite` | 0 / 177 |

## Appendix B: Suggested Review Workshops

### Workshop 1: Species and sample identity

Purpose:

- Decide canonical species source.
- Decide how to handle invalid/missing sample species IDs.
- Define sample ID rules.

Participants:

- Database owner.
- Taxonomy/species data owner.
- Sample intake owner.
- Reporting/API owner.

Outputs:

- Species source decision.
- Species cleanup mapping.
- Sample ID validation rules.

### Workshop 2: Lab workflow model

Purpose:

- Clarify extraction, library, and sequencing relationships.
- Decide whether sample-level workflow fields are derived or manually managed.
- Discuss Kinnex sequencing representation.

Outputs:

- Current-state workflow diagram.
- Target-state workflow diagram.
- Sequencing redesign decision.

### Workshop 3: Reporting and public API

Purpose:

- Identify required API contracts.
- Review GoaT view logic.
- Review `summary` view requirements.

Outputs:

- View contract documentation.
- Test cases for report/API outputs.
- View refactor priorities.

## Appendix C: Example Data Dictionary Template

| Field | Description |
|---|---|
| Table name | Name of table or view. |
| Owner | Team/person responsible. |
| Purpose | Why the object exists. |
| Source | Manual entry, import, derived, external feed, or view. |
| Grain | One row represents what. |
| Primary key | Current or intended key. |
| Parent entity | Sample, tissue, extraction, library, run, species, etc. |
| Active status | Active, planned, deprecated, archive, staging. |
| Sensitive data | Yes/no and notes. |
| Main consumers | Reports, API, scripts, users. |
| Data quality checks | Required validation checks. |
| Notes | Design notes or known issues. |

Column-level template:

| Field | Description |
|---|---|
| Column name | Current column name. |
| Meaning | Business meaning. |
| Data type | Current and target type. |
| Required | Yes/no/conditional. |
| Valid values | Lookup table, enum, or free text. |
| Source | Manual, import, derived. |
| Example | Valid example value. |
| Cleanup required | Yes/no and notes. |
| Deprecation status | Active, deprecated, planned. |
