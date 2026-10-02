-- Revert genomes_db:create_v2_summary_view from pg

-- goat_species_v1 reads summary, so it goes first.

BEGIN;

DROP VIEW v2.goat_species_v1;
DROP VIEW v2.summary;

COMMIT;
