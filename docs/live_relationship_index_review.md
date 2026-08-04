# Live Relationship And Index Review

Generated from PostgreSQL catalogs. A child-side FK index is marked yes only when an index has the FK columns as its leading columns.

## Foreign Keys

| Constraint | Child table | Child columns | Parent table | Parent columns | Child index | On update | On delete |
|---|---|---|---|---|---|---|---|
| `fk_tissue_id` | `dna_extraction` | `tissue_id` | `public.tissue` | `tissue_id` | no | no action | no action |
| `fk_lysate_id` | `hic_library` | `lysate_id` | `public.hic_lysate` | `lysate_id` | no | no action | no action |
| `fk_tissue_id` | `hic_lysate` | `tissue_id` | `public.tissue` | `tissue_id` | no | no action | no action |
| `fk_dna_id` | `illumina_library` | `dna_id` | `public.dna_extraction` | `dna_id` | no | no action | no action |
| `fk_mitogenome` | `lca` | `og_id`, `tech`, `seq_date`, `code` | `public.mitogenome_data` | `og_id`, `tech`, `seq_date`, `code` | no | no action | no action |
| `fk_mitogenome` | `lca_old` | `og_id`, `tech`, `seq_date`, `code` | `public.mitogenome_data` | `og_id`, `tech`, `seq_date`, `code` | no | no action | no action |
| `fk_mitogenome` | `lca_raw_results` | `og_id`, `tech`, `seq_date`, `code` | `public.mitogenome_data` | `og_id`, `tech`, `seq_date`, `code` | no | no action | no action |
| `lca_validation_mitogenome_data_fk` | `lca_validation` | `og_id`, `tech`, `seq_date`, `code` | `public.mitogenome_data` | `og_id`, `tech`, `seq_date`, `code` | no | no action | no action |
| `fk_dna_id` | `ont_library` | `dna_id` | `public.dna_extraction` | `dna_id` | no | no action | no action |
| `fk_dna_id` | `pacbio_library` | `dna_id` | `public.dna_extraction` | `dna_id` | no | no action | no action |
| `ref_genomes_sra_runs_og_id_fkey` | `ref_genomes_sra_uploads` | `og_id` | `public.ref_genomes_assembly_uploads` | `og_id` | no | no action | no action |
| `fk_tissue_id` | `rna_extraction` | `tissue_id` | `public.tissue` | `tissue_id` | no | no action | no action |
| `fk_rna_id` | `rna_library_ilmn` | `rna_id` | `public.rna_extraction` | `rna_id` | no | no action | no action |
| `fk_hic_library` | `sequencing` | `hic_library_tube_id` | `public.hic_library` | `hic_library_tube_id` | no | no action | no action |
| `fk_illumina_library` | `sequencing` | `illumina_library_tube_id` | `public.illumina_library` | `illumina_library_tube_id` | no | no action | no action |
| `fk_ont_library` | `sequencing` | `ont_library_tube_id` | `public.ont_library` | `ont_library_tube_id` | no | no action | no action |
| `fk_pacbio_library` | `sequencing` | `pacbio_library_tube_id` | `public.pacbio_library` | `pacbio_library_tube_id` | no | no action | no action |
| `species_ncbi_assembly_species_fkey` | `species_ncbi_assembly` | `species` | `public.species` | `species` | no | no action | no action |
| `fk_og_id` | `tissue` | `og_id` | `public.sample` | `og_id` | no | no action | no action |

## Missing Child-Side FK Index Candidates

