-- 069_v4_failed_runs.sql -- Phase RG: run links skip failed runs, and the links the workbook
-- fixes of 2026-10-22 unblocked are made.
--
-- Why. The lab's corrections (docs/lab_note_run_ids_261022.md) reached sequencing with the
-- 2026-10-22 18:00 UTC import: NOVA_240719_AD, NOVA_250114_AD and PACB_250717_AD now hold their
-- libraries, OG650 has its NOVA_240501_LA row, and nine rows carry status = 'Failed' (owner, after
-- their comments said FAIL): the eight Plate 2 libraries of PACB_250704_AD, whose data folder holds
-- Plate 1 only, and OG107's top-up on NOVA_250522_AD. Until now every row was 'Sequenced', so the
-- v4 rules matched failed rows as if they held reads: OG819, OG852 and OG853's read sets and four
-- assembly links (OG819 250704.hic2, OG56 250704.hifi1/.hic1, OG73 250704.hic1) point at them.
--
-- How.
--   1. Every v4 run-matching rule skips status = 'Failed': the assembly-run step of
--      v4.sync_ref_assembly(), resolve_sra_upload_runs(), and the two readiness views. The
--      ref_assembly_run and ref_read_set_run triggers refuse a failed row. Read-QC rows keep their
--      link: QC of a failed cell describes that cell.
--   2. Read sets, from scripts/match_read_sets.py re-run on 2026-10-30 against sequencing without
--      failed rows (sql/data/069_read_set_dates.tsv); a row changes only where its GenomeScope
--      genomesize is unchanged since:
--        OG73   undated -> 250307   its only successful PacBio run (no Acacia reads; 250704 failed)
--        OG804  260522 + 250717     its 250717 movie now has a sequencing row
--        OG819, OG852, OG853  250704 -> 250717   their reads are on 250717; 250704 failed
--   3. SRA uploads, from scripts/match_sra_uploads.py re-run the same way
--      (sql/data/069_sra_upload_runs.tsv): the 11 uploads on the corrected runs leave
--      ref_sra_upload_unlinked with their link (OG8, OG105, OG759 on NOVA_240719_AD; OG676, OG678,
--      OG683 on NOVA_250114_AD; OG650 on NOVA_240501_LA). No existing link changes.
--   4. The sync then drops the four assembly links to failed rows. Those assemblies keep no link:
--      their version date names the failed run, so the date rule finds nothing; they are listed by
--      v_ref_assembly_run_readiness. OG819's 250704.hic2 was built from 250717 reads (the only ones
--      it has); that label is the owner's to fix (rename or re-stage), not a link to fake here.
--
-- Not here: v3.mito_assembly_run has 3 links to failed rows; the mito tables belong to the R.6 merge.
-- The samplesheet builders and refdb.read_set_runs() skip failed rows in their own repos.
--
-- Revert: sql/revert/069_v4_failed_runs_revert.sql.

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('v4.ref_read_set_run') IS NULL OR to_regclass('v4.ref_sra_upload_run') IS NULL THEN
    RAISE EXCEPTION '069 needs v4 read sets (062) and SRA links (064)';
  END IF;
  IF (SELECT count(*) FROM public.sequencing WHERE status = 'Failed') < 9 THEN
    RAISE EXCEPTION '069 expects the nine failed rows of the 2026-10-22 workbook in sequencing';
  END IF;
END
$pre$;

-- 1. Rules skip failed runs --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION v4.ref_assembly_run_genomic_only() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  tech  text;
  ltype text;
  st    text;
BEGIN
  SELECT s.technology, s.library_type, s.status INTO tech, ltype, st
  FROM public.v_sequencing_browse s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS NULL OR tech NOT IN ('PacBio HIFI', 'PacBio', 'ONT', 'Hi-C')
     OR ltype IS NULL OR ltype NOT IN ('pacbio', 'ont', 'hic') THEN
    RAISE EXCEPTION 'ref_assembly_run: % is % / % sequencing; a reference assembly is built from '
      'PacBio, ONT or Hi-C DNA libraries', NEW.sequencing_id, coalesce(tech, 'unknown'), coalesce(ltype, 'unknown');
  END IF;
  IF st = 'Failed' THEN  -- 069
    RAISE EXCEPTION 'ref_assembly_run: % is a failed run (sequencing.status); an assembly is not built from it',
      NEW.sequencing_id;
  END IF;
  RETURN NEW;
