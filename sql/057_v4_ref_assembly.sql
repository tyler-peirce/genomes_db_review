-- 057_v4_ref_assembly.sql -- Phase RG.1: the reference-genome assembly tables in schema v4.
--
-- Why. public.ref_genomes is seven tools written sideways at one key, (og_id, seq_date, stage,
-- haplotype, version): each push script upserts its own block of columns, so a row holds whatever
-- happened to run there and 66% of its cells are NULL (70,741 of 107,908 on 2026-10-19). This
-- builds one row per assembly, one per part of it, one table per tool, and the runs it came from
-- (docs/ref_genomes_runbook_rg0_rg5.md §2):
--   ref_stage                 lookup: 0 contigs, 1 scaffolded, 2 decontaminated, 3 curated
--   ref_assembly              one per (og_id, seq_date, version)
--   ref_assembly_part         one per (assembly, stage, haplotype); dual = hap1 and hap2 together
--   ref_assembly_run          the PacBio/ONT sequencing rows an assembly was built from
--   ref_gfastats, ref_busco, ref_merqury_qv, ref_merqury_completeness, ref_omnic,
--   ref_seqkit_stats, ref_chromosome_stats
--                             one row per part, only where that tool ran (CHECK num_nonnulls > 0)
-- and views:
--   v4.ref_genomes                  compatibility: public.ref_genomes's 58 columns, in its order
--   v4.goat_species_v1              today's definition, its ref_genomes EXISTS on ref_assembly
--   v4.v_ref_assembly_status        one row per assembly: stages present, and stages per tool
--   v4.v_ref_assembly_summary       final stage per assembly and haplotype, the headline metrics
--   v4.v_ref_assembly_run_readiness assemblies with no run link, and the OG's long-read rows
--
-- Separate from v3 (owner decision, 2026-10-19). v4 references only public.sample and
-- public.sequencing, and nothing in public references v4, so DROP SCHEMA v4 CASCADE is a clean
-- revert and Phase R's R.6 merge does not touch it.
--
-- Not carried as columns: k_mer_set and hap2_chr_level_max_len (0 values on live, no writer).
-- v4.ref_genomes shows them as typed NULLs; the sync refuses a public row that fills them.
--
-- Triage (docs/ref_genomes_rg0_record.md §3). public is not changed. v4.ref_key_map remaps 3
-- assemblies (7 rows): OG820 240501 hi1 -> hic1, OG906 '' -> 250212, OG88G -> OG88.
-- v4.ref_excluded_rows leaves out 12 rows: OG108 version 231027 (3), OG90 seq_date bc2008 (6),
-- OG90_bc2008 (2), and OG763's empty stage-1 dual row (1). They stay in public until RG.6.
-- A public row with no value at all is never carried (none besides OG763's today).
--
-- Run links: exact (og_id, seq_date) match to PacBio HiFi/PacBio/ONT DNA rows, every match
-- linked (several SMRT cells on one day). No fuzzy dates: 61 assemblies stay unlinked and are
-- listed by v_ref_assembly_run_readiness. A trigger keeps RNA and Illumina rows out. ON DELETE
-- CASCADE to public.sequencing, so import_v2.py removing a stale row is never blocked.
--
-- ref_assembly.og_id references public.sample. public.ref_genomes has no such FK, so during the
-- window a sample deletion that would orphan an assembly is rejected (import_v2.py quarantines
-- that row). That is the intended relation, arriving early, as in 052.
--
-- Sync and checks follow 052: v4.sync_ref_assembly() is the backfill and the nightly sync
-- (scripts/sync_v4.sql), v4.check_ref_assembly() proves equality with public both ways. Check
-- names starting 'note:' are informational. Both functions and v4.sync_ref_genomes_source are
-- window-only (dropped at RG.6).
--
-- Guards: needs public.ref_genomes and public.sample; idempotent (IF NOT EXISTS, ON CONFLICT);
-- asserts before COMMIT that the triage lists matched exactly 7 remapped and 12 excluded rows,
-- and that every check is 0.
--
-- Revert: sql/revert/057_v4_ref_assembly_revert.sql (refuses while 058/059 objects exist).

BEGIN;

DO $pre$
BEGIN
  IF to_regclass('public.ref_genomes') IS NULL OR to_regclass('public.sample') IS NULL THEN
    RAISE EXCEPTION '057 needs public.ref_genomes and public.sample';
  END IF;
END
$pre$;

CREATE SCHEMA IF NOT EXISTS v4;
COMMENT ON SCHEMA v4 IS
  'Phase RG: the reference-genome design, built beside public and kept in sync with it until the '
  'RG.6 swap. Nothing in public depends on it. docs/ref_genomes_runbook_rg0_rg5.md';
GRANT USAGE ON SCHEMA v4 TO readonly, oceangenom_web;
ALTER DEFAULT PRIVILEGES IN SCHEMA v4 GRANT SELECT ON TABLES TO readonly;

-- Identity ------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS v4.ref_stage (
    stage       integer PRIMARY KEY,
    name        text    NOT NULL UNIQUE,
    description text    NOT NULL
);
COMMENT ON TABLE v4.ref_stage IS
  'Assembly stages, from the pipeline file names (<og>_v<date>.<version>.<stage>.<tool>...).';
INSERT INTO v4.ref_stage (stage, name, description) VALUES
  (0, 'contigs',        'hifiasm output: p_ctg/a_ctg (HiFi only) or Hi-C-phased hap1/hap2 (.0.hifiasm)'),
  (1, 'scaffolded',     'YaHS/SALSA scaffolds (.1.yahs, .1.salsa); for hifiN, the HiFi-only hifiasm haplotypes (.1.hifiasm)'),
  (2, 'decontaminated', 'after Tiara/FCS-GX decontamination (.2.tiara)'),
  (3, 'curated',        'after manual curation (.3.curated); written by the post-curation pipeline')
ON CONFLICT (stage) DO NOTHING;

CREATE TABLE IF NOT EXISTS v4.ref_assembly (
    assembly_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    og_id       text NOT NULL REFERENCES public.sample (og_id),
    seq_date    text NOT NULL CHECK (seq_date ~ '^[0-9]{6}$'),  -- identifier component, YYMMDD
    version     text NOT NULL CHECK (version ~ '^(hic|hifi|ont)[0-9]+$'),
    strategy    text    GENERATED ALWAYS AS (substring(version FROM '^[a-z]+')) STORED,
    attempt     integer GENERATED ALWAYS AS ((substring(version FROM '[0-9]+$'))::integer) STORED,
    og_num      integer GENERATED ALWAYS AS ((SUBSTRING(og_id FROM 3))::integer) STORED,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_assembly_natural_key UNIQUE (og_id, seq_date, version)
);
COMMENT ON TABLE v4.ref_assembly IS
  'One reference-genome assembly attempt: hicN (HiFi + Hi-C), hifiN (HiFi only) or ontN. Written by '
  'OceanOmics-OceanGenomes-ref-genomes and -post-curation push scripts.';

CREATE TABLE IF NOT EXISTS v4.ref_assembly_part (
    part_id     bigint  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assembly_id bigint  NOT NULL REFERENCES v4.ref_assembly ON DELETE CASCADE,
    stage       integer NOT NULL REFERENCES v4.ref_stage,
    haplotype   text    NOT NULL CHECK (haplotype IN ('hap1', 'hap2', 'dual', 'p_ctg', 'a_ctg')),
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_assembly_part_natural_key UNIQUE (assembly_id, stage, haplotype)
);
COMMENT ON TABLE v4.ref_assembly_part IS
  'One sequence set of an assembly at a stage: hap1, hap2, p_ctg/a_ctg (hifiasm primary/alternate '
  'contigs), or dual.';
COMMENT ON COLUMN v4.ref_assembly_part.haplotype IS
  'dual = hap1 and hap2 together: Merqury on both haplotypes, or OMNIC on the combined scaffold set.';

CREATE TABLE IF NOT EXISTS v4.ref_assembly_run (
    assembly_id   bigint NOT NULL REFERENCES v4.ref_assembly ON DELETE CASCADE,
    sequencing_id text   NOT NULL REFERENCES public.sequencing (sequencing_id) ON DELETE CASCADE,
    PRIMARY KEY (assembly_id, sequencing_id)
);
CREATE INDEX IF NOT EXISTS ref_assembly_run_sequencing_id_idx ON v4.ref_assembly_run (sequencing_id);
COMMENT ON TABLE v4.ref_assembly_run IS
  'The sequencing rows an assembly was built from: PacBio/ONT DNA, and Hi-C once writers record it '
  '(trigger).';

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
DROP TRIGGER IF EXISTS ref_assembly_run_genomic_only ON v4.ref_assembly_run;
CREATE TRIGGER ref_assembly_run_genomic_only BEFORE INSERT OR UPDATE ON v4.ref_assembly_run
  FOR EACH ROW EXECUTE FUNCTION v4.ref_assembly_run_genomic_only();

-- One table per tool ------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS v4.ref_gfastats (
    part_id                        bigint PRIMARY KEY REFERENCES v4.ref_assembly_part ON DELETE CASCADE,
    num_contigs                    integer,
    contig_n50                     bigint,
    contig_n50_size_mb             numeric(10,2),
    num_scaffolds                  integer,
    scaffold_n50                   bigint,
    scaffold_n50_size_mb           numeric(10,2),
    largest_scaffold               bigint,
    largest_scaffold_size_mb       numeric(10,2),
    total_scaffold_length          bigint,
    total_scaffold_length_size_mb  numeric(10,2),
    gc_content_percent             numeric(5,2),
    num_gaps                       integer,
    loaded_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_gfastats_has_value CHECK (num_nonnulls(num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, num_gaps) > 0)
);
COMMENT ON TABLE v4.ref_gfastats IS
  'gfastats assembly statistics; the authoritative N50. Written by 04a/04b_*push_gfa* (ref repo) and 04a_push_gfa_results_to_sqldb.py (post-curation, which adds num_gaps). The *_size_mb columns are the tool''s own rounding, stored, not derived (RG.0 §1.6).';

CREATE TABLE IF NOT EXISTS v4.ref_busco (
    part_id                      bigint PRIMARY KEY REFERENCES v4.ref_assembly_part ON DELETE CASCADE,
    dataset                      text,
    complete                     numeric(4,1),
    single_copy                  numeric(4,1),
    multi_copy                   numeric(4,1),
    fragmented                   numeric(4,1),
    missing                      numeric(4,1),
    n_markers                    integer,
    internal_stop_codon_percent  numeric(5,2),
    scaffold_n50_bus             bigint,
    contigs_n50_bus              bigint,
    percent_gaps                 numeric(5,2),
    number_of_scaffolds          integer,
    loaded_at                    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_busco_has_value CHECK (num_nonnulls(dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds) > 0)
);
COMMENT ON TABLE v4.ref_busco IS
  'BUSCO completeness and BUSCO''s own assembly statistics. Written by 03a_push_busco_results_to_sqldb.py (ref repo and post-curation).';

CREATE TABLE IF NOT EXISTS v4.ref_merqury_qv (
    part_id                 bigint PRIMARY KEY REFERENCES v4.ref_assembly_part ON DELETE CASCADE,
    unique_k_mers_assembly  bigint,
    k_mers_total            bigint,
    qv                      numeric(6,4),
    error                   double precision,
    loaded_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_merqury_qv_has_value CHECK (num_nonnulls(unique_k_mers_assembly, k_mers_total, qv, error) > 0)
);
COMMENT ON TABLE v4.ref_merqury_qv IS
  'Merqury consensus QV. Written by 02b_push_merqury_qv_results_to_sqldb.py (ref repo and post-curation). On a dual part it is the value for hap1 and hap2 together.';

CREATE TABLE IF NOT EXISTS v4.ref_merqury_completeness (
    part_id       bigint PRIMARY KEY REFERENCES v4.ref_assembly_part ON DELETE CASCADE,
    solid_k_mers  bigint,
    total_k_mers  bigint,
    completeness  numeric(7,4),
    loaded_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_merqury_completeness_has_value CHECK (num_nonnulls(solid_k_mers, total_k_mers, completeness) > 0)
);
COMMENT ON TABLE v4.ref_merqury_completeness IS
  'Merqury k-mer completeness. Written by 02d_push_merqury_completeness_results_to_sqldb.py (ref repo and post-curation). public.ref_genomes.k_mer_set is not carried: it was never filled.';

CREATE TABLE IF NOT EXISTS v4.ref_omnic (
    part_id                    bigint PRIMARY KEY REFERENCES v4.ref_assembly_part ON DELETE CASCADE,
    total                      bigint,
    total_unmapped             bigint,
    total_single_sided_mapped  bigint,
    total_mapped               bigint,
    total_dups                 bigint,
    total_nodups               bigint,
    cis                        bigint,
    trans                      bigint,
    loaded_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_omnic_has_value CHECK (num_nonnulls(total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans) > 0)
);
COMMENT ON TABLE v4.ref_omnic IS
  'Hi-C mapping QC (Dovetail OMNIC). Written by 05a_push_omnic_results_to_sqldb.py (ref repo). Also present on hifi1 stage-1 haplotypes: Hi-C mapped to the HiFi-only haplotypes before scaffolding (RG.0 §3).';

CREATE TABLE IF NOT EXISTS v4.ref_seqkit_stats (
    part_id    bigint PRIMARY KEY REFERENCES v4.ref_assembly_part ON DELETE CASCADE,
    format     text,
    "type"     text,
    num_seqs   integer,
    sum_len    bigint,
    min_len    bigint,
    avg_len    numeric(20,2),
    max_len    bigint,
    loaded_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_seqkit_stats_has_value CHECK (num_nonnulls(format, "type", num_seqs, sum_len, min_len, avg_len, max_len) > 0)
);
COMMENT ON TABLE v4.ref_seqkit_stats IS
  'seqkit stats of the curated FASTA. Written by 05a_push_stats_compiled_results_to_sql.py (post-curation).';

CREATE TABLE IF NOT EXISTS v4.ref_chromosome_stats (
    part_id           bigint PRIMARY KEY REFERENCES v4.ref_assembly_part ON DELETE CASCADE,
    num_chromosomes   integer,
    pct_assigned      numeric(5,2),
    pct_no_super      numeric(5,2),
    num_seq_no_super  integer,
    max_len_no_super  bigint,
    loaded_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ref_chromosome_stats_has_value CHECK (num_nonnulls(num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super) > 0)
);
COMMENT ON TABLE v4.ref_chromosome_stats IS
  'Chromosome assignment of the curated assembly (SUPER_* scaffolds). Written by 06b_push_percentage_stats_to_sqldb.py (post-curation).';

COMMENT ON COLUMN v4.ref_busco.scaffold_n50_bus IS
  'BUSCO''s own scaffold N50; not reliable on every BUSCO version (see 052, draft_busco). Use '
  'ref_gfastats.scaffold_n50.';
COMMENT ON COLUMN v4.ref_busco.contigs_n50_bus IS
  'BUSCO''s own contig N50; see scaffold_n50_bus. Use ref_gfastats.contig_n50.';

-- Triage lists (RG.0 §3) --------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS v4.ref_key_map (
    from_og_id    text NOT NULL,
    from_seq_date text NOT NULL,
    from_version  text NOT NULL,
    to_og_id      text NOT NULL,
    to_seq_date   text NOT NULL,
    to_version    text NOT NULL,
    reason        text NOT NULL,
    PRIMARY KEY (from_og_id, from_seq_date, from_version)
);
COMMENT ON TABLE v4.ref_key_map IS
  'public assembly keys that v4 carries under a corrected key. Window-only: RG.6 rewrites the '
  'public rows or archives them. Rows are added only through docs/ref_genomes_rg0_record.md.';
INSERT INTO v4.ref_key_map VALUES
  ('OG820', '240501', 'hi1',   'OG820', '240501', 'hic1',  'version typo; 240501 hic1 has no stage 1 (RG.0)'),
  ('OG906', '',       'hic1',  'OG906', '250212', 'hic1',  'blank seq_date; 250212 is the OG''s only date (RG.0)'),
  ('OG88G', '230728', 'hifi1', 'OG88',  '230728', 'hifi1', 'og_id carried the tissue letter (RG.0)')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS v4.ref_excluded_rows (
    exclusion_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_table text    NOT NULL CHECK (source_table IN ('ref_genomes', 'raw_qc', 'hifi_reads_qc', 'hic_reads_qc',
                                                         'ref_genomes_assembly_uploads', 'ref_genomes_sra_uploads')),
    og_id        text    NOT NULL,
    seq_date     text,      -- NULL matches any
    version      text,      -- NULL matches any
    stage        integer,   -- NULL matches any
    haplotype    text,      -- NULL matches any
    reason       text    NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ref_excluded_rows_pattern_uq ON v4.ref_excluded_rows
  (source_table, og_id, coalesce(seq_date, ''), coalesce(version, ''), coalesce(stage, -1), coalesce(haplotype, ''));
COMMENT ON TABLE v4.ref_excluded_rows IS
  'public rows that v4 does not carry; NULL columns match anything. Window-only: RG.6 archives the '
  'rows. Rows are added only through docs/ref_genomes_rg0_record.md.';
INSERT INTO v4.ref_excluded_rows (source_table, og_id, seq_date, version, stage, haplotype, reason)
SELECT * FROM (VALUES
  ('ref_genomes', 'OG108',       '231027', '231027', NULL::integer, NULL, 'version is a date; assembly unclear (owner, RG.0)'),
  ('ref_genomes', 'OG90',        'bc2008', NULL,     NULL,          NULL, 'barcode variant, seq_date bc2008 (owner, RG.0)'),
  ('ref_genomes', 'OG90_bc2008', NULL,     NULL,     NULL,          NULL, 'barcode variant; og_id not in sample; collides with OG90 240821 (owner, RG.0)'),
  ('ref_genomes', 'OG763',       '251117', 'hifi1',  1,             'dual', 'no value in any column (owner, RG.0)')
) v (source_table, og_id, seq_date, version, stage, haplotype, reason)
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_excluded_rows x
                  WHERE (x.source_table, x.og_id) = (v.source_table, v.og_id)
                    AND x.seq_date IS NOT DISTINCT FROM v.seq_date AND x.version IS NOT DISTINCT FROM v.version
                    AND x.stage IS NOT DISTINCT FROM v.stage AND x.haplotype IS NOT DISTINCT FROM v.haplotype);

-- Sync (window-only: dropped at RG.6) -------------------------------------------------------

CREATE OR REPLACE VIEW v4.sync_ref_genomes_source AS
SELECT coalesce(m.to_og_id, r.og_id) AS og_id,
       coalesce(m.to_seq_date, r.seq_date) AS seq_date,
       r.stage,
       r.haplotype,
       coalesce(m.to_version, r.version) AS version,
       r.num_contigs,
       r.contig_n50,
       r.contig_n50_size_mb,
       r.num_scaffolds,
       r.scaffold_n50,
       r.scaffold_n50_size_mb,
       r.largest_scaffold,
       r.largest_scaffold_size_mb,
       r.total_scaffold_length,
       r.total_scaffold_length_size_mb,
       r.gc_content_percent,
       r.dataset,
       r.complete,
       r.single_copy,
       r.multi_copy,
       r.fragmented,
       r.missing,
       r.n_markers,
       r.internal_stop_codon_percent,
       r.scaffold_n50_bus,
       r.contigs_n50_bus,
       r.percent_gaps,
       r.number_of_scaffolds,
       r.unique_k_mers_assembly,
       r.k_mers_total,
       r.qv,
       r.error,
       r.k_mer_set,
       r.solid_k_mers,
       r.total_k_mers,
       r.completeness,
       r.total,
       r.total_unmapped,
       r.total_single_sided_mapped,
       r.total_mapped,
       r.total_dups,
       r.total_nodups,
       r.cis,
       r.trans,
       r.hap2_chr_level_max_len,
       r.format,
       r."type",
       r.num_seqs,
       r.sum_len,
       r.min_len,
       r.avg_len,
       r.max_len,
       r.num_chromosomes,
       r.pct_assigned,
       r.pct_no_super,
       r.num_seq_no_super,
       r.max_len_no_super,
       r.num_gaps,
       CASE
         WHEN NOT EXISTS (SELECT 1 FROM public.sample s WHERE s.og_id = coalesce(m.to_og_id, r.og_id))
           THEN 'og_id not in sample'
         WHEN coalesce(m.to_seq_date, r.seq_date) !~ '^[0-9]{6}$' THEN 'seq_date not YYMMDD'
         WHEN coalesce(m.to_version, r.version) !~ '^(hic|hifi|ont)[0-9]+$' THEN 'version not hicN/hifiN/ontN'
         WHEN r.haplotype NOT IN ('hap1', 'hap2', 'dual', 'p_ctg', 'a_ctg') THEN 'unknown haplotype'
         WHEN NOT EXISTS (SELECT 1 FROM v4.ref_stage st WHERE st.stage = r.stage) THEN 'unknown stage'
         WHEN num_nonnulls(r.k_mer_set, r.hap2_chr_level_max_len) > 0 THEN 'value in a column v4 does not carry'
       END AS key_problem,
       num_nonnulls(r.num_contigs, r.contig_n50, r.contig_n50_size_mb, r.num_scaffolds, r.scaffold_n50, r.scaffold_n50_size_mb, r.largest_scaffold, r.largest_scaffold_size_mb, r.total_scaffold_length, r.total_scaffold_length_size_mb, r.gc_content_percent, r.dataset, r.complete, r.single_copy, r.multi_copy, r.fragmented, r.missing, r.n_markers, r.internal_stop_codon_percent, r.scaffold_n50_bus, r.contigs_n50_bus, r.percent_gaps, r.number_of_scaffolds, r.unique_k_mers_assembly, r.k_mers_total, r.qv, r.error, r.k_mer_set, r.solid_k_mers, r.total_k_mers, r.completeness, r.total, r.total_unmapped, r.total_single_sided_mapped, r.total_mapped, r.total_dups, r.total_nodups, r.cis, r.trans, r.hap2_chr_level_max_len, r.format, r."type", r.num_seqs, r.sum_len, r.min_len, r.avg_len, r.max_len, r.num_chromosomes, r.pct_assigned, r.pct_no_super, r.num_seq_no_super, r.max_len_no_super, r.num_gaps) = 0 AS is_empty,
       (m.from_og_id IS NOT NULL) AS is_remapped
FROM public.ref_genomes r
LEFT JOIN v4.ref_key_map m ON (m.from_og_id, m.from_seq_date, m.from_version) = (r.og_id, r.seq_date, r.version)
WHERE NOT EXISTS (SELECT 1 FROM v4.ref_excluded_rows x
                  WHERE x.source_table = 'ref_genomes' AND x.og_id = r.og_id
                    AND (x.seq_date  IS NULL OR x.seq_date  = r.seq_date)
                    AND (x.version   IS NULL OR x.version   = r.version)
                    AND (x.stage     IS NULL OR x.stage     = r.stage)
                    AND (x.haplotype IS NULL OR x.haplotype = r.haplotype));
COMMENT ON VIEW v4.sync_ref_genomes_source IS
  'Phase RG window only: public.ref_genomes after ref_excluded_rows and ref_key_map, with a '
  'key_problem verdict. What the sync copies and the check compares against. Dropped at RG.6.';

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
COMMENT ON FUNCTION v4.sync_ref_assembly() IS
  'Phase RG window only: copy public.ref_genomes into the v4 assembly tables, keyed on natural keys '
  'so ids stay stable. Skips rows with a key_problem (check_ref_assembly then fails). Dropped at RG.6.';

-- Views ---------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW v4.ref_genomes AS
SELECT a.og_id,
       a.seq_date,
       p.stage,
       p.haplotype,
       gf.num_contigs,
       gf.contig_n50,
       gf.contig_n50_size_mb,
       gf.num_scaffolds,
       gf.scaffold_n50,
       gf.scaffold_n50_size_mb,
       gf.largest_scaffold,
       gf.largest_scaffold_size_mb,
       gf.total_scaffold_length,
       gf.total_scaffold_length_size_mb,
       gf.gc_content_percent,
       bu.dataset,
       bu.complete,
       bu.single_copy,
       bu.multi_copy,
       bu.fragmented,
       bu.missing,
       bu.n_markers,
       bu.internal_stop_codon_percent,
       bu.scaffold_n50_bus,
       bu.contigs_n50_bus,
       bu.percent_gaps,
       bu.number_of_scaffolds,
       mq.unique_k_mers_assembly,
       mq.k_mers_total,
       mq.qv,
       mq.error,
       NULL::text AS k_mer_set,
       mc.solid_k_mers,
       mc.total_k_mers,
       mc.completeness,
       om.total,
       om.total_unmapped,
       om.total_single_sided_mapped,
       om.total_mapped,
       om.total_dups,
       om.total_nodups,
       om.cis,
       om.trans,
       NULL::bigint AS hap2_chr_level_max_len,
       sk.format,
       sk."type",
       sk.num_seqs,
       sk.sum_len,
       sk.min_len,
       sk.avg_len,
       sk.max_len,
       ch.num_chromosomes,
       ch.pct_assigned,
       ch.pct_no_super,
       ch.num_seq_no_super,
       ch.max_len_no_super,
       a.version,
       gf.num_gaps
FROM v4.ref_assembly_part p
JOIN v4.ref_assembly a ON a.assembly_id = p.assembly_id
LEFT JOIN v4.ref_gfastats gf ON gf.part_id = p.part_id
LEFT JOIN v4.ref_busco bu ON bu.part_id = p.part_id
LEFT JOIN v4.ref_merqury_qv mq ON mq.part_id = p.part_id
LEFT JOIN v4.ref_merqury_completeness mc ON mc.part_id = p.part_id
LEFT JOIN v4.ref_omnic om ON om.part_id = p.part_id
LEFT JOIN v4.ref_seqkit_stats sk ON sk.part_id = p.part_id
LEFT JOIN v4.ref_chromosome_stats ch ON ch.part_id = p.part_id
;
COMMENT ON VIEW v4.ref_genomes IS
  'Compatibility view: public.ref_genomes''s 58 columns in its order, one row per part. k_mer_set '
  'and hap2_chr_level_max_len are always NULL. Not a write path.';

CREATE OR REPLACE VIEW v4.goat_species_v1 AS
SELECT s.ncbi_taxon_id,
    s.family,
    s.species,
    COALESCE(s.epithet, '-'::text) AS subspecies_epithet,
        CASE
            WHEN s.ncbi_taxon_id = ANY (ARRAY[215367, 182658, 163129, 7793, 582430]) THEN 'priority_target'::text
            ELSE 'potential_target'::text
        END AS target_list_status,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM public.sample samp
              WHERE samp.nominal_species_id = s.species)) THEN 'sample_collected'::text
            ELSE NULL::text
        END AS sampling_status,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM public.sample samp
              WHERE samp.nominal_species_id = s.species AND samp.ncbi_bioproject_id_lvl_3_hifi IS NOT NULL)) THEN 'submitted'::text
            WHEN (EXISTS ( SELECT 1
               FROM public.sample samp
                 JOIN v4.ref_assembly rg ON rg.og_id = samp.og_id
              WHERE samp.nominal_species_id = s.species)) THEN 'in_assembly'::text
            WHEN (EXISTS ( SELECT 1
               FROM public.summary sm
              WHERE sm.nominal_species_id = s.species AND (sm.pacbio_status = ANY (ARRAY['Library Prep - PacBio SMRTbell'::text, 'QC - Femto'::text, 'Sequenced'::text, 'Sequenced, SRE'::text, 'Sequence - PacBio'::text, 'Shearing'::text, 'SRE'::text, 'SRE - ULI'::text, 'ULI'::text])))) THEN 'in_lab'::text
            ELSE NULL::text
        END AS sequencing_status,
    NULL::text AS genome_publication,
    'Ocean Genomes'::text AS primary_project,
    NULL::text AS ebp_collaborator_acronyms,
    NULL::text AS contributing_project_lab,
        CASE
            WHEN s.species = ANY (ARRAY['Neophoca cinerea'::text, 'Careproctus sp.'::text, 'Lethrinus punctulatus'::text, 'Siphonognathus radiatus'::text, 'Dascyllus aruanus'::text, 'Carcharhinus galapagensis'::text]) THEN 'data_conflict'::text
            ELSE ( SELECT samp.collector
               FROM public.sample samp
              WHERE samp.nominal_species_id = s.species AND samp.workflow = 'Reference'::text AND samp.collector IS NOT NULL
             LIMIT 1)
        END AS collected_by,
    NULL::text AS priority_flags,
    COALESCE(s.afd_common_name, '-'::text) AS common_name,
    COALESCE(s.synonym, '-'::text) AS synonym,
    NULL::text AS assigned_sequencing_center
   FROM public.master_species s
  ORDER BY s.family, s.species;
