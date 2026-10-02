# Ocean Genomes Database Review

Review date: 2026-10-02 (revision 2)  
First reviewed: 2026-07-07  
Database: PostgreSQL 14.24, `oceanomics_genomes` @ 146.118.120.134  
Scope: Schema design, relationship quality, data completeness signals, view design, migration governance, and improvement planning  
Status: Review, plus the Phase A remediations applied on 2026-10-02 (migrations `027`–`030`). Each is recorded in Appendix C and in the relevant finding.

## 0. What Changed Since Revision 1

Revision 1 reviewed 31 tables and 11 views. The live database now holds **53 tables and 17 views**, and column count has grown from 934 to 1,502. Three distinct bodies of work landed in between, and they did not all land the same way.

### 0.1 Changes with migrations and a ledger

The mitogenome/ENA pipeline work in `sql/` (`001`–`026`) is the strongest schema work in the project so far. It is numbered, idempotent, guarded with `to_regclass()` so it replays safely against partial schemas, recorded in a `schema_migrations` table with SHA-256 per file, and — unusually — each file carries a prose header explaining *why* the change was made, what was rejected, and what must not be done later. Several of those headers are better documentation than anything in `docs/`.

Applied: at review time, `001`–`025` ledgered and `026` physically applied but **not ledgered** (see Finding 10). The `026` ledger row was written on 2026-10-02; the ledger now covers `001`–`030` with no gaps.

| Migration | Effect |
|---|---|
| `001`, `002` | `ena_validation_attempts` created, then collapsed to one row per attempt key. |
| `003` | `mitogenome_data` gains 13 typed depth columns and `depth_method`; legacy `avg_coverage` retained and labelled rather than silently recomputed. |
| `004` | ENA candidate/package registry, `ena_specimen_accessions`, `ena_related_assemblies`, locus registry. |
| `005`–`009` | Webin test/production split, tech-aware locus tags, INSDC BioSample accession handling, submission queue, locus serial renumbering into coordinate order. |
| `010`–`013` | Locus-tag allocation, local package validation, selection layer and candidate runs all retired to a downstream repo; dropped tables archived first (`ena_locus_registry_archive`, `ena_candidate_loci_archive`). |
| `014` | `ena_validation_attempts` re-keyed from `assembly_prefix` to `full_seqid` + `annotation`. Table rebuild. |
| `015` | `ena_submissions` ledger created, owned by the downstream submitter. |
| `016`, `018` | `mitogenome_data.og_num` restored as a stored generated column, then moved back to position 1. Table rebuild with a bidirectional `EXCEPT` verification before the swap. |
| `017` | Retro-documents the content-addressing rework of `lca` / `lca_raw_results` (`content_hash` trigger + unique constraints) that had been applied to the live database in August and never written down. |
| `019` | Repairs `submission_ready`, which `005` wrongly cleared for every row when replayed against a restored database. |
| `020` | `og_num` added to `ena_validation_attempts`; rebuild with row-for-row verification. |
| `021`, `023`, `024`, `025` | Audit columns for relaxed QC gates: `trna_advisory`, `order_variant`, `order_deviation`, `annotation_gaps`, `validated_rank`, order-variant taxon agreement. |
| `022` | Widens `blast_filtered_lca.taxon_id` to text and the two confidence columns to double precision; 87 assemblies had been losing their LCA rows to `;`-joined `staxids` and `5.27e-163` confidence values. Re-hashes every row so `content_hash` stays consistent under the new types. |
| `026` | 16 additive annotation-integrity / lineage-gene / MITOS-audit columns on `mitogenome_data`. |

### 0.2 Changes with migrations that were never deployed

`genomes_db_review/sqitch.plan` declares eight Sqitch changes, including the Phase 3 index work and the whole `v2` lab-table redesign. **None of them are deployed.** There is no Sqitch registry schema on the live database and no `v2` schema at all — `public` is the only non-system schema present. Every index candidate from revision 1's Finding 4 is still missing.

### 0.3 Changes with no migration anywhere

These tables and views exist on the live database and appear in no migration directory, no baseline file, and no data dictionary:

| Object | Rows | Apparent purpose |
|---|---:|---|
| `data_package_delivery` | 1 | Project data-delivery run header. |
| `data_package_component` | 3 | Per-component approval/validation state. |
| `data_package_item` | 110 | Per-`og_id`/`seq_id` inclusion decisions. |
| `data_package_artifact` | 10 | Packaged archive files, digests, upload state. |
| `data_package_link_set` | 0 | Expiring download links (`jsonb`). |
| `data_package_email` | 0 | Delivery email preview/send ledger. |
| `data_package_email_recipient` | 0 | Email recipients. |
| `project_delivery_contact` | 0 | Per-project contact roster. |
| `ncbi_genome_assemblies` | 1,772 | NCBI assembly metadata feed. |
| `master_species_genome` | 19,817 | Genome columns split off `master_species`, FK'd back to it. |
| `mitogenome_data_SS260818` | 2,181 | Frozen 2026-08-18 snapshot. |
| `lca_SS260818` | 9,890 | Frozen snapshot. |
| `lca_raw_results_SS260818` | 51,032 | Frozen snapshot. |
| `lca_validation_SS260818` | 2,056 | Frozen snapshot. |
| `blast_filtered_lca_SS260818` | 192,207 | Frozen snapshot. |
| `schema_migrations` | 25 | Migration ledger for `sql/`. |
| `ena_submission_status` (view) | — | ENA submission reporting. |
| `ena_validation_latest` (view) | — | Latest validation per sequence. |
| `mitogenome_submission_view` (view) | — | Mitogenome submission reporting. |
| `lca_pivot_view_SS260818` (view) | — | Snapshot pivot. |
| `lca_results_view_SS260818` (view) | — | Snapshot results. |
| `lca_validation_report_view_SS260818` (view) | — | Snapshot validation report. |

The `data_package_*` subsystem is the largest single piece of undocumented schema: eight tables, ten foreign keys, `ON DELETE CASCADE` throughout, and a design that is visibly more careful than the legacy lab tables — but nothing in source control describes it.

### 0.4 Finding status at a glance

| # | Finding (rev 1) | Status now |
|---|---|---|
| 1 | Repository is not the schema source of truth | **Worse.** Baseline covers 31 of 53 tables; three parallel migration systems. |
| 2 | Species data has two competing authorities | **Worse.** Now three species tables and a fourth `og_id` authority; sample species drift grew. |
| 3 | Logical relationships not enforced | **Much improved.** `blast_filtered_lca` orphans 334 → 0; FKs are now actually addable. |
| 4 | FK columns not indexed | **Unchanged.** All 24 candidates still missing. |
| 5 | Sequencing modelled with polymorphic nullable columns | **Unchanged.** |
| 6 | Columns unused or nearly unused | **Unchanged.** All 16 named columns still fully empty. |
| 7 | Dates/numbers/statuses stored as text | **Mixed.** New tables are properly typed; legacy unchanged; status cardinality worsened. |
| 8 | Reporting views hide logic and carry performance risk | **Worse, and now measured.** `summary` takes 7.6 s. |
| 9 | Documentation coverage minimal | **Improved.** 0 → 3 object comments, 12 → 60 column comments. |
| 10 | — | **New.** Three migration systems, one ledger gap. |
| 11 | — | **New. RESOLVED 2026-10-02** by migration `027`. Production views read frozen August snapshots. |
| 12 | — | **New.** Snapshot tables have become permanent fixtures. |
| 13 | — | **New.** Nine tables have no primary key. |
| 14 | — | **New.** Database credentials in a world-readable file. |
| 15 | — | **New.** Live `lca_validation` species-name coverage is incomplete; exposed by fixing 11. |
| 16 | — | **New. RESOLVED 2026-10-02** by migrations `028`+`029`. `mitogenome_submission_view` ENA join keyed one grain too coarse. |

## 1. Executive Summary

The Ocean Genomes database remains functional and the central laboratory workflow is still coherent. Since July the picture has become **bimodal**: the newest work is well engineered, and the oldest work has not moved.

What improved:

- The mitogenome/ENA pipeline now has real migrations, a ledger, idempotent guards, verified table rebuilds, and genuinely good inline documentation.
- `blast_filtered_lca` was rebuilt and re-pushed; its 334 orphan `og_id` values are gone. Across the eight largest `og_id`-bearing tables there are now only 7 orphan rows and 33 blank ones.
- New tables use `timestamptz`, `double precision`, `bigint`, `date`, `jsonb`, real check constraints, partial unique indexes, and generated `og_num` columns. The `data_package_*` subsystem and `ena_*` tables are the best-modelled part of the database.
- Column documentation went from 12 comments to 60, concentrated where the new work landed.

What got worse:

- There are now **three** migration systems: `sql/` + `schema_migrations` (deployed), `genomes_db_review/sqitch.plan` (declared, never deployed), and direct DDL against production (eight `data_package_*` tables, two reference tables, five snapshot tables, six views). The schema baseline in `schema/current_schema.sql` describes 31 tables; the database has 53.
- `summary` now takes **7.6 seconds** to execute. In July this was a projected risk; it is now a measured one.
- `summary`, `embargo_assignment_view`, and `mitogenome_submission_view` read the frozen `*_SS260818` snapshot tables rather than the live ones. 61 samples that have live LCA validation are invisible to the Summary report, and 39 samples in the report carry validation that the live pipeline no longer holds.
- Species fragmentation increased: `species` (22,724), `master_species` (19,817), and now `master_species_genome` (19,817). Samples whose `nominal_species_id` is absent from `species` grew from 645 to 892.
- `ena_specimen_accessions` (2,848 rows) is a fourth specimen authority alongside `sample`, with no foreign key to it.
- Everything in revision 1's Phase 3 and Phase 4 — the cheap, high-value index and constraint work — is still entirely undone.

The single highest-value action has changed. In July it was "establish a schema baseline". The baseline exists but is already stale by 22 tables, so the recommendation is now sharper: **pick one migration tool, re-baseline from the live database, and bring the `data_package_*` and snapshot layers under it.** The second is to repoint the three reporting views off the August snapshots. Both are small, and both are currently producing wrong answers for users.

## 2. Review Goals

Unchanged from revision 1. The database should become:

- Easier to understand.
- More efficient for common reporting and API queries.
- More reliable through better constraints and clearer relationships.
- Tidier by removing or deprecating unused structures.
- Safer to evolve through versioned schema management.

This review intentionally does not apply any changes.

## 3. Methodology

This revision used:

- Read-only inspection of the live PostgreSQL schema via `information_schema` and the PostgreSQL catalogs.
- Review of all 26 migration files in `sql/`, and of the `schema_migrations` ledger.
- Review of `genomes_db_review/sqitch.plan` and the `deploy/`, `revert/`, `verify/` scripts, checked against live schema presence.
- Comparison of `schema/current_schema.sql` against the live object inventory.
- Read-only row-count, sparsity, orphan, and status-cardinality checks.
- `EXPLAIN (ANALYZE)` on `summary` and `goat_species_v1`.
- Dependency analysis of all 17 views against the snapshot tables.

No mutation statements were run against the database.

## 4. Current Architecture Snapshot

### 4.1 Live Database Inventory

53 base tables and 17 views in `public`. `public` is the only non-system schema.

Core lab workflow and reference tables:

