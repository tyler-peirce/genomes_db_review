-- 071_v4_read_set_external_and_dates_revert.sql -- back to 070's state: the four read sets undated
-- with no run links, no external read-set table, 069's readiness view, and the compatibility
-- views' earlier comments.
--
-- After running this, delete 071's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '071_v4_read_set_external_and_dates.sql';

BEGIN;

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

COMMENT ON VIEW v4.ref_genomes IS
  'Compatibility view: public.ref_genomes''s 58 columns in its order, one row per part. k_mer_set and hap2_chr_level_max_len are always NULL. Not a write path.';
COMMENT ON VIEW v4.raw_qc IS
  'Compatibility view: public.raw_qc''s columns, one row per OG, from one read set: the undated one if any (it mirrors a public state no dated read set matches), else the latest dated. Not a write path.';
COMMENT ON VIEW v4.hifi_reads_qc IS
  'Compatibility view: public.hifi_reads_qc''s columns in its order. Not a write path.';
COMMENT ON VIEW v4.hic_reads_qc IS
  'Compatibility view: public.hic_reads_qc''s columns in its order, NULL key parts shown as ''''. Not a write path.';
COMMENT ON VIEW v4.ref_genomes_assembly_uploads IS
  'Compatibility view: public.ref_genomes_assembly_uploads''s columns in its order. Not a write path.';
COMMENT ON VIEW v4.ref_genomes_sra_uploads IS
  'Compatibility view: public.ref_genomes_sra_uploads''s columns in its order, status and date recombined. Not a write path.';

DROP TRIGGER IF EXISTS ref_read_set_run_not_external ON v4.ref_read_set_run;
DROP TABLE IF EXISTS v4.ref_read_set_external;
DROP FUNCTION IF EXISTS v4.ref_read_set_external_exclusive();

CREATE TEMP TABLE rs_fix (og_id text PRIMARY KEY, seq_date text NOT NULL) ON COMMIT DROP;
INSERT INTO rs_fix VALUES ('OG906', '250212'), ('OG845', '241023'), ('OG781', '260421'), ('OG763', '251117');

DELETE FROM v4.ref_read_set_run r
USING v4.ref_read_set rs, rs_fix f
WHERE r.read_set_id = rs.read_set_id AND rs.og_id = f.og_id AND rs.seq_date = f.seq_date;
UPDATE v4.ref_read_set rs SET seq_date = NULL
FROM rs_fix f WHERE rs.og_id = f.og_id AND rs.seq_date = f.seq_date;

COMMIT;