COMMENT ON VIEW v4.goat_species_v1 IS
  'public.goat_species_v1 with its in_assembly test on v4.ref_assembly. For the RG.5 reader test; '
  'replaces the public view at RG.6.';

CREATE OR REPLACE VIEW v4.v_ref_assembly_status AS
SELECT a.og_num, a.og_id, a.seq_date, a.version, a.strategy, a.attempt,
       (SELECT count(*) FROM v4.ref_assembly_run r WHERE r.assembly_id = a.assembly_id) AS run_links,
       count(p.part_id) AS parts,
       string_agg(DISTINCT p.stage::text, ',' ORDER BY p.stage::text) AS stages,
       coalesce(bool_or(p.stage = 3), false) AS curated,
       string_agg(DISTINCT (CASE WHEN gf.part_id IS NOT NULL THEN p.stage END)::text, ',' ORDER BY (CASE WHEN gf.part_id IS NOT NULL THEN p.stage END)::text) AS gfastats_stages,
       string_agg(DISTINCT (CASE WHEN bu.part_id IS NOT NULL THEN p.stage END)::text, ',' ORDER BY (CASE WHEN bu.part_id IS NOT NULL THEN p.stage END)::text) AS busco_stages,
       string_agg(DISTINCT (CASE WHEN mq.part_id IS NOT NULL THEN p.stage END)::text, ',' ORDER BY (CASE WHEN mq.part_id IS NOT NULL THEN p.stage END)::text) AS merqury_qv_stages,
       string_agg(DISTINCT (CASE WHEN mc.part_id IS NOT NULL THEN p.stage END)::text, ',' ORDER BY (CASE WHEN mc.part_id IS NOT NULL THEN p.stage END)::text) AS merqury_completeness_stages,
       string_agg(DISTINCT (CASE WHEN om.part_id IS NOT NULL THEN p.stage END)::text, ',' ORDER BY (CASE WHEN om.part_id IS NOT NULL THEN p.stage END)::text) AS omnic_stages,
       string_agg(DISTINCT (CASE WHEN sk.part_id IS NOT NULL THEN p.stage END)::text, ',' ORDER BY (CASE WHEN sk.part_id IS NOT NULL THEN p.stage END)::text) AS seqkit_stats_stages,
       string_agg(DISTINCT (CASE WHEN ch.part_id IS NOT NULL THEN p.stage END)::text, ',' ORDER BY (CASE WHEN ch.part_id IS NOT NULL THEN p.stage END)::text) AS chromosome_stats_stages
