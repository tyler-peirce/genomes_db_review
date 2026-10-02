-- Revert genomes_db:create_v2_lca_tables from pg

-- mitogenome_data is the parent of the other three, so it goes last.

BEGIN;

DROP TABLE v2.blast_filtered_lca;
DROP TABLE v2.lca_raw_results;
DROP TABLE v2.lca_validation;
DROP TABLE v2.lca;
DROP TABLE v2.mitogenome_data;

COMMIT;
