-- 086_ncbi_genome_assemblies_comment.sql -- correct ncbi_genome_assemblies' table comment after 085.
--
-- Why. 079's comment says the empty species_ncbi_assembly "was meant to hold the same and is what
-- v_genome_size_comparison reads; consolidating them is a backlog item". 085 dropped both, so the
-- comment pointed at objects that no longer exist. Comment only; no data or structure changes.
--
-- Replay: COMMENT ON overwrites, so a replay is a no-op.
-- Revert: sql/revert/086_ncbi_genome_assemblies_comment_revert.sql (puts 079's text back).

BEGIN;

COMMENT ON TABLE public.ncbi_genome_assemblies IS 'NCBI genome assembly metadata: what is already '
  'assembled for a species. No writer and no reading view found; no FK to species. The only NCBI '
  'assembly table since 085 dropped the empty species_ncbi_assembly. No primary key: '
  'assembly_accession is UNIQUE.';

COMMIT;
