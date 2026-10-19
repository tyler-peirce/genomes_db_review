-- 059_v4_ref_submission.sql -- Phase RG.3: reference-genome NCBI submissions, in schema v4.
--
-- Why. public.ref_genomes_assembly_uploads keeps hap1 and hap2 side by side (bioproject_hap1,
-- bioproject_hap2, assembly_accession_hap1, ...), one row per OG with no link to the assembly
-- submitted. public.ref_genomes_sra_uploads.ncbi_status holds either a status ('Released',
-- 'ToBeReleased') or a date (132 rows on 2026-10-19). docs/ref_genomes_runbook_rg0_rg5.md §2.
-- This builds:
--   ref_submission            one per OG (as public): BioSample, umbrella and raw-data BioProjects,
--                             embargo; assembly_id where the OG has exactly one curated assembly
--   ref_submission_haplotype  one per (submission, hap1|hap2): BioProject, assembly and GCA
--                             accessions
--   ref_sra_upload            one per SRA run accession, under its submission; ncbi_status split
--                             into ncbi_status and status_date
-- and compatibility views v4.ref_genomes_assembly_uploads and v4.ref_genomes_sra_uploads, which
-- reproduce public exactly.
--
-- status_date. Its meaning (submitted? scheduled release?) is not known yet (owner, RG.0 §3), so
-- the column has a neutral name. A value is a status or an ISO date, never both, as in public;
-- the compatibility view recombines them as to_char(status_date, 'YYYY-MM-DD').
--
-- assembly_id is set by the sync where the OG has exactly one v4 assembly with a stage-3 part:
-- 84 of 88 on 2026-10-19. OG637, OG645 and OG910 have two curated assemblies and OG906 none;
-- they stay NULL. ON DELETE SET NULL. Kept one-submission-per-OG because public is; a
-- resubmission of a later assembly is a design question for RG.6.
--
-- Writers: another repo, not yet identified (RG.0 §3). The nightly sync copies what they write.
-- A value outside the CHECK domains (embargo, data_type, status) is reported as an untriaged key
-- problem and fails the night rather than being guessed.
--
-- Sync and checks follow 057/058: v4.sync_ref_submission(), v4.check_ref_submission(),
-- window-only (dropped at RG.6). Needs 057 (v4.ref_assembly).
--
-- Revert: sql/revert/059_v4_ref_submission_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_assembly') IS NULL THEN
    RAISE EXCEPTION '059 needs schema v4 from 057';
  END IF;
END
$pre$;

CREATE TABLE IF NOT EXISTS v4.ref_submission (
    submission_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id               text   NOT NULL UNIQUE REFERENCES public.sample (og_id),
    assembly_id         bigint REFERENCES v4.ref_assembly ON DELETE SET NULL,
    biosample           text,
    bioproject_umbrella text,
    bioproject_rawdata  text,
    embargo_status      text   NOT NULL CHECK (embargo_status IN ('Release', 'Embargo')),
    loaded_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ref_submission_assembly_id_idx ON v4.ref_submission (assembly_id);
COMMENT ON TABLE v4.ref_submission IS
  'NCBI submission of a reference genome, one per OG. assembly_id: the OG''s one curated assembly, '
  'NULL where it has none or several. Writer: another repo, not yet identified (RG.0 §3).';

CREATE TABLE IF NOT EXISTS v4.ref_submission_haplotype (
    submission_id      bigint NOT NULL REFERENCES v4.ref_submission ON DELETE CASCADE,
    haplotype          text   NOT NULL CHECK (haplotype IN ('hap1', 'hap2')),
    bioproject         text,
    assembly_accession text,
    gca_accession      text,
    loaded_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (submission_id, haplotype),
    CONSTRAINT ref_submission_haplotype_has_value CHECK (num_nonnulls(bioproject, assembly_accession, gca_accession) > 0)
);
COMMENT ON TABLE v4.ref_submission_haplotype IS
  'Per-haplotype BioProject and assembly accessions of a submission. Was the _hap1/_hap2 column pairs.';

CREATE TABLE IF NOT EXISTS v4.ref_sra_upload (
    srr_accession text   PRIMARY KEY,
    submission_id bigint NOT NULL REFERENCES v4.ref_submission,
    filenames     text,
    data_type     text   CHECK (data_type IN ('hifi', 'hic', 'ont', 'illumina')),
    ncbi_status   text   CHECK (ncbi_status IN ('Released', 'ToBeReleased')),
    status_date   date,
    loaded_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_sra_upload_status_or_date CHECK (num_nonnulls(ncbi_status, status_date) <= 1)
);
CREATE INDEX IF NOT EXISTS ref_sra_upload_submission_id_idx ON v4.ref_sra_upload (submission_id);
COMMENT ON TABLE v4.ref_sra_upload IS
  'Raw reads uploaded to the SRA for a submission, one row per run accession. Writer: another repo, '
  'not yet identified (RG.0 §3).';
COMMENT ON COLUMN v4.ref_sra_upload.status_date IS
  'The date public.ref_genomes_sra_uploads.ncbi_status held instead of a status. Meaning not yet '
  'known (submitted or release date); renamed once it is (RG.0 §3).';

-- Sync (window-only: dropped at RG.6) -------------------------------------------------------

CREATE OR REPLACE VIEW v4.sync_ref_submission_source AS
SELECT u.*,
       CASE WHEN NOT EXISTS (SELECT 1 FROM public.sample s WHERE s.og_id = u.og_id) THEN 'og_id not in sample'
            WHEN u.embargo_status IS NULL OR u.embargo_status NOT IN ('Release', 'Embargo') THEN 'embargo_status not Release/Embargo'
       END AS key_problem
FROM public.ref_genomes_assembly_uploads u
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_excluded_rows x
                  WHERE x.source_table = 'ref_genomes_assembly_uploads' AND x.og_id = u.og_id);