FROM v4.ref_assembly a
JOIN v4.ref_assembly_part p ON p.assembly_id = a.assembly_id
LEFT JOIN v4.ref_gfastats gf ON gf.part_id = p.part_id
LEFT JOIN v4.ref_busco bu ON bu.part_id = p.part_id
LEFT JOIN v4.ref_merqury_qv mq ON mq.part_id = p.part_id
LEFT JOIN v4.ref_merqury_completeness mc ON mc.part_id = p.part_id
LEFT JOIN v4.ref_omnic om ON om.part_id = p.part_id
LEFT JOIN v4.ref_seqkit_stats sk ON sk.part_id = p.part_id
LEFT JOIN v4.ref_chromosome_stats ch ON ch.part_id = p.part_id
GROUP BY a.assembly_id;
COMMENT ON VIEW v4.v_ref_assembly_status IS
  'One row per assembly: which stages exist, and at which stages each tool has results '
  '(e.g. busco_stages = ''0,2,3'').';

CREATE OR REPLACE VIEW v4.v_ref_assembly_summary AS
WITH final_part AS (
  SELECT DISTINCT ON (p.assembly_id, p.haplotype) p.*
  FROM v4.ref_assembly_part p
  WHERE p.haplotype <> 'dual'
  ORDER BY p.assembly_id, p.haplotype, p.stage DESC
)
SELECT a.og_num, a.og_id, a.seq_date, a.version, f.haplotype,
       f.stage AS final_stage, st.name AS final_stage_name,
       gf.num_scaffolds, gf.scaffold_n50_size_mb, gf.total_scaffold_length_size_mb, gf.gc_content_percent,
       ch.num_chromosomes, ch.pct_assigned,
       bu.dataset AS busco_dataset, bu.complete AS busco_complete, bu.single_copy AS busco_single_copy,
       bu.multi_copy AS busco_multi_copy, bu.fragmented AS busco_fragmented, bu.missing AS busco_missing,
       mq.qv, mc.completeness AS kmer_completeness
