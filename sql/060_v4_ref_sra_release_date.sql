-- 060_v4_ref_sra_release_date.sql -- Phase RG: v4.ref_sra_upload.status_date becomes release_date.
--
-- Why. 059 gave the date that public.ref_genomes_sra_uploads.ncbi_status holds instead of a status
-- a neutral name, because its meaning was not known (RG.0 §3). It is now known: the writer,
-- ENA-ref-genomes workflow/09_push_submission_data_to_db.py, stores the holdUntilDate of the ENA
-- component receipt, "the embargo end date", and OcOm_B219 scripts/queries.py (RELEASE_STATE_SQL)
-- reads a date <= CURRENT_DATE as public and a later one as embargoed. So it is the scheduled
-- release date. docs/ref_genomes_rg0_record.md §3.
--
-- Renames the column, the matching column of v4.sync_ref_sra_source, and the comments, and
-- recreates v4.sync_ref_submission(), whose body names the column. The compatibility view
-- v4.ref_genomes_sra_uploads follows the rename by itself, and its output (public's ncbi_status)
-- is unchanged. No data changes.
--
-- Idempotent: does nothing where release_date already exists. Revert:
-- sql/revert/060_v4_ref_sra_release_date_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_sra_upload') IS NULL THEN
    RAISE EXCEPTION '060 needs v4.ref_sra_upload from 059';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'v4' AND table_name = 'ref_sra_upload' AND column_name = 'status_date') THEN
    ALTER TABLE v4.ref_sra_upload RENAME COLUMN status_date TO release_date;
    ALTER TABLE v4.ref_sra_upload RENAME CONSTRAINT ref_sra_upload_status_or_date TO ref_sra_upload_status_or_release_date;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'v4' AND table_name = 'sync_ref_sra_source' AND column_name = 'status_date') THEN
    ALTER VIEW v4.sync_ref_sra_source RENAME COLUMN status_date TO release_date;
  END IF;
END
$pre$;

COMMENT ON COLUMN v4.ref_sra_upload.release_date IS
  'Scheduled public release (embargo end) of the run: ENA holdUntilDate, written by ENA-ref-genomes '
  'step 09. public.ref_genomes_sra_uploads keeps it in ncbi_status instead of a status.';
COMMENT ON TABLE v4.ref_sra_upload IS
  'Raw reads uploaded to the SRA/ENA for a submission, one row per run accession. Writer: '
  'ENA-ref-genomes workflow/09_push_submission_data_to_db.py.';
COMMENT ON TABLE v4.ref_submission IS
  'NCBI/ENA submission of a reference genome, one per OG. assembly_id: the OG''s one curated assembly, '
  'NULL where it has none or several. Writers: ENA-ref-genomes steps 09 (accessions) and 10 (GCA), '
  'and OcOm_B219 scripts/resolve_gca_accessions.py (GCA).';

