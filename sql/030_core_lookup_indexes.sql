-- Supporting indexes for the core FK and og_id lookup columns on the legacy lab
-- tables (database_review.md Finding 4).
--
-- Provenance: this is the Sqitch change `add_core_lookup_indexes`
-- (deploy/add_core_lookup_indexes.sql, itself ported from
-- migrations/legacy/202607070001_add_core_lookup_indexes.sql), written in July
-- 2026 and never deployed -- Sqitch has never run against this database and has
-- no registry schema here. Rather than stand up a second migration system to
-- deploy one index change, it is ported into the numbered sql/ convention, which
-- is the system actually in use. The Sqitch copy is superseded by this file.
--
-- Extended on port: the Sqitch version created 19 indexes and omitted five
-- columns from Finding 4's list of 24 -- sequencing's four library tube columns
-- and ref_genomes_sra_uploads.og_id. The four sequencing tube columns are the
-- child side of four live foreign keys, so an unindexed parent delete or key
-- update scans the whole table. All five are added here.
--
-- NO TRANSACTION. Every statement is CREATE INDEX CONCURRENTLY, which cannot run
-- inside a transaction block. Do not wrap this file in BEGIN/COMMIT -- unlike
-- 001-029 it must be applied in autocommit. CONCURRENTLY is deliberate: these
-- tables take writes from the nightly import and the pipelines, and a plain
-- CREATE INDEX would hold an ACCESS EXCLUSIVE lock for the duration.
--
-- Replay safety: IF NOT EXISTS throughout. One caveat specific to CONCURRENTLY
-- -- an interrupted build leaves an INVALID index behind, and IF NOT EXISTS will
-- then skip it on re-run rather than repair it. After any failed or interrupted
-- apply, check for invalid indexes before re-running:
--     SELECT c.relname FROM pg_index x
--       JOIN pg_class c ON c.oid = x.indexrelid
--      WHERE NOT x.indisvalid;
-- and DROP INDEX any that appear.
--
-- Semantics unchanged: this file adds no constraint and alters no data. It is a
-- prerequisite for Finding 3's foreign keys, which should not be added while the
-- child-side columns are unindexed.

-- sample -> tissue
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tissue_og_id
  ON tissue (og_id);

-- tissue -> extractions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dna_extraction_tissue_id
  ON dna_extraction (tissue_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dna_extraction_og_id
  ON dna_extraction (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_extraction_tissue_id
  ON rna_extraction (tissue_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_extraction_og_id
  ON rna_extraction (og_id);

-- dna_extraction -> DNA libraries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_illumina_library_dna_id
  ON illumina_library (dna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_illumina_library_og_id
  ON illumina_library (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pacbio_library_dna_id
  ON pacbio_library (dna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_pacbio_library_og_id
  ON pacbio_library (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ont_library_dna_id
  ON ont_library (dna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ont_library_og_id
  ON ont_library (og_id);

-- tissue -> hic_lysate -> hic_library
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hic_lysate_tissue_id
  ON hic_lysate (tissue_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hic_library_lysate_id
  ON hic_library (lysate_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hic_library_og_id
  ON hic_library (og_id);

-- rna_extraction -> RNA libraries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_library_ilmn_rna_id
  ON rna_library_ilmn (rna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_library_ilmn_og_id
  ON rna_library_ilmn (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_library_kinx_rna_id
  ON rna_library_kinx (rna_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rna_library_kinx_og_id
  ON rna_library_kinx (og_id);

-- sequencing: og_id, plus the four polymorphic library tube columns (Finding 5).
-- These four are the child side of live foreign keys and were missing from the
-- Sqitch version. Each is NULL for the three technologies it does not apply to,
-- so the indexes stay small.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sequencing_og_id
  ON sequencing (og_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sequencing_illumina_library_tube_id
  ON sequencing (illumina_library_tube_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sequencing_pacbio_library_tube_id
  ON sequencing (pacbio_library_tube_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sequencing_ont_library_tube_id
  ON sequencing (ont_library_tube_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sequencing_hic_library_tube_id
  ON sequencing (hic_library_tube_id);

-- ref_genomes_sra_uploads (table's PK is still named ref_genomes_sra_runs_pkey
-- from an earlier name; the index below uses the current table name).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ref_genomes_sra_uploads_og_id
  ON ref_genomes_sra_uploads (og_id);
