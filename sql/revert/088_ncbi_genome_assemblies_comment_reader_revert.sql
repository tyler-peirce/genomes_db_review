-- Revert 088_ncbi_genome_assemblies_comment_reader.sql: put back 086's table comment.
--     psql -f sql/revert/088_ncbi_genome_assemblies_comment_reader_revert.sql   then delete 088's ledger row.

BEGIN;

COMMENT ON TABLE public.ncbi_genome_assemblies IS 'NCBI genome assembly metadata: what is already assembled for a species. No writer and no reading view found; no FK to species. The only NCBI assembly table since 085 dropped the empty species_ncbi_assembly. No primary key: assembly_accession is UNIQUE.';

COMMIT;
