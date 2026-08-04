# Ocean Genomes Data Dictionary

Status: Draft skeleton generated from `database_review.md` on 2026-07-07.

This document is the working inventory for table purpose, ownership, lifecycle, and column-level cleanup decisions. Update it before structural migrations are applied.

## Generated Live Inventories

These files are generated from the live PostgreSQL database and should be refreshed when the schema changes:

- `docs/live_object_inventory.md`: tables/views, exact base-table row counts, column counts, and database comments.
- `docs/live_column_inventory.md`: column-level types, nullability, defaults, PK/FK/index signals, and comments.
- `docs/live_relationship_index_review.md`: foreign keys, missing child-side FK index candidates, and existing indexes.

See also `docs/spreadsheet_column_gap_analysis.md` for a review of spreadsheet columns the
nightly `import_data.py` import currently drops on the floor — including the likely root
cause of the `status_overwrite` backlog item below.


## Object Inventory

| Object | Type | Purpose | Grain | Owner | Source | Lifecycle | Priority Notes |
|---|---|---|---|---|---|---|---|
| `sample` | Table | Core biological sample entity. | One row per `og_id`. | TBD | Sample intake/import | Active | Decide canonical species links and derived workflow columns. |
| `tissue` | Table | Physical tissue inventory for samples. | One row per tissue record. | TBD | Lab workflow | Active | Add/support index on `og_id`; clarify storage model later. |
| `dna_extraction` | Table | DNA extraction records from tissue. | One row per DNA extraction. | TBD | Lab workflow | Active | Clean blank `tissue_id`; normalize numeric/date/status fields. |
| `rna_extraction` | Table | RNA extraction records from tissue. | One row per RNA extraction. | TBD | Lab workflow | Active | Review empty storage/status overwrite columns. |
| `illumina_library` | Table | Illumina library prep records. | One row per library tube. | TBD | Lab workflow | Active | Add FK/index support and normalize statuses. |
| `pacbio_library` | Table | PacBio library prep records. | One row per library tube. | TBD | Lab workflow | Active | Add FK/index support and normalize statuses. |
| `ont_library` | Table | ONT library prep records. | One row per library tube. | TBD | Lab workflow | Active | Add FK/index support and normalize statuses. |
| `hic_lysate` | Table | Hi-C lysate records from tissue. | One row per lysate. | TBD | Lab workflow | Active | Add/support index on `tissue_id`. |
| `hic_library` | Table | Hi-C library prep records. | One row per library tube. | TBD | Lab workflow | Active | Add/support indexes on `lysate_id` and `og_id`. |
| `rna_library_ilmn` | Table | RNA Illumina library prep records. | One row per library tube. | TBD | Lab workflow | Active | Add/support indexes on `rna_id` and `og_id`. |
| `rna_library_kinx` | Table | RNA Kinnex library prep records. | One row per library tube. | TBD | Lab workflow | Active | Add FK to `rna_extraction` after validation. |
| `sequencing` | Table | Sequencing event/run metadata. | TBD: run, library-on-run, lane, or output file. | TBD | Sequencing workflow | Active | Clarify grain; redesign polymorphic library links later. |
| `species` | Table | Candidate canonical taxonomy/species table. | One row per species/taxon name. | TBD | Taxonomy/import | Active | Recommended canonical source, pending decision. |
| `master_species` | Table | GoaT-facing curated species subset or legacy duplicate. | One row per curated species. | TBD | Taxonomy/import | Review | Decide whether to replace with view/subset. |
| `species_ncbi_assembly` | Table | NCBI assembly metadata for species. | One row per species assembly record. | TBD | NCBI/import | Planned or inactive | Currently empty; confirm intended use. |
| `draft_genomes` | Table | Draft assembly and QC tracking. | One row per draft genome record. | TBD | Assembly workflow | Active | Very wide; consider thematic split later. |
| `ref_genomes` | Table | Reference genome tracking. | One row per reference genome record. | TBD | Assembly/workflow | Active | Classify orphan `og_id` examples before FK. |
| `ref_genomes_assembly_uploads` | Table | Assembly upload tracking. | One row per assembly upload. | TBD | Submission workflow | Active | Document relationship to reference genomes. |
| `ref_genomes_sra_uploads` | Table | SRA upload tracking. | One row per SRA upload. | TBD | Submission workflow | Active | Existing FK to assembly uploads; add supporting index review. |
| `mitogenome_data` | Table | Parent mitogenome analysis data. | One row per mitogenome data record. | TBD | Analysis workflow | Active | Parent for LCA tables. |
| `lca` | Table | Active LCA output. | One row per LCA result. | TBD | Analysis workflow | Active | Normalize date fields. |
| `lca_old` | Table | Legacy LCA output. | One row per legacy LCA result. | TBD | Analysis workflow | Archive review | Confirm no active consumers. |
| `lca_raw_results` | Table | Raw LCA result details. | One row per raw result. | TBD | Analysis workflow | Active | Existing FK chain to `mitogenome_data`. |
| `lca_validation` | Table | LCA validation records. | One row per validation record. | TBD | Analysis workflow | Active | Existing FK chain to `mitogenome_data`. |
| `blast_filtered_lca` | Table | Filtered BLAST/LCA output. | One row per filtered result. | TBD | Analysis workflow | Active | Classify non-sample `og_id` values before constraints. |
| `raw_data` | Table | Raw data inventory. | TBD: sample, run, lane, or file. | TBD | Sequencing/data workflow | Active | Clarify grain; blank `og_id` rows exist. |
| `raw_qc` | Table | Raw QC data. | TBD: sample, run, lane, or file. | TBD | QC workflow | Active | Classify invalid `og_id` values. |
| `hifi_reads_qc` | Table | HiFi reads QC. | TBD | TBD | QC workflow | Active | Add relationship at correct grain. |
| `hic_reads_qc` | Table | Hi-C reads QC. | TBD | TBD | QC workflow | Active | Add relationship at correct grain. |
| `rna_qc_kinnex` | Table | RNA Kinnex QC. | One row per Kinnex QC record. | TBD | QC workflow | Active | Consider FK to `rna_library_kinx`. |
| `design_description` | Table | Lookup-like design descriptions. | One row per design description. | TBD | Manual/reference | Review | No FK links observed. |

