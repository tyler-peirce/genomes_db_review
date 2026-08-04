# Live Column Inventory

Generated from the live PostgreSQL database. `Indexed` means the column appears in at least one index definition; review index order and selectivity before relying on it.

| Object | Type | # | Column | Data type | Nullable | Default | PK | FK target | Indexed | Database comment |
|---|---|---:|---|---|---|---|---|---|---|---|
| `blast_filtered_lca` | table | 1 | `og_id` | `text` | no |  | yes |  | yes |  |
| `blast_filtered_lca` | table | 2 | `tech` | `text` | no |  | yes |  | yes |  |
| `blast_filtered_lca` | table | 3 | `seq_date` | `text` | no |  | yes |  | yes |  |
| `blast_filtered_lca` | table | 4 | `code` | `text` | no |  | yes |  | yes |  |
| `blast_filtered_lca` | table | 5 | `annotation` | `text` | no |  | yes |  | yes |  |
| `blast_filtered_lca` | table | 6 | `match_sequence_id` | `text` | no |  | yes |  | yes |  |
| `blast_filtered_lca` | table | 7 | `taxon_id` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 8 | `scientific_name` | `text` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 9 | `common_name` | `text` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 10 | `kingdoms` | `text` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 11 | `percent_identity` | `double precision` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 12 | `alignment_length` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 13 | `query_length` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 14 | `subject_length` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 15 | `mismatch` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 16 | `gap_open` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 17 | `gaps` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 18 | `query_start` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 19 | `query_end` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 20 | `subject_start` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 21 | `subject_end` | `integer` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 22 | `subject_title` | `text` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 23 | `evalue` | `double precision` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 24 | `bit_score` | `double precision` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 25 | `query_coverage` | `double precision` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 26 | `subject_coverage` | `double precision` | yes |  |  |  |  |  |
| `blast_filtered_lca` | table | 27 | `region` | `text` | no |  | yes |  | yes |  |
| `blast_filtered_lca` | table | 28 | `blast_run_date` | `text` | yes |  |  |  |  |  |
| `design_description` | table | 1 | `design_no` | `integer` | no |  | yes |  | yes |  |
| `design_description` | table | 2 | `design_description` | `character varying` | yes |  |  |  |  |  |
| `design_description` | table | 3 | `comment` | `character varying` | yes |  |  |  |  |  |
| `dna_extraction` | table | 1 | `dna_id` | `text` | no |  | yes |  | yes |  |
| `dna_extraction` | table | 2 | `tissue_id` | `text` | yes |  |  | public.tissue(tissue_id) |  |  |
| `dna_extraction` | table | 3 | `ext_num` | `integer` | yes |  |  |  |  |  |
| `dna_extraction` | table | 4 | `status` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 5 | `extraction_method` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 6 | `extraction_date` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 7 | `extraction_batch_id` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 8 | `final_buffer` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 9 | `volume` | `integer` | yes |  |  |  |  |  |
| `dna_extraction` | table | 10 | `qubit_conc` | `real` | yes |  |  |  |  |  |
| `dna_extraction` | table | 11 | `nano_drop_conc` | `real` | yes |  |  |  |  |  |
| `dna_extraction` | table | 12 | `ratio_260_280` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 13 | `ratio_260_230` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 14 | `ratioqubit_nanodrop` | `real` | yes |  |  |  |  |  |
| `dna_extraction` | table | 15 | `total_yield` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 16 | `gdna_femtol_id` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 17 | `av_size` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 18 | `extraction_qc` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 19 | `comment` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 20 | `dna_freezer` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 21 | `dna_shelf` | `integer` | yes |  |  |  |  |  |
| `dna_extraction` | table | 22 | `dna_rack` | `integer` | yes |  |  |  |  |  |
| `dna_extraction` | table | 23 | `dna_level` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 24 | `dna_box` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 25 | `dna_notes` | `text` | yes |  |  |  |  |  |
| `dna_extraction` | table | 26 | `og_num` | `integer` | yes | `(regexp_replace(tissue_id, '[^0-9]'::text, ''::text, 'g'::text))::integer` |  |  |  |  |
| `dna_extraction` | table | 27 | `og_id` | `text` | yes | `regexp_replace(tissue_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)` |  |  |  |  |
| `dna_extraction` | table | 28 | `status_overwrite` | `character varying` | yes |  |  |  |  |  |
| `draft_genomes` | table | 1 | `og_id` | `text` | no |  | yes |  | yes |  |
| `draft_genomes` | table | 2 | `mach` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 3 | `seq_date` | `text` | no |  | yes |  | yes |  |
| `draft_genomes` | table | 4 | `initial` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 5 | `passed_filter_reads` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 6 | `low_quality_reads` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 7 | `too_many_n_reads` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 8 | `too_short_reads` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 9 | `too_long_reads` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 10 | `raw_total_reads` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 11 | `raw_total_bases` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 12 | `raw_q20_bases` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 13 | `raw_q30_bases` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 14 | `raw_q20_rate` | `numeric(7,6)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 15 | `raw_q30_rate` | `numeric(7,6)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 16 | `raw_read1_mean_length` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 17 | `raw_read2_mean_length` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 18 | `raw_gc_content` | `numeric(7,6)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 19 | `total_reads` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 20 | `total_bases` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 21 | `q20_bases` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 22 | `q30_bases` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 23 | `q20_rate` | `numeric(7,6)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 24 | `q30_rate` | `numeric(7,6)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 25 | `read1_mean_length` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 26 | `read2_mean_length` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 27 | `gc_content` | `numeric(7,6)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 28 | `homozygosity` | `numeric(5,2)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 29 | `heterozygosity` | `numeric(5,2)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 30 | `genomesize` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 31 | `repeatsize` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 32 | `uniquesize` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 33 | `modelfit` | `numeric(5,2)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 34 | `errorrate` | `numeric(5,2)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 35 | `num_contigs` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 36 | `num_contigs_mitochondrion` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 37 | `num_contigs_plastid` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 38 | `num_contigs_prokarya` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 39 | `bp_mitochondrion` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 40 | `bp_plastid` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 41 | `bp_prokarya` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 42 | `complete` | `numeric(4,1)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 43 | `single_copy` | `numeric(4,1)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 44 | `multi_copy` | `numeric(4,1)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 45 | `fragmented` | `numeric(4,1)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 46 | `missing` | `numeric(4,1)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 47 | `n_markers` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 48 | `domain` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 49 | `number_of_scaffolds` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 50 | `number_of_contigs` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 51 | `total_length` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 52 | `percent_gaps` | `numeric(5,2)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 53 | `scaffold_n50` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 54 | `contigs_n50` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 55 | `unique_k_mers_assembly` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 56 | `k_mers_total` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 57 | `qv` | `numeric(6,4)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 58 | `error` | `numeric(12,11)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 59 | `k_mer_set` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 60 | `solid_k_mers` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 61 | `total_k_mers` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 62 | `completeness` | `numeric(7,4)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 63 | `depmethod` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 64 | `adjust` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 65 | `readbp` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 66 | `mapadjust` | `numeric(7,6)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 67 | `scdepth` | `numeric(5,2)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 68 | `estgenomesize` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 69 | `aws_r1` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 70 | `aws_r1_size` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 71 | `aws_r2` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 72 | `aws_r2_size` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 73 | `aws_assm` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 74 | `aws_assm_size` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 75 | `sra_accession` | `character varying` | yes |  |  |  |  |  |
| `draft_genomes` | table | 76 | `biosample_accession` | `character varying` | yes |  |  |  |  |  |
| `draft_genomes` | table | 77 | `study` | `character varying` | yes |  |  |  |  |  |
| `draft_genomes` | table | 78 | `bioproject_accession` | `character varying` | yes |  |  |  |  |  |
| `draft_genomes` | table | 79 | `comment` | `character varying` | yes |  |  |  |  |  |
| `draft_genomes` | table | 80 | `fastp_r1` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 81 | `fastp_r1_size` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 82 | `fastp_r2` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 83 | `fastp_r2_size` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 84 | `sra_r1` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 85 | `sra_r1_size` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 86 | `sra_r2` | `text` | yes |  |  |  |  |  |
| `draft_genomes` | table | 87 | `sra_r2_size` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 89 | `og_num` | `integer` | yes | `(SUBSTRING(og_id FROM 3))::integer` |  |  |  |  |
| `draft_genomes` | table | 90 | `sra_date_submitted` | `date` | yes |  |  |  |  |  |
| `draft_genomes` | table | 91 | `num_contigs_exclude` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 92 | `num_contigs_trim` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 93 | `num_contigs_review` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 94 | `bp_exclude` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 95 | `bp_trim` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 96 | `bp_review` | `integer` | yes |  |  |  |  |  |
| `draft_genomes` | table | 97 | `gfa_num_contigs` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 98 | `gfa_contig_n50` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 99 | `gfa_num_scaffolds` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 100 | `gfa_scaffold_n50` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 101 | `gfa_largest_scaffold` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 102 | `gfa_total_scaffold_length` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 103 | `gfa_gc_content_percent` | `numeric(10,2)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 104 | `internal_stop_codon_percent` | `numeric(5,2)` | yes |  |  |  |  |  |
| `draft_genomes` | table | 105 | `internal_stop_codon_count` | `bigint` | yes |  |  |  |  |  |
| `draft_genomes` | table | 106 | `assembly_accession` | `text` | yes |  |  |  |  |  |
| `hic_library` | table | 1 | `hic_library_tube_id` | `text` | no |  | yes |  | yes |  |
| `hic_library` | table | 2 | `lysate_id` | `text` | yes |  |  | public.hic_lysate(lysate_id) |  |  |
| `hic_library` | table | 3 | `hic_num` | `integer` | yes |  |  |  |  |  |
| `hic_library` | table | 4 | `hic_status` | `text` | yes |  |  |  |  |  |
| `hic_library` | table | 5 | `library_method` | `text` | yes |  |  |  |  |  |
| `hic_library` | table | 6 | `library_date` | `text` | yes |  |  |  |  |  |
| `hic_library` | table | 7 | `library_id` | `text` | yes |  |  |  |  |  |
| `hic_library` | table | 8 | `prox_ligation_conc` | `real` | yes |  |  |  |  |  |
| `hic_library` | table | 9 | `purified_dna_total` | `real` | yes |  |  |  |  |  |
| `hic_library` | table | 10 | `index_set` | `text` | yes |  |  |  |  |  |
| `hic_library` | table | 11 | `library_conc` | `real` | yes |  |  |  |  |  |
| `hic_library` | table | 12 | `library_size` | `integer` | yes |  |  |  |  |  |
| `hic_library` | table | 13 | `hic_comments` | `text` | yes |  |  |  |  |  |
| `hic_library` | table | 14 | `status_overwrite` | `character varying` | yes |  |  |  |  |  |
| `hic_library` | table | 15 | `og_id` | `text` | yes | `regexp_replace(lysate_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)` |  |  |  |  |
| `hic_lysate` | table | 1 | `lysate_id` | `text` | no |  | yes |  | yes |  |
| `hic_lysate` | table | 2 | `tissue_id` | `text` | yes |  |  | public.tissue(tissue_id) |  |  |
| `hic_lysate` | table | 3 | `lysate_num` | `integer` | yes |  |  |  |  |  |
| `hic_lysate` | table | 4 | `lysate_status` | `text` | yes |  |  |  |  |  |
| `hic_lysate` | table | 5 | `lysate_prep_date` | `date` | yes |  |  |  |  |  |
| `hic_lysate` | table | 6 | `lysate_batch_id` | `text` | yes |  |  |  |  |  |
| `hic_lysate` | table | 7 | `lysate_conc` | `real` | yes |  |  |  |  |  |
| `hic_lysate` | table | 8 | `total_lysate` | `real` | yes |  |  |  |  |  |
| `hic_lysate` | table | 9 | `lysate_cde` | `real` | yes |  |  |  |  |  |
| `hic_lysate` | table | 10 | `lysate_comments` | `text` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 1 | `og_id` | `text` | no | `''::text` | yes |  | yes |  |
| `hic_reads_qc` | table | 2 | `tissue` | `text` | no | `''::text` | yes |  | yes |  |
| `hic_reads_qc` | table | 3 | `ext_type` | `text` | no | `''::text` | yes |  | yes |  |
| `hic_reads_qc` | table | 4 | `lib_code` | `text` | no | `''::text` | yes |  | yes |  |
| `hic_reads_qc` | table | 5 | `lane` | `text` | no | `''::text` | yes |  | yes |  |
| `hic_reads_qc` | table | 6 | `run_id` | `text` | no | `''::text` | yes |  | yes |  |
| `hic_reads_qc` | table | 7 | `datecreated` | `date` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 8 | `isarchived` | `boolean` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 9 | `isfiledeleted` | `boolean` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 10 | `totalreadspf` | `bigint` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 11 | `totalclusterspf` | `bigint` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 12 | `read1length` | `integer` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 13 | `read2length` | `integer` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 14 | `ispairedend` | `boolean` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 15 | `yield_gb` | `numeric` | yes |  |  |  |  |  |
| `hic_reads_qc` | table | 16 | `totalsize_gb` | `numeric` | yes |  |  |  |  |  |
| `hifi_reads_qc` | table | 1 | `og_id` | `text` | no |  | yes |  | yes |  |
| `hifi_reads_qc` | table | 2 | `tissue` | `text` | no |  | yes |  | yes |  |
| `hifi_reads_qc` | table | 3 | `ext_type` | `text` | no |  | yes |  | yes |  |
| `hifi_reads_qc` | table | 4 | `lib_code` | `text` | no |  | yes |  | yes |  |
| `hifi_reads_qc` | table | 5 | `run_id` | `text` | no | `''::text` | yes |  | yes |  |
| `hifi_reads_qc` | table | 6 | `barcode` | `text` | yes |  |  |  |  |  |
| `hifi_reads_qc` | table | 7 | `barcode_quality` | `numeric` | yes |  |  |  |  |  |
| `hifi_reads_qc` | table | 8 | `hifi_reads` | `bigint` | yes |  |  |  |  |  |
| `hifi_reads_qc` | table | 9 | `hifi_read_length` | `numeric` | yes |  |  |  |  |  |
| `hifi_reads_qc` | table | 10 | `hifi_read_quality` | `text` | yes |  |  |  |  |  |
| `hifi_reads_qc` | table | 11 | `hifi_yield` | `bigint` | yes |  |  |  |  |  |
| `hifi_reads_qc` | table | 12 | `polymerase_read_length` | `numeric` | yes |  |  |  |  |  |
| `illumina_library` | table | 1 | `illumina_library_tube_id` | `text` | no |  | yes |  | yes |  |
| `illumina_library` | table | 2 | `dna_id` | `text` | yes |  |  | public.dna_extraction(dna_id) |  |  |
| `illumina_library` | table | 3 | `ilmn_num` | `integer` | yes |  |  |  |  |  |
| `illumina_library` | table | 4 | `ilmn_status` | `text` | yes |  |  |  |  |  |
| `illumina_library` | table | 5 | `library_method` | `text` | yes |  |  |  |  |  |
| `illumina_library` | table | 6 | `library_date` | `text` | yes |  |  |  |  |  |
| `illumina_library` | table | 7 | `library_id` | `text` | yes |  |  |  |  |  |
| `illumina_library` | table | 8 | `index_set` | `text` | yes |  |  |  |  |  |
| `illumina_library` | table | 9 | `index_well` | `text` | yes |  |  |  |  |  |
| `illumina_library` | table | 10 | `index_idx` | `text` | yes |  |  |  |  |  |
| `illumina_library` | table | 11 | `library_qubit_conc` | `text` | yes |  |  |  |  |  |
| `illumina_library` | table | 12 | `il_comments` | `text` | yes |  |  |  |  |  |
| `illumina_library` | table | 13 | `status_overwrite` | `character varying` | yes |  |  |  |  |  |
| `illumina_library` | table | 14 | `og_id` | `text` | yes | `regexp_replace(dna_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)` |  |  |  |  |
| `lca` | table | 1 | `og_num` | `integer` | yes | `(SUBSTRING(og_id FROM 3))::integer` |  |  |  |  |
| `lca` | table | 2 | `og_id` | `text` | no |  |  | public.mitogenome_data(og_id) | yes |  |
| `lca` | table | 3 | `tech` | `text` | no |  |  | public.mitogenome_data(tech) | yes |  |
| `lca` | table | 4 | `seq_date` | `text` | no |  |  | public.mitogenome_data(seq_date) | yes |  |
| `lca` | table | 5 | `code` | `text` | no |  |  | public.mitogenome_data(code) | yes |  |
| `lca` | table | 6 | `annotation` | `text` | no |  |  |  | yes |  |
| `lca` | table | 7 | `region` | `text` | no |  |  |  | yes |  |
| `lca` | table | 8 | `lca_run_date` | `text` | yes |  |  |  | yes |  |
| `lca` | table | 9 | `species_in_lca` | `text` | yes |  |  |  |  |  |
| `lca` | table | 10 | `number_unq_blast_hits` | `integer` | yes |  |  |  |  |  |
| `lca` | table | 11 | `domain` | `text` | yes |  |  |  |  |  |
| `lca` | table | 12 | `phylum` | `text` | yes |  |  |  |  |  |
| `lca` | table | 13 | `class` | `text` | yes |  |  |  |  |  |
| `lca` | table | 14 | `order` | `text` | yes |  |  |  |  |  |
| `lca` | table | 15 | `family` | `text` | yes |  |  |  |  |  |
| `lca` | table | 16 | `genus` | `text` | yes |  |  |  |  |  |
| `lca` | table | 17 | `specific_epiphet` | `text` | yes |  |  |  |  |  |
| `lca` | table | 18 | `species` | `text` | yes |  |  |  |  |  |
| `lca` | table | 19 | `scientific_name_authorship` | `character varying` | yes |  |  |  |  |  |
| `lca` | table | 20 | `taxon_rank` | `text` | yes |  |  |  |  |  |
| `lca` | table | 21 | `top_taxon_id` | `character varying` | yes |  |  |  |  |  |
| `lca` | table | 22 | `taxon_id_db` | `character varying` | yes |  |  |  |  |  |
| `lca` | table | 23 | `top_accession_id` | `character varying` | yes |  |  |  |  |  |
| `lca` | table | 24 | `accession_id_ref_db` | `character varying` | yes |  |  |  |  |  |
| `lca` | table | 25 | `top_percent_query_cover` | `real` | yes |  |  |  |  |  |
| `lca` | table | 26 | `top_percent_query_cover_hsp` | `real` | yes |  |  |  |  |  |
| `lca` | table | 27 | `alignment_length` | `integer` | yes |  |  |  |  |  |
| `lca` | table | 28 | `subject_length` | `integer` | yes |  |  |  |  |  |
| `lca` | table | 29 | `sequence_length` | `integer` | yes |  |  |  |  |  |
| `lca` | table | 30 | `top_confidence_score` | `real` | yes |  |  |  |  |  |
| `lca` | table | 31 | `top_percent_match` | `double precision` | yes |  |  |  |  |  |
| `lca_old` | table | 1 | `og_id` | `text` | no |  |  | public.mitogenome_data(og_id) | yes |  |
| `lca_old` | table | 2 | `tech` | `text` | no |  |  | public.mitogenome_data(tech) | yes |  |
| `lca_old` | table | 3 | `seq_date` | `text` | no |  |  | public.mitogenome_data(seq_date) | yes |  |
| `lca_old` | table | 4 | `code` | `text` | no |  |  | public.mitogenome_data(code) | yes |  |
| `lca_old` | table | 5 | `annotation` | `text` | no |  |  |  | yes |  |
| `lca_old` | table | 6 | `taxonomy` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 7 | `lca` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 8 | `top_percent_match` | `real` | yes |  |  |  |  |  |
| `lca_old` | table | 9 | `length` | `integer` | yes |  |  |  |  |  |
| `lca_old` | table | 10 | `lca_run_date` | `text` | yes |  |  |  | yes |  |
| `lca_old` | table | 11 | `region` | `text` | no |  |  |  | yes |  |
| `lca_old` | table | 12 | `og_num` | `integer` | yes | `(SUBSTRING(og_id FROM 3))::integer` |  |  |  |  |
| `lca_old` | table | 13 | `class` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 14 | `order` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 15 | `family` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 16 | `genus` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 17 | `species` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 18 | `coverage` | `real` | yes |  |  |  |  |  |
| `lca_old` | table | 19 | `specific_epiphet` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 20 | `scientific_name_authorship` | `character varying` | yes |  |  |  |  |  |
| `lca_old` | table | 21 | `taxon_rank` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 22 | `top_taxon_id` | `character varying` | yes |  |  |  |  |  |
| `lca_old` | table | 23 | `taxon_id_db` | `character varying` | yes |  |  |  |  |  |
| `lca_old` | table | 24 | `top_accession_id` | `character varying` | yes |  |  |  |  |  |
| `lca_old` | table | 25 | `accession_id_ref_db` | `character varying` | yes |  |  |  |  |  |
| `lca_old` | table | 26 | `top_percent_query_cover` | `real` | yes |  |  |  |  |  |
| `lca_old` | table | 27 | `top_percent_query_cover_hsp` | `real` | yes |  |  |  |  |  |
| `lca_old` | table | 28 | `alignment_length` | `integer` | yes |  |  |  |  |  |
| `lca_old` | table | 29 | `subject_length` | `integer` | yes |  |  |  |  |  |
| `lca_old` | table | 30 | `sequence_length` | `integer` | yes |  |  |  |  |  |
| `lca_old` | table | 31 | `top_confidence_score` | `real` | yes |  |  |  |  |  |
| `lca_old` | table | 32 | `species_in_lca` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 33 | `number_unq_blast_hits` | `integer` | yes |  |  |  |  |  |
| `lca_old` | table | 34 | `domain` | `text` | yes |  |  |  |  |  |
| `lca_old` | table | 35 | `phylum` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 1 | `og_num` | `integer` | yes | `(SUBSTRING(og_id FROM 3))::integer` |  |  |  |  |
| `lca_raw_results` | table | 2 | `og_id` | `text` | no |  |  | public.mitogenome_data(og_id) | yes |  |
| `lca_raw_results` | table | 3 | `tech` | `text` | no |  |  | public.mitogenome_data(tech) | yes |  |
| `lca_raw_results` | table | 4 | `seq_date` | `text` | no |  |  | public.mitogenome_data(seq_date) | yes |  |
| `lca_raw_results` | table | 5 | `code` | `text` | no |  |  | public.mitogenome_data(code) | yes |  |
| `lca_raw_results` | table | 6 | `annotation` | `text` | no |  |  |  | yes |  |
| `lca_raw_results` | table | 7 | `sequence_region` | `text` | yes |  |  |  | yes |  |
| `lca_raw_results` | table | 8 | `lca_run_date` | `integer` | yes |  |  |  | yes |  |
| `lca_raw_results` | table | 9 | `domain` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 10 | `phylum` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 11 | `class` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 12 | `order` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 13 | `family` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 14 | `genus` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 15 | `specific_epiphet` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 16 | `scientific_name` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 17 | `scientific_name_authorship` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 18 | `taxon_rank` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 19 | `taxon_id` | `character varying` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 20 | `taxon_id_db` | `character varying` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 21 | `verbatim_identification` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 22 | `accession_id` | `character varying` | yes |  |  |  | yes |  |
| `lca_raw_results` | table | 23 | `accession_id_ref_db` | `text` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 24 | `percent_match` | `real` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 25 | `percent_query_cover` | `real` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 26 | `percent_query_cover_hsp` | `real` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 27 | `alignment_length` | `integer` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 28 | `subject_length` | `integer` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 29 | `sequence_length` | `integer` | yes |  |  |  |  |  |
| `lca_raw_results` | table | 30 | `confidence_score` | `real` | yes |  |  |  |  |  |
| `lca_validation` | table | 1 | `og_id` | `text` | no |  | yes | public.mitogenome_data(og_id) | yes |  |
| `lca_validation` | table | 2 | `tech` | `text` | no |  | yes | public.mitogenome_data(tech) | yes |  |
| `lca_validation` | table | 3 | `validated_species_name` | `text` | yes |  |  |  |  |  |
| `lca_validation` | table | 4 | `validator` | `text` | yes |  |  |  |  |  |
| `lca_validation` | table | 5 | `nominal_species_id_lca_comment` | `text` | yes |  |  |  |  |  |
| `lca_validation` | table | 6 | `validator_2` | `text` | yes |  |  |  |  |  |
| `lca_validation` | table | 7 | `data_release` | `character varying` | yes |  |  |  |  |  |
| `lca_validation` | table | 8 | `og_num` | `integer` | yes | `(SUBSTRING(og_id FROM 3))::integer` |  |  |  |  |
| `lca_validation` | table | 9 | `seq_date` | `text` | no |  | yes | public.mitogenome_data(seq_date) | yes |  |
| `lca_validation` | table | 10 | `code` | `character varying` | no |  | yes | public.mitogenome_data(code) | yes |  |
| `lca_validation` | table | 11 | `annotation` | `character varying` | no |  | yes |  | yes |  |
| `lca_validation` | table | 12 | `row_created_on` | `timestamp with time zone` | no | `now()` |  |  |  |  |
| `master_species` | table | 1 | `species` | `text` | no |  | yes |  | yes |  |
| `master_species` | table | 2 | `class` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 3 | `ordr` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 4 | `family` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 5 | `genus` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 6 | `epithet` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 7 | `afd_common_name` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 8 | `family_common_name` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 9 | `ncbi_taxon_id` | `integer` | yes |  |  |  |  |  |
| `master_species` | table | 10 | `synonym` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 11 | `specimen_tol_id` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 12 | `sequencing_status` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 13 | `ont` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 14 | `hifi` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 15 | `hic` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 16 | `draft_sequencing_status` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 17 | `illumina` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 18 | `draft_genome_bioproject_id` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 19 | `genome_available` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 20 | `internal_aus_status_fishbase` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 21 | `cites_listing` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 22 | `iucn_code` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 23 | `iucn_assessment` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 24 | `iucn_dateassessed` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 25 | `epbc` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 26 | `internal_first_in_family` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 27 | `internal_first_in_genus` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 28 | `internal_conservation_value` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 29 | `internal_research` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 30 | `internal_endemic` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 31 | `sequencing_priority` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 32 | `collaboration` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 33 | `comments` | `text` | yes |  |  |  |  |  |
| `master_species` | table | 34 | `lab_database_status` | `text` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 1 | `og_id` | `text` | no |  | yes |  | yes |  |
| `mitogenome_data` | table | 2 | `tech` | `text` | no |  | yes |  | yes |  |
| `mitogenome_data` | table | 3 | `seq_date` | `text` | no |  | yes |  | yes |  |
| `mitogenome_data` | table | 4 | `code` | `text` | no |  | yes |  | yes |  |
| `mitogenome_data` | table | 5 | `stats` | `text` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 6 | `length` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 7 | `length_emma` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 8 | `seqlength_12s` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 9 | `seqlength_16s` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 10 | `seqlength_co1` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 11 | `cds_no` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 12 | `trna_no` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 13 | `rrna_no` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 14 | `status` | `text` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 15 | `genbank` | `text` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 16 | `rrna12s` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 17 | `rrna16s` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 18 | `atp6` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 19 | `atp8` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 20 | `cox1` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 21 | `cox2` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 22 | `cox3` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 23 | `cytb` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 24 | `nad1` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 25 | `nad2` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 26 | `nad3` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 27 | `nad4` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 28 | `nad4l` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 29 | `nad5` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 30 | `nad6` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 31 | `trna_phe` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 32 | `trna_val` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 33 | `trna_leuuag` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 34 | `trna_leuuaa` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 35 | `trna_ile` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 36 | `trna_met` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 37 | `trna_thr` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 38 | `trna_pro` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 39 | `trna_lys` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 40 | `trna_asp` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 41 | `trna_glu` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 42 | `trna_sergcu` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 43 | `trna_seruga` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 44 | `trna_tyr` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 45 | `trna_cys` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 46 | `trna_trp` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 47 | `trna_ala` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 48 | `trna_asn` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 49 | `trna_gly` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 50 | `trna_arg` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 51 | `trna_his` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 52 | `trna_gln` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 53 | `manual_curation_notes` | `text` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 54 | `bankit` | `character varying` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 55 | `genbank_accession` | `character varying` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 56 | `og_num` | `integer` | yes | `(SUBSTRING(og_id FROM 3))::integer` |  |  |  |  |
| `mitogenome_data` | table | 57 | `annotation` | `character varying` | yes |  |  |  | yes |  |
| `mitogenome_data` | table | 58 | `date_submitted_genbank` | `date` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 59 | `avg_coverage` | `real` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 60 | `avg_base_coverage` | `real` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 61 | `atp6_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 62 | `atp8_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 63 | `cox1_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 64 | `cox2_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 65 | `cox3_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 66 | `cytb_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 67 | `nad1_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 68 | `nad2_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 69 | `nad3_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 70 | `nad4_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 71 | `nad4l_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 72 | `nad5_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 73 | `nad6_trans` | `integer` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 74 | `extra_genes` | `character varying` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 75 | `missing_genes` | `character varying` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 76 | `order_correct` | `character varying` | yes |  |  |  |  |  |
| `mitogenome_data` | table | 77 | `passed` | `character varying` | yes |  |  |  |  |  |
| `ont_library` | table | 1 | `ont_library_tube_id` | `text` | no |  | yes |  | yes |  |
| `ont_library` | table | 2 | `dna_id` | `text` | yes |  |  | public.dna_extraction(dna_id) |  |  |
| `ont_library` | table | 3 | `ont_num` | `integer` | yes |  |  |  |  |  |
| `ont_library` | table | 4 | `ont_status` | `text` | yes |  |  |  |  |  |
| `ont_library` | table | 5 | `library_date` | `text` | yes |  |  |  |  |  |
| `ont_library` | table | 6 | `library_id` | `text` | yes |  |  |  |  |  |
| `ont_library` | table | 7 | `library_method` | `text` | yes |  |  |  |  |  |
| `ont_library` | table | 8 | `library_type` | `text` | yes |  |  |  |  |  |
| `ont_library` | table | 9 | `est_loading_size` | `integer` | yes |  |  |  |  |  |
| `ont_library` | table | 10 | `ont_comments` | `text` | yes |  |  |  |  |  |
| `ont_library` | table | 11 | `og_id` | `text` | yes | `regexp_replace(dna_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)` |  |  |  |  |
| `ont_library` | table | 12 | `status_overwrite` | `character varying` | yes |  |  |  |  |  |
| `pacbio_library` | table | 1 | `pacbio_library_tube_id` | `text` | no |  | yes |  | yes |  |
| `pacbio_library` | table | 2 | `dna_id` | `text` | yes |  |  | public.dna_extraction(dna_id) |  |  |
| `pacbio_library` | table | 3 | `pacb_num` | `integer` | yes |  |  |  |  |  |
| `pacbio_library` | table | 4 | `pacb_status` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 5 | `library_method` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 6 | `library_date` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 7 | `library_id` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 8 | `dna_treatment` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 9 | `index_well` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 10 | `barcode` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 11 | `shear_femtol_id` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 12 | `shear_av_size` | `integer` | yes |  |  |  |  |  |
| `pacbio_library` | table | 13 | `seq_femto_id` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 14 | `seq_av_size` | `real` | yes |  |  |  |  |  |
| `pacbio_library` | table | 15 | `library_conc` | `real` | yes |  |  |  |  |  |
| `pacbio_library` | table | 16 | `comment` | `text` | yes |  |  |  |  |  |
| `pacbio_library` | table | 17 | `status_overwrite` | `character varying` | yes |  |  |  |  |  |
| `pacbio_library` | table | 18 | `og_id` | `text` | yes | `regexp_replace(dna_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)` |  |  |  |  |
| `raw_data` | table | 1 | `og_id` | `text` | yes |  |  |  |  |  |
| `raw_data` | table | 2 | `run_id` | `text` | no |  | yes |  | yes |  |
| `raw_data` | table | 3 | `lane_id` | `text` | no |  | yes |  | yes |  |
| `raw_data` | table | 4 | `filename` | `text` | no |  | yes |  | yes |  |
| `raw_data` | table | 5 | `og_num` | `integer` | yes | `(SUBSTRING(og_id FROM 3))::integer` |  |  |  |  |
| `raw_qc` | table | 1 | `og_id` | `text` | no |  | yes |  | yes |  |
| `raw_qc` | table | 2 | `homozygosity` | `numeric(5,2)` | yes |  |  |  |  |  |
| `raw_qc` | table | 3 | `heterozygosity` | `numeric(5,2)` | yes |  |  |  |  |  |
| `raw_qc` | table | 4 | `genomesize` | `bigint` | yes |  |  |  |  |  |
| `raw_qc` | table | 5 | `repeatsize` | `bigint` | yes |  |  |  |  |  |
| `raw_qc` | table | 6 | `uniquesize` | `bigint` | yes |  |  |  |  |  |
| `raw_qc` | table | 7 | `modelfit` | `numeric(5,2)` | yes |  |  |  |  |  |
| `raw_qc` | table | 8 | `errorrate` | `numeric(5,2)` | yes |  |  |  |  |  |
| `raw_qc` | table | 9 | `contam_reads` | `integer` | yes |  |  |  |  |  |
| `ref_genomes` | table | 1 | `og_id` | `text` | no |  | yes |  | yes |  |
| `ref_genomes` | table | 2 | `seq_date` | `text` | no |  | yes |  | yes |  |
| `ref_genomes` | table | 3 | `stage` | `integer` | no |  | yes |  | yes | Pulled from file names where 0=contig level, 1=scaffold level, 2=decontaminated scaffold, 3=curated final |
| `ref_genomes` | table | 4 | `haplotype` | `text` | no |  | yes |  | yes |  |
| `ref_genomes` | table | 5 | `num_contigs` | `integer` | yes |  |  |  |  |  |
| `ref_genomes` | table | 6 | `contig_n50` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 7 | `contig_n50_size_mb` | `numeric(10,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 8 | `num_scaffolds` | `integer` | yes |  |  |  |  |  |
| `ref_genomes` | table | 9 | `scaffold_n50` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 10 | `scaffold_n50_size_mb` | `numeric(10,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 11 | `largest_scaffold` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 12 | `largest_scaffold_size_mb` | `numeric(10,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 13 | `total_scaffold_length` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 14 | `total_scaffold_length_size_mb` | `numeric(10,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 15 | `gc_content_percent` | `numeric(5,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 16 | `dataset` | `text` | yes |  |  |  |  |  |
| `ref_genomes` | table | 17 | `complete` | `numeric(4,1)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 18 | `single_copy` | `numeric(4,1)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 19 | `multi_copy` | `numeric(4,1)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 20 | `fragmented` | `numeric(4,1)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 21 | `missing` | `numeric(4,1)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 22 | `n_markers` | `integer` | yes |  |  |  |  |  |
| `ref_genomes` | table | 23 | `internal_stop_codon_percent` | `numeric(5,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 24 | `scaffold_n50_bus` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 25 | `contigs_n50_bus` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 26 | `percent_gaps` | `numeric(5,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 27 | `number_of_scaffolds` | `integer` | yes |  |  |  |  |  |
| `ref_genomes` | table | 28 | `unique_k_mers_assembly` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 29 | `k_mers_total` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 30 | `qv` | `numeric(6,4)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 31 | `error` | `double precision` | yes |  |  |  |  |  |
| `ref_genomes` | table | 32 | `k_mer_set` | `text` | yes |  |  |  |  |  |
| `ref_genomes` | table | 33 | `solid_k_mers` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 34 | `total_k_mers` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 35 | `completeness` | `numeric(7,4)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 36 | `total` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 37 | `total_unmapped` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 38 | `total_single_sided_mapped` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 39 | `total_mapped` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 40 | `total_dups` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 41 | `total_nodups` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 42 | `cis` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 43 | `trans` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 54 | `hap2_chr_level_max_len` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 55 | `format` | `text` | yes |  |  |  |  |  |
| `ref_genomes` | table | 56 | `type` | `text` | yes |  |  |  |  |  |
| `ref_genomes` | table | 57 | `num_seqs` | `integer` | yes |  |  |  |  |  |
| `ref_genomes` | table | 58 | `sum_len` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 59 | `min_len` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 60 | `avg_len` | `numeric(20,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 61 | `max_len` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 62 | `num_chromosomes` | `integer` | yes |  |  |  |  |  |
| `ref_genomes` | table | 63 | `pct_assigned` | `numeric(5,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 64 | `pct_no_super` | `numeric(5,2)` | yes |  |  |  |  |  |
| `ref_genomes` | table | 65 | `num_seq_no_super` | `integer` | yes |  |  |  |  |  |
| `ref_genomes` | table | 66 | `max_len_no_super` | `bigint` | yes |  |  |  |  |  |
| `ref_genomes` | table | 67 | `version` | `text` | no |  | yes |  | yes |  |
| `ref_genomes` | table | 68 | `num_gaps` | `integer` | yes |  |  |  |  |  |
| `ref_genomes_assembly_uploads` | table | 1 | `og_id` | `text` | no |  | yes |  | yes |  |
| `ref_genomes_assembly_uploads` | table | 2 | `biosample` | `text` | yes |  |  |  |  |  |
| `ref_genomes_assembly_uploads` | table | 3 | `bioproject_umbrella` | `text` | yes |  |  |  |  |  |
| `ref_genomes_assembly_uploads` | table | 4 | `bioproject_hap1` | `text` | yes |  |  |  |  |  |
| `ref_genomes_assembly_uploads` | table | 5 | `bioproject_hap2` | `text` | yes |  |  |  |  |  |
| `ref_genomes_assembly_uploads` | table | 6 | `bioproject_rawdata` | `text` | yes |  |  |  |  |  |
| `ref_genomes_assembly_uploads` | table | 7 | `assembly_accession_hap1` | `text` | yes |  |  |  |  |  |
| `ref_genomes_assembly_uploads` | table | 8 | `assembly_accession_hap2` | `text` | yes |  |  |  |  |  |
| `ref_genomes_assembly_uploads` | table | 9 | `embargo_status` | `text` | yes |  |  |  |  |  |
| `ref_genomes_sra_uploads` | table | 1 | `srr_accession` | `text` | no |  | yes |  | yes |  |
| `ref_genomes_sra_uploads` | table | 2 | `og_id` | `text` | yes |  |  | public.ref_genomes_assembly_uploads(og_id) |  |  |
| `ref_genomes_sra_uploads` | table | 3 | `filenames` | `text` | yes |  |  |  |  |  |
| `ref_genomes_sra_uploads` | table | 4 | `data_type` | `text` | yes |  |  |  |  |  |
| `ref_genomes_sra_uploads` | table | 5 | `ncbi_status` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 1 | `rna_id` | `text` | no |  | yes |  | yes |  |
| `rna_extraction` | table | 2 | `tissue_id` | `text` | yes |  |  | public.tissue(tissue_id) |  |  |
| `rna_extraction` | table | 3 | `ext_num` | `integer` | yes |  |  |  |  |  |
| `rna_extraction` | table | 4 | `status` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 5 | `extraction_method` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 6 | `extraction_date` | `date` | yes |  |  |  |  |  |
| `rna_extraction` | table | 7 | `extraction_batch_id` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 8 | `final_buffer` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 9 | `volume` | `integer` | yes |  |  |  |  |  |
| `rna_extraction` | table | 10 | `qubit_conc` | `real` | yes |  |  |  |  |  |
| `rna_extraction` | table | 11 | `nano_drop_conc` | `real` | yes |  |  |  |  |  |
| `rna_extraction` | table | 12 | `ratio_260_280` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 13 | `ratio_260_230` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 14 | `total_yield` | `integer` | yes |  |  |  |  |  |
| `rna_extraction` | table | 15 | `tapestation_id` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 16 | `rna_dv200` | `real` | yes |  |  |  |  |  |
| `rna_extraction` | table | 17 | `rin` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 18 | `extraction_qc` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 19 | `comment` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 20 | `rna_freezer` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 21 | `rna_shelf` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 22 | `rna_rack` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 23 | `rna_level` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 24 | `rna_box` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 25 | `rna_notes` | `text` | yes |  |  |  |  |  |
| `rna_extraction` | table | 26 | `og_id` | `text` | yes | `regexp_replace(tissue_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)` |  |  |  |  |
| `rna_extraction` | table | 27 | `status_overwrite` | `character varying` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 1 | `rna_library_tube_id` | `text` | no |  | yes |  | yes |  |
| `rna_library_ilmn` | table | 2 | `rna_id` | `text` | yes |  |  | public.rna_extraction(rna_id) |  |  |
| `rna_library_ilmn` | table | 3 | `rna_num` | `integer` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 4 | `rna_status` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 5 | `library_method` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 6 | `library_date` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 7 | `library_id` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 8 | `library_size` | `integer` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 9 | `perc_product` | `real` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 10 | `library_qubit_conc` | `real` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 11 | `library_molarity` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 12 | `index_set` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 13 | `index_well` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 14 | `index_inx` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 15 | `kinnex_primers` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 16 | `kinnex_barcode` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 17 | `comments` | `text` | yes |  |  |  |  |  |
| `rna_library_ilmn` | table | 18 | `og_id` | `text` | yes | `regexp_replace(rna_id, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)` |  |  |  |  |
| `rna_library_ilmn` | table | 19 | `status_overwrite` | `character varying` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 1 | `rna_library_tube_id` | `character varying(50)` | no |  | yes |  | yes |  |
| `rna_library_kinx` | table | 2 | `rna_id` | `character varying(50)` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 3 | `rna_num` | `integer` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 4 | `rna_status` | `character varying(50)` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 5 | `library_method` | `character varying(100)` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 6 | `processing_comment` | `text` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 7 | `synthesis_date` | `date` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 8 | `part1_batch_id` | `character varying(50)` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 9 | `synthesis_conc` | `real` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 10 | `part2_batch_id` | `character varying(50)` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 11 | `final_qubit_conc` | `real` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 12 | `library_size` | `integer` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 13 | `kinnex_primers` | `character varying(20)` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 14 | `kinnex_barcode` | `character varying(20)` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 15 | `pool_id` | `character varying(50)` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 16 | `plate` | `integer` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 17 | `plate_location` | `character varying(5)` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 18 | `comments` | `text` | yes |  |  |  |  |  |
| `rna_library_kinx` | table | 19 | `created_at` | `timestamp with time zone` | yes | `now()` |  |  |  |  |
| `rna_library_kinx` | table | 20 | `updated_at` | `timestamp with time zone` | yes | `now()` |  |  |  |  |
| `rna_library_kinx` | table | 21 | `og_id` | `text` | yes | `regexp_replace((rna_id)::text, '^([^0-9]*[0-9]+).*$'::text, '\1'::text)` |  |  |  |  |
| `rna_library_kinx` | table | 22 | `status_overwrite` | `character varying` | yes |  |  |  |  |  |
| `rna_qc_kinnex` | table | 1 | `rna_tube_id` | `text` | no |  |  |  | yes |  |
| `rna_qc_kinnex` | table | 2 | `rna_tube_id_2` | `text` | yes |  |  |  |  |  |
| `rna_qc_kinnex` | table | 3 | `read_count` | `bigint` | yes |  |  |  |  |  |
| `rna_qc_kinnex` | table | 4 | `run_id` | `text` | yes |  |  |  | yes |  |
| `rna_qc_kinnex` | table | 5 | `read_length_mean` | `integer` | yes |  |  |  |  |  |
| `rna_qc_kinnex` | table | 6 | `read_length_n50` | `integer` | yes |  |  |  |  |  |
| `sample` | table | 1 | `og_id` | `text` | no |  | yes |  | yes | Ocean Genomes sample number that links through the whole database. |
| `sample` | table | 2 | `field_id` | `text` | yes |  |  |  |  |  |
| `sample` | table | 3 | `nominal_species_id` | `text` | yes |  |  |  |  |  |
| `sample` | table | 4 | `common_name` | `text` | yes |  |  |  |  |  |
| `sample` | table | 5 | `collector` | `text` | yes |  |  |  |  |  |
| `sample` | table | 6 | `contact` | `text` | yes |  |  |  |  |  |
| `sample` | table | 7 | `date_collected` | `date` | yes |  |  |  |  |  |
| `sample` | table | 8 | `sex` | `text` | yes |  |  |  |  |  |
| `sample` | table | 9 | `weight` | `text` | yes |  |  |  |  |  |
| `sample` | table | 10 | `lengthtl_and_lengthfl` | `text` | yes |  |  |  |  |  |
| `sample` | table | 11 | `country` | `text` | yes |  |  |  |  |  |
| `sample` | table | 12 | `state` | `text` | yes |  |  |  |  |  |
| `sample` | table | 13 | `location` | `text` | yes |  |  |  |  |  |
| `sample` | table | 14 | `latitude_collection` | `text` | yes |  |  |  |  |  |
| `sample` | table | 15 | `longitude_collection` | `text` | yes |  |  |  |  |  |
| `sample` | table | 16 | `depth_collection` | `text` | yes |  |  |  |  |  |
| `sample` | table | 17 | `collection_method` | `text` | yes |  |  |  |  |  |
| `sample` | table | 18 | `preservation_method` | `text` | yes |  |  |  |  |  |
| `sample` | table | 19 | `sample_condition` | `text` | yes |  |  |  |  |  |
| `sample` | table | 20 | `photo_voucher` | `text` | yes |  |  |  |  |  |
| `sample` | table | 21 | `photo_id` | `text` | yes |  |  |  |  |  |
| `sample` | table | 22 | `specimen_voucher` | `text` | yes |  |  |  |  |  |
| `sample` | table | 23 | `voucher_id` | `text` | yes |  |  |  |  |  |
| `sample` | table | 24 | `comments` | `text` | yes |  |  |  |  |  |
| `sample` | table | 25 | `priority` | `text` | yes |  |  |  |  |  |
| `sample` | table | 26 | `tissues` | `text` | yes |  |  |  |  |  |
| `sample` | table | 27 | `extracted` | `text` | yes |  |  |  |  |  |
| `sample` | table | 28 | `extraction_queue` | `text` | yes |  |  |  |  |  |
| `sample` | table | 29 | `ilmn` | `text` | yes |  |  |  |  |  |
| `sample` | table | 30 | `il_status` | `text` | yes |  |  |  |  |  |
| `sample` | table | 31 | `hifi` | `text` | yes |  |  |  |  |  |
| `sample` | table | 32 | `pb_status` | `text` | yes |  |  |  |  |  |
| `sample` | table | 33 | `hic` | `text` | yes |  |  |  |  |  |
| `sample` | table | 34 | `hic_status` | `text` | yes |  |  |  |  |  |
| `sample` | table | 35 | `nano` | `text` | yes |  |  |  |  |  |
| `sample` | table | 36 | `ont_num` | `text` | yes |  |  |  |  |  |
| `sample` | table | 37 | `rna` | `text` | yes |  |  |  |  |  |
| `sample` | table | 38 | `rna_status` | `text` | yes |  |  |  |  |  |
| `sample` | table | 39 | `ilrna` | `text` | yes |  |  |  |  |  |
| `sample` | table | 40 | `ilrna_status` | `text` | yes |  |  |  |  |  |
| `sample` | table | 41 | `assigned_species` | `text` | yes |  |  |  |  |  |
| `sample` | table | 42 | `eschmeyer_id` | `text` | yes |  |  |  |  |  |
| `sample` | table | 43 | `ncbi_sample_name` | `text` | yes |  |  |  |  |  |
| `sample` | table | 44 | `ncbi_biosample_id` | `text` | yes |  |  |  |  |  |
| `sample` | table | 45 | `hifi_lca_outcome` | `text` | yes |  |  |  |  | Not up to date - use lca_validation table |
| `sample` | table | 46 | `ncbi_id` | `text` | yes |  |  |  |  |  |
| `sample` | table | 47 | `tol_id` | `text` | yes |  |  |  |  |  |
| `sample` | table | 48 | `ncbi_bioproject_id_lvl_3_hifi` | `text` | yes |  |  |  |  |  |
| `sample` | table | 49 | `bioproject_id_haplotype_1` | `text` | yes |  |  |  |  |  |
| `sample` | table | 50 | `bioproject_id_haplotype_2` | `text` | yes |  |  |  |  |  |
| `sample` | table | 51 | `bioproject_sequencing_data` | `text` | yes |  |  |  |  |  |
| `sample` | table | 52 | `ncbi_assembly_upload` | `text` | yes |  |  |  |  |  |
| `sample` | table | 53 | `ncbi_raw_reads_upload` | `text` | yes |  |  |  |  |  |
| `sample` | table | 54 | `hifi_public` | `text` | yes |  |  |  |  |  |
| `sample` | table | 55 | `illumina_lca` | `text` | yes |  |  |  |  | Not up to date - use lca_validation table |
| `sample` | table | 56 | `ncbi_bioproject_id_draft` | `text` | yes |  |  |  |  |  |
| `sample` | table | 57 | `illumina_public` | `text` | yes |  |  |  |  |  |
| `sample` | table | 58 | `draft_sra_accessions` | `text` | yes |  |  |  |  |  |
| `sample` | table | 59 | `draft_assembly_accession` | `text` | yes |  |  |  |  |  |
| `sample` | table | 61 | `og_num` | `integer` | yes | `(SUBSTRING(og_id FROM 3))::integer` |  |  |  |  |
| `sample` | table | 62 | `project_id` | `text` | yes |  |  |  |  |  |
| `sample` | table | 63 | `workflow` | `character varying` | yes |  |  |  |  |  |
| `sample` | table | 64 | `illumina_sequencing` | `text` | yes |  |  |  |  | Require a Y for if this type of sequencing is to occur |
| `sample` | table | 65 | `hifi_sequencing` | `text` | yes |  |  |  |  | Require a Y for if this type of sequencing is to occur |
| `sample` | table | 66 | `hic_sequencing` | `text` | yes |  |  |  |  | Require a Y for if this type of sequencing is to occur |
| `sample` | table | 67 | `nanopore_sequencing` | `text` | yes |  |  |  |  | Require a Y for if this type of sequencing is to occur |
| `sample` | table | 68 | `rna_ilmn_sequencing` | `text` | yes |  |  |  |  | Require a Y for if this type of sequencing is to occur |
| `sample` | table | 69 | `rna_kinnex_sequencing` | `text` | yes |  |  |  |  | Require a Y for if this type of sequencing is to occur |
| `sample` | table | 70 | `rna_extraction` | `text` | yes |  |  |  |  | Require a Y for if this type of sequencing is to occur |
| `sample` | table | 71 | `summary_comments` | `character varying` | yes |  |  |  |  | comments on the status of the samples, different to the metadata comments in the comment column |
| `sample` | table | 72 | `embargo_status` | `character varying` | yes |  |  |  |  |  |
| `sequencing` | table | 1 | `sequencing_id` | `text` | no |  | yes |  | yes |  |
| `sequencing` | table | 2 | `og_id` | `text` | yes | `"substring"(sequencing_id, '([A-Z]{2}[0-9]+)'::text)` |  |  |  |  |
| `sequencing` | table | 3 | `rna_library_tube_id` | `text` | yes |  |  |  |  |  |
| `sequencing` | table | 4 | `illumina_library_tube_id` | `text` | yes |  |  | public.illumina_library(illumina_library_tube_id) |  |  |
| `sequencing` | table | 5 | `ont_library_tube_id` | `text` | yes |  |  | public.ont_library(ont_library_tube_id) |  |  |
| `sequencing` | table | 6 | `pacbio_library_tube_id` | `text` | yes |  |  | public.pacbio_library(pacbio_library_tube_id) |  |  |
| `sequencing` | table | 7 | `hic_library_tube_id` | `text` | yes |  |  | public.hic_library(hic_library_tube_id) |  |  |
| `sequencing` | table | 8 | `technology` | `text` | yes |  |  |  |  |  |
| `sequencing` | table | 9 | `instrument` | `text` | yes |  |  |  |  |  |
| `sequencing` | table | 10 | `run_date` | `text` | yes |  |  |  |  |  |
| `sequencing` | table | 11 | `run_id` | `text` | yes |  |  |  |  |  |
| `sequencing` | table | 12 | `seq_date` | `text` | yes | `split_part(run_id, '_'::text, 2)` |  |  |  |  |
| `sequencing` | table | 13 | `cell_id` | `text` | yes |  |  |  |  |  |
| `sequencing` | table | 14 | `smrt_num` | `integer` | yes |  |  |  |  |  |
| `sequencing` | table | 15 | `seq_comments` | `text` | yes |  |  |  |  |  |
| `sequencing` | table | 16 | `seq_type` | `text` | yes |  |  |  |  |  |
| `sequencing` | table | 17 | `design_no` | `integer` | yes |  |  |  |  |  |
| `sequencing` | table | 18 | `og_num` | `integer` | yes | `("substring"(sequencing_id, '^OG([0-9]+)'::text))::integer` |  |  |  |  |
| `species` | table | 1 | `species` | `text` | no |  | yes |  | yes |  |
| `species` | table | 2 | `class` | `text` | yes |  |  |  |  |  |
| `species` | table | 3 | `ordr` | `text` | yes |  |  |  |  |  |
| `species` | table | 4 | `family` | `text` | yes |  |  |  |  |  |
| `species` | table | 5 | `genus` | `text` | yes |  |  |  |  |  |
| `species` | table | 6 | `epithet` | `text` | yes |  |  |  |  |  |
| `species` | table | 7 | `afd_common_name` | `text` | yes |  |  |  |  |  |
| `species` | table | 8 | `family_common_name` | `text` | yes |  |  |  |  |  |
| `species` | table | 9 | `ncbi_taxon_id` | `integer` | yes |  |  |  |  |  |
| `species` | table | 10 | `synonym` | `text` | yes |  |  |  |  |  |
| `species` | table | 11 | `specimen_tol_id` | `text` | yes |  |  |  |  |  |
| `species` | table | 12 | `sequencing_status` | `text` | yes |  |  |  |  |  |
| `species` | table | 13 | `ont` | `text` | yes |  |  |  |  |  |
| `species` | table | 14 | `hifi` | `text` | yes |  |  |  |  |  |
| `species` | table | 15 | `hic` | `text` | yes |  |  |  |  |  |
| `species` | table | 16 | `draft_sequencing_status` | `text` | yes |  |  |  |  |  |
| `species` | table | 17 | `illumina` | `text` | yes |  |  |  |  |  |
| `species` | table | 18 | `draft_genome_bioproject_id` | `text` | yes |  |  |  |  |  |
| `species` | table | 19 | `genome_available` | `text` | yes |  |  |  |  |  |
| `species` | table | 20 | `internal_aus_status_fishbase` | `text` | yes |  |  |  |  |  |
| `species` | table | 21 | `cites_listing` | `text` | yes |  |  |  |  |  |
| `species` | table | 22 | `iucn_code` | `text` | yes |  |  |  |  |  |
| `species` | table | 23 | `iucn_assessment` | `text` | yes |  |  |  |  |  |
| `species` | table | 24 | `iucn_dateassessed` | `text` | yes |  |  |  |  |  |
| `species` | table | 25 | `epbc` | `text` | yes |  |  |  |  |  |
| `species` | table | 26 | `internal_first_in_family` | `text` | yes |  |  |  |  |  |
| `species` | table | 27 | `internal_first_in_genus` | `text` | yes |  |  |  |  |  |
| `species` | table | 28 | `internal_conservation_value` | `text` | yes |  |  |  |  |  |
| `species` | table | 29 | `internal_research` | `text` | yes |  |  |  |  |  |
| `species` | table | 30 | `internal_endemic` | `text` | yes |  |  |  |  |  |
| `species` | table | 31 | `sequencing_priority` | `text` | yes |  |  |  |  |  |
| `species` | table | 32 | `collaboration` | `text` | yes |  |  |  |  |  |
| `species` | table | 33 | `comments` | `text` | yes |  |  |  |  |  |
| `species` | table | 34 | `lab_database_status` | `text` | yes |  |  |  |  |  |
| `species_ncbi_assembly` | table | 1 | `assembly_accession` | `text` | no |  | yes |  | yes |  |
| `species_ncbi_assembly` | table | 2 | `species` | `text` | no |  |  | public.species(species) | yes |  |
| `species_ncbi_assembly` | table | 3 | `ncbi_taxon_id` | `integer` | no |  |  |  |  |  |
| `species_ncbi_assembly` | table | 4 | `assembly_name` | `text` | yes |  |  |  |  |  |
| `species_ncbi_assembly` | table | 5 | `assembly_level` | `text` | yes |  |  |  |  |  |
| `species_ncbi_assembly` | table | 6 | `total_sequence_length` | `bigint` | yes |  |  |  |  |  |
| `species_ncbi_assembly` | table | 7 | `is_refseq` | `boolean` | no | `false` |  |  |  |  |
| `species_ncbi_assembly` | table | 8 | `is_representative` | `boolean` | no | `false` |  |  |  |  |
| `species_ncbi_assembly` | table | 9 | `is_chosen` | `boolean` | no | `false` |  |  |  |  |
| `species_ncbi_assembly` | table | 10 | `release_date` | `date` | yes |  |  |  |  |  |
| `species_ncbi_assembly` | table | 11 | `retrieved_at` | `timestamp without time zone` | no | `now()` |  |  |  |  |
| `tissue` | table | 1 | `tissue_id` | `text` | no |  | yes |  | yes |  |
| `tissue` | table | 2 | `og_id` | `text` | yes |  |  | public.sample(og_id) |  |  |
| `tissue` | table | 3 | `field_id` | `text` | yes |  |  |  |  |  |
| `tissue` | table | 4 | `alt_id` | `text` | yes |  |  |  |  |  |
| `tissue` | table | 5 | `tissue` | `text` | yes |  |  |  |  |  |
| `tissue` | table | 6 | `extracted` | `integer` | yes |  |  |  |  |  |
| `tissue` | table | 7 | `freezer` | `text` | yes |  |  |  |  |  |
| `tissue` | table | 8 | `shelf` | `integer` | yes |  |  |  |  |  |
| `tissue` | table | 9 | `rack` | `integer` | yes |  |  |  |  |  |
| `tissue` | table | 10 | `level` | `text` | yes |  |  |  |  |  |
| `tissue` | table | 11 | `box` | `text` | yes |  |  |  |  |  |
| `tissue` | table | 12 | `comment` | `text` | yes |  |  |  |  |  |
| `tissue` | table | 13 | `og_num` | `integer` | yes | `(SUBSTRING(og_id FROM 3))::integer` |  |  |  |  |
| `coverage_summary` | view | 1 | `og_id` | `text` | yes |  |  |  |  |  |
| `coverage_summary` | view | 2 | `genomesize` | `bigint` | yes |  |  |  |  |  |
| `coverage_summary` | view | 3 | `total_hic_yield_gb` | `numeric` | yes |  |  |  |  |  |
| `coverage_summary` | view | 4 | `total_hifi_yield_gb` | `numeric` | yes |  |  |  |  |  |
| `coverage_summary` | view | 5 | `hifi_coverage` | `numeric` | yes |  |  |  |  |  |
| `coverage_summary` | view | 6 | `hic_coverage` | `numeric` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 1 | `og_id` | `text` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 2 | `og_num` | `integer` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 3 | `collector` | `text` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 4 | `embargo_status` | `character varying` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 5 | `validated_species_name` | `text` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 6 | `nominal_species_id` | `text` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 7 | `common_name` | `text` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 8 | `field_id` | `text` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 9 | `contact` | `text` | yes |  |  |  |  |  |
| `embargo_assignment_view` | view | 10 | `date_collected` | `date` | yes |  |  |  |  |  |
| `filtered_lca_view` | view | 1 | `og_id_flv` | `text` | yes |  |  |  |  |  |
| `filtered_lca_view` | view | 2 | `tech` | `text` | yes |  |  |  |  |  |
| `filtered_lca_view` | view | 3 | `seq_date` | `text` | yes |  |  |  |  |  |
| `filtered_lca_view` | view | 4 | `code` | `text` | yes |  |  |  |  |  |
| `filtered_lca_view` | view | 5 | `annotation` | `text` | yes |  |  |  |  |  |
| `filtered_lca_view` | view | 6 | `filtered_12s` | `text` | yes |  |  |  |  |  |
| `filtered_lca_view` | view | 7 | `filtered_16s` | `text` | yes |  |  |  |  |  |
| `filtered_lca_view` | view | 8 | `filtered_co1` | `text` | yes |  |  |  |  |  |
| `goat_project_metadata_v1` | view | 1 | `project_name` | `text` | yes |  |  |  |  |  |
| `goat_project_metadata_v1` | view | 2 | `project_acronym` | `text` | yes |  |  |  |  |  |
| `goat_project_metadata_v1` | view | 3 | `subproject_name` | `text` | yes |  |  |  |  |  |
| `goat_project_metadata_v1` | view | 4 | `bioproject_id` | `text` | yes |  |  |  |  |  |
| `goat_project_metadata_v1` | view | 5 | `primary_contact` | `text` | yes |  |  |  |  |  |
| `goat_project_metadata_v1` | view | 6 | `primary_contact_institution` | `text` | yes |  |  |  |  |  |
| `goat_project_metadata_v1` | view | 7 | `public_contact_email` | `text` | yes |  |  |  |  |  |
| `goat_project_metadata_v1` | view | 8 | `date_of_last_update` | `date` | yes |  |  |  |  |  |
| `goat_project_metadata_v1` | view | 9 | `schema_version` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 1 | `ncbi_taxon_id` | `integer` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 2 | `family` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 3 | `species` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 4 | `subspecies_epithet` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 5 | `target_list_status` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 6 | `sampling_status` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 7 | `sequencing_status` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 8 | `genome_publication` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 9 | `primary_project` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 10 | `ebp_collaborator_acronyms` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 11 | `contributing_project_lab` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 12 | `collected_by` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 13 | `priority_flags` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 14 | `common_name` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 15 | `synonym` | `text` | yes |  |  |  |  |  |
| `goat_species_v1` | view | 16 | `assigned_sequencing_center` | `text` | yes |  |  |  |  |  |
| `lca_pivot_view` | view | 1 | `og_num` | `integer` | yes |  |  |  |  |  |
| `lca_pivot_view` | view | 2 | `og_id_lp` | `text` | yes |  |  |  |  |  |
| `lca_pivot_view` | view | 3 | `tech` | `text` | yes |  |  |  |  |  |
| `lca_pivot_view` | view | 4 | `seq_date` | `text` | yes |  |  |  |  |  |
| `lca_pivot_view` | view | 5 | `code` | `text` | yes |  |  |  |  |  |
| `lca_pivot_view` | view | 6 | `annotation` | `text` | yes |  |  |  |  |  |
| `lca_pivot_view` | view | 7 | `s12_lca` | `text` | yes |  |  |  |  |  |
| `lca_pivot_view` | view | 8 | `s16_lca` | `text` | yes |  |  |  |  |  |
| `lca_pivot_view` | view | 9 | `co1_lca` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 1 | `og_id_lr` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 2 | `tech` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 3 | `seq_date` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 4 | `code` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 5 | `annotation` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 6 | `nominal_species_id` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 7 | `s12_lca` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 8 | `s16_lca` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 9 | `co1_lca` | `text` | yes |  |  |  |  |  |
| `lca_results_view` | view | 10 | `validation_status` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 1 | `og_num` | `integer` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 2 | `proj_id` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 3 | `og_id` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 4 | `tech` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 5 | `seq_date` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 6 | `code` | `character varying` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 7 | `annotation` | `character varying` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 8 | `s12_lca` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 9 | `s16_lca` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 10 | `co1_lca` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 11 | `validation_status` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 12 | `nom_id` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 13 | `validated_species_name` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 14 | `validator` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 15 | `validator_2` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 16 | `lca_taxon_ranks` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 17 | `lca_orders` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 18 | `lca_families` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 19 | `lca_genera` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 20 | `lca_specific_epiphets` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 21 | `nom_id_in_results` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 22 | `comment` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 23 | `data_release` | `character varying` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 24 | `filtered_12s` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 25 | `filtered_16s` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 26 | `filtered_co1` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 27 | `photo_id_sv` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 28 | `photo_vouch_sv` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 29 | `specimen_vouch_sv` | `text` | yes |  |  |  |  |  |
| `lca_validation_report_view` | view | 30 | `vouch_id_sv` | `text` | yes |  |  |  |  |  |
| `sample_view` | view | 1 | `og_id_sv` | `text` | yes |  |  |  |  |  |
| `sample_view` | view | 2 | `proj_id` | `text` | yes |  |  |  |  |  |
| `sample_view` | view | 3 | `nom_id` | `text` | yes |  |  |  |  |  |
| `sample_view` | view | 4 | `photo_id_sv` | `text` | yes |  |  |  |  |  |
| `sample_view` | view | 5 | `photo_vouch_sv` | `text` | yes |  |  |  |  |  |
| `sample_view` | view | 6 | `specimen_vouch_sv` | `text` | yes |  |  |  |  |  |
| `sample_view` | view | 7 | `vouch_id_sv` | `text` | yes |  |  |  |  |  |
| `summary` | view | 1 | `og_num` | `integer` | yes |  |  |  |  |  |
| `summary` | view | 2 | `og_id` | `text` | yes |  |  |  |  |  |
| `summary` | view | 3 | `project_id` | `text` | yes |  |  |  |  |  |
| `summary` | view | 4 | `workflow` | `character varying` | yes |  |  |  |  |  |
| `summary` | view | 5 | `priority` | `text` | yes |  |  |  |  |  |
| `summary` | view | 6 | `tissues` | `bigint` | yes |  |  |  |  |  |
| `summary` | view | 7 | `extracted` | `bigint` | yes |  |  |  |  |  |
| `summary` | view | 8 | `dna_extraction_status` | `text` | yes |  |  |  |  |  |
| `summary` | view | 9 | `illumina_sequencing` | `text` | yes |  |  |  |  |  |
| `summary` | view | 10 | `illumina_status` | `text` | yes |  |  |  |  |  |
| `summary` | view | 11 | `hifi_sequencing` | `text` | yes |  |  |  |  |  |
| `summary` | view | 12 | `pacbio_status` | `text` | yes |  |  |  |  |  |
| `summary` | view | 13 | `hic_sequencing` | `text` | yes |  |  |  |  |  |
| `summary` | view | 14 | `hic_status` | `text` | yes |  |  |  |  |  |
| `summary` | view | 15 | `nanopore_sequencing` | `text` | yes |  |  |  |  |  |
| `summary` | view | 16 | `nanopore_status` | `text` | yes |  |  |  |  |  |
| `summary` | view | 17 | `rna_extraction` | `text` | yes |  |  |  |  |  |
| `summary` | view | 18 | `rna_extraction_status` | `text` | yes |  |  |  |  |  |
| `summary` | view | 19 | `rna_ilmn_sequencing` | `text` | yes |  |  |  |  |  |
| `summary` | view | 20 | `rna_ilmn_status` | `text` | yes |  |  |  |  |  |
| `summary` | view | 21 | `rna_kinnex_sequencing` | `text` | yes |  |  |  |  |  |
| `summary` | view | 22 | `rna_kinnex_status` | `character varying` | yes |  |  |  |  |  |
| `summary` | view | 23 | `ilmn_validated_species_name` | `text` | yes |  |  |  |  |  |
| `summary` | view | 24 | `hifi_validated_species_name` | `text` | yes |  |  |  |  |  |
| `summary` | view | 25 | `hic_validated_species_name` | `text` | yes |  |  |  |  |  |
| `summary` | view | 26 | `field_id` | `text` | yes |  |  |  |  |  |
| `summary` | view | 27 | `nominal_species_id` | `text` | yes |  |  |  |  |  |
| `summary` | view | 28 | `common_name` | `text` | yes |  |  |  |  |  |
| `summary` | view | 29 | `collector` | `text` | yes |  |  |  |  |  |
| `summary` | view | 30 | `contact` | `text` | yes |  |  |  |  |  |
| `summary` | view | 31 | `summary_comments` | `character varying` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 1 | `og_id` | `text` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 2 | `seq_date` | `text` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 3 | `species` | `text` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 4 | `ncbi_taxon_id` | `integer` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 5 | `estimated_bp` | `bigint` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 6 | `ncbi_bp` | `bigint` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 7 | `estimated_over_ncbi` | `numeric` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 8 | `assembly_accession` | `text` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 9 | `assembly_level` | `text` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 10 | `is_refseq` | `boolean` | yes |  |  |  |  |  |
| `v_genome_size_comparison` | view | 11 | `is_representative` | `boolean` | yes |  |  |  |  |  |
