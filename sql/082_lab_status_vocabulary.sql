-- 082_lab_status_vocabulary.sql -- One table of allowed lab Status values, enforced by FK on nine sheets.
--
-- Backlog Medium 4, Finding 7. Each lab sheet's Status column (dna_extraction.status,
-- hic_library.hic_status, ...) was free text, and on 2026-11-09 held a few variants of the same
-- stage: 'HOLD' (98 rows) beside 'Hold' (30), 'Failed QC - Illumina' (35) and 'Failed QC - PacBio'
-- (20) beside 'Failed QC', the typos 'State 3 - Proximity Ligation' (14) and 'Ilumina' (48), and
-- 'Hold for Repeat check' (6). summary reports these values, so each variant split a count.
--
-- Owner decisions 2026-11-09: one shared table; canonical 'Hold'; 'Hold for Repeat check' is
-- 'Hold'; 'Shearing', 'ULI' and 'Shearing - ULI' stay three PacBio stages. The workbook is not
-- changed: the importer (OceanOmics-Database import_v2.py, STATUS_VARIANTS) maps the variants
-- every night, so it must be deployed with this file.
--
--   - lab_status (sheet, status) holds every sheet's allowed values: one place to read them, and
--     a new stage is one INSERT, not a migration. Seeded with the values on live after the map.
--   - Each sheet gets status_sheet, a stored constant naming its sheet, so a declared FK
--     (status_sheet, <status column>) -> lab_status (sheet, status) can serve nine vocabularies
--     from one table. Plain FK: PostgreSQL allows no ON UPDATE action on a generated column, so a
--     stage is renamed by inserting the new value, moving the rows, then deleting the old.
--   - The importer's column lists never write status_sheet, and the browse views list their
--     columns, so only SELECT * readers see it.
--   - A value not in its sheet's list is loaded by the importer as NULL with a lookup quarantine
--     record (the raw value is kept there), which closes once the value is added here.
--
-- Replay: lab_status and the FKs are created only if missing; the row updates are then no-ops.
-- Revert: sql/revert/082_lab_status_vocabulary_revert.sql (values stay canonical).

BEGIN;

CREATE TABLE IF NOT EXISTS lab_status (
    sheet  text NOT NULL,
    status text NOT NULL,
    note   text,
    PRIMARY KEY (sheet, status),
    CONSTRAINT lab_status_sheet_check CHECK (sheet IN (
      'dna_extraction', 'rna_extraction', 'hic_lysate', 'hic_library', 'illumina_library',
      'pacbio_library', 'ont_library', 'rna_library_ilmn', 'rna_library_kinx'))
);
COMMENT ON TABLE lab_status IS
  'The allowed values of each lab sheet''s Status column, one row per (sheet, status). Each sheet''s '
  'status column has an FK here through its status_sheet column (082). Add a row to allow a new '
  'stage; the importer (import_v2.py) matches case-blind and maps the variants in '
  'name_convert_v2.STATUS_VARIANTS.';
COMMENT ON COLUMN lab_status.sheet IS 'The table whose status column this value is allowed in.';
COMMENT ON COLUMN lab_status.status IS 'The value, as stored.';
COMMENT ON COLUMN lab_status.note IS 'Optional: what the stage means, for the lab to fill in.';

