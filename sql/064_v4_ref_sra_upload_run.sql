-- 064_v4_ref_sra_upload_run.sql -- Phase RG: each SRA upload records the sequencing rows its
-- files came from.
--
-- Why. v4.ref_sra_upload (059) holds 304 raw-read submissions (SRR/ERR accessions) with their file
-- names, but nothing tied an upload to a library or run, so "which reads did we submit for this
-- OG" had no join. Owner, 2026-10-20: SRA uploads link to sequencing, and step 09 records the link.
-- Owner, 2026-10-22: a Hi-C file name starts with, or contains, the library_tube_id.
--
-- This builds:
--   ref_sra_upload_run           (srr_accession, sequencing_id): an upload can span several
--                                libraries (OG637: two HiFi barcodes, two ONT and three Hi-C libraries)
--   ref_sra_upload_unlinked      uploads reviewed and left unlinked, with the reason
--   resolve_sra_upload_runs()    the forward rule (below), used by the sync and by step 09
--   v_sra_upload_run_readiness   uploads with no link, and why
-- and adds the link step to v4.sync_ref_submission() and a note to v4.check_ref_submission().
--
-- Backfill evidence (2026-10-22, scripts/match_sra_uploads.py, rclone lsjson only):
-- s3:ocom.oceangenomes/illumina-hic/{run}/ (one folder per Hi-C run), the ENA staging copies in
-- analysed-data/reference-genomes/*/*/genomic_data/dovetail/, and pacbio/{run}/*/hifi_reads/.
-- Result: sql/data/064_sra_upload_runs.tsv. Of 304 uploads, 277 are linked:
--   hic 136/152   the run from a leading run ID, else from the raw-run folder holding the file (by
--                 name, by the staged copy's size, or by elimination: an earlier run's files were
--                 uploaded unprefixed, the later run's with the run ID in front); the library whose
--                 library_tube_id the name contains, else the OG's only Hi-C row on that run
--                 (older sample sheets named libraries OG11G_HICL, OG10G_D_HICL, OG101G-1_SBL)
--   hifi 101/102  the movie's pacbio/{run}/ folder when the OG has a row there, else barcode
--                 through hifi_read_qc, else the nearest PacBio seq_date; unassigned/unbarcoded
--                 files take the upload's one barcode
--   ont 25/26     the run ID in the name; ONT_240306_ADAK / ONT_230726_LPAD are the workbook's
--                 ONT_240306_AD / ONT_230726_AD (the OG's only ONT row with that run date)
--   illumina 15/15
-- Left unlinked (ref_sra_upload_unlinked), for the lab:
--   - NOVA_240719_AD (raw folder and hic_read_qc) is NOVA_240718_AD in sequencing: OG8, OG105, OG759;
--   - NOVA_250114_AD's Hi-C libraries are PACB_250114_AD in sequencing: OG676, OG678, OG683;
--   - OG650 has no row for NOVA_240501_LA; OG706 uploads HICL1, recorded as HICL/HICL2;
--   - OG665L-1 (two runs, sizes do not decide), OG88 (renamed files, no size match), OG651 (no ONT
--     row); 10 uploads with no file names (9 with no data_type either).
-- A link is applied only where the upload's file names are unchanged since the match (md5).
--
-- Forward rule, resolve_sra_upload_runs(og_id, data_type, filenames):
--   hic, ont, illumina  run IDs in the names; the OG's rows of that technology on those runs
--                       whose library_tube_id the names contain (followed by _ or .); else the OG's
--                       only such row on the run; else its only such row with the same run date.
--   hifi                per movie (m84154_YYMMDD_...): the OG's PacBio rows with the nearest
--                       seq_date within 21 days; several -> the one hifi_read_qc ties to the
--                       barcode; still several -> none for that movie.
-- It has no S3 access, so it cannot use the run folders; the staging step now prefixes Hi-C files
-- with their run ID, which is what makes the rule exact going forward. An upload it cannot link
-- shows in the readiness view.
--
-- Sync. Window only: an upload with no link, not in ref_sra_upload_unlinked, gets what the
-- resolver finds. Uploads the evidence left unlinked are not re-resolved by the weaker rule; when
-- the lab fixes a run ID, delete that upload's ref_sra_upload_unlinked row and the next sync
-- resolves it.
--
-- RG.6. The resolver is SET search_path = v4, public; re-point it to public when v4 moves.
--
-- Revert: sql/revert/064_v4_ref_sra_upload_run_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_sra_upload') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'v4' AND table_name = 'ref_sra_upload' AND column_name = 'release_date') THEN
    RAISE EXCEPTION '064 needs v4.ref_sra_upload with release_date (059, 060)';
  END IF;
END
$pre$;

CREATE TABLE IF NOT EXISTS v4.ref_sra_upload_run (
    srr_accession  text NOT NULL REFERENCES v4.ref_sra_upload ON DELETE CASCADE,
    sequencing_id  text NOT NULL REFERENCES public.sequencing (sequencing_id) ON DELETE CASCADE,
    PRIMARY KEY (srr_accession, sequencing_id)
);
CREATE INDEX IF NOT EXISTS ref_sra_upload_run_sequencing_id_idx ON v4.ref_sra_upload_run (sequencing_id);
COMMENT ON TABLE v4.ref_sra_upload_run IS
  'The sequencing rows (library on a run) an SRA upload''s files came from. Several where one upload '
  'carries several libraries. Migration 064.';

CREATE TABLE IF NOT EXISTS v4.ref_sra_upload_unlinked (
    srr_accession  text PRIMARY KEY REFERENCES v4.ref_sra_upload ON DELETE CASCADE,
    reason         text NOT NULL,
    reviewed_on    date NOT NULL DEFAULT current_date
);
COMMENT ON TABLE v4.ref_sra_upload_unlinked IS
  'SRA uploads reviewed and left with no sequencing link, and why (064''s evidence). The sync does '
  'not re-resolve these; delete a row once the lab has fixed the cause.';

CREATE OR REPLACE FUNCTION v4.resolve_sra_upload_runs(p_og_id text, p_data_type text, p_filenames text)
RETURNS SETOF text LANGUAGE plpgsql STABLE SET search_path = v4, public, pg_temp AS $fn$
DECLARE
  files text[] := ARRAY(SELECT btrim(f) FROM unnest(string_to_array(coalesce(p_filenames, ''), ',')) f
                        WHERE btrim(f) <> '');
  kind  text;
  runs  text[];
  hit   text[];
BEGIN
  IF cardinality(files) = 0 OR p_og_id IS NULL THEN
    RETURN;
  END IF;

  IF p_data_type = 'hifi' THEN
    RETURN QUERY
    WITH f AS (
      SELECT substring(x from 'm[0-9]+[a-z]?_([0-9]{6})_[0-9]{6}') AS mdate,
             substring(x from '\.(bc[0-9]+)(?:--bc[0-9]+)?\.') AS bc
      FROM unnest(files) x
    ), ub AS (
      SELECT CASE WHEN count(DISTINCT bc) = 1 THEN min(bc) END AS bc FROM f
    ), mv AS (
      SELECT DISTINCT f.mdate, coalesce(f.bc, ub.bc) AS bc FROM f CROSS JOIN ub WHERE f.mdate IS NOT NULL
    ), cand AS (
      SELECT mv.mdate, mv.bc, s.sequencing_id, s.library_tube_id,
             abs(to_date(mv.mdate, 'YYMMDD') - to_date(s.seq_date, 'YYMMDD')) AS gap
      FROM mv JOIN v_sequencing_browse s
        ON s.og_id = p_og_id AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio'
       AND s.seq_date ~ '^[0-9]{6}$'
       AND abs(to_date(mv.mdate, 'YYMMDD') - to_date(s.seq_date, 'YYMMDD')) <= 21
    ), nearest AS (
      SELECT c.* FROM cand c
      WHERE c.gap = (SELECT min(c2.gap) FROM cand c2 WHERE c2.mdate = c.mdate AND c2.bc IS NOT DISTINCT FROM c.bc)
    ), narrowed AS (
      SELECT n.mdate, n.bc, n.sequencing_id FROM nearest n
      WHERE (SELECT count(*) FROM nearest n2 WHERE n2.mdate = n.mdate AND n2.bc IS NOT DISTINCT FROM n.bc) = 1
         OR EXISTS (SELECT 1 FROM hifi_read_qc q
                    WHERE q.og_id = p_og_id AND q.barcode = n.bc
                      AND (q.sequencing_id = n.sequencing_id
                           OR q.og_id || q.tissue || '_' || q.ext_type || '_' || q.lib_code = n.library_tube_id))
    ), one AS (
      SELECT mdate, bc FROM narrowed GROUP BY mdate, bc HAVING count(*) = 1
    )
    SELECT DISTINCT n.sequencing_id FROM narrowed n
    JOIN one o ON o.mdate = n.mdate AND o.bc IS NOT DISTINCT FROM n.bc;
    RETURN;
  END IF;

  kind := CASE p_data_type WHEN 'hic' THEN 'Hi-C' WHEN 'ont' THEN 'ONT' WHEN 'illumina' THEN 'Illumina' END;
  IF kind IS NULL THEN
    RETURN;
  END IF;
  runs := ARRAY(SELECT DISTINCT m[1] FROM unnest(files) x,
                regexp_matches(x, '(?:^|[._])((?:NOVA|NEXT|ISEQ|PACB|ONT)[A-Za-z-]*_[0-9]{6}_[A-Za-z0-9]+)(?=[._])', 'g') m);
  IF cardinality(runs) = 0 THEN
    RETURN;
  END IF;
  hit := ARRAY(SELECT s.sequencing_id FROM v_sequencing_browse s
               WHERE s.og_id = p_og_id AND s.technology = kind AND s.run_id = ANY (runs)
                 AND EXISTS (SELECT 1 FROM unnest(files) x
                             WHERE strpos(x, s.library_tube_id || '_') > 0 OR strpos(x, s.library_tube_id || '.') > 0));
  IF cardinality(hit) = 0 THEN
    hit := ARRAY(SELECT s.sequencing_id FROM v_sequencing_browse s
                 WHERE s.og_id = p_og_id AND s.technology = kind AND s.run_id = ANY (runs));
  END IF;
  IF cardinality(hit) = 0 THEN
    hit := ARRAY(SELECT s.sequencing_id FROM v_sequencing_browse s
                 WHERE s.og_id = p_og_id AND s.technology = kind
                   AND split_part(s.run_id, '_', 2) = ANY (ARRAY(SELECT split_part(r, '_', 2) FROM unnest(runs) r)));
  END IF;
  IF cardinality(hit) = 1 OR EXISTS (SELECT 1 FROM unnest(files) x, v_sequencing_browse s
                                     WHERE s.sequencing_id = ANY (hit)
                                       AND (strpos(x, s.library_tube_id || '_') > 0 OR strpos(x, s.library_tube_id || '.') > 0)) THEN
    RETURN QUERY SELECT unnest(hit);
  END IF;
END
$fn$;
COMMENT ON FUNCTION v4.resolve_sra_upload_runs(text, text, text) IS
  'The sequencing rows an SRA upload''s file names point to (064''s forward rule). Used by the v4 '
  'sync and by ENA-ref-genomes step 09. Re-point search_path to public at RG.6.';

-- Backfill from the evidence (sql/data/064_sra_upload_runs.tsv, 2026-10-22) ------------------

CREATE TEMP TABLE sra_upload_links (
    srr_accession  text NOT NULL,
    sequencing_ids text[] NOT NULL,
    filenames_md5  text NOT NULL
) ON COMMIT DROP;
INSERT INTO sra_upload_links VALUES
  ('ERR17791606', ARRAY['OG794G-1_HICL_NOVA_260209_TW2'], '4e52d45899778e5178557b30e314f0f7'),
  ('ERR17794663', ARRAY['OG794G-1_HICL_NOVA_260209_TW2'], 'fc0287b799c0352a9afea413124b2d74'),
  ('ERR17794679', ARRAY['OG794G_D_SBL_PACB_250307_AD'], 'c2f77ddf2cec58cc4c33cbcd0a444ea1'),
  ('ERR17798705', ARRAY['OG652L-1_HICL_NOVA_260123_TWAD'], '98740fd622df3f3b951673dbcd0c6f4f'),
  ('ERR17798706', ARRAY['OG659L-1_HICL_NOVA_240509_AD'], 'e19820fbfeb68ad6e79e55c02d6030f5'),
  ('ERR17798707', ARRAY['OG111G-4_HICL_NOVA_260123_TWAD'], '6303596b96c57846ec458bd295d9668c'),
  ('ERR17798709', ARRAY['OG40G-2_HICL_NEXT_251118_AD'], '1ee400e1a25448b4e1d93b2737c54e37'),
  ('ERR17798710', ARRAY['OG652L-1_HICL_NOVA_260123_TWAD'], 'aa1966e428465cbc6fd9d61acc0863bb'),
  ('ERR17798711', ARRAY['OG658G-2_HICL_NOVA_260209_TW1'], '0e8ab185bf1667000a29cb5982c59b4b'),
  ('ERR17798713', ARRAY['OG659L-1_HICL_NOVA_240509_AD'], '19d479d536a7992b2b0134bcf004961f'),
  ('ERR17798716', ARRAY['OG664G-1_HICL_NEXT_250325_AD'], '8a9a587507b5fed32ccdf98f807f2cb0'),
  ('ERR17798717', ARRAY['OG652H_D_SBL_PACB_240327_LA'], '3a1cf7c95f79cc23abe8cf6e86b9bd10'),
  ('ERR17798718', ARRAY['OG111G-4_HICL_NOVA_260123_TWAD'], '9b91a64e825a438f556fa9b3c7bb8018'),
  ('ERR17798719', ARRAY['OG40H_D2_SBL_PACB_241004_LA'], 'a87739e66429aab7351523f8f01b1804'),
  ('ERR17798723', ARRAY['OG659H_D_SBL2_PACB_240427_LA'], 'fcdb84ab45d986ffcb93be756764c777'),
  ('ERR17798774', ARRAY['OG658G-2_HICL_NOVA_260209_TW1'], '94a653676f38a436e3d8001d2f1e062e'),
  ('ERR17798775', ARRAY['OG111H_D_SBL_PACB_241018_LA'], '4d038d1008f8a6d2b8977d693a777d29'),
  ('ERR17798776', ARRAY['OG664H_D_SBL_PACB_241018_LA'], '9b824e3e1e8883fea6c2f041fbca9267'),
  ('ERR17798777', ARRAY['OG658H_D_SBL_PACB_240327_LA'], '6a0acbd8a53074048392a907e01086fa'),
  ('ERR17853347', ARRAY['OG1326L-1_HICL_NOVA_260605_AD2'], 'd84fe79fcd849495fe20442fecaeaa28'),
  ('ERR17853424', ARRAY['OG1326L-1_HICL_NOVA_260605_AD2'], '5f715b9287c6266c0a35ffe6dcf8221e'),
  ('ERR17853989', ARRAY['OG1326H_D2_SBL_PACB_260730_AMD'], '47d3e2b3f7811230adf4f6527440a5fc'),
  ('ERR17854807', ARRAY['OG53G-1_HICL_NEXT_240301_AD'], 'df56a4abed5476907bfc32c06c12abf9'),
  ('ERR17854809', ARRAY['OG53G_D2_SBL2_PACB_230915_LP'], 'f0bcda0a88dad4bf895c4eb2715c3305'),
  ('ERR17854995', ARRAY['OG53G_D2_SBL_PACB_230915_LP'], '06fa3e46377ab18b9d85b40059ef7b83'),
  ('ERR17884216', ARRAY['OG778G-2_HICL_NEXT_250613_LA'], '2544cf8b5a00a4cca742e1363c3270a3'),
  ('ERR17884217', ARRAY['OG829L-2_HICL_NEXT_250613_LA'], '9eac747951ca734554abe862c19ce8a2'),
  ('ERR17884221', ARRAY['OG679L-2_HICL_NEXT_250613_LA'], 'eb4023808ea94a356af5a11606a11319'),
  ('ERR17884222', ARRAY['OG810G-2_HICL_NOVA_260420_TW1'], '11e518616388f8b1ba678c297f318564'),
  ('ERR17884223', ARRAY['OG801L-1_HICL_NOVA_260209_TW1'], '5cfa4580be6e326010db75d01a979687'),
  ('ERR17884224', ARRAY['OG679H_D_SBL_PACB_250307_AD'], 'fcd4707e7e39eb5160a609f2fe4eb4cb'),
  ('ERR17884225', ARRAY['OG824G-1_HICL_NOVA_250522_AD'], '266486ede372c6041fc48d70cfe99e4c'),
  ('ERR17884226', ARRAY['OG67W-1_HICL_NOVA_260123_TWAD'], '59276c8b80b22a73cc459e9d6aa6fea0'),
  ('ERR17884227', ARRAY['OG838B-1_HICL2_NOVA_241106_AD'], '12ae726dd972cd4d9c1d0b1d07c53af8'),
  ('ERR17884229', ARRAY['OG778H_D_SBL_PACB_241018_LA'], 'c5d112ce2bcdda9363eec042b9bcc580'),
  ('ERR17884230', ARRAY['OG829H_D2_SBL_PACB_240927_LA'], 'eddc62de7a7db80ccb64b6b9051ff030'),
  ('ERR17884231', ARRAY['OG113G-1_HICL_NOVA_240522_AD'], '614289c6ee1365a40cb2bd39b30fac4c'),
  ('ERR17884232', ARRAY['OG855L-2_HICL_NEXT_250325_AD'], '07b9165ed8c980d0d284d76ac07fd87b'),
  ('ERR17884234', ARRAY['OG681L-2_HICL_NEXT_250613_LA'], '3bd20f3ddf371320efcf2c9730f49c3e'),
  ('ERR17884235', ARRAY['OG67W-1_HICL_NOVA_260123_TWAD'], 'c09426155cddf9541d51f2534cb848b0'),
  ('ERR17884236', ARRAY['OG824H_D_SBL_PACB_241004_LA'], 'b368b6079dd5ce8f279e090559c1d7e7'),
  ('ERR17884237', ARRAY['OG838B-1_HICL2_NOVA_241106_AD'], 'd1dd004f782b55197b6055fcb3000a09'),
  ('ERR17884238', ARRAY['OG855H_D_SBL_PACB_240821_AD'], 'cac540008610cc62673ee5d518926d9c'),
  ('ERR17884239', ARRAY['OG64W-1_HICL_NEXT_251118_AD'], 'fd7bb361fcfb96277d99a3d18dfc0240'),
  ('ERR17884242', ARRAY['OG64W_D_SBL_PACB_250307_AD'], '0051d92506ba93359977511cc7b679b9'),
  ('ERR17884243', ARRAY['OG836B-1_HICL2_NOVA_241106_AD'], '4ff75c636bdf9d55c6261452b86c1754'),
  ('ERR17884245', ARRAY['OG838B-1_HICL_NOVA_241106_AD'], 'b0ac1a23b206f41fa4655a68863b25ab'),
  ('ERR17884293', ARRAY['OG681H_D_SBL_PACB_250307_AD'], '56286423e01e1f81f2bc2f810fc682df'),
  ('ERR17884294', ARRAY['OG838B-1_HICL_NOVA_241106_AD'], '52f4f31fa9412bd71ca594e1cb262ed5'),
  ('ERR17884295', ARRAY['OG836B-1_HICL2_NOVA_241106_AD'], 'a2a282accb5db3a64188a345c2a3d130'),
  ('ERR17884297', ARRAY['OG836B-1_HICL_NOVA_241106_AD'], '7b2da78c370d6fefd07828f9f8fe4e60'),
  ('ERR17884298', ARRAY['OG838B2_D_SBL_PACB_240813_AD'], 'fd27868bedfdc7a597352e02fafc178b'),
  ('ERR17885181', ARRAY['OG836B-1_HICL_NOVA_241106_AD'], '42f09eba03b400ceb3c41e16aa6112cc'),
  ('ERR17885271', ARRAY['OG863G-2_HICL_NOVA_250312_LA'], 'b889d4ee3b30a6eca86c5894bd3360ed'),
  ('ERR17885433', ARRAY['OG863G-2_HICL_NOVA_250312_LA'], 'a0abf5d353e1406738ac04f0a49f7374'),
  ('ERR17885438', ARRAY['OG838B2_D_SBL_PACB_240813_AD'], '5a1eae6039d55d6087cbe595f6f1b413'),
  ('ERR17885599', ARRAY['OG863G_D_SBL_PACB_241004_LA'], '251ec44b9499745e4e33c3b42985189a'),
  ('ERR17885765', ARRAY['OG863G_D_SBL_PACB_250331_LA'], 'ea3aeedd269e4b53ae05b35520de07c9'),
  ('ERR17885783', ARRAY['OG666L-1_HICL_NOVA_250312_LA'], 'd35b76cbcba98baa9aa0f56b1c1533d7'),
  ('ERR17885914', ARRAY['OG666L-1_HICL_NOVA_250312_LA'], '6eac1497a190cd9b7083374e21a8993e'),
  ('ERR17885978', ARRAY['OG676H_D_SBL_PACB_240327_LA'], '72203263f8149a25349cf5c0c224a5cd'),
  ('ERR17885979', ARRAY['OG54G-3_HICL_NEXT_250613_LA'], '8bd9fc83f0e9c616e647ae304e05cba4'),
  ('ERR17885981', ARRAY['OG810G-2_HICL_NOVA_260420_TW1'], 'b34ce3fcb4f8ebb9decae3f6d9e2ddfc'),
  ('ERR17885983', ARRAY['OG686G-1_HICL_NEXT_250613_LA'], '0b45f9925a783f72b81c3a392f8229c7'),
  ('ERR17885985', ARRAY['OG666H_D_SBL_PACB_241004_LA'], 'ced626f48c88cc3e908276f4928b7f5a'),
  ('ERR17885986', ARRAY['OG801L-1_HICL_NOVA_260209_TW1'], 'b66a509f7106bea529ad0417abda84bf'),
  ('ERR17886011', ARRAY['OG54G_D_SBL_PACB_241004_LA'], 'f11f76cacc6e43829d6ec356ea23e698'),
  ('ERR17886018', ARRAY['OG54G_D_SBL2_PACB_250331_LA'], 'db55559ffae1c1b7107ddfc34dfce8cc'),
  ('ERR17886440', ARRAY['OG837B-1_HICL2_NOVA_241106_AD'], '8fdb8ef83c818c9ab957b6e43a5b1c29'),
  ('ERR17886522', ARRAY['OG836B_D_SBL_PACB_240520_LA'], '9212b53d6b87ed6eba5874b31295f459'),
  ('ERR17886775', ARRAY['OG837B-1_HICL2_NOVA_241106_AD'], '4a04f41c3dd177d34fedfe8e77453a23'),
  ('ERR17886816', ARRAY['OG836B_D_SBL_PACB_240520_LA'], '2fbd172c5bedf67d14d2c9ca80b7bf1c'),
  ('ERR17886830', ARRAY['OG837B-1_HICL_NOVA_241106_AD'], '9676b4d524980f41c523ea1661d1d901'),
  ('ERR17886916', ARRAY['OG686H_D_SBL_PACB_241004_LA'], 'db66c77c8a92cd47199de2eaf1a04f3e'),
  ('ERR17887176', ARRAY['OG837B-1_HICL_NOVA_241106_AD'], '278a027b008c2e4800345cecd1ea8df7'),
  ('ERR17887179', ARRAY['OG801L_D_SBL_PACB_250828_AD'], '4691b588ed454dffd128b7be73244e8e'),
  ('ERR17887334', ARRAY['OG113G-1_HICL_NOVA_240522_AD'], '2ed00b74005b77baced850d95e512903'),
  ('ERR17887450', ARRAY['OG67W_D_SBL_PACB_241127_AD'], '4de28634dffc91400e35ca21ed4bf304'),
  ('ERR17887477', ARRAY['OG837B_D3_SBL_PACB_240813_AD'], 'f16e9b7a31ff21630be1d52573f17072'),
  ('ERR17887488', ARRAY['OG810G_D_SBL_PACB_241004_LA'], 'f1c0e01cbf547e083a3cd86ce4be1b37'),
  ('ERR17887591', ARRAY['OG79G-1_HICL2_NOVA_240522_AD'], '370bbf92602b628eb3f7c145be0a605d'),
  ('ERR17887594', ARRAY['OG79G-1_HICL2_NOVA_240522_AD'], '3da100343a234a8a48993f91a63987bb'),
  ('ERR17887597', ARRAY['OG79G_D_SBL_PACB_240427_LA'], '8243ab63358f14c4bfd55003611e6487'),
  ('ERR17887765', ARRAY['OG683L-1_HICL_NEXT_240705_AD'], '23f38499207e6c34a43423c82d02654f'),
  ('ERR17887769', ARRAY['OG683H_D_SBL2_PACB_241023_AD'], 'e8e7c97e7229b90cd51f99bc2ec9c168'),
  ('ERR17887777', ARRAY['OG837B_D3_SBL_PACB_240813_AD'], '04226911522acc97eeace6e5fa63f66b'),
  ('ERR17887778', ARRAY['OG683H_D_SBL2_PACB_240821_AD'], 'c16205f25a8eb823dbb69287e1bc146e'),
  ('ERR17887780', ARRAY['OG55G-2_HICL_NEXT_251118_AD'], '8d719ec5e5bcb31aa48d34073e0d3096'),
  ('ERR17887781', ARRAY['OG55G_D_SBL_PACB_231115_LA'], 'a523db47cdda14054bfa23754a95cd48'),
  ('ERR17887782', ARRAY['OG55G_D_SBL_PACB_231115_LA'], '20ffd7e71a023b586fa9fc4255d35d9e'),
  ('ERR17889038', ARRAY['OG666L-1_HICL_NOVA_250522_AD'], 'e7c51c9529a9206fb35f7b03373a2972'),
  ('ERR17889039', ARRAY['OG810G-2_HICL_NOVA_260605_AD'], '1684107f8f6f1768797f0fd0efd082b1'),
  ('ERR17889130', ARRAY['OG810G-2_HICL_NOVA_260605_AD'], 'b847a512357030d826f772259379bd1d'),
  ('ERR17889131', ARRAY['OG686G-1_HICL_NOVA_250624_LA'], '81daff6bcb1b7b98dcb2444bea0ad670'),
  ('ERR17889210', ARRAY['OG686G-1_HICL_NOVA_250624_LA'], '8727f430785bac2e7415a0a238663a2a'),
  ('ERR17889211', ARRAY['OG778G-2_HICL_NOVA_250624_LA'], 'a2e8decb40d34611dce7269d359002a3'),
  ('ERR17889214', ARRAY['OG863G-2_HICL_NOVA_250522_AD'], '97130e9d71f2c4876828d2f5b545607d'),
  ('ERR17889216', ARRAY['OG863G-2_HICL_NOVA_250820_AD'], '873122e0b8bf62f7f1e720188bda115b'),
  ('ERR17889217', ARRAY['OG778G-2_HICL_NOVA_250624_LA'], '1311d4eef787ca1f9949657af9d9a4b4'),
  ('ERR17889218', ARRAY['OG863G-2_HICL_NOVA_250820_AD'], '914c3b7fd5736a6afb1671630117a66a'),
  ('ERR17889223', ARRAY['OG64W-1_HICL_NOVA_251204_AD'], 'be7b84b746239a34b1c60c8d4a29552f'),
  ('ERR17889224', ARRAY['OG829L-2_HICL_NOVA_250624_LA'], '4ac33775871e846ee89e04539fb28883'),
  ('ERR17889225', ARRAY['OG679L-2_HICL_NOVA_250624_LA'], 'faa171dc11de629616f2b6540b6e57d2'),
  ('ERR17889226', ARRAY['OG829L-2_HICL_NOVA_250624_LA'], '967b217896d3b45398052967fa460177'),
  ('ERR17889227', ARRAY['OG679L-2_HICL_NOVA_250624_LA'], '39d9142bb4e77295bcff0ef3405d4fda'),
  ('ERR17889239', ARRAY['OG855L-2_HICL_NOVA_250505_AD'], '1e3c141e9c0627f3c454defe994f8ea4'),
  ('ERR17889241', ARRAY['OG55G-2_HICL_NOVA_251204_AD'], 'deded7a432de8aa82b9a0ef542d5d2a2'),
  ('ERR17889317', ARRAY['OG855L-2_HICL_NOVA_250505_AD'], '11c07b7664b4277b7f8a1ef8af2b0c31'),
  ('ERR17889318', ARRAY['OG838B-1_HICL_NOVA_250522_AD'], 'c9e52390314e7eefeca6e4311ead38a6'),
  ('ERR17889320', ARRAY['OG681L-2_HICL_NOVA_250624_LA'], '86e2dea53b527c2aa1f27caa22eee017'),
  ('ERR17889325', ARRAY['OG54G-3_HICL_NOVA_250624_LA'], 'bea27c590943ce8282e17a8948cbf6a9'),
  ('ERR17889412', ARRAY['OG681L-2_HICL_NOVA_250624_LA'], '19a77273c9520bdc89581a70446790af'),
  ('ERR17889413', ARRAY['OG54G-3_HICL_NOVA_250624_LA'], '3c824cd7ad9a3042eb62a3399ffaffa8'),
  ('ERR17889415', ARRAY['OG64W-1_HICL_NOVA_251204_AD'], 'ac1adec0d8bc405be3b090e7b7269142'),
  ('ERR17889436', ARRAY['OG55G-2_HICL_NOVA_251204_AD'], 'ca6581fefc94387f8fe302983b338db5'),
  ('ERR17889782', ARRAY['OG37H-1_HICL_NEXT_250325_AD'], '90c1ec86b25bcf2713c87de08ee77b13'),
  ('ERR17889807', ARRAY['OG678G-1_HICL_NOVA_241125_AD'], '424d16102bfbcab4118591c23cd667e9'),
  ('ERR17889808', ARRAY['OG678G-1_HICL_NOVA_241125_AD'], 'cb8dbe307e448f7fcf83cc1d3881e6a0'),
  ('ERR17889810', ARRAY['OG37H-1_HICL_NOVA_250505_AD'], 'cc4c8bb79108425ae4b3f48fe90a82b2'),
  ('ERR17889812', ARRAY['OG37H-1_HICL_NOVA_250505_AD'], 'a4e6d74de9c10f273e2f462ea23afaf9'),
  ('ERR17889825', ARRAY['OG37G_D_SBL_PACB_240116_LAAD'], '06d60477cbea3cfdc25a5c05a3f777a6'),
  ('ERR17889838', ARRAY['OG678H_D_SBL_PACB_240327_LA'], 'e51d4c00cdad4ba50ae11ba2b142b6a0'),
  ('ERR18010633', ARRAY['OG61W-3_HICL_NEXT_251118_AD'], 'ddd8eccc4918c3257ee5876bea1d507a'),
  ('ERR18010634', ARRAY['OG856L-1_HICL_NEXT_240705_AD'], '9f25f739c801420313454f1c611463ff'),
  ('ERR18010635', ARRAY['OG856L2-1_HICL_NOVA_241204_AD'], '077a80e3f29225f07c9ae99023437ac2'),
  ('ERR18010636', ARRAY['OG856L2-1_HICL_NOVA_241204_AD'], '552a0f9fc11edc15fe42cb0ef48ac061'),
  ('ERR18010637', ARRAY['OG61W-3_HICL_NOVA_251204_AD2'], 'f3b03cd994b765b6720900539757b8fe'),
  ('ERR18010638', ARRAY['OG856L2-1_HICL_NOVA_250505_AD'], '00fb7aef56d6f93c5beca0919963ea91'),
  ('ERR18010640', ARRAY['OG61W-3_HICL_NOVA_251204_AD2'], '13213ff13068e20f1df130207627fb2b'),
  ('ERR18010641', ARRAY['OG856L2-1_HICL_NOVA_250505_AD'], '6cc7f37e057ba208a449dbadf66fc752'),
  ('ERR18010642', ARRAY['OG61W_D_SBL_PACB_250317_AD'], '44bc289956a40bf612b007c0c5972865'),
  ('ERR18010643', ARRAY['OG856H_D_SBL_PACB_240821_AD'], '4909a9957cd2e2c8167238a02e0118e0'),
  ('SRR28675117', ARRAY['OG36W-1_HICL_NEXT_240207_AD'], '9ac59a0d3c0bbec9eaf7459197874584'),
  ('SRR28675118', ARRAY['OG36W_D_SBL_PACB_230724_AD'], 'bbe674dee9f377cf94989054fea4b597'),
  ('SRR28678403', ARRAY['OG88G_D_SBL_PACB_230724_AD'], 'd7d32df218b761d2d140d8236680b42f'),
  ('SRR28680776', ARRAY['OG95H-1_HICL_NEXT_230912_AD'], 'c05298a1c4c57e13fda5c727b3c6e203'),
  ('SRR28680777', ARRAY['OG95H_D_SBL_PACB_230525_AD'], 'f7377f5ff3538f9696aab6876c9890f8'),
  ('SRR28880426', ARRAY['OG88G_R_IL_NOVA_240301_LA'], 'c4b026c0eaec1b79869bcd891c727913'),
  ('SRR28880427', ARRAY['OG95H_R_IL2_NOVA_240301_LA'], '764eaa75c1d3b9055f9ec243f05927d3'),
  ('SRR28880835', ARRAY['OG36W_R_IL_NOVA_240301_LA'], '13c1bd9660b837a585b28bfb20059141'),
  ('SRR28903490', ARRAY['OG10G_R_IL2_NOVA_240301_LA'], 'c3444d2a86912327ea87d87ca67998a3'),
  ('SRR28903491', ARRAY['OG10G-1_HICL_NEXT_230912_AD'], '1e02aeb15c1938bb52f06932d0ba4a0e'),
  ('SRR28903492', ARRAY['OG10G_D_SBL_PACB_230209_LP'], '5f1c67070b5514043c6263283d2d403e'),
  ('SRR28903493', ARRAY['OG76G_R_IL_NOVA_240301_LA'], 'c524314791bc64b82ccc75f4a8205955'),
  ('SRR28903494', ARRAY['OG76G-1_HICL_NEXT_240301_AD'], '7d1ac5796894d975d43520cc57e1cf55'),
  ('SRR28903495', ARRAY['OG76G_D_SBL_PACB_230825_AD'], '4d71a1a78480c94f8e3268ad533751a4'),
  ('SRR28903531', ARRAY['OG14G_R_IL_NOVA_240301_LA'], 'e60174810d33fdf3cdb4f4fad51eeb0d'),
  ('SRR28903532', ARRAY['OG14G-1_HICL_NEXT_240207_AD'], 'f12901fcd9ba83b3c47551625cf38e45'),
  ('SRR28903533', ARRAY['OG14G_D_SBL_PACB_230209_LP'], '0e6578f3c464e9fe5585dd29dabe499a'),
  ('SRR28903534', ARRAY['OG11G_R_IL2_NOVA_240301_LA'], '0de67099ef4def4aa91f8bf43a6804e6'),
  ('SRR28903535', ARRAY['OG11G-1_HICL_NEXT_240207_AD'], 'b12a918d2077c3e4f984f6857d479604'),
  ('SRR28903536', ARRAY['OG11G_D_SBL_PACB_230825_AD'], '1415a701dff5b6f1a7a2adeb538033af'),
  ('SRR28903549', ARRAY['OG15G_R_IL2_NOVA_240301_LA'], '50eef2b218564b632eb00cbfa5c8a630'),
  ('SRR28903550', ARRAY['OG15G-1_HICL_NEXT_240207_AD'], 'ec174658c515055c6836feaeb1b5d934'),
  ('SRR28903551', ARRAY['OG15G_D_SBL_PACB_230413_AD'], 'ab69257a21506659772c6955f398e846'),
  ('SRR28983768', ARRAY['OG5G_D_SBL2_PACB_230628_AD'], '414b069a8bf690b8b08f5d4405025142'),
  ('SRR28983769', ARRAY['OG5G_D2_SBL_PACB_240116_LAAD'], '46aeae107e11610b6ae9c4e5c3b9a95e'),
  ('SRR28983770', ARRAY['OG5G_R_IL_NOVA_240301_LA'], '4d2c661885d79abd97b1bd99ea7383dc'),
  ('SRR28983771', ARRAY['OG5G-1_HICL_NEXT_230912_AD'], '91018ca98c9a02901d478d0fe4abc938'),
  ('SRR28983772', ARRAY['OG5G_D_SBL_PACB_230609_AD'], 'ed48a9e3cc47a3ae43bb2758a1bff27b'),
  ('SRR29159646', ARRAY['OG6G-1_HICL_NEXT_240405_AD'], '3626963daed57225bda89e6d3c16678b'),
  ('SRR29159647', ARRAY['OG6G_D_SBL2_PACB_230628_AD'], '0b9c5d5ab8658fce9e1fac183e393c49'),
  ('SRR29159648', ARRAY['OG2G-2_HICL_NEXT_240405_AD'], 'c957eb1b5e39df612f1e5ae0e4412769'),
  ('SRR29159649', ARRAY['OG2G_D_SBL_PACB_230413_AD'], '358986fecbd9b445b4b2d2fa54d50d34'),
  ('SRR29159650', ARRAY['OG3G-3_HICL_NEXT_240405_AD'], '870b06ad572aa4021ad7bd97e7e1e485'),
  ('SRR29159651', ARRAY['OG3G_D_SBL_PACB_230825_AD'], 'b26251a656bf5708a5f85dec868b98fe'),
  ('SRR29159653', ARRAY['OG1G-1_HICL_NEXT_240405_AD'], '7c19ce07f30b36cf030c7520e4a4325e'),
  ('SRR29159654', ARRAY['OG1G_D_SBL_PACB_230525_AD'], '01b7fd5991e47df0cd6073c452bbf4fb'),
  ('SRR29313611', ARRAY['OG12G-1_HICL_NOVA_240509_AD'], '43972a9cc267f148198970710d90302a'),
  ('SRR29313612', ARRAY['OG12G_D_SBL_PACB_230512_AD'], 'f1454d4bb1246769bd9b69496bbdeca2'),
  ('SRR29313688', ARRAY['OG28B_D7_SBL_PACB_230811_AD'], '0f77b62851c97b79366446f0eb24476c'),
  ('SRR29313689', ARRAY['OG28B_D6_SBL_PACB_230811_AD'], '72180ca45e229f89a43941d54149ec8d'),
  ('SRR29313690', ARRAY['OG28B_D5_SBL_PACB_230811_AD'], 'e4c3417ccdcff3f43cdd3323ecf819e5'),
  ('SRR29313691', ARRAY['OG28B-1_HICL_NEXT_230912_AD'], '857e3b4cbfa2f270903da65622989cfc'),
  ('SRR29313692', ARRAY['OG28B_D4_SBL_PACB_230811_AD'], 'cdef7e0e5be6dca326e6884c857e0fe0'),
  ('SRR29340084', ARRAY['OG105G_R_IL_NOVA_240301_LA'], 'f679df42e0ef351f31e957cd0603452c'),
  ('SRR29340085', ARRAY['OG105H_D_SBL_PACB_231027_ADLA'], '6303bf256a9bf1cb30660e53fb7f11a2'),
  ('SRR29340086', ARRAY['OG52G_R_IL2_NOVA_240301_LA'], 'd2de168e1fab595dc89e07fa1df12d43'),
  ('SRR29340087', ARRAY['OG52G-1_HICL_NEXT_240207_AD'], 'f0e01d3f2b3a103c15393957fdade16e'),
  ('SRR29340088', ARRAY['OG52G_D_SBL_PACB_230825_AD'], '16ea6e8f95e2cba6153a87e56a4548b2'),
  ('SRR29340089', ARRAY['OG113G_R_IL_NOVA_240301_LA'], '668aae6d2b111b90fef03a34c6992385'),
  ('SRR29340090', ARRAY['OG113G_D_SBL_PACB_231027_ADLA'], 'a386077489268aee88fac84711491036'),
  ('SRR29340091', ARRAY['OG9G-2_HICL_NEXT_240301_AD'], 'f0b0df558457fbbac1290f870d71228c'),
  ('SRR29340092', ARRAY['OG9G_D3_SBL_PACB_240206_AD'], '3fbadc8134ebf10219ae2cd024e2eb7f'),
  ('SRR29340093', ARRAY['OG101G_R_IL_NOVA_240301_LA'], '01ec695e1e210a33561af2f8dcf67921'),
  ('SRR29340094', ARRAY['OG101G-1_HICL_NEXT_240301_AD'], '785ddccf6ded238e9ef051665d5d6922'),
  ('SRR29340095', ARRAY['OG101H_D_SBL2_PACB_240206_AD'], 'c63943f4feff7e3f980a21117a5a27fb'),
  ('SRR29340145', ARRAY['OG672H_R_IL_NOVA_240301_LA'], '8d8075ceab153cbe911ac48f12bd32f9'),
  ('SRR29340146', ARRAY['OG672L-1_HICL_NEXT_240301_AD'], '288ef776d6de0fdf517e996d53f59b0d'),
  ('SRR29340147', ARRAY['OG672H_D2_SBL_PACB_240215_AD'], '3f956e6b2fc12aeeeb88313f777613fd'),
  ('SRR29368780', ARRAY['OG706L-8_HICL2_NOVA_240501_LA'], 'e23ae67da1274d5d779b0296136eca7f'),
  ('SRR29368781', ARRAY['OG706L-7_HICL2_NOVA_240501_LA'], '2c9ee50a8cf9da48b116b166655d6c9c'),
  ('SRR29368784', ARRAY['OG706H_D5_SBL_PACB_240228_AD'], 'e88d9b67a6c6bb11c6d50804c86b2641'),
  ('SRR29368785', ARRAY['OG706H_D_SBL2_PACB_240206_AD'], '3fc0b4d6902f0490d6b20276984e61d3'),
  ('SRR29368786', ARRAY['OG706H_D_SBL_PACB_240206_AD'], '8bf0f24f3caecb1150673a29f920ff58'),
  ('SRR30164277', ARRAY['OG660H_R_IL_NOVA_240301_LA'], '6f6d25fa5dc7cc9faf08910ee4339047'),
  ('SRR30164278', ARRAY['OG660L-2_HICL_NEXT_240301_AD'], '7b72c4fa237ec64e997ca05d44007a72'),
  ('SRR30164279', ARRAY['OG660H_D2_SBL2_PACB_240228_AD'], '386229cc8dfd67925160d1627f797d54'),
  ('SRR30164280', ARRAY['OG660H_D2_SBL_PACB_240228_AD'], '8cff710716ea1a1c97b01718cdc35b40'),
  ('SRR32638237', ARRAY['OG13G-1_HICL_NEXT_240423_AD'], 'a9a76a25449e6c29fec991ca052b574b'),
  ('SRR32638238', ARRAY['OG13G_D_LSKL_ONT_240307_AD2'], '9a7bbf54e9c9d97805046da4d1acf52f'),
  ('SRR32638239', ARRAY['OG13G_D_SBL_PACB_230209_LP'], '2209e522e2a126c869bc33d1f6839005'),
  ('SRR32638240', ARRAY['OG16G-1_HICL_NOVA_240509_AD'], '00f1a27c6a87a98a0a306a36c636eac1'),
  ('SRR32638241', ARRAY['OG16G_D_SBL_PACB_240427_LA'], '63bdd73dbceb891fceab2d4505bab38f'),
  ('SRR32638324', ARRAY['OG114G-1_HICL_NOVA_240613_LA'], 'e11333204990b4f2bab3536154082600'),
  ('SRR32638325', ARRAY['OG114H_D2_LSKL_ONT_240306_AD'], 'f641e25fae229a95b7abd6c073339d69'),
  ('SRR32638326', ARRAY['OG114H_D_SBL2_PACB_240116_LAAD'], 'a8d396cfad56d06f386fb10f7a871cba'),
  ('SRR32638328', ARRAY['OG108G-1_HICL_NOVA_240522_AD'], 'bfc1b2cc1d37eead7185f353ea7863d6'),
  ('SRR32638329', ARRAY['OG108H_D_LSKL_ONT_240306_AD'], 'eb9130afba2d19f15f7de51016e6d241'),
  ('SRR32638330', ARRAY['OG108H_D_SBL_PACB_231027_ADLA'], '69e1fe58dd3f0e002c2894dec88bb7f0'),
  ('SRR32638517', ARRAY['OG647G-1_HICL_NOVA_240613_LA'], '6bee11ed5412049812b5209fa3a2322f'),
  ('SRR32638518', ARRAY['OG647H_D_SBL_PACB_240501_AD'], '010daf40a038013f88664844ab1a3c90'),
  ('SRR32638520', ARRAY['OG650H_D_SBL_PACB_240327_LA'], '6e440865bebce6648600b0a28df6779f'),
  ('SRR32639442', ARRAY['OG38L-1_HICL_NOVA_241125_AD'], 'a153fcf8186352ee8afd5a3e7c139a90'),
  ('SRR32639443', ARRAY['OG38G_D_LSKL_ONT_240418_AD'], 'd2addf94b042911b1f274b3268b8c2c7'),
  ('SRR32639444', ARRAY['OG38G_D_SBL_PACB_230609_AD'], 'e258b49c78187ee1b1e147b5385d68b0'),
  ('SRR32639457', ARRAY['OG701L-1_HICL_NOVA_240509_AD'], 'be0c4913cc8db08b8d7a08212c8c894b'),
  ('SRR32639458', ARRAY['OG701H_D_SBL2_PACB_240427_LA'], '18d80014f2671397290625e3e8058f3d'),
  ('SRR32639460', ARRAY['OG759H_D_SBL_PACB_240520_LA'], '676234363837bd0e065d9ffb3c688dc5'),
  ('SRR32639461', ARRAY['OG760L-1_HICL_NEXT_240705_AD'], 'f03f93ae8a106b326003e4a2963eb010'),
  ('SRR32639462', ARRAY['OG760H_D2_SBL_PACB_240520_LA'], '96030dc6242817dbbe7c886398aec54b'),
  ('SRR32639464', ARRAY['OG8G_D_LSKL_ONT_240418_AD'], 'fc262a0f3c39bbfb231910b64bb7f06c'),
  ('SRR32639465', ARRAY['OG8G_D_SBL_PACB_230512_AD'], 'bfd7f94bd76c29fe6c4bbee07f310aa7'),
  ('SRR32639781', ARRAY['OG35W-1_HICL_NEXT_240207_AD'], 'ab4506a5a730de323194fb78b8e0828f'),
  ('SRR32639782', ARRAY['OG35W_D2_LSKL_ONT_240306_AD'], 'd1d35f4066d6c7e5040bac1d078f4294'),
  ('SRR32639783', ARRAY['OG35W_D_SBL_PACB_231027_ADLA'], '63c2c93ceda28d33d9e7c0bb718d269b'),
  ('SRR32639804', ARRAY['OG47G-1_HICL_NEXT_240207_AD'], 'bcca24c2cf276c959b0ad9dfb9e65638'),
  ('SRR32639805', ARRAY['OG47G_D_LSKL_ONT_240418_AD'], '87dc5d922fdcbb8e74d1e9303db93945'),
  ('SRR32639806', ARRAY['OG47G_D_SBL_PACB_231115_LA'], 'f4d18bb9863a4f89a77de1f89ca0338e'),
  ('SRR32640330', ARRAY['OG654L-1_HICL_NOVA_240501_LA'], '808fc7cb81182f59fcef3c1cf4bd18b0'),
  ('SRR32640331', ARRAY['OG654H_D_LSKL_ONT_240306_AD'], '25164a805535b12efc302163affd3846'),
  ('SRR32640332', ARRAY['OG654H_D_SBL_PACB_240327_LA'], '0725535a2f06324f3fd84215053c2139'),
  ('SRR32729623', ARRAY['OG651G-1_HICL_NOVA_240501_LA'], '9a9fc92dd79eb9b5377a2eb0e17dd420'),
  ('SRR32729625', ARRAY['OG651H_D_SBL_PACB_240327_LA'], '91c846c2183d5bfdd0501cb8141bd056'),
  ('SRR32747483', ARRAY['OG99G-2_HICL_NOVA_240522_AD'], 'b9b1c38d9b3f08dc050ebdec31f41a78'),
  ('SRR32747484', ARRAY['OG99G_D2_SBL_PACB_240215_AD'], '569b8767e666eb608b3a6a5178addea8'),
  ('SRR32748484', ARRAY['OG115L-1_HICL_NOVA_240613_LA'], 'd36b33278b1d0e6bdb627d8c68635f89'),
  ('SRR32748485', ARRAY['OG115H_D_LSKL_ONT_240418_AD'], 'aa861d819d56f13647f0232321a1960b'),
  ('SRR32748486', ARRAY['OG115H_D_SBL_PACB_240125_LA'], 'b3800811e599f862b875c6f75ffe2e46'),
  ('SRR32859499', ARRAY['OG2G_D_LSKL_ONT_240306_AD'], '4e0dc135d74ec0336ea6890be03d2c8a'),
  ('SRR32859501', ARRAY['OG3G_D_LSKL_ONT_230912_AD'], '0f83f15c3ff771f52ba3e675640a1321'),
  ('SRR32859502', ARRAY['OG10G_D_LSKL_ONT_230727_AD'], '5c1d35c17fcfdd533c2bd1daf05ca5db'),
  ('SRR32859503', ARRAY['OG12G_D_LSKL_ONT_240418_AD'], 'd27771ab4d9c78874bb2db567a8c25aa'),
  ('SRR32859585', ARRAY['OG1G_D_LSKL_ONT_240418_AD'], '16bc0f34ae7e53412a53beae15161bea'),
  ('SRR32859586', ARRAY['OG11G_D_LSKL_ONT_230912_AD'], '18d493fdc93a9cc9186b37a7beb4a222'),
  ('SRR32859706', ARRAY['OG36W_D_LSKL_ONT_230727_AD'], '94a6314d41ff9cc4f81b8189a555b795'),
  ('SRR32859707', ARRAY['OG15G_D_LSKL_ONT_230912_AD'], '437ea788b915a67768ca1aa0d7b34264'),
  ('SRR32859709', ARRAY['OG52G_D_LSKL_ONT_230912_AD'], 'd7d0e86b23515e834a948b75015adc8a'),
  ('SRR32860255', ARRAY['OG76G_D_LSKL_ONT_230912_AD'], '72dcf33859e29dc25f45694e6088e023'),
  ('SRR32860256', ARRAY['OG14G_D_LSKL_ONT_230912_AD'], '994d22265379ed987f14c2378f6ffcd6'),
  ('SRR32860257', ARRAY['OG88G_D_LSKL_ONT_230726_AD'], '23a9fab2441fd9a493f282636d713612'),
  ('SRR32860258', ARRAY['OG95H_D_LSKL_ONT_230726_AD'], '4d35b9a1bcc31326f303951b24cdf85d'),
  ('SRR32917540', ARRAY['OG910L-1_HICL_NOVA_241204_AD'], '4c9ed354ec7904a619f929fd9697315c'),
  ('SRR32917541', ARRAY['OG910H_D_SBL_PACB_241127_AD'], 'e9c22e4e9c4ddab16b3404271f03ff99'),
  ('SRR32917542', ARRAY['OG7G-1_HICL_NEXT_240423_AD'], 'cb8ac35ef0056eff01543aed042ff9e6'),
  ('SRR32917543', ARRAY['OG7G_D2_LSKL_ONT_240306_AD'], '925f0a0b3242c0cd52cd99e4b1db6de6'),
  ('SRR32917544', ARRAY['OG7G_D2_SBL_PACB_230915_LP'], '791ba6d5e11900c9891d2f26d7845421'),
  ('SRR32942155', ARRAY['OG787G-2_HICL_NOVA_241204_AD'], '7be306e788c5c14443bbae8d820289b8'),
  ('SRR32942156', ARRAY['OG787G_D_SBL_PACB_240927_LA'], 'fdd28e4a805f9c3174f951a20f656f28'),
  ('SRR32942157', ARRAY['OG755G-2_HICL_NOVA_241204_AD'], '8ed119662bd8d66160aecc64917ddbbb'),
  ('SRR32942158', ARRAY['OG755H_D_SBL_PACB_240821_AD'], '07b8937c3e1812f753215b81c011795c'),
  ('SRR32942159', ARRAY['OG637B-1_HICL2_NEXT_240423_AD', 'OG637B-1_HICL3_NEXT_240423_AD'], '11d786cee88fcbb84b6fd49c0397957e'),
  ('SRR32942160', ARRAY['OG637B_D7_LSKL_ONT_240819_AD', 'OG637B_D7_ULKL_ONT_240819_AD2'], 'c1338434b6bc50ac4a4bcfe3aee2ce45'),
  ('SRR32942161', ARRAY['OG637B_D3_SBL2_PACB_240206_AD', 'OG637B_D3_SBL_PACB_240206_AD'], '6e5e7d4cad0c56c62005cad395092a45'),
  ('SRR34136250', ARRAY['OG9G_D_LSKL_ONT_240306_AD'], 'c7dddd453465275fa7954d5d545d1e3f'),
  ('SRR34259960', ARRAY['OG695L-1_HICL_NOVA_240821_AD'], '6cc7ce832626f4b77fa531259d44a619'),
  ('SRR34259961', ARRAY['OG695H_D_SBL3_PACB_240520_LA'], 'cbcb8a4720e9e813f3b231257315c66a'),
  ('SRR34259962', ARRAY['OG657L-1_HICL_NOVA_240821_AD'], 'd6edb6f1063b0484a34d12a468cfbf35'),
  ('SRR34259963', ARRAY['OG657H_D_SBL_PACB_240501_AD'], 'c5c8288e36cacd57591b5a68c0b9e7b9'),
  ('SRR34259964', ARRAY['OG649L-1_HICL_NOVA_250312_LA'], '0672dca53c2282d62538139162bd9fcf'),
  ('SRR34259965', ARRAY['OG649H_D2_SBL2_PACB_240427_LA'], '940049347d5ec895363e5a5a5e8b617f'),
  ('SRR34259968', ARRAY['OG645L-1_HICL_NOVA_240613_LA'], 'ce000187d536ca64864cc5c4ed177cca'),
  ('SRR34259969', ARRAY['OG645H_D_SBL_PACB_240427_LA'], '2d14c56f276523954d20f44defbc6c0f'),
  ('SRR34562934', ARRAY['OG680L-2_HICL_NOVA_250312_LA'], 'f188ed47468e89e2a59844fadca81fa2'),
  ('SRR34562935', ARRAY['OG680G_D_SBL_PACB_241004_LA'], 'b4257ba0fb50f9307f381e88e46e66d7'),
  ('SRR34562936', ARRAY['OG665L-2_HICL_NOVA_250505_AD'], 'f9b518c314cc4ee13447b659eaf95b91'),
  ('SRR34562938', ARRAY['OG665H_D_SBL_PACB_240501_AD'], 'b4f6df96b8f64a791cae8808b44d309f');

CREATE TEMP TABLE sra_upload_unlinked (
    srr_accession  text NOT NULL,
    reason         text NOT NULL
) ON COMMIT DROP;
INSERT INTO sra_upload_unlinked VALUES
  ('ERR17798704', 'run not in sequencing (runs NOVA_240719_AD)'),
  ('ERR17798720', 'run not in sequencing (runs NOVA_240719_AD)'),
  ('ERR17885486', 'run not in sequencing (runs NOVA_250114_AD)'),
  ('ERR17885568', 'run not in sequencing (runs NOVA_250114_AD)'),
  ('ERR17889416', 'run not in sequencing (runs NOVA_250114_AD)'),
  ('ERR17889437', 'run not in sequencing (runs NOVA_250114_AD)'),
  ('ERR17889809', 'run not in sequencing (runs NOVA_250114_AD)'),
  ('ERR17889811', 'run not in sequencing (runs NOVA_250114_AD)'),
  ('SRR28678402', 'untraced: OG88L.230801.hic.R1.fastq.gz: staged copy matches 0 raw files by size; OG88L.230801.hic.R2.fastq.gz: staged copy matches 0 raw files by size'),
  ('SRR29368782', 'no row for library (runs NOVA_240501_LA)'),
  ('SRR29368783', 'no row for library (runs NOVA_240501_LA)'),
  ('SRR32372870', 'no filenames'),
  ('SRR32372871', 'no filenames'),
  ('SRR32372872', 'no filenames'),
  ('SRR32372873', 'no filenames'),
  ('SRR32372874', 'no filenames'),
  ('SRR32372875', 'no filenames'),
  ('SRR32638519', 'no row for library (runs NOVA_240501_LA)'),
  ('SRR32639459', 'run not in sequencing (runs NOVA_240719_AD)'),
  ('SRR32639463', 'run not in sequencing (runs NOVA_240719_AD)'),
  ('SRR32729624', 'run not in sequencing (runs ONT_240617_AD)'),
  ('SRR34168401', 'no filenames'),
  ('SRR34168402', 'no filenames'),
  ('SRR34168403', 'no filenames'),
  ('SRR34562937', 'untraced: OG665L-1_HICL_S5_L001_R1_001.fastq.gz: in 2 runs, sizes do not decide; OG665L-1_HICL_S5_L001_R2_001.fastq.gz: in 2 runs, sizes do not decide'),
  ('SRR34562950', 'no filenames'),
  ('SRR34562951', 'no filenames');

DO $backfill$
DECLARE
  n_links   bigint;
  n_stale   bigint;
  n_missing bigint;
  n_unl     bigint;
BEGIN
  INSERT INTO v4.ref_sra_upload_run (srr_accession, sequencing_id)
  SELECT l.srr_accession, sid
  FROM sra_upload_links l
  JOIN v4.ref_sra_upload u ON u.srr_accession = l.srr_accession AND md5(coalesce(u.filenames, '')) = l.filenames_md5
  CROSS JOIN LATERAL unnest(l.sequencing_ids) AS sid
  WHERE EXISTS (SELECT 1 FROM public.sequencing s WHERE s.sequencing_id = sid)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n_links = ROW_COUNT;

  SELECT count(*) INTO n_stale FROM sra_upload_links l
  WHERE NOT EXISTS (SELECT 1 FROM v4.ref_sra_upload u
                    WHERE u.srr_accession = l.srr_accession AND md5(coalesce(u.filenames, '')) = l.filenames_md5);
  SELECT count(*) INTO n_missing FROM sra_upload_links l CROSS JOIN LATERAL unnest(l.sequencing_ids) AS sid
  WHERE NOT EXISTS (SELECT 1 FROM public.sequencing s WHERE s.sequencing_id = sid);

  INSERT INTO v4.ref_sra_upload_unlinked (srr_accession, reason, reviewed_on)
  SELECT x.srr_accession, x.reason, DATE '2026-10-22' FROM sra_upload_unlinked x
  WHERE EXISTS (SELECT 1 FROM v4.ref_sra_upload u WHERE u.srr_accession = x.srr_accession)
    AND NOT EXISTS (SELECT 1 FROM v4.ref_sra_upload_run r WHERE r.srr_accession = x.srr_accession)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n_unl = ROW_COUNT;

  RAISE NOTICE '064: % links from the evidence; % uploads skipped (file names changed since); % sequencing rows '
    'no longer present; % uploads recorded as reviewed and unlinked', n_links, n_stale, n_missing, n_unl;
END
$backfill$;

-- Readiness ------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW v4.v_sra_upload_run_readiness AS
SELECT s.og_id, u.srr_accession, u.data_type,
       coalesce(x.reason, 'not resolved by the forward rule') AS reason,
       x.reviewed_on,
       left(u.filenames, 200) AS filenames
FROM v4.ref_sra_upload u
JOIN v4.ref_submission s USING (submission_id)
LEFT JOIN v4.ref_sra_upload_unlinked x USING (srr_accession)
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_sra_upload_run r WHERE r.srr_accession = u.srr_accession);
COMMENT ON VIEW v4.v_sra_upload_run_readiness IS
  'SRA uploads with no sequencing link, and why. Most are run IDs the workbook has wrong '
  '(064''s header); fix at source, delete the ref_sra_upload_unlinked row, and the sync links them.';

-- Sync and checks (window only) -----------------------------------------------------------------

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

-- Verify ---------------------------------------------------------------------------------------

SELECT * FROM v4.sync_ref_submission();  -- links any upload added since the evidence was taken

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v4.sync_ref_submission() LOOP
    IF r.changed <> 0 THEN
      RAISE EXCEPTION '064: the sync is not a no-op after the migration: % (%)', r.step, r.changed;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM v4.check_ref_submission() LOOP
    IF r.check_name LIKE 'note:%' THEN
      RAISE NOTICE '064 %: %', r.check_name, r.problems;
    ELSIF r.problems <> 0 THEN
      RAISE EXCEPTION '064 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
END
$verify$;

GRANT SELECT ON ALL TABLES IN SCHEMA v4 TO readonly;

COMMIT;