FROM final_part f
JOIN v4.ref_assembly a ON a.assembly_id = f.assembly_id
JOIN v4.ref_stage st ON st.stage = f.stage
LEFT JOIN v4.ref_gfastats gf ON gf.part_id = f.part_id
LEFT JOIN v4.ref_chromosome_stats ch ON ch.part_id = f.part_id
LEFT JOIN v4.ref_busco bu ON bu.part_id = f.part_id
LEFT JOIN v4.ref_merqury_qv mq ON mq.part_id = f.part_id
LEFT JOIN v4.ref_merqury_completeness mc ON mc.part_id = f.part_id;
COMMENT ON VIEW v4.v_ref_assembly_summary IS
  'One row per assembly and haplotype (not dual): the latest stage present and its headline metrics.';

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

-- Checks (window-only: dropped at RG.6) ------------------------------------------------------

CREATE OR REPLACE FUNCTION v4.check_ref_assembly() RETURNS TABLE (check_name text, problems bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
BEGIN
  check_name := 'ref_genomes: v4 rows not in public (after triage)';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, seq_date, stage, haplotype, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans, hap2_chr_level_max_len, format, "type", num_seqs, sum_len, min_len, avg_len, max_len, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super, version, num_gaps FROM v4.ref_genomes
    EXCEPT ALL
    SELECT og_id, seq_date, stage, haplotype, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans, hap2_chr_level_max_len, format, "type", num_seqs, sum_len, min_len, avg_len, max_len, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super, version, num_gaps FROM v4.sync_ref_genomes_source WHERE key_problem IS NULL AND NOT is_empty) x;
  RETURN NEXT;

  check_name := 'ref_genomes: public rows not in v4 (after triage)';
  SELECT count(*) INTO problems FROM (
    SELECT og_id, seq_date, stage, haplotype, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans, hap2_chr_level_max_len, format, "type", num_seqs, sum_len, min_len, avg_len, max_len, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super, version, num_gaps FROM v4.sync_ref_genomes_source WHERE key_problem IS NULL AND NOT is_empty
    EXCEPT ALL
    SELECT og_id, seq_date, stage, haplotype, num_contigs, contig_n50, contig_n50_size_mb, num_scaffolds, scaffold_n50, scaffold_n50_size_mb, largest_scaffold, largest_scaffold_size_mb, total_scaffold_length, total_scaffold_length_size_mb, gc_content_percent, dataset, complete, single_copy, multi_copy, fragmented, missing, n_markers, internal_stop_codon_percent, scaffold_n50_bus, contigs_n50_bus, percent_gaps, number_of_scaffolds, unique_k_mers_assembly, k_mers_total, qv, error, k_mer_set, solid_k_mers, total_k_mers, completeness, total, total_unmapped, total_single_sided_mapped, total_mapped, total_dups, total_nodups, cis, trans, hap2_chr_level_max_len, format, "type", num_seqs, sum_len, min_len, avg_len, max_len, num_chromosomes, pct_assigned, pct_no_super, num_seq_no_super, max_len_no_super, version, num_gaps FROM v4.ref_genomes) x;
  RETURN NEXT;

  check_name := 'ref_genomes: public rows with an untriaged key problem';
  SELECT count(*) INTO problems FROM v4.sync_ref_genomes_source WHERE key_problem IS NOT NULL;
  RETURN NEXT;

  check_name := 'goat_species_v1: in_assembly species differ';
  SELECT (SELECT count(*) FROM (SELECT samp.nominal_species_id FROM public.sample samp JOIN public.ref_genomes rg ON rg.og_id = samp.og_id
                                EXCEPT SELECT samp.nominal_species_id FROM public.sample samp JOIN v4.ref_assembly rg ON rg.og_id = samp.og_id) x)
       + (SELECT count(*) FROM (SELECT samp.nominal_species_id FROM public.sample samp JOIN v4.ref_assembly rg ON rg.og_id = samp.og_id
                                EXCEPT SELECT samp.nominal_species_id FROM public.sample samp JOIN public.ref_genomes rg ON rg.og_id = samp.og_id) x)
    INTO problems;
  RETURN NEXT;

  check_name := 'parts with no tool row';
  SELECT count(*) INTO problems FROM v4.ref_assembly_part p
  WHERE NOT (EXISTS (SELECT 1 FROM v4.ref_gfastats x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_busco x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_merqury_qv x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_merqury_completeness x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_omnic x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_seqkit_stats x WHERE x.part_id = p.part_id) OR EXISTS (SELECT 1 FROM v4.ref_chromosome_stats x WHERE x.part_id = p.part_id));
  RETURN NEXT;

  check_name := 'note: public rows with no value (not carried)';
  SELECT count(*) INTO problems FROM v4.sync_ref_genomes_source WHERE key_problem IS NULL AND is_empty;
  RETURN NEXT;

  check_name := 'note: assemblies with no run link';
  SELECT count(*) INTO problems FROM v4.v_ref_assembly_run_readiness;
  RETURN NEXT;