INSERT INTO lab_status (sheet, status) VALUES
  ('dna_extraction', 'Extracted'), ('dna_extraction', 'Extraction - DNeasy'),
  ('dna_extraction', 'Extraction - MagMaxCore'), ('dna_extraction', 'Extraction - Nanobind'),
  ('dna_extraction', 'Failed QC'), ('dna_extraction', 'For review'), ('dna_extraction', 'Hold'),
  ('dna_extraction', 'QC - Femto'), ('dna_extraction', 'ULI'),
  ('rna_extraction', 'Extracted'), ('rna_extraction', 'Failed QC'), ('rna_extraction', 'Hold'),
  ('hic_lysate', 'Awaiting Status'), ('hic_lysate', 'Combined'), ('hic_lysate', 'Completed'),
  ('hic_lysate', 'Failed QC'), ('hic_lysate', 'Hold'), ('hic_lysate', 'Not proceeding'),
  ('hic_lysate', 'Stage 1 - Lysate Prep'),
  ('hic_library', 'Combined'), ('hic_library', 'Deep Sequence - Illumina'), ('hic_library', 'Failed QC'),
  ('hic_library', 'Hold'), ('hic_library', 'Not proceeding'), ('hic_library', 'Sequenced'),
  ('hic_library', 'Stage 3 - Proximity Ligation'), ('hic_library', 'Stage 4 - Library Prep'),
  ('illumina_library', 'Failed QC'), ('illumina_library', 'Hold'),
  ('illumina_library', 'Library Prep - Ilmn DNA Prep'), ('illumina_library', 'QC - iSEQ'),
  ('illumina_library', 'Sequence - Illumina'), ('illumina_library', 'Sequenced'),
  ('pacbio_library', 'Awaiting Status'), ('pacbio_library', 'Failed QC'), ('pacbio_library', 'Hold'),
  ('pacbio_library', 'Library Prep - PacBio SMRTbell'), ('pacbio_library', 'Not proceeding'),
  ('pacbio_library', 'Polymerase Bound'), ('pacbio_library', 'QC - Femto'),
  ('pacbio_library', 'Sequence - PacBio'), ('pacbio_library', 'Sequenced'), ('pacbio_library', 'Shearing'),
  ('pacbio_library', 'Shearing - ULI'), ('pacbio_library', 'SRE'), ('pacbio_library', 'ULI'),
  ('ont_library', 'Failed QC'), ('ont_library', 'Hold'), ('ont_library', 'Library - LSK'),
  ('ont_library', 'Library - ULK'), ('ont_library', 'Sequenced'), ('ont_library', 'SRE'),
  ('rna_library_ilmn', 'Failed QC'), ('rna_library_ilmn', 'Hold'),
  ('rna_library_ilmn', 'Library Prep - Illumina mRNA'), ('rna_library_ilmn', 'Library Prep - Illumina rRNA depletion'),
  ('rna_library_ilmn', 'QC - iSEQ'), ('rna_library_ilmn', 'Sequenced'),
  ('rna_library_kinx', 'Failed QC'), ('rna_library_kinx', 'Hold'),
  ('rna_library_kinx', 'K1 - Kinnex cDNA Synthesis'), ('rna_library_kinx', 'K2 - Concatenation stage'),
  ('rna_library_kinx', 'Library Prep - PacBio Kinnex'), ('rna_library_kinx', 'Sequence - PacBio'),
  ('rna_library_kinx', 'Sequenced')
ON CONFLICT DO NOTHING;

-- The variant map, as in name_convert_v2.STATUS_VARIANTS ('*' is every sheet).
CREATE TEMP TABLE status_variant_082 (sheet text, variant text, canonical text) ON COMMIT DROP;
INSERT INTO status_variant_082 VALUES
  ('*', 'hold', 'Hold'),
  ('illumina_library', 'hold for repeat check', 'Hold'),
  ('hic_library', 'state 3 - proximity ligation', 'Stage 3 - Proximity Ligation'),
  ('rna_library_ilmn', 'failed qc - illumina', 'Failed QC'),
  ('rna_library_ilmn', 'library prep - ilumina mrna', 'Library Prep - Illumina mRNA'),
  ('rna_library_ilmn', 'library prep - ilumina rrna depletion', 'Library Prep - Illumina rRNA depletion'),
  ('rna_library_kinx', 'failed qc - pacbio', 'Failed QC');

