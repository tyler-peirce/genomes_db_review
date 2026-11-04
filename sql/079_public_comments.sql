-- 079_public_comments.sql -- Comments on the rest of public: every base-table column outside the
-- Phase R/RG tables (078), the tables and views that had no comment, and every column of the
-- contract and reporting views.
--
-- Record: docs/r_rg_docs_record.md. Backlog: database_review.md §10, "Add comments across the
-- whole database"; Phase G item 4.
--
-- Sources, each read at the commit named in 078's header, plus:
--   OceanOmics-Database  origin/main  547b53f21623  name_convert_v2.py (workbook header -> column),
--                                                   import_v2.py, v2_value_rules.py
--   OceanOmics-OceanGenomes-Draft-Genomes  scripts/taxonomy/load_taxonomy.py (species)
--   the headers of 001-077 and the v2 design review.
-- A lab column's comment names the workbook sheet and header it is imported from, so a reader
-- can find the cell; the header usually carries the unit.
--
-- Not commented here, on purpose:
--   - master_species, master_species_genome, og_priority_log, og_workflow_*: OceanGenom_Web's
--     tables, documented by their owner;
--   - pre_v*_archive: being dropped (V.7, R.8, RG.7);
--   - the columns of compatibility views (draft_genomes, mitogenome_data, ref_genomes*, lca*,
--     raw_qc, *_reads_qc, blast_filtered_lca) and of the v_*_browse views. Their columns are the
--     base tables' columns, documented there; their table comments say which base tables.
--
-- The four open questions (database_review.md §11 Q1 species authority, Q2 sample status
-- columns, Q5 sequencing grain, Q6 GoaT contract) do not block this. The columns they touch say
-- what is known now and end "Meaning undecided: §11 Q<n>"; each answer becomes a small migration
-- that removes that sentence.
--
-- Also corrected: comments 036-048 wrote while the v2 import was being built, which now
-- describe it as future or broken (status_overwrite, synthesis_conc, perc_product, the sample
-- table comment).
--
-- Comments only. COMMENT ON replaces, so a replay is a no-op.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('public.library') IS NULL OR to_regclass('public.mito_annotation') IS NULL THEN
    RAISE EXCEPTION '079 needs the v2 tables (048) and the Phase R tables (072)';
  END IF;
END
$pre$;

-- Specimens and tissue -----------------------------------------------------------------------

COMMENT ON TABLE sample IS
  'One row per specimen. Source: the 1.MetaData sheet (import_v2.py). The planning columns '
  '(workflow, priority, ilmn ... ilrna) are kept in the database, not read from the workbook '
  '(2026-10-28); the submission columns are written by the ENA pipelines.';
COMMENT ON COLUMN sample.og_id IS 'Specimen id, OG<number>. 1.MetaData "Specimen ID". Every lab, assembly and submission table hangs off it.';
COMMENT ON COLUMN sample.project_id IS '1.MetaData "Project ID".';
COMMENT ON COLUMN sample.field_id IS 'The collector''s own identifier. 1.MetaData "Field Identifier".';
COMMENT ON COLUMN sample.nominal_species_id IS 'The species name the specimen arrived as. 1.MetaData "Nominal Species ID". Free text, not validated against species on import (backlog item 8); the LCA validates it later (mito_lca_validation). Meaning undecided: §11 Q1 (which species table it should match).';
COMMENT ON COLUMN sample.common_name IS '1.MetaData "Common name/s".';
COMMENT ON COLUMN sample.collector IS 'Who collected the specimen. 1.MetaData "Collector".';
COMMENT ON COLUMN sample.contact IS '1.MetaData "Contact".';
COMMENT ON COLUMN sample.date_collected IS '1.MetaData "Date_Collected" (an Excel date serial in the sheet).';
COMMENT ON COLUMN sample.sex IS '1.MetaData "Sex": F, M, Unknown, TBA, or blank. Not normalised.';
COMMENT ON COLUMN sample.weight IS 'Weight, g. 1.MetaData "Weight (g)".';
COMMENT ON COLUMN sample.country IS '1.MetaData "Country".';
COMMENT ON COLUMN sample.state IS '1.MetaData "State".';
COMMENT ON COLUMN sample.location IS '1.MetaData "Location".';
COMMENT ON COLUMN sample.latitude_collection IS 'Decimal degrees. 1.MetaData "Latitude_Collection"; DMS and Excel-serial values are converted (value_conversions).';
COMMENT ON COLUMN sample.longitude_collection IS 'Decimal degrees. 1.MetaData "Longitude_Collection"; converted as latitude is.';
COMMENT ON COLUMN sample.collection_method IS '1.MetaData "Collection_Method".';
COMMENT ON COLUMN sample.preservation_method IS 'Specimen-level preservation. 1.MetaData "Preservation_Method". Tissue-level is tissue.preservation.';
COMMENT ON COLUMN sample.sample_condition IS '1.MetaData "Sample_Condition".';
COMMENT ON COLUMN sample.sample_condition_upon_preservation IS '1.MetaData "Sample Condition upon preservation".';
COMMENT ON COLUMN sample.photo_voucher IS '1.MetaData "Photo_Voucher".';
COMMENT ON COLUMN sample.photo_id IS '1.MetaData "Photo_Voucher_Accession_Details".';
COMMENT ON COLUMN sample.specimen_voucher IS '1.MetaData "Specimen_Voucher".';
COMMENT ON COLUMN sample.voucher_id IS '1.MetaData "Specimen_Voucher_Accession_details".';
COMMENT ON COLUMN sample.ethics_permit IS '1.MetaData "Ethics_Permit".';
COMMENT ON COLUMN sample.collection_permit IS '1.MetaData "Collection_Permit".';
COMMENT ON COLUMN sample.import_permit IS '1.MetaData "Import_Permit".';
COMMENT ON COLUMN sample.cultural_significance IS '1.MetaData "Cultural_Significance".';
COMMENT ON COLUMN sample.cites IS 'CITES listing. 1.MetaData "CITES".';
COMMENT ON COLUMN sample.cms IS 'Convention on Migratory Species listing. 1.MetaData "CMS".';
COMMENT ON COLUMN sample.iucn IS 'IUCN Red List status. 1.MetaData "IUCN".';
COMMENT ON COLUMN sample.epbc IS 'EPBC Act listing. 1.MetaData "EPBC".';
COMMENT ON COLUMN sample.comments IS '1.MetaData "Comments".';
COMMENT ON COLUMN sample.workflow IS 'Planned workflow: Draft, Reference, Resequence, Metabarcoding, Not assigned. Set in OceanGenom_Web (Assign; og_workflow_assignment_log). Meaning undecided: §11 Q2.';
COMMENT ON COLUMN sample.priority IS 'Priority: Immediate, Completed, Draft, HOLD, Not proceeding, Low. Set in OceanGenom_Web (og_priority_log). Meaning undecided: §11 Q2.';
COMMENT ON COLUMN sample.assigned_species IS 'Species name assigned after identification. No current writer found; loaded at the v2 backfill. Meaning undecided: §11 Q1.';
COMMENT ON COLUMN sample.eschmeyer_id IS 'Eschmeyer''s Catalog of Fishes id. 1 row; no current writer found.';
COMMENT ON COLUMN sample.ncbi_sample_name IS 'Sample name used at NCBI. 5 rows; no current writer found.';
COMMENT ON COLUMN sample.ncbi_biosample_id IS 'The specimen''s BioSample (SAMN... at NCBI, or SAMEA...), shared by draft, ref and mito submissions. Written blank-only by ENA-draft-genomes step 06 and ENA-ref-genomes step 09.';
COMMENT ON COLUMN sample.hifi_lca_outcome IS 'Outcome of the species check on the HiFi assembly, e.g. Not validated. No current writer found.';
COMMENT ON COLUMN sample.ncbi_id IS 'NCBI Taxonomy id of the species, as text (e.g. 379402.0, an Excel float). No current writer found.';
COMMENT ON COLUMN sample.tol_id IS 'Tree of Life id (e.g. fLutVit1). No current writer found.';
COMMENT ON COLUMN sample.ncbi_bioproject_id_lvl_3_hifi IS 'Umbrella BioProject of the reference genome. Written blank-only by ENA-ref-genomes step 09.';
COMMENT ON COLUMN sample.bioproject_id_haplotype_1 IS 'BioProject of haplotype 1. ENA-ref-genomes step 09, blank-only. ref_submission_haplotype holds the same per haplotype.';
COMMENT ON COLUMN sample.bioproject_id_haplotype_2 IS 'BioProject of haplotype 2. ENA-ref-genomes step 09, blank-only.';
COMMENT ON COLUMN sample.bioproject_sequencing_data IS 'BioProject of the raw reads. ENA-ref-genomes step 09, blank-only.';
COMMENT ON COLUMN sample.ncbi_assembly_upload IS 'Free-text assembly upload state (e.g. completed). No current writer found; ref_submission is the structured record.';
COMMENT ON COLUMN sample.ncbi_raw_reads_upload IS 'Free-text note of which reads were uploaded (e.g. DNA + HiC + ONT). No current writer found; ref_sra_upload is the structured record.';
COMMENT ON COLUMN sample.hifi_public IS '8 rows; no current writer found.';
COMMENT ON COLUMN sample.illumina_lca IS 'Outcome of the species check on the Illumina data, e.g. Not validated. No current writer found.';
COMMENT ON COLUMN sample.ncbi_bioproject_id_draft IS 'BioProject of the draft genome. No current writer found; draft_submission is the structured record.';
COMMENT ON COLUMN sample.draft_sra_accessions IS 'Run accessions of the draft reads. No current writer found; draft_submission.sra_accession is the structured record.';
COMMENT ON COLUMN sample.draft_assembly_accession IS 'Accession of the draft assembly. No current writer found; draft_submission.assembly_accession is the structured record.';
COMMENT ON COLUMN sample.embargo_status IS 'Release or Embargo: whether this specimen''s data may be made public. Set in OceanGenom_Web through embargo_assignment_view; read by the ENA pipelines.';

