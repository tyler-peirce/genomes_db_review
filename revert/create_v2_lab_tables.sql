-- Revert genomes_db:create_v2_lab_tables from pg

-- Rollback notes: safe at any point before the (future, separate) import/backfill work
-- starts populating these tables — they hold no data until then.

BEGIN;

DROP TABLE IF EXISTS public.v2_sequencing;
DROP TABLE IF EXISTS public.v2_rna_library_kinx;
DROP TABLE IF EXISTS public.v2_rna_library_ilmn;
DROP TABLE IF EXISTS public.v2_hic_library;
DROP TABLE IF EXISTS public.v2_pacbio_library;
DROP TABLE IF EXISTS public.v2_ont_library;
DROP TABLE IF EXISTS public.v2_illumina_library;
DROP TABLE IF EXISTS public.v2_hic_lysate;
DROP TABLE IF EXISTS public.v2_rna_extraction;
DROP TABLE IF EXISTS public.v2_dna_extraction;
DROP TABLE IF EXISTS public.v2_tissue;
DROP TABLE IF EXISTS public.v2_sample;

COMMIT;
