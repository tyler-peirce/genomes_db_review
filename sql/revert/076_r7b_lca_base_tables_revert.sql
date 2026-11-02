-- Revert 076_r7b_lca_base_tables.sql: lca, lca_raw_results, lca_validation and blast_filtered_lca
-- become tables again, exactly as before 076, refilled from the mito_* base tables.
--
-- The table definitions (pre- and post-data) are pg_dump's of live just before 076 (2026-11-02).
-- Rows are copied back through the annotation join, so rows written after 076 come back too.
-- content_hash is recomputed by the restored trigger, which reproduces the pre-076 hashes (before
-- 076 every stored hash equalled a fresh computation). The ten dependent views are recreated from
-- their own definitions, and lca_validation_report_view_upd() from its pre-076 body.
--
-- After it, the r7b-lca-base-tables writers fail (no mito_* tables) and the pre-076 writers work:
-- reset the mito pipeline's inverts-dev to its pre-merge SHA the same day.
--
-- Opt-in:  PGOPTIONS="-c oceanomics.r7b_revert=yes" psql -f sql/revert/076_r7b_lca_base_tables_revert.sql
-- then delete 076's ledger row.

BEGIN;

DO $rv1$
BEGIN
  IF coalesce(current_setting('oceanomics.r7b_revert', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'This turns the LCA compatibility views back into tables. Run with '
      'PGOPTIONS="-c oceanomics.r7b_revert=yes"';
  END IF;
  IF to_regclass('public.mito_lca_validation') IS NULL THEN
    RAISE EXCEPTION '076 is not applied';
  END IF;
  CREATE TEMP TABLE rv_views ON COMMIT DROP AS
  WITH RECURSIVE dep(oid, lvl) AS (
    SELECT DISTINCT rw.ev_class, 1 FROM pg_depend d JOIN pg_rewrite rw ON rw.oid = d.objid
     WHERE d.refobjid IN ('public.lca'::regclass, 'public.lca_raw_results'::regclass,
                          'public.lca_validation'::regclass, 'public.blast_filtered_lca'::regclass)
       AND rw.ev_class NOT IN ('public.lca'::regclass, 'public.lca_raw_results'::regclass,
                               'public.lca_validation'::regclass, 'public.blast_filtered_lca'::regclass)
    UNION
    SELECT DISTINCT rw.ev_class, dep.lvl + 1 FROM dep JOIN pg_depend d ON d.refobjid = dep.oid
      JOIN pg_rewrite rw ON rw.oid = d.objid WHERE rw.ev_class <> dep.oid AND dep.lvl < 10)
  SELECT dep.oid, max(lvl) AS lvl, n.nspname AS sch, c.relname AS name,
         pg_get_viewdef(dep.oid) AS def, obj_description(dep.oid, 'pg_class') AS cmt
    FROM dep JOIN pg_class c ON c.oid = dep.oid JOIN pg_namespace n ON n.oid = c.relnamespace
   GROUP BY dep.oid, n.nspname, c.relname;
  CREATE TEMP TABLE rv_view_cols ON COMMIT DROP AS
  SELECT v.sch, v.name, a.attname, col_description(v.oid, a.attnum) AS cmt FROM rv_views v
    JOIN pg_attribute a ON a.attrelid = v.oid AND a.attnum > 0 AND NOT a.attisdropped
   WHERE col_description(v.oid, a.attnum) IS NOT NULL;
  CREATE TEMP TABLE rv_view_grants ON COMMIT DROP AS
  SELECT g.table_schema AS sch, g.table_name AS name, g.grantee, g.privilege_type
    FROM information_schema.role_table_grants g JOIN rv_views v ON v.sch = g.table_schema AND v.name = g.table_name
   WHERE g.grantee <> 'postgres';
  CREATE TEMP TABLE rv_view_triggers ON COMMIT DROP AS
  SELECT pg_get_triggerdef(t.oid) AS def FROM pg_trigger t JOIN rv_views v ON v.oid = t.tgrelid WHERE NOT t.tgisinternal;
  EXECUTE (SELECT 'DROP VIEW ' || string_agg(format('%I.%I', sch, name), ', ') || ' CASCADE' FROM rv_views);
  DROP VIEW public.lca, public.lca_raw_results, public.lca_validation, public.blast_filtered_lca;
END
$rv1$;

-- The four tables as they were (pg_dump --section=pre-data of live, 2026-11-02, before 076).
--
-- PostgreSQL database dump
--


-- Dumped from database version 14.24 (Ubuntu 14.24-0ubuntu0.22.04.1)
-- Dumped by pg_dump version 14.24 (Ubuntu 14.24-0ubuntu0.22.04.1)




--
-- Name: lca_validation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lca_validation (
    og_id text NOT NULL,
    tech text NOT NULL,
    validated_species_name text,
    validator text,
    nominal_species_id_lca_comment text,
    validator_2 text,
    data_release text,
    validated_rank text,
    lca_genus text,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    row_created_on timestamp with time zone DEFAULT now() NOT NULL,
    annotation_id bigint NOT NULL
);


ALTER TABLE public.lca_validation OWNER TO postgres;

--
-- Name: TABLE lca_validation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.lca_validation IS 'Human validation of LCA calls. Read by v2.summary and by the public reporting views.';


--
-- Name: COLUMN lca_validation.annotation_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.lca_validation.annotation_id IS 'The mito_annotation this row describes. Filled from (og_id, tech, seq_date, code, annotation) by the lca_validation_annotation_id trigger when a writer omits it; checked when one sends it. 074, Phase R.7.';


--
-- Name: blast_filtered_lca; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.blast_filtered_lca (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    match_sequence_id text NOT NULL,
    taxon_id text,
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
    blast_run_date text,
    annotation_id bigint NOT NULL
);


ALTER TABLE public.blast_filtered_lca OWNER TO postgres;

--
-- Name: TABLE blast_filtered_lca; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.blast_filtered_lca IS 'BLAST hits retained after LCA filtering, one row per matched sequence and region.';


--
-- Name: COLUMN blast_filtered_lca.annotation_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.blast_filtered_lca.annotation_id IS 'The mito_annotation this row describes. Filled from (og_id, tech, seq_date, code, annotation) by the blast_filtered_lca_annotation_id trigger when a writer omits it; checked when one sends it. 074, Phase R.7.';


--
-- Name: lca; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lca (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    region text NOT NULL,
    lca_run_date text NOT NULL,
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
    scientific_name_authorship text,
    taxon_rank text,
    top_taxon_id text,
    taxon_id_db text,
    top_accession_id text,
    accession_id_ref_db text,
    top_percent_query_cover real,
    top_percent_query_cover_hsp real,
    alignment_length integer,
    subject_length integer,
    sequence_length integer,
    top_confidence_score double precision,
    top_percent_match double precision,
    taxon_rank_db text,
    content_hash text NOT NULL,
    annotation_id bigint NOT NULL
);


ALTER TABLE public.lca OWNER TO postgres;

--
-- Name: TABLE lca; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.lca IS 'Lowest common ancestor calls per marker region. Live carries this key as a UNIQUE constraint only; here it is the primary key.';


--
-- Name: COLUMN lca.lca_run_date; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.lca.lca_run_date IS 'When the LCA pipeline ran. NOT NULL, but deliberately NOT part of the key -- row identity is the content hash (migration 017), so a re-run with a changed answer stores a new row rather than colliding with the old one.';


--
-- Name: COLUMN lca.content_hash; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.lca.content_hash IS 'md5 of the row content, maintained by the trigger below. Row identity for this table. Not comparable with public.lca.content_hash: the hash covers every column, and the two tables no longer have the same column set (og_num is gone, F2). Reconcile these tables on their business keys, never on this value.';


--
-- Name: COLUMN lca.annotation_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.lca.annotation_id IS 'The mito_annotation this row describes. Filled from (og_id, tech, seq_date, code, annotation) by the lca_annotation_id trigger when a writer omits it; checked when one sends it. 074, Phase R.7.';


--
-- Name: lca_raw_results; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lca_raw_results (
    og_id text NOT NULL,
    tech text NOT NULL,
    seq_date text NOT NULL,
    code text NOT NULL,
    annotation text NOT NULL,
    sequence_region text NOT NULL,
    lca_run_date text NOT NULL,
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
    taxon_id text,
    taxon_id_db text,
    verbatim_identification text,
    accession_id text NOT NULL,
    accession_id_ref_db text,
    percent_match real,
    percent_query_cover real,
    percent_query_cover_hsp real,
    alignment_length integer,
    subject_length integer,
    sequence_length integer,
    confidence_score double precision,
    taxon_rank_db text,
    content_hash text NOT NULL,
    annotation_id bigint NOT NULL
);


ALTER TABLE public.lca_raw_results OWNER TO postgres;

--
-- Name: TABLE lca_raw_results; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.lca_raw_results IS 'Unfiltered LCA output. lca_run_date is text here, matching v2.lca; the live tables disagree on its type while using it in equivalent uniqueness constraints. confidence_score is double precision, not real -- see the column note, and do not narrow it back.';


--
-- Name: COLUMN lca_raw_results.content_hash; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.lca_raw_results.content_hash IS 'See v2.lca.content_hash. Part of the key here because one BLAST accession can yield several HSPs in a single run, which share accession and run date but differ in percent_match -- 33 such rows exist in live today.';


--
-- Name: COLUMN lca_raw_results.annotation_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.lca_raw_results.annotation_id IS 'The mito_annotation this row describes. Filled from (og_id, tech, seq_date, code, annotation) by the lca_raw_results_annotation_id trigger when a writer omits it; checked when one sends it. 074, Phase R.7.';


--
-- Name: TABLE lca_validation; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.lca_validation TO oceangenom_web;
GRANT SELECT ON TABLE public.lca_validation TO readonly;


--
-- Name: TABLE blast_filtered_lca; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.blast_filtered_lca TO readonly;


--
-- Name: TABLE lca; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.lca TO readonly;


--
-- Name: TABLE lca_raw_results; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.lca_raw_results TO readonly;


--
-- PostgreSQL database dump complete
--



-- A default privilege grants readonly at CREATE TABLE, ahead of the dump's own GRANTs; reset
-- lca_validation's ACL so it reads as it did (oceangenom_web, then readonly).
REVOKE SELECT ON TABLE public.lca_validation FROM readonly, oceangenom_web;
GRANT SELECT ON TABLE public.lca_validation TO oceangenom_web;
GRANT SELECT ON TABLE public.lca_validation TO readonly;

-- Refill from the base tables. content_hash gets a placeholder; the restored trigger recomputes it.
DO $rv2$
DECLARE
  pairs text[][] := ARRAY[['lca','mito_lca'],['lca_raw_results','mito_lca_raw'],
                          ['lca_validation','mito_lca_validation'],['blast_filtered_lca','mito_blast_hit']];
  i int; old text; base text; cols text; sel text;
BEGIN
  FOR i IN 1..array_length(pairs, 1) LOOP
    old := pairs[i][1]; base := pairs[i][2];
    SELECT string_agg(format('%I', attname), ', ' ORDER BY attnum),
           string_agg(CASE attname
                        WHEN 'og_id' THEN 'a.og_id' WHEN 'tech' THEN 'a.tech'
                        WHEN 'seq_date' THEN 'a.seq_date' WHEN 'code' THEN 'a.code'
                        WHEN 'annotation' THEN 'an.annotation'
                        WHEN 'content_hash' THEN $q$'r076-' || row_number() OVER ()$q$
                        ELSE format('t.%I', attname) END, ', ' ORDER BY attnum)
      INTO cols, sel
      FROM pg_attribute WHERE attrelid = format('public.%I', old)::regclass AND attnum > 0 AND NOT attisdropped;
    EXECUTE format('INSERT INTO public.%I (%s) SELECT %s FROM public.%I t '
                   'JOIN public.mito_annotation an ON an.annotation_id = t.annotation_id '
                   'JOIN public.mito_assembly a ON a.assembly_id = an.assembly_id', old, cols, sel, base);
  END LOOP;
END
$rv2$;

-- Keys, indexes, FKs and triggers as they were (pg_dump --section=post-data, before 076).
--
-- PostgreSQL database dump
--


-- Dumped from database version 14.24 (Ubuntu 14.24-0ubuntu0.22.04.1)
-- Dumped by pg_dump version 14.24 (Ubuntu 14.24-0ubuntu0.22.04.1)



--
-- Name: blast_filtered_lca blast_filtered_lca_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blast_filtered_lca
    ADD CONSTRAINT blast_filtered_lca_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, match_sequence_id, region);


--
-- Name: lca lca_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT lca_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, region, content_hash);


