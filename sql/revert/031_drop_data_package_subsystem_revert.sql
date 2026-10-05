-- Revert 031_drop_data_package_subsystem.sql.
--
-- STRUCTURE ONLY. THIS DOES NOT RESTORE ANY DATA.
--
-- This recreates the eight empty tables, their identity sequences, primary
-- keys, unique constraints, foreign keys and indexes exactly as they were at
-- 2026-10-05. It does not bring back the 124 rows, because those rows were
-- stale -- that was the reason for dropping the subsystem, not an accident of
-- it. The revert exists so the shape of the design is recoverable if the
-- data-delivery work is ever resumed.
--
-- If you actually need the rows, they are in the nightly base backup at
-- s3://ocom-databases/oceanomics_genomes/base_backups -- restore that to a
-- scratch database and copy them out. Do not expect this file to do it.
--
-- Generated from pg_dump --schema-only against the live database immediately
-- before the drop, so it is the real DDL rather than a reconstruction. Run it
-- in one transaction; the ordering below is pg_dump's (tables first, then
-- constraints, then indexes, then foreign keys), which is dependency-safe.

BEGIN;

\restrict RUqC1oZnGhjVvxEDR2ccESHzibuddbaKes1iUc2kRLe9YHCXCZ6aXOd2YUhpXvb
CREATE TABLE public.data_package_artifact (
    id bigint NOT NULL,
    delivery_id bigint NOT NULL,
    component_id bigint,
    batch_number integer,
    artifact_type text NOT NULL,
    filename text NOT NULL,
    local_path text,
    remote_path text,
    size_bytes bigint DEFAULT 0 NOT NULL,
    sha256 text,
    status text DEFAULT 'planned'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    uploaded_at timestamp with time zone,
    verified_at timestamp with time zone,
    error_text text,
    CONSTRAINT data_package_artifact_size_bytes_check CHECK ((size_bytes >= 0))
);
ALTER TABLE public.data_package_artifact ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_artifact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.data_package_component (
    id bigint NOT NULL,
    delivery_id bigint NOT NULL,
    component_type text NOT NULL,
    status text NOT NULL,
    requested_count integer DEFAULT 0 NOT NULL,
    eligible_count integer DEFAULT 0 NOT NULL,
    included_count integer DEFAULT 0 NOT NULL,
    excluded_count integer DEFAULT 0 NOT NULL,
    warning_count integer DEFAULT 0 NOT NULL,
    validation_result text,
    validation_report text,
    inventory_digest text,
    approved_by text,
    approved_at timestamp with time zone,
    approval_note text,
    override_used boolean DEFAULT false NOT NULL,
    override_reason text,
    pending_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT data_package_component_check CHECK (((NOT override_used) OR (NULLIF(btrim(override_reason), ''::text) IS NOT NULL))),
    CONSTRAINT data_package_component_component_type_check CHECK ((component_type = ANY (ARRAY['reference'::text, 'draft'::text, 'mito'::text])))
);
ALTER TABLE public.data_package_component ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_component_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.data_package_delivery (
    id bigint NOT NULL,
    project_id text NOT NULL,
    run_id text NOT NULL,
    delivery_version integer NOT NULL,
    status text NOT NULL,
    is_partial boolean DEFAULT false NOT NULL,
    created_by text NOT NULL,
    repository_revisions jsonb DEFAULT '{}'::jsonb NOT NULL,
    manifest_digest text,
    archive_count integer DEFAULT 0 NOT NULL,
    total_bytes bigint DEFAULT 0 NOT NULL,
    remote_prefix text,
    approved_at timestamp with time zone,
    packaged_at timestamp with time zone,
    uploaded_at timestamp with time zone,
    links_generated_at timestamp with time zone,
    email_accepted_at timestamp with time zone,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT data_package_delivery_archive_count_check CHECK ((archive_count >= 0)),
    CONSTRAINT data_package_delivery_delivery_version_check CHECK ((delivery_version > 0)),
    CONSTRAINT data_package_delivery_project_id_check CHECK ((project_id ~ '^OGP[0-9]+'::text)),
    CONSTRAINT data_package_delivery_total_bytes_check CHECK ((total_bytes >= 0))
);
ALTER TABLE public.data_package_delivery ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_delivery_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.data_package_email (
    id bigint NOT NULL,
    delivery_id bigint NOT NULL,
    link_set_id bigint NOT NULL,
    preview_id text NOT NULL,
    content_digest text NOT NULL,
    status text NOT NULL,
    sender text NOT NULL,
    reply_to text,
    subject text NOT NULL,
    text_body text NOT NULL,
    html_body text,
    message_id text,
    previewed_by text NOT NULL,
    sent_by text,
    transport text,
    transport_exit_status integer,
    error_text text,
    previewed_at timestamp with time zone DEFAULT now() NOT NULL,
    confirmed_at timestamp with time zone,
    submitted_at timestamp with time zone,
    accepted_at timestamp with time zone
);
ALTER TABLE public.data_package_email ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_email_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.data_package_email_recipient (
    id bigint NOT NULL,
    email_id bigint NOT NULL,
    contact_id bigint,
    recipient_role text NOT NULL,
    display_name text NOT NULL,
    organisation text,
    email text NOT NULL,
    CONSTRAINT data_package_email_recipient_recipient_role_check CHECK ((recipient_role = ANY (ARRAY['to'::text, 'cc'::text, 'bcc'::text])))
);
ALTER TABLE public.data_package_email_recipient ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_email_recipient_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.data_package_item (
    id bigint NOT NULL,
    component_id bigint NOT NULL,
    og_id text NOT NULL,
    seq_id text DEFAULT ''::text NOT NULL,
    disposition text NOT NULL,
    validation_result text,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT data_package_item_disposition_check CHECK ((disposition = ANY (ARRAY['included'::text, 'excluded'::text, 'pending'::text])))
);
ALTER TABLE public.data_package_item ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.data_package_link_set (
    id bigint NOT NULL,
    delivery_id bigint NOT NULL,
    previous_link_set_id bigint,
    status text NOT NULL,
    requested_expiry text NOT NULL,
    effective_expiry text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    links jsonb NOT NULL,
    manifest_path text NOT NULL,
    generated_by text NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    error_text text
);
ALTER TABLE public.data_package_link_set ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_package_link_set_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.project_delivery_contact (
    id bigint NOT NULL,
    project_id text NOT NULL,
    display_name text NOT NULL,
    organisation text,
    email text NOT NULL,
    recipient_role text NOT NULL,
    component_types text[] DEFAULT ARRAY['reference'::text, 'draft'::text, 'mito'::text] NOT NULL,
    active boolean DEFAULT true NOT NULL,
    effective_from timestamp with time zone DEFAULT now() NOT NULL,
    effective_until timestamp with time zone,
    created_by text DEFAULT CURRENT_USER NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT project_delivery_contact_recipient_role_check CHECK ((recipient_role = ANY (ARRAY['to'::text, 'cc'::text, 'bcc'::text])))
);
ALTER TABLE public.project_delivery_contact ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.project_delivery_contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
ALTER TABLE ONLY public.data_package_artifact
    ADD CONSTRAINT data_package_artifact_delivery_id_component_id_artifact_typ_key UNIQUE (delivery_id, component_id, artifact_type, batch_number, filename);
