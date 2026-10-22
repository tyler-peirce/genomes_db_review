-- 062_v4_ref_read_set.sql -- Phase RG: GenomeScope and HiFiAdapterFilt share one HiFi read set,
-- and a read set records the PacBio sequencing rows it was made from.
--
-- Why. 058 gave ref_genomescope and ref_hifi_adapter_filter each their own og_id and seq_date, and
-- nothing tied either to sequencing. Both tools run at the start of the reference pipeline on the
-- same input reads (the samplesheet's date column), and public.raw_qc has always stored them in one
-- row. Every backfilled row had seq_date NULL, because public never kept it. Owner, 2026-10-20: the
-- read sets must connect to the sequencing they were run on, with dates recovered from the Acacia
-- backups rather than guessed.
--
-- This builds:
--   ref_read_set             one per (og_id, seq_date): a HiFi read set. seq_date NULL = unknown
--   ref_read_set_run         the PacBio sequencing rows in a read set (FK public.sequencing)
--   ref_genomescope          now keyed on read_set_id (FK ref_read_set), no og_id/seq_date
--   ref_hifi_adapter_filter  the same
--   v4.v_read_set_run_readiness   read sets with no run link, and the OG's PacBio rows
-- and replaces v4.raw_qc, v4.coverage_summary (unchanged text), v4.sync_ref_read_qc() and
-- v4.check_ref_read_qc().
--
-- Dates. scripts/acacia_read_set_inventory.py read (rclone lsjson/cat only) the GenomeScope
-- summaries in pawsey0964:oceanomics-refassemblies/{OG}/genomescope/ and the HiFiAdapterFilt .stats
-- in pawsey0964:oceanomics-filtered-reads/{OG}/hifi/. scripts/match_read_sets.py matched them to
-- these rows on 2026-10-20: sql/data/062_read_set_dates.tsv, evidence in sql/data/062_evidence/.
--   - Each backed-up PacBio movie maps to its sequencing row by (OG, barcode) through
--     v4.hifi_read_qc, else by nearest seq_date within 21 days.
--   - One run date among the movies -> that run. Several -> the movies backed up in the same job as
--     the GenomeScope summary that equals this row (genomesize to the bp, or within 0.001% for a
--     re-fit), else the runs up to the assembly version current when that summary was written.
--   - seq_date is the latest seq_date of the read set's sequencing rows. It is not the
--     samplesheet's date (v4.ref_assembly's seq_date), which is sometimes the PacBio movie date and
--     up to ~10 days off: OG16's v240417 is run PACB_240427_LA. The writers map a samplesheet date
--     to a read set with the same rule (refdb.read_set_runs: the OG's PacBio DNA rows up to the
--     date + 21 days; their latest seq_date is the key), so a rerun finds the backfilled read set.
--   - OG61 and OG856 have no backed-up reads; each has one PacBio run date in sequencing.
-- 243 of 248 OGs are dated. Left undated, listed by the readiness view: OG73 and OG845 (no backup,
-- two runs), OG781 (two runs; the only backed-up summary is a later run), OG763 and OG906 (no PacBio
-- row in sequencing; OG906's reads are external SSB/SSC cells).
-- A date is applied only where the row still holds the values it was matched on (genomesize,
-- contam_reads); otherwise it stays undated and a NOTICE says how many.
--
-- Sync (window only, until RG.6). public.raw_qc is one row per OG: the OG's latest pipeline run.
--   - If it equals the OG's latest dated read set (both tools, NULL-safe), that set is its mirror
--     and the OG has no undated read set.
--   - Otherwise one undated read set (seq_date NULL) holds public's values.
--   - An OG no longer in public loses all its read sets, dated ones included: during the window v4
--     mirrors public, and the dates can be re-applied from this file.
-- v4.raw_qc therefore shows, per OG, the undated read set if there is one, else the latest dated
-- one (seq_date DESC NULLS FIRST). RG.6 must date or remove the undated read sets left at the swap,
-- because after it a new dated read set would sort behind them.
--
-- ref_read_set_run. ON DELETE CASCADE from sequencing, as ref_assembly_run: import_v2.py removing a
-- stale sequencing row drops the link. A trigger admits PacBio DNA libraries only.
--
-- Not changed: ref_excluded_rows' raw_qc triage (OG750_PD, OG90_bc2008, OG90ULI, OG760),
-- hifi_read_qc, hic_read_qc, their sync and checks (copied from 058 unchanged).
--
-- Writers. The phase-rg-v4 branches of 01a/0a (OceanOmics-OceanGenomes-ref-genomes,
-- scripts/lib/refdb.py) write the 058 shape; they change in the same step, before RG.6.
--
-- Guards: needs 058's shape or this one; asserts before COMMIT that the sync is a no-op, every
-- check is 0, raw_qc and coverage_summary equal public, and the row counts are unchanged.
--
-- Revert: sql/revert/062_v4_ref_read_set_revert.sql (back to 058's shape, all seq_date NULL).

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_genomescope') IS NULL OR to_regclass('v4.ref_hifi_adapter_filter') IS NULL THEN
    RAISE EXCEPTION '062 needs v4.ref_genomescope and v4.ref_hifi_adapter_filter from 058';
  END IF;
END
$pre$;

-- Views over the old tables go first; both are recreated below.
DROP VIEW IF EXISTS v4.coverage_summary;
DROP VIEW IF EXISTS v4.raw_qc;

-- Move 058's tables aside (only if they still have 058's shape) --------------------------------

DO $aside$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'v4' AND table_name = 'ref_genomescope' AND column_name = 'og_id') THEN
    ALTER TABLE v4.ref_genomescope RENAME TO ref_genomescope_pre062;
    ALTER TABLE v4.ref_genomescope_pre062 RENAME CONSTRAINT ref_genomescope_pkey TO ref_genomescope_pre062_pkey;
    ALTER INDEX v4.ref_genomescope_natural_key RENAME TO ref_genomescope_pre062_natural_key;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'v4' AND table_name = 'ref_hifi_adapter_filter' AND column_name = 'og_id') THEN
    ALTER TABLE v4.ref_hifi_adapter_filter RENAME TO ref_hifi_adapter_filter_pre062;
    ALTER TABLE v4.ref_hifi_adapter_filter_pre062 RENAME CONSTRAINT ref_hifi_adapter_filter_pkey TO ref_hifi_adapter_filter_pre062_pkey;
    ALTER INDEX v4.ref_hifi_adapter_filter_natural_key RENAME TO ref_hifi_adapter_filter_pre062_natural_key;
  END IF;
END
$aside$;

