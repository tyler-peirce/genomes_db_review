-- 049_remove_hic_draft_genomes.sql -- delete the 15 draft genomes assembled from Hi-C reads.
--
-- Why. draft_genomes rows with seq_date 251118 (OG40, OG55, OG56, OG57, OG58, OG61, OG64,
-- OG70, OG72, OG758, OG770, OG784, OG81, OG834, OG96) were built from run NEXT_251118_AD, which
-- carries nothing but 15 shallow Hi-C libraries (_HICL, NextSeq, hic_depth 'Shallow'). A draft
-- genome is a shotgun Illumina assembly; these are not. On live, 2026-10-16:
--   - assembly length 0.6-99 Mb against a median of 829 Mb for the other drafts;
--   - BUSCO complete 0.0-1.1% against a median of 56.1%; GenomeScope sizes 0.1-3.2 Mb;
--   - no SRA, BioSample, ERZ or GCA accession on any of them, so nothing was submitted.
-- 14 of the 15 samples have reference-genome rows, and 6 also have a real Illumina draft on an
-- earlier date. Owner decision 2026-10-16: remove them. docs/assembly_relations_plan.md §2.2.
--
-- What was rejected. Flagging them in place: draft_genomes has no column to flag with, and
-- Phase R replaces the table anyway. Deleting by seq_date alone: a future run on 251118 of a
-- real Illumina library would be caught too. So the keys are listed, and each is re-checked.
--
-- Guards, in order, all before anything is deleted:
--   1. Opt-in. Refuses unless PGOPTIONS carries the row count this file expects:
--        PGOPTIONS="-c oceanomics.remove_hic_draft_genomes=15" bin/apply_migrations.py
--   2. Each listed draft must still be built only from Hi-C: at least one sequencing row on its
--      (og_id, seq_date), and none that is not Hi-C. A listed draft with an Illumina run is a
--      real draft, and the file refuses.
--   3. The 15 rows must be byte-identical to the ones archived on 2026-10-16 (md5 below), which
--      is what makes the revert exact. If a writer has touched them since, re-export first.
--
-- Archive. archive/draft_genomes_hic_251118/ (CSV and SHA256SUMS), and the revert file itself
-- re-inserts the exact rows.
--
-- Not done here, and worth knowing. The draft-genome writers are not in either repository
-- (plan §2.2). If the draft pipeline re-pushes these assemblies they come back; stop it at
-- source. Phase R (plan §4.1) proposes rejecting a Hi-C library as draft input at write time.
--
-- Replay: once the rows are gone the guards are skipped and the DELETE matches nothing.
--
-- Revert: sql/revert/049_remove_hic_draft_genomes_revert.sql.

BEGIN;

CREATE TEMP TABLE hic_draft_keys (og_id text, seq_date text) ON COMMIT DROP;
INSERT INTO hic_draft_keys VALUES
  ('OG40', '251118'), ('OG55', '251118'), ('OG56', '251118'), ('OG57', '251118'),
  ('OG58', '251118'), ('OG61', '251118'), ('OG64', '251118'), ('OG70', '251118'),
  ('OG72', '251118'), ('OG758', '251118'), ('OG770', '251118'), ('OG784', '251118'),
  ('OG81', '251118'), ('OG834', '251118'), ('OG96', '251118');

DO $guard$
DECLARE
  present  int;
  bad      text;
  checksum text;
BEGIN
  SELECT count(*) INTO present
  FROM public.draft_genomes d JOIN hic_draft_keys k USING (og_id, seq_date);
  IF present = 0 THEN
    RETURN;  -- already removed; replay
  END IF;

  IF coalesce(current_setting('oceanomics.remove_hic_draft_genomes', true), '') <> '15' THEN
    RAISE EXCEPTION 'This deletes the 15 Hi-C draft genomes (% still present). Run with '
      'PGOPTIONS="-c oceanomics.remove_hic_draft_genomes=15"', present;
  END IF;
  IF present <> 15 THEN
    RAISE EXCEPTION 'Expected 15 Hi-C draft genomes, found %; some were already removed or '
      'renamed. Investigate before deleting the rest.', present;
  END IF;

  SELECT string_agg(k.og_id, ', ' ORDER BY k.og_id) INTO bad
  FROM hic_draft_keys k
  WHERE NOT EXISTS (SELECT 1 FROM public.v_sequencing_browse s
                    WHERE s.og_id = k.og_id AND s.seq_date = k.seq_date AND s.technology = 'Hi-C')
     OR EXISTS (SELECT 1 FROM public.v_sequencing_browse s
                WHERE s.og_id = k.og_id AND s.seq_date = k.seq_date
                  AND s.technology IS DISTINCT FROM 'Hi-C');
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'Not built only from Hi-C any more, so not deleted: %', bad;
  END IF;

  SELECT md5(string_agg(to_jsonb(d)::text, E'\n' ORDER BY d.og_id)) INTO checksum
  FROM public.draft_genomes d JOIN hic_draft_keys k USING (og_id, seq_date);
  IF checksum <> 'ee48835d1d3e2282dd4ed107be07b2a2' THEN
    RAISE EXCEPTION 'The 15 rows changed since they were archived on 2026-10-16 (md5 %), so the '
      'revert would not restore them. Re-export and update this file and its revert.', checksum;
  END IF;
END
$guard$;

DELETE FROM public.draft_genomes d
USING hic_draft_keys k
WHERE d.og_id = k.og_id AND d.seq_date = k.seq_date;

DO $verify$
BEGIN
  IF EXISTS (SELECT 1 FROM public.draft_genomes d JOIN hic_draft_keys k USING (og_id, seq_date)) THEN
    RAISE EXCEPTION 'Hi-C draft genomes still present after the delete';
  END IF;
END
$verify$;

COMMIT;
