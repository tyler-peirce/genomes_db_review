-- 088_ncbi_genome_assemblies_comment_reader.sql -- ncbi_genome_assemblies' comment names its reader.
--
-- Why. 086's comment says "No writer and no reading view found". Since 087,
-- v_genome_size_comparison reads the table. Comment only.
--
-- Replay: COMMENT ON overwrites, so a replay is a no-op.
-- Revert: sql/revert/088_ncbi_genome_assemblies_comment_reader_revert.sql (puts 086's text back).

BEGIN;

COMMENT ON TABLE public.ncbi_genome_assemblies IS 'NCBI genome assembly metadata: what is already '
  'assembled for a species. No writer found; no FK to species. Read by v_genome_size_comparison (087), '
  'which matches it on organism_taxonomic_id. The only NCBI assembly table since 085 dropped the empty '
  'species_ncbi_assembly. No primary key: assembly_accession is UNIQUE.';

COMMIT;
