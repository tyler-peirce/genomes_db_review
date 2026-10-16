-- 051_v3_mitogenome_revert.sql -- remove schema v3 and everything 051 built in it.
--
-- v3 holds only copies: production writers still write public until the R.6 merge, and
-- nothing in public depends on v3, so dropping it loses nothing that public does not hold.
-- 052 and 053 also build in v3. Revert them first if they are applied; this file refuses
-- while their objects exist, so it cannot take their work with it by accident.
--
-- After running this, delete 051's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '051_v3_mitogenome.sql';

BEGIN;

DO $revert$
BEGIN
  IF to_regnamespace('v3') IS NULL THEN
    RETURN;
  END IF;
  IF to_regclass('v3.draft_genome') IS NOT NULL OR to_regclass('v3.sequencing_run') IS NOT NULL THEN
    RAISE EXCEPTION 'v3 still holds 052/053 objects; revert those first';
  END IF;
  DROP SCHEMA v3 CASCADE;
END
$revert$;

COMMIT;