| Table | Columns | FK constraint | Candidate index |
|---|---|---|---|
| `dna_extraction` | `tissue_id` | `fk_tissue_id` | `CREATE INDEX CONCURRENTLY ON dna_extraction (tissue_id);` |
| `hic_library` | `lysate_id` | `fk_lysate_id` | `CREATE INDEX CONCURRENTLY ON hic_library (lysate_id);` |
| `hic_lysate` | `tissue_id` | `fk_tissue_id` | `CREATE INDEX CONCURRENTLY ON hic_lysate (tissue_id);` |
| `illumina_library` | `dna_id` | `fk_dna_id` | `CREATE INDEX CONCURRENTLY ON illumina_library (dna_id);` |
| `lca` | `og_id`, `tech`, `seq_date`, `code` | `fk_mitogenome` | `CREATE INDEX CONCURRENTLY ON lca (og_id, tech, seq_date, code);` |
| `lca_old` | `og_id`, `tech`, `seq_date`, `code` | `fk_mitogenome` | `CREATE INDEX CONCURRENTLY ON lca_old (og_id, tech, seq_date, code);` |
| `lca_raw_results` | `og_id`, `tech`, `seq_date`, `code` | `fk_mitogenome` | `CREATE INDEX CONCURRENTLY ON lca_raw_results (og_id, tech, seq_date, code);` |
| `lca_validation` | `og_id`, `tech`, `seq_date`, `code` | `lca_validation_mitogenome_data_fk` | `CREATE INDEX CONCURRENTLY ON lca_validation (og_id, tech, seq_date, code);` |
| `ont_library` | `dna_id` | `fk_dna_id` | `CREATE INDEX CONCURRENTLY ON ont_library (dna_id);` |
| `pacbio_library` | `dna_id` | `fk_dna_id` | `CREATE INDEX CONCURRENTLY ON pacbio_library (dna_id);` |
| `ref_genomes_sra_uploads` | `og_id` | `ref_genomes_sra_runs_og_id_fkey` | `CREATE INDEX CONCURRENTLY ON ref_genomes_sra_uploads (og_id);` |
| `rna_extraction` | `tissue_id` | `fk_tissue_id` | `CREATE INDEX CONCURRENTLY ON rna_extraction (tissue_id);` |
| `rna_library_ilmn` | `rna_id` | `fk_rna_id` | `CREATE INDEX CONCURRENTLY ON rna_library_ilmn (rna_id);` |
| `sequencing` | `hic_library_tube_id` | `fk_hic_library` | `CREATE INDEX CONCURRENTLY ON sequencing (hic_library_tube_id);` |
| `sequencing` | `illumina_library_tube_id` | `fk_illumina_library` | `CREATE INDEX CONCURRENTLY ON sequencing (illumina_library_tube_id);` |
| `sequencing` | `ont_library_tube_id` | `fk_ont_library` | `CREATE INDEX CONCURRENTLY ON sequencing (ont_library_tube_id);` |
| `sequencing` | `pacbio_library_tube_id` | `fk_pacbio_library` | `CREATE INDEX CONCURRENTLY ON sequencing (pacbio_library_tube_id);` |
| `species_ncbi_assembly` | `species` | `species_ncbi_assembly_species_fkey` | `CREATE INDEX CONCURRENTLY ON species_ncbi_assembly (species);` |
| `tissue` | `og_id` | `fk_og_id` | `CREATE INDEX CONCURRENTLY ON tissue (og_id);` |

## Existing Indexes

