-- Revert 083_ref_decontamination.sql: drop ref_decontamination (its rows go with it; the pre-change
-- dump and the pipeline outputs are the copies).
--     psql -f sql/revert/083_ref_decontamination_revert.sql   then delete 083's ledger row.

BEGIN;

DROP TABLE ref_decontamination;

COMMIT;
