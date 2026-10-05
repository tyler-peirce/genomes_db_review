-- Revert genomes_db:create_v2_quarantine from pg

BEGIN;

DROP VIEW v2.v_quarantine_open;
DROP FUNCTION v2.quarantine(text, text, text, text, jsonb, text);
DROP TABLE v2.import_quarantine;

COMMIT;
