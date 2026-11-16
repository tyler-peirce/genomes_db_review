-- Revert 085_drop_unused_tables.sql: recreate species_ncbi_assembly, ena_locus_registry_archive,
-- ena_candidate_loci_archive and v_genome_size_comparison, empty, as they were on live on
-- 2026-11-13 (from pg_dump --schema-only of those four objects): columns, comments, keys,
-- indexes, the FK onto species and the readonly grants. The tables were empty, so no rows return.
--     psql -f sql/revert/085_drop_unused_tables_revert.sql   then delete 085's ledger row.

BEGIN;

--
--


--
-- Name: ena_candidate_loci_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ena_candidate_loci_archive (
    full_seqid text,
    og_id text,
    gene_serial integer,
    locus_tag text,
    feature_key text,
    start_coordinate integer,
    end_coordinate integer,
    strand character(1),
    created_at timestamp with time zone
);

--
-- Name: TABLE ena_candidate_loci_archive; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ena_candidate_loci_archive IS 'Frozen copy of ena_candidate_loci as of migration 010. Records the per-candidate locus tags this pipeline submitted before locus-tag assignment moved to the downstream submission pipeline. Historical reference only.';

--
-- Name: COLUMN ena_candidate_loci_archive.full_seqid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_candidate_loci_archive.full_seqid IS 'The annotation. Archive: empty, frozen by 010.';

--
-- Name: COLUMN ena_candidate_loci_archive.og_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_candidate_loci_archive.og_id IS 'The sample.';

--
-- Name: COLUMN ena_candidate_loci_archive.gene_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_candidate_loci_archive.gene_serial IS 'Serial from ena_locus_registry_archive.';

--
-- Name: COLUMN ena_candidate_loci_archive.locus_tag; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_candidate_loci_archive.locus_tag IS 'Locus tag submitted.';

--
-- Name: COLUMN ena_candidate_loci_archive.feature_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_candidate_loci_archive.feature_key IS 'Feature key.';

--
-- Name: COLUMN ena_candidate_loci_archive.start_coordinate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_candidate_loci_archive.start_coordinate IS 'Start, bp.';

--
-- Name: COLUMN ena_candidate_loci_archive.end_coordinate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_candidate_loci_archive.end_coordinate IS 'End, bp.';

--
-- Name: COLUMN ena_candidate_loci_archive.strand; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_candidate_loci_archive.strand IS 'Strand.';

--
-- Name: COLUMN ena_candidate_loci_archive.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_candidate_loci_archive.created_at IS 'When written.';

--
-- Name: ena_locus_registry_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ena_locus_registry_archive (
    og_id text,
    gene_serial integer,
    canonical_gene text,
    gene_occurrence integer,
    feature_type text,
    strand character(1),
    feature_sequence_sha256 character(64),
    coordinate_snapshot text,
    allocation_status text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);

--
-- Name: TABLE ena_locus_registry_archive; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ena_locus_registry_archive IS 'Frozen copy of ena_locus_registry as of migration 010. Records the specimen gene serials this pipeline allocated before locus-tag assignment moved to the downstream submission pipeline. Historical reference only: do not write to it and do not treat it as the current tag assignment.';

--
-- Name: COLUMN ena_locus_registry_archive.og_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.og_id IS 'The sample. Archive: empty, frozen by 010.';

--
-- Name: COLUMN ena_locus_registry_archive.gene_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.gene_serial IS 'Serial allocated for the gene within the specimen.';

--
-- Name: COLUMN ena_locus_registry_archive.canonical_gene; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.canonical_gene IS 'Canonical gene name.';

--
-- Name: COLUMN ena_locus_registry_archive.gene_occurrence; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.gene_occurrence IS 'Occurrence of the gene, where it appears more than once.';

--
-- Name: COLUMN ena_locus_registry_archive.feature_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.feature_type IS 'Feature type (CDS, tRNA, rRNA).';

--
-- Name: COLUMN ena_locus_registry_archive.strand; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.strand IS 'Strand.';

--
-- Name: COLUMN ena_locus_registry_archive.feature_sequence_sha256; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.feature_sequence_sha256 IS 'SHA-256 of the feature sequence.';

--
-- Name: COLUMN ena_locus_registry_archive.coordinate_snapshot; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.coordinate_snapshot IS 'Coordinates when allocated.';

--
-- Name: COLUMN ena_locus_registry_archive.allocation_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.allocation_status IS 'Allocation state.';

--
-- Name: COLUMN ena_locus_registry_archive.created_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.created_at IS 'When allocated.';

--
-- Name: COLUMN ena_locus_registry_archive.updated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ena_locus_registry_archive.updated_at IS 'When last changed.';