DO $a$
DECLARE
  sheets text[][] := ARRAY[
    ['dna_extraction', 'status'], ['rna_extraction', 'status'], ['hic_lysate', 'lysate_status'],
    ['hic_library', 'hic_status'], ['illumina_library', 'ilmn_status'], ['pacbio_library', 'pacb_status'],
    ['ont_library', 'ont_status'], ['rna_library_ilmn', 'rna_status'], ['rna_library_kinx', 'rna_status']];
  t text;
  c text;
  n bigint;
  moved bigint := 0;
BEGIN
  FOR i IN 1 .. array_length(sheets, 1) LOOP
    t := sheets[i][1];
    c := sheets[i][2];

    -- Variants, then any other case-only difference, to the sheet's value.
    EXECUTE format(
      'UPDATE %1$I x SET %2$I = v.canonical FROM status_variant_082 v '
      'WHERE v.sheet IN (%3$L, ''*'') AND v.variant = lower(btrim(x.%2$I)) AND x.%2$I IS DISTINCT FROM v.canonical', t, c, t);
    GET DIAGNOSTICS n = ROW_COUNT; moved := moved + n;
    EXECUTE format(
      'UPDATE %1$I x SET %2$I = s.status FROM lab_status s '
      'WHERE s.sheet = %3$L AND lower(s.status) = lower(btrim(x.%2$I)) AND x.%2$I <> s.status', t, c, t);
    GET DIAGNOSTICS n = ROW_COUNT; moved := moved + n;

    EXECUTE format('SELECT count(*) FROM %1$I x WHERE x.%2$I IS NOT NULL AND NOT EXISTS '
                   '(SELECT 1 FROM lab_status s WHERE s.sheet = %3$L AND s.status = x.%2$I)', t, c, t) INTO n;
    IF n > 0 THEN
      RAISE EXCEPTION '082: % %.% value(s) are not in lab_status; add them or map them first', n, t, c;
    END IF;

    IF to_regclass(format('%I', t)) IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass(format('%I', t)) AND attname = 'status_sheet') THEN
      EXECUTE format('ALTER TABLE %I ADD COLUMN status_sheet text GENERATED ALWAYS AS (%L) STORED', t, t);
      EXECUTE format('COMMENT ON COLUMN %I.status_sheet IS %L', t,
        format('Always %L: names this table in lab_status, for the FK on %s (082).', t, c));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = t || '_status_fkey') THEN
      EXECUTE format('ALTER TABLE %1$I ADD CONSTRAINT %2$I FOREIGN KEY (status_sheet, %3$I) '
                     'REFERENCES lab_status (sheet, status) NOT VALID', t, t || '_status_fkey', c);
      EXECUTE format('ALTER TABLE %I VALIDATE CONSTRAINT %I', t, t || '_status_fkey');
    END IF;
  END LOOP;
  RAISE NOTICE '082: % status value(s) made canonical; nine status FKs in place', moved;

  -- Probes, inside a sub-block that is always rolled back.
  BEGIN
    BEGIN
      UPDATE illumina_library SET ilmn_status = 'PROBE082'
       WHERE illumina_library_tube_id = (SELECT min(illumina_library_tube_id) FROM illumina_library);
      RAISE EXCEPTION '082 probe: an unknown status was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
      UPDATE illumina_library SET ilmn_status = 'Shearing'
       WHERE illumina_library_tube_id = (SELECT min(illumina_library_tube_id) FROM illumina_library);
      RAISE EXCEPTION '082 probe: another sheet''s status was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    INSERT INTO lab_status (sheet, status) VALUES ('illumina_library', 'PROBE082');
    UPDATE illumina_library SET ilmn_status = 'PROBE082'
     WHERE illumina_library_tube_id = (SELECT min(illumina_library_tube_id) FROM illumina_library);
    RAISE EXCEPTION USING ERRCODE = 'P0082', MESSAGE = 'probes passed';
  EXCEPTION
    WHEN SQLSTATE 'P0082' THEN NULL;
  END;
END
$a$;

COMMIT;
