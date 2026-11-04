# Documentation record: Phase R/RG close-out and the whole-database comments (`078`, `079`), 2026-11-04

What changed: database comments only (`078`, `079`), a rewritten `docs/data_dictionary.md`,
`database_review.md` revision 3.40 (§7, §9 Phases G and R, §10, §13, Finding 9),
`scripts/comment_coverage.sql`, and a fix to `bin/check_drift.py --coverage`. No data or
structure changed.

## Writers read

Fetched first, then read at the remote default branch (`docs/database_change_checklist.md`,
"For Pipeline Writer and Reader Audits").

| Repository | Branch | Commit | Read for |
|---|---|---|---|
| OceanOmics-OceanGenomes-Draft-Genomes | `origin/master` | `58353cf41815` | `bin/draft_genome_stats.py` (every draft table), `scripts/taxonomy/load_taxonomy.py` (`species`) |
| Oceanomics-OceanGenomes-Mitogenomes | `origin/inverts-dev` | `00aca11047a2` | `push_*.py`, `mito_depth.py`, `calculateLCA.py`, `species_validation.py`, `push_ena_validation_results.py`, `backfill_ena_specimen_accessions.py` |
| OceanOmics-OceanGenomes-ref-genomes | `origin/master` | `b330b008d39c` | `scripts/lib/refdb.py`, the `0a`-`05a` push scripts |
| OceanOmics-OceanGenomes-post-curation | `origin/master` | `36db0953e771` | `04a`, `05a`, `06b` push scripts |
| ENA-draft-genomes | `origin/main` | `c0f78fdaf14a` | `workflow/06`, `07` |
| ENA-ref-genomes | `origin/main` | `3f245cfb7e48` | `workflow/09` (`SAMPLE_FIELDS`, SRA upload links) |
| ref_genomes_hic_automation | `origin/main` | `4180383e79d3` | `push_hic_yield.py`, `generate_hic_yield.py` |
| OceanOmics-Database | `origin/main` | `547b53f21623` | `name_convert_v2.py`, `import_v2.py`, `SS/import_data_lca_validation.py` |
| ENA-mito-genomes | `origin/main` | `bbba294f8bfa` | Searched for `mito_lca_validation` writers; none |

**The mito pipeline's default branch is `inverts-dev`.** The local clone's `origin/HEAD` points at
`master` (`b0cf5a325ef0`, 2026-09-07), which still writes `mitogenome_data`, `lca` and the other
pre-R names. A writer audit that reads `origin/HEAD` there reads the wrong code.

Not readable from this host: OceanGenom_Web (writes `sample.workflow`, `priority`,
`embargo_status`), and anything that runs only on Pawsey outside these clones.

## Findings

Each is also written into the relevant column or table comment.

1. **No writer for `mito_assembly_run` or `ref_assembly_run` since the merges.** The window syncs
   derived both, and `072`/`073` dropped the syncs with nothing in their place. No pipeline
   repository inserts into either table. On 2026-11-04, the 2 mito assemblies created since
   2026-11-02 have no run links. This is now backlog Highest 13.
2. **`confidence_score` / `top_confidence_score` in the LCA tables is the BLAST e-value**
   (`calculateLCA.py`: `'confidence_score': evalue`). Lower is better.
3. **`taxon_rank_db` is the taxonomy source** the lineage came from (fishbase 43,672, worms
   6,015, ncbi 103 rows in `mito_lca_raw`), not a rank. `017`'s comment on it was wrong.
4. **`mito_blast_hit.subject_coverage` is BLAST `qcovhsp`.** The pipeline's `-outfmt` ends
   `... qcovs qcovhsp`, mapped by position onto `query_coverage, subject_coverage`.
5. **`v_genome_size_comparison` reads the empty `species_ncbi_assembly`**, so its NCBI columns
   are NULL on every row. `ncbi_genome_assemblies` (1,830 rows) has no reading view at all.
6. **`ena_specimen_accessions` holds 1 accession in 2,848 rows.** It has an FK to `sample` now
   (the review said it had none).