--
-- Name: lca_raw_results lca_raw_results_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT lca_raw_results_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation, sequence_region, accession_id, content_hash);


--
-- Name: lca_validation lca_validation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT lca_validation_pkey PRIMARY KEY (og_id, tech, seq_date, code, annotation);


--
-- Name: blast_filtered_lca_annotation_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX blast_filtered_lca_annotation_id_idx ON public.blast_filtered_lca USING btree (annotation_id);


--
-- Name: blast_filtered_lca_og_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX blast_filtered_lca_og_id_idx ON public.blast_filtered_lca USING btree (og_id);


--
-- Name: lca_annotation_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lca_annotation_id_idx ON public.lca USING btree (annotation_id);


--
-- Name: lca_mitogenome_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lca_mitogenome_idx ON public.lca USING btree (og_id, tech, seq_date, code);


--
-- Name: lca_og_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lca_og_id_idx ON public.lca USING btree (og_id);


--
-- Name: lca_raw_results_annotation_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lca_raw_results_annotation_id_idx ON public.lca_raw_results USING btree (annotation_id);


--
-- Name: lca_raw_results_mito_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lca_raw_results_mito_idx ON public.lca_raw_results USING btree (og_id, tech, seq_date, code);


--
-- Name: lca_raw_results_og_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lca_raw_results_og_id_idx ON public.lca_raw_results USING btree (og_id);


