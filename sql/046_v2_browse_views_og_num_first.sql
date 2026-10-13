-- 046_v2_browse_views_og_num_first.sql -- og_num as the first column of all twelve browse views.
--
-- Written 2026-10-13, after the cutover (045). Supersedes the column order of
-- 037_v2_browse_views.sql; every view body is otherwise unchanged.
--
-- Purpose: Sort the browse views numerically. og_id is text, so ORDER BY og_id puts OG1000
--   before OG703. og_num (sample.og_num, the generated integer part of og_id) sorts correctly,
--   but 037 exposed it only on v_tissue_browse, and as its second column. Every view now
--   starts og_num, og_id.
--
--   og_num comes from a join to v2.sample on its primary key, not from re-parsing og_id here,
--   so the views use the one definition of it (036; null on an og_id not matching ^OG[0-9]+$).
--   The join cannot drop rows: tissue.og_id is a NOT NULL foreign key to sample. Every other
--   view reaches sample through tissue; v_sequencing_browse takes og_num from v_library_browse.
--
-- Why DROP and CREATE, not CREATE OR REPLACE: OR REPLACE may only append columns, and og_num
--   has to be column 1. Dropping loses grants and comments, so both are restored below and
--   checked by the verify block. v_sequencing_browse reads v_library_browse, so it is dropped
--   first and created last. No CASCADE: on 2026-10-13 nothing else depended on these views
--   (pg_depend), and if something does by the time this runs, the DROP fails loudly.
--
-- Replay: drops and recreates the same views, so the crash-recovery replay in
--   bin/apply_migrations.py is harmless.
--
-- Expected impact: Read-only views only; no table is touched. Column positions change, so a
--   client selecting by position (SELECT * into a fixed layout) sees og_num first.
--
-- Rollback: sql/revert/046_v2_browse_views_og_num_first_revert.sql restores 037's order.

BEGIN;

DROP VIEW IF EXISTS v2.v_sequencing_browse;
DROP VIEW IF EXISTS v2.v_rna_library_kinx_browse;
DROP VIEW IF EXISTS v2.v_rna_library_ilmn_browse;
DROP VIEW IF EXISTS v2.v_hic_library_browse;
DROP VIEW IF EXISTS v2.v_ont_library_browse;
DROP VIEW IF EXISTS v2.v_pacbio_library_browse;
DROP VIEW IF EXISTS v2.v_illumina_library_browse;
DROP VIEW IF EXISTS v2.v_library_browse;
DROP VIEW IF EXISTS v2.v_hic_lysate_browse;
DROP VIEW IF EXISTS v2.v_rna_extraction_browse;
DROP VIEW IF EXISTS v2.v_dna_extraction_browse;
DROP VIEW IF EXISTS v2.v_tissue_browse;

-- ---------------------------------------------------------------------------------------
-- Tissue and extractions
-- ---------------------------------------------------------------------------------------

CREATE VIEW v2.v_tissue_browse AS
SELECT s.og_num,
       s.og_id,
       s.nominal_species_id,
       t.tissue_id,
       t.tissue,
       t.preservation,
       t.extracted,
       t.freezer,
       t.shelf,
       t.rack,
       t.level,
       t.box,
       t.comment
FROM v2.tissue t
JOIN v2.sample s ON s.og_id = t.og_id;

CREATE VIEW v2.v_dna_extraction_browse AS
SELECT s.og_num,
       t.og_id,
       d.tissue_id,
       d.dna_id,
       d.ext_num,
       (d.ext_num = max(d.ext_num) OVER (PARTITION BY d.tissue_id)) AS is_latest,
       d.status,
       d.status_overwrite,
       d.extraction_method,
       d.extraction_date,
       d.extraction_batch_id,
       d.qubit_conc,
       d.total_yield,
       d.av_size,
       d.extraction_qc,
       d.extract_plate,
       d.extract_plate_well,
       d.comment