END
$fn$;

CREATE OR REPLACE FUNCTION v4.ref_read_set_run_pacbio_only() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  tech  text;
  ltype text;
  st    text;
BEGIN
  SELECT s.technology, s.library_type, s.status INTO tech, ltype, st
  FROM public.v_sequencing_browse s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS NULL OR tech NOT IN ('PacBio HIFI', 'PacBio') OR ltype IS DISTINCT FROM 'pacbio' THEN
    RAISE EXCEPTION 'ref_read_set_run: % is % / % sequencing; a HiFi read set is PacBio DNA',
      NEW.sequencing_id, coalesce(tech, 'unknown'), coalesce(ltype, 'unknown');
  END IF;
  IF st = 'Failed' THEN  -- 069
    RAISE EXCEPTION 'ref_read_set_run: % is a failed run (sequencing.status); it has no reads', NEW.sequencing_id;
  END IF;
  RETURN NEW;
END
$fn$;

CREATE OR REPLACE FUNCTION v4.sync_ref_assembly() RETURNS TABLE (step text, changed bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp SET client_min_messages = warning AS $fn$
DECLARE
  n bigint;
BEGIN
  DROP TABLE IF EXISTS pg_temp.sync_ref_src, pg_temp.sync_ref_src_k, pg_temp.sync_ref_run_want;
  CREATE TEMP TABLE sync_ref_src ON COMMIT DROP AS
    SELECT * FROM v4.sync_ref_genomes_source WHERE key_problem IS NULL AND NOT is_empty;

  DELETE FROM v4.ref_assembly a
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src s WHERE (s.og_id, s.seq_date, s.version) = (a.og_id, a.seq_date, a.version));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_assembly (og_id, seq_date, version)
  SELECT DISTINCT og_id, seq_date, version FROM sync_ref_src
  ON CONFLICT (og_id, seq_date, version) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly inserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_assembly_part p USING v4.ref_assembly a
  WHERE p.assembly_id = a.assembly_id
    AND NOT EXISTS (SELECT 1 FROM sync_ref_src s
                    WHERE (s.og_id, s.seq_date, s.version, s.stage, s.haplotype) = (a.og_id, a.seq_date, a.version, p.stage, p.haplotype));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'part deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_assembly_part (assembly_id, stage, haplotype)
  SELECT a.assembly_id, s.stage, s.haplotype FROM sync_ref_src s JOIN v4.ref_assembly a USING (og_id, seq_date, version)
  ON CONFLICT (assembly_id, stage, haplotype) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'part inserted'; changed := n; RETURN NEXT;

  CREATE TEMP TABLE sync_ref_src_k ON COMMIT DROP AS
    SELECT p.part_id, s.* FROM sync_ref_src s
    JOIN v4.ref_assembly a USING (og_id, seq_date, version)
    JOIN v4.ref_assembly_part p ON (p.assembly_id, p.stage, p.haplotype) = (a.assembly_id, s.stage, s.haplotype);

  DELETE FROM v4.ref_gfastats t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.num_contigs, s.contig_n50, s.contig_n50_size_mb, s.num_scaffolds, s.scaffold_n50, s.scaffold_n50_size_mb, s.largest_scaffold, s.largest_scaffold_size_mb, s.total_scaffold_length, s.total_scaffold_length_size_mb, s.gc_content_percent, s.num_gaps) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_gfastats deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_gfastats AS t (part_id, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, num_gaps)
  SELECT s.part_id, s.num_contigs, s.contig_n50, s.contig_n50_size_mb, s.num_scaffolds, s.scaffold_n50, s.scaffold_n50_size_mb, s.largest_scaffold, s.largest_scaffold_size_mb, s.total_scaffold_length, s.total_scaffold_length_size_mb, s.gc_content_percent, s.num_gaps FROM sync_ref_src_k s WHERE num_nonnulls(s.num_contigs, s.contig_n50, s.contig_n50_size_mb, s.num_scaffolds, s.scaffold_n50, s.scaffold_n50_size_mb, s.largest_scaffold, s.largest_scaffold_size_mb, s.total_scaffold_length, s.total_scaffold_length_size_mb, s.gc_content_percent, s.num_gaps) > 0
  ON CONFLICT (part_id) DO UPDATE SET num_contigs = EXCLUDED.num_contigs, contig_n50 = EXCLUDED.contig_n50, contig_n50_size_mb = EXCLUDED.contig_n50_size_mb, num_scaffolds = EXCLUDED.num_scaffolds, scaffold_n50 = EXCLUDED.scaffold_n50, scaffold_n50_size_mb = EXCLUDED.scaffold_n50_size_mb, largest_scaffold = EXCLUDED.largest_scaffold, largest_scaffold_size_mb = EXCLUDED.largest_scaffold_size_mb, total_scaffold_length = EXCLUDED.total_scaffold_length, total_scaffold_length_size_mb = EXCLUDED.total_scaffold_length_size_mb, gc_content_percent = EXCLUDED.gc_content_percent, num_gaps = EXCLUDED.num_gaps, loaded_at = now()
    WHERE (t.num_contigs, t.contig_n50, t.contig_n50_size_mb, t.num_scaffolds, t.scaffold_n50, t.scaffold_n50_size_mb, t.largest_scaffold, t.largest_scaffold_size_mb, t.total_scaffold_length, t.total_scaffold_length_size_mb, t.gc_content_percent, t.num_gaps) IS DISTINCT FROM (EXCLUDED.num_contigs, EXCLUDED.contig_n50, EXCLUDED.contig_n50_size_mb, EXCLUDED.num_scaffolds, EXCLUDED.scaffold_n50, EXCLUDED.scaffold_n50_size_mb, EXCLUDED.largest_scaffold, EXCLUDED.largest_scaffold_size_mb, EXCLUDED.total_scaffold_length, EXCLUDED.total_scaffold_length_size_mb, EXCLUDED.gc_content_percent, EXCLUDED.num_gaps);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_gfastats upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_busco t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.dataset, s.complete, s.single_copy, s.multi_copy, s.fragmented, s.missing, s.n_markers, s.internal_stop_codon_percent, s.scaffold_n50_bus, s.contigs_n50_bus, s.percent_gaps, s.number_of_scaffolds) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_busco deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_busco AS t (part_id, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds)
  SELECT s.part_id, s.dataset, s.complete, s.single_copy, s.multi_copy, s.fragmented, s.missing, s.n_markers, s.internal_stop_codon_percent, s.scaffold_n50_bus, s.contigs_n50_bus, s.percent_gaps, s.number_of_scaffolds FROM sync_ref_src_k s WHERE num_nonnulls(s.dataset, s.complete, s.single_copy, s.multi_copy, s.fragmented, s.missing, s.n_markers, s.internal_stop_codon_percent, s.scaffold_n50_bus, s.contigs_n50_bus, s.percent_gaps, s.number_of_scaffolds) > 0
  ON CONFLICT (part_id) DO UPDATE SET dataset = EXCLUDED.dataset, complete = EXCLUDED.complete, single_copy = EXCLUDED.single_copy, multi_copy = EXCLUDED.multi_copy, fragmented = EXCLUDED.fragmented, missing = EXCLUDED.missing, n_markers = EXCLUDED.n_markers, internal_stop_codon_percent = EXCLUDED.internal_stop_codon_percent, scaffold_n50_bus = EXCLUDED.scaffold_n50_bus, contigs_n50_bus = EXCLUDED.contigs_n50_bus, percent_gaps = EXCLUDED.percent_gaps, number_of_scaffolds = EXCLUDED.number_of_scaffolds, loaded_at = now()
    WHERE (t.dataset, t.complete, t.single_copy, t.multi_copy, t.fragmented, t.missing, t.n_markers, t.internal_stop_codon_percent, t.scaffold_n50_bus, t.contigs_n50_bus, t.percent_gaps, t.number_of_scaffolds) IS DISTINCT FROM (EXCLUDED.dataset, EXCLUDED.complete, EXCLUDED.single_copy, EXCLUDED.multi_copy, EXCLUDED.fragmented, EXCLUDED.missing, EXCLUDED.n_markers, EXCLUDED.internal_stop_codon_percent, EXCLUDED.scaffold_n50_bus, EXCLUDED.contigs_n50_bus, EXCLUDED.percent_gaps, EXCLUDED.number_of_scaffolds);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_busco upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_merqury_qv t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.unique_k_mers_assembly, s.k_mers_total, s.qv, s.error) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_merqury_qv deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_merqury_qv AS t (part_id, unique_k_mers_assembly, k_mers_total, qv, error)
  SELECT s.part_id, s.unique_k_mers_assembly, s.k_mers_total, s.qv, s.error FROM sync_ref_src_k s WHERE num_nonnulls(s.unique_k_mers_assembly, s.k_mers_total, s.qv, s.error) > 0
  ON CONFLICT (part_id) DO UPDATE SET unique_k_mers_assembly = EXCLUDED.unique_k_mers_assembly, k_mers_total = EXCLUDED.k_mers_total, qv = EXCLUDED.qv, error = EXCLUDED.error, loaded_at = now()
    WHERE (t.unique_k_mers_assembly, t.k_mers_total, t.qv, t.error) IS DISTINCT FROM (EXCLUDED.unique_k_mers_assembly, EXCLUDED.k_mers_total, EXCLUDED.qv, EXCLUDED.error);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_merqury_qv upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_merqury_completeness t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.solid_k_mers, s.total_k_mers, s.completeness) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_merqury_completeness deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_merqury_completeness AS t (part_id, solid_k_mers, total_k_mers, completeness)
  SELECT s.part_id, s.solid_k_mers, s.total_k_mers, s.completeness FROM sync_ref_src_k s WHERE num_nonnulls(s.solid_k_mers, s.total_k_mers, s.completeness) > 0
  ON CONFLICT (part_id) DO UPDATE SET solid_k_mers = EXCLUDED.solid_k_mers, total_k_mers = EXCLUDED.total_k_mers, completeness = EXCLUDED.completeness, loaded_at = now()
    WHERE (t.solid_k_mers, t.total_k_mers, t.completeness) IS DISTINCT FROM (EXCLUDED.solid_k_mers, EXCLUDED.total_k_mers, EXCLUDED.completeness);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_merqury_completeness upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_omnic t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.total, s.total_unmapped, s.total_single_sided_mapped, s.total_mapped, s.total_dups, s.total_nodups, s.cis, s.trans) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_omnic deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_omnic AS t (part_id, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans)
  SELECT s.part_id, s.total, s.total_unmapped, s.total_single_sided_mapped, s.total_mapped, s.total_dups, s.total_nodups, s.cis, s.trans FROM sync_ref_src_k s WHERE num_nonnulls(s.total, s.total_unmapped, s.total_single_sided_mapped, s.total_mapped, s.total_dups, s.total_nodups, s.cis, s.trans) > 0
  ON CONFLICT (part_id) DO UPDATE SET total = EXCLUDED.total, total_unmapped = EXCLUDED.total_unmapped, total_single_sided_mapped = EXCLUDED.total_single_sided_mapped, total_mapped = EXCLUDED.total_mapped, total_dups = EXCLUDED.total_dups, total_nodups = EXCLUDED.total_nodups, cis = EXCLUDED.cis, trans = EXCLUDED.trans, loaded_at = now()
    WHERE (t.total, t.total_unmapped, t.total_single_sided_mapped, t.total_mapped, t.total_dups, t.total_nodups, t.cis, t.trans) IS DISTINCT FROM (EXCLUDED.total, EXCLUDED.total_unmapped, EXCLUDED.total_single_sided_mapped, EXCLUDED.total_mapped, EXCLUDED.total_dups, EXCLUDED.total_nodups, EXCLUDED.cis, EXCLUDED.trans);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_omnic upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_seqkit_stats t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.format, s."type", s.num_seqs, s.sum_len, s.min_len, s.avg_len, s.max_len) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_seqkit_stats deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_seqkit_stats AS t (part_id, format, "type", num_seqs, sum_len, min_len, avg_len, max_len)
  SELECT s.part_id, s.format, s."type", s.num_seqs, s.sum_len, s.min_len, s.avg_len, s.max_len FROM sync_ref_src_k s WHERE num_nonnulls(s.format, s."type", s.num_seqs, s.sum_len, s.min_len, s.avg_len, s.max_len) > 0
  ON CONFLICT (part_id) DO UPDATE SET format = EXCLUDED.format, "type" = EXCLUDED."type", num_seqs = EXCLUDED.num_seqs, sum_len = EXCLUDED.sum_len, min_len = EXCLUDED.min_len, avg_len = EXCLUDED.avg_len, max_len = EXCLUDED.max_len, loaded_at = now()
    WHERE (t.format, t."type", t.num_seqs, t.sum_len, t.min_len, t.avg_len, t.max_len) IS DISTINCT FROM (EXCLUDED.format, EXCLUDED."type", EXCLUDED.num_seqs, EXCLUDED.sum_len, EXCLUDED.min_len, EXCLUDED.avg_len, EXCLUDED.max_len);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_seqkit_stats upserted'; changed := n; RETURN NEXT;

  DELETE FROM v4.ref_chromosome_stats t
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_src_k s WHERE s.part_id = t.part_id AND num_nonnulls(s.num_chromosomes, s.pct_assigned, s.pct_no_super, s.num_seq_no_super, s.max_len_no_super) > 0);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_chromosome_stats deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_chromosome_stats AS t (part_id, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super)
  SELECT s.part_id, s.num_chromosomes, s.pct_assigned, s.pct_no_super, s.num_seq_no_super, s.max_len_no_super FROM sync_ref_src_k s WHERE num_nonnulls(s.num_chromosomes, s.pct_assigned, s.pct_no_super, s.num_seq_no_super, s.max_len_no_super) > 0
  ON CONFLICT (part_id) DO UPDATE SET num_chromosomes = EXCLUDED.num_chromosomes, pct_assigned = EXCLUDED.pct_assigned, pct_no_super = EXCLUDED.pct_no_super, num_seq_no_super = EXCLUDED.num_seq_no_super, max_len_no_super = EXCLUDED.max_len_no_super, loaded_at = now()
    WHERE (t.num_chromosomes, t.pct_assigned, t.pct_no_super, t.num_seq_no_super, t.max_len_no_super) IS DISTINCT FROM (EXCLUDED.num_chromosomes, EXCLUDED.pct_assigned, EXCLUDED.pct_no_super, EXCLUDED.num_seq_no_super, EXCLUDED.max_len_no_super);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'ref_chromosome_stats upserted'; changed := n; RETURN NEXT;

  CREATE TEMP TABLE sync_ref_run_want ON COMMIT DROP AS
    SELECT DISTINCT a.assembly_id, s.sequencing_id
    FROM v4.ref_assembly a
    JOIN public.v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
    WHERE s.technology IN ('PacBio HIFI', 'PacBio', 'ONT') AND s.library_type IN ('pacbio', 'ont')
      AND s.status IS DISTINCT FROM 'Failed';  -- 069: a failed run produced no reads to build from
  DELETE FROM v4.ref_assembly_run r
  WHERE NOT EXISTS (SELECT 1 FROM sync_ref_run_want w WHERE (w.assembly_id, w.sequencing_id) = (r.assembly_id, r.sequencing_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link deleted'; changed := n; RETURN NEXT;
  INSERT INTO v4.ref_assembly_run (assembly_id, sequencing_id)
  SELECT assembly_id, sequencing_id FROM sync_ref_run_want
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link inserted'; changed := n; RETURN NEXT;
END
$fn$;

CREATE OR REPLACE VIEW v4.v_ref_assembly_run_readiness AS
SELECT a.og_num, a.og_id, a.seq_date, a.version,
       (SELECT string_agg(s.sequencing_id, ', ' ORDER BY s.seq_date, s.sequencing_id)
        FROM public.v_sequencing_browse s
        WHERE s.og_id = a.og_id AND s.technology IN ('PacBio HIFI', 'PacBio', 'ONT') AND s.library_type IN ('pacbio', 'ont')
          AND s.status IS DISTINCT FROM 'Failed') AS long_read_rows_for_og
FROM v4.ref_assembly a
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_assembly_run r WHERE r.assembly_id = a.assembly_id);
COMMENT ON VIEW v4.v_ref_assembly_run_readiness IS
  'Assemblies with no run link, and the OG''s PacBio/ONT DNA rows to choose from. Their seq_date '
  'matches no run date (RG.0 §1.5); writers link explicitly from RG.4.';

CREATE OR REPLACE VIEW v4.v_read_set_run_readiness AS
SELECT rs.og_id, rs.seq_date, rs.read_set_id,
       (SELECT string_agg(s.sequencing_id, ', ' ORDER BY s.seq_date, s.sequencing_id)
        FROM public.v_sequencing_browse s
        WHERE s.og_id = rs.og_id AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio'
          AND s.status IS DISTINCT FROM 'Failed') AS pacbio_rows_for_og
FROM v4.ref_read_set rs
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_read_set_run r WHERE r.read_set_id = rs.read_set_id);
COMMENT ON VIEW v4.v_read_set_run_readiness IS
  'Read sets with no run link, and the OG''s PacBio DNA rows to choose from. On 2026-10-30: OG763, '
  'OG781, OG845, OG906 (062''s header; OG73 dated by 069).';

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
       AND s.seq_date ~ '^[0-9]{6}$' AND s.status IS DISTINCT FROM 'Failed'
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
               WHERE s.og_id = p_og_id AND s.technology = kind AND s.run_id = ANY (runs) AND s.status IS DISTINCT FROM 'Failed'
                 AND EXISTS (SELECT 1 FROM unnest(files) x
                             WHERE strpos(x, s.library_tube_id || '_') > 0 OR strpos(x, s.library_tube_id || '.') > 0));
  IF cardinality(hit) = 0 THEN
    hit := ARRAY(SELECT s.sequencing_id FROM v_sequencing_browse s
                 WHERE s.og_id = p_og_id AND s.technology = kind AND s.run_id = ANY (runs) AND s.status IS DISTINCT FROM 'Failed');
  END IF;
  IF cardinality(hit) = 0 THEN
    hit := ARRAY(SELECT s.sequencing_id FROM v_sequencing_browse s
                 WHERE s.og_id = p_og_id AND s.technology = kind AND s.status IS DISTINCT FROM 'Failed'
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
  'The sequencing rows an SRA upload''s file names point to (064''s forward rule; HICL1 = HICL, 065; failed runs skipped, 069). Used by the v4 '
  'sync and by ENA-ref-genomes step 09. Re-point search_path to public at RG.6.';

-- 2. Read sets ---------------------------------------------------------------------------------

CREATE TEMP TABLE rs_fix (og_id text PRIMARY KEY, old_seq_date text, new_seq_date text NOT NULL,
                          sequencing_ids text[] NOT NULL, match_genomesize bigint) ON COMMIT DROP;
INSERT INTO rs_fix VALUES
  ('OG73', NULL, '250307', ARRAY['OG73W_D_SBL_PACB_250307_AD'], 968441003),
  ('OG804', '260522', '260522', ARRAY['OG804G_D_SBL2_PACB_260522_AMD', 'OG804G_D_SBL_PACB_250717_AD'], 909916039),
  ('OG819', '250704', '250717', ARRAY['OG819H_D_SBL_PACB_250717_AD'], 586805045),
  ('OG852', '250704', '250717', ARRAY['OG852O_D_SBL_PACB_250717_AD'], 321593136),
  ('OG853', '250704', '250717', ARRAY['OG853O_D_SBL_PACB_250717_AD'], 398638208);

DO $rs$
DECLARE
  n bigint;
BEGIN
  WITH hit AS (
    SELECT rs.read_set_id, f.new_seq_date
    FROM rs_fix f
    JOIN v4.ref_read_set rs ON rs.og_id = f.og_id AND coalesce(rs.seq_date, '') = coalesce(f.old_seq_date, '')
    JOIN v4.ref_genomescope g ON g.read_set_id = rs.read_set_id AND g.genomesize = f.match_genomesize
  )
  UPDATE v4.ref_read_set rs SET seq_date = hit.new_seq_date FROM hit WHERE rs.read_set_id = hit.read_set_id;
  GET DIAGNOSTICS n = ROW_COUNT;

  DELETE FROM v4.ref_read_set_run r
  USING v4.ref_read_set rs, rs_fix f
  WHERE r.read_set_id = rs.read_set_id AND rs.og_id = f.og_id AND rs.seq_date = f.new_seq_date
    AND NOT r.sequencing_id = ANY (f.sequencing_ids);
  INSERT INTO v4.ref_read_set_run (read_set_id, sequencing_id)
  SELECT rs.read_set_id, sid
  FROM rs_fix f JOIN v4.ref_read_set rs ON rs.og_id = f.og_id AND rs.seq_date = f.new_seq_date
  CROSS JOIN LATERAL unnest(f.sequencing_ids) AS sid
  ON CONFLICT DO NOTHING;

  IF (SELECT count(*) FROM rs_fix f JOIN v4.ref_read_set rs ON rs.og_id = f.og_id AND rs.seq_date = f.new_seq_date) <> 5
     OR EXISTS (SELECT 1 FROM rs_fix f JOIN v4.ref_read_set rs ON rs.og_id = f.og_id AND rs.seq_date = f.new_seq_date
                WHERE (SELECT array_agg(r.sequencing_id ORDER BY r.sequencing_id) FROM v4.ref_read_set_run r
                       WHERE r.read_set_id = rs.read_set_id)
                      IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(f.sequencing_ids) x)) THEN
    RAISE EXCEPTION '069: the five read sets do not all have their new date and runs (a value changed since 2026-10-30?)';
  END IF;
  RAISE NOTICE '069: % read sets re-dated now; all five have their new date and runs', n;
