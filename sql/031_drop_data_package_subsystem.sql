-- Drop the data-delivery subsystem: seven data_package_* tables plus
-- project_delivery_contact.
--
-- What it was. A project data-delivery tracker -- a delivery header, the
-- components within it, the individual items and artifacts making up each
-- component, and a notification layer (link sets, emails, recipients) joined to
-- a contact list. It was the best-modelled subsystem in this database: real
-- primary keys, composite uniques, a partial unique index, sensible FK
-- cascades. database_review.md Finding 9 and section 7 describe it in detail.
--
-- Why it is going. The work was never finished and will not be picked up. It
-- had been running as mid-rollout since August: one delivery, three components,
-- 110 items, 10 artifacts, and nothing at all in the email, link-set or contact
-- tables. Those 124 rows are stale. Keeping an unfinished subsystem in the live
-- schema costs more than it preserves -- it appears in every inventory, every
-- drift report and every catch-up-migration estimate, and it was never in a
-- migration to begin with (it reached this database by direct DDL).
--
-- Row counts at drop time, 2026-10-05:
--     data_package_delivery          1
--     data_package_component         3
--     data_package_item            110
--     data_package_artifact         10
--     data_package_email             0
--     data_package_email_recipient   0
--     data_package_link_set          0
--     project_delivery_contact       0
--
-- Safety. Verified before writing this migration:
--   * Every foreign key in the cluster is internal to it. Nothing outside
--     points in -- confirmed by querying pg_constraint for inbound FKs whose
--     source is outside the group, which returned zero rows.
--   * No view, function or trigger depends on any of these tables.
--   * No application code anywhere under /home/tyler references them. Every
--     textual hit is a generated schema baseline, prose in database_review.md,
--     or a comment.
--
-- Deliberately NOT using CASCADE. The drops are ordered children-first so this
-- file documents the dependency structure as it removes it. If a drop fails for
-- an unexpected dependency, it should fail loudly rather than silently taking
-- the dependency with it.
--
-- Identity sequences (data_package_*_id_seq) are owned by their tables and are
-- removed automatically with them. They need no separate statement.
--
-- Reverting. revert/031_drop_data_package_subsystem_revert.sql recreates the
-- structure but NOT the data -- see its header. The 124 rows remain in the
-- nightly base backup at s3://ocom-databases/oceanomics_genomes/base_backups.

BEGIN;

-- Leaves first: the notification layer.
DROP TABLE IF EXISTS data_package_email_recipient;
DROP TABLE IF EXISTS data_package_email;

-- Then the per-component detail.
DROP TABLE IF EXISTS data_package_artifact;
DROP TABLE IF EXISTS data_package_item;

-- data_package_link_set references itself (previous_link_set_id) as well as
-- the delivery, so it goes before the delivery but after the email table that
-- points at it.
DROP TABLE IF EXISTS data_package_link_set;

-- Then the spine.
DROP TABLE IF EXISTS data_package_component;
DROP TABLE IF EXISTS data_package_delivery;

-- Finally the contact list, which only data_package_email_recipient used.
DROP TABLE IF EXISTS project_delivery_contact;

-- Fail loudly if anything survived.
DO $$
DECLARE
    leftover text;
BEGIN
    SELECT string_agg(c.relname, ', ' ORDER BY c.relname)
      INTO leftover
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind = 'r'
       AND (c.relname LIKE 'data_package%' OR c.relname = 'project_delivery_contact');

    IF leftover IS NOT NULL THEN
        RAISE EXCEPTION 'data_package drop incomplete, still present: %', leftover;
    END IF;
END $$;

COMMIT;