COMMENT ON COLUMN tissue.tissue_id IS 'Tissue id, OG<number><tissue letter>[<n>] (e.g. OG2270G2). 2.Tissue "Sample ID". Parent of extractions and lysates.';
COMMENT ON COLUMN tissue.alt_id IS '2.Tissue "Alt ID".';
COMMENT ON COLUMN tissue.tissue IS 'Tissue type: Fin Clip, Eye, Other, Unknown... 2.Tissue "Tissue". Not normalised.';
COMMENT ON COLUMN tissue.extracted IS 'Times this tissue has been extracted, as the lab records it. 2.Tissue "Extracted".';
COMMENT ON COLUMN tissue.freezer IS '2.Tissue "Freezer".';
COMMENT ON COLUMN tissue.shelf IS '2.Tissue "Shelf".';
COMMENT ON COLUMN tissue.rack IS '2.Tissue "Rack".';
COMMENT ON COLUMN tissue.level IS '2.Tissue "Level".';
COMMENT ON COLUMN tissue.box IS '2.Tissue "Box Label".';
COMMENT ON COLUMN tissue.comment IS '2.Tissue "Comment".';

-- Extractions --------------------------------------------------------------------------------

COMMENT ON COLUMN dna_extraction.dna_id IS 'DNA tube id. 3.DNAExtractions "Tube ID".';
COMMENT ON COLUMN dna_extraction.tissue_id IS 'The tissue extracted (FK to tissue). "Sample ID".';
COMMENT ON COLUMN dna_extraction.ext_num IS 'Attempt number for this tissue. "#". With tissue_id, the attempt key.';
COMMENT ON COLUMN dna_extraction.status IS 'Workbook "Status", free text (Extracted, Hold, For review...). Not normalised (Phase H).';
COMMENT ON COLUMN dna_extraction.status_overwrite IS 'Lab flag marking which extraction to report when a tissue has several. "Status Overwrite"; the workbook holds only Y, stored as true. Read by summary (backlog item 10 removes that use).';
COMMENT ON COLUMN dna_extraction.extraction_method IS '"Extraction Method".';
COMMENT ON COLUMN dna_extraction.extraction_date IS '"Extraction Date".';
COMMENT ON COLUMN dna_extraction.extraction_batch_id IS '"Extraction Batch ID".';
COMMENT ON COLUMN dna_extraction.final_buffer IS '"Final Buffer".';
COMMENT ON COLUMN dna_extraction.volume IS 'uL. "Volume (uL)".';
COMMENT ON COLUMN dna_extraction.qubit_conc IS 'ng/uL. "Qubit Conc. (ng/uL)".';
COMMENT ON COLUMN dna_extraction.nano_drop_conc IS 'ng/uL. "NanoDrop Conc. (ng/uL)".';
COMMENT ON COLUMN dna_extraction.ratio_260_280 IS 'A260/A280 purity ratio. "260/280".';
COMMENT ON COLUMN dna_extraction.ratio_260_230 IS 'A260/A230 purity ratio. "260/230".';
COMMENT ON COLUMN dna_extraction.ratioqubit_nanodrop IS 'Qubit:NanoDrop ratio. Historical values only: no workbook header maps to it (name_convert_v2.py).';
COMMENT ON COLUMN dna_extraction.total_yield IS 'ng. "Total Yield (ng)".';
COMMENT ON COLUMN dna_extraction.gdna_femtol_id IS 'Femto Pulse run id for the gDNA size check. "gDNA Femto ID".';
COMMENT ON COLUMN dna_extraction.av_size IS 'Mean fragment size, bp. "Average size (bp)".';
COMMENT ON COLUMN dna_extraction.extraction_qc IS '"Pass / Fail QC": Pass, PASS, pass, MAYBE... Not normalised.';
COMMENT ON COLUMN dna_extraction.comment IS '"Comment".';
COMMENT ON COLUMN dna_extraction.dna_freezer IS '"DNA Archives Freezer".';
COMMENT ON COLUMN dna_extraction.dna_shelf IS 'Archive shelf. "Shelf".';
COMMENT ON COLUMN dna_extraction.dna_rack IS 'Archive rack. "Rack".';
COMMENT ON COLUMN dna_extraction.dna_level IS 'Archive level. "Level".';
COMMENT ON COLUMN dna_extraction.dna_box IS 'Archive box. "Box Label".';
COMMENT ON COLUMN dna_extraction.dna_notes IS '"Notes".';

COMMENT ON COLUMN rna_extraction.rna_id IS 'RNA tube id. 3.RNAExtractions "Tube ID".';
COMMENT ON COLUMN rna_extraction.tissue_id IS 'The tissue extracted (FK to tissue). "Sample ID".';
COMMENT ON COLUMN rna_extraction.ext_num IS 'Attempt number for this tissue. "#".';
COMMENT ON COLUMN rna_extraction.status IS 'Workbook "Status", free text. Not normalised (Phase H).';
COMMENT ON COLUMN rna_extraction.extraction_method IS '"Extraction Method".';
COMMENT ON COLUMN rna_extraction.extraction_date IS '"Extraction Date".';
COMMENT ON COLUMN rna_extraction.extraction_batch_id IS '"Extraction Batch ID".';
COMMENT ON COLUMN rna_extraction.final_buffer IS '"Final Buffer".';
COMMENT ON COLUMN rna_extraction.volume IS 'uL. "Volume (uL)".';
COMMENT ON COLUMN rna_extraction.qubit_conc IS 'ng/uL. "Qubit Conc. (ng/uL)".';
COMMENT ON COLUMN rna_extraction.nano_drop_conc IS 'ng/uL. "NanoDrop Conc. (ng/uL)".';
COMMENT ON COLUMN rna_extraction.ratio_260_280 IS 'A260/A280 purity ratio. "260/280".';
COMMENT ON COLUMN rna_extraction.ratio_260_230 IS 'A260/A230 purity ratio. "260/230".';
COMMENT ON COLUMN rna_extraction.total_yield IS 'ng. "Total Yield (ng)".';
COMMENT ON COLUMN rna_extraction.tapestation_id IS '"TapeStation Run ID".';
COMMENT ON COLUMN rna_extraction.rna_dv200 IS '% of RNA fragments over 200 nt. "RNA DV200".';
COMMENT ON COLUMN rna_extraction.rin IS 'RNA integrity number (1-10). "RIN".';
COMMENT ON COLUMN rna_extraction.extraction_qc IS '"Pass / Fail QC". Not normalised.';
COMMENT ON COLUMN rna_extraction.comment IS '"Comment".';
COMMENT ON COLUMN rna_extraction.rna_freezer IS '"RNA Archives Freezer".';
COMMENT ON COLUMN rna_extraction.rna_shelf IS 'Archive shelf. "Shelf".';
COMMENT ON COLUMN rna_extraction.rna_rack IS 'Archive rack. "Rack".';
COMMENT ON COLUMN rna_extraction.rna_level IS 'Archive level. "Level".';
COMMENT ON COLUMN rna_extraction.rna_box IS 'Archive box. "Box Label". Empty on every row (2026-11-04).';
COMMENT ON COLUMN rna_extraction.rna_notes IS '"Notes". Empty on every row (2026-11-04).';
COMMENT ON COLUMN rna_extraction.status_overwrite IS 'Lab flag marking which extraction to report. "Overwrite Status"; Y stored as true. Read by summary (backlog item 10).';

-- Hi-C lysates and libraries -----------------------------------------------------------------

COMMENT ON COLUMN hic_lysate.lysate_id IS 'Lysate tube id. 4.HiCLysate "Lysate Tube ID".';
COMMENT ON COLUMN hic_lysate.tissue_id IS 'The tissue lysed (FK to tissue). "Sample ID".';
COMMENT ON COLUMN hic_lysate.lysate_num IS 'Attempt number for this tissue. "#".';
COMMENT ON COLUMN hic_lysate.lysate_status IS 'Workbook "Status", free text. Not normalised (Phase H).';
COMMENT ON COLUMN hic_lysate.lysate_prep_date IS '"Lysate Prep Date".';
COMMENT ON COLUMN hic_lysate.lysate_batch_id IS '"Lysate Batch ID".';
COMMENT ON COLUMN hic_lysate.lysate_conc IS 'ng/uL. "Lysate Conc. (ng/uL)".';
COMMENT ON COLUMN hic_lysate.total_lysate IS 'ng. "Total Lysate (ng)".';
COMMENT ON COLUMN hic_lysate.lysate_cde IS 'Chromatin digestion efficiency, %. "CDE (%)".';
COMMENT ON COLUMN hic_lysate.prox_ligation_date IS '"Proximity Ligation prep date".';
COMMENT ON COLUMN hic_lysate.lysate_comments IS '"Comments".';
COMMENT ON COLUMN hic_lysate.status_overwrite IS 'Lab report flag. 4.HiCLysate has no such column, so it is empty on every row.';

COMMENT ON COLUMN hic_library.hic_library_tube_id IS 'Library tube id. 4.HiCLibrary "Library Tube ID". Also in library.';
COMMENT ON COLUMN hic_library.lysate_id IS 'The lysate (FK to hic_lysate). "Lysate Tube ID".';
COMMENT ON COLUMN hic_library.hic_num IS 'Attempt number for this lysate. "#".';
COMMENT ON COLUMN hic_library.hic_status IS 'Workbook "Status", free text. Not normalised (Phase H).';
COMMENT ON COLUMN hic_library.library_method IS '"Library Prep Method".';
COMMENT ON COLUMN hic_library.processing_notes IS '"Processing notes".';
COMMENT ON COLUMN hic_library.library_date IS '"Library Prep Date".';
COMMENT ON COLUMN hic_library.library_id IS 'Library batch. "Library Batch ID".';
COMMENT ON COLUMN hic_library.purified_dna_total IS '"Total Purified DNA".';
COMMENT ON COLUMN hic_library.index_set IS '"Dovetail Dual Index Primer Set #1 For Illumina".';
COMMENT ON COLUMN hic_library.index_i5 IS '"Index i5".';
COMMENT ON COLUMN hic_library.index_i7 IS '"Index i7".';
COMMENT ON COLUMN hic_library.library_conc IS 'ng/uL. "Library Conc. (ng/uL)".';
COMMENT ON COLUMN hic_library.library_yield IS 'ng. "Library yield (ng)".';
COMMENT ON COLUMN hic_library.library_size IS 'bp. "Library size (bp)".';
COMMENT ON COLUMN hic_library.pcr_dup_read_pairs IS 'QC run: PCR duplicate read pairs. "PCR Dup Read Pairs".';
COMMENT ON COLUMN hic_library.nodup_cis_read_pairs_1kb IS 'QC run: deduplicated cis read pairs >= 1 kb apart. "No-Dup Cis Read Pairs >= 1kb".';
COMMENT ON COLUMN hic_library.expected_distinct_30m_reads IS 'QC run: expected distinct reads at 30 M reads, in millions. "EXPECTED_DISTINCT at 30M reads (M)".';
COMMENT ON COLUMN hic_library.hic_comments IS '"Comments".';
COMMENT ON COLUMN hic_library.status_overwrite IS 'Lab flag marking which library to report. "Status Overwrite"; Y stored as true. Read by summary (backlog item 10).';

