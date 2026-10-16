-- 051_v3_mitogenome.sql -- Phase R.2: the mitogenome tables in a new schema v3, beside public.
--
-- Why. public.mitogenome_data holds one row per assembly with one annotation in its columns, so
-- a re-annotation overwrites the previous one and an unannotated assembly carries 81 empty
-- annotation columns (docs/assembly_relations_plan.md §1-3). This builds the replacement shape:
-- one identity table per assembly, plus one table per thing that happens to it:
--   mito_assembly         one per (og_id, tech, seq_date, code)
--   mito_assembly_depth   0..1 per assembly: the depth step's verdict
--   mito_assembly_run     0..n per assembly: the sequencing rows it was built from
--   mito_annotation       0..n per assembly: one per annotator run, all kept
--   mito_annotation_gene  0..n per annotation: one row per gene (owner decision 4: long)
--   mito_gene             lookup of the 39 gene names
-- and three views:
--   v3.mitogenome_data             the 102 kept legacy columns, one row per (assembly,
--                                  annotation) plus one per unannotated assembly;
--   v3.mitogenome_submission_view  today's definition, on the new tables;
--   v3.v_mito_annotation_genes     one row per annotation, genes wide (generated from mito_gene).
--
-- Owner decision 11: everything is built in v3 and tested beside public, then merged at R.6.
-- Until then:
--   - nothing in public depends on v3. DROP SCHEMA v3 CASCADE is a clean revert.
--   - Production writers keep writing public.mitogenome_data. v3.sync_mito() copies it across:
--     this file runs it once as the backfill, and scripts/sync_v3.sh runs it nightly.
--     v3.check_mito() proves v3 equals public, by key and by value, EXCEPT ALL both ways.
--   - sync_mito and check_mito are window-only. R.6 drops them.
--
-- Decisions carried here:
--   - Every annotation is kept and shown. is_selected is an optional, person-set flag that
--     nothing reads (owner decision 3). No writer, sync or view sets it. A CHECK requires
--     selected_by whenever it is set.
--   - mito_assembly_depth stores depth_method = 'not_measured' rows. They record when the depth
--     step ran and measured nothing (depth_measured_at is set on all 412). That differs from the
--     plan's first draft, which dropped them; they carry a real event, and the compatibility
--     view has to reproduce them. An assembly the depth step never touched (5 rows, NULL
--     depth_method) has no depth row.
--   - mito_assembly_run: ilmn -> Illumina runs other than iSEQ (QC runs); hic -> Hi-C;
--     hifi -> PacBio*. Measured in docs/assembly_relations_r0_record.md. ON DELETE CASCADE to
--     public.sequencing, so import_v2.py removing a stale sequencing row is never blocked by v3;
--     the sync re-derives links.
--   - Not carried: seqlength_12s/16s/co1 and status (never populated); genbank, bankit,
--     genbank_accession, date_submitted_genbank (empty on live; GenBank submitter retired, owner
--     decision 5). They stay in public.mitogenome_data until R.6 archives it.
--   - Column types copy public.mitogenome_data exactly. No value changes in the split.
--
-- What was rejected. Building the views as mitogenome_data_v in public (the first draft): it
-- would make public depend on the new tables before they were proven. Deriving the gene seed
-- from information_schema at run time: the seed is written out so it cannot drift silently.
--
-- Checks before COMMIT (v3.check_mito()): v3.mitogenome_data and v3.mitogenome_submission_view
-- equal their public counterparts; every lca, lca_raw_results, blast_filtered_lca,
-- lca_validation, ena_validation_attempts and ena_submissions row resolves to exactly one
-- v3.mito_annotation (0 unresolved, true only since 050); no row is selected.
--
-- Revert: sql/revert/051_v3_mitogenome_revert.sql (052 and 053's reverts first, if applied).

BEGIN;

CREATE SCHEMA IF NOT EXISTS v3;
COMMENT ON SCHEMA v3 IS
  'Phase R: the new mitogenome and draft-genome design, built beside public and kept in sync '
  'with it until the R.6 merge. Nothing in public depends on it. docs/assembly_relations_plan.md';
GRANT USAGE ON SCHEMA v3 TO readonly, oceangenom_web;

-- Gene lookup -------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS v3.mito_gene (
    gene            text    PRIMARY KEY,
    gene_class      text    NOT NULL CHECK (gene_class IN ('pcg', 'rrna', 'trna')),
    sort_order      integer NOT NULL UNIQUE,
    has_translation boolean NOT NULL DEFAULT false
);
COMMENT ON TABLE v3.mito_gene IS
  'Mitochondrial gene names. A new gene is an INSERT here plus v3.rebuild_mito_gene_views(); '
  'gene is also the legacy length column name, and gene || ''_trans'' the translated-length one.';

INSERT INTO v3.mito_gene (gene, gene_class, sort_order, has_translation) VALUES
  ('rrna12s', 'rrna', 1, false),
  ('rrna16s', 'rrna', 2, false),
  ('atp6', 'pcg', 3, true),
  ('atp8', 'pcg', 4, true),
  ('cox1', 'pcg', 5, true),
  ('cox2', 'pcg', 6, true),
  ('cox3', 'pcg', 7, true),
  ('cytb', 'pcg', 8, true),
  ('nad1', 'pcg', 9, true),
  ('nad2', 'pcg', 10, true),
  ('nad3', 'pcg', 11, true),
  ('nad4', 'pcg', 12, true),
  ('nad4l', 'pcg', 13, true),
  ('nad5', 'pcg', 14, true),
  ('nad6', 'pcg', 15, true),
  ('trna_phe', 'trna', 16, false),
  ('trna_val', 'trna', 17, false),
  ('trna_leuuag', 'trna', 18, false),
  ('trna_leuuaa', 'trna', 19, false),
  ('trna_ile', 'trna', 20, false),
  ('trna_met', 'trna', 21, false),
  ('trna_thr', 'trna', 22, false),
  ('trna_pro', 'trna', 23, false),
  ('trna_lys', 'trna', 24, false),
  ('trna_asp', 'trna', 25, false),
  ('trna_glu', 'trna', 26, false),
  ('trna_sergcu', 'trna', 27, false),
  ('trna_seruga', 'trna', 28, false),
  ('trna_tyr', 'trna', 29, false),
  ('trna_cys', 'trna', 30, false),
  ('trna_trp', 'trna', 31, false),
  ('trna_ala', 'trna', 32, false),
  ('trna_asn', 'trna', 33, false),
  ('trna_gly', 'trna', 34, false),
  ('trna_arg', 'trna', 35, false),
  ('trna_his', 'trna', 36, false),
  ('trna_gln', 'trna', 37, false),
  ('atp9', 'pcg', 38, true),
  ('mtmuts', 'pcg', 39, true)
ON CONFLICT (gene) DO NOTHING;

-- Assembly ----------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS v3.mito_assembly (
    assembly_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id             text NOT NULL REFERENCES public.sample (og_id),
    tech              text NOT NULL,
    seq_date          text NOT NULL,     -- identifier component, not a date
    code              text NOT NULL,
    stats             text,
    length            integer,
    avg_coverage      real,              -- legacy, assembler-specific; see mito_assembly_depth
    avg_base_coverage real,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT mito_assembly_natural_key UNIQUE (og_id, tech, seq_date, code),
    CONSTRAINT mito_assembly_tech_check CHECK (tech IN ('ilmn', 'hifi', 'hic'))
);
COMMENT ON TABLE v3.mito_assembly IS
  'One mitogenome assembly. Written by push_mtdna_assm_results.py (Oceanomics-OceanGenomes-Mitogenomes).';

CREATE TABLE IF NOT EXISTS v3.mito_assembly_depth (
    assembly_id bigint PRIMARY KEY REFERENCES v3.mito_assembly ON DELETE CASCADE,
    depth_method            text NOT NULL,
    mean_depth              double precision,
    median_depth            double precision,
    depth_sd                double precision,
    depth_cv                double precision,
    breadth_1x              double precision,
    breadth_10x             double precision,
    mito_mapped_reads       bigint,
    total_reads             bigint,
    mito_read_fraction      double precision,
    depth_target_length_bp  integer,
    depth_target_fasta      text,
    depth_measured_at       timestamp with time zone
);
COMMENT ON TABLE v3.mito_assembly_depth IS
  'The remap depth step''s verdict for an assembly: a measurement (remap_full_v1), or '
  'not_measured with the time it was recorded. No row: the step never ran on it.';

CREATE TABLE IF NOT EXISTS v3.mito_assembly_run (
    assembly_id   bigint NOT NULL REFERENCES v3.mito_assembly ON DELETE CASCADE,
    sequencing_id text   NOT NULL REFERENCES public.sequencing (sequencing_id) ON DELETE CASCADE,
    PRIMARY KEY (assembly_id, sequencing_id)
);
CREATE INDEX IF NOT EXISTS mito_assembly_run_sequencing_id_idx ON v3.mito_assembly_run (sequencing_id);
COMMENT ON TABLE v3.mito_assembly_run IS
  'The sequencing rows (a library on a run) an assembly was built from, derived from '
  '(og_id, seq_date) and tech. ilmn excludes iSEQ QC runs.';

-- Annotation --------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS v3.mito_annotation (
    annotation_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assembly_id     bigint NOT NULL REFERENCES v3.mito_assembly ON DELETE CASCADE,
    annotation      text   NOT NULL,     -- annotator+version: emma102, mitos2110, mito2110mc
    is_selected     boolean NOT NULL DEFAULT false,
    selected_by     text,
    selected_at     timestamptz,
    length_emma                     integer,
    cds_no                          integer,
    trna_no                         integer,
    rrna_no                         integer,
    manual_curation_notes           text,
    extra_genes                     text,
    missing_genes                   text,
    order_correct                   text,
    passed                          text,
    trna_advisory                   text,
    order_variant                   text,
    order_deviation                 text,
    annotation_gaps                 text,
    order_variant_taxon_check       text,
    order_status                    text,
    order_deviation_detail          text,
    expected_lineage_genes          text,
    missing_expected_lineage_genes  text,
    lineage_gene_advisories         text,
    mitos_unmapped_features         text,
    mitos_known_auxiliary_features  text,
    duplicate_loci                  text,
    annotation_integrity_status     text,
    annotation_integrity_issues     text,
    annotation_stats_version        text,
    annotation_updated_at           timestamp with time zone,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT mito_annotation_natural_key UNIQUE (assembly_id, annotation),
    CONSTRAINT mito_annotation_selected_by_check CHECK (NOT is_selected OR selected_by IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS mito_annotation_one_selected
    ON v3.mito_annotation (assembly_id) WHERE is_selected;
COMMENT ON TABLE v3.mito_annotation IS
  'One annotation of an assembly. All are kept. Written by push_emma_annotation_results.py.';
COMMENT ON COLUMN v3.mito_annotation.is_selected IS
  'Optional: a person may mark one annotation per assembly as the one they chose. Set by hand '
  'only; no writer, view or pipeline reads it (owner decision 3, 2026-10-16).';

CREATE TABLE IF NOT EXISTS v3.mito_annotation_gene (
    annotation_id     bigint  NOT NULL REFERENCES v3.mito_annotation ON DELETE CASCADE,
    gene              text    NOT NULL REFERENCES v3.mito_gene (gene),
    length            integer,
    translated_length integer,     -- protein-coding genes only
    PRIMARY KEY (annotation_id, gene),
    CONSTRAINT mito_annotation_gene_has_value CHECK (num_nonnulls(length, translated_length) > 0)
);
COMMENT ON TABLE v3.mito_annotation_gene IS
  'Per-gene lengths of one annotation. No row: the annotation has no value for that gene.';

-- Sync (window-only: dropped at R.6) --------------------------------------------------------

CREATE OR REPLACE FUNCTION v3.sync_mito() RETURNS TABLE (step text, changed bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  n       bigint;
  unpivot text;
BEGIN
  -- Assemblies: delete what public no longer has (cascades), upsert the rest.
  DELETE FROM v3.mito_assembly a
  WHERE NOT EXISTS (SELECT 1 FROM public.mitogenome_data m
                    WHERE (m.og_id, m.tech, m.seq_date, m.code) = (a.og_id, a.tech, a.seq_date, a.code));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_assembly AS t (og_id, tech, seq_date, code, stats, length, avg_coverage, avg_base_coverage)
  SELECT og_id, tech, seq_date, code, stats, length, avg_coverage, avg_base_coverage
  FROM public.mitogenome_data
  ON CONFLICT (og_id, tech, seq_date, code) DO UPDATE
    SET stats = EXCLUDED.stats, length = EXCLUDED.length, avg_coverage = EXCLUDED.avg_coverage,
        avg_base_coverage = EXCLUDED.avg_base_coverage, updated_at = now()
    WHERE (t.stats, t.length, t.avg_coverage, t.avg_base_coverage)
          IS DISTINCT FROM (EXCLUDED.stats, EXCLUDED.length, EXCLUDED.avg_coverage, EXCLUDED.avg_base_coverage);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'assembly upserted'; changed := n; RETURN NEXT;

  -- Depth: a row wherever public has a depth_method.
  DELETE FROM v3.mito_assembly_depth d
  USING v3.mito_assembly a JOIN public.mitogenome_data m USING (og_id, tech, seq_date, code)
  WHERE d.assembly_id = a.assembly_id AND m.depth_method IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'depth deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_assembly_depth AS t (assembly_id, depth_method, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_measured_at)
  SELECT a.assembly_id, m.depth_method, m.mean_depth, m.median_depth, m.depth_sd, m.depth_cv, m.breadth_1x, m.breadth_10x, m.mito_mapped_reads, m.total_reads, m.mito_read_fraction, m.depth_target_length_bp, m.depth_target_fasta, m.depth_measured_at
  FROM public.mitogenome_data m JOIN v3.mito_assembly a USING (og_id, tech, seq_date, code)
  WHERE m.depth_method IS NOT NULL
  ON CONFLICT (assembly_id) DO UPDATE SET depth_method = EXCLUDED.depth_method, mean_depth = EXCLUDED.mean_depth, median_depth = EXCLUDED.median_depth, depth_sd = EXCLUDED.depth_sd, depth_cv = EXCLUDED.depth_cv, breadth_1x = EXCLUDED.breadth_1x, breadth_10x = EXCLUDED.breadth_10x, mito_mapped_reads = EXCLUDED.mito_mapped_reads, total_reads = EXCLUDED.total_reads, mito_read_fraction = EXCLUDED.mito_read_fraction, depth_target_length_bp = EXCLUDED.depth_target_length_bp, depth_target_fasta = EXCLUDED.depth_target_fasta, depth_measured_at = EXCLUDED.depth_measured_at
    WHERE (t.depth_method, t.mean_depth, t.median_depth, t.depth_sd, t.depth_cv, t.breadth_1x, t.breadth_10x, t.mito_mapped_reads, t.total_reads, t.mito_read_fraction, t.depth_target_length_bp, t.depth_target_fasta, t.depth_measured_at)
            IS DISTINCT FROM (EXCLUDED.depth_method, EXCLUDED.mean_depth, EXCLUDED.median_depth, EXCLUDED.depth_sd, EXCLUDED.depth_cv, EXCLUDED.breadth_1x, EXCLUDED.breadth_10x, EXCLUDED.mito_mapped_reads, EXCLUDED.total_reads, EXCLUDED.mito_read_fraction, EXCLUDED.depth_target_length_bp, EXCLUDED.depth_target_fasta, EXCLUDED.depth_measured_at);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'depth upserted'; changed := n; RETURN NEXT;

  -- Annotations: public holds at most one per assembly, so v3 mirrors exactly that one.
  DELETE FROM v3.mito_annotation n_
  USING v3.mito_assembly a
  WHERE n_.assembly_id = a.assembly_id
    AND NOT EXISTS (SELECT 1 FROM public.mitogenome_data m
                    WHERE (m.og_id, m.tech, m.seq_date, m.code, m.annotation)
                        = (a.og_id, a.tech, a.seq_date, a.code, n_.annotation));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'annotation deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_annotation AS t (assembly_id, annotation, length_emma, cds_no, trna_no, rrna_no, manual_curation_notes, extra_genes, missing_genes, order_correct, passed, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, annotation_stats_version, annotation_updated_at)
  SELECT a.assembly_id, m.annotation, m.length_emma, m.cds_no, m.trna_no, m.rrna_no, m.manual_curation_notes, m.extra_genes, m.missing_genes, m.order_correct, m.passed, m.trna_advisory, m.order_variant, m.order_deviation, m.annotation_gaps, m.order_variant_taxon_check, m.order_status, m.order_deviation_detail, m.expected_lineage_genes, m.missing_expected_lineage_genes, m.lineage_gene_advisories, m.mitos_unmapped_features, m.mitos_known_auxiliary_features, m.duplicate_loci, m.annotation_integrity_status, m.annotation_integrity_issues, m.annotation_stats_version, m.annotation_updated_at
  FROM public.mitogenome_data m JOIN v3.mito_assembly a USING (og_id, tech, seq_date, code)
  WHERE m.annotation IS NOT NULL
  ON CONFLICT (assembly_id, annotation) DO UPDATE SET length_emma = EXCLUDED.length_emma, cds_no = EXCLUDED.cds_no, trna_no = EXCLUDED.trna_no, rrna_no = EXCLUDED.rrna_no, manual_curation_notes = EXCLUDED.manual_curation_notes, extra_genes = EXCLUDED.extra_genes, missing_genes = EXCLUDED.missing_genes, order_correct = EXCLUDED.order_correct, passed = EXCLUDED.passed, trna_advisory = EXCLUDED.trna_advisory, order_variant = EXCLUDED.order_variant, order_deviation = EXCLUDED.order_deviation, annotation_gaps = EXCLUDED.annotation_gaps, order_variant_taxon_check = EXCLUDED.order_variant_taxon_check, order_status = EXCLUDED.order_status, order_deviation_detail = EXCLUDED.order_deviation_detail, expected_lineage_genes = EXCLUDED.expected_lineage_genes, missing_expected_lineage_genes = EXCLUDED.missing_expected_lineage_genes, lineage_gene_advisories = EXCLUDED.lineage_gene_advisories, mitos_unmapped_features = EXCLUDED.mitos_unmapped_features, mitos_known_auxiliary_features = EXCLUDED.mitos_known_auxiliary_features, duplicate_loci = EXCLUDED.duplicate_loci, annotation_integrity_status = EXCLUDED.annotation_integrity_status, annotation_integrity_issues = EXCLUDED.annotation_integrity_issues, annotation_stats_version = EXCLUDED.annotation_stats_version, annotation_updated_at = EXCLUDED.annotation_updated_at, updated_at = now()
    WHERE (t.length_emma, t.cds_no, t.trna_no, t.rrna_no, t.manual_curation_notes, t.extra_genes, t.missing_genes, t.order_correct, t.passed, t.trna_advisory, t.order_variant, t.order_deviation, t.annotation_gaps, t.order_variant_taxon_check, t.order_status, t.order_deviation_detail, t.expected_lineage_genes, t.missing_expected_lineage_genes, t.lineage_gene_advisories, t.mitos_unmapped_features, t.mitos_known_auxiliary_features, t.duplicate_loci, t.annotation_integrity_status, t.annotation_integrity_issues, t.annotation_stats_version, t.annotation_updated_at)
            IS DISTINCT FROM (EXCLUDED.length_emma, EXCLUDED.cds_no, EXCLUDED.trna_no, EXCLUDED.rrna_no, EXCLUDED.manual_curation_notes, EXCLUDED.extra_genes, EXCLUDED.missing_genes, EXCLUDED.order_correct, EXCLUDED.passed, EXCLUDED.trna_advisory, EXCLUDED.order_variant, EXCLUDED.order_deviation, EXCLUDED.annotation_gaps, EXCLUDED.order_variant_taxon_check, EXCLUDED.order_status, EXCLUDED.order_deviation_detail, EXCLUDED.expected_lineage_genes, EXCLUDED.missing_expected_lineage_genes, EXCLUDED.lineage_gene_advisories, EXCLUDED.mitos_unmapped_features, EXCLUDED.mitos_known_auxiliary_features, EXCLUDED.duplicate_loci, EXCLUDED.annotation_integrity_status, EXCLUDED.annotation_integrity_issues, EXCLUDED.annotation_stats_version, EXCLUDED.annotation_updated_at);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'annotation upserted'; changed := n; RETURN NEXT;

  -- Genes: unpivot the legacy columns. The list is fixed: the 39 genes public has columns for.
  CREATE TEMP TABLE IF NOT EXISTS sync_mito_gene_want
    (annotation_id bigint, gene text, length integer, translated_length integer) ON COMMIT DROP;
  TRUNCATE sync_mito_gene_want;
  INSERT INTO sync_mito_gene_want
  SELECT n_.annotation_id, x.gene, x.len, x.tlen
  FROM public.mitogenome_data m
  JOIN v3.mito_assembly a USING (og_id, tech, seq_date, code)
  JOIN v3.mito_annotation n_ ON n_.assembly_id = a.assembly_id AND n_.annotation = m.annotation
  CROSS JOIN LATERAL (VALUES
        ('rrna12s', m.rrna12s, NULL::integer),
        ('rrna16s', m.rrna16s, NULL::integer),
        ('atp6', m.atp6, m.atp6_trans),
        ('atp8', m.atp8, m.atp8_trans),
        ('cox1', m.cox1, m.cox1_trans),
        ('cox2', m.cox2, m.cox2_trans),
        ('cox3', m.cox3, m.cox3_trans),
        ('cytb', m.cytb, m.cytb_trans),
        ('nad1', m.nad1, m.nad1_trans),
        ('nad2', m.nad2, m.nad2_trans),
        ('nad3', m.nad3, m.nad3_trans),
        ('nad4', m.nad4, m.nad4_trans),
        ('nad4l', m.nad4l, m.nad4l_trans),
        ('nad5', m.nad5, m.nad5_trans),
        ('nad6', m.nad6, m.nad6_trans),
        ('trna_phe', m.trna_phe, NULL::integer),
        ('trna_val', m.trna_val, NULL::integer),
        ('trna_leuuag', m.trna_leuuag, NULL::integer),
        ('trna_leuuaa', m.trna_leuuaa, NULL::integer),
        ('trna_ile', m.trna_ile, NULL::integer),
        ('trna_met', m.trna_met, NULL::integer),
        ('trna_thr', m.trna_thr, NULL::integer),
        ('trna_pro', m.trna_pro, NULL::integer),
        ('trna_lys', m.trna_lys, NULL::integer),
        ('trna_asp', m.trna_asp, NULL::integer),
        ('trna_glu', m.trna_glu, NULL::integer),
        ('trna_sergcu', m.trna_sergcu, NULL::integer),
        ('trna_seruga', m.trna_seruga, NULL::integer),
        ('trna_tyr', m.trna_tyr, NULL::integer),
        ('trna_cys', m.trna_cys, NULL::integer),
        ('trna_trp', m.trna_trp, NULL::integer),
        ('trna_ala', m.trna_ala, NULL::integer),
        ('trna_asn', m.trna_asn, NULL::integer),
        ('trna_gly', m.trna_gly, NULL::integer),
        ('trna_arg', m.trna_arg, NULL::integer),
        ('trna_his', m.trna_his, NULL::integer),
        ('trna_gln', m.trna_gln, NULL::integer),
        ('atp9', m.atp9, m.atp9_trans),
        ('mtmuts', m.mtmuts, m.mtmuts_trans)
  ) AS x (gene, len, tlen)
  WHERE num_nonnulls(x.len, x.tlen) > 0;

  DELETE FROM v3.mito_annotation_gene g
  WHERE NOT EXISTS (SELECT 1 FROM sync_mito_gene_want w
                    WHERE (w.annotation_id, w.gene) = (g.annotation_id, g.gene));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'gene deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_annotation_gene AS t (annotation_id, gene, length, translated_length)
  SELECT annotation_id, gene, length, translated_length FROM sync_mito_gene_want
  ON CONFLICT (annotation_id, gene) DO UPDATE
    SET length = EXCLUDED.length, translated_length = EXCLUDED.translated_length
    WHERE (t.length, t.translated_length) IS DISTINCT FROM (EXCLUDED.length, EXCLUDED.translated_length);
  GET DIAGNOSTICS n = ROW_COUNT; step := 'gene upserted'; changed := n; RETURN NEXT;

  -- Run links: derived, so replace what differs.
  CREATE TEMP TABLE IF NOT EXISTS sync_mito_run_want (assembly_id bigint, sequencing_id text) ON COMMIT DROP;
  TRUNCATE sync_mito_run_want;
  INSERT INTO sync_mito_run_want
  SELECT DISTINCT a.assembly_id, s.sequencing_id
  FROM v3.mito_assembly a
  JOIN public.v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
  WHERE (a.tech = 'ilmn' AND s.technology = 'Illumina' AND s.instrument IS DISTINCT FROM 'iSEQ')
     OR (a.tech = 'hic'  AND s.technology = 'Hi-C')
     OR (a.tech = 'hifi' AND s.technology LIKE 'PacBio%');

  DELETE FROM v3.mito_assembly_run r
  WHERE NOT EXISTS (SELECT 1 FROM sync_mito_run_want w
                    WHERE (w.assembly_id, w.sequencing_id) = (r.assembly_id, r.sequencing_id));
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link deleted'; changed := n; RETURN NEXT;

  INSERT INTO v3.mito_assembly_run (assembly_id, sequencing_id)
  SELECT assembly_id, sequencing_id FROM sync_mito_run_want
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT; step := 'run link inserted'; changed := n; RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v3.sync_mito() IS
  'Phase R window only: copy public.mitogenome_data into the v3 tables, keyed on natural keys. '
  'Run nightly by scripts/sync_v3.sh. Dropped at the R.6 merge.';

-- Views -------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW v3.mitogenome_data AS
SELECT
       a.og_id,
       a.tech,
       a.seq_date,
       a.code,
       a.stats,
       a.length,
       n.length_emma,
       n.cds_no,
       n.trna_no,
       n.rrna_no,
       g.rrna12s,
       g.rrna16s,
       g.atp6,
       g.atp8,
       g.cox1,
       g.cox2,
       g.cox3,
       g.cytb,
       g.nad1,
       g.nad2,
       g.nad3,
       g.nad4,
       g.nad4l,
       g.nad5,
       g.nad6,
       g.trna_phe,
       g.trna_val,
       g.trna_leuuag,
       g.trna_leuuaa,
       g.trna_ile,
       g.trna_met,
       g.trna_thr,
       g.trna_pro,
       g.trna_lys,
       g.trna_asp,
       g.trna_glu,
       g.trna_sergcu,
       g.trna_seruga,
       g.trna_tyr,
       g.trna_cys,
       g.trna_trp,
       g.trna_ala,
       g.trna_asn,
       g.trna_gly,
       g.trna_arg,
       g.trna_his,
       g.trna_gln,
       n.manual_curation_notes,
       n.annotation,
       a.avg_coverage,
       a.avg_base_coverage,
       g.atp6_trans,
       g.atp8_trans,
       g.cox1_trans,
       g.cox2_trans,
       g.cox3_trans,
       g.cytb_trans,
       g.nad1_trans,
       g.nad2_trans,
       g.nad3_trans,
       g.nad4_trans,
       g.nad4l_trans,
       g.nad5_trans,
       g.nad6_trans,
       n.extra_genes,
       n.missing_genes,
       n.order_correct,
       n.passed,
       d.mean_depth,
       d.median_depth,
       d.depth_sd,
       d.depth_cv,
       d.breadth_1x,
       d.breadth_10x,
       d.mito_mapped_reads,
       d.total_reads,
       d.mito_read_fraction,
       d.depth_target_length_bp,
       d.depth_target_fasta,
       d.depth_method,
       d.depth_measured_at,
       n.trna_advisory,
       n.order_variant,
       n.order_deviation,
       n.annotation_gaps,
       n.order_variant_taxon_check,
       n.order_status,
       n.order_deviation_detail,
       n.expected_lineage_genes,
       n.missing_expected_lineage_genes,
       n.lineage_gene_advisories,
       n.mitos_unmapped_features,
       n.mitos_known_auxiliary_features,
       n.duplicate_loci,
       n.annotation_integrity_status,
       n.annotation_integrity_issues,
       g.atp9,
       g.atp9_trans,
       g.mtmuts,
       g.mtmuts_trans,
       n.annotation_stats_version,
       n.annotation_updated_at
FROM v3.mito_assembly a
LEFT JOIN v3.mito_annotation n ON n.assembly_id = a.assembly_id
LEFT JOIN v3.mito_assembly_depth d ON d.assembly_id = a.assembly_id
LEFT JOIN (
    SELECT annotation_id,
           max(length) FILTER (WHERE gene = 'rrna12s') AS rrna12s,
           max(length) FILTER (WHERE gene = 'rrna16s') AS rrna16s,
           max(length) FILTER (WHERE gene = 'atp6') AS atp6,
           max(length) FILTER (WHERE gene = 'atp8') AS atp8,
           max(length) FILTER (WHERE gene = 'cox1') AS cox1,
           max(length) FILTER (WHERE gene = 'cox2') AS cox2,
           max(length) FILTER (WHERE gene = 'cox3') AS cox3,
           max(length) FILTER (WHERE gene = 'cytb') AS cytb,
           max(length) FILTER (WHERE gene = 'nad1') AS nad1,
           max(length) FILTER (WHERE gene = 'nad2') AS nad2,
           max(length) FILTER (WHERE gene = 'nad3') AS nad3,
           max(length) FILTER (WHERE gene = 'nad4') AS nad4,
           max(length) FILTER (WHERE gene = 'nad4l') AS nad4l,
           max(length) FILTER (WHERE gene = 'nad5') AS nad5,
           max(length) FILTER (WHERE gene = 'nad6') AS nad6,
           max(length) FILTER (WHERE gene = 'trna_phe') AS trna_phe,
           max(length) FILTER (WHERE gene = 'trna_val') AS trna_val,
           max(length) FILTER (WHERE gene = 'trna_leuuag') AS trna_leuuag,
           max(length) FILTER (WHERE gene = 'trna_leuuaa') AS trna_leuuaa,
           max(length) FILTER (WHERE gene = 'trna_ile') AS trna_ile,
           max(length) FILTER (WHERE gene = 'trna_met') AS trna_met,
           max(length) FILTER (WHERE gene = 'trna_thr') AS trna_thr,
           max(length) FILTER (WHERE gene = 'trna_pro') AS trna_pro,
           max(length) FILTER (WHERE gene = 'trna_lys') AS trna_lys,
           max(length) FILTER (WHERE gene = 'trna_asp') AS trna_asp,
           max(length) FILTER (WHERE gene = 'trna_glu') AS trna_glu,
           max(length) FILTER (WHERE gene = 'trna_sergcu') AS trna_sergcu,
           max(length) FILTER (WHERE gene = 'trna_seruga') AS trna_seruga,
           max(length) FILTER (WHERE gene = 'trna_tyr') AS trna_tyr,
           max(length) FILTER (WHERE gene = 'trna_cys') AS trna_cys,
           max(length) FILTER (WHERE gene = 'trna_trp') AS trna_trp,
           max(length) FILTER (WHERE gene = 'trna_ala') AS trna_ala,
           max(length) FILTER (WHERE gene = 'trna_asn') AS trna_asn,
           max(length) FILTER (WHERE gene = 'trna_gly') AS trna_gly,
           max(length) FILTER (WHERE gene = 'trna_arg') AS trna_arg,
           max(length) FILTER (WHERE gene = 'trna_his') AS trna_his,
           max(length) FILTER (WHERE gene = 'trna_gln') AS trna_gln,
           max(length) FILTER (WHERE gene = 'atp9') AS atp9,
           max(length) FILTER (WHERE gene = 'mtmuts') AS mtmuts,
           max(translated_length) FILTER (WHERE gene = 'atp6') AS atp6_trans,
           max(translated_length) FILTER (WHERE gene = 'atp8') AS atp8_trans,
           max(translated_length) FILTER (WHERE gene = 'cox1') AS cox1_trans,
           max(translated_length) FILTER (WHERE gene = 'cox2') AS cox2_trans,
           max(translated_length) FILTER (WHERE gene = 'cox3') AS cox3_trans,
           max(translated_length) FILTER (WHERE gene = 'cytb') AS cytb_trans,
           max(translated_length) FILTER (WHERE gene = 'nad1') AS nad1_trans,
           max(translated_length) FILTER (WHERE gene = 'nad2') AS nad2_trans,
           max(translated_length) FILTER (WHERE gene = 'nad3') AS nad3_trans,
           max(translated_length) FILTER (WHERE gene = 'nad4') AS nad4_trans,
           max(translated_length) FILTER (WHERE gene = 'nad4l') AS nad4l_trans,
           max(translated_length) FILTER (WHERE gene = 'nad5') AS nad5_trans,
           max(translated_length) FILTER (WHERE gene = 'nad6') AS nad6_trans,
           max(translated_length) FILTER (WHERE gene = 'atp9') AS atp9_trans,
           max(translated_length) FILTER (WHERE gene = 'mtmuts') AS mtmuts_trans
    FROM v3.mito_annotation_gene
    GROUP BY annotation_id
) g ON g.annotation_id = n.annotation_id;
COMMENT ON VIEW v3.mitogenome_data IS
  'Compatibility view: the 102 kept columns of the old mitogenome_data table, in its order. One '
  'row per (assembly, annotation), plus one per unannotated assembly. Not a write path.';

CREATE OR REPLACE VIEW v3.mitogenome_submission_view AS
SELECT s.og_num,
       a.og_id, a.tech, a.seq_date, a.code,
       n.annotation,
       a.stats, a.length,
       n.length_emma, n.cds_no, n.trna_no, n.rrna_no,
       a.avg_coverage, a.avg_base_coverage,
       n.extra_genes, n.missing_genes, n.order_correct,
       e.table2asn_status, e.warning_codes, e.webin_status, e.webin_reason, e.submission_ready,
       l.validated_species_name, l.validator
FROM v3.mito_assembly a
LEFT JOIN v3.mito_annotation n ON n.assembly_id = a.assembly_id
LEFT JOIN public.sample s ON s.og_id = a.og_id
LEFT JOIN public.ena_validation_attempts e
       ON e.og_id = a.og_id AND e.tech = a.tech AND e.seq_date = a.seq_date AND e.code = a.code
      AND e.annotation = n.annotation
LEFT JOIN public.lca_validation l
       ON l.og_id = a.og_id AND l.tech = a.tech AND l.seq_date = a.seq_date AND l.code = a.code
      AND l.annotation = n.annotation;
COMMENT ON VIEW v3.mitogenome_submission_view IS
  'mitogenome_submission_view rebuilt on the v3 tables. The ENA and LCA joins move to '
  'annotation_id at R.7.';

-- v_mito_annotation_genes is generated from mito_gene, so a new gene needs no hand-written SQL.
CREATE OR REPLACE FUNCTION v3.rebuild_mito_gene_views() RETURNS void
LANGUAGE plpgsql SET search_path = v3, public, pg_temp AS $fn$
DECLARE
  lens  text;
  trans text;
BEGIN
  SELECT string_agg(format('max(g.length) FILTER (WHERE g.gene = %L) AS %I', gene, gene), E',\n       '
                    ORDER BY sort_order)
    INTO lens FROM mito_gene;
  SELECT string_agg(format('max(g.translated_length) FILTER (WHERE g.gene = %L) AS %I', gene, gene || '_trans'),
                    E',\n       ' ORDER BY sort_order)
    INTO trans FROM mito_gene WHERE has_translation;
  -- Dropped and recreated so a new gene can take its place in the column order. Nothing may be
  -- built on this view for that reason.
  DROP VIEW IF EXISTS v_mito_annotation_genes;
  EXECUTE format($v$
    CREATE VIEW v_mito_annotation_genes AS
    SELECT a.og_id, a.tech, a.seq_date, a.code, n.annotation, n.annotation_id, n.is_selected,
       %s,
       %s
    FROM mito_annotation n
    JOIN mito_assembly a ON a.assembly_id = n.assembly_id
    LEFT JOIN mito_annotation_gene g ON g.annotation_id = n.annotation_id
    GROUP BY a.og_id, a.tech, a.seq_date, a.code, n.annotation, n.annotation_id, n.is_selected$v$,
    lens, trans);
  COMMENT ON VIEW v_mito_annotation_genes IS
    'One row per annotation, gene lengths wide. Generated by rebuild_mito_gene_views() from '
    'mito_gene; is_selected is display only. Do not build other views on this one.';
  GRANT SELECT ON v_mito_annotation_genes TO readonly;
END
$fn$;
COMMENT ON FUNCTION v3.rebuild_mito_gene_views() IS
  'Regenerate v_mito_annotation_genes from mito_gene. Run after adding a gene.';

-- Checks (window-only: dropped at R.6) ------------------------------------------------------

CREATE OR REPLACE FUNCTION v3.check_mito() RETURNS TABLE (check_name text, problems bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  check_name := 'mitogenome_data: v3 rows not in public';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at FROM v3.mitogenome_data
    EXCEPT ALL
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at FROM public.mitogenome_data) x;
  RETURN NEXT;

  check_name := 'mitogenome_data: public rows not in v3';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at FROM public.mitogenome_data
    EXCEPT ALL
    SELECT og_id, tech, seq_date, code, stats, length, length_emma, cds_no, trna_no, rrna_no, rrna12s, rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5, nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr, trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr, trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln, manual_curation_notes, annotation, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans, cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans, nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes, order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x, breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction, depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at, trna_advisory, order_variant, order_deviation, annotation_gaps, order_variant_taxon_check, order_status, order_deviation_detail, expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories, mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci, annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts, mtmuts_trans, annotation_stats_version, annotation_updated_at FROM v3.mitogenome_data) x;
  RETURN NEXT;

  check_name := 'mitogenome_submission_view: differs (either way)';
  SELECT (SELECT count(*) FROM (SELECT * FROM v3.mitogenome_submission_view
                                EXCEPT ALL SELECT * FROM public.mitogenome_submission_view) x)
       + (SELECT count(*) FROM (SELECT * FROM public.mitogenome_submission_view
                                EXCEPT ALL SELECT * FROM v3.mitogenome_submission_view) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'child rows not resolving to exactly one v3 annotation';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, tech, seq_date, code, annotation FROM public.lca_validation
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.lca
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.lca_raw_results
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.blast_filtered_lca
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.ena_validation_attempts
    UNION ALL SELECT og_id, tech, seq_date, code, annotation FROM public.ena_submissions) c
  WHERE (SELECT count(*) FROM v3.mito_annotation n JOIN v3.mito_assembly a USING (assembly_id)
         WHERE (a.og_id, a.tech, a.seq_date, a.code, n.annotation)
             = (c.og_id, c.tech, c.seq_date, c.code, c.annotation)) <> 1;
  RETURN NEXT;

  check_name := 'annotations selected (none expected before a person chooses)';
  SELECT count(*) INTO problems FROM v3.mito_annotation WHERE is_selected;
  RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v3.check_mito() IS
  'Phase R window only: v3 against public, by key and value. Every problems value must be 0, '
  'except selected annotations once someone has chosen one. Dropped at the R.6 merge.';

-- Backfill and verify -----------------------------------------------------------------------

SELECT * FROM v3.sync_mito();
SELECT v3.rebuild_mito_gene_views();

DO $verify$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM v3.check_mito() LOOP
    IF r.problems <> 0 THEN
      RAISE EXCEPTION '051 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM v3.mito_gene) <> 39 THEN
    RAISE EXCEPTION '051: expected 39 genes in mito_gene';
  END IF;
END
$verify$;

GRANT SELECT ON ALL TABLES IN SCHEMA v3 TO readonly;
GRANT SELECT ON v3.mitogenome_data TO oceangenom_web;

COMMIT;