--
-- Name: lca_validation_annotation_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lca_validation_annotation_id_idx ON public.lca_validation USING btree (annotation_id);


--
-- Name: lca_validation_og_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lca_validation_og_id_idx ON public.lca_validation USING btree (og_id);


--
-- Name: blast_filtered_lca blast_filtered_lca_annotation_id; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER blast_filtered_lca_annotation_id BEFORE INSERT OR UPDATE OF og_id, tech, seq_date, code, annotation, annotation_id ON public.blast_filtered_lca FOR EACH ROW EXECUTE FUNCTION public.mito_child_annotation_id();


--
-- Name: lca lca_annotation_id; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER lca_annotation_id BEFORE INSERT OR UPDATE OF og_id, tech, seq_date, code, annotation, annotation_id ON public.lca FOR EACH ROW EXECUTE FUNCTION public.mito_child_annotation_id();


--
-- Name: lca lca_content_hash; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER lca_content_hash BEFORE INSERT OR UPDATE ON public.lca FOR EACH ROW EXECUTE FUNCTION public.lca_set_content_hash();


--
-- Name: lca_raw_results lca_raw_results_annotation_id; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER lca_raw_results_annotation_id BEFORE INSERT OR UPDATE OF og_id, tech, seq_date, code, annotation, annotation_id ON public.lca_raw_results FOR EACH ROW EXECUTE FUNCTION public.mito_child_annotation_id();