-- DNA and RNA libraries ----------------------------------------------------------------------

COMMENT ON COLUMN illumina_library.illumina_library_tube_id IS 'Library tube id. 4.Illumina "Library Tube ID". Also in library.';
COMMENT ON COLUMN illumina_library.dna_id IS 'The DNA extraction (FK to dna_extraction). "DNA Tube ID".';
COMMENT ON COLUMN illumina_library.ilmn_num IS 'Attempt number for this DNA. "#".';
COMMENT ON COLUMN illumina_library.ilmn_status IS 'Workbook "Status", free text. Not normalised (Phase H).';
COMMENT ON COLUMN illumina_library.library_method IS '"Library Prep Method".';
COMMENT ON COLUMN illumina_library.library_date IS '"Library Prep Date".';
COMMENT ON COLUMN illumina_library.library_id IS 'Library batch. "Library Batch ID".';
COMMENT ON COLUMN illumina_library.index_set IS '"DNA/RNA UD Indexes Set".';
COMMENT ON COLUMN illumina_library.index_well IS '"Index Adaptor Well".';
COMMENT ON COLUMN illumina_library.index_idx IS 'The index sequences joined. "Concatenate Index".';
COMMENT ON COLUMN illumina_library.library_qubit_conc IS 'ng/uL. "Library Qubit Conc. (ng/ul)".';
COMMENT ON COLUMN illumina_library.il_comments IS '"Comments".';
COMMENT ON COLUMN illumina_library.status_overwrite IS 'Lab flag marking which library to report. "Overwrite Status"; Y stored as true. Read by summary (backlog item 10).';

COMMENT ON COLUMN pacbio_library.pacbio_library_tube_id IS 'Library tube id. 4.PacBio "Library Tube ID". Also in library.';
COMMENT ON COLUMN pacbio_library.dna_id IS 'The DNA extraction (FK to dna_extraction). "DNA Tube ID".';
COMMENT ON COLUMN pacbio_library.pacb_num IS 'Attempt number for this DNA. "#".';
COMMENT ON COLUMN pacbio_library.pacb_status IS 'Workbook "Status", free text. Not normalised (Phase H).';
COMMENT ON COLUMN pacbio_library.dna_treatment IS '"DNA treatment comments".';
COMMENT ON COLUMN pacbio_library.shear_femtol_id IS 'Femto Pulse run id after shearing. "Shearing Femto ID".';
COMMENT ON COLUMN pacbio_library.shear_av_size IS 'Mean size after shearing, bp. "Shearing Av. size (bp)".';
COMMENT ON COLUMN pacbio_library.library_method IS '"Library Prep Method".';
COMMENT ON COLUMN pacbio_library.library_date IS '"Library Prep Date".';
COMMENT ON COLUMN pacbio_library.library_id IS 'Library batch. "Library Batch ID".';
COMMENT ON COLUMN pacbio_library.index_well IS '"SMRTbell barcoded adapter plate 3.0 Index well".';
COMMENT ON COLUMN pacbio_library.barcode IS '"Barcode".';
COMMENT ON COLUMN pacbio_library.seq_femto_id IS 'Femto Pulse run id of the final library. "Library Femto ID".';
COMMENT ON COLUMN pacbio_library.seq_av_size IS 'Mean library size, bp. "Library Av. size (bp)".';
COMMENT ON COLUMN pacbio_library.library_conc IS 'ng/uL. "Library Conc. (ng/uL)".';
COMMENT ON COLUMN pacbio_library.comment IS '"Comments".';
COMMENT ON COLUMN pacbio_library.status_overwrite IS 'Lab flag marking which library to report. "Overwrite Status"; Y stored as true. Read by summary (backlog item 10).';

COMMENT ON COLUMN ont_library.ont_library_tube_id IS 'Library tube id. 4.ONT "Library Tube ID". Also in library.';
COMMENT ON COLUMN ont_library.dna_id IS 'The DNA extraction (FK to dna_extraction). "DNA Tube ID".';
COMMENT ON COLUMN ont_library.ont_num IS 'Attempt number, counted per DNA and kit. "#". The attempt key is (dna_id, library_method, ont_num).';
COMMENT ON COLUMN ont_library.ont_status IS 'Workbook "Status", free text. Not normalised (Phase H).';
COMMENT ON COLUMN ont_library.library_method IS 'Kit, e.g. LSK or ULK. "Library Prep Method".';
COMMENT ON COLUMN ont_library.library_date IS '"Library Prep Date".';
COMMENT ON COLUMN ont_library.library_id IS 'Library batch. "Library Batch ID".';
COMMENT ON COLUMN ont_library.est_loading_size IS 'bp. "Estimated Loading size (bp)".';
COMMENT ON COLUMN ont_library.ont_comments IS '"Comments".';
COMMENT ON COLUMN ont_library.status_overwrite IS 'Lab report flag. "Status Overwrite" exists on 4.ONT but is empty, so this is empty on every row.';

COMMENT ON COLUMN rna_library_ilmn.rna_library_tube_id IS 'Library tube id (_IL mRNA, _dIL ribo-depleted). 4.RNAIllumina "Library Tube ID". Also in library.';
COMMENT ON COLUMN rna_library_ilmn.rna_id IS 'The RNA extraction (FK to rna_extraction). "RNA Tube ID".';
COMMENT ON COLUMN rna_library_ilmn.rna_num IS 'Attempt number, counted per RNA and prep method. "#". The attempt key is (rna_id, library_method, rna_num).';
COMMENT ON COLUMN rna_library_ilmn.rna_status IS 'Workbook "Status", free text. Not normalised (Phase H).';
COMMENT ON COLUMN rna_library_ilmn.library_method IS '"Library Prep Method".';
COMMENT ON COLUMN rna_library_ilmn.library_date IS '"Library Prep Date".';
COMMENT ON COLUMN rna_library_ilmn.library_id IS 'Library batch. "Library Batch ID".';
COMMENT ON COLUMN rna_library_ilmn.library_qubit_conc IS 'ng/uL. "Library Qubit Conc. (ng/ul)".';
COMMENT ON COLUMN rna_library_ilmn.library_molarity IS 'nM. "Library Molarity (nM)".';
COMMENT ON COLUMN rna_library_ilmn.index_set IS '"IDT for Illumina DNA/RNA UD Indexes Set".';
COMMENT ON COLUMN rna_library_ilmn.index_well IS '"Illumina Index Adaptor Well".';
COMMENT ON COLUMN rna_library_ilmn.index_inx IS 'The index sequences joined. "Illumina Contatenate Index" (sic).';
COMMENT ON COLUMN rna_library_ilmn.comments IS '"Comments".';
COMMENT ON COLUMN rna_library_ilmn.status_overwrite IS 'Lab flag marking which library to report. "Overwrite Status"; Y stored as true. Read by summary (backlog item 10).';
COMMENT ON COLUMN rna_library_ilmn.perc_product IS 'Empty. The "% Product" header it was meant to load no longer exists on 4.RNAIllumina, and name_convert_v2.py does not map it. Candidate for removal.';

COMMENT ON COLUMN rna_library_kinx.rna_library_tube_id IS 'Library tube id (_KL). 4.RNAkinnex "Library Tube ID". Also in library.';
COMMENT ON COLUMN rna_library_kinx.rna_id IS 'The RNA extraction (FK to rna_extraction). "RNA Tube ID".';
COMMENT ON COLUMN rna_library_kinx.rna_num IS 'Attempt number for this RNA. "#".';
COMMENT ON COLUMN rna_library_kinx.rna_status IS 'Workbook "Status", free text. Not normalised (Phase H).';
COMMENT ON COLUMN rna_library_kinx.library_method IS '"Library Prep Method".';
COMMENT ON COLUMN rna_library_kinx.processing_comment IS '"Processing comment".';
COMMENT ON COLUMN rna_library_kinx.synthesis_date IS '"Kinnex cDNA synthesis date".';
COMMENT ON COLUMN rna_library_kinx.synthesis_conc IS 'cDNA concentration at the end of Kinnex part 1, ng/uL. "cDNA Concentration (end of section 1 conc)"; the header has an embedded newline, matched since V.2 (2026-10-06).';
COMMENT ON COLUMN rna_library_kinx.part1_batch_id IS '"Kinnex Part 1: cDNA synthesis batch".';
COMMENT ON COLUMN rna_library_kinx.part2_batch_id IS '"Kinnex Part 2: Batch ID".';
COMMENT ON COLUMN rna_library_kinx.final_qubit_conc IS 'ng/uL. "Final Library Qubit Conc. (ng/ul)".';
COMMENT ON COLUMN rna_library_kinx.library_size IS 'bp. "cDNA Library Size (bp)".';
COMMENT ON COLUMN rna_library_kinx.kinnex_primers IS '"PacBo Kinnex Barcoded Primers" (sic).';
COMMENT ON COLUMN rna_library_kinx.kinnex_barcode IS '"PacBio Kinnex Library Barcode".';
COMMENT ON COLUMN rna_library_kinx.pool_id IS '"Pool ID".';
COMMENT ON COLUMN rna_library_kinx.plate IS '"Plate".';
COMMENT ON COLUMN rna_library_kinx.plate_location IS '"Plate Location".';
COMMENT ON COLUMN rna_library_kinx.comments IS '"Comments".';
COMMENT ON COLUMN rna_library_kinx.status_overwrite IS 'Lab report flag. "Overwrite Status" exists on 4.RNAkinnex but is empty, so this is empty on every row.';

