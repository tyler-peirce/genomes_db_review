-- Deploy genomes_db:create_v2_browse_views to pg
-- requires: create_v2_lab_tables

-- Purpose: Provide the ancestor context and the "is this the current attempt" flag that the
--   v2 tables deliberately do not store, per docs/lab_key_strategy.md §7 (Option B) and
--   docs/v2_scaffold_design_review.md §5 step 5.
--
--   Two columns were removed from the base tables and are recovered here:
--
--   og_id   Removed from nine child tables (F1). It was a parsed grandparent or
--           great-grandparent that could carry no foreign key and could silently disagree
--           with its own ancestor — and because regexp_replace returns its input unchanged on
--           a non-match, a malformed ID such as ')G2112_D' yielded og_id = ')G2112' rather
--           than failing or nulling. Here it comes from a real indexed join.
--
--   latest  Never stored (F4a). The workbook computes it identically on every sheet as
--             IF($B2="","",IF(MAX(IF($B:$B=$B2,$C:$C))=$C2,"Y","N"))
--           where B is the parent ID and C is the attempt number — i.e. "this row has the
--           highest attempt number for its parent". That is a window function, so storing it
--           would mean keeping a derived flag in sync for no benefit.
--
-- Review source: docs/lab_key_strategy.md §7; docs/v2_scaffold_design_review.md F1, F4a, §5.
--
-- Expected impact: Additive only. Creates 12 read-only views over empty v2 tables. Note these
--   are multi-table views and are for reading: the nightly import must continue to insert and
--   update against the base tables.

BEGIN;

-- ---------------------------------------------------------------------------------------
-- Tissue and extractions
-- ---------------------------------------------------------------------------------------

CREATE VIEW v2.v_tissue_browse AS
SELECT s.og_id,
       s.og_num,
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
SELECT t.og_id,
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
       d.comment
FROM v2.dna_extraction d
JOIN v2.tissue t ON t.tissue_id = d.tissue_id;

CREATE VIEW v2.v_rna_extraction_browse AS
SELECT t.og_id,
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
JOIN v2.tissue t ON t.tissue_id = r.tissue_id;

CREATE VIEW v2.v_hic_lysate_browse AS
SELECT t.og_id,
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
JOIN v2.tissue t ON t.tissue_id = y.tissue_id;

-- ---------------------------------------------------------------------------------------
-- Libraries
-- ---------------------------------------------------------------------------------------

-- Identity across all six technologies, with og_id resolved through whichever parent chain
-- applies. This is the view that makes the registry usable for browsing.
CREATE VIEW v2.v_library_browse AS
SELECT t.og_id,
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
JOIN v2.tissue t ON t.tissue_id = coalesce(d.tissue_id, r.tissue_id, y.tissue_id);

CREATE VIEW v2.v_illumina_library_browse AS
SELECT t.og_id,
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
JOIN v2.tissue         t ON t.tissue_id = d.tissue_id;

CREATE VIEW v2.v_pacbio_library_browse AS
SELECT t.og_id,
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
JOIN v2.tissue         t ON t.tissue_id = d.tissue_id;

CREATE VIEW v2.v_ont_library_browse AS
SELECT t.og_id,
       d.tissue_id,
       o.dna_id,
       o.ont_library_tube_id,
       o.ont_num,
       (o.ont_num = max(o.ont_num) OVER (PARTITION BY o.dna_id)) AS is_latest,
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
JOIN v2.tissue         t ON t.tissue_id = d.tissue_id;

CREATE VIEW v2.v_hic_library_browse AS
SELECT t.og_id,
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
JOIN v2.tissue     t ON t.tissue_id = y.tissue_id;

CREATE VIEW v2.v_rna_library_ilmn_browse AS
SELECT t.og_id,
       r.tissue_id,
       x.rna_id,
       x.rna_library_tube_id,
       x.rna_num,
       (x.rna_num = max(x.rna_num) OVER (PARTITION BY x.rna_id)) AS is_latest,
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
       x.comments
FROM v2.rna_library_ilmn x
JOIN v2.rna_extraction r ON r.rna_id    = x.rna_id
JOIN v2.tissue         t ON t.tissue_id = r.tissue_id;

CREATE VIEW v2.v_rna_library_kinx_browse AS
SELECT t.og_id,
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
JOIN v2.tissue         t ON t.tissue_id = r.tissue_id;

-- ---------------------------------------------------------------------------------------
-- Sequencing
-- ---------------------------------------------------------------------------------------

CREATE VIEW v2.v_sequencing_browse AS
SELECT b.og_id,
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
-- Documentation
-- ---------------------------------------------------------------------------------------

COMMENT ON VIEW v2.v_tissue_browse            IS 'Tissues with specimen context. Read-only; import against v2.tissue.';
COMMENT ON VIEW v2.v_dna_extraction_browse    IS 'DNA extractions with og_id and is_latest, neither of which is stored on the base table.';
COMMENT ON VIEW v2.v_rna_extraction_browse    IS 'RNA extractions with og_id and is_latest.';
COMMENT ON VIEW v2.v_hic_lysate_browse        IS 'Hi-C lysates with og_id and is_latest, including the live proximity-ligation columns.';
COMMENT ON VIEW v2.v_library_browse           IS 'All libraries of every technology, one row each, with og_id resolved through whichever parent chain applies. The registry made browsable.';
COMMENT ON VIEW v2.v_illumina_library_browse  IS 'Illumina DNA libraries with og_id and is_latest.';
COMMENT ON VIEW v2.v_pacbio_library_browse    IS 'PacBio HiFi libraries with og_id and is_latest.';
COMMENT ON VIEW v2.v_ont_library_browse       IS 'ONT libraries with og_id and is_latest.';
COMMENT ON VIEW v2.v_hic_library_browse       IS 'Hi-C libraries with og_id and is_latest. Exposes the lysate proximity-ligation value as prox_ligation_conc and the legacy library-level one separately.';
COMMENT ON VIEW v2.v_rna_library_ilmn_browse  IS 'Illumina RNA libraries with og_id and is_latest.';
COMMENT ON VIEW v2.v_rna_library_kinx_browse  IS 'PacBio Kinnex RNA libraries with og_id and is_latest.';
COMMENT ON VIEW v2.v_sequencing_browse        IS 'Sequencing records with the full ancestor chain, through the library registry.';

COMMENT ON COLUMN v2.v_dna_extraction_browse.is_latest IS
    'True when this row has the highest ext_num for its tissue. A faithful translation of the '
    'workbook''s Latest formula, MAX(#) per parent — including its behaviour on ties, which is '
    'why unique(tissue_id, ext_num) matters.';

COMMIT;
