-- 070_v4_submission_part_and_accessions.sql -- Phase RG: a submitted haplotype is enforced against
-- the curated assembly part it submits, and its accessions are split by kind.
--
-- Why. Owner, 2026-10-20: enforce ref_submission_haplotype against ref_assembly_part, and split
-- assembly_accession, which held two kinds of ID (live, 2026-10-30, 174 haplotype rows):
--   - 96 ERZ...: ENA *analysis* accessions, written by ENA-ref-genomes step 09 from the Webin
--     assembly receipt. Not assembly accessions; step 10 later resolves the GCA_.
--   - 60 WGS master accessions (JB...000000000, CDSAW...000000000) from the earlier NCBI submissions.
--   - 18 empty. 148 GCA_ accessions, all well-formed.
-- (The 2026-10-20 notes said 112 and 62; these counts are re-measured.)
--
-- How.
--   1. New column analysis_accession, CHECK ~ '^ERZ[0-9]+$'; the 96 ERZ values move into it.
--      assembly_accession keeps WGS masters, CHECK ~ '^[A-Z]{4}([A-Z]{2})?[0-9]{8,9}$';
--      gca_accession CHECK ~ '^GCA_[0-9]{9}\.[0-9]+$'; at most one of analysis/assembly per row.
--      has_value now counts analysis_accession too.
--   2. New columns assembly_id and stage (always 3), and FK (assembly_id, stage, haplotype) ->
--      ref_assembly_part (its UNIQUE natural key). All 166 rows with an assembly have their stage-3
--      part; the 8 under the 4 submissions with no single curated assembly stay NULL.
--      assembly_id always equals the submission's: a BEFORE trigger sets it on every insert and
--      update, and an AFTER UPDATE OF assembly_id trigger on ref_submission pushes it down (ENA
--      step 09 and the sync set ref_submission.assembly_id after writing the haplotypes).
--      The FK is DEFERRABLE INITIALLY DEFERRED: the nightly v4 sync is one transaction that may
--      drop a part and relink the submission later in it; the commit judges the end state, and a
--      submitted haplotype whose curated part really vanished stops the sync for a person to look.
--   3. v4.ref_genomes_assembly_uploads shows coalesce(analysis_accession, assembly_accession) as
--      assembly_accession_hapN, so its readers (ENA step 10, OcOm_B219, genome notes) see public's
--      values. The sync routes public's one column by shape; check_ref_submission gains a check that
--      a haplotype's assembly_id equals its submission's.
--
-- Writers. ENA-ref-genomes step 09 writes the ERZ to analysis_accession (same day). Step 10 reads
-- the view and writes gca_accession: unchanged.
--
-- Revert: sql/revert/070_v4_submission_part_and_accessions_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_submission_haplotype') IS NULL THEN
    RAISE EXCEPTION '070 needs v4.ref_submission_haplotype (059)';
  END IF;
END
$pre$;

-- 1. Accessions -------------------------------------------------------------------------------

ALTER TABLE v4.ref_submission_haplotype ADD COLUMN IF NOT EXISTS analysis_accession text;
UPDATE v4.ref_submission_haplotype
SET analysis_accession = assembly_accession, assembly_accession = NULL
WHERE assembly_accession ~ '^ERZ';

ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_has_value;
ALTER TABLE v4.ref_submission_haplotype ADD CONSTRAINT ref_submission_haplotype_has_value
  CHECK (num_nonnulls(bioproject, analysis_accession, assembly_accession, gca_accession) > 0);
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_analysis_accession_shape;
ALTER TABLE v4.ref_submission_haplotype ADD CONSTRAINT ref_submission_haplotype_analysis_accession_shape
  CHECK (analysis_accession ~ '^ERZ[0-9]+$');
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_assembly_accession_shape;
ALTER TABLE v4.ref_submission_haplotype ADD CONSTRAINT ref_submission_haplotype_assembly_accession_shape
  CHECK (assembly_accession ~ '^[A-Z]{4}([A-Z]{2})?[0-9]{8,9}$');
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_gca_accession_shape;
ALTER TABLE v4.ref_submission_haplotype ADD CONSTRAINT ref_submission_haplotype_gca_accession_shape
  CHECK (gca_accession ~ '^GCA_[0-9]{9}\.[0-9]+$');
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_one_assembly_id;
ALTER TABLE v4.ref_submission_haplotype ADD CONSTRAINT ref_submission_haplotype_one_assembly_id
  CHECK (num_nonnulls(analysis_accession, assembly_accession) <= 1);