COMMENT ON COLUMN library.library_tube_id IS 'Library tube id, unique across every technology. Equal to the tube id in the technology table library_type names.';
COMMENT ON COLUMN library.dna_id IS 'The DNA extraction, for illumina, pacbio and ont libraries (FK to dna_extraction). Exactly one of dna_id, rna_id, lysate_id is set.';
COMMENT ON COLUMN library.rna_id IS 'The RNA extraction, for rna_ilmn and rna_kinx libraries (FK to rna_extraction).';
COMMENT ON COLUMN library.lysate_id IS 'The lysate, for hic libraries (FK to hic_lysate).';

COMMENT ON COLUMN prep_automation.prep_automation IS 'The normalised value: Manual or Automated Biomek i7.';
COMMENT ON COLUMN prep_automation.description IS 'What the value means at the bench.';

-- Sequencing, raw data, read QC --------------------------------------------------------------

COMMENT ON TABLE sequencing IS
  'One row per sequencing record. Source: the 5.Sequencing sheet (import_v2.py). Each row names one '
  'library (library_tube_id) and one run (run_id). Grain undecided: a library on a run in most rows, but '
  'see §11 Q5.';
COMMENT ON COLUMN sequencing.sequencing_id IS '5.Sequencing "Sequencing ID", usually <library tube>_<run_id>. Run-link tables (draft_genome_run, mito_assembly_run, ref_*_run) point here.';
COMMENT ON COLUMN sequencing.technology IS '"Technology": Illumina, PacBio, PacBio Kinnex, ONT, Hi-C... Not normalised.';
COMMENT ON COLUMN sequencing.instrument IS '"Sequencing Instrument": NovaSeq, NextSeq, iSEQ, Revio...';
COMMENT ON COLUMN sequencing.run_date IS '"Sequencing Date". Can differ from seq_date, which is parsed from run_id.';
COMMENT ON COLUMN sequencing.run_id IS 'Run id, MACHINE_YYMMDD_INITIALS. "Sequencing Run ID". FK to sequencing_run (075).';
COMMENT ON COLUMN sequencing.seq_date IS 'Generated: the YYMMDD component of run_id. An identifier component, not a date: the assembly tables key on it.';
COMMENT ON COLUMN sequencing.cell_id IS 'SMRT cell well or flow cell. "SMRTcell well / Flowcell".';
COMMENT ON COLUMN sequencing.smrt_num IS 'SMRT cells used. "No. SMRTcells".';
COMMENT ON COLUMN sequencing.design_no IS 'Illumina prep protocol (FK to design_description; 063).';
COMMENT ON COLUMN sequencing.hic_depth IS 'Hi-C sequencing depth as the lab records it, text. "HiC Depth".';
COMMENT ON COLUMN sequencing.seq_comments IS '"Comments".';

COMMENT ON COLUMN design_description.design_no IS 'Protocol number, as in sequencing.design_no.';
COMMENT ON COLUMN design_description.design_description IS 'The protocol text.';
COMMENT ON COLUMN design_description.comment IS 'Short label: which lab''s standard prep.';

COMMENT ON TABLE raw_data IS
  'Raw sequencing files: one row per FASTQ file of an OG on a run and lane. No current writer found in '
  'the pipeline repositories; took no new rows Jul-Nov 2026 (§11 Q13). FK run_id to sequencing_run (075).';
COMMENT ON COLUMN raw_data.og_id IS 'The sample (FK to sample). NULL on 30 rows.';
COMMENT ON COLUMN raw_data.run_id IS 'The run (FK to sequencing_run).';
COMMENT ON COLUMN raw_data.lane_id IS 'Library and lane as the sequencer named them, e.g. F15-0238_L1.';
COMMENT ON COLUMN raw_data.filename IS 'The FASTQ file name.';
COMMENT ON COLUMN raw_data.og_num IS 'Numeric part of og_id, for sorting. Generated.';

COMMENT ON COLUMN rna_qc_kinnex.rna_tube_id IS 'The Kinnex library (rna_library_kinx tube id). Part of the key (061).';
COMMENT ON COLUMN rna_qc_kinnex.rna_tube_id_2 IS 'A second library pooled into the same QC row, where there was one.';
COMMENT ON COLUMN rna_qc_kinnex.read_count IS 'Reads.';
COMMENT ON COLUMN rna_qc_kinnex.run_id IS 'The PacBio run (FK to sequencing_run).';
COMMENT ON COLUMN rna_qc_kinnex.read_length_mean IS 'Mean read length, bp.';
COMMENT ON COLUMN rna_qc_kinnex.read_length_n50 IS 'Read length N50, bp.';

-- Taxonomy and NCBI assemblies ---------------------------------------------------------------

COMMENT ON TABLE species IS
  'Species names with their lineage, one row per name. Loaded from NCBI rankedlineage.dmp by '
  'OceanOmics-OceanGenomes-Draft-Genomes scripts/taxonomy/load_taxonomy.py (insert-only, existing rows '
  'never touched), plus earlier AFD-sourced rows. The draft pipeline routes BUSCO lineages on class. '
  'One of several species sources: which is authoritative is undecided (§11 Q1).';
COMMENT ON COLUMN species.species IS 'Species name. The key.';
COMMENT ON COLUMN species.class IS 'Class. Holds the phylum where NCBI gives no class, so it is never NULL for the BUSCO lineage selector.';
COMMENT ON COLUMN species.ordr IS 'Order (spelled ordr to avoid the keyword).';
COMMENT ON COLUMN species.family IS 'Family.';
COMMENT ON COLUMN species.genus IS 'Genus.';
COMMENT ON COLUMN species.epithet IS 'Specific epithet.';
COMMENT ON COLUMN species.afd_common_name IS 'Common name from the Australian Faunal Directory, on AFD-sourced rows.';
COMMENT ON COLUMN species.family_common_name IS 'Common name of the family, e.g. Elapid Snakes.';
COMMENT ON COLUMN species.ncbi_taxon_id IS 'NCBI Taxonomy id. NULL on rows not from NCBI.';
COMMENT ON COLUMN species.synonym IS 'A synonym or the accepted name.';

COMMENT ON TABLE ncbi_genome_assemblies IS
  'NCBI genome assembly metadata (1,830 rows): what is already assembled for a species. No writer and '
  'no reading view found; no FK to species. The empty species_ncbi_assembly was meant to hold the same '
  'and is what v_genome_size_comparison reads; consolidating them is a backlog item.';
COMMENT ON COLUMN ncbi_genome_assemblies.assembly_accession IS 'GCA_/GCF_ accession. Unique.';
COMMENT ON COLUMN ncbi_genome_assemblies.assembly_name IS 'Assembly name.';
COMMENT ON COLUMN ncbi_genome_assemblies.assembly_level IS 'Contig, Scaffold, Chromosome or Complete Genome.';
COMMENT ON COLUMN ncbi_genome_assemblies.assembly_bioproject_accession IS 'BioProject of the assembly.';
COMMENT ON COLUMN ncbi_genome_assemblies.organism_name IS 'Organism name as NCBI gives it.';
COMMENT ON COLUMN ncbi_genome_assemblies.organism_taxonomic_id IS 'NCBI Taxonomy id.';
COMMENT ON COLUMN ncbi_genome_assemblies.assembly_refseq_category IS 'RefSeq category; the string NaN where there is none.';
COMMENT ON COLUMN ncbi_genome_assemblies.assembly_release_date IS 'Release date.';
COMMENT ON COLUMN ncbi_genome_assemblies.contig_n50 IS 'Contig N50, bp.';

COMMENT ON TABLE species_ncbi_assembly IS
  'Planned NCBI assembly table, with a species FK and one chosen assembly per species. Empty since it '
  'was created; ncbi_genome_assemblies holds the data. v_genome_size_comparison reads this table, so '
  'its NCBI columns are NULL on every row until the two are consolidated (backlog item).';
COMMENT ON COLUMN species_ncbi_assembly.assembly_accession IS 'GCA_/GCF_ accession.';
COMMENT ON COLUMN species_ncbi_assembly.species IS 'The species (FK to species).';
COMMENT ON COLUMN species_ncbi_assembly.ncbi_taxon_id IS 'NCBI Taxonomy id.';
COMMENT ON COLUMN species_ncbi_assembly.assembly_name IS 'Assembly name.';
COMMENT ON COLUMN species_ncbi_assembly.assembly_level IS 'Contig, Scaffold, Chromosome or Complete Genome.';
COMMENT ON COLUMN species_ncbi_assembly.total_sequence_length IS 'bp.';
COMMENT ON COLUMN species_ncbi_assembly.is_refseq IS 'A RefSeq assembly.';
COMMENT ON COLUMN species_ncbi_assembly.is_representative IS 'NCBI''s representative assembly for the species.';
COMMENT ON COLUMN species_ncbi_assembly.is_chosen IS 'The one assembly chosen for the species (partial unique index).';
COMMENT ON COLUMN species_ncbi_assembly.release_date IS 'Release date.';
COMMENT ON COLUMN species_ncbi_assembly.retrieved_at IS 'When the row was fetched from NCBI.';

-- ENA ----------------------------------------------------------------------------------------

COMMENT ON TABLE ena_validation_attempts IS
  'One ENA validation of one mitogenome annotation (full_seqid) per attempt: table2asn, EMBL conversion, '
  'preflight and Webin-CLI results, and whether it is submission_ready. Written by the mito pipeline '
  'bin/push_ena_validation_results.py (from collate_ena_validation.py), upserted across every non-key '
  'column, so it holds the latest result of each attempt. Submission state is ena_submissions''.';