7. **13 `sample` submission columns have no current writer** (`assigned_species`,
   `eschmeyer_id`, `ncbi_sample_name`, `hifi_lca_outcome`, `ncbi_id`, `tol_id`,
   `ncbi_assembly_upload`, `ncbi_raw_reads_upload`, `hifi_public`, `illumina_lca`,
   `ncbi_bioproject_id_draft`, `draft_sra_accessions`, `draft_assembly_accession`). ENA steps 06
   and 09 write the other five (`ncbi_biosample_id` and the four BioProjects).
8. **No current writer found** for `raw_data`, `rna_qc_kinnex` or `ncbi_genome_assemblies`.
9. **`mito_lca_validation.data_release` is empty on every row**, with no writer.
10. **`bin/check_drift.py --coverage` miscounted.** Its pattern accepted only a `public.`
    prefix, so `CREATE TABLE v3.draft_busco` read as an object named `v3`, and 93 objects built
    in `v2`/`v3`/`v4` and moved into `public` showed as baseline-only. Fixed: migration-covered
    went from 27 to 120 of 132. This is V.7 item 2.
11. Two table comments made false claims: `v_ref_assembly_run_readiness` ("the writers link new
    assemblies"; see 1) and `v_sequencing_run_fk_readiness` (FKs "R.7 will" add; `075`/`077`
    added them). Corrected, along with every remaining comment that named a `v2.`/`v3.` object
    (V.7 item 3), except `refresh_sequencing_run()`'s, which is accurate history.

## Coverage

`scripts/comment_coverage.sql`, `public` only (the archive schemas are excluded):

| | Before (live, 2026-11-04) | After `079` (rehearsal) |
|---|---|---|
| Tables with a comment | 72 / 81 | 79 / 81 |
| Views with a comment | 41 / 51 | 51 / 51 |
| Table columns commented | 122 / 988 | 949 / 988 |
| View columns commented | 3 / 1,053 | 174 / 1,053 |

What is still uncommented, on purpose:
- OceanGenom_Web's `master_species`, `master_species_genome`, `og_priority_log` and
  `og_workflow_*` (2 tables without a table comment; 39 columns);
- the columns of the compatibility views and the `v_*_browse` views (879), which repeat
  base-table columns. Their table comments name the base tables.

Comments that depend on an open question end "Meaning undecided: §11 Q<n>": Q1 on
`sample.nominal_species_id`, `assigned_species` and `species`, Q2 on `workflow` and `priority`,
and Q5 on `sequencing`.

## Rehearsal (PG14 restore of live, 2026-11-04)

Dump: `~/oceanomics_genomes_pre_078_261104.dump` (`pg_dump -Fc`, taken just before), restored
into a throwaway cluster on port 55432.

| Check | Result |
|---|---|
| `bin/apply_migrations.py` | Applied `078` and `079`; each one's built-in check passed (no in-scope table, view or column without a comment) |
| Replay of each file | No-op; both checks pass again |
| `--verify` | 80 files, all hashes match |
| `pg_dump -s` against an unmigrated restore, dumped by the same server | Identical apart from `COMMENT` lines |
| `goat_species_v1` (19,817 rows) and `summary` (3,411) | Output identical before and after |
| `\d+ draft_busco` | The N50 warning shows |
| `bin/check_drift.py --coverage` on live | migration 120, baseline-only 10, NEITHER 2 (OceanGenom_Web's `og_priority_log` and `v_sample_master_species`, kept out of the baseline) |

## On live

Applied with `bin/apply_migrations.py` at 05:11 UTC, after a second pre-change dump
(`~/oceanomics_genomes_pre_078_261104b.dump`). `--verify`: 80 files, all hashes match. Coverage
on live is the same as the rehearsal's. `summary` (3,411) and `goat_species_v1` (19,817) still
select.

Baseline: `scripts/export_schema_baseline.sh` was run into a scratch directory, and only its
`COMMENT` entries were merged into `schema/current_schema.sql`. With the comment entries removed,
the file is byte-identical to the previous baseline. Left out: the comments on OceanGenom_Web's
`og_priority_log` and `v_sample_master_species`, and the colleague's drift in
`current_views.sql`, `current_indexes.sql` and `current_constraints.sql`, which stay as they
were. `schema/object_inventory.tsv` is unchanged: comments are not objects.

## Still to do

- Backlog Highest 13: a writer for the two run-link tables.
- Copy the migration headers into the data dictionary (backlog Medium 7).