COMMENT ON COLUMN v4.ref_submission_haplotype.analysis_accession IS
  'ENA analysis accession (ERZ...) of the submitted assembly, from the Webin receipt (ENA-ref-genomes step 09). '
  'Not an assembly accession: step 10 resolves the GCA_ into gca_accession. Migration 070.';
COMMENT ON COLUMN v4.ref_submission_haplotype.assembly_accession IS
  'WGS master record accession (e.g. JBLNKH000000000) of an NCBI-submitted assembly. ENA submissions '
  'carry analysis_accession instead. Migration 070.';
COMMENT ON COLUMN v4.ref_submission_haplotype.gca_accession IS
  'Public INSDC assembly accession (GCA_...), resolved after processing (step 10).';

-- 2. The curated part it submits ---------------------------------------------------------------

ALTER TABLE v4.ref_submission_haplotype ADD COLUMN IF NOT EXISTS assembly_id bigint;
ALTER TABLE v4.ref_submission_haplotype ADD COLUMN IF NOT EXISTS stage integer NOT NULL DEFAULT 3;
ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_stage_check;
ALTER TABLE v4.ref_submission_haplotype ADD CONSTRAINT ref_submission_haplotype_stage_check CHECK (stage = 3);
COMMENT ON COLUMN v4.ref_submission_haplotype.assembly_id IS
  'The submission''s curated assembly (ref_submission.assembly_id, kept equal by trigger). With stage and '
  'haplotype it names the ref_assembly_part submitted. Migration 070.';
COMMENT ON COLUMN v4.ref_submission_haplotype.stage IS 'Always 3 (curated): what is submitted. Migration 070.';

CREATE OR REPLACE FUNCTION v4.ref_submission_haplotype_assembly() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  SELECT s.assembly_id INTO NEW.assembly_id FROM v4.ref_submission s WHERE s.submission_id = NEW.submission_id;
  RETURN NEW;
END
$fn$;
DROP TRIGGER IF EXISTS ref_submission_haplotype_assembly ON v4.ref_submission_haplotype;
CREATE TRIGGER ref_submission_haplotype_assembly BEFORE INSERT OR UPDATE ON v4.ref_submission_haplotype
  FOR EACH ROW EXECUTE FUNCTION v4.ref_submission_haplotype_assembly();

CREATE OR REPLACE FUNCTION v4.ref_submission_assembly_to_haplotypes() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  UPDATE v4.ref_submission_haplotype h SET assembly_id = NEW.assembly_id
  WHERE h.submission_id = NEW.submission_id AND h.assembly_id IS DISTINCT FROM NEW.assembly_id;
  RETURN NULL;
END
$fn$;
DROP TRIGGER IF EXISTS ref_submission_assembly_to_haplotypes ON v4.ref_submission;
CREATE TRIGGER ref_submission_assembly_to_haplotypes AFTER UPDATE OF assembly_id ON v4.ref_submission
  FOR EACH ROW WHEN (OLD.assembly_id IS DISTINCT FROM NEW.assembly_id)
  EXECUTE FUNCTION v4.ref_submission_assembly_to_haplotypes();

UPDATE v4.ref_submission_haplotype h SET assembly_id = s.assembly_id
FROM v4.ref_submission s WHERE s.submission_id = h.submission_id AND h.assembly_id IS DISTINCT FROM s.assembly_id;

ALTER TABLE v4.ref_submission_haplotype DROP CONSTRAINT IF EXISTS ref_submission_haplotype_part_fkey;
ALTER TABLE v4.ref_submission_haplotype ADD CONSTRAINT ref_submission_haplotype_part_fkey
  FOREIGN KEY (assembly_id, stage, haplotype) REFERENCES v4.ref_assembly_part (assembly_id, stage, haplotype)
  DEFERRABLE INITIALLY DEFERRED;
CREATE INDEX IF NOT EXISTS ref_submission_haplotype_part_idx ON v4.ref_submission_haplotype (assembly_id, stage, haplotype);

