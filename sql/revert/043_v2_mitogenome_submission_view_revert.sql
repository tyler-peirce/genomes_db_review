-- Revert 043_v2_mitogenome_submission_view.sql.
--
-- Drops the v2 view. public.mitogenome_submission_view is untouched by 043 and needs nothing
-- here. Do not run after the V.5 cutover has made this the view that unqualified
-- mitogenome_submission_view resolves to; revert the cutover first. Does not touch the
-- ledger; afterwards:
--
--     DELETE FROM schema_migrations WHERE filename = '043_v2_mitogenome_submission_view.sql';

BEGIN;

DROP VIEW v2.mitogenome_submission_view;

COMMIT;