| Table | Rows (Jul) | Rows (Oct) | Notes |
|---|---:|---:|---|
| `sample` | 2,675 | 3,294 | Core sample table. |
| `tissue` | 5,393 | 7,241 | FK to `sample`. |
| `dna_extraction` | 2,273 | 2,636 | FK to `tissue`. 1 blank `og_id`. |
| `rna_extraction` | 262 | 270 | FK to `tissue`. |
| `illumina_library` | 1,724 | 2,080 | FK to `dna_extraction`. |
| `pacbio_library` | 427 | 439 | FK to `dna_extraction`. |
| `ont_library` | 98 | 98 | FK to `dna_extraction`. No new rows. |
| `hic_lysate` | 439 | 439 | FK to `tissue`. No new rows. |
| `hic_library` | 326 | 326 | FK to `hic_lysate`. No new rows. |
| `rna_library_ilmn` | 271 | 389 | FK to `rna_extraction`. |
| `rna_library_kinx` | 177 | 188 | Still no FK to `rna_extraction`. |
| `sequencing` | 4,212 | 4,765 | Polymorphic nullable library links. |
| `design_description` | 2 | 2 | Lookup-like. No FK links. |
| `species` | 22,650 | 22,724 | |
| `master_species` | 19,817 | 19,817 | Used by GoaT view. |
| `master_species_genome` | — | 19,817 | **New.** Genome columns split off `master_species`. |
| `species_ncbi_assembly` | 0 | 0 | Still empty. |
| `ncbi_genome_assemblies` | — | 1,772 | **New.** NCBI assembly feed. |

Genome, QC, and raw data:

| Table | Rows (Jul) | Rows (Oct) | Notes |
|---|---:|---:|---|
| `draft_genomes` | 1,448 | 1,542 | 0 orphan `og_id` (was unmeasured). |
| `ref_genomes` | 1,835 | 1,994 | 4 orphan `og_id`. |
| `ref_genomes_assembly_uploads` | 54 | 88 | |
| `ref_genomes_sra_uploads` | 153 | 304 | FK to assembly uploads. |
| `raw_data` | 8,010 | 8,010 | 30 blank `og_id`. No new rows. |
| `raw_qc` | 240 | 252 | 3 orphan `og_id`. |
| `hifi_reads_qc` | 248 | 277 | 0 orphan. |
| `hic_reads_qc` | 522 | 552 | 0 orphan. |
| `rna_qc_kinnex` | 96 | 96 | No PK. No new rows. |

Mitogenome / LCA, live:

| Table | Rows (Jul) | Rows (Oct) | Notes |
|---|---:|---:|---|
| `mitogenome_data` | 2,165 | 2,301 | Rebuilt twice (`016`, `018`). `og_num` generated. 0 orphan. |
| `lca` | 6,384 | 4,784 | Content-addressed (`017`). No PK. |
| `lca_raw_results` | 20,170 | 46,072 | Content-addressed. No PK. |
| `lca_validation` | 2,021 | 1,854 | `validated_rank` added (`024`). |
| `blast_filtered_lca` | 191,888 | 241,564 | Rebuilt; orphans 334 → 0. `taxon_id` widened to text. |
| `lca_old` | 2,895 | 2,895 | Legacy. Now FK'd to the `SS260818` snapshot. |

ENA submission pipeline (all new):

| Table | Rows | Notes |
|---|---:|---|
| `ena_validation_attempts` | 1,185 | Keyed on `full_seqid` + annotation. 1,149 `submission_ready`. |
| `ena_submissions` | 539 | Downstream-owned ledger. All 539 `ACCESSION_ASSIGNED`. |
| `ena_specimen_accessions` | 2,848 | Specimen registry. No FK to `sample`. |
| `ena_related_assemblies` | 0 | Empty. |
| `ena_locus_registry_archive` | 0 | Frozen archive from `010`. Empty — nothing had been allocated. |
| `ena_candidate_loci_archive` | 0 | Frozen archive from `010`. Empty. |

Data delivery subsystem (all new, no migration):

| Table | Rows |
|---|---:|
| `data_package_delivery` | 1 |
| `data_package_component` | 3 |
| `data_package_item` | 110 |
| `data_package_artifact` | 10 |
| `data_package_link_set` | 0 |
| `data_package_email` | 0 |
| `data_package_email_recipient` | 0 |
| `project_delivery_contact` | 0 |

Frozen snapshots (all new, no migration):

| Table | Rows |
|---|---:|
| `blast_filtered_lca_SS260818` | 192,207 |
| `lca_raw_results_SS260818` | 51,032 |
| `lca_SS260818` | 9,890 |
| `lca_validation_SS260818` | 2,056 |
| `mitogenome_data_SS260818` | 2,181 |

Views:

| View | Reads snapshots? | Purpose |
|---|---|---|
| `coverage_summary` | no | HiFi/Hi-C yield and coverage. |
| `embargo_assignment_view` | **yes** | Sample embargo/assignment reporting. |
| `ena_submission_status` | no | **New.** ENA submission reporting. |
| `ena_validation_latest` | no | **New.** Latest validation per sequence. |
| `filtered_lca_view` | no | Filtered LCA output. |
| `goat_project_metadata_v1` | no | GoaT project metadata API view. |
| `goat_species_v1` | no | GoaT species API view. |
| `lca_pivot_view` | no | LCA region pivot. |
| `lca_pivot_view_SS260818` | yes | **New.** Snapshot pivot. |
| `lca_results_view` | no | LCA validation helper. |
| `lca_results_view_SS260818` | yes | **New.** Snapshot variant. |
| `lca_validation_report_view` | no | Validation reporting. |
| `lca_validation_report_view_SS260818` | yes | **New.** Snapshot variant. |
| `mitogenome_submission_view` | **yes** | **New.** Mitogenome submission reporting. |
| `sample_view` | no | Sample metadata subset. |
| `summary` | **yes** | Operational workflow summary. |
| `v_genome_size_comparison` | no | Genome size vs NCBI assembly data. |

The three views in bold are the problem: they are general-purpose reporting surfaces, not snapshot-specific ones, and they read frozen data. See Finding 11.

### 4.2 Repository Schema Coverage

| Artifact | Covers | Deployed |
|---|---|---|
| `schema/current_schema.sql` | 31 tables, as of 2026-07 | — (baseline only) |
| `migrations/legacy/*.sql` | 2 changes, superseded by Sqitch | unclear |
| `sqitch.plan` | 8 changes incl. all Phase 3 indexes and the `v2` redesign | **no** |
| `sql/001`–`026` | ENA + mitogenome tables | yes (`026` unledgered) |
| nothing | 8 `data_package_*` tables, `project_delivery_contact`, `ncbi_genome_assemblies`, `master_species_genome`, 5 snapshot tables, 6 views | yes |

22 of 53 live tables are in no repository artifact.

## 5. Existing Relationship Model

The central wet-lab chain is unchanged and still the strongest part of the schema:

```text
sample
  -> tissue
      -> dna_extraction
          -> illumina_library
          -> pacbio_library
          -> ont_library
      -> rna_extraction
          -> rna_library_ilmn
          -> rna_library_kinx   (still unenforced)
      -> hic_lysate
          -> hic_library
```

The LCA chain is enforced, and now split across live and snapshot parents:

```text
mitogenome_data                    mitogenome_data_SS260818
  -> lca                             -> lca_SS260818
  -> lca_raw_results                 -> lca_raw_results_SS260818
  -> lca_validation                  -> lca_validation_SS260818
                                     -> lca_old
```

`lca_old` was re-pointed at the snapshot parent during the August rebuild. That is defensible — it is historical data and the snapshot is its contemporaneous parent — but it means `lca_old` can never be reconciled against the live table without going through the snapshot.

The ENA layer has its own enforced chain, rooted on its own specimen table rather than on `sample`:

```text
ena_specimen_accessions           (2,848 rows, og_id, no FK to sample)
  -> ena_related_assemblies

ena_validation_attempts           (og_id, no FK to anything)
ena_submissions                   (og_id, no FK to anything)
```

The data delivery layer is fully enforced internally, which is a notable contrast with the rest of the database:

```text
data_package_delivery
  -> data_package_component
      -> data_package_item          (og_id, seq_id; no FK to sample)
      -> data_package_artifact
  -> data_package_artifact
  -> data_package_link_set
      -> data_package_email
          -> data_package_email_recipient
              -> project_delivery_contact
```

Still carrying `og_id` with no enforced link to `sample`:

```text
sample
  -> draft_genomes
  -> ref_genomes
  -> raw_data
  -> raw_qc
  -> hifi_reads_qc
  -> hic_reads_qc
  -> blast_filtered_lca
  -> mitogenome_data
  -> ena_specimen_accessions
  -> ena_validation_attempts
  -> ena_submissions
  -> data_package_item
```

The list got longer, but — and this is the real change since July — most of these are now clean enough to constrain. See Finding 3.

## 6. Major Findings

### Finding 1: The repository is not the schema source of truth

Severity: High  
Theme: Maintainability, safety  
Status since revision 1: **worse**

Revision 1's recommendation was to create a baseline and move to migration-based management. The baseline was created (`schema/current_schema.sql`, 31 tables) and Sqitch was adopted (`sqitch.plan`, 8 changes). Neither took hold:

- The baseline is stale by 22 tables and 6 views. It mentions none of `ena_validation_attempts`, `data_package_delivery`, `ncbi_genome_assemblies`, or the snapshot tables.
- The Sqitch plan has never been deployed. There is no Sqitch registry on the database and the `v2` schema it creates does not exist.
- A second, independent migration system (`sql/` + `schema_migrations`) was built for the mitogenome pipeline and *is* deployed. It does not know about the Sqitch plan, and vice versa.
- A third category of change — the `data_package_*` subsystem, the two new reference tables, the five snapshot tables, and six views — was applied by direct DDL with no migration file at all.

Why this matters:

- A database rebuilt from source control would be missing the entire data-delivery subsystem, both new reference tables, and every snapshot table. Three production views would fail to create.
- The two migration systems can collide. `016` and `018` document exactly this hazard: index names like `mitogenome_data_pkey` were already taken by the snapshot table, so the live table's indexes carry `_1` suffixes that look like leftovers but are load-bearing.
- `017` exists solely because a live change (LCA content addressing) was made in August and never written down; it was reconstructed after the fact. That reconstruction worked, but it is not repeatable as a practice.

Recommendation:

1. Pick one tool. The `sql/` convention is the one that actually works in practice and has the better documentation discipline; Sqitch is the one with revert/verify scripts. Choose on that trade-off, but choose.
2. Re-baseline from the live database into `schema/`, including the `data_package_*` and snapshot layers.
3. Write catch-up migration files for the 22 unmanaged tables and 6 unmanaged views — even if they only assert what already exists, so a rebuild reproduces them.
4. Either deploy the Sqitch index change or port it into the surviving system. It is the cheapest unrealised win in the project.

### Finding 2: Species data now has three competing authorities

Severity: High  
Theme: Data integrity, modeling  
Status since revision 1: **worse**

| Table | Rows (Jul) | Rows (Oct) | Columns |
|---|---:|---:|---:|
| `species` | 22,650 | 22,724 | — |
| `master_species` | 19,817 | 19,817 | 31 |
| `master_species_genome` | — | 19,817 | 7 |

Overlap:

| Check | Jul | Oct |
|---|---:|---:|
| Rows in both `species` and `master_species` | 19,817 | 19,817 |
| In `species` but not `master_species` | 2,833 | 2,907 |
| In `master_species` but not `species` | 0 | 0 |

`master_species_genome` is a proper normalisation: it lifts the genome-tracking columns out of `master_species` and carries a real `FOREIGN KEY (species) REFERENCES master_species(species) ON UPDATE CASCADE ON DELETE CASCADE`. As a piece of modelling it is correct. But it was built on top of `master_species`, which revision 1 recommended retiring — so the non-canonical table now has a dependant, and retiring it has become more expensive than it was in July.

Sample species linkage degraded:

| Check | Jul | Oct |
|---|---:|---:|
| `sample.nominal_species_id` blank/null | 33 | 43 |
| `sample.nominal_species_id` not in `species` | 645 | 892 |
| `sample.nominal_species_id` not in `master_species` | 706 | 953 |
| `sample.assigned_species` not in `species` | 25 | 25 |

