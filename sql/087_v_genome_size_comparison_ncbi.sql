-- 087_v_genome_size_comparison_ncbi.sql -- recreate v_genome_size_comparison on ncbi_genome_assemblies.
--
-- Why. Owner, 2026-11-13: point the view at ncbi_genome_assemblies. 085 dropped it with
-- species_ncbi_assembly, the empty table it read, so its NCBI half had been NULL on every row.
-- ncbi_genome_assemblies (1,830 assemblies of 1,725 taxa, live 2026-11-13) is where NCBI assembly
-- metadata actually is.
--
-- What changes against the pre-085 view:
--   - Same rows: one per draft whose sample's nominal_species_id is in species (as before), with
--     og_num, og_id, species, ncbi_taxon_id, seq_date and estimated_bp (GenomeScope genomesize).
--   - The NCBI assembly is matched on taxon id (organism_taxonomic_id = species.ncbi_taxon_id).
--     That finds 1,053 of 2,085 drafts; matching on the name finds 1,044.
--   - One assembly per taxon, chosen in this order, because 88 taxa have several and 37 have
--     several marked 'reference genome': RefSeq category 'reference genome' first; then level
--     (Complete Genome, Chromosome, Scaffold, Contig); then the latest release; then accession.
--     ncbi_assembly_count says how many there were to choose from.
--   - ncbi_bp and estimated_over_ncbi are gone. ncbi_genome_assemblies has no total sequence
--     length, so neither can be computed; a column that is always NULL would only mislead. If a
--     loader ever adds the length, add them back here. is_refseq and is_representative become
--     refseq_category (NCBI's own value: 'reference genome', '' or 'NaN').
--   - Added from NCBI: assembly_name, assembly_bioproject_accession, release_date, contig_n50.
--
-- Rejected: joining through master_species. It covers vertebrates only and is a colleague's
-- (database_review.md §2); species was the view's source before and still gives the same matches.
--
-- Revert: sql/revert/087_v_genome_size_comparison_ncbi_revert.sql (drops the view). To get the
-- pre-085 view back, revert 087 first, then 085.
-- Replay: CREATE OR REPLACE with the same columns is a no-op.

BEGIN;

CREATE OR REPLACE VIEW public.v_genome_size_comparison AS
SELECT s.og_num,
       d.og_id,
       sp.species,
       sp.ncbi_taxon_id,
       d.seq_date,
       gs.genomesize                   AS estimated_bp,
       a.assembly_accession,
       a.assembly_name,
       a.assembly_level,
       a.assembly_refseq_category      AS refseq_category,
       a.assembly_bioproject_accession,
       a.assembly_release_date         AS release_date,
       a.contig_n50,
       a.ncbi_assembly_count
  FROM public.draft_genome d
  LEFT JOIN public.draft_genomescope gs ON gs.draft_id = d.draft_id
  JOIN public.sample s ON s.og_id = d.og_id
  JOIN public.species sp ON sp.species = s.nominal_species_id
  LEFT JOIN LATERAL (
        SELECT n.*, count(*) OVER () AS ncbi_assembly_count
          FROM public.ncbi_genome_assemblies n
         WHERE n.organism_taxonomic_id = sp.ncbi_taxon_id
         ORDER BY (n.assembly_refseq_category = 'reference genome') DESC NULLS LAST,
                  CASE n.assembly_level WHEN 'Complete Genome' THEN 1 WHEN 'Chromosome' THEN 2
                                        WHEN 'Scaffold' THEN 3 WHEN 'Contig' THEN 4 ELSE 5 END,
                  n.assembly_release_date DESC NULLS LAST,
                  n.assembly_accession
         LIMIT 1) a ON true;

COMMENT ON VIEW public.v_genome_size_comparison IS 'Per draft: the GenomeScope genome size, beside the NCBI '
  'assembly chosen for the nominal species (ncbi_genome_assemblies, matched on taxon id). One assembly per '
  'taxon: RefSeq reference genome first, then the most complete level, then the latest release. '
  'ncbi_genome_assemblies has no total length, so there is no NCBI size or ratio (087).';
COMMENT ON COLUMN public.v_genome_size_comparison.estimated_bp IS 'draft_genomescope.genomesize, bp. Check genome_size_reliable before quoting it.';
COMMENT ON COLUMN public.v_genome_size_comparison.ncbi_taxon_id IS 'species.ncbi_taxon_id of the nominal species; the key the NCBI assembly is matched on.';
COMMENT ON COLUMN public.v_genome_size_comparison.assembly_accession IS 'The chosen NCBI assembly (GCA_/GCF_). NULL: NCBI has no assembly for the taxon in ncbi_genome_assemblies.';
COMMENT ON COLUMN public.v_genome_size_comparison.refseq_category IS 'NCBI RefSeq category: ''reference genome'', '''' or ''NaN''.';
COMMENT ON COLUMN public.v_genome_size_comparison.contig_n50 IS 'NCBI contig N50 of the chosen assembly, bp.';
COMMENT ON COLUMN public.v_genome_size_comparison.ncbi_assembly_count IS 'How many assemblies ncbi_genome_assemblies holds for the taxon; the view shows one.';

GRANT SELECT ON public.v_genome_size_comparison TO readonly;

COMMIT;
