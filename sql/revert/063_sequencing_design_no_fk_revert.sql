-- 063_sequencing_design_no_fk_revert.sql -- drop the FK 063 added, and restore 034's table
-- comment.
--
-- After running this, delete 063's ledger row:
--   DELETE FROM schema_migrations WHERE filename = '063_sequencing_design_no_fk.sql';

BEGIN;

ALTER TABLE public.sequencing DROP CONSTRAINT IF EXISTS sequencing_design_no_fkey;
COMMENT ON TABLE public.design_description IS
  'Lookup of sequencing design numbers to descriptions. Two rows, no foreign keys in or out, and no '
  'reference from either repository. Captured by 034_catchup_design_description.sql so it is not lost '
  'on a rebuild; a candidate for removal once open question 15 confirms no external consumer.';

COMMIT;