-- Read sets ------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS v4.ref_read_set (
    read_set_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id        text NOT NULL REFERENCES public.sample (og_id),
    seq_date     text CHECK (seq_date ~ '^[0-9]{6}$'),  -- latest seq_date of its runs; NULL = unknown
    loaded_at    timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ref_read_set_natural_key ON v4.ref_read_set (og_id, (coalesce(seq_date, '')));
COMMENT ON TABLE v4.ref_read_set IS
  'A HiFi read set: the PacBio reads one reference-pipeline run took in for an OG (the samplesheet''s '
  'date). seq_date is the latest seq_date of its sequencing rows, not the samplesheet date. NULL = unknown '
  '(before RG, or a public.raw_qc state no dated read set matches). Migration 062.';

CREATE TABLE IF NOT EXISTS v4.ref_read_set_run (
    read_set_id   bigint NOT NULL REFERENCES v4.ref_read_set ON DELETE CASCADE,
    sequencing_id text   NOT NULL REFERENCES public.sequencing (sequencing_id) ON DELETE CASCADE,
    PRIMARY KEY (read_set_id, sequencing_id)
);
CREATE INDEX IF NOT EXISTS ref_read_set_run_sequencing_id_idx ON v4.ref_read_set_run (sequencing_id);
COMMENT ON TABLE v4.ref_read_set_run IS
  'The PacBio sequencing rows in a read set. PacBio DNA libraries only (trigger). Migration 062.';

CREATE OR REPLACE FUNCTION v4.ref_read_set_run_pacbio_only() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  tech  text;
  ltype text;
BEGIN
  SELECT s.technology, s.library_type INTO tech, ltype
  FROM public.v_sequencing_browse s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS NULL OR tech NOT IN ('PacBio HIFI', 'PacBio') OR ltype IS DISTINCT FROM 'pacbio' THEN
    RAISE EXCEPTION 'ref_read_set_run: % is % / % sequencing; a HiFi read set is PacBio DNA',
      NEW.sequencing_id, coalesce(tech, 'unknown'), coalesce(ltype, 'unknown');
  END IF;
  RETURN NEW;
END
$fn$;
DROP TRIGGER IF EXISTS ref_read_set_run_pacbio_only ON v4.ref_read_set_run;
CREATE TRIGGER ref_read_set_run_pacbio_only BEFORE INSERT OR UPDATE ON v4.ref_read_set_run
  FOR EACH ROW EXECUTE FUNCTION v4.ref_read_set_run_pacbio_only();

CREATE TABLE IF NOT EXISTS v4.ref_genomescope (
    read_set_id     bigint PRIMARY KEY REFERENCES v4.ref_read_set ON DELETE CASCADE,
    homozygosity    numeric(5,2),
    heterozygosity  numeric(5,2),
    genomesize      bigint,
    repeatsize      bigint,
    uniquesize      bigint,
    modelfit        numeric(5,2),
    errorrate       numeric(5,2),
    loaded_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_genomescope_has_value CHECK (num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate) > 0)
);
COMMENT ON TABLE v4.ref_genomescope IS
  'GenomeScope2 k-mer profile of a HiFi read set (ref_read_set). Written by '
  '01a_push_genomescope_comp_results_to_sqldb.py (ref repo). A fish whose model failed carries the '
  '1 Gb default genomesize (the writer''s rule).';

CREATE TABLE IF NOT EXISTS v4.ref_hifi_adapter_filter (
    read_set_id   bigint PRIMARY KEY REFERENCES v4.ref_read_set ON DELETE CASCADE,
    contam_reads  integer,
    loaded_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_hifi_adapter_filter_has_value CHECK (num_nonnulls(contam_reads) > 0)
);
COMMENT ON TABLE v4.ref_hifi_adapter_filter IS
  'HiFiAdapterFilt: reads removed as adapter-contaminated, per HiFi read set (ref_read_set). Written by '
  '0a_push_hifiadapt_results_to_sqldb.py (ref repo).';

-- Carry 058's rows across ---------------------------------------------------------------------

DO $carry$
DECLARE
  n_gs bigint;
  n_af bigint;
BEGIN
  IF to_regclass('v4.ref_genomescope_pre062') IS NULL THEN
    RETURN;  -- already carried on an earlier run
  END IF;
  SELECT count(*) INTO n_gs FROM v4.ref_genomescope_pre062;
  SELECT count(*) INTO n_af FROM v4.ref_hifi_adapter_filter_pre062;

  INSERT INTO v4.ref_read_set (og_id, seq_date)
  SELECT og_id, seq_date FROM v4.ref_genomescope_pre062
  UNION
  SELECT og_id, seq_date FROM v4.ref_hifi_adapter_filter_pre062
  ON CONFLICT DO NOTHING;

  INSERT INTO v4.ref_genomescope (read_set_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, loaded_at)
  SELECT rs.read_set_id, o.homozygosity, o.heterozygosity, o.genomesize, o.repeatsize, o.uniquesize, o.modelfit, o.errorrate, o.loaded_at
  FROM v4.ref_genomescope_pre062 o
  JOIN v4.ref_read_set rs ON rs.og_id = o.og_id AND coalesce(rs.seq_date, '') = coalesce(o.seq_date, '');

  INSERT INTO v4.ref_hifi_adapter_filter (read_set_id, contam_reads, loaded_at)
  SELECT rs.read_set_id, o.contam_reads, o.loaded_at
  FROM v4.ref_hifi_adapter_filter_pre062 o
  JOIN v4.ref_read_set rs ON rs.og_id = o.og_id AND coalesce(rs.seq_date, '') = coalesce(o.seq_date, '');

  IF (SELECT count(*) FROM v4.ref_genomescope) <> n_gs OR (SELECT count(*) FROM v4.ref_hifi_adapter_filter) <> n_af THEN
    RAISE EXCEPTION '062: carried % / % rows, expected % / %',
      (SELECT count(*) FROM v4.ref_genomescope), (SELECT count(*) FROM v4.ref_hifi_adapter_filter), n_gs, n_af;
  END IF;
  DROP TABLE v4.ref_genomescope_pre062, v4.ref_hifi_adapter_filter_pre062;
  RAISE NOTICE '062: carried % GenomeScope and % HiFiAdapterFilt rows into % read sets',
    n_gs, n_af, (SELECT count(*) FROM v4.ref_read_set);
END
$carry$;

-- Dates and run links from Acacia (sql/data/062_read_set_dates.tsv, 2026-10-20) ---------------

