-- 080_assembly_run_links.sql -- Keep mito_assembly_run and ref_assembly_run current, from triggers.
--
-- Backlog Highest 13 (found 2026-11-04 with 078; docs/r_rg_docs_record.md finding 1).
--
-- Both tables were derived by the window syncs: v3.sync_mito() (rule as 055 left it) and
-- v4.sync_ref() (rule as 069 left it). 072 and 073 dropped the syncs, and no pipeline writes
-- either table, so an assembly created after 2026-11-02 gets no run link. On 2026-11-09 that is
-- 2 mito assemblies (OG2375 ilmn 260514, OG853 hifi 250717), each with one run under the old rule;
-- no ref assembly has been created since 073.
--
-- The upkeep moves into the database, as 075 did for sequencing_run, not into the push scripts.
-- The sequencing row often arrives after the assembly: the lab enters the run in the workbook,
-- the nightly importer loads it, and only then can a link exist. A push-time writer would miss
-- those; the old syncs caught them every night.
--   - refresh_assembly_runs(og_ids, sequencing_ids) is the two syncs' run-link rules, restricted
--     to the assemblies of the OGs given and the links of the sequencing rows given.
--   - mito_assembly_runs_link / ref_assembly_runs_link (AFTER INSERT OR UPDATE OF the key, per
--     row) link a new or re-keyed assembly. The ref writers' upsert sets og_id = EXCLUDED.og_id on
--     every push (refdb.py), so an update that changes nothing is skipped.
--   - sequencing_assembly_runs_ins / _upd (AFTER, per statement, transition tables) re-derive for
--     inserted rows, and for updated rows whose library, status, technology, instrument or run
--     changed. The importer upserts every row every night; unchanged rows cost a join only.
--   - library_assembly_runs_upd does the same when a library's type or parent changes.
--   A deleted sequencing row or assembly takes its links with it (ON DELETE CASCADE, as before).
--
-- The two tables differ in what may be removed:
--   - mito: every link is derived (all 2,560 on 2026-11-09), so a link the rule no longer gives
--     is removed, as v3.sync_mito() did.
--   - ref: v_ref_assembly_run_readiness lists the 61 assemblies whose seq_date matches no run,
--     for someone to link by hand. A link is removed only when its row can no longer have one:
--     another OG, not PacBio/ONT/Hi-C DNA, or failed -- what ref_assembly_run_genomic_only refuses.
--
-- Not changed: the rules. Mito links include failed runs, unlike ref (owner decision 2026-11-09):
-- a mitogenome is assembled from one run, whatever came off it, while a reference genome pools
-- runs and 069 keeps a failed one out of the pool. So the 3 hifi assemblies dated 250704 (OG819,
-- OG852, OG853) keep their links to PACB_250704_AD. Not covered: a tissue moving to another OG,
-- or an extraction to another tissue, upstream of library. Run
-- refresh_assembly_runs(ARRAY(SELECT og_id FROM sample)) after such a fix.
--
-- Apply: the backfill refuses to run if it would remove any existing link (0 on 2026-11-09), so a
-- surprise is looked at before it is applied. Probes (rolled back) prove each trigger.
-- Replay: functions and triggers are replaced; the backfill is then a no-op.
-- Revert: sql/revert/080_assembly_run_links_revert.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.mito_run_matches(p_tech text, p_technology text,
                                                   p_library_type text, p_instrument text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
  -- 055: DNA libraries only; ilmn leaves out iSEQ QC runs.
  SELECT coalesce(CASE p_tech
    WHEN 'ilmn' THEN p_technology = 'Illumina' AND p_library_type = 'illumina'
                     AND p_instrument IS DISTINCT FROM 'iSEQ'
    WHEN 'hic'  THEN p_technology = 'Hi-C' AND p_library_type = 'hic'
    WHEN 'hifi' THEN p_technology LIKE 'PacBio%' AND p_library_type = 'pacbio'
  END, false)
$fn$;
COMMENT ON FUNCTION public.mito_run_matches(text, text, text, text) IS
  'Whether a sequencing row (technology, library_type, instrument) can be a run of a mito assembly '
  'of this tech. The rule of v3.sync_mito() as 055 left it. 080.';

CREATE OR REPLACE FUNCTION public.refresh_assembly_runs(p_og_ids text[],
                                                        p_sequencing_ids text[] DEFAULT '{}')
RETURNS void
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  -- Mito: every link is derived, so drop one the rule no longer gives.
  DELETE FROM mito_assembly_run r
   USING mito_assembly a
   WHERE a.assembly_id = r.assembly_id
     AND (a.og_id = ANY (p_og_ids) OR r.sequencing_id = ANY (p_sequencing_ids))
     AND NOT EXISTS (SELECT 1 FROM v_sequencing_browse s
                      WHERE s.sequencing_id = r.sequencing_id
                        AND s.og_id = a.og_id AND s.seq_date = a.seq_date
                        AND mito_run_matches(a.tech, s.technology, s.library_type, s.instrument));

  INSERT INTO mito_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT a.assembly_id, s.sequencing_id
    FROM mito_assembly a
    JOIN v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
   WHERE a.og_id = ANY (p_og_ids)
     AND mito_run_matches(a.tech, s.technology, s.library_type, s.instrument)
  ON CONFLICT DO NOTHING;

  -- Ref: a link may have been chosen by hand, so drop only one its row can no longer have
  -- (what ref_assembly_run_genomic_only refuses, or another OG's row).
  DELETE FROM ref_assembly_run r
   USING ref_assembly a
   WHERE a.assembly_id = r.assembly_id
     AND (a.og_id = ANY (p_og_ids) OR r.sequencing_id = ANY (p_sequencing_ids))
     AND NOT EXISTS (SELECT 1 FROM v_sequencing_browse s
                      WHERE s.sequencing_id = r.sequencing_id AND s.og_id = a.og_id
                        AND s.technology IN ('PacBio HIFI', 'PacBio', 'ONT', 'Hi-C')
                        AND s.library_type IN ('pacbio', 'ont', 'hic')
                        AND s.status IS DISTINCT FROM 'Failed');

  -- 069: a failed run produced no reads to build from.
  INSERT INTO ref_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT a.assembly_id, s.sequencing_id
    FROM ref_assembly a
    JOIN v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
   WHERE a.og_id = ANY (p_og_ids)
     AND s.technology IN ('PacBio HIFI', 'PacBio', 'ONT') AND s.library_type IN ('pacbio', 'ont')
     AND s.status IS DISTINCT FROM 'Failed'
  ON CONFLICT DO NOTHING;
END
$fn$;
COMMENT ON FUNCTION public.refresh_assembly_runs(text[], text[]) IS
  'Re-derive mito_assembly_run and ref_assembly_run for the assemblies of the OGs given and the links '
  'of the sequencing rows given: the run-link rules of v3.sync_mito() (055) and v4.sync_ref() (069). '
  'Mito links the rule no longer gives are removed; a ref link only when its row can no longer have '
  'one, so links chosen by hand stay. Called by triggers on mito_assembly, ref_assembly, sequencing '
  'and library. 080.';

CREATE OR REPLACE FUNCTION public.mito_assembly_runs_link() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  IF TG_OP = 'INSERT'
     OR (NEW.og_id, NEW.tech, NEW.seq_date) IS DISTINCT FROM (OLD.og_id, OLD.tech, OLD.seq_date) THEN
    PERFORM refresh_assembly_runs(ARRAY[NEW.og_id]);
  END IF;
  RETURN NULL;
END
$fn$;
COMMENT ON FUNCTION public.mito_assembly_runs_link() IS
  'Links a new or re-keyed mito assembly to its runs (refresh_assembly_runs). 080.';

CREATE OR REPLACE FUNCTION public.ref_assembly_runs_link() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  -- The ref writers' upsert sets og_id = EXCLUDED.og_id on every push; that changes nothing.
  IF TG_OP = 'INSERT'
     OR (NEW.og_id, NEW.seq_date) IS DISTINCT FROM (OLD.og_id, OLD.seq_date) THEN
    PERFORM refresh_assembly_runs(ARRAY[NEW.og_id]);
  END IF;
  RETURN NULL;
END
$fn$;
COMMENT ON FUNCTION public.ref_assembly_runs_link() IS
  'Links a new or re-keyed reference assembly to its runs (refresh_assembly_runs). 080.';

CREATE OR REPLACE FUNCTION public.sequencing_assembly_runs() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
DECLARE
  ids text[];
BEGIN
  -- As in sequencing_run_refresh(), a branch naming a transition table this trigger does not have
  -- is never planned.
  IF TG_OP = 'INSERT' THEN
    ids := ARRAY(SELECT sequencing_id FROM new_rows);
  ELSE
    ids := ARRAY(SELECT n.sequencing_id
                   FROM new_rows n JOIN old_rows o USING (sequencing_id)
                  WHERE (n.library_tube_id, n.status, n.technology, n.instrument, n.run_id)
                        IS DISTINCT FROM (o.library_tube_id, o.status, o.technology, o.instrument, o.run_id));
  END IF;
  IF cardinality(ids) > 0 THEN
    PERFORM refresh_assembly_runs(
      ARRAY(SELECT DISTINCT b.og_id FROM sequencing q JOIN v_library_browse b USING (library_tube_id)
             WHERE q.sequencing_id = ANY (ids)),
      ids);
  END IF;
  RETURN NULL;
END
$fn$;
COMMENT ON FUNCTION public.sequencing_assembly_runs() IS
  'Statement-level: re-derives assembly run links for the sequencing rows a statement inserted, or '
  'changed in library, status, technology, instrument or run. 080.';

CREATE OR REPLACE FUNCTION public.library_assembly_runs() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
DECLARE
  tubes text[];
BEGIN
  tubes := ARRAY(SELECT n.library_tube_id
                   FROM new_rows n JOIN old_rows o USING (library_tube_id)
                  WHERE (n.library_type, n.dna_id, n.rna_id, n.lysate_id)
                        IS DISTINCT FROM (o.library_type, o.dna_id, o.rna_id, o.lysate_id));
  IF cardinality(tubes) > 0 THEN
    PERFORM refresh_assembly_runs(
      ARRAY(SELECT DISTINCT og_id FROM v_library_browse WHERE library_tube_id = ANY (tubes)),
      ARRAY(SELECT sequencing_id FROM sequencing WHERE library_tube_id = ANY (tubes)));
  END IF;
  RETURN NULL;
END
$fn$;
COMMENT ON FUNCTION public.library_assembly_runs() IS
  'Statement-level: re-derives assembly run links for the sequencing rows of libraries whose type or '
  'parent a statement changed. 080.';

DROP TRIGGER IF EXISTS mito_assembly_runs_link ON mito_assembly;
CREATE TRIGGER mito_assembly_runs_link AFTER INSERT OR UPDATE OF og_id, tech, seq_date ON mito_assembly
  FOR EACH ROW EXECUTE FUNCTION mito_assembly_runs_link();
DROP TRIGGER IF EXISTS ref_assembly_runs_link ON ref_assembly;
CREATE TRIGGER ref_assembly_runs_link AFTER INSERT OR UPDATE OF og_id, seq_date ON ref_assembly
  FOR EACH ROW EXECUTE FUNCTION ref_assembly_runs_link();
DROP TRIGGER IF EXISTS sequencing_assembly_runs_ins ON sequencing;
CREATE TRIGGER sequencing_assembly_runs_ins AFTER INSERT ON sequencing
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION sequencing_assembly_runs();
DROP TRIGGER IF EXISTS sequencing_assembly_runs_upd ON sequencing;
CREATE TRIGGER sequencing_assembly_runs_upd AFTER UPDATE ON sequencing
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION sequencing_assembly_runs();
DROP TRIGGER IF EXISTS library_assembly_runs_upd ON library;
CREATE TRIGGER library_assembly_runs_upd AFTER UPDATE ON library
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION library_assembly_runs();

COMMENT ON TABLE mito_assembly_run IS
  'The sequencing rows (a library on a run) an assembly was built from, derived from (og_id, seq_date) '
  'and tech; ilmn excludes iSEQ QC runs. Kept current by refresh_assembly_runs() from triggers on '
  'mito_assembly, sequencing and library (080); a link the rule no longer gives is removed.';
COMMENT ON TABLE ref_assembly_run IS
  'The sequencing rows an assembly was built from: PacBio/ONT DNA, and Hi-C once writers record it '
  '(trigger). Links to the OG''s non-failed PacBio/ONT rows of the assembly''s seq_date are kept current '
  'by refresh_assembly_runs() from triggers on ref_assembly, sequencing and library (080). A link '
  'chosen by hand stays until its row can no longer have one.';
COMMENT ON VIEW v_ref_assembly_run_readiness IS
  'Assemblies with no run link, and the OG''s PacBio/ONT DNA rows to choose from. Their seq_date '
  'matches no run date (RG.0 §1.5), so refresh_assembly_runs() (080) cannot derive one: link them '
  'by hand, or fix the date.';

DO $a$
DECLARE
  mito_drop bigint;
  ref_drop  bigint;
  before_m  bigint := (SELECT count(*) FROM mito_assembly_run);
  before_r  bigint := (SELECT count(*) FROM ref_assembly_run);
  src       record;
  n         bigint;
BEGIN
  -- Links the backfill would remove. Expected 0; anything else is looked at before applying.
  SELECT count(*) INTO mito_drop
    FROM mito_assembly_run r JOIN mito_assembly a USING (assembly_id)
   WHERE NOT EXISTS (SELECT 1 FROM v_sequencing_browse s
                      WHERE s.sequencing_id = r.sequencing_id AND s.og_id = a.og_id AND s.seq_date = a.seq_date
                        AND mito_run_matches(a.tech, s.technology, s.library_type, s.instrument));
  SELECT count(*) INTO ref_drop
    FROM ref_assembly_run r JOIN ref_assembly a USING (assembly_id)
   WHERE NOT EXISTS (SELECT 1 FROM v_sequencing_browse s
                      WHERE s.sequencing_id = r.sequencing_id AND s.og_id = a.og_id
                        AND s.technology IN ('PacBio HIFI', 'PacBio', 'ONT', 'Hi-C')
                        AND s.library_type IN ('pacbio', 'ont', 'hic')
                        AND s.status IS DISTINCT FROM 'Failed');
  IF mito_drop + ref_drop > 0 THEN
    RAISE EXCEPTION '080: the backfill would remove % mito and % ref run link(s); look at them first',
      mito_drop, ref_drop;
  END IF;

  PERFORM refresh_assembly_runs(ARRAY(SELECT og_id FROM sample));
  RAISE NOTICE '080: backfill added % mito and % ref run link(s)',
    (SELECT count(*) FROM mito_assembly_run) - before_m, (SELECT count(*) FROM ref_assembly_run) - before_r;

  -- Probes, inside a sub-block that is always rolled back.
  BEGIN
    -- 1. A new mito assembly gets the links of an existing one with the same key but another code.
    SELECT a.og_id, a.tech, a.seq_date, count(*) AS links INTO src
      FROM mito_assembly a JOIN mito_assembly_run r USING (assembly_id)
     GROUP BY a.assembly_id ORDER BY a.assembly_id DESC LIMIT 1;
    INSERT INTO mito_assembly (og_id, tech, seq_date, code) VALUES (src.og_id, src.tech, src.seq_date, 'probe080');
    SELECT count(*) INTO n FROM mito_assembly_run r JOIN mito_assembly a USING (assembly_id) WHERE a.code = 'probe080';
    IF n <> src.links THEN
      RAISE EXCEPTION '080 probe: new mito assembly got % run link(s), expected %', n, src.links;
    END IF;

    -- 2. A new ref assembly gets the links of an existing one with the same (og_id, seq_date).
    SELECT a.og_id, a.seq_date, count(*) AS links INTO src
      FROM ref_assembly a JOIN ref_assembly_run r USING (assembly_id)
     GROUP BY a.assembly_id ORDER BY a.assembly_id DESC LIMIT 1;
    INSERT INTO ref_assembly (og_id, seq_date, version) VALUES (src.og_id, src.seq_date, 'hifi9080');
    SELECT count(*) INTO n FROM ref_assembly_run r JOIN ref_assembly a USING (assembly_id)
     WHERE a.og_id = src.og_id AND a.version = 'hifi9080';
    IF n <> src.links THEN
      RAISE EXCEPTION '080 probe: new ref assembly got % run link(s), expected %', n, src.links;
    END IF;
    -- The ref writers' no-op upsert leaves the links alone.
    UPDATE ref_assembly SET og_id = og_id WHERE og_id = src.og_id AND version = 'hifi9080';

    -- 3. A sequencing row that arrives after the assembly is linked to it: copy a row of the probe
    -- ref assembly's run under a new ID.
    INSERT INTO sequencing (sequencing_id, library_tube_id, status, technology, instrument, run_date, run_id)
    SELECT 'PROBE080_' || q.sequencing_id, q.library_tube_id, q.status, q.technology, q.instrument, q.run_date, q.run_id
      FROM ref_assembly_run r JOIN ref_assembly a USING (assembly_id) JOIN sequencing q USING (sequencing_id)
     WHERE a.og_id = src.og_id AND a.version = 'hifi9080'
     LIMIT 1;
    SELECT count(*) INTO n FROM ref_assembly_run r JOIN ref_assembly a USING (assembly_id)
     WHERE a.og_id = src.og_id AND a.version = 'hifi9080' AND r.sequencing_id LIKE 'PROBE080\_%';
    IF n <> 1 THEN
      RAISE EXCEPTION '080 probe: a late sequencing row got % ref link(s), expected 1', n;
    END IF;

    -- 4. The row then fails: its ref links go.
    UPDATE sequencing SET status = 'Failed' WHERE sequencing_id LIKE 'PROBE080\_%';
    SELECT count(*) INTO n FROM ref_assembly_run WHERE sequencing_id LIKE 'PROBE080\_%';
    IF n <> 0 THEN
      RAISE EXCEPTION '080 probe: % ref link(s) to a failed row survived', n;
    END IF;

    -- 5. A mito link goes when its row stops matching the assembly's tech.
    SELECT r.sequencing_id INTO src FROM mito_assembly_run r JOIN mito_assembly a USING (assembly_id)
     WHERE a.code = 'probe080' LIMIT 1;
    UPDATE sequencing SET technology = 'PROBE080' WHERE sequencing_id = src.sequencing_id;
    SELECT count(*) INTO n FROM mito_assembly_run WHERE sequencing_id = src.sequencing_id;
    IF n <> 0 THEN
      RAISE EXCEPTION '080 probe: % mito link(s) to a non-matching row survived', n;
    END IF;

    RAISE EXCEPTION USING ERRCODE = 'P0080', MESSAGE = 'probes passed';
  EXCEPTION
    WHEN SQLSTATE 'P0080' THEN
      NULL;
  END;

  RAISE NOTICE '080: run-link triggers in place; probes passed';
END
$a$;

COMMIT;