619 samples were added and roughly 250 of them arrived with a `nominal_species_id` that is not in the taxonomy. The import path is not validating against either species table.

Migration `024` is relevant context here and is a point in the project's favour: `species_validation.py` now recognises that many `nominal_species_id` values are not binomials at all (`'Diaphus sp 1'`, `'Squalus notocaudatus?'`, `'Ophidiidae'`, `'Serrivomer'`) and records the rank at which validation succeeded in `lca_validation.validated_rank`. So the shape of the problem is now understood and instrumented — it just has not been fixed at the source.

Recommendation:

Unchanged in direction, more urgent in timing:

- Make `species` canonical.
- Redefine `master_species` as a view over `species`, and re-point `master_species_genome`'s FK at `species`. Do this before `master_species_genome` acquires more dependants.
- Add a validating check or FK on `sample.nominal_species_id` at import time. 892 bad rows is still tractable; at the current rate it will not stay that way.
- Use `lca_validation.validated_rank` to classify the 892: a non-binomial family-level label is a different problem from a typo.

### Finding 3: Logical relationships are much closer to enforceable

Severity: Medium (was High)  
Theme: Data integrity  
Status since revision 1: **much improved**

The August rebuild of the LCA/BLAST tables cleared the largest orphan population in the database.

| Table | Rows | Blank `og_id` (Jul → Oct) | Orphan `og_id` (Jul → Oct) |
|---|---:|---|---|
| `blast_filtered_lca` | 241,564 | 0 → 0 | **334 → 0** |
| `raw_qc` | 252 | 0 → 0 | 3 → 3 |
| `ref_genomes` | 1,994 | 0 → 0 | 4 → 4 |
| `raw_data` | 8,010 | 30 → 30 | 0 → 0 |
| `sequencing` | 4,765 | 2 → 2 | 0 → 0 |
| `dna_extraction` | 2,636 | 1 → 1 | 0 → 0 |
| `draft_genomes` | 1,542 | 0 | 0 |
| `mitogenome_data` | 2,301 | 0 | 0 |
| `hifi_reads_qc` | 277 | 0 | 0 |
| `hic_reads_qc` | 552 | 0 | 0 |
| `ena_specimen_accessions` | 2,848 | 0 | 0 |
| `ena_validation_attempts` | 1,185 | 0 | 0 |

Across every `og_id`-bearing table there are now **7 orphan rows and 33 blank ones** out of roughly 270,000. Revision 1's open question 2 — whether `OG672L-1`, `OG90_bc2008`, `OG750_PD` were invalid IDs, derived IDs, or valid analysis IDs — has been answered in practice for `blast_filtered_lca`: the rebuild did not reproduce them, so they were artefacts. Only `raw_qc` (3) and `ref_genomes` (4) still carry them.

This changes the cost of Phase 4 substantially. The FKs revision 1 listed as "candidate future constraints, after cleanup" are now addable for `draft_genomes`, `mitogenome_data`, `hifi_reads_qc`, `hic_reads_qc`, `blast_filtered_lca`, `ena_specimen_accessions`, and `ena_validation_attempts` with **no cleanup at all**.

Recommendation:

Add these now, as one migration — the data already satisfies them:

```sql
ALTER TABLE draft_genomes           ADD CONSTRAINT draft_genomes_og_fk           FOREIGN KEY (og_id) REFERENCES sample (og_id);
ALTER TABLE mitogenome_data         ADD CONSTRAINT mitogenome_data_og_fk         FOREIGN KEY (og_id) REFERENCES sample (og_id);
ALTER TABLE hifi_reads_qc           ADD CONSTRAINT hifi_reads_qc_og_fk           FOREIGN KEY (og_id) REFERENCES sample (og_id);
ALTER TABLE hic_reads_qc            ADD CONSTRAINT hic_reads_qc_og_fk            FOREIGN KEY (og_id) REFERENCES sample (og_id);
ALTER TABLE blast_filtered_lca      ADD CONSTRAINT blast_filtered_lca_og_fk      FOREIGN KEY (og_id) REFERENCES sample (og_id);
ALTER TABLE ena_specimen_accessions ADD CONSTRAINT ena_specimen_og_fk            FOREIGN KEY (og_id) REFERENCES sample (og_id);
ALTER TABLE ena_validation_attempts ADD CONSTRAINT ena_validation_attempts_og_fk FOREIGN KEY (og_id) REFERENCES sample (og_id);
```

Each needs the supporting index from Finding 4 first, or the parent-side delete cost gets worse rather than better. Fix the 7 remaining orphans in `raw_qc` and `ref_genomes` and those two can follow.

One caveat worth stating: adding an FK to `sample` makes the ENA and LCA pipelines fail on insert when a sample has not been registered yet. That is the correct behaviour, but it is a behaviour change for the pipelines, so it needs to go out with the pipeline owners' agreement rather than silently.

### Finding 4: Foreign key columns are still not indexed

Severity: Medium to High  
Theme: Performance, operational safety  
Status since revision 1: **resolved 2026-10-02** (see "Resolution" below)

All 24 index candidates from revision 1 were still missing at the time of this review:

| Column | Indexed? |
|---|---|
| `tissue.og_id` | missing |
| `dna_extraction.tissue_id`, `dna_extraction.og_id` | missing |
| `rna_extraction.tissue_id`, `rna_extraction.og_id` | missing |
| `illumina_library.dna_id`, `illumina_library.og_id` | missing |
| `pacbio_library.dna_id`, `pacbio_library.og_id` | missing |
| `ont_library.dna_id`, `ont_library.og_id` | missing |
| `hic_lysate.tissue_id` | missing |
| `hic_library.lysate_id`, `hic_library.og_id` | missing |
| `rna_library_ilmn.rna_id`, `rna_library_ilmn.og_id` | missing |
| `rna_library_kinx.rna_id`, `rna_library_kinx.og_id` | missing |
| `sequencing.og_id` and all four library tube FK columns | missing |
| `ref_genomes_sra_uploads.og_id` | missing |

The migration that would fix this (`add_core_lookup_indexes`, the first change in `sqitch.plan`, ported from `migrations/legacy/202607070001_add_core_lookup_indexes.sql`) was written in July and never deployed.

The contrast with the new tables is stark. Everything built since July is indexed deliberately:

- `ena_validation_attempts`: PK, unique attempt key, identity index on `(og_id, tech, seq_date, code)`, `recorded_at DESC`.
- `ena_submissions`: PK, identity index, status index.
- `ena_specimen_accessions`: PK, unique on `og_numeric`, unique on BioSample accession.
- `ena_related_assemblies`: PK, composite unique, partial unique `WHERE is_primary`.
- `data_package_item` / `data_package_artifact`: PK, composite unique, plus an `og_id` lookup index and a remote-path index.
- `lca` / `lca_raw_results`: content-hash unique indexes whose leading columns `(og_id, tech, seq_date, code)` happen to cover the composite FK to `mitogenome_data` — so those FK lookups are served, by luck of column order rather than by design, but served.

So the project knows how to index. The legacy tables simply never got the migration applied.

Why this matters more than in July:

- `tissue` grew 34% (5,393 → 7,241) and `illumina_library` 21% (1,724 → 2,080), and `summary` does per-sample correlated lookups into both. `summary` is now at 7.6 s (Finding 8).
- Finding 3's FKs should not be added without these indexes in place.

**Deployment status re-verified 2026-10-02.** Confirmed not deployed, three ways:

- None of the 19 index names the migration creates (`idx_tissue_og_id`, `idx_dna_extraction_tissue_id`, …) exists on the database.
- There is no `sqitch` registry schema, so Sqitch has never run against this database at all.
- Each of the 11 affected tables has **exactly one index**, and in every case it is that table's `*_pkey` primary key — `Tissue_pkey`, `DNA_Extraction_pkey`, `Illumina_Library_pkey`, and so on. There are no secondary indexes of any kind on these tables.

Also worth noting: the migration as written covers **19** of the 24 candidates. It omits `sequencing`'s four library tube FK columns (`illumina_library_tube_id`, `pacbio_library_tube_id`, `ont_library_tube_id`, `hic_library_tube_id`) and `ref_genomes_sra_uploads.og_id`. Those five should be added to it before deploying, since the `sequencing` tube columns are the child side of four live foreign keys.

Recommendation:

Deploy the existing index migration, extended with the five missing columns. It is already written, already reviewed, and is `CREATE INDEX` only. This is the lowest-risk, highest-value item in the whole backlog, and it has been sitting undeployed for three months.

The deploy script already uses `CREATE INDEX CONCURRENTLY` and is marked `-- no-transaction`, which is correct for live tables under pipeline writes. If it is ported out of Sqitch into the `sql/` convention, that migration must **not** be wrapped in `BEGIN`/`COMMIT` — `CONCURRENTLY` cannot run inside a transaction block.

**Resolution — 2026-10-02.** Done, as `sql/030_core_lookup_indexes.sql`.

It was ported into the numbered-SQL convention rather than deployed through Sqitch: deploying one index change via Sqitch would have created a registry schema on a database that has never had one, standing up a second live migration system to record a change the first one already owns. `deploy/add_core_lookup_indexes.sql` is marked SUPERSEDED — DO NOT DEPLOY, and `revert/030_core_lookup_indexes_revert.sql` was written to match.

All **24** columns are now indexed, not the Sqitch version's 19 — the four `sequencing` library tube columns and `ref_genomes_sra_uploads.og_id` were added on port. The file is `CREATE INDEX CONCURRENTLY IF NOT EXISTS` throughout with no transaction wrapper, and its header documents the one replay hazard `CONCURRENTLY` introduces: an interrupted build leaves an `INVALID` index that `IF NOT EXISTS` will then skip rather than repair, so check `pg_index.indisvalid` before re-running.

Verified after apply: 24 indexes present, 0 invalid, ledger row written.

Measured effect, after `ANALYZE` on the 12 affected tables: **`summary` fell from 7.6 s to 2.0 s** — a 73% reduction, repeatable across runs. That addresses the acute part of Finding 8; the remaining 2.0 s is the view's own structure, which Phase D (pre-aggregated CTEs) still needs to deal with. Finding 3's FKs are now unblocked on the indexing precondition.

### Finding 5: Sequencing is still modelled with polymorphic nullable columns

Severity: High  
Theme: Modeling, query simplicity  
Status since revision 1: **unchanged**

| Linked library columns per row | Jul | Oct |
|---:|---:|---:|
| 0 | 40 | 40 |
| 1 | 4,172 | 4,725 |

| Technology | Jul | Oct |
|---|---:|---:|
| `Illumina` | 3,149 | 3,652 |
| `Hi-C` | 471 | 500 |
| `PacBio HIFI` | 287 | 308 |
| `PacBio Kinnex` | 138 | 138 |
| `ONT` | 92 | 92 |
| blank | 40 | 40 |
| `PacBio` | 35 | 35 |

553 rows were added, all correctly linked to exactly one library. The 40 unlinked rows and the 40 blank-technology rows are the same stable historical set — they have not grown, which suggests they are legacy rather than an ongoing import defect.

`PacBio Kinnex` is still 138 rows with no FK to `rna_library_kinx`, and `rna_library_kinx` (188 rows) still has no FK to `rna_extraction`. Neither grew much, so this is not getting worse, but it is also exactly as wrong as it was.

The `v2` redesign in `sqitch.plan` addresses this with a library identity registry replacing the five polymorphic columns. It is written and undeployed.

Recommendation:

Unchanged. Option A (unified `library` table) remains the tidier target, and the `v2` scaffold is already most of the way there. Given the 0-link and blank-technology rows are stable at 40, a `CHECK` enforcing "exactly one library link" on new rows (via `NOT VALID`, leaving the 40 historical rows alone) is a cheap interim guard:

```sql
ALTER TABLE sequencing ADD CONSTRAINT sequencing_one_library_check CHECK (
  (rna_library_tube_id IS NOT NULL)::int + (illumina_library_tube_id IS NOT NULL)::int
+ (ont_library_tube_id IS NOT NULL)::int + (pacbio_library_tube_id IS NOT NULL)::int
+ (hic_library_tube_id IS NOT NULL)::int = 1
) NOT VALID;
```

### Finding 6: Unused columns are still unused

Severity: Medium  
Theme: Tidiness, usability  
Status since revision 1: **unchanged**

Every column revision 1 named as fully empty is still fully empty, now across 3,294 samples rather than 2,675 — so 619 new rows all arrived NULL as well.

| Table | Column | Filled (Oct) |
|---|---|---:|
| `sample` | `illumina_sequencing` | 0 / 3,294 |
| `sample` | `hifi_sequencing` | 0 / 3,294 |
| `sample` | `hic_sequencing` | 0 / 3,294 |
| `sample` | `nanopore_sequencing` | 0 / 3,294 |
| `sample` | `rna_extraction` | 0 / 3,294 |
| `sample` | `rna_ilmn_sequencing` | 0 / 3,294 |
| `sample` | `rna_kinnex_sequencing` | 0 / 3,294 |
| `sample` | `illumina_public` | 0 / 3,294 |
| `sample` | `summary_comments` | 0 / 3,294 |
| `dna_extraction` | `status_overwrite` | 0 / 2,636 |
| `illumina_library` | `status_overwrite` | 0 / 2,080 |
| `pacbio_library` | `status_overwrite` | 0 / 439 |
| `hic_library` | `status_overwrite` | 0 / 326 |
| `ont_library` | `status_overwrite` | 0 / 98 |
| `rna_extraction` | `status_overwrite` | 0 / 270 |
| `rna_library_ilmn` | `status_overwrite` | 0 / 389 |
| `rna_library_kinx` | `status_overwrite` | 0 / 188 |
| `species_ncbi_assembly` | all | table still 0 rows |

Near-empty, barely moved:

| Table | Column | Jul | Oct |
|---|---|---:|---:|
| `sample` | `eschmeyer_id` | 1 / 2,675 | 1 / 3,294 |
| `sample` | `ncbi_sample_name` | 5 / 2,675 | 5 / 3,294 |
| `sample` | `hifi_public` | 8 / 2,675 | 8 / 3,294 |
| `sample` | `ncbi_assembly_upload` | 41 / 2,675 | 42 / 3,294 |
| `sample` | `ncbi_bioproject_id_lvl_3_hifi` | 52 / 2,675 | 90 / 3,294 |

Three months of operation with zero writes to any of these is reasonably strong evidence. `species_ncbi_assembly` is now superseded in practice by `ncbi_genome_assemblies` (1,772 rows), which answers revision 1's open question 6: the NCBI import happened, into a different table.

Recommendation:

The classification exercise revision 1 asked for can now be short-circuited for most of these:

- The eight empty `sample` workflow flags and the eight `status_overwrite` columns: **deprecate**. Three months of writes touched none of them. `status_overwrite` is still referenced by `summary`, so remove the `summary` references first — that also removes dead logic from the slowest view in the database.
- `species_ncbi_assembly`: **retire** in favour of `ncbi_genome_assemblies`, or document why both exist.
- `eschmeyer_id`, `ncbi_sample_name`, `hifi_public`, `illumina_public`: decide whether these are abandoned or reserved; at 1–8 rows they are not carrying information.

### Finding 7: Dates, numbers, and statuses — new tables good, legacy unchanged, statuses worse

Severity: Medium  
Theme: Data quality, query reliability  
Status since revision 1: **mixed**

The new tables get this right. `ena_validation_attempts`, `ena_submissions`, `ena_specimen_accessions`, all eight `data_package_*` tables, `ncbi_genome_assemblies`, and the 13 depth columns added to `mitogenome_data` by `003` use `timestamptz`, `double precision`, `bigint`, `integer`, `date`, `boolean`, and `jsonb` — with check constraints on accession and digest formats. This is the standard the rest of the schema should be held to.

The legacy text columns are unchanged:

| Still text | |
|---|---|
| Dates | `dna_extraction.extraction_date`, `draft_genomes.seq_date`, `hic_library.library_date`, `illumina_library.library_date`, `lca.lca_run_date`, `ont_library.library_date`, `pacbio_library.library_date`, `ref_genomes.seq_date`, `rna_library_ilmn.library_date`, `sequencing.run_date`, `blast_filtered_lca.blast_run_date`, `species.iucn_dateassessed` |
| Numbers | `sample.weight`, `sample.depth_collection`, `sample.lengthtl_and_lengthfl`, `sample.ont_num`, `dna_extraction.av_size`, `dna_extraction.total_yield`, `dna_extraction.ratio_260_280`, `dna_extraction.ratio_260_230`, `illumina_library.library_qubit_conc`, `rna_extraction.ratio_260_280`, `rna_extraction.ratio_260_230` |

**One reclassification.** Revision 1 listed `seq_date` as a text date to convert. It should be removed from that list: `seq_date` is the third field of the composite key `og_id.tech.seq_date.code`, which is the `full_seqid` naming convention the ENA pipeline, the LCA tables, and every on-disk artifact are built on. It is a `YYMMDD` identifier component, not a date value, and it sorts correctly as text. Converting it would break `mitogenome_data`'s primary key, four inbound foreign keys, `ena_validation_attempts`' identity index, and the filename convention. **Leave `seq_date` as text**, and document it as an identifier component rather than a date.

Status cardinality moved in the wrong direction:

| Field | Jul | Oct |
|---|---:|---:|
| `sample.rna_status` | 47 | 46 |
| `sample.ilrna_status` | 10 | **44** |
| `sample.pb_status` | 19 | 19 |
| `sample.hic_status` | 13 | 11 |
| `sample.il_status` | — | 10 |
| `pacbio_library.pacb_status` | 15 | 13 |
| `hic_library.hic_status` | 9 | 8 |

`sample.ilrna_status` went from 10 distinct values to 44 — a 4x increase on a field that revision 1 already flagged for comma-combined duplicates. This is the clearest evidence that free-text status fields are actively accumulating noise, not holding steady.

Migrations `021`, `023`, `024` and `025` are worth noting as the counter-example. Where the project needed to relax a QC gate, it added a dedicated audit column with an enumerated, documented value set (`trna_advisory`, `order_variant`, `order_deviation`, `validated_rank`, `order_variant_taxon_check`) and the migration header states explicitly that the value must stay queryable and, in `025`'s case, that the column **must never become a gate**. That is exactly the discipline the lab-side status columns lack.

Recommendation:

- Convert the legacy date and numeric columns, excluding `seq_date`.
- Prioritise `sample.ilrna_status` for normalisation; it is degrading fastest.
- Build the status lookup table, and populate it from the enumerated value sets the newer migrations already document.

### Finding 8: `summary` is now measurably slow, and `goat_species_v1` has not improved

Severity: High (was Medium to High)  
Theme: Performance, maintainability  
Status since revision 1: **worse, and now measured**

Revision 1 flagged `summary` and `goat_species_v1` as carrying correlated-subquery risk. Measured now:

| View | Planner cost | Actual execution |
|---|---:|---|
| `summary` (full scan, 3,294 rows) | 3,913,657 | **7,578 ms** |
| `goat_species_v1` (first 100 rows) | 168,812 (32,362,040 for full) | 275 ms |

`summary` executes one correlated subplan per sample per derived column, with sequential scans into `tissue` (7,241 rows), `dna_extraction` (2,636), and each library table. 162 JIT functions get compiled per execution. None of the FK columns those subplans scan are indexed (Finding 4). The projected degradation arrived: at 2,675 samples this was tolerable, at 3,294 it is not, and at 5,000 it will be unusable.

`goat_species_v1` still does repeated `EXISTS` checks against `sample` and `ref_genomes` for each of 19,817 `master_species` rows, sorted before the subplans run. The 275 ms for 100 rows is acceptable only because of the `LIMIT`; the full-scan estimate is 32M.

Some of `summary`'s work is provably dead: it still references the eight `status_overwrite` columns, every one of which is empty in every row (Finding 6).

Recommendation:

- Strip the `status_overwrite` references from `summary`. Free, and removes dead branches from the hot path.
- Deploy the index migration (Finding 4). Most of `summary`'s cost is sequential scans on unindexed FK columns.
- Rebuild `summary` with pre-aggregated CTEs instead of per-row correlated subqueries, or make it a materialised view refreshed after the nightly import. At 3,294 rows and 7.6 s, a materialised view is the pragmatic answer.
- Repoint it off the snapshot tables first (Finding 11) — no point optimising a view that returns stale data.
- Add the API smoke tests revision 1 recommended before touching `goat_species_v1`.

### Finding 9: Documentation coverage improved, from a very low base

Severity: Medium  
Theme: Team knowledge, maintainability  
Status since revision 1: **improved**

| Metric | Jul | Oct |
|---|---|---|
| Table/view comments | 0 / 42 | 3 / 70 |
| Column comments | 12 / 934 | 60 / 1,502 |

The 48 new column comments are concentrated where the new work landed:

| Table | Commented columns |
|---|---:|
| `master_species` | 24 |
| `sample` | 11 |
| `mitogenome_data` | 7 |
| `ena_submissions` | 4 |
| `lca` | 3 |
| `lca_raw_results` | 3 |
| `mitogenome_data_SS260818` | 3 |
| `draft_genomes` | 2 |
| `blast_filtered_lca`, `ena_validation_attempts`, `ref_genomes` | 1 each |

The three object comments are all on ENA tables and all three say something genuinely useful about ownership — e.g. `ena_submissions`: *"Submission ledger, written by the downstream ENA submission pipeline. This pipeline never writes or reads it: validation does not depend on submission state."* That is the kind of statement that prevents a future mistake.

The quality of the `mitogenome_data` comments is also high: `depth_method` enumerates its five values, and `avg_coverage` is explicitly labelled `LEGACY, assembler-specific and NOT comparable across assemblers`, which is precisely the trap a new reader would fall into.

The real documentation asset, though, is not in the database — it is the 26 migration headers in `sql/`. Between them they explain the depth-metric redesign, the full-seqid rekeying, why selection moved downstream, why `seq_date` is in the key, why `submission_ready` was reset and recomputed, why `real` was too narrow for BLAST confidence scores, and why the order-variant taxon check must never become a gate. None of that is reachable from the database or from `docs/`.

Recommendation:

- Extract the migration headers into `docs/data_dictionary.md` so the reasoning survives independently of the SQL files.
- Keep the comment-as-you-go practice. It worked: every table that got new work got new comments.
- The eight `data_package_*` tables have zero comments and zero documentation anywhere. They are the biggest gap.

### Finding 10: Three migration systems and a ledger gap

Severity: High  
Theme: Maintainability, safety  
Status: **new** — ledger gap and drift check both closed 2026-10-02; the multiple-systems problem remains open

| System | Location | Changes | Deployed |
|---|---|---:|---|
| Numbered SQL + `schema_migrations` | `sql/` | 26 | 25 ledgered, 1 unledgered |
| Sqitch | `genomes_db_review/sqitch.plan` | 8 | **0** |
| Legacy flat files | `genomes_db_review/migrations/legacy` | 2 | unclear |
| Direct DDL | — | 22 tables, 6 views | yes |

Migration `026_mitogenome_data_annotation_integrity.sql` is the concrete symptom. All 16 of its columns are present on `mitogenome_data` — `order_status`, `order_deviation_detail`, `expected_lineage_genes`, `missing_expected_lineage_genes`, `lineage_gene_advisories`, `mitos_unmapped_features`, `mitos_known_auxiliary_features`, `duplicate_loci`, `annotation_integrity_status`, `annotation_integrity_issues`, `atp9`, `atp9_trans`, `mtmuts`, `mtmuts_trans`, `annotation_stats_version`, `annotation_updated_at` — but there is no row for it in `schema_migrations`. It was applied out of band.

