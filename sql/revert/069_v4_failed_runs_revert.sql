-- 069_v4_failed_runs_revert.sql -- back to 068's state: the 057/062/065 texts of the rules (failed
-- runs matched again), the five read sets and the 11 SRA uploads as they were, and the sync re-adds
-- the assembly links to failed rows.
--
-- After running this, delete 069's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '069_v4_failed_runs.sql';

BEGIN;

CREATE OR REPLACE FUNCTION v4.ref_assembly_run_genomic_only() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  tech  text;
  ltype text;
BEGIN
  SELECT s.technology, s.library_type INTO tech, ltype
  FROM public.v_sequencing_browse s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS NULL OR tech NOT IN ('PacBio HIFI', 'PacBio', 'ONT', 'Hi-C')
     OR ltype IS NULL OR ltype NOT IN ('pacbio', 'ont', 'hic') THEN
    RAISE EXCEPTION 'ref_assembly_run: % is % / % sequencing; a reference assembly is built from '
      'PacBio, ONT or Hi-C DNA libraries', NEW.sequencing_id, coalesce(tech, 'unknown'), coalesce(ltype, 'unknown');
  END IF;
  RETURN NEW;
END
$fn$;

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
    WHERE s.technology IN ('PacBio HIFI', 'PacBio', 'ONT') AND s.library_type IN ('pacbio', 'ont');
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
        WHERE s.og_id = a.og_id AND s.technology IN ('PacBio HIFI', 'PacBio', 'ONT') AND s.library_type IN ('pacbio', 'ont')) AS long_read_rows_for_og
FROM v4.ref_assembly a
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_assembly_run r WHERE r.assembly_id = a.assembly_id);
COMMENT ON VIEW v4.v_ref_assembly_run_readiness IS
  'Assemblies with no run link, and the OG''s PacBio/ONT DNA rows to choose from. Their seq_date '
  'matches no run date (RG.0 §1.5); writers link explicitly from RG.4.';

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

CREATE TEMP TABLE rs_back (og_id text PRIMARY KEY, cur_seq_date text, old_seq_date text,
                           old_ids text[] NOT NULL, match_genomesize bigint) ON COMMIT DROP;
INSERT INTO rs_back VALUES
  ('OG73', '250307', NULL, ARRAY[]::text[], 968441003),
  ('OG804', '260522', '260522', ARRAY['OG804G_D_SBL2_PACB_260522_AMD'], 909916039),
  ('OG819', '250717', '250704', ARRAY['OG819H_D_SBL_PACB_250704_AD'], 586805045),
  ('OG852', '250717', '250704', ARRAY['OG852O_D_SBL_PACB_250704_AD'], 321593136),
  ('OG853', '250717', '250704', ARRAY['OG853O_D_SBL_PACB_250704_AD'], 398638208);
DELETE FROM v4.ref_read_set_run r USING v4.ref_read_set rs, rs_back b
WHERE r.read_set_id = rs.read_set_id AND rs.og_id = b.og_id AND rs.seq_date = b.cur_seq_date;
UPDATE v4.ref_read_set rs SET seq_date = b.old_seq_date FROM rs_back b
WHERE rs.og_id = b.og_id AND rs.seq_date = b.cur_seq_date;
INSERT INTO v4.ref_read_set_run (read_set_id, sequencing_id)
SELECT rs.read_set_id, sid FROM rs_back b
JOIN v4.ref_read_set rs ON rs.og_id = b.og_id AND coalesce(rs.seq_date, '') = coalesce(b.old_seq_date, '')
CROSS JOIN LATERAL unnest(b.old_ids) AS sid
ON CONFLICT DO NOTHING;

DELETE FROM v4.ref_sra_upload_run WHERE srr_accession IN ('ERR17798704', 'ERR17798720', 'ERR17885486', 'ERR17885568', 'ERR17889416', 'ERR17889437', 'ERR17889809', 'ERR17889811', 'SRR32638519', 'SRR32639459', 'SRR32639463');
INSERT INTO v4.ref_sra_upload_unlinked (srr_accession, reason, reviewed_on) VALUES
  ('ERR17798704', 'run not in sequencing (runs NOVA_240719_AD)', DATE '2026-10-22'),
  ('ERR17798720', 'run not in sequencing (runs NOVA_240719_AD)', DATE '2026-10-22'),
  ('ERR17885486', 'run not in sequencing (runs NOVA_250114_AD)', DATE '2026-10-22'),
  ('ERR17885568', 'run not in sequencing (runs NOVA_250114_AD)', DATE '2026-10-22'),
  ('ERR17889416', 'run not in sequencing (runs NOVA_250114_AD)', DATE '2026-10-22'),
  ('ERR17889437', 'run not in sequencing (runs NOVA_250114_AD)', DATE '2026-10-22'),
  ('ERR17889809', 'run not in sequencing (runs NOVA_250114_AD)', DATE '2026-10-22'),
  ('ERR17889811', 'run not in sequencing (runs NOVA_250114_AD)', DATE '2026-10-22'),
  ('SRR32638519', 'no row for library (runs NOVA_240501_LA)', DATE '2026-10-22'),
  ('SRR32639459', 'run not in sequencing (runs NOVA_240719_AD)', DATE '2026-10-22'),
  ('SRR32639463', 'run not in sequencing (runs NOVA_240719_AD)', DATE '2026-10-22')
ON CONFLICT DO NOTHING;

SELECT * FROM v4.sync_ref_assembly();

COMMIT;