CREATE TEMP TABLE read_set_dates (
    og_id            text PRIMARY KEY,
    seq_date         text NOT NULL,
    sequencing_ids   text[] NOT NULL,
    match_genomesize bigint,   -- the values the evidence was matched against
    match_contam     integer
) ON COMMIT DROP;
INSERT INTO read_set_dates VALUES
  ('OG1', '230525', ARRAY['OG1G_D_SBL_PACB_230525_AD'], 1118026378, NULL),
  ('OG2', '230413', ARRAY['OG2G_D_SBL_PACB_230413_AD'], 983951412, NULL),
  ('OG3', '230825', ARRAY['OG3G_D_SBL_PACB_230825_AD'], 957342831, NULL),
  ('OG5', '230628', ARRAY['OG5G_D_SBL2_PACB_230628_AD', 'OG5G_D_SBL_PACB_230609_AD'], 3618597434, NULL),
  ('OG6', '230628', ARRAY['OG6G_D_SBL2_PACB_230628_AD'], 1008654320, NULL),
  ('OG7', '230915', ARRAY['OG7G_D2_SBL_PACB_230915_LP'], 1044880125, NULL),
  ('OG8', '230512', ARRAY['OG8G_D_SBL_PACB_230512_AD'], 1050721636, NULL),
  ('OG9', '240206', ARRAY['OG9G_D3_SBL_PACB_240206_AD'], 983187261, NULL),
  ('OG10', '230209', ARRAY['OG10G_D_SBL_PACB_230209_LP'], 948168099, NULL),
  ('OG11', '230825', ARRAY['OG11G_D_SBL_PACB_230825_AD'], 1053758062, NULL),
  ('OG12', '230512', ARRAY['OG12G_D_SBL_PACB_230512_AD'], 974045289, NULL),
  ('OG13', '230209', ARRAY['OG13G_D_SBL_PACB_230209_LP'], 1031699736, NULL),
  ('OG14', '230209', ARRAY['OG14G_D_SBL_PACB_230209_LP'], 1092800854, NULL),
  ('OG15', '230413', ARRAY['OG15G_D_SBL_PACB_230413_AD'], 1122893855, NULL),
  ('OG16', '240427', ARRAY['OG16G_D_SBL_PACB_240427_LA'], 941684468, NULL),
  ('OG27', '230512', ARRAY['OG27B_D_SBL_PACB_230512_AD'], 5423317898, NULL),
  ('OG28', '230811', ARRAY['OG28B_D4_SBL_PACB_230811_AD', 'OG28B_D5_SBL_PACB_230811_AD', 'OG28B_D6_SBL_PACB_230811_AD', 'OG28B_D7_SBL_PACB_230811_AD'], 5498447611, NULL),
  ('OG35', '231027', ARRAY['OG35W_D_SBL_PACB_231027_ADLA'], 604586141, NULL),
  ('OG36', '230724', ARRAY['OG36W_D_SBL_PACB_230724_AD'], 590720667, NULL),
  ('OG37', '240116', ARRAY['OG37G_D_SBL_PACB_240116_LAAD'], 574673514, 0),
  ('OG38', '230609', ARRAY['OG38G_D_SBL_PACB_230609_AD'], 695633824, NULL),
  ('OG39', '241018', ARRAY['OG39H_D_SBL_PACB_241018_LA'], 476615259, 0),
  ('OG40', '241004', ARRAY['OG40H_D2_SBL_PACB_241004_LA'], 656527315, 0),
  ('OG42', '240215', ARRAY['OG42G_D_SBL2_PACB_240215_AD'], 785008184, NULL),
  ('OG46', '240215', ARRAY['OG46G_D_SBL_PACB_240215_AD'], 721535643, NULL),
  ('OG47', '231115', ARRAY['OG47G_D_SBL_PACB_231115_LA'], 637904034, NULL),
  ('OG52', '230825', ARRAY['OG52G_D_SBL_PACB_230825_AD'], 557783573, NULL),
  ('OG53', '230915', ARRAY['OG53G_D2_SBL2_PACB_230915_LP', 'OG53G_D2_SBL_PACB_230915_LP'], 702690937, NULL),
  ('OG54', '241004', ARRAY['OG54G_D_SBL_PACB_241004_LA'], 821024877, 0),
  ('OG55', '231115', ARRAY['OG55G_D_SBL_PACB_231115_LA'], 642687374, 0),
  ('OG56', '240116', ARRAY['OG56G_D_SBL_PACB_240116_LAAD'], 1816305234, 0),
  ('OG57', '231027', ARRAY['OG57G_D_SBL_PACB_231027_ADLA'], 532109732, 0),
  ('OG58', '250704', ARRAY['OG58W_D2_SBL_PACB_250704_AD'], 447389165, 0),
  ('OG60', '241127', ARRAY['OG60M_D_SBL_PACB_241127_AD'], 748749535, NULL),
  ('OG61', '250317', ARRAY['OG61W_D_SBL_PACB_250317_AD'], 497676843, 0),
  ('OG62', '250317', ARRAY['OG62G_D_SBL_PACB_250317_AD'], 342953766, 0),
  ('OG64', '250307', ARRAY['OG64W_D_SBL_PACB_250307_AD'], 428594961, 0),
  ('OG65', '250704', ARRAY['OG65W_D_SBL_PACB_250704_AD'], 568386472, 0),
  ('OG67', '241127', ARRAY['OG67W_D_SBL_PACB_241127_AD'], 594160935, 0),
  ('OG70', '250307', ARRAY['OG70W_D_SBL_PACB_250307_AD'], 759678936, 0),
  ('OG72', '241023', ARRAY['OG72H_D_SBL_PACB_241023_AD'], 473968994, 0),
  ('OG76', '230825', ARRAY['OG76G_D_SBL_PACB_230825_AD'], 426253245, NULL),
  ('OG78', '260626', ARRAY['OG78W_D2_SBL_PACB_260626_AMDTW'], 870504017, 0),
  ('OG79', '240427', ARRAY['OG79G_D_SBL_PACB_240427_LA'], 648809456, 0),
  ('OG81', '250704', ARRAY['OG81W_D_SBL_PACB_250704_AD'], 639699970, 0),
  ('OG85', '240927', ARRAY['OG85H_D_SBL_PACB_240927_LA'], 670080210, 0),
  ('OG88', '230724', ARRAY['OG88G_D_SBL_PACB_230724_AD'], 526581119, NULL),
  ('OG90', '240821', ARRAY['OG90H_D2_SBL2_PACB_240821_AD'], 546685376, 0),
  ('OG95', '230525', ARRAY['OG95H_D_SBL_PACB_230525_AD'], 709563303, NULL),
  ('OG99', '240215', ARRAY['OG99G_D2_SBL_PACB_240215_AD'], 667090715, NULL),
  ('OG100', '240116', ARRAY['OG100W_D2_SBL_PACB_240116_LAAD'], 446688936, 0),
  ('OG101', '240206', ARRAY['OG101H_D_SBL2_PACB_240206_AD'], 463148198, NULL),
  ('OG104', '250113', ARRAY['OG104M_D_SBL2_PACB_241127_AD', 'OG104M_D_SBL_PACB_250113_AD'], 642436646, NULL),
  ('OG105', '231027', ARRAY['OG105H_D_SBL_PACB_231027_ADLA'], 660132539, NULL),
  ('OG106', '240927', ARRAY['OG106G_D2_SBL_PACB_240927_LA'], 460018976, 0),
  ('OG107', '240125', ARRAY['OG107G_D_SBL_PACB_240125_LA'], 495558393, 0),
  ('OG108', '231027', ARRAY['OG108H_D_SBL_PACB_231027_ADLA'], 764100923, NULL),
  ('OG111', '241018', ARRAY['OG111H_D_SBL_PACB_241018_LA'], 697542192, 0),
  ('OG113', '231027', ARRAY['OG113G_D_SBL_PACB_231027_ADLA'], 824061360, 0),
  ('OG114', '240116', ARRAY['OG114H_D_SBL2_PACB_240116_LAAD'], 1555140873, 0),
  ('OG115', '240125', ARRAY['OG115H_D_SBL_PACB_240125_LA'], 558231591, NULL),
  ('OG637', '240206', ARRAY['OG637B_D3_SBL2_PACB_240206_AD', 'OG637B_D3_SBL_PACB_240206_AD'], 3274000304, NULL),
  ('OG645', '240427', ARRAY['OG645H_D_SBL_PACB_240427_LA'], 775063150, NULL),
  ('OG646', '240821', ARRAY['OG646G_D_SBL_PACB_240821_AD'], 1118950839, NULL),
  ('OG647', '240501', ARRAY['OG647H_D_SBL_PACB_240501_AD'], 1296578525, NULL),
  ('OG648', '250704', ARRAY['OG648G_D2_SBL_PACB_250704_AD'], 915430125, 0),
  ('OG649', '240427', ARRAY['OG649H_D2_SBL2_PACB_240427_LA'], 572773833, 0),
  ('OG650', '240327', ARRAY['OG650H_D_SBL_PACB_240327_LA'], 1309712204, NULL),
  ('OG651', '240327', ARRAY['OG651H_D_SBL_PACB_240327_LA'], 1181044347, NULL),
  ('OG652', '240327', ARRAY['OG652H_D_SBL_PACB_240327_LA'], 786985717, 0),
  ('OG654', '240327', ARRAY['OG654H_D_SBL_PACB_240327_LA'], 803382373, NULL),
  ('OG657', '240501', ARRAY['OG657H_D_SBL_PACB_240501_AD'], 1100506307, NULL),
  ('OG658', '240327', ARRAY['OG658H_D_SBL_PACB_240327_LA'], 975891070, 0),
  ('OG659', '240427', ARRAY['OG659H_D_SBL2_PACB_240427_LA'], 733027122, 0),
  ('OG660', '240228', ARRAY['OG660H_D2_SBL2_PACB_240228_AD', 'OG660H_D2_SBL_PACB_240228_AD'], 631937079, NULL),
  ('OG662', '240327', ARRAY['OG662G_D_SBL_PACB_240327_LA'], 554001499, 0),
  ('OG664', '241018', ARRAY['OG664H_D_SBL_PACB_241018_LA'], 937586279, 0),
  ('OG665', '240501', ARRAY['OG665H_D_SBL_PACB_240501_AD'], 1208694604, 0),
  ('OG666', '241004', ARRAY['OG666H_D_SBL_PACB_241004_LA'], 1052171519, 0),
  ('OG672', '240215', ARRAY['OG672H_D2_SBL_PACB_240215_AD'], 1006593532, NULL),
  ('OG673', '240427', ARRAY['OG673H_D_SBL2_PACB_240427_LA'], 1517258036, NULL),
  ('OG675', '250828', ARRAY['OG675G_D2_SBL2_PACB_250828_AD'], 658968388, 0),
  ('OG676', '240327', ARRAY['OG676H_D_SBL_PACB_240327_LA'], 633086596, 0),
  ('OG678', '240327', ARRAY['OG678H_D_SBL_PACB_240327_LA'], 716875895, 0),
  ('OG679', '250307', ARRAY['OG679H_D_SBL_PACB_250307_AD'], 640668596, 0),
  ('OG680', '241004', ARRAY['OG680G_D_SBL_PACB_241004_LA'], 456146256, 0),
  ('OG681', '250307', ARRAY['OG681H_D_SBL_PACB_250307_AD'], 758041015, 0),
  ('OG683', '241023', ARRAY['OG683H_D_SBL2_PACB_241023_AD'], 1128856634, NULL),
  ('OG686', '241004', ARRAY['OG686H_D_SBL_PACB_241004_LA'], 558603285, 0),
  ('OG695', '240520', ARRAY['OG695H_D_SBL3_PACB_240520_LA'], 905330060, NULL),
  ('OG696', '240228', ARRAY['OG696H_D_SBL_PACB_240228_AD'], 1375723817, 0),
  ('OG698', '241004', ARRAY['OG698H_D_SBL_PACB_241004_LA'], 1035214674, NULL),
  ('OG699', '250317', ARRAY['OG699H_D_SBL_PACB_250317_AD'], 1194150809, 0),
  ('OG701', '240427', ARRAY['OG701H_D_SBL2_PACB_240427_LA'], 1004398013, NULL),
  ('OG702', '240501', ARRAY['OG702G_D_SBL_PACB_240501_AD'], 1130871274, 0),
  ('OG704', '240417', ARRAY['OG704H_D_SBL2_PACB_240417_LA'], 223545058, 0),
  ('OG706', '240206', ARRAY['OG706H_D_SBL2_PACB_240206_AD', 'OG706H_D_SBL_PACB_240206_AD'], 4080042520, NULL),
  ('OG709', '240501', ARRAY['OG709G_D_SBL_PACB_240501_AD'], 534152175, NULL),
  ('OG711', '260603', ARRAY['OG711O_D3_SBL_PACB_260603_AMD'], 586533931, NULL),
  ('OG716', '260730', ARRAY['OG716O_D_SBL2_PACB_260730_AMD'], 1284310661, 0),
  ('OG721', '240501', ARRAY['OG721G_D2_SBL_PACB_240501_AD'], 873543429, 0),
  ('OG748', '241018', ARRAY['OG748H_D_SBL_PACB_241018_LA'], 816230411, 0),
  ('OG749', '250331', ARRAY['OG749H_D_SBL_PACB_250331_LA'], 670742894, 0),
  ('OG750', '241004', ARRAY['OG750G_D_SBL_PACB_241004_LA'], 890413754, 0),
  ('OG751', '250317', ARRAY['OG751G_D_SBL_PACB_250317_AD'], 800406022, 0),
  ('OG755', '240821', ARRAY['OG755H_D_SBL_PACB_240821_AD'], 631804687, NULL),
  ('OG756', '250704', ARRAY['OG756G_D_SBL_PACB_250704_AD'], 1110686183, 0),
  ('OG757', '241018', ARRAY['OG757G_D_SBL_PACB_241018_LA'], 629727043, NULL),
  ('OG758', '241127', ARRAY['OG758M_D_SBL_PACB_241127_AD'], 523203132, 0),
  ('OG759', '240520', ARRAY['OG759H_D_SBL_PACB_240520_LA'], 823411099, NULL),
  ('OG762', '241018', ARRAY['OG762H_D_SBL2_PACB_241018_LA'], 608223064, 0),
  ('OG765', '240821', ARRAY['OG765W_D_SBL_PACB_240821_AD'], 1033378066, 0),
  ('OG766', '241004', ARRAY['OG766G_D_SBL_PACB_241004_LA'], 628241596, 0),
  ('OG767', '241004', ARRAY['OG767G_D_SBL_PACB_241004_LA'], 1539424730, 0),
  ('OG769', '250828', ARRAY['OG769G_D_SBL_PACB_250828_AD'], 881803085, 0),
  ('OG770', '241127', ARRAY['OG770M_D_SBL_PACB_241127_AD'], 583286978, 0),
  ('OG775', '241004', ARRAY['OG775G_D_SBL_PACB_241004_LA'], 571343043, 0),
  ('OG777', '240520', ARRAY['OG777G_D_SBL_PACB_240520_LA'], 591670185, NULL),
  ('OG778', '241018', ARRAY['OG778H_D_SBL_PACB_241018_LA'], 704840232, 0),
  ('OG784', '241018', ARRAY['OG784G_D_SBL_PACB_241018_LA'], 626428492, 0),
  ('OG785', '241004', ARRAY['OG785G_D_SBL_PACB_241004_LA'], 855052045, 0),
  ('OG787', '240927', ARRAY['OG787G_D_SBL_PACB_240927_LA'], 614950900, NULL),
  ('OG788', '240927', ARRAY['OG788G_D_SBL_PACB_240927_LA'], 618314688, 0),
  ('OG790', '250704', ARRAY['OG790G_D_SBL_PACB_250704_AD'], 566367073, 0),
  ('OG793', '250317', ARRAY['OG793G_D_SBL_PACB_250317_AD'], 721692668, 0),
  ('OG794', '250307', ARRAY['OG794G_D_SBL_PACB_250307_AD'], 673512243, NULL),
  ('OG799', '241018', ARRAY['OG799H_D2_SBL_PACB_241018_LA'], 725662703, 0),
  ('OG800', '241004', ARRAY['OG800H_D_SBL_PACB_241004_LA'], 679276561, 0),
  ('OG801', '250828', ARRAY['OG801L_D_SBL_PACB_250828_AD'], 796071130, 0),
  ('OG803', '240927', ARRAY['OG803G_D_SBL_PACB_240927_LA'], 751310397, 0),
  ('OG804', '260522', ARRAY['OG804G_D_SBL2_PACB_260522_AMD'], 909916039, 0),
  ('OG808', '240520', ARRAY['OG808H_D_SBL_PACB_240520_LA'], 1092298780, 0),
  ('OG810', '241004', ARRAY['OG810G_D_SBL_PACB_241004_LA'], 718891915, NULL),
  ('OG811', '241004', ARRAY['OG811G_D_SBL_PACB_241004_LA'], 658428033, 0),
  ('OG813', '250704', ARRAY['OG813G_D_SBL_PACB_250704_AD'], 938638192, 0),
  ('OG819', '250704', ARRAY['OG819H_D_SBL_PACB_250704_AD'], 586805045, 0),
  ('OG820', '240501', ARRAY['OG820G_D_SBL_PACB_240501_AD'], 839879667, 0),
  ('OG824', '241004', ARRAY['OG824H_D_SBL_PACB_241004_LA'], 827050724, 0),
  ('OG829', '240927', ARRAY['OG829H_D2_SBL_PACB_240927_LA'], 678844369, 0),
  ('OG834', '240927', ARRAY['OG834H_D2_SBL_PACB_240927_LA'], 1136083427, 0),
  ('OG836', '240520', ARRAY['OG836B_D_SBL_PACB_240520_LA'], 2787911839, 0),
  ('OG837', '240813', ARRAY['OG837B_D3_SBL_PACB_240813_AD'], 3515375553, 0),
  ('OG838', '240813', ARRAY['OG838B2_D_SBL_PACB_240813_AD', 'OG838B_D_SBL_PACB_240520_LA'], 2240927288, 0),
  ('OG844', '260511', ARRAY['OG844H_D5_SBL_PACB_260511_AMD'], 2766354953, 0),
  ('OG847', '260626', ARRAY['OG847M_D2_SBL_PACB_260626_AMDTW'], 522571028, 0),
  ('OG848', '250113', ARRAY['OG848U_D_SBL2_PACB_241127_AD', 'OG848U_D_SBL_PACB_250113_AD'], 790821299, NULL),
  ('OG849', '241127', ARRAY['OG849U_D_SBL_PACB_241127_AD'], 525039910, 0),
  ('OG852', '250704', ARRAY['OG852O_D_SBL_PACB_250704_AD'], 321593136, 0),
  ('OG853', '250704', ARRAY['OG853O_D_SBL_PACB_250704_AD'], 398638208, 0),
  ('OG855', '240821', ARRAY['OG855H_D_SBL_PACB_240821_AD'], 651631565, 0),
  ('OG856', '240821', ARRAY['OG856H_D_SBL_PACB_240821_AD'], 662303726, 0),
  ('OG859', '241023', ARRAY['OG859B_D2_SBL_PACB_241023_AD', 'OG859B_D_SBL_PACB_241023_AD'], 2465450130, NULL),
  ('OG860', '240927', ARRAY['OG860H_D_SBL_PACB_240927_LA'], 489664320, NULL),
  ('OG863', '241004', ARRAY['OG863G_D_SBL_PACB_241004_LA'], 1055370755, 0),
  ('OG865', '250818', ARRAY['OG865G_D_SBL2_PACB_250818_AD'], 645484586, 0),
  ('OG866', '241023', ARRAY['OG866G_D_SBL_PACB_241023_AD'], 666787149, 0),
  ('OG868', '250317', ARRAY['OG868M_D_SBL_PACB_250317_AD'], 91120189, 0),
  ('OG869', '250818', ARRAY['OG869M_D_SBL3_PACB_250818_AD'], 639296573, 0),
  ('OG907', '250828', ARRAY['OG907H_D_SBL_PACB_250828_AD'], 773855290, 0),
  ('OG910', '241127', ARRAY['OG910H_D_SBL_PACB_241127_AD'], 829385747, 0),
  ('OG1161', '250113', ARRAY['OG1161B_D4_SBL_PACB_250113_AD', 'OG1161B_D5_SBL_PACB_250113_AD'], 2398484228, 0),
  ('OG1297', '250818', ARRAY['OG1297B_D_SBL_PACB_250818_AD'], 2715639206, 0),
  ('OG1326', '260730', ARRAY['OG1326H_D2_SBL_PACB_260730_AMD'], 793180269, 0),
  ('OG1369', '260227', ARRAY['OG1369H_D_SBL_PACB_260227_AMD'], 528263522, 0),
  ('OG1422', '260227', ARRAY['OG1422H_D_SBL_PACB_260227_AMD'], 522959581, 0),
  ('OG1454', '260227', ARRAY['OG1454H_D_SBL_PACB_260227_AMD'], 928433338, 0),
  ('OG1455', '260331', ARRAY['OG1455H_D_SBL_PACB_260331_AMDLA'], 545148406, 0),
  ('OG1560', '260408', ARRAY['OG1560G_D_SBL_PACB_260408_AMD'], 638852790, 0),
  ('OG1573', '260626', ARRAY['OG1573M_D_SBL_PACB_260626_AMDTW'], 209372408, 0),
  ('OG1613', '260603', ARRAY['OG1613M_D_SBL_PACB_260603_AMD'], 843764526, 0),
  ('OG1639', '260626', ARRAY['OG1639G_D_SBL_PACB_260626_AMDTW'], 790211967, 0),
  ('OG1650', '260331', ARRAY['OG1650H_D_SBL_PACB_260331_AMDLA'], 817177052, NULL),
  ('OG1651', '260522', ARRAY['OG1651G_D2_SBL_PACB_260522_AMD'], 682277482, NULL),
  ('OG1663', '260603', ARRAY['OG1663G_D_SBL_PACB_260603_AMD'], 814991186, 0),
  ('OG1678', '260603', ARRAY['OG1678G_D2_SBL_PACB_260603_AMD'], 580850900, NULL),
  ('OG1699', '260421', ARRAY['OG1699G_D_SBL_PACB_260421_AMD'], 258488465, 0),
  ('OG1701', '260428', ARRAY['OG1701G_D_SBL_PACB_260428_AMD'], 646335281, NULL),
  ('OG2088', '260414', ARRAY['OG2088G_D_SBL_PACB_260414_AMD'], 1083646822, 0),
  ('OG2089', '260227', ARRAY['OG2089G_D_SBL_PACB_260227_AMD'], 1691041945, 0),
  ('OG2090', '260303', ARRAY['OG2090E_D_SBL_PACB_260303_AD'], 1107233930, 0),
  ('OG2092', '260626', ARRAY['OG2092E_D_SBL_PACB_260626_AMDTW'], 520040978, 0),
  ('OG2093', '260227', ARRAY['OG2093E_D_SBL_PACB_260227_AMD'], 1025980474, 0),
  ('OG2098', '260511', ARRAY['OG2098M_D_SBL_PACB_260511_AMD'], 1483469419, NULL),
  ('OG2099', '260603', ARRAY['OG2099M_D_SBL_PACB_260603_AMD'], 1015605281, NULL),
  ('OG2100', '260227', ARRAY['OG2100G_D_SBL_PACB_260227_AMD'], 606293092, 0),
  ('OG2102', '260227', ARRAY['OG2102G_D_SBL_PACB_260227_AMD'], 213712163, 0),
  ('OG2104', '260414', ARRAY['OG2104E_D_SBL_PACB_260414_AMD'], 510567224, 0),
  ('OG2105', '260421', ARRAY['OG2105G_D_SBL2_PACB_260421_AMD', 'OG2105G_D_SBL_PACB_260421_AMD'], 4503833832, 0),
  ('OG2109', '260626', ARRAY['OG2109M_D_SBL_PACB_260626_AMDTW'], 1857355671, 0),
  ('OG2112', '260603', ARRAY['OG2112M_D_SBL_PACB_260603_AMD'], 1314750346, NULL),
  ('OG2113', '260522', ARRAY['OG2113M_D_SBL_PACB_260522_AMD'], 628118513, NULL),
  ('OG2116', '260603', ARRAY['OG2116M_D_SBL_PACB_260603_AMD'], 596305762, NULL),
  ('OG2118', '260626', ARRAY['OG2118E_D_SBL_PACB_260626_AMDTW'], 1489680179, 0),
  ('OG2119', '260408', ARRAY['OG2119E_D_SBL_PACB_260408_AMD'], 1537696985, 0),
  ('OG2121', '260511', ARRAY['OG2121E_D_SBL_PACB_260511_AMD'], 781508477, NULL),
  ('OG2122', '260511', ARRAY['OG2122E_D_SBL_PACB_260511_AMD'], 1115352176, NULL),
  ('OG2124', '260421', ARRAY['OG2124G_D_SBL_PACB_260421_AMD'], 1227970323, 0),
  ('OG2126', '260730', ARRAY['OG2126E_D_SBL_PACB_260730_AMD'], 1379767869, 0),
  ('OG2127', '260603', ARRAY['OG2127E_D_SBL_PACB_260603_AMD'], 850213129, 0),
  ('OG2128', '260603', ARRAY['OG2128E_D_SBL_PACB_260603_AMD'], 1407718659, NULL),
  ('OG2130', '260428', ARRAY['OG2130G_D_SBL_PACB_260428_AMD'], 1468216819, NULL),
  ('OG2131', '260511', ARRAY['OG2131E_D_SBL_PACB_260511_AMD'], 769262316, NULL),
  ('OG2132', '260408', ARRAY['OG2132E_D_SBL_PACB_260408_AMD'], 735989317, 0),
  ('OG2133', '260522', ARRAY['OG2133E_D_SBL_PACB_260522_AMD'], 986420575, NULL),
  ('OG2134', '260511', ARRAY['OG2134E_D_SBL_PACB_260511_AMD'], 552343236, NULL),
  ('OG2135', '260730', ARRAY['OG2135E_D_SBL_PACB_260730_AMD'], 596337638, 0),
  ('OG2136', '260730', ARRAY['OG2136E_D_SBL_PACB_260730_AMD'], 7788192910, 0),
  ('OG2138', '260626', ARRAY['OG2138E_D_SBL_PACB_260626_AMDTW'], 507665276, 0),
  ('OG2142', '260603', ARRAY['OG2142G_D_SBL_PACB_260603_AMD'], 1129831250, NULL),
  ('OG2143', '260421', ARRAY['OG2143E_D_SBL_PACB_260421_AMD'], 2720719294, 0),
  ('OG2145', '260730', ARRAY['OG2145G_D_SBL_PACB_260730_AMD'], 1386835163, 0),
  ('OG2146', '260414', ARRAY['OG2146H_D_SBL_PACB_260414_AMD'], 1027219217, 0),
  ('OG2151', '260421', ARRAY['OG2151H_D_SBL_PACB_260421_AMD'], 371240349, 0),
  ('OG2156', '260408', ARRAY['OG2156H_D_SBL_PACB_260408_AMD'], 696949954, 0),
  ('OG2159', '260408', ARRAY['OG2159H_D_SBL_PACB_260408_AMD'], 768842548, NULL),
  ('OG2161', '260331', ARRAY['OG2161H_D_SBL_PACB_260331_AMDLA'], 1053102650, NULL),
  ('OG2163', '260603', ARRAY['OG2163H_D_SBL_PACB_260603_AMD'], 986165625, NULL),
  ('OG2164', '260331', ARRAY['OG2164H_D_SBL_PACB_260331_AMDLA'], 727737529, NULL),
  ('OG2165', '260428', ARRAY['OG2165H_D_SBL_PACB_260428_AMD'], 543386501, NULL),
  ('OG2166', '260331', ARRAY['OG2166H_D_SBL_PACB_260331_AMDLA'], 724912746, NULL),
  ('OG2177', '260603', ARRAY['OG2177H_D_SBL_PACB_260603_AMD'], 1387858421, NULL),
  ('OG2178', '260408', ARRAY['OG2178H_D_SBL_PACB_260408_AMD'], 611495665, NULL),
  ('OG2179', '260428', ARRAY['OG2179M_D_SBL_PACB_260428_AMD'], 1451793875, NULL),
  ('OG2182', '260331', ARRAY['OG2182H_D2_SBL_PACB_260331_AMDLA'], 719348691, NULL),
  ('OG2188', '260408', ARRAY['OG2188H_D_SBL_PACB_260408_AMD'], 993000562, NULL),
  ('OG2189', '260414', ARRAY['OG2189H_D_SBL_PACB_260414_AMD'], 749201194, 0),
  ('OG2200', '260603', ARRAY['OG2200H_D_SBL_PACB_260603_AMD'], 821804092, NULL),
  ('OG2202', '260331', ARRAY['OG2202H_D_SBL_PACB_260331_AMDLA'], 474606108, NULL),
  ('OG2203', '260408', ARRAY['OG2203H_D_SBL_PACB_260408_AMD'], 682313069, NULL),
  ('OG2205', '260522', ARRAY['OG2205H_D_SBL_PACB_260522_AMD'], 537163736, NULL),
  ('OG2209', '260626', ARRAY['OG2209H_D_SBL_PACB_260626_AMDTW'], 510650437, 0),
  ('OG2218', '260428', ARRAY['OG2218H_D_SBL_PACB_260428_AMD'], 1052595157, NULL),
  ('OG2220', '260421', ARRAY['OG2220H_D_SBL_PACB_260421_AMD'], 832499981, 0),
  ('OG2227', '260414', ARRAY['OG2227H_D2_SBL_PACB_260414_AMD'], 832708979, NULL),
  ('OG2237', '260414', ARRAY['OG2237H_D_SBL_PACB_260414_AMD'], 534470456, NULL),
  ('OG2241', '260414', ARRAY['OG2241H_D2_SBL_PACB_260414_AMD'], 820701423, NULL),
  ('OG2242', '260414', ARRAY['OG2242H_D_SBL_PACB_260414_AMD'], 1035238583, NULL),
  ('OG2266', '260511', ARRAY['OG2266H_D_SBL_PACB_260511_AMD'], 700981937, NULL),
  ('OG2268', '260428', ARRAY['OG2268H_D2_SBL_PACB_260428_AMD'], 1152957063, NULL),
  ('OG2269', '260428', ARRAY['OG2269G_D_SBL_PACB_260428_AMD'], 664860409, NULL),
  ('OG2317', '260303', ARRAY['OG2317B_D_SBL2_PACB_260303_AD', 'OG2317B_D_SBL_PACB_260303_AD'], 2856847467, 0),
  ('OG2320', '260303', ARRAY['OG2320B_D2_SBL_PACB_260303_AD'], 529537079, 0),
  ('OG2325', '260428', ARRAY['OG2325H_D2_SBL_PACB_260428_AMD'], 742845009, NULL);

