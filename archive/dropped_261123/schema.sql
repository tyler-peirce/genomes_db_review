--
-- PostgreSQL database dump
--

\restrict mcpW2Q0tiC7nhSruxoOXlgs2QsHdPeuatey5zQjaZtNwgD2rVjw5zzrIyw2Iqf4

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
-- Name: ena_specimen_accessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ena_specimen_accessions (
    og_id text NOT NULL,
    og_numeric integer NOT NULL,
    ena_biosample_accession text,
    accession_source text,
    verified_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ena_specimen_biosample_check CHECK (((ena_biosample_accession IS NULL) OR (ena_biosample_accession ~ '^SAM(EA|N|D)[0-9]+$'::text))),
    CONSTRAINT ena_specimen_og_id_check CHECK ((og_id ~ '^OG[0-9]+$'::text)),
    CONSTRAINT ena_specimen_og_numeric_check CHECK (((og_numeric >= 0) AND (og_numeric <= 999999))),
    CONSTRAINT ena_specimen_og_numeric_matches_check CHECK ((og_numeric = (SUBSTRING(og_id FROM 3))::integer))
);


ALTER TABLE public.ena_specimen_accessions OWNER TO postgres;

--
-- Name: TABLE ena_specimen_accessions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.ena_specimen_accessions IS 'Specimen registry for ENA: one row per OG with an ENA-referenceable BioSample, where one is known. Filled by the mito pipeline bin/backfill_ena_specimen_accessions.py; 1 of 2,848 rows has an accession. Whether to keep it or make it a view over sample is open (§11 Q14).';


--
-- Name: COLUMN ena_specimen_accessions.og_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ena_specimen_accessions.og_id IS 'The sample (FK to sample).';


--
-- Name: COLUMN ena_specimen_accessions.og_numeric; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ena_specimen_accessions.og_numeric IS 'Numeric part of og_id (checked to match).';


--
-- Name: COLUMN ena_specimen_accessions.ena_biosample_accession; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ena_specimen_accessions.ena_biosample_accession IS 'SAMEA/SAMN/SAMD accession. A SAMN is NCBI-registered and webin-cli cannot resolve it (007).';


--
-- Name: COLUMN ena_specimen_accessions.accession_source; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ena_specimen_accessions.accession_source IS 'Where the accession came from, e.g. sample,draft_genomes.';


--
-- Name: COLUMN ena_specimen_accessions.verified_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ena_specimen_accessions.verified_at IS 'When the accession was last checked.';


--
-- Name: COLUMN ena_specimen_accessions.updated_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.ena_specimen_accessions.updated_at IS 'When the row was last written.';


--
-- Name: raw_data; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.raw_data (
    og_id text,
    run_id text NOT NULL,
    lane_id text NOT NULL,
    filename text NOT NULL,
    og_num integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED
);


ALTER TABLE public.raw_data OWNER TO postgres;

--
-- Name: TABLE raw_data; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.raw_data IS 'Raw sequencing files: one row per FASTQ file of an OG on a run and lane. No current writer found in the pipeline repositories; took no new rows Jul-Nov 2026 (§11 Q13). FK run_id to sequencing_run (075).';


--
-- Name: COLUMN raw_data.og_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.raw_data.og_id IS 'The sample (FK to sample). NULL on 30 rows.';


--
-- Name: COLUMN raw_data.run_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.raw_data.run_id IS 'The run (FK to sequencing_run).';


--
-- Name: COLUMN raw_data.lane_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.raw_data.lane_id IS 'Library and lane as the sequencer named them, e.g. F15-0238_L1.';


--
-- Name: COLUMN raw_data.filename; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.raw_data.filename IS 'The FASTQ file name.';


--
-- Name: COLUMN raw_data.og_num; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.raw_data.og_num IS 'Numeric part of og_id, for sorting. Generated.';


--
-- Name: ena_specimen_accessions ena_specimen_accessions_ena_biosample_accession_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ena_specimen_accessions
    ADD CONSTRAINT ena_specimen_accessions_ena_biosample_accession_key UNIQUE (ena_biosample_accession);


--
-- Name: ena_specimen_accessions ena_specimen_accessions_og_numeric_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ena_specimen_accessions
    ADD CONSTRAINT ena_specimen_accessions_og_numeric_key UNIQUE (og_numeric);


--
-- Name: ena_specimen_accessions ena_specimen_accessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ena_specimen_accessions
    ADD CONSTRAINT ena_specimen_accessions_pkey PRIMARY KEY (og_id);


--
-- Name: raw_data raw_data_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.raw_data
    ADD CONSTRAINT raw_data_pkey PRIMARY KEY (run_id, lane_id, filename);


--
-- Name: raw_data_og_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX raw_data_og_id_idx ON public.raw_data USING btree (og_id);


--
-- Name: ena_specimen_accessions ena_specimen_accessions_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ena_specimen_accessions
    ADD CONSTRAINT ena_specimen_accessions_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: raw_data raw_data_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.raw_data
    ADD CONSTRAINT raw_data_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: raw_data raw_data_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.raw_data
    ADD CONSTRAINT raw_data_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.sequencing_run(run_id);


--
-- Name: TABLE ena_specimen_accessions; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.ena_specimen_accessions TO readonly;


--
-- Name: TABLE raw_data; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.raw_data TO readonly;


--
-- PostgreSQL database dump complete
--

\unrestrict mcpW2Q0tiC7nhSruxoOXlgs2QsHdPeuatey5zQjaZtNwgD2rVjw5zzrIyw2Iqf4