END
$rs$;

-- 3. SRA uploads -------------------------------------------------------------------------------

CREATE TEMP TABLE sra_fix (srr_accession text PRIMARY KEY, sequencing_ids text[] NOT NULL, filenames_md5 text NOT NULL) ON COMMIT DROP;
INSERT INTO sra_fix VALUES
  ('ERR17798704', ARRAY['OG105G-2_HICL_NOVA_240719_AD'], '41d8f90764dd93d2475ace7962766288'),
  ('ERR17798720', ARRAY['OG105G-2_HICL_NOVA_240719_AD'], '625a1660ab5ad3e5468274aae6efdda6'),
  ('ERR17885486', ARRAY['OG676G-1_HICL_NOVA_250114_AD'], 'f9ed388ebdcb47bd5a8de83c56ff83b7'),
  ('ERR17885568', ARRAY['OG676G-1_HICL_NOVA_250114_AD'], '6e676edb2924dcb1a6e9f72c95b29470'),
  ('ERR17889416', ARRAY['OG683L-1_HICL_NOVA_250114_AD'], '0c4a6e50cfd980ccd430053cf8e05cd6'),
  ('ERR17889437', ARRAY['OG683L-1_HICL_NOVA_250114_AD'], 'c79972919083433e44ce82da93c5470b'),
  ('ERR17889809', ARRAY['OG678G-1_HICL_NOVA_250114_AD'], '6d5fd2e0278b4a167e8fb7b5d04a4e97'),
  ('ERR17889811', ARRAY['OG678G-1_HICL_NOVA_250114_AD'], '8d65855366500145da6886587b6d8c12'),
  ('SRR32638519', ARRAY['OG650L-1_HICL_NOVA_240501_LA'], '80e9cbb7617667f26bdf9b64677c1b5c'),
  ('SRR32639459', ARRAY['OG759G-1_HICL_NOVA_240719_AD'], '8fa9846eca75512873affcad1860df39'),
  ('SRR32639463', ARRAY['OG8G-1_HICL_NOVA_240719_AD'], '4032129d1d1f60b2b790d4da69e51068');