COMMENT ON COLUMN ena_validation_attempts.id IS 'Surrogate key.';
COMMENT ON COLUMN ena_validation_attempts.full_seqid IS 'og_id.tech.seq_date.code.annotation: the annotation validated (014).';
COMMENT ON COLUMN ena_validation_attempts.og_id IS 'The sample.';
COMMENT ON COLUMN ena_validation_attempts.tech IS 'ilmn, hifi or hic.';
COMMENT ON COLUMN ena_validation_attempts.seq_date IS 'YYMMDD identifier component.';
COMMENT ON COLUMN ena_validation_attempts.code IS 'Assembler code (mito_assembly.code).';
COMMENT ON COLUMN ena_validation_attempts.annotation IS 'Annotator code (mito_annotation.annotation). NULL on rows carried from before 014.';
COMMENT ON COLUMN ena_validation_attempts.ena_study IS 'ENA study the validation targeted (PRJEB...).';
COMMENT ON COLUMN ena_validation_attempts.validation_mode IS 'pipeline (table2asn and EMBL conversion) or validate (preflight of an existing flat file). pipeline on every row so far.';
COMMENT ON COLUMN ena_validation_attempts.validation_attempt IS 'Which attempt, part of the key with full_seqid and ena_study. initial on every row so far.';
COMMENT ON COLUMN ena_validation_attempts.table2asn_status IS 'The table2asn step: PASS or FAIL_TABLE2ASN.';
COMMENT ON COLUMN ena_validation_attempts.reject_count IS 'table2asn REJECT messages.';
COMMENT ON COLUMN ena_validation_attempts.error_count IS 'table2asn ERROR messages.';
COMMENT ON COLUMN ena_validation_attempts.warning_count IS 'table2asn WARNING messages.';
COMMENT ON COLUMN ena_validation_attempts.info_count IS 'table2asn INFO messages.';
COMMENT ON COLUMN ena_validation_attempts.fatal_discrepancy_count IS 'FATAL items in the table2asn discrepancy report.';
COMMENT ON COLUMN ena_validation_attempts.nostop_count IS 'CDS features without a stop codon.';
COMMENT ON COLUMN ena_validation_attempts.blocking_codes IS 'Message codes that block submission, comma-joined.';
COMMENT ON COLUMN ena_validation_attempts.warning_codes IS 'Message codes that do not block, comma-joined (e.g. MISSING_PROTEIN_ID,NO_LOCUS_TAGS).';
COMMENT ON COLUMN ena_validation_attempts.conversion_status IS 'The conversion to EMBL flat file (pipeline mode): PASS, SKIPPED_TABLE2ASN (table2asn failed), or NOT_APPLICABLE in validate mode.';
COMMENT ON COLUMN ena_validation_attempts.conversion_reason IS 'Why conversion failed.';
COMMENT ON COLUMN ena_validation_attempts.conversion_exit IS 'Exit code of the conversion step.';
COMMENT ON COLUMN ena_validation_attempts.preflight_status IS 'PASS, FAIL, NOT_RUN or NOT_APPLICABLE: the preflight check (validate mode).';
COMMENT ON COLUMN ena_validation_attempts.preflight_reason IS 'Why preflight failed.';
COMMENT ON COLUMN ena_validation_attempts.preflight_exit IS 'Exit code of the preflight step. Empty on every row (validate mode has not been used).';
COMMENT ON COLUMN ena_validation_attempts.webin_status IS 'Webin-CLI -validate: PASS, FAIL_WEBIN, FAIL_INFRASTRUCTURE, NOT_RUN (an earlier gate failed) or NOT_REQUESTED.';
COMMENT ON COLUMN ena_validation_attempts.webin_reason IS 'Why Webin-CLI validation failed.';
COMMENT ON COLUMN ena_validation_attempts.webin_exit IS 'Exit code of Webin-CLI.';
COMMENT ON COLUMN ena_validation_attempts.submission_ready IS 'true when every gate for the mode passed: webin PASS and (preflight PASS in validate mode, or table2asn and conversion PASS otherwise) (019).';
COMMENT ON COLUMN ena_validation_attempts.recorded_at IS 'When the result was last written.';
COMMENT ON COLUMN ena_validation_attempts.attempt_count IS 'Times this attempt has been written: 1 on insert, +1 on each re-run (push_ena_validation_results.py).';

COMMENT ON COLUMN ena_submissions.full_seqid IS 'og_id.tech.seq_date.code.annotation: the annotation submitted.';
COMMENT ON COLUMN ena_submissions.og_id IS 'The sample.';
COMMENT ON COLUMN ena_submissions.tech IS 'ilmn, hifi or hic.';
COMMENT ON COLUMN ena_submissions.seq_date IS 'YYMMDD identifier component.';
COMMENT ON COLUMN ena_submissions.code IS 'Assembler code.';
COMMENT ON COLUMN ena_submissions.annotation IS 'Annotator code.';
COMMENT ON COLUMN ena_submissions.submission_status IS 'Ledger state, e.g. SUBMITTED or ACCESSION_ASSIGNED (all 539 rows as of 2026-11).';
COMMENT ON COLUMN ena_submissions.submitted_at IS 'When it was submitted.';
COMMENT ON COLUMN ena_submissions.submitted_by IS 'User who ran the submission.';
COMMENT ON COLUMN ena_submissions.error_message IS 'Submission error. Empty on every row.';
COMMENT ON COLUMN ena_submissions.receipt_path IS 'Path of the Webin receipt XML (on Pawsey scratch).';
COMMENT ON COLUMN ena_submissions.receipt_sha256 IS 'SHA-256 of the receipt, so a later copy can be checked.';
COMMENT ON COLUMN ena_submissions.webin_cli_version IS 'Webin-CLI version used.';
COMMENT ON COLUMN ena_submissions.ena_study_accession IS 'ENA study (PRJEB...).';
COMMENT ON COLUMN ena_submissions.ena_sample_accession IS 'ENA sample (ERS...). Missing on 172 of 539 (§11 Q12).';
COMMENT ON COLUMN ena_submissions.ena_analysis_accession IS 'ENA analysis (ERZ...) from the receipt.';
COMMENT ON COLUMN ena_submissions.ena_assembly_accession IS 'Public assembly accession (GCA_...) once ENA processes the ERZ.';
COMMENT ON COLUMN ena_submissions.ena_sequence_accession IS 'Empty on every row: genome-context submissions return analysis and assembly accessions, not sequence ones (§11 Q12).';
COMMENT ON COLUMN ena_submissions.locus_tag_prefix IS 'Locus-tag prefix registered for the submission (e.g. OG193MT).';
COMMENT ON COLUMN ena_submissions.created_at IS 'When the row was first written.';
COMMENT ON COLUMN ena_submissions.updated_at IS 'When the row was last written.';

COMMENT ON TABLE ena_specimen_accessions IS
  'Specimen registry for ENA: one row per OG with an ENA-referenceable BioSample, where one is known. '
  'Filled by the mito pipeline bin/backfill_ena_specimen_accessions.py; 1 of 2,848 rows has an accession. '
  'Whether to keep it or make it a view over sample is open (§11 Q14).';
COMMENT ON COLUMN ena_specimen_accessions.og_id IS 'The sample (FK to sample).';
COMMENT ON COLUMN ena_specimen_accessions.og_numeric IS 'Numeric part of og_id (checked to match).';
COMMENT ON COLUMN ena_specimen_accessions.ena_biosample_accession IS 'SAMEA/SAMN/SAMD accession. A SAMN is NCBI-registered and webin-cli cannot resolve it (007).';
COMMENT ON COLUMN ena_specimen_accessions.accession_source IS 'Where the accession came from, e.g. sample,draft_genomes.';
COMMENT ON COLUMN ena_specimen_accessions.verified_at IS 'When the accession was last checked.';
COMMENT ON COLUMN ena_specimen_accessions.updated_at IS 'When the row was last written.';

COMMENT ON TABLE ena_related_assemblies IS
  'Planned: accessions of the reference or draft assemblies an OG''s mitogenome submission relates to. '
  'Empty since created; no writer.';
COMMENT ON COLUMN ena_related_assemblies.id IS 'Surrogate key.';
COMMENT ON COLUMN ena_related_assemblies.og_id IS 'The sample.';
COMMENT ON COLUMN ena_related_assemblies.relationship_type IS 'reference or draft.';
COMMENT ON COLUMN ena_related_assemblies.archive IS 'ENA, NCBI or OTHER.';
COMMENT ON COLUMN ena_related_assemblies.accession IS 'The related assembly''s accession.';
COMMENT ON COLUMN ena_related_assemblies.is_primary IS 'The one to cite, where there are several.';
COMMENT ON COLUMN ena_related_assemblies.accession_source IS 'Where the accession came from.';
COMMENT ON COLUMN ena_related_assemblies.updated_at IS 'When the row was last written.';

COMMENT ON COLUMN ena_locus_registry_archive.og_id IS 'The sample. Archive: empty, frozen by 010.';
COMMENT ON COLUMN ena_locus_registry_archive.gene_serial IS 'Serial allocated for the gene within the specimen.';
COMMENT ON COLUMN ena_locus_registry_archive.canonical_gene IS 'Canonical gene name.';
COMMENT ON COLUMN ena_locus_registry_archive.gene_occurrence IS 'Occurrence of the gene, where it appears more than once.';
COMMENT ON COLUMN ena_locus_registry_archive.feature_type IS 'Feature type (CDS, tRNA, rRNA).';
COMMENT ON COLUMN ena_locus_registry_archive.strand IS 'Strand.';
COMMENT ON COLUMN ena_locus_registry_archive.feature_sequence_sha256 IS 'SHA-256 of the feature sequence.';
COMMENT ON COLUMN ena_locus_registry_archive.coordinate_snapshot IS 'Coordinates when allocated.';
COMMENT ON COLUMN ena_locus_registry_archive.allocation_status IS 'Allocation state.';
COMMENT ON COLUMN ena_locus_registry_archive.created_at IS 'When allocated.';
COMMENT ON COLUMN ena_locus_registry_archive.updated_at IS 'When last changed.';

COMMENT ON COLUMN ena_candidate_loci_archive.full_seqid IS 'The annotation. Archive: empty, frozen by 010.';
COMMENT ON COLUMN ena_candidate_loci_archive.og_id IS 'The sample.';
COMMENT ON COLUMN ena_candidate_loci_archive.gene_serial IS 'Serial from ena_locus_registry_archive.';
COMMENT ON COLUMN ena_candidate_loci_archive.locus_tag IS 'Locus tag submitted.';
COMMENT ON COLUMN ena_candidate_loci_archive.feature_key IS 'Feature key.';
COMMENT ON COLUMN ena_candidate_loci_archive.start_coordinate IS 'Start, bp.';
COMMENT ON COLUMN ena_candidate_loci_archive.end_coordinate IS 'End, bp.';
COMMENT ON COLUMN ena_candidate_loci_archive.strand IS 'Strand.';
COMMENT ON COLUMN ena_candidate_loci_archive.created_at IS 'When written.';