--
-- Name: lca_raw_results lca_raw_results_content_hash; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER lca_raw_results_content_hash BEFORE INSERT OR UPDATE ON public.lca_raw_results FOR EACH ROW EXECUTE FUNCTION public.lca_set_content_hash();


--
-- Name: lca_validation lca_validation_annotation_id; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER lca_validation_annotation_id BEFORE INSERT OR UPDATE OF og_id, tech, seq_date, code, annotation, annotation_id ON public.lca_validation FOR EACH ROW EXECUTE FUNCTION public.mito_child_annotation_id();


--
-- Name: blast_filtered_lca blast_filtered_lca_annotation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blast_filtered_lca
    ADD CONSTRAINT blast_filtered_lca_annotation_fkey FOREIGN KEY (annotation_id) REFERENCES public.mito_annotation(annotation_id);


--
-- Name: blast_filtered_lca blast_filtered_lca_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blast_filtered_lca
    ADD CONSTRAINT blast_filtered_lca_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: lca lca_annotation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT lca_annotation_fkey FOREIGN KEY (annotation_id) REFERENCES public.mito_annotation(annotation_id);


--
-- Name: lca lca_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lca
    ADD CONSTRAINT lca_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: lca_raw_results lca_raw_results_annotation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT lca_raw_results_annotation_fkey FOREIGN KEY (annotation_id) REFERENCES public.mito_annotation(annotation_id);


