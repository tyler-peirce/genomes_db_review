-- 065_v4_sra_hicl1_alias.sql -- Phase RG: a Hi-C file named ..._HICL1 is the library ..._HICL.
--
-- Why. Owner, 2026-10-22: "HICL1 are the HICL files". Sample sheets named a tube's first Hi-C
-- library HICL1; the workbook calls it HICL, and no workbook tube ends in HICL1. 064's evidence and
-- resolver matched the library_tube_id literally, so three uploads were short of a link:
--   SRR29368783  OG706L-7_HICL1 files -> OG706L-7_HICL_NOVA_240501_LA   (was unlinked)
--   SRR29368782  OG706L-8_HICL1 files -> OG706L-8_HICL_NOVA_240501_LA   (was unlinked)
--   SRR32942159  OG637B-1_HICL1/2/3   -> adds OG637B-1_HICL_NEXT_240423_AD beside HICL2 and HICL3
-- The run (NOVA_240501_LA, NEXT_240423_AD) is 064's evidence, unchanged. Re-running
-- scripts/match_sra_uploads.py with the alias changes exactly these three uploads
-- (sql/data/065_sra_upload_runs.tsv).
--
-- How. Replace v4.resolve_sra_upload_runs() so it reads HICL1 as HICL in file names (064's text
-- otherwise unchanged); remove the two uploads from ref_sra_upload_unlinked; add the three links,
-- only where each upload's file names are unchanged (md5). Assert the sync is a no-op after.
--
-- Revert: sql/revert/065_v4_sra_hicl1_alias_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_sra_upload_run') IS NULL THEN
    RAISE EXCEPTION '065 needs v4.ref_sra_upload_run from 064';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION v4.resolve_sra_upload_runs(p_og_id text, p_data_type text, p_filenames text)
RETURNS SETOF text LANGUAGE plpgsql STABLE SET search_path = v4, public, pg_temp AS $fn$
DECLARE
  -- File names call a tube's first Hi-C library HICL1; the workbook calls it HICL (065).
  files text[] := ARRAY(SELECT regexp_replace(btrim(f), '_HICL1(?=[_.])', '_HICL', 'g')
                        FROM unnest(string_to_array(coalesce(p_filenames, ''), ',')) f
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
  'The sequencing rows an SRA upload''s file names point to (064''s forward rule; HICL1 = HICL, 065). Used by the v4 '
  'sync and by ENA-ref-genomes step 09. Re-point search_path to public at RG.6.';

DO $links$
DECLARE
  n bigint;
BEGIN
  DELETE FROM v4.ref_sra_upload_unlinked WHERE srr_accession IN ('SRR29368782', 'SRR29368783');
  INSERT INTO v4.ref_sra_upload_run (srr_accession, sequencing_id)
  SELECT v.srr, v.sid
  FROM (VALUES ('SRR29368783', 'OG706L-7_HICL_NOVA_240501_LA', '651e33236013a8a20e14811f8074f7d8'),
               ('SRR29368782', 'OG706L-8_HICL_NOVA_240501_LA', 'c56d4e245cc0367530093d13fce8589f'),
               ('SRR32942159', 'OG637B-1_HICL_NEXT_240423_AD', '11d786cee88fcbb84b6fd49c0397957e')) AS v (srr, sid, md5)
  JOIN v4.ref_sra_upload u ON u.srr_accession = v.srr AND md5(coalesce(u.filenames, '')) = v.md5
  WHERE EXISTS (SELECT 1 FROM public.sequencing s WHERE s.sequencing_id = v.sid)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  -- Idempotent: on a replay the links are already there, so check presence, not inserts.
  IF (SELECT count(*) FROM v4.ref_sra_upload_run
      WHERE (srr_accession, sequencing_id) IN (('SRR29368783', 'OG706L-7_HICL_NOVA_240501_LA'),
                                               ('SRR29368782', 'OG706L-8_HICL_NOVA_240501_LA'),
                                               ('SRR32942159', 'OG637B-1_HICL_NEXT_240423_AD'))) <> 3 THEN
    RAISE EXCEPTION '065: the 3 links are not all present; an upload''s file names or a sequencing row changed';
  END IF;
  RAISE NOTICE '065: % of 3 links added now; % SRA uploads linked',
    n, (SELECT count(DISTINCT srr_accession) FROM v4.ref_sra_upload_run);
END
$links$;

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v4.sync_ref_submission() LOOP
    IF r.changed <> 0 THEN
      RAISE EXCEPTION '065: the sync is not a no-op after the migration: % (%)', r.step, r.changed;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM v4.check_ref_submission() LOOP
    IF r.check_name NOT LIKE 'note:%' AND r.problems <> 0 THEN
      RAISE EXCEPTION '065 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
END
$verify$;

COMMIT;