-- Import bookkeeping and the ledger ----------------------------------------------------------

COMMENT ON COLUMN import_quarantine.quarantine_id IS 'Surrogate key.';
COMMENT ON COLUMN import_quarantine.violation_type IS 'Why the row was rejected: not_null, foreign_key, type_cast, unique, duplicate_source_row, lookup, conflicting_value, check or displaced.';
COMMENT ON COLUMN import_quarantine.violation_detail IS 'The constraint or message, for the lab to act on.';
COMMENT ON COLUMN import_quarantine.first_seen IS 'When the violation was first recorded.';
COMMENT ON COLUMN import_quarantine.resolved_at IS 'When it was resolved. NULL: still open (v_quarantine_open).';
COMMENT ON COLUMN import_quarantine.resolution_note IS 'How it was resolved. Needs resolved_at.';

COMMENT ON COLUMN value_conversions.source_table IS 'Table the value was stored in.';
COMMENT ON COLUMN value_conversions.row_key IS 'Key of the row (og_id, tube id...).';
COMMENT ON COLUMN value_conversions.column_name IS 'Column the value was stored in.';
COMMENT ON COLUMN value_conversions.raw_value IS 'The workbook text as typed.';
COMMENT ON COLUMN value_conversions.rule IS 'Which v2_value_rules.py rule converted it: no_value, unit, bound, surface, length, dms, excel_serial_coordinate, dms_assumed_hemisphere, length_split, depth_range.';
COMMENT ON COLUMN value_conversions.first_seen IS 'When the conversion was first recorded.';
COMMENT ON COLUMN value_conversions.last_seen IS 'When the same conversion was last made.';

COMMENT ON COLUMN workbook_attempt_keys.source_table IS 'Target table.';
COMMENT ON COLUMN workbook_attempt_keys.row_key IS 'The row''s key (tube id...).';
COMMENT ON COLUMN workbook_attempt_keys.parent_key IS 'Its parent''s key (tissue, DNA, RNA or lysate).';
COMMENT ON COLUMN workbook_attempt_keys.attempt_scope IS 'The prep method, on the two sheets that count attempts per method (4.ONT, 4.RNAIllumina); otherwise NULL.';
COMMENT ON COLUMN workbook_attempt_keys.attempt_num IS 'The workbook "#".';
COMMENT ON COLUMN workbook_attempt_keys.workbook_file IS 'Which workbook was staged.';
COMMENT ON COLUMN workbook_attempt_keys.staged_at IS 'When it was staged.';

COMMENT ON COLUMN schema_migrations.filename IS 'The sql/ file applied, e.g. 078_phase_r_rg_comments.sql.';
COMMENT ON COLUMN schema_migrations.sha256 IS 'SHA-256 of the file when applied. bin/apply_migrations.py --verify refuses to continue when a file stops matching.';
COMMENT ON COLUMN schema_migrations.applied_at IS 'When it was applied.';

-- Views: table comments where missing or stale --------------------------------------------------

COMMENT ON VIEW embargo_assignment_view IS
  'Per specimen: embargo_status beside the identifying fields and the validated species names, for '
  'OceanGenom_Web''s embargo page. Updatable: an UPDATE of embargo_status writes sample.embargo_status '
  '(trigger trg_embargo_assignment_view_upd). Nothing else is writable through it.';
COMMENT ON VIEW sample_view IS
  'The sample fields lca_validation_report_view shows, with _sv-suffixed names, for specimens that have an '
  'LCA validation row.';
COMMENT ON VIEW ena_submission_status IS
  'One row per annotation validated for ENA: its latest validation (as ena_validation_latest) and its '
  'production submission, if any. submission_status is NOT_SUBMITTED where there is none.';
COMMENT ON VIEW ena_validation_latest IS
  'The latest ena_validation_attempts row per full_seqid (by recorded_at, then id). Same columns.';
COMMENT ON VIEW filtered_lca_view IS
  'Per annotation and region: the filtered BLAST matches whose species is the specimen''s nominal ID, '
  '('', ''-joined match_sequence_id). Read by lca_validation_report_view.';
COMMENT ON VIEW lca_pivot_view IS
  'Per annotation: every species in the LCA, per region (12S, 16S, CO1), '', ''-joined and de-duplicated.';
COMMENT ON VIEW lca_results_view IS
  'Per annotation: lca_pivot_view beside the nominal species ID, with a validation_status: the nominal ID '
  'when it is one of the LCA species in any region, MISSING NOMINAL ID, or INVESTIGATE (066).';
COMMENT ON VIEW lca_validation_report_view IS
  'The LCA validation report, one row per mito_lca_validation row, for curators in OceanGenom_Web. '
  'Updatable through trigger trg_lca_validation_report_view_upd (the validation fields only; the key '
  'fields are refused).';
COMMENT ON VIEW goat_project_metadata_v1 IS
  'GoaT (Genomes on a Tree) project metadata: one constant row describing Ocean Genomes. An external '
  'contract: a breaking change is a new _v2 beside it (§11 Q6).';
COMMENT ON VIEW v_genome_size_comparison IS
  'Per draft: the GenomeScope genome size against the chosen NCBI assembly of the nominal species. Reads '
  'species_ncbi_assembly, which is empty, so ncbi_bp and the columns after it are NULL on every row until '
  'it is consolidated with ncbi_genome_assemblies.';
COMMENT ON VIEW mitogenome_submission_view IS
  'One row per mitogenome assembly and annotation (one per unannotated assembly): the assembly and '
  'annotation results beside the ENA validation and the validated species. Built on mito_assembly and '
  'mito_annotation (056); joins ENA validation and LCA validation on the five-part key. avg_coverage '
  'and avg_base_coverage are not shown.';
COMMENT ON VIEW v_ref_assembly_run_readiness IS
  'Assemblies with no run link, and the OG''s PacBio/ONT DNA rows to choose from. Their seq_date matches '
  'no run date (RG.0 §1.5). No writer links new assemblies since the RG.6 merge (078), so every new '
  'assembly appears here.';
COMMENT ON VIEW v_sequencing_run_fk_readiness IS
  'Per table with an FK to sequencing_run (sequencing, raw_data: 075; hifi_read_qc, hic_read_qc: 077): '
  'rows whose run is not in sequencing_run. The FKs make this 0; kept as the check.';

-- Comments that still named v2./v3. objects (V.7 item 3) ---------------------------------------

COMMENT ON VIEW summary IS
  'The workbook''s Summary sheet, computed from the child tables instead of copied from Excel (decision '
  '5). This replaces the nine derived columns removed from sample, and fixes the status fragmentation of '
  'database_review.md Finding 7 at source: the 47 distinct rna_status values were Excel string '
  'concatenation being persisted. Each technology also reports planned (lab intent) against actual '
  '(counted). Takes about 2 s (backlog item 10).';
COMMENT ON VIEW v_tissue_browse IS 'Tissues with specimen context. Read-only; write to tissue.';
COMMENT ON VIEW draft_genomes IS
  'Compatibility view: the kept columns of the old draft_genomes table plus nominal_species_id, grouped '
  'by process (056), plus the read depth and host partition columns (067). Read by column name, not '
  'position. DepthSizer (retired) is not shown; see draft_depthsizer. Not a write path: writers use '
  'draft_genome and its process tables.';
COMMENT ON COLUMN sample.ilmn IS 'Is this sample slated for Illumina? Hand-entered lab intent, kept in the database (2026-10-28). Compare against summary.illumina_actual.';
COMMENT ON FUNCTION lca_set_content_hash() IS
  'Maintains content_hash on mito_lca and mito_lca_raw. Pinned search_path so the hash cannot vary with '
  'the caller''s path.';

-- Views: columns of the contract and reporting views ---------------------------------------------

COMMENT ON COLUMN goat_species_v1.ncbi_taxon_id IS 'GoaT: NCBI Taxonomy id (master_species).';
COMMENT ON COLUMN goat_species_v1.family IS 'GoaT: family.';
COMMENT ON COLUMN goat_species_v1.species IS 'GoaT: species name. Matched to sample.nominal_species_id by exact string.';
COMMENT ON COLUMN goat_species_v1.subspecies_epithet IS 'GoaT: master_species.epithet, or - . (It is the specific epithet, whatever the GoaT name.)';
COMMENT ON COLUMN goat_species_v1.target_list_status IS 'GoaT: priority_target for five hard-coded taxon ids, otherwise potential_target.';
COMMENT ON COLUMN goat_species_v1.sampling_status IS 'GoaT: sample_collected when any sample has this nominal species; NULL otherwise.';
COMMENT ON COLUMN goat_species_v1.sequencing_status IS 'GoaT, first that applies: submitted (a sample has ncbi_bioproject_id_lvl_3_hifi), in_assembly (a ref_assembly exists), in_lab (summary.pacbio_status is one of nine PacBio lab states); NULL otherwise.';
COMMENT ON COLUMN goat_species_v1.genome_publication IS 'GoaT: always NULL.';
COMMENT ON COLUMN goat_species_v1.primary_project IS 'GoaT: always Ocean Genomes.';
COMMENT ON COLUMN goat_species_v1.ebp_collaborator_acronyms IS 'GoaT: always NULL.';
COMMENT ON COLUMN goat_species_v1.contributing_project_lab IS 'GoaT: always NULL.';
COMMENT ON COLUMN goat_species_v1.collected_by IS 'GoaT: data_conflict for six hard-coded species; otherwise the collector of one Reference-workflow sample of the species (arbitrary when there are several).';
COMMENT ON COLUMN goat_species_v1.priority_flags IS 'GoaT: always NULL.';
COMMENT ON COLUMN goat_species_v1.common_name IS 'GoaT: master_species.afd_common_name, or - .';
COMMENT ON COLUMN goat_species_v1.synonym IS 'GoaT: master_species.synonym, or - .';
COMMENT ON COLUMN goat_species_v1.assigned_sequencing_center IS 'GoaT: always NULL.';

