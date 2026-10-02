-- Revert genomes_db:create_v2_schema from pg

-- Deliberately NOT `DROP SCHEMA v2 CASCADE`. If a later change has created objects in v2 and
-- has not itself been reverted first, this should fail loudly rather than silently destroy
-- them. Sqitch reverts in dependency order, so a clean revert leaves the schema empty.

BEGIN;

DROP SCHEMA v2 RESTRICT;

COMMIT;