In this specific case the consequence is mild: `026` is `ADD COLUMN IF NOT EXISTS` throughout with no `BEGIN`/`COMMIT`, so a replay is a no-op. But the ledger's whole purpose is to answer "what is applied?" without inspecting the catalog, and it can no longer do that. Note also that `026` is the only file in the set without explicit transaction control, which is probably why it was applied by hand.

Why this matters:

- The ledger is the mechanism that makes the `sql/` approach trustworthy. One unrecorded apply is a warning; a habit of them makes the ledger decorative.
- Two unaware migration systems targeting one database is how the `mitogenome_data_pkey` / `mitogenome_data_pkey_1` name collision documented in `018` happened.
- A rebuild from source control produces a database missing 22 tables.

Recommendation:

1. Insert the ledger row for `026` with its correct SHA-256, or re-apply it through `bin/apply_ena_migrations.py` so the row is written. Add `BEGIN`/`COMMIT` to `026` so it does not invite hand-application again.
2. Choose one system and retire the others. Write down the decision in `docs/database_change_checklist.md`.
3. Add a CI or cron check comparing the live object inventory against the baseline, failing on drift. The drift found in this review would all have been caught by one query.

**Partial resolution — 2026-10-02.** Recommendation 1 is done. `026` was given `BEGIN`/`COMMIT`, replayed against the live database (a no-op — all 16 columns were already present, every statement is `ADD COLUMN IF NOT EXISTS` or `COMMENT ON`), and its `schema_migrations` row written with the SHA-256 of the amended file. Editing an applied file normally violates `sql/README.md`'s "do not reformat an applied file" rule, but that rule exists to protect a recorded hash, and `026` had no recorded hash — which was the defect. Amending it before ledgering was therefore the one moment the fix was free. The ledger now accounts for all 30 numbered migrations with no gaps.

One Sqitch change was also retired into the numbered set (`add_core_lookup_indexes` → `030`, Finding 4), which narrows the surface but does not settle recommendation 2.

**Further resolution — 2026-10-02.** Recommendation 3 is done, and the mechanism behind the finding is closed.

`bin/apply_migrations.py` applies a migration and writes its `schema_migrations` row in one invocation, so the two can no longer come apart. It refuses to run at all if an already-applied file's hash no longer matches the tree; it detects `CREATE INDEX CONCURRENTLY` directly rather than trusting a comment marker, so `030`'s no-transaction requirement is honoured without editing that file; it checks `pg_index.indisvalid` after any concurrent build; and it refuses to apply `005` unless `019` is applied or pending, so the one replay hazard still latent in the set cannot fire by accident.

`bin/check_drift.py` compares the live object inventory against a tracked manifest (`schema/object_inventory.tsv`, 70 objects) and exits non-zero on any difference — suitable for cron or CI. Its `--coverage` mode classifies every live object by where it can be reproduced from. `schema/` was re-baselined the same day, having been three months stale.

Verified by test: a tampered applied file aborts the run; a deliberately broken migration leaves neither a partial schema nor a ledger row; `030` replays cleanly through the no-transaction path; and a canary table and view are both detected as drift.

Still open: recommendation 2 — choose one migration system and write the decision down. The coverage report now quantifies the cost of not having done so: of 70 live objects, **12 are created by a migration and 58 exist only as a dump snapshot**, with no change history or rationale behind them. That list is the Phase B catch-up worklist.

### Finding 11: Three production views read frozen August snapshots

Severity: High  
Theme: Correctness, reporting  
Status: **new — RESOLVED 2026-10-02 by migration `027_reporting_views_live_tables.sql`**

> **Resolution.** All three views were repointed at the live tables via `CREATE OR REPLACE VIEW`
> (chosen over DROP + CREATE so the `readonly` role's SELECT grant survived — the trap
> migration `018` had to work around). Only table names changed: 5 lines across the three
> views, verified by diffing `pg_get_viewdef` before and after. All 14 non-snapshot views now
> read live tables. Rollback: `sql/revert/027_reporting_views_live_tables_revert.sql`.
>
> Measured effect:
>
> | Metric | Before | After |
> |---|---:|---:|
> | `mitogenome_submission_view` rows | 2,181 | 2,301 |
> | `mitogenome_submission_view` rows with `webin_status` | 680 | **1,182** |
> | `summary` rows with HiFi validated name | 152 | 196 |
> | `summary` rows with Hi-C validated name | 135 | 164 |
> | `summary` rows with Illumina validated name | 981 | 933 |
> | `embargo_assignment_view` rows with a validated name | 1,120 | 1,090 |
>
> At `og_id` level: 241 samples gained a validated species name that the stale views had been
> hiding, and 271 lost one. The losses are correct — 39 of them exist only in the snapshot, and
> the other 232 do have live `lca_validation` rows but with a NULL `validated_species_name`.
>
> **This surfaced a separate, real problem the staleness was masking — see Finding 15.**
>
> The stale ENA join noted below as a known issue was fixed separately by migration
> `028_mitogenome_submission_view_annotation_key.sql` — see Finding 16.

Three general-purpose reporting views read `*_SS260818` snapshot tables instead of the live ones:

| View | Reads | Should read |
|---|---|---|
| `summary` | `lca_validation_SS260818` (3 references) | `lca_validation` |
| `embargo_assignment_view` | `lca_validation_SS260818` | `lca_validation` |
| `mitogenome_submission_view` | `mitogenome_data_SS260818`, `lca_validation_SS260818` | `mitogenome_data`, `lca_validation` |

These are distinct from `lca_pivot_view_SS260818`, `lca_results_view_SS260818`, and `lca_validation_report_view_SS260818`, which are explicitly named as snapshot views and are presumably intentional.

Measured divergence:

| Metric | Snapshot | Live |
|---|---:|---:|
| `lca_validation` distinct `og_id` | 1,474 | 1,496 |
| `mitogenome_data` distinct `og_id` | 1,483 | 1,579 |
| `og_id` in live only — **invisible to these views** | — | **61** |
| `og_id` in snapshot only — **stale in these views** | **39** | — |

So the Summary sheet, the embargo report, and the mitogenome submission view are each wrong in two directions: 61 samples with current LCA validation do not appear, and 39 samples appear carrying validation the live pipeline no longer holds.

`mitogenome_submission_view` is the most concerning of the three, because it joins the frozen `mitogenome_data_SS260818` to the **live** `ena_validation_attempts`. A sample validated by the current ENA pipeline against an assembly that only exists in the live `mitogenome_data` will simply not have a row. Migration `016`'s header notes in passing that `mitogenome_submission_view` reads the snapshot — recorded as a reason the migration was safe, not as a defect to fix, so it has stayed that way.

Why this matters:

- These are the views humans read. A wrong Summary sheet is worse than a slow one.
- `embargo_assignment_view` feeds embargo decisions. Stale validation there has external consequences.
- The divergence grows with every pipeline run. 61 and 39 today; more next month.

Recommendation:

Repoint all three at the live tables. This is a `CREATE OR REPLACE VIEW` per view, and should be the first change made after this review — it is small, it is reversible, and it is currently producing wrong answers.

Check column compatibility first: `lca_validation` gained `validated_rank` in `024` and `mitogenome_data` gained 30+ columns across `003`, `021`, `023`, `025`, `026`, so `SELECT *`-style expansion may shift. All three views enumerate their columns explicitly, so this should be mechanical.

### Finding 12: Snapshot tables have become permanent fixtures

Severity: Medium  
Theme: Tidiness, storage, clarity  
Status: **new**

| Snapshot table | Rows | Live counterpart | Rows |
|---|---:|---|---:|
| `blast_filtered_lca_SS260818` | 192,207 | `blast_filtered_lca` | 241,564 |
| `lca_raw_results_SS260818` | 51,032 | `lca_raw_results` | 46,072 |
| `lca_SS260818` | 9,890 | `lca` | 4,784 |
| `lca_validation_SS260818` | 2,056 | `lca_validation` | 1,854 |
| `mitogenome_data_SS260818` | 2,181 | `mitogenome_data` | 2,301 |
| **Total** | **257,366** | | **296,575** |

The snapshots hold 257,366 rows — 46% of all LCA-related rows in the database — and have been in place since 2026-08-18. They have acquired structural dependencies that make them hard to remove:

- Four foreign keys point into `mitogenome_data_SS260818` (`lca_SS260818`, `lca_raw_results_SS260818`, `lca_validation_SS260818`, and **`lca_old`**).
- Six views read them, three of which should not (Finding 11).
- They own the clean index names. `mitogenome_data_pkey`, `mitogenome_data_unique` and `mitogenome_data_depth_method_idx` belong to the snapshot, which is why the live table's equivalents carry `_1` suffixes. Migration `018` is explicit that these are *"deliberate, not leftovers"*.

Note `lca_SS260818` has 9,890 rows against a live `lca` of 4,784, and `lca_raw_results_SS260818` has 51,032 against 46,072 live. The content-addressing rework in `017` deduplicated these, so the live tables are smaller by design — but it means the snapshot is not simply "the old version of the live data", it is the pre-deduplication version, with different row semantics.

Recommendation:

- Decide whether these are an archive or a rollback point. If archive: move them to an `archive` schema, drop the six snapshot views, and the clean index names become reclaimable.
- If they are a rollback point, they have outlived it — the live tables have three months of pipeline output the snapshot does not.
- Either way, document them. A new reader encountering `mitogenome_data` and `mitogenome_data_SS260818` with near-identical row counts has no way to tell which is authoritative, and three production views currently pick the wrong one.
- `lca_old`'s FK to the snapshot is the thing that makes a clean drop impossible. Resolve `lca_old` first — revision 1's open question 5 (is `lca_old` still used?) is now blocking.

### Finding 13: Nine tables have no primary key

Severity: Medium  
Theme: Data integrity  
Status: **new**

| Table | Rows | Has unique index? |
|---|---:|---|
| `lca` | 4,784 | yes — `lca_content_unique` (7 columns incl. `content_hash`) |
| `lca_raw_results` | 46,072 | yes — `lca_raw_results_content_unique` (8 columns) |
| `ncbi_genome_assemblies` | 1,772 | yes — unique on `assembly_accession` |
| `rna_qc_kinnex` | 96 | no |
| `lca_old` | 2,895 | no |
| `lca_SS260818` | 9,890 | no |
| `lca_raw_results_SS260818` | 51,032 | no |
| `ena_locus_registry_archive` | 0 | no |
| `ena_candidate_loci_archive` | 0 | no |

For `lca` and `lca_raw_results` the unique content index is the real key, and the design is deliberate — `017` explains the content-addressing rationale, and the `ON CONFLICT` targets in `push_lca_blast_results.py` name those constraints directly. Promoting them to primary keys would be cosmetic. Worth doing anyway for the NOT NULL guarantee and for client tooling that looks for a PK, but not urgent.

`ncbi_genome_assemblies` should simply have `assembly_accession` as its PK; the unique index is already there.

`rna_qc_kinnex` is the genuine gap: 96 rows, no PK, no unique constraint, and no FK — revision 1 noted its tube IDs match `rna_library_kinx` but the link is unenforced. Nothing prevents duplicate QC rows for one library.

The snapshot and archive tables were created with `CREATE TABLE AS`, which does not carry constraints. Acceptable for frozen data, but it is why they cannot be verified.

Recommendation:

```sql
ALTER TABLE ncbi_genome_assemblies ADD PRIMARY KEY (assembly_accession);
-- after checking for duplicates:
ALTER TABLE rna_qc_kinnex ADD PRIMARY KEY (rna_tube_id);
ALTER TABLE rna_qc_kinnex ADD FOREIGN KEY (rna_tube_id) REFERENCES rna_library_kinx (rna_library_tube_id);
```

