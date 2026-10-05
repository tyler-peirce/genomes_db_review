-- Verify genomes_db:create_v2_browse_views on pg

-- Asserts the views exist, are documented, and — more usefully — that they are actually
-- selectable and expose the two columns they exist to provide.

BEGIN;

DO $$
DECLARE
  v   text;
  rec record;
BEGIN
  FOREACH v IN ARRAY ARRAY[
    'v_tissue_browse', 'v_dna_extraction_browse', 'v_rna_extraction_browse',
    'v_hic_lysate_browse', 'v_library_browse', 'v_illumina_library_browse',
    'v_pacbio_library_browse', 'v_ont_library_browse', 'v_hic_library_browse',
    'v_rna_library_ilmn_browse', 'v_rna_library_kinx_browse', 'v_sequencing_browse'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.views
                   WHERE table_schema = 'v2' AND table_name = v) THEN
      RAISE EXCEPTION 'Missing expected view: v2.%', v;
    END IF;

    -- Executes the view, so a column that does not exist on the base table fails here rather
    -- than on first use.
    EXECUTE format('SELECT 1 FROM v2.%I LIMIT 1', v);

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = v AND column_name = 'og_id') THEN
      RAISE EXCEPTION 'v2.% does not expose og_id, which is the point of it (F1)', v;
    END IF;

    IF obj_description(format('v2.%I', v)::regclass, 'pg_class') IS NULL THEN
      RAISE EXCEPTION 'View v2.% has no COMMENT (Finding 9)', v;
    END IF;
  END LOOP;

  -- Every view over a table with an attempt number recovers `latest` (F4a).
  FOREACH v IN ARRAY ARRAY[
    'v_dna_extraction_browse', 'v_rna_extraction_browse', 'v_hic_lysate_browse',
    'v_illumina_library_browse', 'v_pacbio_library_browse', 'v_ont_library_browse',
    'v_hic_library_browse', 'v_rna_library_ilmn_browse', 'v_rna_library_kinx_browse'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = v AND column_name = 'is_latest') THEN
      RAISE EXCEPTION 'v2.% does not expose is_latest (F4a)', v;
    END IF;
  END LOOP;

  -- The Hi-C library view must keep the live and legacy proximity-ligation values apart (F13).
  FOR rec IN
    SELECT unnest(ARRAY['prox_ligation_conc', 'prox_ligation_conc_legacy']) AS col
  LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = 'v_hic_library_browse'
                     AND column_name = rec.col) THEN
      RAISE EXCEPTION 'v2.v_hic_library_browse is missing % (F13)', rec.col;
    END IF;
  END LOOP;
END $$;

ROLLBACK;
