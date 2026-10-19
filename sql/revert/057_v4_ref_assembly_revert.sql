-- 057_v4_ref_assembly_revert.sql -- remove schema v4 and everything 057 built in it.
--
-- v4 holds only copies: production writers still write public until the RG.6 swap, and nothing
-- in public depends on v4, so dropping it loses nothing that public does not hold. 058 and 059
-- also build in v4. Revert them first if they are applied; this file refuses while their objects
-- exist, so it cannot take their work with it by accident. Dropping the schema also drops its
-- default privileges.
--
-- After running this, delete 057's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '057_v4_ref_assembly.sql';

BEGIN;

DO $revert$
BEGIN
  IF to_regnamespace('v4') IS NULL THEN
    RETURN;
  END IF;
  IF to_regclass('v4.ref_genomescope') IS NOT NULL OR to_regclass('v4.ref_submission') IS NOT NULL THEN
    RAISE EXCEPTION 'v4 still holds 058/059 objects; revert those first';
  END IF;
  DROP SCHEMA v4 CASCADE;
END
$revert$;

COMMIT;
