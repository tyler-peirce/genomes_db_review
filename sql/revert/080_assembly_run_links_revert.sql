-- Revert 080_assembly_run_links.sql: drop the run-link triggers and functions, and restore the
-- three comments as 078 left them.
--     psql -f sql/revert/080_assembly_run_links_revert.sql   then delete 080's ledger row.
-- The links 080 and its triggers added stay: they are what the old syncs would have derived.

BEGIN;

DROP TRIGGER mito_assembly_runs_link ON mito_assembly;
DROP TRIGGER ref_assembly_runs_link ON ref_assembly;
DROP TRIGGER sequencing_assembly_runs_ins ON sequencing;
DROP TRIGGER sequencing_assembly_runs_upd ON sequencing;
DROP TRIGGER library_assembly_runs_upd ON library;

DROP FUNCTION public.mito_assembly_runs_link();
DROP FUNCTION public.ref_assembly_runs_link();
DROP FUNCTION public.sequencing_assembly_runs();
DROP FUNCTION public.library_assembly_runs();
DROP FUNCTION public.refresh_assembly_runs(text[], text[]);
DROP FUNCTION public.mito_run_matches(text, text, text, text);

-- Comments as on live, 2026-11-09.
COMMENT ON TABLE mito_assembly_run IS 'The sequencing rows (a library on a run) an assembly was built from, derived from (og_id, seq_date) and tech; ilmn excludes iSEQ QC runs. Derived by the Phase R window sync and loaded at the 072 merge. No writer has added rows since, so assemblies created after 2026-11-02 have none (078).';
COMMENT ON TABLE ref_assembly_run IS 'The sequencing rows an assembly was built from: PacBio/ONT DNA, and Hi-C once writers record it (trigger). Derived by the RG window sync and loaded at the 073 merge. No writer has added rows since (078).';
COMMENT ON VIEW v_ref_assembly_run_readiness IS 'Assemblies with no run link, and the OG''s PacBio/ONT DNA rows to choose from. Their seq_date matches no run date (RG.0 §1.5). No writer links new assemblies since the RG.6 merge (078), so every new assembly appears here.';

COMMIT;