ALTER TABLE ONLY public.data_package_artifact
    ADD CONSTRAINT data_package_artifact_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.data_package_component
    ADD CONSTRAINT data_package_component_delivery_id_component_type_key UNIQUE (delivery_id, component_type);
ALTER TABLE ONLY public.data_package_component
    ADD CONSTRAINT data_package_component_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.data_package_delivery
    ADD CONSTRAINT data_package_delivery_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.data_package_delivery
    ADD CONSTRAINT data_package_delivery_project_id_delivery_version_key UNIQUE (project_id, delivery_version);
ALTER TABLE ONLY public.data_package_delivery
    ADD CONSTRAINT data_package_delivery_run_id_key UNIQUE (run_id);
ALTER TABLE ONLY public.data_package_email
    ADD CONSTRAINT data_package_email_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.data_package_email
    ADD CONSTRAINT data_package_email_preview_id_key UNIQUE (preview_id);
ALTER TABLE ONLY public.data_package_email_recipient
    ADD CONSTRAINT data_package_email_recipient_email_id_recipient_role_email_key UNIQUE (email_id, recipient_role, email);
ALTER TABLE ONLY public.data_package_email_recipient
    ADD CONSTRAINT data_package_email_recipient_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.data_package_item
    ADD CONSTRAINT data_package_item_component_id_og_id_seq_id_key UNIQUE (component_id, og_id, seq_id);
ALTER TABLE ONLY public.data_package_item
    ADD CONSTRAINT data_package_item_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.data_package_link_set
    ADD CONSTRAINT data_package_link_set_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.project_delivery_contact
    ADD CONSTRAINT project_delivery_contact_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.project_delivery_contact
    ADD CONSTRAINT project_delivery_contact_project_id_email_recipient_role_key UNIQUE (project_id, email, recipient_role);
CREATE INDEX data_package_artifact_remote_idx ON public.data_package_artifact USING btree (remote_path);
CREATE INDEX data_package_delivery_project_status_idx ON public.data_package_delivery USING btree (project_id, status, created_at DESC);
CREATE INDEX data_package_item_og_idx ON public.data_package_item USING btree (og_id);
CREATE INDEX data_package_link_expiry_idx ON public.data_package_link_set USING btree (delivery_id, expires_at DESC);
CREATE INDEX project_delivery_contact_active_idx ON public.project_delivery_contact USING btree (project_id, active);
ALTER TABLE ONLY public.data_package_artifact
    ADD CONSTRAINT data_package_artifact_component_id_fkey FOREIGN KEY (component_id) REFERENCES public.data_package_component(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.data_package_artifact
    ADD CONSTRAINT data_package_artifact_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.data_package_delivery(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.data_package_component
    ADD CONSTRAINT data_package_component_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.data_package_delivery(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.data_package_email
    ADD CONSTRAINT data_package_email_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.data_package_delivery(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.data_package_email
    ADD CONSTRAINT data_package_email_link_set_id_fkey FOREIGN KEY (link_set_id) REFERENCES public.data_package_link_set(id);
ALTER TABLE ONLY public.data_package_email_recipient
    ADD CONSTRAINT data_package_email_recipient_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.project_delivery_contact(id);
ALTER TABLE ONLY public.data_package_email_recipient
    ADD CONSTRAINT data_package_email_recipient_email_id_fkey FOREIGN KEY (email_id) REFERENCES public.data_package_email(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.data_package_item
    ADD CONSTRAINT data_package_item_component_id_fkey FOREIGN KEY (component_id) REFERENCES public.data_package_component(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.data_package_link_set
    ADD CONSTRAINT data_package_link_set_delivery_id_fkey FOREIGN KEY (delivery_id) REFERENCES public.data_package_delivery(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.data_package_link_set
    ADD CONSTRAINT data_package_link_set_previous_link_set_id_fkey FOREIGN KEY (previous_link_set_id) REFERENCES public.data_package_link_set(id);
\unrestrict RUqC1oZnGhjVvxEDR2ccESHzibuddbaKes1iUc2kRLe9YHCXCZ6aXOd2YUhpXvb

COMMIT;