DO $dates$
DECLARE
  n_dated   bigint;
  n_skipped bigint;
  n_links   bigint;
  n_missing bigint;
BEGIN
  WITH ok AS (
    SELECT d.og_id, d.seq_date, rs.read_set_id
    FROM read_set_dates d
    JOIN v4.ref_read_set rs ON rs.og_id = d.og_id AND rs.seq_date IS NULL
    LEFT JOIN v4.ref_genomescope g ON g.read_set_id = rs.read_set_id
    LEFT JOIN v4.ref_hifi_adapter_filter f ON f.read_set_id = rs.read_set_id
    WHERE g.genomesize IS NOT DISTINCT FROM d.match_genomesize
      AND f.contam_reads IS NOT DISTINCT FROM d.match_contam
  )
  UPDATE v4.ref_read_set rs SET seq_date = ok.seq_date
  FROM ok WHERE rs.read_set_id = ok.read_set_id;
  GET DIAGNOSTICS n_dated = ROW_COUNT;

  SELECT count(*) INTO n_skipped FROM read_set_dates d
  WHERE NOT EXISTS (SELECT 1 FROM v4.ref_read_set rs WHERE rs.og_id = d.og_id AND rs.seq_date = d.seq_date);

  INSERT INTO v4.ref_read_set_run (read_set_id, sequencing_id)
  SELECT rs.read_set_id, sid
  FROM read_set_dates d
  JOIN v4.ref_read_set rs ON rs.og_id = d.og_id AND rs.seq_date = d.seq_date
  CROSS JOIN LATERAL unnest(d.sequencing_ids) AS sid
  WHERE EXISTS (SELECT 1 FROM public.sequencing s WHERE s.sequencing_id = sid)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n_links = ROW_COUNT;

  SELECT count(*) INTO n_missing
  FROM read_set_dates d CROSS JOIN LATERAL unnest(d.sequencing_ids) AS sid
  WHERE NOT EXISTS (SELECT 1 FROM public.sequencing s WHERE s.sequencing_id = sid);

  RAISE NOTICE '062: dated % read sets with % run links; % dates not applied (values changed since '
    '2026-10-20, or already dated); % sequencing rows no longer in sequencing',
    n_dated, n_links, n_skipped, n_missing;