CREATE OR REPLACE FUNCTION v4.sync_ref_submission() RETURNS TABLE (step text, changed bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp SET client_min_messages = warning AS $fn$
DECLARE
  n bigint;
BEGIN
  DELETE FROM v4.ref_sra_upload t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_ref_sra_source s WHERE s.key_problem IS NULL AND s.srr_accession = t.srr_accession);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_sra_upload deleted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_submission t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_ref_submission_source s WHERE s.key_problem IS NULL AND s.og_id = t.og_id);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_submission AS t (og_id, biosample, bioproject_umbrella, bioproject_rawdata, embargo_status)
  SELECT s.og_id, s.biosample, s.bioproject_umbrella, s.bioproject_rawdata, s.embargo_status FROM v4.sync_ref_submission_source s WHERE s.key_problem IS NULL
  ON CONFLICT (og_id) DO UPDATE SET biosample = EXCLUDED.biosample, bioproject_umbrella = EXCLUDED.bioproject_umbrella, bioproject_rawdata = EXCLUDED.bioproject_rawdata, embargo_status = EXCLUDED.embargo_status, loaded_at = now()
    WHERE (t.biosample, t.bioproject_umbrella, t.bioproject_rawdata, t.embargo_status) IS DISTINCT FROM (EXCLUDED.biosample, EXCLUDED.bioproject_umbrella, EXCLUDED.bioproject_rawdata, EXCLUDED.embargo_status);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission upserted'; changed := n; RETURN NEXT;

  UPDATE v4.ref_submission t SET assembly_id = c.assembly_id
  FROM (SELECT sub.submission_id,
               (SELECT CASE WHEN count(DISTINCT a.assembly_id) = 1 THEN min(a.assembly_id) END
                FROM v4.ref_assembly a JOIN v4.ref_assembly_part p ON p.assembly_id = a.assembly_id
                WHERE a.og_id = sub.og_id AND p.stage = 3) AS assembly_id
        FROM v4.ref_submission sub) c
  WHERE c.submission_id = t.submission_id AND t.assembly_id IS DISTINCT FROM c.assembly_id;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission assembly linked'; changed := n; RETURN NEXT;

  DROP TABLE IF EXISTS pg_temp.sync_ref_hap;
  CREATE TEMP TABLE sync_ref_hap ON COMMIT DROP AS
    SELECT sub.submission_id, h.haplotype, h.bioproject, h.assembly_accession, h.gca_accession
    FROM v4.sync_ref_submission_source s
    JOIN v4.ref_submission sub ON sub.og_id = s.og_id
    CROSS JOIN LATERAL (VALUES ('hap1', s.bioproject_hap1, s.assembly_accession_hap1, s.gca_accession_hap1),
                               ('hap2', s.bioproject_hap2, s.assembly_accession_hap2, s.gca_accession_hap2)) h (haplotype, bioproject, assembly_accession, gca_accession)
    WHERE s.key_problem IS NULL AND num_nonnulls(h.bioproject, h.assembly_accession, h.gca_accession) > 0;
  DELETE FROM v4.ref_submission_haplotype t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_hap h WHERE (h.submission_id, h.haplotype) = (t.submission_id, t.haplotype));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission_haplotype deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_submission_haplotype AS t (submission_id, haplotype, bioproject, assembly_accession, gca_accession)
  SELECT submission_id, haplotype, bioproject, assembly_accession, gca_accession FROM sync_ref_hap
  ON CONFLICT (submission_id, haplotype) DO UPDATE SET bioproject = EXCLUDED.bioproject, assembly_accession = EXCLUDED.assembly_accession, gca_accession = EXCLUDED.gca_accession, loaded_at = now()
    WHERE (t.bioproject, t.assembly_accession, t.gca_accession) IS DISTINCT FROM (EXCLUDED.bioproject, EXCLUDED.assembly_accession, EXCLUDED.gca_accession);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission_haplotype upserted'; changed := n; RETURN NEXT;

  INSERT INTO v4.ref_sra_upload AS t (srr_accession, submission_id, filenames, data_type, ncbi_status, release_date)
  SELECT s.srr_accession, sub.submission_id, s.filenames, s.data_type, s.status_value, s.release_date
  FROM v4.sync_ref_sra_source s JOIN v4.ref_submission sub ON sub.og_id = s.og_id
  WHERE s.key_problem IS NULL
  ON CONFLICT (srr_accession) DO UPDATE SET submission_id = EXCLUDED.submission_id, filenames = EXCLUDED.filenames,
    data_type = EXCLUDED.data_type, ncbi_status = EXCLUDED.ncbi_status, release_date = EXCLUDED.release_date, loaded_at = now()
    WHERE (t.submission_id, t.filenames, t.data_type, t.ncbi_status, t.release_date)
          IS DISTINCT FROM (EXCLUDED.submission_id, EXCLUDED.filenames, EXCLUDED.data_type, EXCLUDED.ncbi_status, EXCLUDED.release_date);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_sra_upload upserted'; changed := n; RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v4.sync_ref_submission() IS
  'Phase RG window only: copy the two public upload tables into v4, and link each submission to its '
  'one curated assembly. Skips rows with a key_problem (check_ref_submission then fails). Dropped at RG.6.';

-- Verify: the sync is a no-op and every check passes ----------------------------------------

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v4.sync_ref_submission() LOOP
    IF r.changed <> 0 THEN
      RAISE EXCEPTION '060: sync changed rows after the rename: % (%)', r.step, r.changed;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM v4.check_ref_submission() LOOP
    IF r.check_name NOT LIKE 'note:%' AND r.problems <> 0 THEN
      RAISE EXCEPTION '060 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
END
$verify$;

COMMIT;
