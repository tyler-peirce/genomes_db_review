-- 044_catchup_og_workflow_tables.sql
--
-- Purpose: bring OceanGenom_Web's three tables under migration management, and close open
-- question 16.
--
-- Review source: database_review.md Phase B.6, open question 16; docs/phase_v5_plan.md
-- prerequisite 5.
--
-- What they are, and how we know
-- ------------------------------
-- og_workflow_recommendation, og_workflow_assignment_log and og_workflow_notification were
-- created on live by direct DDL some time after the 2026-10-02 re-baseline. Phase B.6
-- deliberately left them unclaimed -- not dropped, not captured, not baselined -- so the daily
-- drift check failed on them until someone owned them. The 2026-10-13 investigation for the
-- v2 cutover answered the question from the database itself:
--
--   - Their own COMMENTs name OceanGenom_Web: the recommendation table is "Edited in the
--     OceanGenom_Web Unassigned Workflows tab", the log records "the Assign button in
--     OceanGenom_Web", and the notification table is its "Notification feed".
--   - The only role that writes them is oceangenom_web, the application's login: SELECT,
--     INSERT, UPDATE, DELETE on all three, and USAGE on both sequences. readonly can read them.
--   - oceangenom_web connects from 146.118.122.158 with application_name 'oceangenom_web', and
--     the notification feed holds recommendations made through the site by named lab users.
--
-- So they are live application tables in active use, owned by the web application, and they
-- stay. Phase B's rule is that the drift alarm sounds until the objects are claimed; this
-- migration is the claim. Nothing in genomes_db_review or OceanOmics-Database writes them.
--
-- Captured as they are. og_id has no foreign key to sample here, as on live: adding one is a
-- behavioural change for the application and belongs in its own migration, agreed with its
-- owner. Unaffected by the v2 cutover, which neither replaces nor renames them; the comment on
-- og_workflow_recommendation names public.sample.workflow, which the cutover moves to v2 and
-- V.6 brings back to public. The web application owns sample.workflow (owner decision
-- 2026-10-13): the importers set it only when a sample is created.
--
-- Expected impact: none on live, where every object, grant and comment already exists exactly
-- as written here (the DDL is a pg_dump of live, 2026-10-13). Every CREATE is guarded and
-- every GRANT and COMMENT is idempotent. The grants are skipped where a role does not exist,
-- so a rebuild on a cluster without the application's role still succeeds.
--
-- Revert: sql/revert/044_catchup_og_workflow_tables_revert.sql is a deliberate no-op, the
-- standing pattern for catch-up migrations (sql/README.md).

BEGIN;

CREATE SEQUENCE IF NOT EXISTS public.og_workflow_assignment_log_id_seq
    START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
CREATE SEQUENCE IF NOT EXISTS public.og_workflow_notification_id_seq
    START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

CREATE TABLE IF NOT EXISTS public.og_workflow_recommendation (
    og_id text NOT NULL,
    recommended_workflow text,
    note text,
    updated_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT og_workflow_recommendation_pkey PRIMARY KEY (og_id),
    CONSTRAINT og_workflow_recommendation_recommended_workflow_check
        CHECK ((recommended_workflow = ANY (ARRAY['Reference'::text, 'Draft'::text])))
);

CREATE TABLE IF NOT EXISTS public.og_workflow_assignment_log (
    id bigint DEFAULT nextval('public.og_workflow_assignment_log_id_seq'::regclass) NOT NULL,
    og_id text NOT NULL,
    workflow text NOT NULL,
    recommended_workflow text,
    note text,
    samples_updated integer NOT NULL,
    assigned_by text NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT og_workflow_assignment_log_pkey PRIMARY KEY (id),
    CONSTRAINT og_workflow_assignment_log_workflow_check
        CHECK ((workflow = ANY (ARRAY['Reference'::text, 'Draft'::text])))
);

CREATE TABLE IF NOT EXISTS public.og_workflow_notification (
    id bigint DEFAULT nextval('public.og_workflow_notification_id_seq'::regclass) NOT NULL,
    kind text NOT NULL,
    og_id text NOT NULL,
    workflow text,
    recommended_workflow text,
    actor text,
    source text DEFAULT 'site'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT og_workflow_notification_pkey PRIMARY KEY (id),
    CONSTRAINT og_workflow_notification_kind_check
        CHECK ((kind = ANY (ARRAY['recommendation'::text, 'assigned'::text]))),
    CONSTRAINT og_workflow_notification_source_check
        CHECK ((source = ANY (ARRAY['site'::text, 'database'::text])))
);

-- Idempotent: re-stating ownership of an already-owned sequence is a no-op.
ALTER SEQUENCE public.og_workflow_assignment_log_id_seq OWNED BY public.og_workflow_assignment_log.id;
ALTER SEQUENCE public.og_workflow_notification_id_seq OWNED BY public.og_workflow_notification.id;

CREATE INDEX IF NOT EXISTS og_workflow_assignment_log_assigned_at_idx
    ON public.og_workflow_assignment_log USING btree (assigned_at);
CREATE INDEX IF NOT EXISTS og_workflow_notification_created_at_idx
    ON public.og_workflow_notification USING btree (created_at DESC);

-- The comments are the application's own, taken verbatim from live.
COMMENT ON TABLE public.og_workflow_recommendation IS
    'Recommended sequencing workflow for OGs whose public.sample.workflow is still ''Not assigned''. Edited in the OceanGenom_Web Unassigned Workflows tab; a row is deleted when the workflow is assigned.';
COMMENT ON TABLE public.og_workflow_assignment_log IS
    'Audit log of workflow assignments made with the Assign button in OceanGenom_Web: which OG, which workflow, the recommendation at the time, who and when.';
COMMENT ON TABLE public.og_workflow_notification IS
    'Notification feed for OceanGenom_Web: new workflow recommendations and workflow assignments.';

DO $$
BEGIN
  IF to_regrole('readonly') IS NOT NULL THEN
    GRANT SELECT ON public.og_workflow_recommendation, public.og_workflow_assignment_log,
                    public.og_workflow_notification TO readonly;
    GRANT SELECT ON SEQUENCE public.og_workflow_assignment_log_id_seq,
                             public.og_workflow_notification_id_seq TO readonly;
  END IF;
  IF to_regrole('oceangenom_web') IS NOT NULL THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.og_workflow_recommendation,
          public.og_workflow_assignment_log, public.og_workflow_notification TO oceangenom_web;
    GRANT SELECT, USAGE ON SEQUENCE public.og_workflow_assignment_log_id_seq,
                                    public.og_workflow_notification_id_seq TO oceangenom_web;
  END IF;
END $$;

-- ---------------------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------------------

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['og_workflow_recommendation', 'og_workflow_assignment_log',
                           'og_workflow_notification'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION '044: public.% is missing', t;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = ('public.' || t)::regclass AND contype = 'p') THEN
      RAISE EXCEPTION '044: public.% has no primary key', t;
    END IF;
    IF obj_description(('public.' || t)::regclass, 'pg_class') IS NULL THEN
      RAISE EXCEPTION '044: public.% has no COMMENT (Finding 9)', t;
    END IF;
  END LOOP;
END $$;

COMMIT;