END
$dates$;

-- Views ---------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW v4.raw_qc AS
WITH pick AS (
  SELECT DISTINCT ON (rs.og_id) rs.og_id, rs.read_set_id
  FROM v4.ref_read_set rs
  WHERE EXISTS (SELECT 1 FROM v4.ref_genomescope g WHERE g.read_set_id = rs.read_set_id)
     OR EXISTS (SELECT 1 FROM v4.ref_hifi_adapter_filter f WHERE f.read_set_id = rs.read_set_id)
  ORDER BY rs.og_id, rs.seq_date DESC NULLS FIRST
)
SELECT p.og_id,
       g.homozygosity, g.heterozygosity, g.genomesize, g.repeatsize, g.uniquesize, g.modelfit, g.errorrate,
       f.contam_reads
FROM pick p
LEFT JOIN v4.ref_genomescope g ON g.read_set_id = p.read_set_id
LEFT JOIN v4.ref_hifi_adapter_filter f ON f.read_set_id = p.read_set_id;
COMMENT ON VIEW v4.raw_qc IS
  'Compatibility view: public.raw_qc''s columns, one row per OG, from one read set: the undated one '
  'if any (it mirrors a public state no dated read set matches), else the latest dated. Not a write path.';

CREATE OR REPLACE VIEW v4.coverage_summary AS
WITH hifi_agg AS (
         SELECT hifi_reads_qc.og_id,
            sum(hifi_reads_qc.hifi_yield) AS total_hifi_yield_bp
           FROM v4.hifi_reads_qc hifi_reads_qc
          GROUP BY hifi_reads_qc.og_id
        ), hic_agg AS (
         SELECT hic_reads_qc.og_id,
            sum(hic_reads_qc.yield_gb * 1000000000::numeric)::bigint AS total_hic_yield_bp
           FROM v4.hic_reads_qc hic_reads_qc
          GROUP BY hic_reads_qc.og_id
        ), all_ogs AS (
         SELECT hifi_agg.og_id
           FROM hifi_agg
        UNION
         SELECT hic_agg.og_id
           FROM hic_agg
        )
 SELECT a.og_id,
    r.genomesize,
    round(hic.total_hic_yield_bp::numeric / '1000000000'::numeric, 3) AS total_hic_yield_gb,
    round(hifi.total_hifi_yield_bp / '1000000000'::numeric, 3) AS total_hifi_yield_gb,
        CASE
            WHEN r.genomesize > 0 THEN round(hifi.total_hifi_yield_bp / r.genomesize::numeric, 2)
            ELSE NULL::numeric
        END AS hifi_coverage,
        CASE
            WHEN r.genomesize > 0 THEN round(hic.total_hic_yield_bp::numeric / r.genomesize::numeric, 2)
            ELSE NULL::numeric
        END AS hic_coverage
   FROM all_ogs a
     LEFT JOIN hifi_agg hifi ON hifi.og_id = a.og_id
     LEFT JOIN hic_agg hic ON hic.og_id = a.og_id
     LEFT JOIN v4.raw_qc r ON r.og_id = a.og_id
  ORDER BY a.og_id;