END
$fn$;
COMMENT ON FUNCTION v4.check_ref_assembly() IS
  'Phase RG window only: v4 assembly tables against public.ref_genomes after triage, by key and '
  'value. Every problems value must be 0 except checks named note:. Dropped at RG.6.';

-- Backfill and verify -----------------------------------------------------------------------

SELECT * FROM v4.sync_ref_assembly();

DO $verify$
DECLARE
  r        record;
  remapped bigint;
  excluded bigint;
BEGIN
  SELECT count(*) INTO remapped FROM v4.sync_ref_genomes_source WHERE is_remapped;
  SELECT (SELECT count(*) FROM public.ref_genomes) - (SELECT count(*) FROM v4.sync_ref_genomes_source) INTO excluded;
  IF remapped <> 7 OR excluded <> 12 THEN
    RAISE EXCEPTION '057: triage lists matched % remapped (expected 7) and % excluded (expected 12) public rows; '
      're-measure (docs/ref_genomes_rg0_record.md §4)', remapped, excluded;
  END IF;
  FOR r IN SELECT * FROM v4.check_ref_assembly() LOOP
    IF r.check_name LIKE 'note:%' THEN
      RAISE NOTICE '057 %: %', r.check_name, r.problems;
    ELSIF r.problems <> 0 THEN
      RAISE EXCEPTION '057 check failed: % (%)', r.check_name, r.problems;
    END IF;
  END LOOP;
  RAISE NOTICE '057: % assemblies, % parts, % run links',
    (SELECT count(*) FROM v4.ref_assembly), (SELECT count(*) FROM v4.ref_assembly_part),
    (SELECT count(*) FROM v4.ref_assembly_run);
END
$verify$;

GRANT SELECT ON ALL TABLES IN SCHEMA v4 TO readonly;
GRANT SELECT ON v4.ref_genomes TO oceangenom_web;

COMMIT;
