-- 071_v4_read_set_external_and_dates.sql -- Phase RG: external read sets are recorded as such,
-- and the last four undated read sets are dated (RG.6 gate G4).
--
-- Why. After 069, four read sets had no date and no run link (v4.v_read_set_run_readiness):
--   OG906  its HiFi reads are not OceanOmics sequencing: six cells SSB_cell1-3 and SSC_cell1-3
--          (s3:ocom.oceangenomes/pacbio-sra/OG906/, staged 2024-05) and no sequencing row. Its
--          GenomeScope summary on Acacia equals the stored row; its assemblies are v250212.
--   OG845  PACB_241018_LA and PACB_241023_AD (two libraries); S3 holds the three cells
--          (m84154_241018, _241019, _241024); every assembly is v241023.
--   OG781  PACB_250317_AD and PACB_260421_AMD; both cells on S3 and Acacia; assemblies at both
--          dates. Owner, 2026-11-02: date it 260421 (both runs, as the current assemblies).
--   OG763  no PacBio DNA row in the workbook, but one HiFi cell on S3 (m84154_251118_..._s4,
--          bc2015; the week's only PacBio run is PACB_251117_LAAMD) and v251117 assemblies.
-- Owner, 2026-11-02: date all four; an external read set may exist without a sequencing row.
--
-- How.
--   1. v4.ref_read_set_external: one row per read set whose reads came from outside, with its
--      cells, supplier (unknown for OG906) and a note. A trigger keeps the two kinds apart: an
--      external read set has no ref_read_set_run rows, and a read set with runs is not external.
--      v_read_set_run_readiness leaves external read sets out.
--   2. Dates, each only where the GenomeScope genomesize is unchanged since 2026-11-02, with the
--      runs refdb.read_set_runs() gives for that date (every PacBio DNA run up to date + 21 days):
--        OG906  250212  external, no runs (the samplesheet date, as the writer resolves it)
--        OG845  241023  PACB_241018_LA SBL, PACB_241023_AD SBL and SBL2
--        OG781  260421  PACB_250317_AD SBL, PACB_260421_AMD SBL3
--        OG763  251117  no runs until the lab adds its DNA row; then the next push links it, and
--                       until then readiness lists it.
--   The sync owns only undated read sets, so it leaves these alone and stays a no-op.
--   3. The six compatibility views' comments name the tables to write instead, so a writer that
--      fails on one after RG.6 ("cannot update view") finds its way. ref_genomes_assembly_uploads
--      also records 070's change: assembly_accession_hapN shows the ERZ (analysis_accession) or
--      the WGS master (assembly_accession). Owner, 2026-11-02: OcOm_B219's GCA resolver, which
--      updates that view's gca_accession_hapN, is left to its maintainer to fix when it fails.
--
-- Writers. refdb.ensure_read_set() already creates a run-less read set from the samplesheet date
-- when the OG has no PacBio row; nothing changes there.
--
-- Revert: sql/revert/071_v4_read_set_external_and_dates_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_read_set_run') IS NULL THEN
    RAISE EXCEPTION '071 needs v4 read sets (062)';
  END IF;
END
$pre$;

-- 1. External read sets ------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS v4.ref_read_set_external (
  read_set_id bigint PRIMARY KEY REFERENCES v4.ref_read_set (read_set_id) ON DELETE CASCADE,
  cells       text[] NOT NULL CHECK (cardinality(cells) > 0),
  supplier    text,
  note        text,
  loaded_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE v4.ref_read_set_external IS
  'HiFi read sets whose reads are not OceanOmics sequencing, so have no sequencing row (071). Such a '
  'read set has no ref_read_set_run rows; its seq_date is the samplesheet date.';
COMMENT ON COLUMN v4.ref_read_set_external.cells IS 'The read files or cells, as staged in pacbio-sra/{OG}/.';
COMMENT ON COLUMN v4.ref_read_set_external.supplier IS 'Who sequenced them, where known.';

CREATE OR REPLACE FUNCTION v4.ref_read_set_external_exclusive() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  IF TG_TABLE_NAME = 'ref_read_set_run' THEN
    IF EXISTS (SELECT 1 FROM v4.ref_read_set_external x WHERE x.read_set_id = NEW.read_set_id) THEN
      RAISE EXCEPTION 'ref_read_set_run: read set % is external (ref_read_set_external); it has no sequencing rows',
        NEW.read_set_id;
    END IF;
  ELSIF EXISTS (SELECT 1 FROM v4.ref_read_set_run r WHERE r.read_set_id = NEW.read_set_id) THEN
    RAISE EXCEPTION 'ref_read_set_external: read set % has sequencing rows (ref_read_set_run); it is not external',
      NEW.read_set_id;
  END IF;
  RETURN NEW;
END
$fn$;
COMMENT ON FUNCTION v4.ref_read_set_external_exclusive() IS
  'A read set is either external or linked to sequencing rows, not both (071). Outlives RG.6.';

DROP TRIGGER IF EXISTS ref_read_set_run_not_external ON v4.ref_read_set_run;
CREATE TRIGGER ref_read_set_run_not_external BEFORE INSERT OR UPDATE ON v4.ref_read_set_run
  FOR EACH ROW EXECUTE FUNCTION v4.ref_read_set_external_exclusive();
DROP TRIGGER IF EXISTS ref_read_set_external_no_runs ON v4.ref_read_set_external;
CREATE TRIGGER ref_read_set_external_no_runs BEFORE INSERT OR UPDATE ON v4.ref_read_set_external
  FOR EACH ROW EXECUTE FUNCTION v4.ref_read_set_external_exclusive();

GRANT SELECT ON v4.ref_read_set_external TO readonly;

CREATE OR REPLACE VIEW v4.v_read_set_run_readiness AS
SELECT rs.og_id, rs.seq_date, rs.read_set_id,
       (SELECT string_agg(s.sequencing_id, ', ' ORDER BY s.seq_date, s.sequencing_id)
        FROM public.v_sequencing_browse s
        WHERE s.og_id = rs.og_id AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio'
          AND s.status IS DISTINCT FROM 'Failed') AS pacbio_rows_for_og
FROM v4.ref_read_set rs
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_read_set_run r WHERE r.read_set_id = rs.read_set_id)
  AND NOT EXISTS (SELECT 1 FROM v4.ref_read_set_external x WHERE x.read_set_id = rs.read_set_id);
COMMENT ON VIEW v4.v_read_set_run_readiness IS
  'Read sets with no run link that are not external, and the OG''s PacBio DNA rows to choose from. '
  'On 2026-11-02: OG763 (its DNA row is missing from the workbook, 071).';

-- 2. Dates -------------------------------------------------------------------------------------

CREATE TEMP TABLE rs_fix (og_id text PRIMARY KEY, new_seq_date text NOT NULL, sequencing_ids text[] NOT NULL,
                          match_genomesize bigint NOT NULL, external_cells text[]) ON COMMIT DROP;
INSERT INTO rs_fix VALUES
  ('OG906', '250212', '{}', 4007159763,
   ARRAY['SSB_cell1_ccs', 'SSB_cell2_ccs', 'SSB_cell3_ccs', 'SSC_cell1_ccs', 'SSC_cell2_ccs', 'SSC_cell3_ccs']),
  ('OG845', '241023', ARRAY['OG845H_D2_SBL_PACB_241018_LA', 'OG845H_D2_SBL2_PACB_241023_AD',
                            'OG845H_D2_SBL_PACB_241023_AD'], 2759672662, NULL),
  ('OG781', '260421', ARRAY['OG781G_D_SBL_PACB_250317_AD', 'OG781G_D_SBL3_PACB_260421_AMD'], 633246488, NULL),
  ('OG763', '251117', '{}', 912562051, NULL);

DO $rs$
DECLARE
  n bigint;
BEGIN
  WITH hit AS (
    SELECT rs.read_set_id, f.new_seq_date
    FROM rs_fix f
    JOIN v4.ref_read_set rs ON rs.og_id = f.og_id AND rs.seq_date IS NULL
    JOIN v4.ref_genomescope g ON g.read_set_id = rs.read_set_id AND g.genomesize = f.match_genomesize
  )
  UPDATE v4.ref_read_set rs SET seq_date = hit.new_seq_date FROM hit WHERE rs.read_set_id = hit.read_set_id;
  GET DIAGNOSTICS n = ROW_COUNT;

  INSERT INTO v4.ref_read_set_run (read_set_id, sequencing_id)
  SELECT rs.read_set_id, sid
  FROM rs_fix f JOIN v4.ref_read_set rs ON rs.og_id = f.og_id AND rs.seq_date = f.new_seq_date
  CROSS JOIN LATERAL unnest(f.sequencing_ids) AS sid
  ON CONFLICT DO NOTHING;

  INSERT INTO v4.ref_read_set_external (read_set_id, cells, supplier, note)
  SELECT rs.read_set_id, f.external_cells, NULL,
         'Staged in s3:ocom.oceangenomes/pacbio-sra/' || f.og_id || '/ (2024-05); no sequencing row. '
         'Supplier not recorded (071).'
  FROM rs_fix f JOIN v4.ref_read_set rs ON rs.og_id = f.og_id AND rs.seq_date = f.new_seq_date
  WHERE f.external_cells IS NOT NULL
  ON CONFLICT (read_set_id) DO NOTHING;

  IF (SELECT count(*) FROM rs_fix f JOIN v4.ref_read_set rs ON rs.og_id = f.og_id AND rs.seq_date = f.new_seq_date) <> 4
     OR EXISTS (SELECT 1 FROM rs_fix f JOIN v4.ref_read_set rs ON rs.og_id = f.og_id AND rs.seq_date = f.new_seq_date
                WHERE coalesce((SELECT array_agg(r.sequencing_id ORDER BY r.sequencing_id) FROM v4.ref_read_set_run r
                                WHERE r.read_set_id = rs.read_set_id), '{}')
                      IS DISTINCT FROM coalesce((SELECT array_agg(x ORDER BY x) FROM unnest(f.sequencing_ids) x), '{}'))
     OR (SELECT count(*) FROM v4.ref_read_set_external) <> 1 THEN
    RAISE EXCEPTION '071: the four read sets do not all have their new date and runs (a value changed since 2026-11-02?)';
  END IF;
  RAISE NOTICE '071: % read sets dated now; all four have their date and runs, OG906 external', n;
END
$rs$;

-- 3. Where the compatibility views' writes go --------------------------------------------------

COMMENT ON VIEW v4.ref_genomes IS
  'Compatibility view: public.ref_genomes''s 58 columns in its order, one row per part. k_mer_set and '
  'hap2_chr_level_max_len are always NULL. Not a write path: write ref_assembly, ref_assembly_part, '
  'ref_assembly_run and the per-tool tables (ref_busco, ref_gfastats, ref_merqury_qv, ...).';
COMMENT ON VIEW v4.raw_qc IS
  'Compatibility view: public.raw_qc''s columns, one row per OG, from one read set: the undated one if '
  'any (it mirrors a public state no dated read set matches), else the latest dated. Not a write path: '
  'write ref_read_set with ref_genomescope / ref_hifi_adapter_filter (refdb.upsert_read_set).';
COMMENT ON VIEW v4.hifi_reads_qc IS
  'Compatibility view: public.hifi_reads_qc''s columns in its order. Not a write path: write hifi_read_qc.';
COMMENT ON VIEW v4.hic_reads_qc IS
  'Compatibility view: public.hic_reads_qc''s columns in its order, NULL key parts shown as ''''. Not a '
  'write path: write hic_read_qc.';
COMMENT ON VIEW v4.ref_genomes_assembly_uploads IS
  'Compatibility view: public.ref_genomes_assembly_uploads''s columns in its order. assembly_accession_hapN '
  'shows coalesce(analysis_accession, assembly_accession): the ERZ, or the WGS master of older NCBI '
  'submissions (070). Not a write path: write ref_submission, and per haplotype '
  'ref_submission_haplotype (bioproject, analysis_accession, assembly_accession, gca_accession), as '
  'ENA-ref-genomes steps 09 and 10 do. OcOm_B219''s resolve_gca_accessions.py still updates '
  'gca_accession_hapN here and fails after RG.6 until ported (owner, 2026-11-02).';
COMMENT ON VIEW v4.ref_genomes_sra_uploads IS
  'Compatibility view: public.ref_genomes_sra_uploads''s columns in its order, status and date recombined. '
  'Not a write path: write ref_sra_upload and its run links (ref_sra_upload_run, '
  'resolve_sra_upload_runs()), as ENA-ref-genomes step 09 does.';

-- 4. Verify ------------------------------------------------------------------------------------

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v4.sync_ref_read_qc() LOOP
    IF r.changed <> 0 THEN
      RAISE EXCEPTION '071: sync_ref_read_qc is not a no-op after the migration: % (%)', r.step, r.changed;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM v4.check_ref_read_qc() LOOP
    IF r.check_name LIKE 'note:%' THEN
      RAISE NOTICE '071 %: %', r.check_name, r.problems;
    ELSIF r.problems <> 0 THEN
      RAISE EXCEPTION '071 check_ref_read_qc failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM v4.ref_read_set WHERE seq_date IS NULL) THEN
    RAISE EXCEPTION '071: a read set is still undated';
  END IF;
  IF (SELECT array_agg(og_id ORDER BY og_id) FROM v4.v_read_set_run_readiness) IS DISTINCT FROM ARRAY['OG763'] THEN
    RAISE EXCEPTION '071: readiness should list OG763 only';
  END IF;
END
$verify$;

COMMIT;