| Table | Index | Type | Definition |
|---|---|---|---|
| `blast_filtered_lca` | `blast_filtered_lca_pk` | primary | `CREATE UNIQUE INDEX blast_filtered_lca_pk ON public.blast_filtered_lca USING btree (og_id, tech, seq_date, code, annotation, match_sequence_id, region)` |
| `design_description` | `design_description_pk` | primary | `CREATE UNIQUE INDEX design_description_pk ON public.design_description USING btree (design_no)` |
| `dna_extraction` | `DNA_Extraction_pkey` | primary | `CREATE UNIQUE INDEX "DNA_Extraction_pkey" ON public.dna_extraction USING btree (dna_id)` |
| `draft_genomes` | `draft_genomes_pkey` | primary | `CREATE UNIQUE INDEX draft_genomes_pkey ON public.draft_genomes USING btree (og_id, seq_date)` |
| `hic_library` | `HiC_Library_pkey` | primary | `CREATE UNIQUE INDEX "HiC_Library_pkey" ON public.hic_library USING btree (hic_library_tube_id)` |
| `hic_lysate` | `HiC_Lysate_pkey` | primary | `CREATE UNIQUE INDEX "HiC_Lysate_pkey" ON public.hic_lysate USING btree (lysate_id)` |
| `hic_reads_qc` | `hic_reads_qc_pkey` | primary | `CREATE UNIQUE INDEX hic_reads_qc_pkey ON public.hic_reads_qc USING btree (og_id, tissue, ext_type, lib_code, lane, run_id)` |
| `hifi_reads_qc` | `hifi_reads_qc_pkey` | primary | `CREATE UNIQUE INDEX hifi_reads_qc_pkey ON public.hifi_reads_qc USING btree (og_id, tissue, ext_type, lib_code, run_id)` |
| `illumina_library` | `Illumina_Library_pkey` | primary | `CREATE UNIQUE INDEX "Illumina_Library_pkey" ON public.illumina_library USING btree (illumina_library_tube_id)` |
| `lca` | `lca_results_unique` | unique | `CREATE UNIQUE INDEX lca_results_unique ON public.lca USING btree (og_id, tech, seq_date, code, annotation, region, lca_run_date)` |
| `lca_old` | `lca_unique` | unique | `CREATE UNIQUE INDEX lca_unique ON public.lca_old USING btree (og_id, tech, seq_date, code, annotation, region, lca_run_date)` |
| `lca_raw_results` | `lca_raw_results_unique` | unique | `CREATE UNIQUE INDEX lca_raw_results_unique ON public.lca_raw_results USING btree (og_id, tech, seq_date, code, annotation, sequence_region, lca_run_date, accession_id)` |
| `lca_validation` | `lca_validation_pk` | primary | `CREATE UNIQUE INDEX lca_validation_pk ON public.lca_validation USING btree (og_id, tech, seq_date, code, annotation)` |
| `master_species` | `master_species_pkey` | primary | `CREATE UNIQUE INDEX master_species_pkey ON public.master_species USING btree (species)` |
| `mitogenome_data` | `mitogenome_data_pkey` | primary | `CREATE UNIQUE INDEX mitogenome_data_pkey ON public.mitogenome_data USING btree (og_id, tech, seq_date, code)` |
| `mitogenome_data` | `mitogenome_data_unique` | unique | `CREATE UNIQUE INDEX mitogenome_data_unique ON public.mitogenome_data USING btree (og_id, tech, seq_date, code, annotation)` |
| `ont_library` | `ONT_Library_pkey` | primary | `CREATE UNIQUE INDEX "ONT_Library_pkey" ON public.ont_library USING btree (ont_library_tube_id)` |
| `pacbio_library` | `PacBio_Library_pkey` | primary | `CREATE UNIQUE INDEX "PacBio_Library_pkey" ON public.pacbio_library USING btree (pacbio_library_tube_id)` |
| `raw_data` | `raw_data_pkey` | primary | `CREATE UNIQUE INDEX raw_data_pkey ON public.raw_data USING btree (run_id, lane_id, filename)` |
| `raw_qc` | `raw_qc_og_id_uq` | unique | `CREATE UNIQUE INDEX raw_qc_og_id_uq ON public.raw_qc USING btree (og_id)` |
| `raw_qc` | `raw_qc_pkey` | primary | `CREATE UNIQUE INDEX raw_qc_pkey ON public.raw_qc USING btree (og_id)` |
| `ref_genomes` | `ref_genomes_pkey` | primary | `CREATE UNIQUE INDEX ref_genomes_pkey ON public.ref_genomes USING btree (og_id, seq_date, stage, haplotype, version)` |
| `ref_genomes_assembly_uploads` | `ref_genomes_uploads_pkey` | primary | `CREATE UNIQUE INDEX ref_genomes_uploads_pkey ON public.ref_genomes_assembly_uploads USING btree (og_id)` |
| `ref_genomes_sra_uploads` | `ref_genomes_sra_runs_pkey` | primary | `CREATE UNIQUE INDEX ref_genomes_sra_runs_pkey ON public.ref_genomes_sra_uploads USING btree (srr_accession)` |
| `rna_extraction` | `RNA_Extraction_pkey` | primary | `CREATE UNIQUE INDEX "RNA_Extraction_pkey" ON public.rna_extraction USING btree (rna_id)` |
| `rna_library_ilmn` | `RNA_Library_pkey` | primary | `CREATE UNIQUE INDEX "RNA_Library_pkey" ON public.rna_library_ilmn USING btree (rna_library_tube_id)` |
| `rna_library_kinx` | `rna_library_kinx_pkey` | primary | `CREATE UNIQUE INDEX rna_library_kinx_pkey ON public.rna_library_kinx USING btree (rna_library_tube_id)` |
| `rna_qc_kinnex` | `rna_qc_run_id_tube_uniq` | unique | `CREATE UNIQUE INDEX rna_qc_run_id_tube_uniq ON public.rna_qc_kinnex USING btree (run_id, rna_tube_id)` |
| `sample` | `Sample_pkey` | primary | `CREATE UNIQUE INDEX "Sample_pkey" ON public.sample USING btree (og_id)` |
| `sequencing` | `Sequencing_pkey` | primary | `CREATE UNIQUE INDEX "Sequencing_pkey" ON public.sequencing USING btree (sequencing_id)` |
| `species` | `Species_pkey` | primary | `CREATE UNIQUE INDEX "Species_pkey" ON public.species USING btree (species)` |
| `species_ncbi_assembly` | `species_ncbi_assembly_one_chosen_idx` | unique | `CREATE UNIQUE INDEX species_ncbi_assembly_one_chosen_idx ON public.species_ncbi_assembly USING btree (species) WHERE is_chosen` |
| `species_ncbi_assembly` | `species_ncbi_assembly_pkey` | primary | `CREATE UNIQUE INDEX species_ncbi_assembly_pkey ON public.species_ncbi_assembly USING btree (assembly_accession)` |
| `species_ncbi_assembly` | `species_ncbi_assembly_species_idx` |  | `CREATE INDEX species_ncbi_assembly_species_idx ON public.species_ncbi_assembly USING btree (species)` |
| `tissue` | `Tissue_pkey` | primary | `CREATE UNIQUE INDEX "Tissue_pkey" ON public.tissue USING btree (tissue_id)` |