-- 3. View, sync and checks ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v4.ref_genomes_assembly_uploads AS
SELECT s.og_id,
       s.biosample,
       s.bioproject_umbrella,
       h1.bioproject AS bioproject_hap1,
       h2.bioproject AS bioproject_hap2,
       s.bioproject_rawdata,
       coalesce(h1.analysis_accession, h1.assembly_accession) AS assembly_accession_hap1,  -- 070: ERZ or WGS master
       coalesce(h2.analysis_accession, h2.assembly_accession) AS assembly_accession_hap2,
       s.embargo_status,
       h1.gca_accession AS gca_accession_hap1,
       h2.gca_accession AS gca_accession_hap2
FROM v4.ref_submission s
LEFT JOIN v4.ref_submission_haplotype h1 ON h1.submission_id = s.submission_id AND h1.haplotype = 'hap1'
LEFT JOIN v4.ref_submission_haplotype h2 ON h2.submission_id = s.submission_id AND h2.haplotype = 'hap2';
COMMENT ON VIEW v4.ref_genomes_assembly_uploads IS
  'Compatibility view: public.ref_genomes_assembly_uploads''s columns in its order. Not a write path.';

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
    -- 070: public keeps ERZ (ENA analysis) and WGS master accessions in one column; v4 splits them.
    SELECT sub.submission_id, h.haplotype, h.bioproject,
           CASE WHEN h.assembly_accession ~ '^ERZ' THEN h.assembly_accession END AS analysis_accession,
           CASE WHEN h.assembly_accession !~ '^ERZ' THEN h.assembly_accession END AS assembly_accession,
           h.gca_accession
    FROM v4.sync_ref_submission_source s
    JOIN v4.ref_submission sub ON sub.og_id = s.og_id
    CROSS JOIN LATERAL (VALUES ('hap1', s.bioproject_hap1, s.assembly_accession_hap1, s.gca_accession_hap1),
                               ('hap2', s.bioproject_hap2, s.assembly_accession_hap2, s.gca_accession_hap2)) h (haplotype, bioproject, assembly_accession, gca_accession)
    WHERE s.key_problem IS NULL AND num_nonnulls(h.bioproject, h.assembly_accession, h.gca_accession) > 0;
  DELETE FROM v4.ref_submission_haplotype t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_hap h WHERE (h.submission_id, h.haplotype) = (t.submission_id, t.haplotype));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_submission_haplotype deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_submission_haplotype AS t (submission_id, haplotype, bioproject, analysis_accession, assembly_accession, gca_accession)
  SELECT submission_id, haplotype, bioproject, analysis_accession, assembly_accession, gca_accession FROM sync_ref_hap
  ON CONFLICT (submission_id, haplotype) DO UPDATE SET bioproject = EXCLUDED.bioproject, analysis_accession = EXCLUDED.analysis_accession, assembly_accession = EXCLUDED.assembly_accession, gca_accession = EXCLUDED.gca_accession, loaded_at = now()
    WHERE (t.bioproject, t.analysis_accession, t.assembly_accession, t.gca_accession) IS DISTINCT FROM (EXCLUDED.bioproject, EXCLUDED.analysis_accession, EXCLUDED.assembly_accession, EXCLUDED.gca_accession);
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

  check_name := 'ref_submission_haplotype: assembly_id differs from its submission (070)';
  SELECT count(*) INTO problems FROM v4.ref_submission_haplotype h JOIN v4.ref_submission s USING (submission_id)
  WHERE h.assembly_id IS DISTINCT FROM s.assembly_id;
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

-- Verify ---------------------------------------------------------------------------------------

SET CONSTRAINTS v4.ref_submission_haplotype_part_fkey IMMEDIATE;  -- check the FK now, not at COMMIT

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v4.sync_ref_submission() LOOP
    IF r.changed <> 0 THEN
      RAISE EXCEPTION '070: the sync is not a no-op after the migration: % (%)', r.step, r.changed;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM v4.check_ref_submission() LOOP
    IF r.check_name LIKE 'note:%' THEN
      RAISE NOTICE '070 %: %', r.check_name, r.problems;
    ELSIF r.problems <> 0 THEN
      RAISE EXCEPTION '070 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
  RAISE NOTICE '070: % haplotype rows; % analysis (ERZ), % WGS master, % linked to their curated part',
    (SELECT count(*) FROM v4.ref_submission_haplotype),
    (SELECT count(analysis_accession) FROM v4.ref_submission_haplotype),
    (SELECT count(assembly_accession) FROM v4.ref_submission_haplotype),
    (SELECT count(assembly_id) FROM v4.ref_submission_haplotype);
END
$verify$;

COMMIT;