COMMENT ON VIEW v4.coverage_summary IS
  'public.coverage_summary on the v4 compatibility views. For the RG.5 reader test; replaces the '
  'public view at RG.6.';

CREATE OR REPLACE VIEW v4.v_read_set_run_readiness AS
SELECT rs.og_id, rs.seq_date, rs.read_set_id,
       (SELECT string_agg(s.sequencing_id, ', ' ORDER BY s.seq_date, s.sequencing_id)
        FROM public.v_sequencing_browse s
        WHERE s.og_id = rs.og_id AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio') AS pacbio_rows_for_og
FROM v4.ref_read_set rs
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_read_set_run r WHERE r.read_set_id = rs.read_set_id);
COMMENT ON VIEW v4.v_read_set_run_readiness IS
  'Read sets with no run link, and the OG''s PacBio DNA rows to choose from. On 2026-10-20: OG73, '
  'OG763, OG781, OG845, OG906 (062''s header says why).';

-- Sync (window-only: dropped at RG.6) --------------------------------------------------------

CREATE OR REPLACE VIEW v4.sync_read_set_source AS
SELECT s.og_id, s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate,
       s.contam_reads,
       num_nonnulls(s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate) > 0 AS has_gs,
       s.contam_reads IS NOT NULL AS has_af,
       coalesce((
         SELECT (g.homozygosity, g.heterozygosity, g.genomesize, g.repeatsize, g.uniquesize, g.modelfit, g.errorrate)
                  IS NOT DISTINCT FROM (s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate)
                AND f.contam_reads IS NOT DISTINCT FROM s.contam_reads
         FROM (SELECT r.read_set_id FROM v4.ref_read_set r
               WHERE r.og_id = s.og_id AND r.seq_date IS NOT NULL
               ORDER BY r.seq_date DESC LIMIT 1) d
         LEFT JOIN v4.ref_genomescope g ON g.read_set_id = d.read_set_id
         LEFT JOIN v4.ref_hifi_adapter_filter f ON f.read_set_id = d.read_set_id), false) AS matches_dated
