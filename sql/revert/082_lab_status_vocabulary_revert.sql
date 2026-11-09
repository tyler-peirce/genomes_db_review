-- Revert 082_lab_status_vocabulary.sql: drop the nine status FKs, the status_sheet columns and
-- lab_status.
--     psql -f sql/revert/082_lab_status_vocabulary_revert.sql   then delete 082's ledger row.
-- The values 082 made canonical stay canonical; the pre-change dump has the old spellings.

BEGIN;

DO $r$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['dna_extraction', 'rna_extraction', 'hic_lysate', 'hic_library',
                           'illumina_library', 'pacbio_library', 'ont_library',
                           'rna_library_ilmn', 'rna_library_kinx'] LOOP
    EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', t, t || '_status_fkey');
    EXECUTE format('ALTER TABLE %I DROP COLUMN status_sheet', t);
  END LOOP;
END
$r$;

DROP TABLE lab_status;

COMMIT;
