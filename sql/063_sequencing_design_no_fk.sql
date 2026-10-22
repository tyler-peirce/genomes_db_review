-- 063_sequencing_design_no_fk.sql -- FK sequencing.design_no -> design_description.
--
-- Why. design_description (034) is the two-row lookup of Illumina prep protocols: 1 = OceanGenomes
-- Lab standard prep, 2 = TREND lab QIAcube prep. sequencing.design_no names one on 1,400 of 4,448
-- rows (live, 2026-10-22), every value 1 or 2, but the link was never declared, so a schema diagram
-- shows design_description floating. 034 found no reader and left open question 15 (drop it?);
-- this answers it: it is a lookup in use, and it stays.
--
-- How. NOT VALID then VALIDATE, as 054 and 061. No ON DELETE action: removing a protocol that
-- sequencing rows still name should fail. No index on sequencing.design_no: two distinct values
-- over ~4,400 rows, and the parent is a two-row table whose rows are never deleted, so an index
-- would serve no query and no FK check worth having.
--
-- Writers. import_v2.py writes sequencing through safe_write, which quarantines a row the
-- database rejects with SQLSTATE 23503 as 'foreign_key'. A workbook design_no not in
-- design_description costs that row, never the run.
--
-- Revert: sql/revert/063_sequencing_design_no_fk_revert.sql.

BEGIN;

DO $fk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'public.sequencing'::regclass AND conname = 'sequencing_design_no_fkey') THEN
    ALTER TABLE public.sequencing ADD CONSTRAINT sequencing_design_no_fkey
      FOREIGN KEY (design_no) REFERENCES public.design_description (design_no) NOT VALID;
  END IF;
  ALTER TABLE public.sequencing VALIDATE CONSTRAINT sequencing_design_no_fkey;
  RAISE NOTICE '063: sequencing_design_no_fkey validated over % rows with a design_no',
    (SELECT count(design_no) FROM public.sequencing);
END
$fk$;

COMMENT ON TABLE public.design_description IS
  'Illumina prep protocols, named by sequencing.design_no (FK, migration 063).';

COMMIT;