## Column Classification Backlog

| Table | Column(s) | Current Signal | Proposed Classification | Decision Needed |
|---|---|---|---|---|
| `sample` | `illumina_sequencing`, `hifi_sequencing`, `hic_sequencing`, `nanopore_sequencing`, `rna_extraction`, `rna_ilmn_sequencing`, `rna_kinnex_sequencing`, `illumina_public`, `summary_comments` | Fully empty | Deprecated or derived | Confirm downstream usage before removal. |
| Lab/library tables | `status_overwrite` | Fully empty but referenced by `summary` | Deprecated or reserved override | Decide whether override behavior is still required. |
| `species`, `master_species` | `draft_genome_bioproject_id` | Fully empty | Deprecated or planned | Confirm project submission workflow. |
| `species_ncbi_assembly` | all columns | Table has 0 rows | Planned or inactive | Decide whether NCBI assembly import is coming soon. |
| `lca_old` | many columns | Legacy table with sparse data | Archive review | Confirm active consumers. |

## Open Ownership Decisions

| Decision | Options | Needed For |
|---|---|---|
| Canonical species source | `species`, `master_species`, or new curated view | Species cleanup, FKs, GoaT view behavior. |
| Meaning of derived `og_id` values | Invalid sample, derived library/specimen ID, analysis ID, or historical archive | FK planning and cleanup scripts. |
| `sequencing` row grain | Run, library-on-run, lane, or output file | Sequencing redesign and QC/raw data relationships. |
| QC/raw data parent entity | Sample, library, sequencing run, lane, or file | Correct FK target. |
| Sample workflow status source | User-entered, imported, or derived from child tables | View refactor and status normalization. |