COMMENT ON COLUMN goat_project_metadata_v1.project_name IS 'GoaT: constant, Ocean Genomes.';
COMMENT ON COLUMN goat_project_metadata_v1.project_acronym IS 'GoaT: constant, OG.';
COMMENT ON COLUMN goat_project_metadata_v1.subproject_name IS 'GoaT: always NULL.';
COMMENT ON COLUMN goat_project_metadata_v1.bioproject_id IS 'GoaT: always NULL.';
COMMENT ON COLUMN goat_project_metadata_v1.primary_contact IS 'GoaT: constant, the project''s primary contact.';
COMMENT ON COLUMN goat_project_metadata_v1.primary_contact_institution IS 'GoaT: constant.';
COMMENT ON COLUMN goat_project_metadata_v1.public_contact_email IS 'GoaT: constant.';
COMMENT ON COLUMN goat_project_metadata_v1.date_of_last_update IS 'GoaT: CURRENT_DATE, i.e. the day it is read, not the day anything changed.';
COMMENT ON COLUMN goat_project_metadata_v1.schema_version IS 'GoaT: the template version, ebp_species_goat_3.0.';

COMMENT ON COLUMN summary.og_num IS 'sample.og_num.';
COMMENT ON COLUMN summary.og_id IS 'The specimen.';
COMMENT ON COLUMN summary.project_id IS 'sample.project_id.';
COMMENT ON COLUMN summary.workflow IS 'sample.workflow (set in OceanGenom_Web).';
COMMENT ON COLUMN summary.priority IS 'sample.priority (set in OceanGenom_Web).';
COMMENT ON COLUMN summary.tissues IS 'Tissue rows for the specimen.';
COMMENT ON COLUMN summary.extracted IS 'DNA extractions with status exactly Extracted.';
COMMENT ON COLUMN summary.dna_extraction_status IS 'Status of the one DNA extraction reported: the status_overwrite one if any, else the highest ext_num. Awaiting Status when there is none. Free text, as entered.';
COMMENT ON COLUMN summary.illumina_status IS 'Status of the reported Illumina library (status_overwrite first, then highest #), or Awaiting Status.';
COMMENT ON COLUMN summary.pacbio_status IS 'Status of the reported PacBio library, or Awaiting Status. goat_species_v1 reads it for in_lab.';
COMMENT ON COLUMN summary.hic_status IS 'Status of the reported Hi-C library, or Awaiting Status.';
COMMENT ON COLUMN summary.nanopore_status IS 'Status of the reported ONT library, or Awaiting Status.';
COMMENT ON COLUMN summary.rna_extraction_status IS 'Status of the reported RNA extraction, or Awaiting Status.';
COMMENT ON COLUMN summary.rna_ilmn_status IS 'Status of the reported Illumina RNA library, or Awaiting Status.';
COMMENT ON COLUMN summary.rna_kinnex_status IS 'Status of the reported Kinnex library, or Awaiting Status.';
COMMENT ON COLUMN summary.hifi_planned IS 'sample.hifi: slated for PacBio HiFi (lab intent). Compare with hifi_actual.';
COMMENT ON COLUMN summary.hic_planned IS 'sample.hic: slated for Hi-C.';
COMMENT ON COLUMN summary.nanopore_planned IS 'sample.nano: slated for ONT.';
COMMENT ON COLUMN summary.rna_planned IS 'sample.rna: slated for RNA extraction.';
COMMENT ON COLUMN summary.rna_ilmn_planned IS 'sample.ilrna: slated for Illumina RNA.';
COMMENT ON COLUMN summary.hifi_actual IS 'PacBio libraries that exist for the specimen.';
COMMENT ON COLUMN summary.hic_actual IS 'Hi-C libraries that exist.';
COMMENT ON COLUMN summary.nanopore_actual IS 'ONT libraries that exist.';
COMMENT ON COLUMN summary.rna_actual IS 'RNA extractions that exist.';
COMMENT ON COLUMN summary.rna_ilmn_actual IS 'Illumina RNA libraries that exist.';
COMMENT ON COLUMN summary.rna_kinnex_actual IS 'Kinnex libraries that exist. (There is no rna_kinnex_planned.)';
COMMENT ON COLUMN summary.ilmn_validated_species_name IS 'Validated species names from the specimen''s Illumina mitogenome validations, '', ''-joined.';
COMMENT ON COLUMN summary.hifi_validated_species_name IS 'The same, from HiFi mitogenomes.';
COMMENT ON COLUMN summary.hic_validated_species_name IS 'The same, from Hi-C mitogenomes.';
COMMENT ON COLUMN summary.field_id IS 'sample.field_id.';
COMMENT ON COLUMN summary.nominal_species_id IS 'sample.nominal_species_id.';
COMMENT ON COLUMN summary.common_name IS 'sample.common_name.';
COMMENT ON COLUMN summary.collector IS 'sample.collector.';
COMMENT ON COLUMN summary.contact IS 'sample.contact.';
COMMENT ON COLUMN summary.comments IS 'sample.comments.';

COMMENT ON COLUMN mitogenome_submission_view.og_num IS 'sample.og_num.';
COMMENT ON COLUMN mitogenome_submission_view.og_id IS 'The specimen.';
COMMENT ON COLUMN mitogenome_submission_view.nominal_species_id IS 'sample.nominal_species_id.';
COMMENT ON COLUMN mitogenome_submission_view.tech IS 'mito_assembly.tech.';
COMMENT ON COLUMN mitogenome_submission_view.seq_date IS 'mito_assembly.seq_date.';
COMMENT ON COLUMN mitogenome_submission_view.code IS 'mito_assembly.code.';
COMMENT ON COLUMN mitogenome_submission_view.annotation IS 'mito_annotation.annotation; NULL for an unannotated assembly.';
COMMENT ON COLUMN mitogenome_submission_view.stats IS 'mito_assembly.stats.';
COMMENT ON COLUMN mitogenome_submission_view.length IS 'mito_assembly.length, bp.';
COMMENT ON COLUMN mitogenome_submission_view.length_emma IS 'mito_annotation.length_emma, bp.';
COMMENT ON COLUMN mitogenome_submission_view.cds_no IS 'mito_annotation.cds_no.';
COMMENT ON COLUMN mitogenome_submission_view.trna_no IS 'mito_annotation.trna_no.';
COMMENT ON COLUMN mitogenome_submission_view.rrna_no IS 'mito_annotation.rrna_no.';
COMMENT ON COLUMN mitogenome_submission_view.missing_genes IS 'mito_annotation.missing_genes.';
COMMENT ON COLUMN mitogenome_submission_view.extra_genes IS 'mito_annotation.extra_genes.';
COMMENT ON COLUMN mitogenome_submission_view.order_correct IS 'mito_annotation.order_correct.';
COMMENT ON COLUMN mitogenome_submission_view.table2asn_status IS 'ena_validation_attempts.table2asn_status. One row per validation attempt, so an annotation with several attempts appears several times.';
COMMENT ON COLUMN mitogenome_submission_view.warning_codes IS 'ena_validation_attempts.warning_codes.';
COMMENT ON COLUMN mitogenome_submission_view.webin_status IS 'ena_validation_attempts.webin_status.';
COMMENT ON COLUMN mitogenome_submission_view.webin_reason IS 'ena_validation_attempts.webin_reason.';
COMMENT ON COLUMN mitogenome_submission_view.submission_ready IS 'ena_validation_attempts.submission_ready.';
COMMENT ON COLUMN mitogenome_submission_view.validated_species_name IS 'mito_lca_validation.validated_species_name.';
COMMENT ON COLUMN mitogenome_submission_view.validator IS 'mito_lca_validation.validator.';

COMMENT ON COLUMN v_draft_genome_status.og_num IS 'draft_genome.og_num.';
COMMENT ON COLUMN v_draft_genome_status.og_id IS 'The specimen.';
COMMENT ON COLUMN v_draft_genome_status.nominal_species_id IS 'sample.nominal_species_id.';
COMMENT ON COLUMN v_draft_genome_status.seq_date IS 'draft_genome.seq_date.';
COMMENT ON COLUMN v_draft_genome_status.mach IS 'draft_genome.mach.';
COMMENT ON COLUMN v_draft_genome_status.has_run_link IS 'At least one draft_genome_run row.';
COMMENT ON COLUMN v_draft_genome_status.has_fastp IS 'A draft_fastp row exists.';
COMMENT ON COLUMN v_draft_genome_status.has_genomescope IS 'A draft_genomescope row exists.';
COMMENT ON COLUMN v_draft_genome_status.genomescope_output_set IS 'draft_genomescope.output_set: core or extended.';
COMMENT ON COLUMN v_draft_genome_status.has_tiara IS 'A draft_tiara row exists.';
COMMENT ON COLUMN v_draft_genome_status.has_contamination IS 'A draft_contamination row exists.';
COMMENT ON COLUMN v_draft_genome_status.has_busco IS 'A draft_busco row exists.';
COMMENT ON COLUMN v_draft_genome_status.has_merqury IS 'A draft_merqury row exists.';
COMMENT ON COLUMN v_draft_genome_status.has_gfastats IS 'A draft_gfastats row exists.';
COMMENT ON COLUMN v_draft_genome_status.has_submission IS 'A draft_submission row exists. Not counted in processes_done.';
COMMENT ON COLUMN v_draft_genome_status.processes_done IS 'How many of the seven processes (fastp, genomescope, tiara, contamination, busco, merqury, gfastats) have a row, 0-7.';
COMMENT ON COLUMN v_draft_genome_status.reads_only IS 'fastp ran and none of the six assembly processes did.';

