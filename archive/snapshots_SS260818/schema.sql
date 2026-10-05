--
-- PostgreSQL database dump
--

\restrict Zj1hIcCrIaA3PlBYkQiXZgB71roaowwG7MewEcbNZEcaQEicsBYy4c4Dms2mT9c

-- Dumped from database version 14.24 (Ubuntu 14.24-0ubuntu0.22.04.1)
-- Dumped by pg_dump version 14.24 (Ubuntu 14.24-0ubuntu0.22.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: blast_filtered_lca_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."blast_filtered_lca_SS260818" (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    match_sequence_id text NOT NULL,
    taxon_id integer,
    scientific_name text,
    common_name text,
    kingdoms text,
    percent_identity double precision,
    alignment_length integer,
    query_length integer,
    subject_length integer,
    mismatch integer,
    gap_open integer,
    gaps integer,
    query_start integer,
    query_end integer,
    subject_start integer,
    subject_end integer,
    subject_title text,
    evalue double precision,
    bit_score double precision,
    query_coverage double precision,
    subject_coverage double precision,
    region text NOT NULL,
    blast_run_date text
);


--
-- Name: lca_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."lca_SS260818" (
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    region text NOT NULL,
    lca_run_date text,
    species_in_lca text,
    number_unq_blast_hits integer,
    domain text,
    phylum text,
    class text,
    "order" text,
    family text,
    genus text,
    specific_epiphet text,
    species text,
    scientific_name_authorship character varying,
    taxon_rank text,
    top_taxon_id character varying,
    taxon_id_db character varying,
    top_accession_id character varying,
    accession_id_ref_db character varying,
    top_percent_query_cover real,
    top_percent_query_cover_hsp real,
    alignment_length integer,
    subject_length integer,
    sequence_length integer,
    top_confidence_score real,
    top_percent_match double precision
);


--
-- Name: lca_old; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lca_old (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    taxonomy text,
    lca text,
    top_percent_match real,
    length integer,
    lca_run_date text,
    region text NOT NULL,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    class text,
    "order" text,
    family text,
    genus text,
    species text,
    coverage real,
    specific_epiphet text,
    scientific_name_authorship character varying,
    taxon_rank text,
    top_taxon_id character varying,
    taxon_id_db character varying,
    top_accession_id character varying,
    accession_id_ref_db character varying,
    top_percent_query_cover real,
    top_percent_query_cover_hsp real,
    alignment_length integer,
    subject_length integer,
    sequence_length integer,
    top_confidence_score real,
    species_in_lca text,
    number_unq_blast_hits integer,
    domain text,
    phylum text
);


--
-- Name: lca_pivot_view_SS260818; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public."lca_pivot_view_SS260818" AS
 SELECT (regexp_replace("lca_SS260818".og_id, 'OG'::text, ''::text, 'g'::text))::integer AS og_num,
    "lca_SS260818".og_id AS og_id_lp,
    "lca_SS260818".tech,
    "lca_SS260818".seq_date,
    "lca_SS260818".code,
    "lca_SS260818".annotation,
    max("lca_SS260818".species_in_lca) FILTER (WHERE ("lca_SS260818".region = '12s'::text)) AS s12_lca,
    max("lca_SS260818".species_in_lca) FILTER (WHERE ("lca_SS260818".region = '16s'::text)) AS s16_lca,
    max("lca_SS260818".species_in_lca) FILTER (WHERE ("lca_SS260818".region = 'CO1'::text)) AS co1_lca
   FROM public."lca_SS260818"
  GROUP BY "lca_SS260818".og_id, "lca_SS260818".tech, "lca_SS260818".seq_date, "lca_SS260818".code, "lca_SS260818".annotation;


--
-- Name: lca_raw_results_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."lca_raw_results_SS260818" (
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    sequence_region text,
    lca_run_date integer,
    domain text,
    phylum text,
    class text,
    "order" text,
    family text,
    genus text,
    specific_epiphet text,
    scientific_name text,
    scientific_name_authorship text,
    taxon_rank text,
    taxon_id character varying,
    taxon_id_db character varying,
    verbatim_identification text,
    accession_id character varying,
    accession_id_ref_db text,
    percent_match real,
    percent_query_cover real,
    percent_query_cover_hsp real,
    alignment_length integer,
    subject_length integer,
    sequence_length integer,
    confidence_score real
);


--
-- Name: lca_results_view_SS260818; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public."lca_results_view_SS260818" AS
 SELECT lp.og_id_lp AS og_id_lr,
    lp.tech,
    lp.seq_date,
    lp.code,
    lp.annotation,
    s.nominal_species_id,
    lp.s12_lca,
    lp.s16_lca,
    lp.co1_lca,
        CASE
            WHEN (s.nominal_species_id IS NULL) THEN 'MISSING NOMINAL ID'::text
            WHEN (((s.nominal_species_id = lp.s12_lca) OR (s.nominal_species_id = lp.s16_lca)) OR (s.nominal_species_id = lp.co1_lca)) THEN s.nominal_species_id
            ELSE 'INVESTIGATE'::text
        END AS validation_status
   FROM (public."lca_pivot_view_SS260818" lp
     JOIN public.sample s ON ((lp.og_id_lp = s.og_id)));


--
-- Name: lca_validation_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."lca_validation_SS260818" (
    og_id text NOT NULL,
    tech text NOT NULL,
    validated_species_name text,
    validator text,
    nominal_species_id_lca_comment text,
    validator_2 text,
    data_release character varying,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    seq_date text NOT NULL,
    code character varying NOT NULL,
    annotation character varying NOT NULL,
    row_created_on timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: lca_validation_report_view_SS260818; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public."lca_validation_report_view_SS260818" AS
 SELECT (regexp_replace(lv.og_id, 'OG'::text, ''::text, 'g'::text))::integer AS og_num,
    sv.proj_id,
    lv.og_id,
    lv.tech,
    lv.seq_date,
    lv.code,
    lv.annotation,
    lp.s12_lca,
    lp.s16_lca,
    lp.co1_lca,
    lr.validation_status,
    sv.nom_id,
    lv.validated_species_name,
    lv.validator,
    lv.validator_2,
    lca_tax.lca_taxon_ranks,
    lca_tax.lca_orders,
    lca_tax.lca_families,
    lca_tax.lca_genera,
    lca_tax.lca_specific_epiphets,
        CASE
            WHEN ((flv.filtered_12s IS NOT NULL) OR (flv.filtered_16s IS NOT NULL) OR (flv.filtered_co1 IS NOT NULL)) THEN 'YES'::text
            ELSE NULL::text
        END AS nom_id_in_results,
    lv.nominal_species_id_lca_comment AS comment,
    lv.data_release,
    flv.filtered_12s,
    flv.filtered_16s,
    flv.filtered_co1,
    sv.photo_id_sv,
    sv.photo_vouch_sv,
    sv.specimen_vouch_sv,
    sv.vouch_id_sv
   FROM (((((public."lca_validation_SS260818" lv
     LEFT JOIN public."lca_pivot_view_SS260818" lp ON (((lp.og_id_lp = lv.og_id) AND (lp.tech = lv.tech) AND (lp.seq_date = lv.seq_date) AND (lp.code = (lv.code)::text) AND (lp.annotation = (lv.annotation)::text))))
     LEFT JOIN public."lca_results_view_SS260818" lr ON (((lr.og_id_lr = lv.og_id) AND (lr.tech = lv.tech) AND (lr.seq_date = lv.seq_date) AND (lr.code = (lv.code)::text) AND (lr.annotation = (lv.annotation)::text))))
     LEFT JOIN public.filtered_lca_view flv ON (((flv.og_id_flv = lv.og_id) AND (flv.tech = lv.tech) AND (flv.seq_date = lv.seq_date) AND (flv.code = (lv.code)::text) AND (flv.annotation = (lv.annotation)::text))))
     LEFT JOIN ( SELECT "lca_SS260818".og_id,
            "lca_SS260818".tech,
            "lca_SS260818".seq_date,
            "lca_SS260818".code,
            "lca_SS260818".annotation,
            string_agg(DISTINCT "lca_SS260818".taxon_rank, ', '::text ORDER BY "lca_SS260818".taxon_rank) AS lca_taxon_ranks,
            string_agg(DISTINCT "lca_SS260818"."order", ', '::text ORDER BY "lca_SS260818"."order") AS lca_orders,
            string_agg(DISTINCT "lca_SS260818".family, ', '::text ORDER BY "lca_SS260818".family) AS lca_families,
            string_agg(DISTINCT "lca_SS260818".genus, ', '::text ORDER BY "lca_SS260818".genus) AS lca_genera,
            string_agg(DISTINCT "lca_SS260818".specific_epiphet, ', '::text ORDER BY "lca_SS260818".specific_epiphet) AS lca_specific_epiphets
           FROM public."lca_SS260818"
          GROUP BY "lca_SS260818".og_id, "lca_SS260818".tech, "lca_SS260818".seq_date, "lca_SS260818".code, "lca_SS260818".annotation) lca_tax ON (((lca_tax.og_id = lv.og_id) AND (lca_tax.tech = lv.tech) AND (lca_tax.seq_date = lv.seq_date) AND (lca_tax.code = (lv.code)::text) AND (lca_tax.annotation = (lv.annotation)::text))))
     LEFT JOIN public.sample_view sv ON ((lv.og_id = sv.og_id_sv)));


--
-- Name: mitogenome_data_SS260818; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."mitogenome_data_SS260818" (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    stats text,
    length integer,
    length_emma integer,
    seqlength_12s integer,
    seqlength_16s integer,
    seqlength_co1 integer,
    cds_no integer,
    trna_no integer,
    rrna_no integer,
    status text,
    genbank text,
    rrna12s integer,
    rrna16s integer,
    atp6 integer,
    atp8 integer,
    cox1 integer,
    cox2 integer,
    cox3 integer,
    cytb integer,
    nad1 integer,
    nad2 integer,
    nad3 integer,
    nad4 integer,
    nad4l integer,
    nad5 integer,
    nad6 integer,
    trna_phe integer,
    trna_val integer,
    trna_leuuag integer,
    trna_leuuaa integer,
    trna_ile integer,
    trna_met integer,
    trna_thr integer,
    trna_pro integer,
    trna_lys integer,
    trna_asp integer,
    trna_glu integer,
    trna_sergcu integer,
    trna_seruga integer,
    trna_tyr integer,
    trna_cys integer,
    trna_trp integer,
    trna_ala integer,
    trna_asn integer,
    trna_gly integer,
    trna_arg integer,
    trna_his integer,
    trna_gln integer,
    manual_curation_notes text,
    bankit character varying,
    genbank_accession character varying,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    annotation character varying,
    date_submitted_genbank date,
    avg_coverage real,
    avg_base_coverage real,
    atp6_trans integer,
    atp8_trans integer,
    cox1_trans integer,
    cox2_trans integer,
    cox3_trans integer,
    cytb_trans integer,
    nad1_trans integer,
    nad2_trans integer,
    nad3_trans integer,
    nad4_trans integer,
    nad4l_trans integer,
    nad5_trans integer,
    nad6_trans integer,
    extra_genes character varying,
    missing_genes character varying,
    order_correct character varying,
    passed character varying,
    mean_depth double precision,
    median_depth double precision,
    depth_sd double precision,
    depth_cv double precision,
    breadth_1x double precision,
    breadth_10x double precision,
    mito_mapped_reads bigint,
    total_reads bigint,
    mito_read_fraction double precision,
    depth_target_length_bp integer,
    depth_target_fasta text,
    depth_method text,
    depth_measured_at timestamp with time zone
);


--
-- Name: COLUMN "mitogenome_data_SS260818".avg_coverage; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."mitogenome_data_SS260818".avg_coverage IS 'LEGACY, assembler-specific and NOT comparable across assemblers: k-mer coverage for GetOrganelle rows, reference-recruited read depth for MitoHiFi rows, NULL for Oatk. Retained for provenance. See mean_depth.';


--
-- Name: COLUMN "mitogenome_data_SS260818".mean_depth; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."mitogenome_data_SS260818".mean_depth IS 'Mean per-base read depth of the sample''s own reads remapped to this assembly. Comparable across GetOrganelle / MitoHiFi / Oatk and across Illumina / HiC / HiFi. Use this, not avg_coverage, for any cross-platform comparison.';


--
-- Name: COLUMN "mitogenome_data_SS260818".depth_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."mitogenome_data_SS260818".depth_method IS 'remap_full_v1  = mean_depth measured by remapping the full post-QC read set to this assembly (circular molecules folded on a doubled reference). not_measured   = this assembly never reached annotation (failed, under-length, or a discarded assembly variant), or the depth step was skipped. legacy_*       = pre-dates the uniform measurement; only the assembler-specific avg_coverage / avg_base_coverage values exist for this row.';


--
-- Name: blast_filtered_lca_SS260818 blast_filtered_lca_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."blast_filtered_lca_SS260818"
    ADD CONSTRAINT blast_filtered_lca_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation, match_sequence_id, region);


--
-- Name: lca_raw_results_SS260818 lca_raw_results_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_raw_results_SS260818"
    ADD CONSTRAINT lca_raw_results_unique UNIQUE (og_id, tech, seq_date, code, annotation, sequence_region, lca_run_date, accession_id);


--
-- Name: lca_SS260818 lca_results_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_SS260818"
    ADD CONSTRAINT lca_results_unique UNIQUE (og_id, tech, seq_date, code, annotation, region, lca_run_date);


--
-- Name: lca_old lca_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_old
    ADD CONSTRAINT lca_unique UNIQUE (og_id, tech, seq_date, code, annotation, region, lca_run_date);


--
-- Name: lca_validation_SS260818 lca_validation_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_validation_SS260818"
    ADD CONSTRAINT lca_validation_pk PRIMARY KEY (og_id, tech, seq_date, code, annotation);


--
-- Name: mitogenome_data_SS260818 mitogenome_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."mitogenome_data_SS260818"
    ADD CONSTRAINT mitogenome_data_pkey PRIMARY KEY (og_id, tech, seq_date, code);


--
-- Name: mitogenome_data_SS260818 mitogenome_data_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."mitogenome_data_SS260818"
    ADD CONSTRAINT mitogenome_data_unique UNIQUE (og_id, tech, seq_date, code, annotation);


--
-- Name: mitogenome_data_depth_method_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mitogenome_data_depth_method_idx ON public."mitogenome_data_SS260818" USING btree (depth_method);


--
-- Name: lca_validation_report_view_SS260818 trg_lca_validation_report_view_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lca_validation_report_view_upd INSTEAD OF UPDATE ON public."lca_validation_report_view_SS260818" FOR EACH ROW EXECUTE FUNCTION public.lca_validation_report_view_upd();


--
-- Name: lca_SS260818 fk_mitogenome; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_SS260818"
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public."mitogenome_data_SS260818"(og_id, tech, seq_date, code);


--
-- Name: lca_old fk_mitogenome; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lca_old
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public."mitogenome_data_SS260818"(og_id, tech, seq_date, code);


--
-- Name: lca_raw_results_SS260818 fk_mitogenome; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_raw_results_SS260818"
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public."mitogenome_data_SS260818"(og_id, tech, seq_date, code);


--
-- Name: lca_validation_SS260818 lca_validation_mitogenome_data_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."lca_validation_SS260818"
    ADD CONSTRAINT lca_validation_mitogenome_data_fk FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public."mitogenome_data_SS260818"(og_id, tech, seq_date, code);


--
-- PostgreSQL database dump complete
--

\unrestrict Zj1hIcCrIaA3PlBYkQiXZgB71roaowwG7MewEcbNZEcaQEicsBYy4c4Dms2mT9c

