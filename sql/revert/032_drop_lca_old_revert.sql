-- Revert 032_drop_lca_old.sql.
--
-- STRUCTURE ONLY. THIS DOES NOT RESTORE ANY DATA.
--
-- Recreates the empty lca_old table with its unique constraint and its foreign
-- key to mitogenome_data_SS260818, exactly as at 2026-10-05.
--
-- The 2,895 rows are NOT restored, deliberately: they are superseded output
-- from an LCA run that has since been redone from scratch, which is why the
-- table was dropped. If you genuinely need them:
--
--     zcat archive/snapshots_SS260818/lca_old.csv.gz | \
--       psql -c '\copy lca_old from stdin with (format csv, header)'
--
-- (The export omits og_num, which is GENERATED and recomputes itself, so that
-- load needs no column list. Do not pass the CSV through any tool that
-- re-serialises it -- that turns "" into NULL.)
--
-- This revert restores fk_mitogenome, so it only succeeds while
-- mitogenome_data_SS260818 still exists. If the snapshots have since been
-- dropped, create the table without that constraint.
--
-- Generated from pg_dump --schema-only immediately before the drop.

BEGIN;

\restrict vHXE6hgQC6EgsvnLRda2Ke9nAjH0YZhHV7ddRMyKrdm0aISfqltgmjZntgaNadc
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
ALTER TABLE ONLY public.lca_old
    ADD CONSTRAINT lca_unique UNIQUE (og_id, tech, seq_date, code, annotation, region, lca_run_date);
ALTER TABLE ONLY public.lca_old
    ADD CONSTRAINT fk_mitogenome FOREIGN KEY (og_id, tech, seq_date, code) REFERENCES public."mitogenome_data_SS260818"(og_id, tech, seq_date, code);
\unrestrict vHXE6hgQC6EgsvnLRda2Ke9nAjH0YZhHV7ddRMyKrdm0aISfqltgmjZntgaNadc

COMMIT;