--
-- Name: lca_raw_results lca_raw_results_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lca_raw_results
    ADD CONSTRAINT lca_raw_results_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- Name: lca_validation lca_validation_annotation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT lca_validation_annotation_fkey FOREIGN KEY (annotation_id) REFERENCES public.mito_annotation(annotation_id);


--
-- Name: lca_validation lca_validation_og_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lca_validation
    ADD CONSTRAINT lca_validation_og_id_fkey FOREIGN KEY (og_id) REFERENCES public.sample(og_id);


--
-- PostgreSQL database dump complete
--



-- The restored hash trigger recomputes every content_hash (BEFORE UPDATE).
UPDATE public.lca SET content_hash = content_hash;
UPDATE public.lca_raw_results SET content_hash = content_hash;

DROP TABLE public.mito_lca, public.mito_lca_raw, public.mito_lca_validation, public.mito_blast_hit;
DROP TABLE pre_v3_archive.lca_hash_map_076, pre_v3_archive.lca_raw_results_hash_map_076;

-- lca_validation_report_view_upd() as it was before 076.
CREATE OR REPLACE FUNCTION public.lca_validation_report_view_upd()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Optional safety: prevent attempts to change the identifying fields via the view
  IF NEW.og_id IS DISTINCT FROM OLD.og_id
     OR NEW.tech IS DISTINCT FROM OLD.tech
     OR NEW.seq_date IS DISTINCT FROM OLD.seq_date
     OR NEW.code IS DISTINCT FROM OLD.code
     OR NEW.annotation IS DISTINCT FROM OLD.annotation
  THEN
    RAISE EXCEPTION
      'Cannot change key fields (og_id, tech, seq_date, code, annotation) through lca_validation_report_view';
  END IF;

  -- Persist only the editable columns back to the base table.
  UPDATE lca_validation
  SET validated_species_name         = NEW.validated_species_name,
      validator                      = NEW.validator,
      validator_2                    = NEW.validator_2,
      nominal_species_id_lca_comment = NEW.comment
  WHERE og_id       = OLD.og_id
    AND tech        = OLD.tech
    AND seq_date    = OLD.seq_date
    AND code        = OLD.code
    AND annotation  = OLD.annotation;

  -- If no row was updated, something is off (missing row or key mismatch).
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Update failed: no matching row in lca_validation for (og_id=%, tech=%, seq_date=%, code=%, annotation=%)',
      OLD.og_id, OLD.tech, OLD.seq_date, OLD.code, OLD.annotation;
  END IF;

  RETURN NEW;
END;
$function$
;

DROP FUNCTION public.mito_annotation_id(text, text, text, text, text, boolean);

DO $rv3$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM rv_views ORDER BY lvl, sch, name LOOP
    EXECUTE format('CREATE VIEW %I.%I AS %s', r.sch, r.name, r.def);
    IF r.cmt IS NOT NULL THEN EXECUTE format('COMMENT ON VIEW %I.%I IS %L', r.sch, r.name, r.cmt); END IF;
  END LOOP;
  FOR r IN SELECT * FROM rv_view_cols LOOP
    EXECUTE format('COMMENT ON COLUMN %I.%I.%I IS %L', r.sch, r.name, r.attname, r.cmt);
  END LOOP;
  FOR r IN SELECT * FROM rv_view_grants LOOP
    EXECUTE format('GRANT %s ON %I.%I TO %I', r.privilege_type, r.sch, r.name, r.grantee);
  END LOOP;
  FOR r IN SELECT * FROM rv_view_triggers LOOP EXECUTE r.def; END LOOP;
END
$rv3$;

COMMIT;