FROM v2.dna_extraction d
JOIN v2.tissue t ON t.tissue_id = d.tissue_id
JOIN v2.sample s ON s.og_id     = t.og_id;

CREATE VIEW v2.v_rna_extraction_browse AS
SELECT s.og_num,
       t.og_id,
       r.tissue_id,
       r.rna_id,
       r.ext_num,
       (r.ext_num = max(r.ext_num) OVER (PARTITION BY r.tissue_id)) AS is_latest,
       r.status,
       r.status_overwrite,
       r.extraction_method,
       r.extraction_date,
       r.extraction_batch_id,
       r.qubit_conc,
       r.total_yield,
       r.rna_dv200,
       r.rin,
       r.gdna_over_7kb_perc,
       r.extraction_qc,
       r.comment
FROM v2.rna_extraction r
JOIN v2.tissue t ON t.tissue_id = r.tissue_id
JOIN v2.sample s ON s.og_id     = t.og_id;

CREATE VIEW v2.v_hic_lysate_browse AS
SELECT s.og_num,
       t.og_id,
       y.tissue_id,
       y.lysate_id,
       y.lysate_num,
       (y.lysate_num = max(y.lysate_num) OVER (PARTITION BY y.tissue_id)) AS is_latest,
       y.lysate_status,
       y.status_overwrite,
       y.lysate_method,
       y.lysate_prep_date,
       y.lysate_batch_id,
       y.lysate_conc,
       y.total_lysate,
       y.lysate_cde,
       y.prox_ligation_date,
       y.prox_ligation_conc,
       y.prox_ligation_yield,
       y.lysate_comments
FROM v2.hic_lysate y
JOIN v2.tissue t ON t.tissue_id = y.tissue_id
JOIN v2.sample s ON s.og_id     = t.og_id;

-- ---------------------------------------------------------------------------------------
-- Libraries
-- ---------------------------------------------------------------------------------------

-- Identity across all six technologies, with og_id resolved through whichever parent chain
-- applies. This is the view that makes the registry usable for browsing.
CREATE VIEW v2.v_library_browse AS
SELECT s.og_num,
       t.og_id,
       t.tissue_id,
       l.library_tube_id,
       l.library_type,
       coalesce(l.dna_id, l.rna_id, l.lysate_id) AS parent_id,
       l.dna_id,
       l.rna_id,
       l.lysate_id
FROM v2.library l
LEFT JOIN v2.dna_extraction d ON d.dna_id    = l.dna_id
LEFT JOIN v2.rna_extraction r ON r.rna_id    = l.rna_id
LEFT JOIN v2.hic_lysate     y ON y.lysate_id = l.lysate_id
JOIN v2.tissue t ON t.tissue_id = coalesce(d.tissue_id, r.tissue_id, y.tissue_id)
JOIN v2.sample s ON s.og_id     = t.og_id;

CREATE VIEW v2.v_illumina_library_browse AS
SELECT s.og_num,
       t.og_id,
       d.tissue_id,
       i.dna_id,
       i.illumina_library_tube_id,
       i.ilmn_num,
       (i.ilmn_num = max(i.ilmn_num) OVER (PARTITION BY i.dna_id)) AS is_latest,
       i.ilmn_status,
       i.status_overwrite,
       i.library_method,
       i.prep_automation,
       i.library_date,
       i.library_id,
       i.library_plate_well,
       i.index_plate,
       i.index_set,
       i.index_well,
       i.index_idx,
       i.library_qubit_conc,
       i.il_comments
FROM v2.illumina_library i
JOIN v2.dna_extraction d ON d.dna_id    = i.dna_id
JOIN v2.tissue         t ON t.tissue_id = d.tissue_id
JOIN v2.sample         s ON s.og_id     = t.og_id;