DO $sra$
BEGIN
  DELETE FROM v4.ref_sra_upload_unlinked x USING sra_fix f WHERE x.srr_accession = f.srr_accession;
  INSERT INTO v4.ref_sra_upload_run (srr_accession, sequencing_id)
  SELECT f.srr_accession, sid
  FROM sra_fix f
  JOIN v4.ref_sra_upload u ON u.srr_accession = f.srr_accession AND md5(coalesce(u.filenames, '')) = f.filenames_md5
  CROSS JOIN LATERAL unnest(f.sequencing_ids) AS sid
  ON CONFLICT DO NOTHING;
  IF (SELECT count(DISTINCT r.srr_accession) FROM v4.ref_sra_upload_run r JOIN sra_fix f USING (srr_accession)) <> 11 THEN
    RAISE EXCEPTION '069: the 11 uploads are not all linked (file names or sequencing rows changed?)';
  END IF;
  RAISE NOTICE '069: 11 uploads linked; % uploads linked in all',
    (SELECT count(DISTINCT srr_accession) FROM v4.ref_sra_upload_run);
END
$sra$;

-- 4. Sync, then verify -------------------------------------------------------------------------

SELECT * FROM v4.sync_ref_assembly();  -- drops the assembly links to failed rows

DO $verify$
DECLARE
  fn text;
  r  record;