FROM v4.sync_raw_qc_source s
WHERE s.key_problem IS NULL
  AND num_nonnulls(s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate, s.contam_reads) > 0;
COMMENT ON VIEW v4.sync_read_set_source IS
  'Phase RG window only: public.raw_qc as the sync reads it, and whether it equals the OG''s latest '
  'dated read set. Dropped at RG.6.';

CREATE OR REPLACE FUNCTION v4.sync_ref_read_qc() RETURNS TABLE (step text, changed bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp SET client_min_messages = warning AS $fn$
DECLARE
  n bigint;
BEGIN
  -- Read sets (062): an OG gone from public loses its read sets; an undated read set exists only
  -- while public differs from the OG's latest dated one.
  DELETE FROM v4.ref_read_set rs
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_read_set_source s WHERE s.og_id = rs.og_id)
     OR (rs.seq_date IS NULL AND EXISTS (SELECT 1 FROM v4.sync_read_set_source s WHERE s.og_id = rs.og_id AND s.matches_dated));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_read_set deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_read_set (og_id, seq_date)
  SELECT s.og_id, NULL FROM v4.sync_read_set_source s WHERE NOT s.matches_dated
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_read_set inserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_genomescope g
  USING v4.ref_read_set rs, v4.sync_read_set_source s
  WHERE g.read_set_id = rs.read_set_id AND rs.seq_date IS NULL AND s.og_id = rs.og_id AND NOT s.has_gs;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_genomescope deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_genomescope AS t (read_set_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate)
  SELECT rs.read_set_id, s.homozygosity, s.heterozygosity, s.genomesize, s.repeatsize, s.uniquesize, s.modelfit, s.errorrate
  FROM v4.sync_read_set_source s JOIN v4.ref_read_set rs ON rs.og_id = s.og_id AND rs.seq_date IS NULL
  WHERE s.has_gs AND NOT s.matches_dated
  ON CONFLICT (read_set_id) DO UPDATE SET homozygosity = EXCLUDED.homozygosity, heterozygosity = EXCLUDED.heterozygosity, genomesize = EXCLUDED.genomesize, repeatsize = EXCLUDED.repeatsize, uniquesize = EXCLUDED.uniquesize, modelfit = EXCLUDED.modelfit, errorrate = EXCLUDED.errorrate, loaded_at = now()
    WHERE (t.homozygosity, t.heterozygosity, t.genomesize, t.repeatsize, t.uniquesize, t.modelfit, t.errorrate) IS DISTINCT FROM (EXCLUDED.homozygosity, EXCLUDED.heterozygosity, EXCLUDED.genomesize, EXCLUDED.repeatsize, EXCLUDED.uniquesize, EXCLUDED.modelfit, EXCLUDED.errorrate);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_genomescope upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_hifi_adapter_filter f
  USING v4.ref_read_set rs, v4.sync_read_set_source s
  WHERE f.read_set_id = rs.read_set_id AND rs.seq_date IS NULL AND s.og_id = rs.og_id AND NOT s.has_af;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_hifi_adapter_filter deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_hifi_adapter_filter AS t (read_set_id, contam_reads)
  SELECT rs.read_set_id, s.contam_reads
  FROM v4.sync_read_set_source s JOIN v4.ref_read_set rs ON rs.og_id = s.og_id AND rs.seq_date IS NULL
  WHERE s.has_af AND NOT s.matches_dated
  ON CONFLICT (read_set_id) DO UPDATE SET contam_reads = EXCLUDED.contam_reads, loaded_at = now()
    WHERE t.contam_reads IS DISTINCT FROM EXCLUDED.contam_reads;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_hifi_adapter_filter upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.hifi_read_qc t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_read_qc_hifi_source s
                    WHERE s.key_problem IS NULL AND (s.og_id, s.tissue, s.ext_type, s.lib_code, s.run_id) = (t.og_id, t.tissue, t.ext_type, t.lib_code, t.run_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hifi_read_qc deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.hifi_read_qc AS t (og_id, tissue, ext_type, lib_code, run_id, sequencing_id, barcode, barcode_quality, hifi_reads, hifi_read_length, hifi_read_quality, hifi_yield, polymerase_read_length)
  SELECT s.og_id, s.tissue, s.ext_type, s.lib_code, s.run_id, s.resolved_sequencing_id, s.barcode, s.barcode_quality, s.hifi_reads, s.hifi_read_length, s.hifi_read_quality, s.hifi_yield, s.polymerase_read_length
  FROM v4.sync_read_qc_hifi_source s WHERE s.key_problem IS NULL
  ON CONFLICT (og_id, tissue, ext_type, lib_code, run_id) DO UPDATE SET sequencing_id = EXCLUDED.sequencing_id, barcode = EXCLUDED.barcode, barcode_quality = EXCLUDED.barcode_quality, hifi_reads = EXCLUDED.hifi_reads, hifi_read_length = EXCLUDED.hifi_read_length, hifi_read_quality = EXCLUDED.hifi_read_quality, hifi_yield = EXCLUDED.hifi_yield, polymerase_read_length = EXCLUDED.polymerase_read_length, loaded_at = now()
    WHERE (t.sequencing_id, t.barcode, t.barcode_quality, t.hifi_reads, t.hifi_read_length, t.hifi_read_quality, t.hifi_yield, t.polymerase_read_length) IS DISTINCT FROM (EXCLUDED.sequencing_id, EXCLUDED.barcode, EXCLUDED.barcode_quality, EXCLUDED.hifi_reads, EXCLUDED.hifi_read_length, EXCLUDED.hifi_read_quality, EXCLUDED.hifi_yield, EXCLUDED.polymerase_read_length);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hifi_read_qc upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.hic_read_qc t
  WHERE NOT EXISTS (SELECT 1 FROM v4.sync_read_qc_hic_source s
                    WHERE s.key_problem IS NULL AND s.og_id = t.og_id AND s.run_id = t.run_id
                      AND s.tissue IS NOT DISTINCT FROM t.tissue AND s.ext_type IS NOT DISTINCT FROM t.ext_type AND s.lib_code IS NOT DISTINCT FROM t.lib_code AND s.lane IS NOT DISTINCT FROM t.lane);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hic_read_qc deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.hic_read_qc AS t (og_id, tissue, ext_type, lib_code, lane, run_id, sequencing_id, datecreated, isarchived, isfiledeleted, totalreadspf, totalclusterspf, read1length, read2length, ispairedend, yield_gb, totalsize_gb)
  SELECT s.og_id, s.tissue, s.ext_type, s.lib_code, s.lane, s.run_id, s.resolved_sequencing_id, s.datecreated, s.isarchived, s.isfiledeleted, s.totalreadspf, s.totalclusterspf, s.read1length, s.read2length, s.ispairedend, s.yield_gb, s.totalsize_gb
  FROM v4.sync_read_qc_hic_source s WHERE s.key_problem IS NULL
  ON CONFLICT (og_id, (coalesce(tissue, '')), (coalesce(ext_type, '')), (coalesce(lib_code, '')), (coalesce(lane, '')), run_id) DO UPDATE SET sequencing_id = EXCLUDED.sequencing_id, datecreated = EXCLUDED.datecreated, isarchived = EXCLUDED.isarchived, isfiledeleted = EXCLUDED.isfiledeleted, totalreadspf = EXCLUDED.totalreadspf, totalclusterspf = EXCLUDED.totalclusterspf, read1length = EXCLUDED.read1length, read2length = EXCLUDED.read2length, ispairedend = EXCLUDED.ispairedend, yield_gb = EXCLUDED.yield_gb, totalsize_gb = EXCLUDED.totalsize_gb, loaded_at = now()
    WHERE (t.sequencing_id, t.datecreated, t.isarchived, t.isfiledeleted, t.totalreadspf, t.totalclusterspf, t.read1length, t.read2length, t.ispairedend, t.yield_gb, t.totalsize_gb) IS DISTINCT FROM (EXCLUDED.sequencing_id, EXCLUDED.datecreated, EXCLUDED.isarchived, EXCLUDED.isfiledeleted, EXCLUDED.totalreadspf, EXCLUDED.totalclusterspf, EXCLUDED.read1length, EXCLUDED.read2length, EXCLUDED.ispairedend, EXCLUDED.yield_gb, EXCLUDED.totalsize_gb);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'hic_read_qc upserted'; changed := n; RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v4.sync_ref_read_qc() IS
  'Phase RG window only: copy public.raw_qc (into read sets, 062), hifi_reads_qc and hic_reads_qc into '
  'v4. Skips rows with a key_problem (check_ref_read_qc then fails). Dropped at RG.6.';

CREATE OR REPLACE FUNCTION v4.check_ref_read_qc() RETURNS TABLE (check_name text, problems bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  check_name := 'raw_qc: differs from public (after triage, either way)';
  SELECT (SELECT count(*) FROM (SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.raw_qc
                                EXCEPT ALL SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.sync_raw_qc_source
                                           WHERE key_problem IS NULL AND num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads) > 0) x)
       + (SELECT count(*) FROM (SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.sync_raw_qc_source
                                WHERE key_problem IS NULL AND num_nonnulls(homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads) > 0
                                EXCEPT ALL SELECT og_id, homozygosity, heterozygosity, genomesize, repeatsize, uniquesize, modelfit, errorrate, contam_reads FROM v4.raw_qc) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'hifi_reads_qc: differs from public (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v4.hifi_reads_qc EXCEPT ALL SELECT * FROM public.hifi_reads_qc) x)
       + (SELECT count(*) FROM (SELECT * FROM public.hifi_reads_qc EXCEPT ALL SELECT * FROM v4.hifi_reads_qc) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'hic_reads_qc: differs from public (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v4.hic_reads_qc EXCEPT ALL SELECT * FROM public.hic_reads_qc) x)
       + (SELECT count(*) FROM (SELECT * FROM public.hic_reads_qc EXCEPT ALL SELECT * FROM v4.hic_reads_qc) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'coverage_summary: differs from public (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v4.coverage_summary EXCEPT ALL SELECT * FROM public.coverage_summary) x)
       + (SELECT count(*) FROM (SELECT * FROM public.coverage_summary EXCEPT ALL SELECT * FROM v4.coverage_summary) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'read QC: public rows with an untriaged key problem';
  SELECT (SELECT count(*) FROM v4.sync_raw_qc_source WHERE key_problem IS NOT NULL)
       + (SELECT count(*) FROM v4.sync_read_qc_hifi_source WHERE key_problem IS NOT NULL)
       + (SELECT count(*) FROM v4.sync_read_qc_hic_source WHERE key_problem IS NOT NULL)
    INTO problems;
  RETURN NEXT;

  check_name := 'read sets with no QC row';
  SELECT count(*) INTO problems FROM v4.ref_read_set rs
  WHERE NOT EXISTS (SELECT 1 FROM v4.ref_genomescope g WHERE g.read_set_id = rs.read_set_id)
    AND NOT EXISTS (SELECT 1 FROM v4.ref_hifi_adapter_filter f WHERE f.read_set_id = rs.read_set_id);
  RETURN NEXT;

  check_name := 'note: read sets with no sequencing link';
  SELECT count(*) INTO problems FROM v4.v_read_set_run_readiness;
  RETURN NEXT;

  check_name := 'note: undated read sets';
  SELECT count(*) INTO problems FROM v4.ref_read_set WHERE seq_date IS NULL;
  RETURN NEXT;

  check_name := 'note: hifi_read_qc rows with no sequencing link';
  SELECT count(*) INTO problems FROM v4.hifi_read_qc WHERE sequencing_id IS NULL;
  RETURN NEXT;

  check_name := 'note: hic_read_qc rows with no sequencing link';
  SELECT count(*) INTO problems FROM v4.hic_read_qc WHERE sequencing_id IS NULL;
  RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v4.check_ref_read_qc() IS
  'Phase RG window only: v4 read-QC tables against public after triage. Every problems value must '
  'be 0 except checks named note:. Dropped at RG.6.';

-- Verify --------------------------------------------------------------------------------------

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v4.sync_ref_read_qc() LOOP
    IF r.changed <> 0 THEN
      RAISE EXCEPTION '062: the sync is not a no-op after the migration: % %', r.step, r.changed;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM v4.check_ref_read_qc() LOOP
    IF r.check_name LIKE 'note:%' THEN
      RAISE NOTICE '062 %: %', r.check_name, r.problems;
    ELSIF r.problems <> 0 THEN
      RAISE EXCEPTION '062 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
END
$verify$;

GRANT SELECT ON ALL TABLES IN SCHEMA v4 TO readonly;

COMMIT;