CREATE VIEW v2.v_pacbio_library_browse AS
SELECT s.og_num,
       t.og_id,
       d.tissue_id,
       p.dna_id,
       p.pacbio_library_tube_id,
       p.pacb_num,
       (p.pacb_num = max(p.pacb_num) OVER (PARTITION BY p.dna_id)) AS is_latest,
       p.pacb_status,
       p.status_overwrite,
       p.dna_treatment,
       p.sre_kit,
       p.post_sre_conc,
       p.final_pre_library_conc,
       p.shear_femtol_id,
       p.shear_av_size,
       p.library_method,
       p.prep_automation,
       p.library_date,
       p.library_id,
       p.index_well,
       p.barcode,
       p.seq_femto_id,
       p.seq_av_size,
       p.library_conc,
       p.comment
FROM v2.pacbio_library p
JOIN v2.dna_extraction d ON d.dna_id    = p.dna_id
JOIN v2.tissue         t ON t.tissue_id = d.tissue_id
JOIN v2.sample         s ON s.og_id     = t.og_id;

CREATE VIEW v2.v_ont_library_browse AS
SELECT s.og_num,
       t.og_id,
       d.tissue_id,
       o.dna_id,
       o.ont_library_tube_id,
       o.ont_num,
       (o.ont_num = max(o.ont_num) OVER (PARTITION BY o.dna_id, o.library_method)) AS is_latest,
       o.ont_status,
       o.status_overwrite,
       o.library_method,
       o.library_type,
       o.library_date,
       o.library_id,
       o.est_loading_size,
       o.ont_comments
FROM v2.ont_library o
JOIN v2.dna_extraction d ON d.dna_id    = o.dna_id
JOIN v2.tissue         t ON t.tissue_id = d.tissue_id
JOIN v2.sample         s ON s.og_id     = t.og_id;

CREATE VIEW v2.v_hic_library_browse AS
SELECT s.og_num,
       t.og_id,
       y.tissue_id,
       h.lysate_id,
       h.hic_library_tube_id,
       h.hic_num,
       (h.hic_num = max(h.hic_num) OVER (PARTITION BY h.lysate_id)) AS is_latest,
       h.hic_status,
       h.status_overwrite,
       h.library_method,
       h.processing_notes,
       h.library_date,
       h.library_id,
       -- The live proximity-ligation value comes from the lysate; hic_library's own column is
       -- legacy and is exposed separately so the two are never silently conflated (F13).
       y.prox_ligation_conc         AS prox_ligation_conc,
       h.prox_ligation_conc         AS prox_ligation_conc_legacy,
       h.purified_dna_total,
       h.index_set,
       h.index_i5,
       h.index_i7,
       h.library_conc,
       h.library_yield,
       h.library_size,
       h.pcr_dup_read_pairs,
       h.nodup_cis_read_pairs_1kb,
       h.expected_distinct_30m_reads,
       h.hic_comments
FROM v2.hic_library h
JOIN v2.hic_lysate y ON y.lysate_id = h.lysate_id
JOIN v2.tissue     t ON t.tissue_id = y.tissue_id
JOIN v2.sample     s ON s.og_id     = t.og_id;

CREATE VIEW v2.v_rna_library_ilmn_browse AS
SELECT s.og_num,
       t.og_id,
       r.tissue_id,
       x.rna_id,
       x.rna_library_tube_id,
       x.rna_num,
       (x.rna_num = max(x.rna_num) OVER (PARTITION BY x.rna_id, x.library_method)) AS is_latest,
       x.rna_status,
       x.status_overwrite,
       x.library_method,
       x.library_date,
       x.library_id,
       x.library_size,
       x.perc_product,
       x.library_qubit_conc,
       x.library_molarity,
       x.index_set,
       x.index_well,
       x.index_inx,
       x.final_plate_name,
       x.final_plate_well,
       x.well_position,
       x.comments
FROM v2.rna_library_ilmn x
JOIN v2.rna_extraction r ON r.rna_id    = x.rna_id
JOIN v2.tissue         t ON t.tissue_id = r.tissue_id
JOIN v2.sample         s ON s.og_id     = t.og_id;