BEGIN
  FOREACH fn IN ARRAY ARRAY['sync_ref_assembly', 'sync_ref_read_qc', 'sync_ref_submission'] LOOP
    FOR r IN EXECUTE format('SELECT * FROM v4.%I()', fn) LOOP
      IF r.changed <> 0 THEN
        RAISE EXCEPTION '069: % is not a no-op after the migration: % (%)', fn, r.step, r.changed;
      END IF;
    END LOOP;
  END LOOP;
  FOREACH fn IN ARRAY ARRAY['check_ref_assembly', 'check_ref_read_qc', 'check_ref_submission'] LOOP
    FOR r IN EXECUTE format('SELECT * FROM v4.%I()', fn) LOOP
      IF r.check_name LIKE 'note:%' THEN
        RAISE NOTICE '069 %: %', r.check_name, r.problems;
      ELSIF r.problems <> 0 THEN
        RAISE EXCEPTION '069 % failed: % (%)', fn, r.check_name, r.problems;
      END IF;
    END LOOP;
  END LOOP;
  IF EXISTS (SELECT 1 FROM v4.ref_assembly_run x JOIN public.sequencing s USING (sequencing_id) WHERE s.status = 'Failed')
     OR EXISTS (SELECT 1 FROM v4.ref_read_set_run x JOIN public.sequencing s USING (sequencing_id) WHERE s.status = 'Failed')
     OR EXISTS (SELECT 1 FROM v4.ref_sra_upload_run x JOIN public.sequencing s USING (sequencing_id) WHERE s.status = 'Failed') THEN
    RAISE EXCEPTION '069: a v4 run link still points at a failed run';
  END IF;
END
$verify$;

COMMIT;