COMMENT ON COLUMN v_ref_assembly_status.og_num IS 'ref_assembly.og_num.';
COMMENT ON COLUMN v_ref_assembly_status.og_id IS 'The specimen.';
COMMENT ON COLUMN v_ref_assembly_status.seq_date IS 'ref_assembly.seq_date.';
COMMENT ON COLUMN v_ref_assembly_status.version IS 'ref_assembly.version.';
COMMENT ON COLUMN v_ref_assembly_status.strategy IS 'ref_assembly.strategy.';
COMMENT ON COLUMN v_ref_assembly_status.attempt IS 'ref_assembly.attempt.';
COMMENT ON COLUMN v_ref_assembly_status.run_links IS 'ref_assembly_run rows (0 for assemblies created since RG.6; see that table).';
COMMENT ON COLUMN v_ref_assembly_status.parts IS 'ref_assembly_part rows.';
COMMENT ON COLUMN v_ref_assembly_status.stages IS 'Stages present, comma-joined (e.g. 0,1,2,3).';
COMMENT ON COLUMN v_ref_assembly_status.curated IS 'A stage-3 (curated) part exists.';
COMMENT ON COLUMN v_ref_assembly_status.gfastats_stages IS 'Stages with a ref_gfastats row, comma-joined.';
COMMENT ON COLUMN v_ref_assembly_status.busco_stages IS 'Stages with a ref_busco row.';
COMMENT ON COLUMN v_ref_assembly_status.merqury_qv_stages IS 'Stages with a ref_merqury_qv row.';
COMMENT ON COLUMN v_ref_assembly_status.merqury_completeness_stages IS 'Stages with a ref_merqury_completeness row.';
COMMENT ON COLUMN v_ref_assembly_status.omnic_stages IS 'Stages with a ref_omnic row.';
COMMENT ON COLUMN v_ref_assembly_status.seqkit_stats_stages IS 'Stages with a ref_seqkit_stats row.';
COMMENT ON COLUMN v_ref_assembly_status.chromosome_stats_stages IS 'Stages with a ref_chromosome_stats row.';

COMMENT ON COLUMN v_ref_assembly_summary.og_num IS 'ref_assembly.og_num.';
COMMENT ON COLUMN v_ref_assembly_summary.og_id IS 'The specimen.';
COMMENT ON COLUMN v_ref_assembly_summary.seq_date IS 'ref_assembly.seq_date.';
COMMENT ON COLUMN v_ref_assembly_summary.version IS 'ref_assembly.version.';
COMMENT ON COLUMN v_ref_assembly_summary.haplotype IS 'hap1, hap2, p_ctg or a_ctg (dual parts are left out).';
COMMENT ON COLUMN v_ref_assembly_summary.final_stage IS 'The highest stage this haplotype has. The metrics after it are that stage''s.';
COMMENT ON COLUMN v_ref_assembly_summary.final_stage_name IS 'ref_stage.name of final_stage.';
COMMENT ON COLUMN v_ref_assembly_summary.num_scaffolds IS 'ref_gfastats.num_scaffolds.';
COMMENT ON COLUMN v_ref_assembly_summary.scaffold_n50_size_mb IS 'ref_gfastats.scaffold_n50_size_mb.';
COMMENT ON COLUMN v_ref_assembly_summary.total_scaffold_length_size_mb IS 'ref_gfastats.total_scaffold_length_size_mb.';
COMMENT ON COLUMN v_ref_assembly_summary.gc_content_percent IS 'ref_gfastats.gc_content_percent.';
COMMENT ON COLUMN v_ref_assembly_summary.num_chromosomes IS 'ref_chromosome_stats.num_chromosomes (curated parts only).';
COMMENT ON COLUMN v_ref_assembly_summary.pct_assigned IS 'ref_chromosome_stats.pct_assigned.';
COMMENT ON COLUMN v_ref_assembly_summary.busco_dataset IS 'ref_busco.dataset.';
COMMENT ON COLUMN v_ref_assembly_summary.busco_complete IS 'ref_busco.complete, %.';
COMMENT ON COLUMN v_ref_assembly_summary.busco_single_copy IS 'ref_busco.single_copy, %.';
COMMENT ON COLUMN v_ref_assembly_summary.busco_multi_copy IS 'ref_busco.multi_copy, %.';
COMMENT ON COLUMN v_ref_assembly_summary.busco_fragmented IS 'ref_busco.fragmented, %.';
COMMENT ON COLUMN v_ref_assembly_summary.busco_missing IS 'ref_busco.missing, %.';
COMMENT ON COLUMN v_ref_assembly_summary.qv IS 'ref_merqury_qv.qv.';
COMMENT ON COLUMN v_ref_assembly_summary.kmer_completeness IS 'ref_merqury_completeness.completeness, %.';

COMMENT ON COLUMN v_read_qc_sequencing_readiness.kind IS 'hifi or hic: which read-QC table the row is from.';
COMMENT ON COLUMN v_read_qc_sequencing_readiness.og_id IS 'The specimen.';
COMMENT ON COLUMN v_read_qc_sequencing_readiness.tissue IS 'Tissue code of the read-QC row.';
COMMENT ON COLUMN v_read_qc_sequencing_readiness.ext_type IS 'Extraction code.';
COMMENT ON COLUMN v_read_qc_sequencing_readiness.lib_code IS 'Library code.';
COMMENT ON COLUMN v_read_qc_sequencing_readiness.lane IS 'Lane (hic only).';
COMMENT ON COLUMN v_read_qc_sequencing_readiness.run_id IS 'The run.';
COMMENT ON COLUMN v_read_qc_sequencing_readiness.reason IS 'Why sequencing_id is NULL: run not in sequencing, library tube not in library, several or no matching sequencing rows.';

COMMENT ON COLUMN v_read_set_run_readiness.og_id IS 'The specimen.';
COMMENT ON COLUMN v_read_set_run_readiness.seq_date IS 'ref_read_set.seq_date.';
COMMENT ON COLUMN v_read_set_run_readiness.read_set_id IS 'The read set with no run link.';
COMMENT ON COLUMN v_read_set_run_readiness.pacbio_rows_for_og IS 'The OG''s PacBio DNA sequencing rows not marked Failed, '', ''-joined: the candidates to link.';

COMMENT ON COLUMN v_ref_assembly_run_readiness.og_num IS 'ref_assembly.og_num.';
COMMENT ON COLUMN v_ref_assembly_run_readiness.og_id IS 'The specimen.';
COMMENT ON COLUMN v_ref_assembly_run_readiness.seq_date IS 'ref_assembly.seq_date.';
COMMENT ON COLUMN v_ref_assembly_run_readiness.version IS 'ref_assembly.version.';
COMMENT ON COLUMN v_ref_assembly_run_readiness.long_read_rows_for_og IS 'The OG''s PacBio/ONT DNA sequencing rows not marked Failed, '', ''-joined: the candidates to link.';

COMMENT ON COLUMN v_sequencing_run_fk_readiness.child IS 'The table checked.';
COMMENT ON COLUMN v_sequencing_run_fk_readiness.child_rows IS 'Its rows.';
COMMENT ON COLUMN v_sequencing_run_fk_readiness.failing_rows IS 'Rows whose run_id is not in sequencing_run. 0 while the FKs hold.';
COMMENT ON COLUMN v_sequencing_run_fk_readiness.failing_run_ids IS 'Those run ids, '', ''-joined.';

COMMENT ON COLUMN v_sequencing_run_issues.run_id IS 'The run.';
COMMENT ON COLUMN v_sequencing_run_issues.run_id_unparsed IS 'run_id does not match MACHINE_YYMMDD_INITIALS.';
COMMENT ON COLUMN v_sequencing_run_issues.instrument_disagrees_or_missing IS 'The run''s sequencing rows disagree on instrument, or none has one.';
COMMENT ON COLUMN v_sequencing_run_issues.run_date_disagrees_or_missing IS 'The run''s sequencing rows disagree on run_date, or none has one.';
COMMENT ON COLUMN v_sequencing_run_issues.instruments IS 'The instruments its rows give, '', ''-joined; (null) for a row with none.';
COMMENT ON COLUMN v_sequencing_run_issues.run_dates IS 'The run dates its rows give, '', ''-joined; (null) for a row with none.';

COMMENT ON COLUMN v_sra_upload_run_readiness.og_id IS 'The specimen (ref_submission.og_id).';
COMMENT ON COLUMN v_sra_upload_run_readiness.srr_accession IS 'The upload with no sequencing link.';
COMMENT ON COLUMN v_sra_upload_run_readiness.data_type IS 'ref_sra_upload.data_type.';
COMMENT ON COLUMN v_sra_upload_run_readiness.reason IS 'ref_sra_upload_unlinked.reason, or not resolved by the forward rule where it has not been reviewed.';
COMMENT ON COLUMN v_sra_upload_run_readiness.reviewed_on IS 'ref_sra_upload_unlinked.reviewed_on; NULL where not reviewed.';
COMMENT ON COLUMN v_sra_upload_run_readiness.filenames IS 'The first 200 characters of ref_sra_upload.filenames.';

-- Check: every in-scope object has a table comment, and every in-scope base-table column one ------

DO $chk$
DECLARE
  missing text;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO missing
    FROM pg_class c
   WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v')
     AND c.relname NOT IN ('master_species', 'master_species_genome', 'og_priority_log',
                           'og_workflow_assignment_log', 'og_workflow_notification')
     AND obj_description(c.oid, 'pg_class') IS NULL;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION '079: tables or views without a comment: %', missing;
  END IF;

  SELECT string_agg(format('%s.%s', c.relname, a.attname), ', ' ORDER BY c.relname, a.attnum) INTO missing
    FROM pg_class c
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
   WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
     AND c.relname NOT IN ('master_species', 'master_species_genome', 'og_priority_log',
                           'og_workflow_assignment_log', 'og_workflow_notification')
     AND col_description(c.oid, a.attnum) IS NULL;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION '079: base-table columns without a comment: %', missing;
  END IF;

  SELECT string_agg(format('%s.%s', c.relname, a.attname), ', ' ORDER BY c.relname, a.attnum) INTO missing
    FROM pg_class c
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
   WHERE c.relnamespace = 'public'::regnamespace
     AND c.relname IN ('goat_species_v1', 'goat_project_metadata_v1', 'summary', 'mitogenome_submission_view',
                       'v_draft_genome_status', 'v_ref_assembly_status', 'v_ref_assembly_summary',
                       'v_read_qc_sequencing_readiness', 'v_read_set_run_readiness',
                       'v_ref_assembly_run_readiness', 'v_sequencing_run_fk_readiness',
                       'v_sequencing_run_issues', 'v_sra_upload_run_readiness')
     AND col_description(c.oid, a.attnum) IS NULL;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION '079: contract/reporting view columns without a comment: %', missing;
  END IF;
  RAISE NOTICE '079: every in-scope table, view and column has a comment';
END
$chk$;

COMMIT;