CREATE VIEW v2.v_rna_library_kinx_browse AS
SELECT s.og_num,
       t.og_id,
       r.tissue_id,
       k.rna_id,
       k.rna_library_tube_id,
       k.rna_num,
       (k.rna_num = max(k.rna_num) OVER (PARTITION BY k.rna_id)) AS is_latest,
       k.rna_status,
       k.status_overwrite,
       k.library_method,
       k.processing_comment,
       k.synthesis_date,
       k.part1_batch_id,
       k.synthesis_conc,
       k.part2_batch_id,
       k.final_qubit_conc,
       k.library_size,
       k.kinnex_primers,
       k.kinnex_barcode,
       k.pool_id,
       k.plate,
       k.plate_location,
       k.sequencing_sample_id,
       k.comments
FROM v2.rna_library_kinx k
JOIN v2.rna_extraction r ON r.rna_id    = k.rna_id
JOIN v2.tissue         t ON t.tissue_id = r.tissue_id
JOIN v2.sample         s ON s.og_id     = t.og_id;

-- ---------------------------------------------------------------------------------------
-- Sequencing
-- ---------------------------------------------------------------------------------------

CREATE VIEW v2.v_sequencing_browse AS
SELECT b.og_num,
       b.og_id,
       b.tissue_id,
       b.parent_id,
       b.library_tube_id,
       b.library_type,
       q.sequencing_id,
       q.status,
       q.technology,
       q.instrument,
       q.run_date,
       q.run_id,
       q.seq_date,
       q.cell_id,
       q.smrt_num,
       q.seq_type,
       q.design_no,
       q.hic_depth,
       q.seq_comments
FROM v2.sequencing q
JOIN v2.v_library_browse b ON b.library_tube_id = q.library_tube_id;


-- ---------------------------------------------------------------------------------------
-- Documentation and grants (both are lost on DROP)
-- ---------------------------------------------------------------------------------------

COMMENT ON VIEW v2.v_tissue_browse            IS 'Tissues with specimen context. Read-only; import against v2.tissue.';
COMMENT ON VIEW v2.v_dna_extraction_browse    IS 'DNA extractions with og_id and is_latest, neither of which is stored on the base table.';
COMMENT ON VIEW v2.v_rna_extraction_browse    IS 'RNA extractions with og_id and is_latest.';
COMMENT ON VIEW v2.v_hic_lysate_browse        IS 'Hi-C lysates with og_id and is_latest, including the live proximity-ligation columns.';
COMMENT ON VIEW v2.v_library_browse           IS 'All libraries of every technology, one row each, with og_id resolved through whichever parent chain applies. The registry made browsable.';
COMMENT ON VIEW v2.v_illumina_library_browse  IS 'Illumina DNA libraries with og_id and is_latest.';
COMMENT ON VIEW v2.v_pacbio_library_browse    IS 'PacBio HiFi libraries with og_id and is_latest.';
COMMENT ON VIEW v2.v_ont_library_browse       IS 'ONT libraries with og_id and is_latest. is_latest is per kit (library_method), because the lab numbers attempts per kit.';
COMMENT ON VIEW v2.v_hic_library_browse       IS 'Hi-C libraries with og_id and is_latest. Exposes the lysate proximity-ligation value as prox_ligation_conc and the legacy library-level one separately.';
COMMENT ON VIEW v2.v_rna_library_ilmn_browse  IS 'Illumina RNA libraries with og_id and is_latest. is_latest is per library_method, because the lab numbers attempts per method (mRNA _IL and ribosomal-depletion _dIL each start at #1).';
COMMENT ON VIEW v2.v_rna_library_kinx_browse  IS 'PacBio Kinnex RNA libraries with og_id and is_latest.';
COMMENT ON VIEW v2.v_sequencing_browse        IS 'Sequencing records with the full ancestor chain, through the library registry.';