### Finding 14: Database credentials in a world-readable file

Severity: Medium  
Theme: Security, operational hygiene  
Status: **new** — file permissions fixed 2026-10-02; the rest open

`/home/tyler/.env.db` holds the host, port, database, user (`postgres`) and password in plaintext, with mode `-rw-rw-r--` — readable by any user on the host. The credentials are for the `postgres` superuser.

Revision 1 noted hardcoded credentials in `create_database.py`. This is the same problem, relocated to a dotfile. Several migration headers also print the full `psql -h 146.118.120.134 -U postgres` invocation, and `002`'s header names the config path `/home/tpeirce/postgresql_details/oceanomics.cfg`.

Recommendation:

- `chmod 600 /home/tyler/.env.db` as an immediate step.
- Use a `~/.pgpass` (mode 600) or a connection service file rather than an env file.
- Stop using the `postgres` superuser for pipeline writes. There is already a `readonly` role (migration `018` re-grants its SELECT on `mitogenome_data`), so role separation exists in part — extend it to a write role scoped to the pipeline tables.
- Remove the credentials from `create_database.py`, which revision 1 flagged and which is still outstanding.

**Partial resolution — 2026-10-02.** `/home/tyler/.env.db` is now mode `600` (was `-rw-rw-r--`). That closes the local read-by-any-user exposure and nothing else.

Treat the password as having been readable by every account on the host since 4 August 2026 — roughly two months. A `chmod` does not undo prior disclosure, so **rotating the `postgres` password is the real remediation** and has not been done. The three structural items — `.pgpass` or a connection service file instead of an env file, a non-superuser write role for the pipelines, and stripping credentials from `create_database.py` — are all still outstanding.

### Finding 15: Live `lca_validation` has materially less species-name coverage than the August snapshot

Severity: High  
Theme: Data completeness, pipeline correctness  
Status: **new — exposed by migration `027`**

Repointing the three reporting views (Finding 11) revealed a gap the stale snapshot had been hiding. 232 samples that displayed a validated species name in the old views have a live `lca_validation` row whose `validated_species_name` is NULL.

Live `lca_validation` has been **entirely rebuilt**. Every one of its 1,854 rows has a `row_created_on` in August or September 2026; the snapshot's rows run back to July 2025. So this is not a partial top-up — the table was re-pushed from scratch, and the re-push is incomplete.

| `row_created_on` | Named | Unnamed |
|---|---:|---:|
| 2026-08 | 1,244 | 168 |
| 2026-09 | 137 | **305** |
| **Total live** | **1,381** | **473** |

The September batch is 69% unnamed, against 12% for August. Overall, 473 of 1,854 live rows (26%) carry no validated species name.

This is consistent with the story migration `022` tells. That migration's header records that three column types silently cost **87 assemblies their LCA rows across batch-12 to batch-20**: `blast_filtered_lca.taxon_id` was `integer` but BLAST returns `;`-joined `staxids`, and the two confidence columns were `real` but HiFi hits produce values like `5.27e-163`. Because the push script had no per-row savepoint, one bad row took the whole sample's upload down. `022` widened the columns — but widening the target does not re-push the data that was already lost.

Separately, migration `024`'s `validated_rank` column is populated on only **12 of 1,854 rows** (7 `genus`, 4 `family`, 1 `genus_downgraded`; 1,842 NULL). The rank-aware validation logic has barely run, so the instrumentation that would let you classify these 473 rows is not yet in place either.

Why this matters:

- The views are now correct, which means they correctly report that roughly a quarter of LCA validations have no species name. Users accustomed to the stale numbers will see coverage appear to drop.
- 87 assemblies are named in `022` as having lost rows. Whether they were re-pushed after the widening is not recorded anywhere.
- `embargo_assignment_view` feeds embargo decisions, and 232 samples just lost their validated name there. That is the correct value, but it is a decision input that changed.

Recommendation:

1. Determine whether the batch-12 to batch-20 LCA data was re-pushed after `022` widened the columns. If not, re-push it — the schema now accepts it.
2. Add the per-row savepoint `022`'s header identifies as the reason one bad row killed a whole sample's upload. Without it, the next type surprise loses data the same way.
3. Investigate the September re-push specifically: 305 of 442 rows unnamed is a different failure rate from August's and suggests a distinct cause.
4. Backfill `validated_rank` so the 473 unnamed rows can be split into "legitimately held" versus "lost to the type bug".
5. Tell the users of `summary` and `embargo_assignment_view` that coverage numbers changed on 2026-10-02 and why — the new numbers are right, but they are lower.

### Finding 16: `mitogenome_submission_view`'s ENA join was keyed one grain too coarse

Severity: Medium  
Theme: Correctness, reporting  
Status: **new — RESOLVED 2026-10-02 by migrations `028_mitogenome_submission_view_annotation_key.sql` and `029_mitogenome_submission_view_join_base_table.sql`**

Migration `014` re-keyed `ena_validation_attempts` from `assembly_prefix` to `full_seqid` plus a separate `annotation` column, because what the pipeline validates is a flatfile built from one *annotation* of one assembly. `mitogenome_submission_view` was never updated and kept joining on the 4-field assembly prefix `(og_id, tech, seq_date, code)` — one grain coarser than either table actually keys on.

`full_seqid` is exactly `og_id.tech.seq_date.code.annotation`, confirmed on all 1,185 rows, and `mitogenome_data` has no `full_seqid` column — so "key on full_seqid" is implemented as component-wise equality including `annotation`. That is equivalent to matching `full_seqid`, and unlike string concatenation it can use an index. `full_seqid` already contains the annotation, so this is one condition rather than two.

Two problems, both fixed:

**1. Wrong rows matched.** Matched ENA rows went from 1,182 to 1,180. The two affected samples are reseed cases and show the defect clearly:

| `mitogenome_data` | annotation | stats |
|---|---|---|
| `OG2951.ilmn.260909.getorg1770` | NULL | 1 scaffold(s) |
| `OG2951.ilmn.260909.getorg1770reseed` | `mitos2110` | circular genome |

| `ena_validation_attempts` | webin / table2asn |
|---|---|
| `OG2951.ilmn.260909.getorg1770.mitos2110` | NOT_RUN / FAIL_TABLE2ASN |
| `OG2951.ilmn.260909.getorg1770reseed.mitos2110` | NOT_RUN / FAIL_TABLE2ASN |

The first assembly came out as a single linear scaffold and was never annotated, which is why it was reseeded. Because `code` differs between the two, the 4-field join paired each `mitogenome_data` row with its own ENA row — including pairing the un-annotated row with a verdict for an annotation it does not have. The 5-field join keeps the reseed pairing and drops the other. No genuine validation result was lost: the reseed rows keep their real verdicts (OG2951 NOT_RUN/FAIL, OG3000 PASS/PASS). `OG3000` has the same shape.

**2. ~~Latent row duplication.~~ Retracted — see below.** Migration `028` additionally routed the join through `ena_validation_latest`, on the grounds that `ena_validation_attempts_key_idx` being UNIQUE on `(full_seqid, ena_study, validation_attempt)` meant the base table could hold several rows per sequence identity. **That reasoning was wrong, and migration `029_mitogenome_submission_view_join_base_table.sql` reverted it to a direct join on the base table.**

A rerun overwrites its row; it does not append one. This is the documented design — `002_ena_validation_attempts_single_row_per_attempt.sql` exists specifically to collapse the table to one row per key "so pipeline reruns overwrite the previous attempt instead of appending a new history row every time", and added `attempt_count` to carry the rerun tally inside the surviving row. `015`'s header states the writer's side: `push_ena_validation_results.py` upserts "with `DO UPDATE SET` across every non-key column".

The data confirms it — 739 of 1,185 rows have `attempt_count` above 1:

| `attempt_count` | Rows |
|---:|---:|
| 1 | 446 |
| 2 | 385 |
| 3 | 321 |
| 4 | 28 |
| 5 | 2 |
| 6 | 3 |

Had reruns appended, the table would hold several thousand rows with `attempt_count` of 1 throughout. The other two key columns do not vary either: `ena_study` is `PRJEB110568`, `validation_attempt` is `initial`, and `validation_mode` is `pipeline` on all 1,185 rows — so in practice the unique key is `full_seqid` alone and the 5-field identity join already selects exactly one row.

The `DISTINCT ON` was therefore not merely redundant but a worse failure mode than the one it guarded against. Fan-out is *visible* — duplicate rows in a report get noticed. `DISTINCT ON (full_seqid)` silently picks one row by `recorded_at` and discards the rest, and discards on `full_seqid` while ignoring the `ena_study` and `validation_attempt` that would have been the only reason a second row existed.

It also cost a Sort + Unique over all 1,185 rows on every execution. Removing it drops the plan from 486.17 to 412.50, leaving two hash joins over sequential scans. Output is unchanged: verified bidirectionally, 0 differing rows across all 2,301.

Notably, `ena_validation_attempts_identity_idx` is already on all five columns `(og_id, tech, seq_date, code, annotation)` — the index was built for the corrected grain. Only the view had not caught up.

Row count unchanged at 2,301; `readonly` grant preserved; one row per sequence identity. Rollback: `sql/revert/029_…_revert.sql` then `sql/revert/028_…_revert.sql`, in that order.

**Follow-up this exposed, not fixed here.** ENA holds a validation row for `getorg1770.mitos2110` on both samples — an assembly/annotation pair `mitogenome_data` has no annotated row for. The coarse join was masking that inconsistency. Most likely the un-annotated assemblies were validated before the reseed superseded them and their ENA rows were never retired. Worth a sweep for other cases: `ena_validation_attempts` rows whose 5-field identity has no counterpart in `mitogenome_data`.

## 7. Table-by-Table Review Notes

### `sample`

Role: Core biological sample table. 2,675 → 3,294 rows.

Strengths: still the hub for `og_id`; PK present; `og_num` generated.

Issues (all carried over): species links unconstrained and degrading (892 `nominal_species_id` values absent from `species`, up from 645); nine fully empty workflow/sequencing columns after 619 new rows; physical measurement fields still text; status fields degrading (`ilrna_status` 10 → 44 distinct values).

Recommendation: unchanged — reduce derived workflow/status fields, push status to child tables or views. Add import-time species validation, which is the one thing actively getting worse.

### `tissue`, `dna_extraction`, `rna_extraction`

Grew 34%, 16%, 3%. FKs intact. `og_id` and `tissue_id` still unindexed on all three — and `summary` scans all three per sample. These are the top three index candidates.

### Library tables

`illumina_library` +21%, `rna_library_ilmn` +44%, `pacbio_library` +3%, `rna_library_kinx` +6%. `ont_library` and `hic_library` took no new rows at all in three months, which is worth confirming as expected rather than as a broken import.

`rna_library_kinx` still has no FK to `rna_extraction`. All eight `status_overwrite` columns still empty. No FK column on any library table is indexed.

### `sequencing`

4,212 → 4,765. All 553 new rows correctly link to exactly one library, which is a good sign for the import path. The 40 zero-link and 40 blank-technology rows are unchanged and therefore historical. `PacBio Kinnex` still has no FK target.

### `species`, `master_species`, `master_species_genome`

See Finding 2. `master_species_genome` is well-built but was built on the table revision 1 recommended retiring, raising the cost of that retirement.

### `species_ncbi_assembly` and `ncbi_genome_assemblies`

`species_ncbi_assembly` is still 0 rows after three months. `ncbi_genome_assemblies` (1,772 rows) now holds NCBI assembly metadata with a different column set and no FK to `species`.

This answers revision 1's open question 6 and replaces it with a new one: two NCBI assembly tables exist, one empty with a species FK and a chosen-assembly partial unique index, one populated with neither. `v_genome_size_comparison` should be checked for which it reads.