--
-- Name: species_ncbi_assembly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.species_ncbi_assembly (
    assembly_accession text NOT NULL,
    species text NOT NULL,
    ncbi_taxon_id integer NOT NULL,
    assembly_name text,
    assembly_level text,
    total_sequence_length bigint,
    is_refseq boolean DEFAULT false NOT NULL,
    is_representative boolean DEFAULT false NOT NULL,
    is_chosen boolean DEFAULT false NOT NULL,
    release_date date,
    retrieved_at timestamp without time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE species_ncbi_assembly; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.species_ncbi_assembly IS 'Planned NCBI assembly table, with a species FK and one chosen assembly per species. Empty since it was created; ncbi_genome_assemblies holds the data. v_genome_size_comparison reads this table, so its NCBI columns are NULL on every row until the two are consolidated (backlog item).';

--
-- Name: COLUMN species_ncbi_assembly.assembly_accession; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.assembly_accession IS 'GCA_/GCF_ accession.';

--
-- Name: COLUMN species_ncbi_assembly.species; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.species IS 'The species (FK to species).';

--
-- Name: COLUMN species_ncbi_assembly.ncbi_taxon_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.ncbi_taxon_id IS 'NCBI Taxonomy id.';

--
-- Name: COLUMN species_ncbi_assembly.assembly_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.assembly_name IS 'Assembly name.';

--
-- Name: COLUMN species_ncbi_assembly.assembly_level; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.assembly_level IS 'Contig, Scaffold, Chromosome or Complete Genome.';

--
-- Name: COLUMN species_ncbi_assembly.total_sequence_length; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.total_sequence_length IS 'bp.';

--
-- Name: COLUMN species_ncbi_assembly.is_refseq; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.is_refseq IS 'A RefSeq assembly.';

--
-- Name: COLUMN species_ncbi_assembly.is_representative; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.is_representative IS 'NCBI''s representative assembly for the species.';

--
-- Name: COLUMN species_ncbi_assembly.is_chosen; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.is_chosen IS 'The one assembly chosen for the species (partial unique index).';

--
-- Name: COLUMN species_ncbi_assembly.release_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.release_date IS 'Release date.';

--
-- Name: COLUMN species_ncbi_assembly.retrieved_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.species_ncbi_assembly.retrieved_at IS 'When the row was fetched from NCBI.';

--
-- Name: v_genome_size_comparison; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_genome_size_comparison AS
 SELECT s.og_num,
    d.og_id,
    sp.species,
    sp.ncbi_taxon_id,
    d.seq_date,
    gs.genomesize AS estimated_bp,
    a.total_sequence_length AS ncbi_bp,
        CASE
            WHEN (a.total_sequence_length > 0) THEN round(((gs.genomesize)::numeric / (a.total_sequence_length)::numeric), 3)
            ELSE NULL::numeric
        END AS estimated_over_ncbi,
    a.assembly_accession,
    a.assembly_level,
    a.is_refseq,
    a.is_representative
   FROM ((((public.draft_genome d
     LEFT JOIN public.draft_genomescope gs ON ((gs.draft_id = d.draft_id)))
     JOIN public.sample s ON ((s.og_id = d.og_id)))
     JOIN public.species sp ON ((s.nominal_species_id = sp.species)))
     LEFT JOIN public.species_ncbi_assembly a ON (((a.species = sp.species) AND a.is_chosen)));

--
-- Name: VIEW v_genome_size_comparison; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_genome_size_comparison IS 'Per draft: the GenomeScope genome size against the chosen NCBI assembly of the nominal species. Reads species_ncbi_assembly, which is empty, so ncbi_bp and the columns after it are NULL on every row until it is consolidated with ncbi_genome_assemblies.';

--
-- Name: species_ncbi_assembly species_ncbi_assembly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.species_ncbi_assembly
    ADD CONSTRAINT species_ncbi_assembly_pkey PRIMARY KEY (assembly_accession);

--
-- Name: species_ncbi_assembly_one_chosen_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX species_ncbi_assembly_one_chosen_idx ON public.species_ncbi_assembly USING btree (species) WHERE is_chosen;

--
-- Name: species_ncbi_assembly_species_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX species_ncbi_assembly_species_idx ON public.species_ncbi_assembly USING btree (species);

--
-- Name: species_ncbi_assembly species_ncbi_assembly_species_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.species_ncbi_assembly
    ADD CONSTRAINT species_ncbi_assembly_species_fkey FOREIGN KEY (species) REFERENCES public.species(species);

--
-- Name: TABLE ena_candidate_loci_archive; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.ena_candidate_loci_archive TO readonly;

--
-- Name: TABLE ena_locus_registry_archive; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.ena_locus_registry_archive TO readonly;

--
-- Name: TABLE species_ncbi_assembly; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.species_ncbi_assembly TO readonly;

--
-- Name: TABLE v_genome_size_comparison; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.v_genome_size_comparison TO readonly;

--
--


COMMIT;