CREATE OR REPLACE VIEW v4.sync_ref_sra_source AS
SELECT s.*,
       CASE WHEN s.ncbi_status IN ('Released', 'ToBeReleased') THEN s.ncbi_status END AS status_value,
       CASE WHEN s.ncbi_status ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN s.ncbi_status::date END AS status_date,
       CASE WHEN s.og_id IS NULL OR NOT EXISTS (SELECT 1 FROM v4.sync_ref_submission_source u
                                               WHERE u.og_id = s.og_id AND u.key_problem IS NULL)
              THEN 'og_id has no carried submission'
            WHEN s.data_type IS NOT NULL AND s.data_type NOT IN ('hifi', 'hic', 'ont', 'illumina') THEN 'unknown data_type'
            WHEN s.ncbi_status IS NOT NULL AND s.ncbi_status NOT IN ('Released', 'ToBeReleased') AND s.ncbi_status !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
              THEN 'ncbi_status neither a status nor an ISO date'
       END AS key_problem
FROM public.ref_genomes_sra_uploads s
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_excluded_rows x
                  WHERE x.source_table = 'ref_genomes_sra_uploads' AND x.og_id = s.og_id);

COMMENT ON VIEW v4.sync_ref_submission_source IS 'Phase RG window only: public.ref_genomes_assembly_uploads as the sync reads it. Dropped at RG.6.';
COMMENT ON VIEW v4.sync_ref_sra_source IS 'Phase RG window only: public.ref_genomes_sra_uploads as the sync reads it, status split. Dropped at RG.6.';

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

  INSERT INTO v4.ref_sra_upload AS t (srr_accession, submission_id, filenames, data_type, ncbi_status, status_date)
  SELECT s.srr_accession, sub.submission_id, s.filenames, s.data_type, s.status_value, s.status_date
  FROM v4.sync_ref_sra_source s JOIN v4.ref_submission sub ON sub.og_id = s.og_id
  WHERE s.key_problem IS NULL
  ON CONFLICT (srr_accession) DO UPDATE SET submission_id = EXCLUDED.submission_id, filenames = EXCLUDED.filenames,
    data_type = EXCLUDED.data_type, ncbi_status = EXCLUDED.ncbi_status, status_date = EXCLUDED.status_date, loaded_at = now()
    WHERE (t.submission_id, t.filenames, t.data_type, t.ncbi_status, t.status_date)
          IS DISTINCT FROM (EXCLUDED.submission_id, EXCLUDED.filenames, EXCLUDED.data_type, EXCLUDED.ncbi_status, EXCLUDED.status_date);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_sra_upload upserted'; changed := n; RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v4.sync_ref_submission() IS
  'Phase RG window only: copy the two public upload tables into v4, and link each submission to its '
  'one curated assembly. Skips rows with a key_problem (check_ref_submission then fails). Dropped at RG.6.';

-- Views ---------------------------------------------------------------------------------------

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

CREATE OR REPLACE VIEW v4.ref_genomes_sra_uploads AS
SELECT u.srr_accession,
       s.og_id,
       u.filenames,
       u.data_type,
       coalesce(u.ncbi_status, to_char(u.status_date, 'YYYY-MM-DD')) AS ncbi_status
FROM v4.ref_sra_upload u
JOIN v4.ref_submission s ON s.submission_id = u.submission_id;
COMMENT ON VIEW v4.ref_genomes_sra_uploads IS
  'Compatibility view: public.ref_genomes_sra_uploads''s columns in its order, status and date '
  'recombined. Not a write path.';

-- Checks (window-only: dropped at RG.6) ------------------------------------------------------

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
END
$fn$;
COMMENT ON FUNCTION v4.check_ref_submission() IS
  'Phase RG window only: v4 submission tables against public. Every problems value must be 0 '
  'except checks named note:. Dropped at RG.6.';

-- Backfill and verify -----------------------------------------------------------------------

SELECT * FROM v4.sync_ref_submission();

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v4.check_ref_submission() LOOP
    IF r.check_name LIKE 'note:%' THEN
      RAISE NOTICE '059 %: %', r.check_name, r.problems;
    ELSIF r.problems <> 0 THEN
      RAISE EXCEPTION '059 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
END
$verify$;

GRANT SELECT ON ALL TABLES IN SCHEMA v4 TO readonly;
GRANT SELECT ON v4.ref_genomes_assembly_uploads TO oceangenom_web;

COMMIT;