COMMENT ON COLUMN v2.v_dna_extraction_browse.is_latest IS
    'True when this row has the highest ext_num for its tissue. A faithful translation of the '
    'workbook''s Latest formula, MAX(#) per parent — including its behaviour on ties, which is '
    'why unique(tissue_id, ext_num) matters.';

GRANT SELECT ON
    v2.v_tissue_browse, v2.v_dna_extraction_browse, v2.v_rna_extraction_browse,
    v2.v_hic_lysate_browse, v2.v_library_browse, v2.v_illumina_library_browse,
    v2.v_pacbio_library_browse, v2.v_ont_library_browse, v2.v_hic_library_browse,
    v2.v_rna_library_ilmn_browse, v2.v_rna_library_kinx_browse, v2.v_sequencing_browse
TO readonly;

-- ---------------------------------------------------------------------------------------
-- Verification: 037's checks, plus the new column order and the restored grant
-- ---------------------------------------------------------------------------------------

DO $$
DECLARE
  v   text;
  rec record;
BEGIN
  FOREACH v IN ARRAY ARRAY[
    'v_tissue_browse', 'v_dna_extraction_browse', 'v_rna_extraction_browse',
    'v_hic_lysate_browse', 'v_library_browse', 'v_illumina_library_browse',
    'v_pacbio_library_browse', 'v_ont_library_browse', 'v_hic_library_browse',
    'v_rna_library_ilmn_browse', 'v_rna_library_kinx_browse', 'v_sequencing_browse'
  ] LOOP
    IF to_regclass(format('v2.%I', v)) IS NULL THEN
      RAISE EXCEPTION 'Missing expected view: v2.%', v;
    END IF;

    EXECUTE format('SELECT 1 FROM v2.%I LIMIT 1', v);

    IF (SELECT attname FROM pg_attribute
        WHERE attrelid = format('v2.%I', v)::regclass AND attnum = 1) IS DISTINCT FROM 'og_num' THEN
      RAISE EXCEPTION 'v2.%: first column is not og_num', v;
    END IF;

    IF (SELECT attname FROM pg_attribute
        WHERE attrelid = format('v2.%I', v)::regclass AND attnum = 2) IS DISTINCT FROM 'og_id' THEN
      RAISE EXCEPTION 'v2.%: second column is not og_id (F1)', v;
    END IF;

    IF obj_description(format('v2.%I', v)::regclass, 'pg_class') IS NULL THEN
      RAISE EXCEPTION 'View v2.% has no COMMENT (Finding 9)', v;
    END IF;

    IF NOT has_table_privilege('readonly', format('v2.%I', v), 'SELECT') THEN
      RAISE EXCEPTION 'readonly cannot SELECT from v2.%', v;
    END IF;
  END LOOP;

  FOREACH v IN ARRAY ARRAY[
    'v_dna_extraction_browse', 'v_rna_extraction_browse', 'v_hic_lysate_browse',
    'v_illumina_library_browse', 'v_pacbio_library_browse', 'v_ont_library_browse',
    'v_hic_library_browse', 'v_rna_library_ilmn_browse', 'v_rna_library_kinx_browse'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = v AND column_name = 'is_latest') THEN
      RAISE EXCEPTION 'v2.% does not expose is_latest (F4a)', v;
    END IF;
  END LOOP;

  FOR rec IN
    SELECT unnest(ARRAY['prox_ligation_conc', 'prox_ligation_conc_legacy']) AS col
  LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'v2' AND table_name = 'v_hic_library_browse'
                     AND column_name = rec.col) THEN
      RAISE EXCEPTION 'v2.v_hic_library_browse is missing % (F13)', rec.col;
    END IF;
  END LOOP;

  IF col_description('v2.v_dna_extraction_browse'::regclass,
       (SELECT attnum FROM pg_attribute
        WHERE attrelid = 'v2.v_dna_extraction_browse'::regclass AND attname = 'is_latest')) IS NULL THEN
    RAISE EXCEPTION 'v2.v_dna_extraction_browse.is_latest lost its COMMENT';
  END IF;
END $$;

COMMIT;