Recommendation: consolidate. Keep the populated one, port the `is_chosen` partial unique index and the `species` FK onto it, and drop the empty one.

### `draft_genomes`, `ref_genomes`, upload tables

`draft_genomes` 1,448 → 1,542 with **0 orphan `og_id`** — ready for an FK today. `ref_genomes` 1,835 → 1,994 with 4 orphans. `ref_genomes_sra_uploads` doubled (153 → 304) and its `og_id` is still unindexed.

`draft_genomes` is still very wide and still mixes read metrics, assembly metrics, BUSCO metrics, AWS paths, SRA metadata, and review fields. Unchanged recommendation to split, unchanged low priority.

### Mitogenome and LCA tables

The most-improved area of the database.

- `mitogenome_data` was rebuilt twice (`016`, `018`) to restore `og_num` as a generated column at position 1, with a bidirectional `EXCEPT` verification before the table swap in `020`'s equivalent rebuild. 13 typed depth columns added by `003`; `depth_method` is populated on 2,296 of 2,301 rows (1,907 `remap_full_v1`, 389 `not_measured`, 5 NULL).
- `lca` and `lca_raw_results` are content-addressed via a `BEFORE INSERT OR UPDATE` trigger on `content_hash`, with unique constraints the push scripts name as `ON CONFLICT` targets. `lca` shrank 6,384 → 4,784 because re-runs no longer append near-duplicates.
- `blast_filtered_lca` was rebuilt, orphans eliminated, and `taxon_id` widened to text in `022` after `;`-joined `staxids` cost 87 assemblies their LCA rows. The two confidence columns went `real` → `double precision` for the same reason, with a full re-hash so `content_hash` stayed consistent under the new types.
- `lca_validation` gained `validated_rank` (`024`), recording whether a sample's species ID was confirmed at species, genus, downgraded genus, or family level.
- `026`'s annotation-integrity columns are populated on only 74 of 2,301 rows (39 `ok`, 19 `advisory`, 16 `broken`, 2,227 NULL) — expected, since the migration header states NULL means "produced before this migration" and rows refresh on their next pipeline run.

Remaining issues: `lca` and `lca_raw_results` have no declared PK (Finding 13); `lca_old` is still present, still unreviewed, and now FK'd to a snapshot table (Finding 12); none of these tables has an FK to `sample` despite 0 orphans.

### ENA submission tables

Well modelled. `ena_validation_attempts` (1,185 rows, 1,149 `submission_ready`, webin status 1,149 PASS / 22 NOT_RUN / 12 FAIL_WEBIN / 2 NOT_REQUESTED) is keyed on `full_seqid` + annotation after `014`, with `og_num` generated at column 2 after `020`.

`ena_submissions` (539 rows, all `ACCESSION_ASSIGNED`) is the downstream-owned ledger. Column population:

| Column | Populated |
|---|---:|
| `ena_study_accession` | 539 / 539 |
| `ena_analysis_accession` | 539 / 539 |
| `biosample_accession` | 539 / 539 |
| `receipt_path`, `receipt_sha256`, `locus_tag_prefix` | 539 / 539 |
| `ena_assembly_accession` | 537 / 539 |
| `ena_sample_accession` | 367 / 539 |
| `ena_sequence_accession` | **0 / 539** |

`ena_sequence_accession` empty on every row is probably correct — genome-context submissions return analysis/assembly accessions, not sequence ones — but it should be documented as such, or dropped, rather than left looking like a gap. `ena_sample_accession` missing on 172 of 539 is the one worth asking about.

`ena_specimen_accessions` (2,848 rows) is a parallel specimen registry with no FK to `sample`, though all 2,848 `og_id` values match. `007`'s header explains the BioSample problem well: OceanOmics registers at NCBI (SAMN), ENA's Webin service only resolves samples registered through Webin, and the archives mint from independent ranges so SAMN cannot be relabelled as SAMEA. That constraint is real and the table handles it correctly — but the table should still FK to `sample`.

`ena_related_assemblies` is empty. `ena_locus_registry_archive` and `ena_candidate_loci_archive` are both empty, meaning `010` archived nothing — no locus tags had been allocated before allocation moved downstream. Both have good object comments explaining they are frozen history and must not be treated as current tag assignments. Consider dropping them: an empty archive with a comment saying "historical reference only" is more confusing than no table.

### Data delivery tables

Eight new tables, ten foreign keys, `ON DELETE CASCADE` down the tree, composite unique constraints, `jsonb` for link sets and repository revisions, `timestamptz` throughout, and separate lifecycle timestamps (`approved_at`, `packaged_at`, `uploaded_at`, `links_generated_at`, `email_accepted_at`) rather than one overloaded status column.

This is the best-modelled subsystem in the database. It is also entirely undocumented, in no migration, in no baseline, and in no data dictionary — and it is barely populated (one delivery, three components, 110 items, 10 artifacts; the email and link-set tables are empty, as is `project_delivery_contact`), so it appears to be mid-rollout.

Recommendation: capture it in a migration file and the data dictionary now, while whoever built it still remembers why. `data_package_item.og_id` should FK to `sample`.

### QC and raw data tables

`raw_data` took no new rows (still 8,010, still 30 blank `og_id`). `raw_qc` +12 rows, 3 orphans. `hifi_reads_qc` and `hic_reads_qc` grew and are both **0 orphan** — FK-ready today. `rna_qc_kinnex` unchanged at 96 rows, still no PK, no unique constraint, no FK.

Revision 1's question — whether QC records belong to samples, libraries, runs, lanes, or files — is still open and still blocking.

## 8. Recommended Target Principles

Unchanged, with two additions:

1. `sample` is the authoritative biological sample entity.
2. `species` is the authoritative taxonomy/species entity.
3. Tissue, extraction, library, sequencing, QC, and analysis records each have explicit parent links.
4. Status values are constrained and documented.
5. Derived status fields live in views, not duplicated free-text columns.
6. Dates and numbers use date/numeric types — except where a date-like string is a documented identifier component (`seq_date`).
7. Import/staging data is separated from curated production tables.
8. Views are versioned and tested when used by APIs.
9. Schema changes are managed through migrations — **one** migration system, with a ledger, and nothing applied outside it.
10. Deprecated columns and tables are documented before removal.
11. **Reporting views read live tables.** Snapshot-reading views are named as such and are never the default reporting surface.

## 9. Revised Phased Plan

Phases 0 and 1 were started and not finished. Phases 2–4 are now cheaper than estimated in July, because the August LCA rebuild did most of Phase 2's cleanup as a side effect.

### Phase A: Stop the bleeding (days, not weeks)

These four items are small, independently deployable, and currently causing wrong answers or measurable slowness.

1. ~~Repoint `summary`, `embargo_assignment_view`, and `mitogenome_submission_view` at the live tables (Finding 11).~~ **Done 2026-10-02, migration `027`.**
2. ~~Deploy the already-written index migration with `CREATE INDEX CONCURRENTLY` (Finding 4).~~ **Done 2026-10-02, migration `030`** — ported out of Sqitch, extended to all 24 columns. `summary` fell from 7.6 s to 2.0 s.
3. ~~`chmod 600 /home/tyler/.env.db` (Finding 14).~~ **Done 2026-10-02.** The remaining Finding 14 items (`.pgpass`, a non-superuser pipeline role, credentials in `create_database.py`) are not done.
4. ~~Ledger the `026` migration and add transaction control to it (Finding 10).~~ **Done 2026-10-02.** The rest of Finding 10 — one migration system, a drift check — is not done.

Phase A is complete.

### Phase B: Re-establish one source of truth

1. Choose one migration tool; document the decision and retire the others.
2. Re-baseline `schema/` from the live database.
3. Write catch-up migrations for the 22 unmanaged tables and 6 unmanaged views.
4. Add a drift check (live inventory vs baseline) to CI or cron.
5. Remove credentials from `create_database.py`.

### Phase C: Add the constraints the data already satisfies

1. Add the seven zero-orphan FKs from Finding 3, with pipeline owners' sign-off.
2. Add PKs to `ncbi_genome_assemblies` and `rna_qc_kinnex`; add `rna_qc_kinnex` → `rna_library_kinx` FK (Finding 13).
3. Add `rna_library_kinx.rna_id` → `rna_extraction` FK (still outstanding from revision 1).
4. Add the `NOT VALID` "exactly one library link" check on `sequencing` (Finding 5).
5. Fix the 7 remaining orphans in `raw_qc` and `ref_genomes`, then FK those too.

### Phase D: Fix `summary`

1. Strip `status_overwrite` references (dead logic, Finding 6).
2. Rebuild with pre-aggregated CTEs, or materialise and refresh after the nightly import.
3. Compare output against the current view before and after.

### Phase E: Species consolidation

1. Make `species` canonical; redefine `master_species` as a view; re-point `master_species_genome`'s FK.
2. Add import-time validation on `sample.nominal_species_id`.
3. Classify the 892 invalid values using `lca_validation.validated_rank`.
4. Consolidate `species_ncbi_assembly` and `ncbi_genome_assemblies`.

### Phase F: Resolve the snapshots

1. Decide `lca_old`'s fate (blocking — it FKs to a snapshot).
2. Move the five `SS260818` tables to an `archive` schema, or drop them.
3. Drop the three snapshot-specific views if the snapshots go.
4. Reclaim the clean index names on `mitogenome_data`.

### Phase G: Documentation

1. Extract the 26 migration headers into `docs/data_dictionary.md`.
2. Document the `data_package_*` subsystem.
3. Document `seq_date` as an identifier component, not a date.
4. Comment the remaining active tables.

### Phase H: Status normalisation, then sequencing/library redesign

As revision 1's Phases 5 and 6. `sample.ilrna_status` first — it is degrading fastest. The `v2` scaffold in `sqitch.plan` is the starting point for the library redesign if that plan is kept.

## 10. Revised Priority Backlog

### Do now

All four are done. The follow-ons each item left behind are listed with their parent below.

1. ~~Repoint the three snapshot-reading views at live tables.~~ **Done, migration `027`.** Follow up on Finding 15, which it exposed.
2. ~~Deploy the index migration.~~ **Done, migration `030`** — all 24 columns; `summary` 7.6 s → 2.0 s.
3. ~~`chmod 600` the credentials file.~~ **Done.** Now rotate the `postgres` password: it was world-readable on the host for about two months, and a `chmod` does not undo that.
4. ~~Ledger migration `026`.~~ **Done.** Write an apply/ledger script so the gap cannot reopen.

### Highest priority

1. Rotate the `postgres` password (Finding 14) — the only item here with a live exposure window behind it. The plumbing is now in place: credentials live in one file (`~/postgresql_details/oceanomics.cfg`) and `OceanOmics-Database/ROTATION.md` is the runbook.
2. ~~Add an apply/ledger script and a drift check.~~ **Done 2026-10-02** — `bin/apply_migrations.py` and `bin/check_drift.py`; `schema/` re-baselined. **Still open: choose one migration system and write the decision down.** The drift check quantifies it — 58 of 70 live objects have no migration behind them.
3. Add the seven zero-orphan FKs to `sample` — unblocked now that the child-side indexes exist.
4. Add import-time species validation on `sample.nominal_species_id`.
5. Capture the `data_package_*` subsystem in a migration and the data dictionary.
6. Strip dead `status_overwrite` logic from `summary` and rebuild or materialise it — less acute after `030`, but 2.0 s is still structural.

### Medium priority

1. Resolve `lca_old`, then the `SS260818` snapshots.
2. Consolidate the three species tables.
3. Consolidate the two NCBI assembly tables.
4. Normalise `sample.ilrna_status`, then the other status fields.
5. Add missing PKs and the `rna_qc_kinnex` / `rna_library_kinx` FKs.
6. Refactor `goat_species_v1` after adding API smoke tests.
7. Extract migration headers into the data dictionary.

### Lower priority

