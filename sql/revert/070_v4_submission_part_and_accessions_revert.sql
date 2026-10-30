-- 070_v4_submission_part_and_accessions_revert.sql -- back to 069: drop the part FK, triggers and
-- shape checks; put the ERZ values back in assembly_accession; restore 059's view and 064's sync and
-- check text.
--
-- After running this, delete 070's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '070_v4_submission_part_and_accessions.sql';

BEGIN;

ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_part_fkey;
DROP INDEX IF EXISTS v4.ref_submission_haplotype_part_idx;
DROP TRIGGER IF EXISTS ref_submission_assembly_to_haplotypes ON v4.ref_submission;
DROP TRIGGER IF EXISTS ref_submission_haplotype_assembly ON v4.ref_submission_haplotype;
DROP FUNCTION IF EXISTS v4.ref_submission_assembly_to_haplotypes();
DROP FUNCTION IF EXISTS v4.ref_submission_haplotype_assembly();

CREATE OR REPLACE VIEW v4.ref_genomes_assembly_uploads AS
SELECT s.og_id,
       s.biosample,
       s.bioproject_umbrella,
       h1.bioproject AS bioproject_hap1,
       h2.bioproject AS bioproject_hap2,
       s.bioproject_rawdata,
       h1.assembly_accession AS assembly_accession_hap1,
       h2.assembly_accession AS assembly_accession_hap2,
       s.embargo_status,
       h1.gca_accession AS gca_accession_hap1,
       h2.gca_accession AS gca_accession_hap2
FROM v4.ref_submission s
LEFT JOIN v4.ref_submission_haplotype h1 ON h1.submission_id = s.submission_id AND h1.haplotype = 'hap1'
LEFT JOIN v4.ref_submission_haplotype h2 ON h2.submission_id = s.submission_id AND h2.haplotype = 'hap2';
COMMENT ON VIEW v4.ref_genomes_assembly_uploads IS
  'Compatibility view: public.ref_genomes_assembly_uploads''s columns in its order. Not a write path.';

ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_one_assembly_id;
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_gca_accession_shape;
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_assembly_accession_shape;
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_analysis_accession_shape;
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_stage_check;
UPDATE v4.ref_submission_haplotype SET assembly_accession = analysis_accession WHERE analysis_accession IS NOT NULL;
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_has_value;
ALTER TABLE v4.ref_submission_haplotype ADD CONSTRAINT ref_submission_haplotype_has_value
  CHECK (num_nonnulls(bioproject, assembly_accession, gca_accession) > 0);
ALTER TABLE v4.ref_submission_haplotype DROP COLUMN IF EXISTS analysis_accession,
  DROP COLUMN IF EXISTS assembly_id, DROP COLUMN IF EXISTS stage;
COMMENT ON COLUMN v4.ref_submission_haplotype.assembly_accession IS NULL;
COMMENT ON COLUMN v4.ref_submission_haplotype.gca_accession IS NULL;

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

  -- SRA run links (064): an upload with none, not reviewed and left unlinked, gets what the
  -- forward rule finds.
  INSERT INTO v4.ref_sra_upload_run (srr_accession, sequencing_id)
  SELECT u.srr_accession, r.sequencing_id
  FROM v4.ref_sra_upload u
  JOIN v4.ref_submission s ON s.submission_id = u.submission_id
  CROSS JOIN LATERAL v4.resolve_sra_upload_runs(s.og_id, u.data_type, u.filenames) AS r (sequencing_id)
  WHERE NOT EXISTS (SELECT 1 FROM v4.ref_sra_upload_run x WHERE x.srr_accession = u.srr_accession)
    AND NOT EXISTS (SELECT 1 FROM v4.ref_sra_upload_unlinked x WHERE x.srr_accession = u.srr_accession)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_sra_upload_run linked'; changed := n; RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v4.sync_ref_submission() IS
  'Phase RG window only: copy the two public upload tables into v4, link each submission to its '
  'one curated assembly, and link new SRA uploads to sequencing (064). Skips rows with a key_problem (check_ref_submission then fails). Dropped at RG.6.';

CREATE OR REPLACE FUNCTION v4.check_ref_submission() RETURNS TABLE (check_name text, problems bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  check_name := 'ref_genomes_assembly_uploads: differs from public (after triage, either way)';
  SELECT (SELECT count(*) FROM (SELECT og_id, biosample, bioproject_umbrella, bioproject_hap1, bioproject_hap2, bioproject_rawdata, assembly_accession_hap1, assembly_accession_hap2, embargo_status, gca_accession_hap1, gca_accession_hap2 FROM v4.ref_genomes_assembly_uploads
                                EXCEPT ALL SELECT og_id, biosample, bioproject_umbrella, bioproject_hap1, bioproject_hap2, bioproject_rawdata, assembly_accession_hap1, assembly_accession_hap2, embargo_status, gca_accession_hap1, gca_accession_hap2 FROM v4.sync_ref_submission_source WHERE key_problem IS NULL) x)
       + (SELECT count(*) FROM (SELECT og_id, biosample, bioproject_umbrella, bioproject_hap1, bioproject_hap2, bioproject_rawdata, assembly_accession_hap1, assembly_accession_hap2, embargo_status, gca_accession_hap1, gca_accession_hap2 FROM v4.sync_ref_submission_source WHERE key_problem IS NULL
                                EXCEPT ALL SELECT og_id, biosample, bioproject_umbrella, bioproject_hap1, bioproject_hap2, bioproject_rawdata, assembly_accession_hap1, assembly_accession_hap2, embargo_status, gca_accession_hap1, gca_accession_hap2 FROM v4.ref_genomes_assembly_uploads) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'ref_genomes_sra_uploads: differs from public (after triage, either way)';
  SELECT (SELECT count(*) FROM (SELECT srr_accession, og_id, filenames, data_type, ncbi_status FROM v4.ref_genomes_sra_uploads
                                EXCEPT ALL SELECT srr_accession, og_id, filenames, data_type, ncbi_status FROM v4.sync_ref_sra_source WHERE key_problem IS NULL) x)
       + (SELECT count(*) FROM (SELECT srr_accession, og_id, filenames, data_type, ncbi_status FROM v4.sync_ref_sra_source WHERE key_problem IS NULL
                                EXCEPT ALL SELECT srr_accession, og_id, filenames, data_type, ncbi_status FROM v4.ref_genomes_sra_uploads) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'uploads: public rows with an untriaged key problem';
  SELECT (SELECT count(*) FROM v4.sync_ref_submission_source WHERE key_problem IS NOT NULL)
       + (SELECT count(*) FROM v4.sync_ref_sra_source WHERE key_problem IS NOT NULL)
    INTO problems;
  RETURN NEXT;

  check_name := 'note: submissions with no single curated assembly';
  SELECT count(*) INTO problems FROM v4.ref_submission WHERE assembly_id IS NULL;
  RETURN NEXT;

  check_name := 'note: SRA uploads with no sequencing link';
  SELECT count(*) INTO problems FROM v4.v_sra_upload_run_readiness;
  RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v4.check_ref_submission() IS
  'Phase RG window only: v4 submission tables against public. Every problems value must be 0 '
  'except checks named note:. Dropped at RG.6.';

COMMIT;
