-- Verify genomes_db:create_v2_lab_tables on pg

-- Asserts existence and emptiness, and then the things this change exists to guarantee: that
-- the defects the previous scaffold reproduced are actually absent, and that the constraints
-- that make an empty schema worth building are actually present.

BEGIN;

DO $$
DECLARE
  tbl        text;
  col        text;
  row_count  bigint;
  actual     text;
  rec        record;
  -- The tables this change owns. Every sweep below is scoped to these: later changes add
  -- tables to `v2` (the LCA group, the quarantine table) that live under different rules, and
  -- `sqitch verify` re-runs this script after those have been deployed.
  owned      text[] := ARRAY[
    'sample', 'tissue', 'dna_extraction', 'rna_extraction', 'hic_lysate', 'library',
    'illumina_library', 'pacbio_library', 'ont_library', 'hic_library',
    'rna_library_ilmn', 'rna_library_kinx', 'sequencing', 'prep_automation'];
BEGIN
  ------------------------------------------------------------------ tables exist and are empty
  FOREACH tbl IN ARRAY ARRAY[
    'sample', 'tissue', 'dna_extraction', 'rna_extraction', 'hic_lysate', 'library',
    'illumina_library', 'pacbio_library', 'ont_library', 'hic_library',
    'rna_library_ilmn', 'rna_library_kinx', 'sequencing'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = 'v2' AND table_name = tbl) THEN
      RAISE EXCEPTION 'Missing expected table: v2.%', tbl;
    END IF;

    EXECUTE format('SELECT count(*) FROM v2.%I', tbl) INTO row_count;
    IF row_count <> 0 THEN
      RAISE EXCEPTION 'Expected v2.% to be empty, found % rows', tbl, row_count;
    END IF;
  END LOOP;

  ------------------------------------------------------------------ the lookup is seeded (F12)
  SELECT count(*) INTO row_count FROM v2.prep_automation;
  IF row_count <> 2 THEN
    RAISE EXCEPTION 'Expected 2 rows in v2.prep_automation, found %', row_count;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM v2.prep_automation WHERE prep_automation = 'Automated Biomek i7') THEN
    RAISE EXCEPTION 'v2.prep_automation is missing the correctly-spelled automated value';
  END IF;

  ------------------------------------------------- F1: no derived og_id on any child table
  -- Restricted to BASE TABLEs throughout: the browse views of the next change legitimately
  -- expose og_id, is_latest and friends, and must not trip these assertions when `sqitch
  -- verify` re-runs every verify script after all changes are deployed.
  FOR rec IN
    SELECT c.table_name FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_name = ANY (owned) AND c.table_schema = 'v2' AND c.column_name = 'og_id'
      -- sample.og_id is the primary key; tissue.og_id is the immediate parent FK, which §6.0
      -- requires. F1 is about grandparent and higher ancestors.
      AND c.table_name NOT IN ('sample', 'tissue')
  LOOP
    RAISE EXCEPTION 'v2.%.og_id exists; tables below tissue must reach og_id through their parent FK (F1)', rec.table_name;
  END LOOP;

  -- og_num survives on sample only, where it derives from that table's own primary key.
  FOR rec IN
    SELECT c.table_name FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_name = ANY (owned) AND c.table_schema = 'v2' AND c.column_name = 'og_num' AND c.table_name <> 'sample'
  LOOP
    RAISE EXCEPTION 'v2.%.og_num exists; og_num belongs on sample only (F2)', rec.table_name;
  END LOOP;

  ---------------------------------------------------- F4/F5: dead columns are not carried over
  FOR rec IN
    SELECT table_name, column_name FROM (VALUES
      ('sample','tissues'), ('sample','extracted'), ('sample','extraction_queue'),
      ('sample','il_status'), ('sample','pb_status'), ('sample','hic_status'),
      ('sample','ont_num'), ('sample','rna_status'), ('sample','ilrna_status'),
      ('sample','rna_extraction'), ('sample','summary_comments'), ('sample','illumina_public'),
      ('sample','rna_kinnex_status'), ('sample','rna_processing_comment'),
      ('dna_extraction','ratioqubit_nanodrop'),
      ('rna_library_ilmn','kinnex_primers'), ('rna_library_ilmn','kinnex_barcode')
    ) AS t(table_name, column_name)
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'v2' AND table_name = rec.table_name
                 AND column_name = rec.column_name) THEN
      RAISE EXCEPTION 'v2.%.% should not exist (F4/F5)', rec.table_name, rec.column_name;
    END IF;
  END LOOP;

  ------------------------------------------- F6: sequencing has one library FK, not five columns
  FOR rec IN
    SELECT column_name FROM information_schema.columns
    WHERE table_schema = 'v2' AND table_name = 'sequencing'
      AND column_name IN ('rna_library_tube_id', 'illumina_library_tube_id',
                          'ont_library_tube_id', 'pacbio_library_tube_id', 'hic_library_tube_id')
  LOOP
    RAISE EXCEPTION 'v2.sequencing.% should be replaced by library_tube_id (F6)', rec.column_name;
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                 WHERE constraint_schema = 'v2' AND constraint_name = 'sequencing_library_fkey') THEN
    RAISE EXCEPTION 'Missing v2.sequencing -> v2.library foreign key (F6)';
  END IF;

  ------------------------------------------------------- F4a: status_overwrite is boolean, and
  ------------------------------------------------------- `latest` is nowhere (it is a view column)
  FOR rec IN
    SELECT c.table_name, c.data_type FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_name = ANY (owned) AND c.table_schema = 'v2' AND c.column_name = 'status_overwrite'
  LOOP
    IF rec.data_type <> 'boolean' THEN
      RAISE EXCEPTION 'v2.%.status_overwrite is %, expected boolean (F4a)', rec.table_name, rec.data_type;
    END IF;
  END LOOP;

  FOR rec IN
    SELECT c.table_name FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_name = ANY (owned) AND c.table_schema = 'v2' AND c.column_name = 'latest'
  LOOP
    RAISE EXCEPTION 'v2.%.latest exists; Latest is MAX(#) per parent and belongs in a view (F4a)', rec.table_name;
  END LOOP;

  ---------------------------------------------------------- F3: dates are dates, not text
  FOR rec IN
    SELECT c.table_name, c.column_name, c.data_type FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_name = ANY (owned) AND c.table_schema = 'v2'
      AND (c.column_name LIKE '%\_date' OR c.column_name LIKE 'date\_%')
      AND c.column_name <> 'seq_date'          -- parsed from run_id, legitimately text
  LOOP
    IF rec.data_type <> 'date' THEN
      RAISE EXCEPTION 'v2.%.% is %, expected date (F3)', rec.table_name, rec.column_name, rec.data_type;
    END IF;
  END LOOP;

  ------------------------------------------------------------- F8: no character varying(n)
  FOR rec IN
    SELECT c.table_name, c.column_name FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_name = ANY (owned) AND c.table_schema = 'v2' AND c.data_type = 'character varying'
  LOOP
    RAISE EXCEPTION 'v2.%.% is character varying; v2 standardises on text (F8)', rec.table_name, rec.column_name;
  END LOOP;

  ------------------------------------------------------- F7: parent FK columns are NOT NULL
  FOR rec IN
    SELECT table_name, column_name FROM (VALUES
      ('tissue','og_id'), ('dna_extraction','tissue_id'), ('rna_extraction','tissue_id'),
      ('hic_lysate','tissue_id'), ('illumina_library','dna_id'), ('pacbio_library','dna_id'),
      ('ont_library','dna_id'), ('hic_library','lysate_id'), ('rna_library_ilmn','rna_id'),
      ('rna_library_kinx','rna_id'), ('sequencing','library_tube_id'), ('library','library_type')
    ) AS t(table_name, column_name)
  LOOP
    SELECT is_nullable INTO actual FROM information_schema.columns
    WHERE table_schema = 'v2' AND table_name = rec.table_name AND column_name = rec.column_name;
    IF actual IS NULL THEN
      RAISE EXCEPTION 'Missing expected column v2.%.%', rec.table_name, rec.column_name;
    END IF;
    IF actual <> 'NO' THEN
      RAISE EXCEPTION 'v2.%.% is nullable, expected NOT NULL (F7)', rec.table_name, rec.column_name;
    END IF;
  END LOOP;

  ------------------------------------------ F7: attempt-number uniqueness and the Kinnex FK
  FOREACH col IN ARRAY ARRAY[
    'dna_extraction_attempt_key', 'rna_extraction_attempt_key', 'hic_lysate_attempt_key',
    'illumina_library_attempt_key', 'pacbio_library_attempt_key', 'ont_library_attempt_key',
    'hic_library_attempt_key', 'rna_library_ilmn_attempt_key', 'rna_library_kinx_attempt_key',
    'rna_library_kinx_rna_id_fkey'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                   WHERE constraint_schema = 'v2' AND constraint_name = col) THEN
      RAISE EXCEPTION 'Missing expected constraint: % (F7)', col;
    END IF;
  END LOOP;

  --------------------------------------------------- every FK column carries a leading index
  FOR rec IN
    SELECT c.conrelid::regclass::text AS tbl,
           a.attname                  AS colname
    FROM pg_constraint c
    JOIN pg_namespace n ON n.oid = c.connamespace AND n.nspname = 'v2'
    JOIN LATERAL unnest(c.conkey[1:1]) AS k(attnum) ON true
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
    WHERE c.contype = 'f'
      AND c.conrelid::regclass::text LIKE 'v2.%'
      AND split_part(c.conrelid::regclass::text, '.', 2) = ANY (owned)
      AND a.attname <> 'prep_automation'      -- two-value lookup; an index would never be used
      AND NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE i.indrelid = c.conrelid AND i.indkey[0] = a.attnum
      )
  LOOP
    RAISE EXCEPTION 'Foreign key column %.% has no leading index (F7 / Finding 4)', rec.tbl, rec.colname;
  END LOOP;

  ------------------------------------------------------------- F7/F9: objects are documented
  FOR rec IN
    SELECT c.relname FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'v2'
    WHERE c.relkind = 'r' AND c.relname = ANY (owned)
      AND obj_description(c.oid, 'pg_class') IS NULL
  LOOP
    RAISE EXCEPTION 'Table v2.% has no COMMENT (Finding 9)', rec.relname;
  END LOOP;

  ------------------------------------------------ F13: proximity ligation on both, by design
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'v2' AND table_name = 'hic_lysate'
                   AND column_name = 'prox_ligation_conc') THEN
    RAISE EXCEPTION 'Missing v2.hic_lysate.prox_ligation_conc (F13)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'v2' AND table_name = 'hic_library'
                   AND column_name = 'prox_ligation_conc') THEN
    RAISE EXCEPTION 'Missing the legacy v2.hic_library.prox_ligation_conc (F13)';
  END IF;

  --------------------------------------- §4.1: the fourteen previously-dropped columns landed
  FOR rec IN
    SELECT table_name, column_name FROM (VALUES
      ('rna_extraction','gdna_over_7kb_perc'),
      ('pacbio_library','sre_kit'), ('pacbio_library','post_sre_conc'),
      ('pacbio_library','final_pre_library_conc'), ('pacbio_library','prep_automation'),
      ('illumina_library','prep_automation'), ('illumina_library','library_plate_well'),
      ('illumina_library','index_plate'),
      ('rna_library_kinx','sequencing_sample_id'),
      ('hic_lysate','lysate_method'), ('hic_lysate','prox_ligation_date'),
      ('hic_lysate','prox_ligation_conc'),
      ('sequencing','status'), ('sequencing','hic_depth'),
      ('sample','cites'), ('sample','sample_receipt_date'), ('tissue','preservation'),
      ('hic_library','expected_distinct_30m_reads')
    ) AS t(table_name, column_name)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = rec.table_name
                     AND column_name = rec.column_name) THEN
      RAISE EXCEPTION 'Missing expected column v2.%.% (spreadsheet_column_gap_analysis.md)',
        rec.table_name, rec.column_name;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