1. Convert legacy text date and numeric columns (not `seq_date`).
2. Deprecate and remove the 16 confirmed-empty columns.
3. Drop the two empty ENA archive tables.
4. Split `draft_genomes`.
5. Unified library model / `v2` cutover.
6. Full database comments.

## 11. Open Questions

Resolved since revision 1:

| # | Question | Answer |
|---|---|---|
| 2 | Are `OG672L-1`, `OG90_bc2008`, `OG750_PD` valid? | Artefacts. The `blast_filtered_lca` rebuild did not reproduce any of them. 7 remain in `raw_qc` / `ref_genomes`. |
| 4 | Should `status_overwrite` exist if empty but referenced by `summary`? | No. Still empty across all eight tables after three more months. Deprecate and strip from `summary`. |
| 6 | Should `species_ncbi_assembly` be populated or marked inactive? | Superseded. `ncbi_genome_assemblies` holds 1,772 rows. Consolidate. |

Still open:

1. Which table is the authoritative species source — and does `master_species_genome` change the answer?
2. Are sample-level workflow status columns user-entered, imported, or derived?
3. Is `lca_old` still used by any report or user? (Now blocking the snapshot cleanup.)
4. Are QC records conceptually linked to samples, libraries, sequencing runs, lanes, or files?
5. Does each `sequencing` row represent a run, a library on a run, a lane, or an output file?
6. What are the required public contracts for GoaT API output?
7. Which downstream users or scripts query the database directly outside these repos?

New:

8. Which migration system is the intended one — `sql/` + `schema_migrations`, or Sqitch? Is the `v2` redesign still the plan, or superseded?
9. Who owns the `data_package_*` subsystem, and where does its code live?
10. Were the three snapshot-reading views intended to read snapshots, or is that a leftover from the August rebuild?
11. Should the `SS260818` tables be archived, dropped, or retained as a rollback point?
12. Is `ena_sequence_accession` expected to stay empty, and why is `ena_sample_accession` missing on 172 of 539 submissions?
13. `ont_library` and `hic_library` took zero new rows in three months, and `raw_data` took zero — expected, or a stalled import?
14. Should `ena_specimen_accessions` remain a separate specimen registry, or become a view over `sample`?

## 12. Risk Assessment

### What the last three months demonstrated

Both of revision 1's risk scenarios partially materialised, in different areas.

*Drift continued where no process was adopted.* 22 tables and 6 views entered production with no migration. The baseline went stale within weeks of being created. Three production views silently kept reading frozen data, and nobody noticed for six weeks.

*Performance degraded as predicted.* `summary` went from "a projected risk" to 7.6 seconds, on a 23% row increase. The index migration that would have mitigated it was written in July and is still undeployed.

*But the mitogenome pipeline shows the counterfactual.* Where migrations, a ledger, idempotent guards, verified rebuilds, and documented rationale were adopted, the result is the cleanest part of the schema: zero orphans, correct types, real constraints, deliberate indexes, and a readable history. Migration `019` is the strongest evidence — a silent data corruption introduced by a replayed migration was found, explained, and repaired in a migration of its own, with the detection gap named. That only happens if there is a written record to reason against.

The lesson is not "be more careful". It is that the practice already exists inside this project and has been proven to work; it just has not been applied to the lab-side tables or to the data-delivery subsystem.

### If no action is taken

- Divergence between the three snapshot-reading views and the live tables grows with every pipeline run (61 / 39 today).
- `summary` becomes unusable somewhere between 4,000 and 5,000 samples.
- `sample.nominal_species_id` invalid values grow at roughly 250 per 600 samples.
- `sample.ilrna_status` continues to accumulate distinct values (10 → 44 in three months).
- The baseline falls further behind, making the eventual re-baseline larger.

### Safest approach

Unchanged in principle, re-ordered in practice: the August rebuild already did much of the data cleanup, so the sequence is now

1. Fix what is wrong today (views, indexes, credentials, ledger).
2. Re-establish one source of truth.
3. Add constraints the data already satisfies.
4. Then document, normalise, and refactor.

## 13. Proposed Success Criteria

Unchanged, with four additions:

- The schema can be recreated from source-controlled migrations.
- Every active table has an owner and documented purpose.
- Every active column is documented or intentionally self-evident.
- There is one canonical species source.
- Sample species links are valid and constrained.
- Core child tables have indexed FK columns.
- Major `og_id`-based tables either have FKs or documented reasons not to.
- Workflow statuses use canonical values.
- Heavy views have acceptable query plans.
- Deprecated tables/columns are clearly marked and eventually removed.
- **There is exactly one migration system, and the live inventory matches the baseline.**
- **No reporting view reads a frozen snapshot unless its name says so.**
- **`summary` returns in under one second.**
- **Database credentials are not readable by other users on the host, and pipelines do not connect as superuser.**

## Appendix A: Key Evidence Summary

### Object counts

| Object type | Jul | Oct |
|---|---:|---:|
| Base tables | 31 | 53 |
| Views | 11 | 17 |
| Columns | 934 | 1,502 |
| Tables/views with comments | 0 / 42 | 3 / 70 |
| Columns with comments | 12 / 934 | 60 / 1,502 |
| Non-system schemas | 1 | 1 |
| Foreign keys | — | 34 |
| Tables with no PK | — | 9 |
| Tables in no repository artifact | — | 22 |

### Migration state

| System | Changes | Applied |
|---|---:|---:|
| `sql/` + `schema_migrations` | 26 | 26 applied, 25 ledgered |
| `genomes_db_review/sqitch.plan` | 8 | 0 |
| Direct DDL | 22 tables, 6 views | 22 / 6 |

### Orphan and blank `og_id`

| Table | Blank | Orphan |
|---|---:|---:|
| `blast_filtered_lca` | 0 | 0 (was 334) |
| `raw_data` | 30 | 0 |
| `ref_genomes` | 0 | 4 |
| `raw_qc` | 0 | 3 |
| `sequencing` | 2 | 0 |
| `dna_extraction` | 1 | 0 |
| `draft_genomes`, `mitogenome_data`, `hifi_reads_qc`, `hic_reads_qc`, `ena_specimen_accessions`, `ena_validation_attempts` | 0 | 0 |

### Snapshot divergence (Finding 11)

| Metric | Count |
|---|---:|
| `lca_validation` distinct `og_id`, snapshot | 1,474 |
| `lca_validation` distinct `og_id`, live | 1,496 |
| Live-only `og_id` (invisible to `summary` / `embargo_assignment_view` / `mitogenome_submission_view`) | 61 |
| Snapshot-only `og_id` (stale in those views) | 39 |
| `mitogenome_data` distinct `og_id`, snapshot | 1,483 |
| `mitogenome_data` distinct `og_id`, live | 1,579 |

### View performance

| View | Planner cost | Actual |
|---|---:|---|
| `summary` (3,294 rows) | 3,913,657 | 7,578 ms |
| `goat_species_v1` (LIMIT 100) | 168,812 | 275 ms |
| `goat_species_v1` (full, estimated) | 32,362,040 | not measured |

### Sequencing link distribution

| Linked library columns per row | Jul | Oct |
|---:|---:|---:|
| 0 | 40 | 40 |
| 1 | 4,172 | 4,725 |

### Confirmed-empty columns after three more months

All 16 columns listed in Finding 6 are at 0 rows filled, across 3,294 samples and 6,426 library/extraction rows.

### Pipeline rollout state

| Metric | Value |
|---|---|
| `mitogenome_data.depth_method` populated | 2,296 / 2,301 (1,907 `remap_full_v1`, 389 `not_measured`) |
| `mitogenome_data.annotation_integrity_status` populated | 74 / 2,301 (39 ok, 19 advisory, 16 broken) |
| `ena_validation_attempts.submission_ready` | 1,149 / 1,185 |
| `ena_validation_attempts.webin_status` | 1,149 PASS, 22 NOT_RUN, 12 FAIL_WEBIN, 2 NOT_REQUESTED |
| `ena_submissions` | 539, all `ACCESSION_ASSIGNED` |

## Appendix B: Suggested Review Workshops

### Workshop 1: Migration governance

Decide which migration system survives, who may apply DDL, and how drift is detected. Output: a one-page rule in `docs/database_change_checklist.md` and a drift-check query in CI.

### Workshop 2: Snapshots and `lca_old`

Decide whether `SS260818` is an archive or a rollback point, and resolve `lca_old`. Output: a drop/archive plan and the three repointed views.

### Workshop 3: Species and sample identity

As revision 1, now with `master_species_genome` and `ena_specimen_accessions` in scope, and the 892 invalid `nominal_species_id` values classified by `validated_rank`.

### Workshop 4: Data delivery subsystem handover

Capture the eight `data_package_*` tables in a migration and the data dictionary while the design is still fresh.

## Appendix C: Revision History

| Revision | Date | Scope |
|---|---|---|
| 1 | 2026-07-07 | Initial review. 31 tables, 11 views. 9 findings. |
| 2 | 2026-10-02 | Re-review against the live database after the mitogenome/ENA migrations (`sql/` 001–026), the data-delivery subsystem, and the August LCA rebuild. 53 tables, 17 views. 15 findings: 1 much improved, 1 improved, 3 unchanged, 1 mixed, 3 worse, 6 new. |
| 2.1 | 2026-10-02 | Applied migration `027_reporting_views_live_tables.sql`, resolving Finding 11. Added Finding 15, which the repoint exposed. |
| 2.2 | 2026-10-02 | Applied migration `028_mitogenome_submission_view_annotation_key.sql`, resolving Finding 16. Re-verified Finding 4: the index migration is confirmed **not** deployed. |
| 2.3 | 2026-10-02 | Applied `029_mitogenome_submission_view_join_base_table.sql`, retracting `028`'s incorrect latent-duplication rationale. `ena_validation_attempts` is upsert-overwrite by design (`attempt_count` reaches 6); the `DISTINCT ON` guard was unnecessary and hid rows rather than revealing them. Output unchanged. |
| 2.4 | 2026-10-02 | Moved the 29 deployed numbered migrations and their three revert scripts from `/home/tyler/sql` into `sql/` in this repo, byte-identical so the `schema_migrations` SHA-256 ledger stays valid, and deleted the untracked original. Path references in this document updated accordingly; no finding, count, or conclusion changed. The migration-tool question (open question 8) remains open. |
| 2.5 | 2026-10-02 | Completed Phase A. Applied `030_core_lookup_indexes.sql` (Finding 4) — the July Sqitch change `add_core_lookup_indexes`, ported into the numbered-SQL convention rather than deployed through Sqitch, and extended from 19 to all 24 index candidates; 24 indexes created, 0 invalid, `summary` 7.6 s → 2.0 s. Added `BEGIN`/`COMMIT` to `026`, replayed it as a no-op, and wrote its missing ledger row (Finding 10). `chmod 600 /home/tyler/.env.db` (Finding 14). Findings 4, 10 and 14 updated with resolution notes; the open remainders — password rotation, one migration system, a drift check, an apply/ledger script — are called out in each. |
| 2.6 | 2026-10-02 | Closed the Finding 10 mechanism and the Finding 14 plumbing. Added `bin/apply_migrations.py` (applies and ledgers in one step; aborts on hash drift; auto-detects `CONCURRENTLY`; guards the `005`/`019` replay hazard) and `bin/check_drift.py` (object inventory vs `schema/object_inventory.tsv`, plus a source-coverage report). Re-baselined `schema/`, three months stale. Separately, in `OceanOmics-Database`: the password was removed from the two live scripts into `~/postgresql_details/oceanomics.cfg` via a new `db_config.py`, `SS/` was documented as the superseded directory, and `ROTATION.md` was written. **The password value is unchanged** — this is plumbing, so rotation is now a one-line edit. |

The previous revision is preserved at `/tmp/database_review.prev.md` at the time of writing; the authoritative history is in git.
