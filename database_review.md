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
| 1 | Repository is not the schema source of truth | **Worse at review; much improved 2026-10-05.** One declared migration system, re-baselined, drift checked daily. Coverage 22 of 64 and routed. |
| 2 | Species data has two competing authorities | **Worse.** Now three species tables and a fourth `og_id` authority; sample species drift grew. |
| 3 | Logical relationships not enforced | **Much improved.** `blast_filtered_lca` orphans 334 → 0; FKs are now actually addable. |
| 4 | FK columns not indexed | **Unchanged.** All 24 candidates still missing. |
| 5 | Sequencing modelled with polymorphic nullable columns | **Unchanged.** |
| 6 | Columns unused or nearly unused | **Unchanged.** All 16 named columns still fully empty. |
| 7 | Dates/numbers/statuses stored as text | **Mixed.** New tables are properly typed; legacy unchanged; status cardinality worsened. |
| 8 | Reporting views hide logic and carry performance risk | **Worse, and now measured.** `summary` takes 7.6 s. |
| 9 | Documentation coverage minimal | **Improved.** 0 → 3 object comments, 12 → 60 column comments. |
| 10 | — | **New at review; resolved 2026-10-05.** One system declared, ledger gap closed, drift check scheduled. |
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

- There are now **three** migration systems: `sql/` + `schema_migrations` (deployed), `genomes_db_review/sqitch.plan` (declared, never deployed), and direct DDL against production (eight `data_package_*` tables, two reference tables, five snapshot tables, six views). The schema baseline in `schema/current_schema.sql` describes 31 tables; the database has 53. **Resolved 2026-10-05:** one system, declared in `docs/migration_system_decision.md`; Sqitch retired and deleted. Direct DDL has not stopped — see Finding 10's final note and open question 16.
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
| `lca_old` | 2,895 | 2,895 | Legacy. FK'd to the `SS260818` snapshot. **Dropped 2026-10-05, migration `032`** — superseded by a full LCA re-run; archived to CSV. |

ENA submission pipeline (all new):

| Table | Rows | Notes |
|---|---:|---|
| `ena_validation_attempts` | 1,185 | Keyed on `full_seqid` + annotation. 1,149 `submission_ready`. |
| `ena_submissions` | 539 | Downstream-owned ledger. All 539 `ACCESSION_ASSIGNED`. |
| `ena_specimen_accessions` | 2,848 | Specimen registry. No FK to `sample`. |
| `ena_related_assemblies` | 0 | Empty. |
| `ena_locus_registry_archive` | 0 | Frozen archive from `010`. Empty — nothing had been allocated. |
| `ena_candidate_loci_archive` | 0 | Frozen archive from `010`. Empty. |

Data delivery subsystem (all new, no migration) — **all eight dropped 2026-10-05, migration `031`.** The work was abandoned and the 124 rows were stale. Structure is recoverable from `sql/revert/031_...`; the rows are only in the nightly S3 base backup:

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

Severity: High → **Medium** (2026-10-05)  
Theme: Maintainability, safety  
Status since revision 1: **worse at review time; substantially improved 2026-10-05** — one declared migration system, daily drift detection, coverage 12 → 22 of 64. See the resolution note at the end of this finding.

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

**Resolution — 2026-10-05. Partly resolved; the severity of the remaining part is lower.**

1. ~~Pick one tool.~~ **Done** — `docs/migration_system_decision.md`. `sql/` + `schema_migrations` is canonical, Sqitch is retired, its project files are deleted, and the three READMEs that used to contradict each other now agree. There is one migration system.
2. ~~Re-baseline.~~ **Done 2026-10-02.**
3. **Partly done, and deliberately so.** 22 of 64 objects are now created by a migration, up from 12. The recommendation as written — "even if they only assert what already exists" — was revised in practice: a migration describing the status quo carries no rationale, because there is none to record, and is superseded within weeks by the migration that actually reworks the object. So the work was routed instead: ten objects nothing else touches were captured in `000`, `033` and `034`, and the other 39 ship with the change that reworks them, in Phases C, E, F and the `v2` cutover. See Phase B.3.
4. ~~Deploy the index change.~~ **Done 2026-10-02** as `030`.

What is left of this finding is not "no process" but "process adopted, coverage incomplete, and one unenforced boundary":

- **Coverage.** 42 objects are still not described by a migration; a rebuild from `sql/` alone stops at `003`. Each is routed, with 17 of them waiting on open question 7.
- **Enforcement.** The rule says DDL reaches this database only through `sql/`, and nothing enforces it — every connection is the `postgres` superuser. Three tables (`og_workflow_*`) arrived by direct DDL between the re-baseline and the scheduling of the drift check, which is the clearest possible demonstration: the check now *detects* this within a day, but nothing *prevents* it. Prevention needs the non-superuser pipeline role from Finding 14, which is still outstanding.

Detection, at least, is no longer manual: `bin/drift_cron.sh` runs daily.

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

- Make `species` canonical for everything this project owns.
- ~~Redefine `master_species` as a view over `species`, and re-point `master_species_genome`'s FK at `species`.~~ **Out of scope as of 2026-10-05.** `master_species` and `master_species_genome` are a colleague's separate piece of work. The analysis above still stands — three competing authorities is still the problem, and these two are still two of them — but the fix for that half is not this project's to implement. Coordinate rather than change them, and do not pick this recommendation up from here: Phase E.1 has been reduced to match.
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

The `v2` redesign addresses this with a library identity registry replacing the five polymorphic columns. It is written and undeployed; since 2026-10-06 (Phase V.3) its DDL is numbered migrations `sql/035`–`040`.

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
Status: **resolved 2026-10-05.** Ledger gap and drift check closed 2026-10-02; the multiple-systems problem closed 2026-10-05 with `docs/migration_system_decision.md`. See the final resolution note at the end. Direct DDL continues to reach the database — detection now catches it, prevention still depends on Finding 14.

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

**Final resolution — 2026-10-05.** Recommendation 2 is done. `docs/migration_system_decision.md` declares `sql/` + `schema_migrations` canonical and retires Sqitch as a tool; `sqitch.conf` and `sqitch.plan` are deleted, so there is no longer a runnable second system. The decision rule lives in `docs/database_change_checklist.md` under "Migration Governance", as recommendation 2 asked. All three recommendations are now closed and this finding is resolved.

Two things the resolution does **not** cover, tracked elsewhere so they are not lost with the finding:

- **The `v2` go/no-go**, deliberately unbundled from the tool decision and still open (question 8). The 17 objects waiting on it are waiting on question 7, not on the tool.
- **Coverage.** The report now reads **22 of 64 objects created by a migration**, up from 12 of 61 and 12 of 70 before that. 39 remain dump-only and routed; 3 are the unclaimed `og_workflow_*` tables.

And one thing it exposes. Scheduling the drift check immediately found three tables — `og_workflow_recommendation`, `og_workflow_assignment_log`, `og_workflow_notification` — created by direct DDL after the 2026-10-02 re-baseline, in neither `sql/` nor the baseline. That is this finding's third system, "direct DDL", still operating three days after the mechanism to catch it was built. The check caught it within a day of being scheduled, which is the point; but **detection is not prevention**, and prevention needs the non-superuser pipeline role from Finding 14. Every connection to this database is still `postgres`. Recorded as open question 16, and the drift check is deliberately left failing until someone claims them.

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
- ~~`lca_old`'s FK to the snapshot is the thing that makes a clean drop impossible. Resolve `lca_old` first.~~ **Resolved 2026-10-05, migration `032`.** `lca_old` was archived to CSV and dropped; its `fk_mitogenome` went with it.

**Status 2026-10-05.** The snapshots are now unblocked. Four FKs pointed into `mitogenome_data_SS260818`; the only one from outside the snapshot set was `lca_old`'s, and it is gone. The remaining three are from `lca_SS260818`, `lca_raw_results_SS260818` and `lca_validation_SS260818` — internal to the group, so the five tables are removable as a unit once the three snapshot views go.

Four of the five are archived as gzipped CSV in `archive/snapshots_SS260818/`, verified to reload `EXCEPT`-identical. **`blast_filtered_lca_SS260818` (192,207 rows) is deliberately not archived** — 4.7 MB gzipped was judged too much to commit — so it must be exported elsewhere before that table is dropped.

Two traps for whoever does the drop, both recorded in the archive manifest:
- `lca_validation_report_view_upd()` is shared with the **live** `lca_validation_report_view`. Drop the snapshot views, keep the function.
- `sql/revert/027_...` reads two of the snapshot tables, so dropping them makes `027` permanently irreversible. Accepted and noted in that file.

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

**Progress as of 2026-10-05: Phases A and B complete; Phase F unblocked.** Phase B's critical-path items are closed — there is one migration system, it is written down, the drift check runs daily, and the ten objects that were genuine Phase B catch-up work are described by migrations. The remaining 39 uncovered objects are routed into Phases C, E, F and the `v2` cutover, where each ships alongside the change that explains it. **The two things now gating the most work are open question 7** (which external clients read this database — it blocks the `v2` cutover and 17 objects with it) **and open question 16** (who owns the three `og_workflow_*` tables that arrived by direct DDL, which keeps the daily drift check red).

### Phase A: Stop the bleeding (days, not weeks)

These four items are small, independently deployable, and currently causing wrong answers or measurable slowness.

1. ~~Repoint `summary`, `embargo_assignment_view`, and `mitogenome_submission_view` at the live tables (Finding 11).~~ **Done 2026-10-02, migration `027`.**
2. ~~Deploy the already-written index migration with `CREATE INDEX CONCURRENTLY` (Finding 4).~~ **Done 2026-10-02, migration `030`** — ported out of Sqitch, extended to all 24 columns. `summary` fell from 7.6 s to 2.0 s.
3. ~~`chmod 600 /home/tyler/.env.db` (Finding 14).~~ **Done 2026-10-02.** Credentials were also centralised into `~/postgresql_details/oceanomics.cfg` (one file, mode `600`, read by a new `OceanOmics-Database/db_config.py`), which supersedes the `.pgpass` recommendation — it serves the same purpose and matches the convention the ref-genomes repo already uses. **Not done: rotating the password**, and the non-superuser pipeline role.
4. ~~Ledger the `026` migration and add transaction control to it (Finding 10).~~ **Done 2026-10-02.** The apply/ledger script and drift check that stop it recurring are also done — see Phase B.

Phase A is complete.

### Phase B: Re-establish one source of truth

**Complete 2026-10-05.** Three items closed on 2026-10-02; the remaining two — the substantive ones — closed on 2026-10-05, together with the scheduling remainder of item 4.

1. ~~**Choose one migration tool; document the decision and retire the others.**~~ **Done 2026-10-05** — `docs/migration_system_decision.md`. `sql/` + `schema_migrations` is canonical; Sqitch is retired as a tool. `sqitch.conf` and `sqitch.plan` are deleted, so there is no longer a runnable second migration system in the repository. The six `create_v2_*` changes moved to `design/v2/` as non-executable reference DDL (`design/v2/README.md` explains what would consume them); the two superseded non-`v2` changes moved to `migrations/legacy/`. `migrations/README.md`, `sql/README.md` and `schema/README.md` were rewritten to agree with each other — the first of those had claimed "Status: Adopted — Sqitch" for two months while `sql/README.md` said the question was open. The working rule is in `docs/database_change_checklist.md` under "Migration Governance", which closes Appendix B's Workshop 1. **The decision covers the tool only.** The `v2` go/no-go was deliberately unbundled from it and remains open — see open question 8.
2. ~~Re-baseline `schema/` from the live database.~~ **Done 2026-10-02** — it was three months stale. `scripts/export_schema_baseline.sh` already existed and was reused unchanged.
3. ~~**Write catch-up migrations for the unmanaged objects.**~~ **Phase B's share done 2026-10-05.** `bin/check_drift.py --coverage` now reports **22 of 64 live objects are created by a migration**, up from 12 of 61; 39 remain baseline-only and 3 are in neither (see item 6). The ten that were genuine Phase B work are captured in `000`, `033` and `034`. The other 39 stay routed to the phases that rework them, per the table below.

   The worklist went 58 → 49 → 39 across three days: nine objects dropped on 2026-10-05 (`031`, `032`), then ten described on 2026-10-05 (`000`, `033`, `034`). Dropping what should not be there remains the cheapest way to shorten it.

   **This is not one job, and most of it does not belong in Phase B.** The guiding principle: *a catch-up migration should be written as the first step of the change that reworks the object, not as a separate job beforehand.* Writing a migration that describes the status quo and then a second that changes it produces two migrations where one would do — and the first carries no rationale, because there is none to record. It describes what is, not why. The 49 route as follows.

   | Group | Count | Where the work belongs |
   |---|---:|---|
   | `SS260818` snapshots — 5 tables + 3 views | 8 | **Phase F.** No migration at all; they are being deleted. |
   | Covered by the `v2` scaffold | 17 | **Phase V, the `v2` cutover.** Direction approved 2026-10-05; gated on open question 7 and on the scaffold re-review (V.1). |
   | QC, raw data, ref/draft genome | 10 | **Phase C**, which already adds their PKs and FKs. |
   | Species / NCBI | 2 | **Phase E**, which already restructures them. |
   | `master_species`, `master_species_genome` | 2 | **Out of scope** — a colleague's separate work. |
   | ~~Nothing else touches these~~ | ~~10~~ | ~~**Stays here.**~~ **Done 2026-10-05** — `000`, `033`, `034`. |
   | `og_workflow_*`, new since the re-baseline | 3 | **Unclaimed.** Open question 16; see item 6. |

   - **Phase C (10):** `rna_qc_kinnex` and `ncbi_genome_assemblies` (C.2 adds their PKs); `raw_qc` and `ref_genomes` (C.5 fixes their 7 orphans then FKs them); `hifi_reads_qc`, `hic_reads_qc`, `raw_data`, `draft_genomes` (C.1, the zero-orphan FKs from Finding 3); plus `ref_genomes_sra_uploads` and `ref_genomes_assembly_uploads`, same `og_id`-bearing family, indexed by `030`.
   - **v2-covered (17) — now Phase V:** the 12 lab tables, the four live LCA tables (`lca`, `lca_raw_results`, `lca_validation`, `blast_filtered_lca`), and `goat_species_v1`. All have DDL in the `v2` migrations — the lab tables in `sql/036_v2_lab_tables.sql`, the LCA tables in `sql/039_v2_lca_tables.sql`, and `goat_species_v1` in `sql/040_v2_summary_view.sql`, which is where it is rebuilt. That DDL was written in August, re-reviewed in V.1 and promoted in V.3 (2026-10-06). Writing catch-up migrations for the `public` versions duplicates it and is wasted now that cutover is the agreed direction.
   - **Phase E (2):** `species` and `species_ncbi_assembly`. `ncbi_genome_assemblies` is touched by both C and E — its CREATE goes with C, the earlier touch, and E reworks it.
   - ~~**Remaining Phase B work (10)**~~ **— done 2026-10-05, in three migrations.**
     - `000_bootstrap_schema_migrations.sql` — the ledger itself. It cannot ledger its own creation, because a file cannot contain its own SHA-256, so it is idempotent and ledgered through the normal path: a no-op replay against the live database, and a one-off `psql -f` on an empty one. `bin/apply_migrations.py` gained a guard that prints exactly that instruction when it finds no ledger, instead of a bare `relation "schema_migrations" does not exist`.
     - `033_catchup_core_views.sql` — the 8 cutover-neutral views, definitions taken verbatim from `pg_get_viewdef(oid, true)` against the live database and emitted in topological order read from `pg_rewrite`/`pg_depend`. That order corrected an assumption: `lca_results_view` reads `lca_pivot_view`, not the reverse, and `lca_validation_report_view` reads four of the others.
     - **`lca_validation_report_view` is a write path, not a report.** An `INSTEAD OF UPDATE` trigger routes writes through `lca_validation_report_view_upd()`. A catch-up migration capturing only the view definition would have silently dropped that path on any rebuild, so `033` captures the function and trigger too. The same function is the trigger body for `lca_validation_report_view_SS260818` — Phase F drops that view but must keep the function, as already noted there.
     - `034_catchup_design_description.sql` — `design_description` (2 rows, 3 columns, a PK, no FKs either way, no reference from either repository). Dropping it was considered and rejected for now: "no code references" only covers the two repositories, and open question 7 is unanswered. Flagged as open question 15.
     - Reverts for `033` and `034` are **deliberate no-ops** that say so in prose. Both migrations created nothing; dropping objects they merely describe would be data loss dressed as a rollback. This is now the standing pattern for catch-up migrations, recorded in `sql/README.md`.
     - Verified no-op: `pg_get_viewdef`, column lists and row counts for all 8 views are byte-identical before and after, as are the function and trigger definitions; `design_description` still has its 2 rows and its PK; the snapshot view's trigger is intact; the ledger went 32 → 35 with no gap.
4. ~~Add a drift check (live inventory vs baseline).~~ **Done 2026-10-02; scheduled 2026-10-05.** `bin/check_drift.py` compares live objects against `schema/object_inventory.tsv` and exits non-zero on any difference. `bin/drift_cron.sh` now runs it daily at 07:17 together with `bin/apply_migrations.py --verify`, and is installed in `tyler`'s crontab. Both the silent-when-healthy path and the failure path were tested.

   **Host cron, not CI**, because GitHub runners cannot reach the database host and giving them access would mean committing credentials — which is what Finding 14 undid.

   **The host has no MTA** — no `sendmail`, no `mail`, postfix inactive — so cron mail is dropped. A check nobody hears is not a check, so the wrapper writes `~/log/genomes_db_drift.FAILING` while the last run failed and removes it when healthy; `~/log/genomes_db_drift.log` records every run. **Surfacing that status file from a login banner or monitoring agent is an outstanding follow-up** — nothing currently pushes it at anyone.
5. ~~Remove credentials from `create_database.py`.~~ **Superseded 2026-10-02.** The two scripts that actually reach the live database (`import_data.py`, `import_v2.py`) no longer contain credentials at all. `create_database.py` was moved to `SS/` — it targets the decommissioned host and the retired `oceanomics` database, so its literal is dead. Its credential, and those in the other 18 `SS/` files, are left in place deliberately and scrubbed at rotation.

6. **New, and deliberately left open: three unmanaged tables appeared after the re-baseline.** `og_workflow_recommendation`, `og_workflow_assignment_log` and `og_workflow_notification` were created on the live database by direct DDL some time after 2026-10-02 — they hold the three highest OIDs in the database. All three are empty. All three are well modelled: primary keys, `CHECK` constraints on their enumerated columns, `timestamptz` throughout. One constraint is `source IN ('site', 'database')`, so something web-facing is being built against them. Nothing in either repository references them.

   They are in **neither** `sql/` nor the baseline, so a rebuild would lose them entirely — the one tier `bin/check_drift.py` describes as "brand new direct DDL".

   **Decision: leave the alarm sounding.** Not dropped (they look like live in-progress work, unlike the abandoned `data_package_*` subsystem), not described in a catch-up migration, and — the operative part — **not accepted into the baseline**. `bin/check_drift.py` therefore exits non-zero every day and the `FAILING` marker stays present until someone claims them. That is the governance rule working rather than failing: the alternative, running `--update`, is drift being rubber-stamped, which is exactly how 22 tables and 6 views got here in the first place. Recorded as open question 16. Do not silence it with `--update`.

   The cost is honest and should be stated: a check that is always red trains people to ignore it. This is tolerable only because it is expected to be short-lived.

Phase B is complete. Its one deliberate loose end is the unclaimed drift in item 6; the `v2` half of open question 8 was unbundled from item 1 rather than left blocking, and is tracked there.

**Known limitation, measured not assumed.** The schema still cannot be rebuilt from `sql/` alone, and the catch-up migrations do not change that — they buy history and rationale for ten objects, not reproducibility. A rebuild was attempted on a scratch database to find out exactly where it stops: `000` applies, `001` and `002` apply, and `003` fails on `relation "mitogenome_data" does not exist`. It never reaches `033`, which fails in turn on `relation "lca" does not exist`. Both failures are readable and both are expected — the base tables those migrations alter are among the 39 objects still routed to Phases C, E and the `v2` cutover. The success criterion in section 13 stays **No** for that reason.

### Phase C: Add the constraints the data already satisfies

0. **Capture these ten tables in a catch-up migration first, as step one of the constraint work** (routed here from Phase B.3): `rna_qc_kinnex`, `ncbi_genome_assemblies`, `raw_qc`, `ref_genomes`, `hifi_reads_qc`, `hic_reads_qc`, `raw_data`, `draft_genomes`, `ref_genomes_sra_uploads`, `ref_genomes_assembly_uploads`. None of them is created by any migration today. Writing the `CREATE TABLE` and the constraint it is about to gain in one change means the migration explains itself; written separately beforehand, the first one would just restate the catalog. Note `draft_genomes` has 118 columns and `ref_genomes` 58 — those two are the bulk of the effort here.

1. Add the seven zero-orphan FKs from Finding 3, with pipeline owners' sign-off. **Unblocked 2026-10-02** — migration `030` added the child-side indexes these need.

   **Two of the seven come off this list, and the rest must wait for V.5.** Recorded 2026-10-05 by Phase V.1, which found the interaction. `mitogenome_data` and `blast_filtered_lca` are two of the seventeen tables `v2` recreates, and `create_v2_lca_tables.sql` already gives all five LCA tables an FK to `v2.sample(og_id)` — adding them to `public` here writes a migration the cutover throws away.

   The remaining five, plus C.5's `raw_qc` and `ref_genomes`, all point at `public.sample` from tables that stay in `public`. **Foreign keys bind to OIDs exactly as views do.** Added before V.5, they bind to `public.sample`; the rename to `sample_pre_v2` does not break them — they follow the OID and keep validating new rows against the frozen pre-cutover sample list — and V.6's `DROP` then either fails or cascades them away. That is worse than the view version of the same trap, because a stale FK rejection reads as a data error rather than a schema error and so does not announce itself. Run this step *after* V.5 and the unqualified `REFERENCES sample` resolves to `v2.sample` correctly. **The ordering is load-bearing.**
2. Add PKs to `ncbi_genome_assemblies` and `rna_qc_kinnex`; add `rna_qc_kinnex` → `rna_library_kinx` FK (Finding 13).
3. Add `rna_library_kinx.rna_id` → `rna_extraction` FK (still outstanding from revision 1).
4. Add the `NOT VALID` "exactly one library link" check on `sequencing` (Finding 5).
5. Fix the 7 remaining orphans in `raw_qc` and `ref_genomes`, then FK those too — **after V.5**, for the OID reason in C.1.

### Phase D: Fix `summary`

Less urgent since `030`: `summary` fell from 7.6 s to 2.0 s on indexing alone. The remaining 2.0 s is the view's own structure, which is what this phase addresses.

1. Strip `status_overwrite` references (dead logic, Finding 6).
2. Rebuild with pre-aggregated CTEs, or materialise and refresh after the nightly import.
3. Compare output against the current view before and after.

### Phase E: Species consolidation

**Scope reduced 2026-10-05.** `master_species` and `master_species_genome` are a colleague's separate piece of work and **must not be touched by this phase.** The original step 1 proposed redefining `master_species` as a view and re-pointing `master_species_genome`'s FK; that is now out of scope here and is struck below. What remains is the `species` side only.

0. **Capture `species` and `species_ncbi_assembly` in a catch-up migration as step one of the restructure** (routed here from Phase B.3) — neither is created by any migration today, and step 4 rewrites them anyway, so the `CREATE` and the change belong in the same migration.
1. ~~Make `species` canonical; redefine `master_species` as a view; re-point `master_species_genome`'s FK.~~ **Reduced:** make `species` canonical for everything this project owns. The `master_species` / `master_species_genome` half is a colleague's work — coordinate, do not implement. See Finding 2.
2. Add import-time validation on `sample.nominal_species_id`.
3. Classify the 892 invalid values using `lca_validation.validated_rank`.
4. Consolidate `species_ncbi_assembly` and `ncbi_genome_assemblies`. (`ncbi_genome_assemblies` gets its catch-up `CREATE` in Phase C.0, the earlier touch; this phase reworks it.)

### Phase F: Resolve the snapshots

**Unblocked 2026-10-05.** Item 1 is done and items 2–4 are now a single operation.

These eight objects (five tables, three views) account for 8 of the 39 still-uncovered objects and **need no catch-up migration at all** — they are being deleted, not brought under management. Dropping them is the cheapest way to shorten that list.

1. ~~Decide `lca_old`'s fate (blocking — it FKs to a snapshot).~~ **Done, migration `032`** — archived to CSV and dropped. Its FK was the only one into `mitogenome_data_SS260818` from outside the snapshot set.
2. Drop the five `SS260818` tables. They are now a self-contained group — their three remaining FKs are all internal. Four of the five are archived in `archive/snapshots_SS260818/`; **export `blast_filtered_lca_SS260818` first**, it was deliberately left out.
3. Drop the three snapshot views at the same time — but **keep `lca_validation_report_view_upd()`**, which is shared with the live `lca_validation_report_view`. Confirmed 2026-10-05: the sharing is via `INSTEAD OF UPDATE` triggers of the same name on both views, both executing that one function. `033` captures the function and the live view's trigger, so dropping the snapshot view removes only its own trigger.
4. Reclaim the clean index names on `mitogenome_data` (`mitogenome_data_pkey` etc., currently held by the snapshot and forcing the live table's `_1` suffixes).

Note that dropping the tables makes `sql/revert/027_...` permanently unrunnable. Accepted; recorded in that file.

### Phase G: Documentation

1. Extract the 26 migration headers into `docs/data_dictionary.md`.
2. Document the `data_package_*` subsystem.
3. Document `seq_date` as an identifier component, not a date.
4. Comment the remaining active tables.

### Phase H: Status normalisation, then sequencing/library redesign

As revision 1's Phases 5 and 6. `sample.ilrna_status` first — it is degrading fastest. **Most of this phase is absorbed by Phase V**: the `v2` design already removes the derived status columns at source (F5) and already builds the library registry (F6, decision 4), so the sequencing/library redesign is cutover work, not a separate later project. What remains here afterwards is the structural change the owner wants *beyond* `v2`, including the deferred `tissue_type_code` / `tissue_index` columns from `lab_key_strategy.md` §6.2 — parked because they parse the ID grammar, which only becomes safe once `v2` enforces it.

### Phase V: the `v2` cutover

**Direction approved 2026-10-05** (open question 8). `v2` is the intended foundation for the schema; this phase is how it lands. It is the largest remaining piece of work in the plan and it closes **17 of the 39 uncovered objects** in one step.

Both gates are now cleared. **V.0 was dropped by decision and V.1 is done**, both 2026-10-05; the detail is under each below. Phase V starts at V.2.

**V.0 — ~~Close open question 7.~~ Dropped 2026-10-05 at the owner's direction.** The fortnight of `log_statement = 'all'` logging will not be run, and open question 7 is closed by decision rather than answered. A consumer carrying hardcoded `public.` prefixes in its own queries is accepted breakage: it fails after cutover and is fixed then. Most such fixes are one word.

   **What this trades away, because it is not nothing.** The logging was the only proposed way to identify a broken consumer *before* breaking it. Without it, the first signal is a person reporting a failure. V.5's design is what makes that tolerable — the superseded tables are renamed so they fail loudly and immediately instead of serving stale data to someone who never notices.

   **What it does not trade away, which turned out to be most of the value.** Everything *inside* the database was always in the catalog and never needed two weeks of waiting. `scripts/audit_v2_dependents.py`, written for V.1, inventories it in a second: ten dependent views, five triggers, and **eleven functions that follow the `search_path` silently** — among them six `build_*_samplesheet*` functions generating Nextflow samplesheets from `sample` and `sequencing`, which nobody had examined and which V.0's log would have surfaced only as traffic from an unidentified client. V.0 would have added the *external* clients only, which is precisely the category now accepted as breakage.

   So the honest summary is that V.0 was mis-scoped as a blocker rather than wrong to want: the discoverable half was free all along, and the expensive half covered the risk being accepted. Run `scripts/audit_v2_dependents.py` again on the morning of the cutover.

**V.1 — Re-review the scaffold before promoting any of it. Done 2026-10-05.** Output: `docs/v2_scaffold_design_review.md` revision 2, `scripts/diff_v2_against_live.py`, `scripts/audit_v2_dependents.py`, and the DDL and backfill changes recorded below. Validated end to end against a throwaway cluster loaded from the current baseline — deploy, verify, revert, re-apply, and the backfill run twice to idempotency.

   The re-review was the right call and the margin was not close. Nine defects, six of them unknown in August, and three would have caused an outright failure rather than quiet damage:

   - **40 columns** added by migrations `017`–`026` were absent from the `v2` DDL and would have been dropped at cutover — 34 on `mitogenome_data` alone.
   - **Three types reverted migration `022`**; two of them make the backfill *abort* (`real` underflows on HiFi confidence scores reaching 5.27e-163), and the third rejects 1,009 rows of semicolon-separated multi-taxon ids.
   - **`v2.lca_raw_results`'s primary key cannot be satisfied by live data** — 33 collisions, because it keyed on `lca_run_date` instead of the content hash that `017` introduced.
   - **`content_hash` was `NOT NULL`, in two keys, with no trigger to fill it.**
   - **`mitogenome_data.annotation` was `NOT NULL`**, which would have quarantined 374 not-yet-annotated assemblies for a constraint no finding asked for.
   - **The lab backfill silently discarded 100 rows** and aborted outright on a tube ID shared across two library types — see the §4.4 note below.
   - Plus the three defects already known: the stale `lca_new` scope boundary, the missing LCA backfill, and `v2.summary` reading `public.lca_validation`.

   Two conclusions worth carrying forward beyond this phase. First, **every one of the six new defects is a migration landing after the design and nobody reconciling the two** — the `v2` directory had no mechanism to notice, which is what `scripts/diff_v2_against_live.py` now provides; run it before V.3. Second, **two August findings were right about the spreadsheet and wrong about the database**: §4.4 concluded RNA tube IDs do not overlap (true of the workbook, false of the live tables, where 24 `_KL` tubes appear in both RNA tables), and F4 called `ratioqubit_nanodrop` "dead on both ends" (true of the import path, false of the table, which holds 987 hand-entered measurements). An analysis of the source is not an analysis of the destination.

   Original scope, for the record:

1. **Re-diff the LCA DDL against the live catalog.** `create_v2_lca_tables.sql` declares `lca_new` and siblings out of scope as concurrent work (lines 5, 31); that rebuild has since landed and those are now the live `lca`, `lca_raw_results`, `lca_validation` and `blast_filtered_lca`. Column-by-column against `information_schema`, not by reading the August document.
2. **Write the missing LCA backfill.** `backfill_v2.sql` covers the twelve lab tables only; the five LCA/mitogenome tables would cut over empty. Build it to the same two-statement pattern — rows that pass, then rows that quarantine — so it stays re-runnable and idempotent.
3. **Fix `v2.summary`'s `public.lca_validation` references** (lines 128–138) unless the re-review finds the qualification was deliberate, in which case comment it like the `master_species` and `ref_genomes` ones at the top of that file.
4. **Re-diff the twelve lab tables against live.** Three months of imports have run since the design. Any column the lab has added to the workbook since August is missing from `v2` and will be silently dropped at cutover — which is exactly the `name_convert.py` failure mode of F4a, repeated.
5. **Re-check the eleven dependent views, and correct the cutover document.** `docs/v2_cutover_dependencies.md` audited them in August and found nine cutover-neutral. Migration `033` has since captured eight of them, and `027` repointed three. Confirm the audit still holds, and in particular that `lca_validation_report_view`'s `INSTEAD OF UPDATE` write path survives the swap — it is a write path, not a report, and nothing in the August analysis knew that.

   **That document contains an error that someone would otherwise act on.** Its line 12 states the mechanism correctly — "a view *recreated* with `v2` ahead of `public` on the search path resolves to the v2 tables with no edit at all" — but its summary then says a "`search_path` swap is sufficient and **no DDL is needed**" for the nine cutover-neutral views. That is wrong: views bind to table OIDs, not names, so an existing view ignores the `search_path` entirely and keeps reading `public`. The nine need no *edit*; they absolutely need **recreating**. Corrected 2026-10-05; the consequence is spelled out in V.5.
6. **Re-run the validation the August review claims.** Deploy / verify / revert against a throwaway cluster loaded from the *current* baseline, re-run the constraint tests, and re-run `import_v2.py` against the current workbook. The August numbers (20,881 loaded, 1,004 quarantined) are the comparison point; a large change in the quarantine count is a finding, not noise.
7. **Audit for new `public.` hardcoding** across all six deploy files, not just the known one in `create_v2_summary_view.sql`.

   Output: an updated `docs/v2_scaffold_design_review.md` — a revision 2 of that document, not a rewrite — plus whatever DDL changes it demands.

**V.2 — Importer changes land before the swap, never after. Done 2026-10-06, rehearsed end to end on a restored copy of live.**

   **Outcome.** The three §0.6 decisions were taken by the owner on 2026-10-06, and all three are now built.
   - **The backfill prefers the workbook row.** `import_v2.py --stage-attempt-keys` copies the workbook's attempt keys into the new `v2.workbook_attempt_keys`.
     - When live has a tie, `backfill_v2.sql` seats the one tied row the workbook carries under that same `(parent, attempt)`.
     - If the workbook carries none of them, or more than one, nothing is seated and every tied row is quarantined.
     - The backfill refuses to run with nothing staged.
   - **The workbook wins at import.** A seated row whose slot the workbook gives to a different tube is handled by whether the workbook still carries that tube:
     - **Still carried** (a renumber or a swap): it moves in the same upsert, because the nine attempt keys are now `DEFERRABLE INITIALLY IMMEDIATE`.
     - **No longer carried:** it is deleted and kept whole in `v2.v_quarantine_displaced`.
     - **No longer carried, but libraries or sequencing hang off it:** the seated row stays, and the workbook row is quarantined instead.
   - **A database-raised violation costs one row, not the run.** Each table is written under a savepoint and falls back to one row at a time. In that fallback the attempt key stays deferred until the end of the pass, so an unrelated bad row cannot block a legitimate swap. An earlier version did block it, and the local test caught that.
   - **`check` was added to the quarantine vocabulary**, for CHECK violations the database raises.
   - **Exit status for the scheduler:** 0 means the run completed, however many rows were quarantined; non-zero means it aborted and wrote nothing. The schedule lives on another HPC and the owner is setting it up, so that is documented in `OceanOmics-Database/README.md` rather than built here.

   **The mapping check was built first**, as this step required: `scripts/check_v2_mappings.py`. It reports three things that look like a NULL in the database:
   - mappings whose header is gone
   - mappings that match only after whitespace is normalised
   - populated headers that nothing reads

   Every allowed exception is listed in its `EXPLAINED` registry with a reason.
   - It reproduced all four defects below.
   - It also found four hand-entered headers §0.8 had missed. Two get mapped by owner decision: `Well Position` gets a new column, and `4.HiCLibrary`'s proximity-ligation concentration loads into the legacy `hic_library` column. The other two are not stored by decision.
   - Against `OceanGenomes_Database_261006.xlsx` it now exits 0. The importer matches headers after normalising whitespace, so a stray CR, LF or doubled space can no longer cost a column its data.

   **One §0.8 finding was wrong and is withdrawn: proximity-ligation yield.** `4.HiCLysate`'s `Proximity Ligation yield (ng)` is `=IF(R="NA","NA",R*40)` on all 386 rows, with no typed values. The 306 "recorded yields" on rows with no concentration are all `0.0`. The existing design, `prox_ligation_yield GENERATED AS (prox_ligation_conc * 40)`, is correct and stays. Mapping that column, as §0.8 recommended, would have stored 306 false zeros. Measure formula versus typed value before calling a column data.

   **Figures, against an empty `v2`, from `OceanGenomes_Database_261006.xlsx`:**
   - 21,347 loaded and 243 rejected, identical to §0.5.
   - 1,139 degraded against 1,137. The extra two are the text `too low` in two newly mapped numeric columns.
   - Recovered data: `synthesis_conc` 109 values (previously 0), `library_plate_well` 1,078, legacy HiC proximity-ligation concentration 264, and the five plate columns 274 / 266 / 129 / 129 / 34.

   A second run and a `--dry-run` were both unchanged.

   The local test reproduced the post-backfill sequence that used to abort. With `OG2111E_D` seated in `(OG2111G, 1)`, the importer completed, displaced `OG2111E_D` and seated `OG2111G_D`. All six DDL files deploy, verify, revert and re-apply, and `diff_v2_against_live.py` reports zero UNEXPLAINED against the 2026-10-02 baseline.

   **Rehearsed on a full copy of live, 2026-10-06.** A `pg_dump` of live (356 MB) was restored into a throwaway local cluster. The sequence was: deploy and verify all six DDL files, run `--stage-attempt-keys` from `OceanGenomes_Database_261006.xlsx`, run the backfill twice, then run `import_v2.py` twice.
   - **Nothing aborted.** The two backfill passes gave identical counts, and so did the two imports.
   - **The importer completes against the backfilled schema.** This is the sequence §0.6 reported as aborting. It also displaced nothing, because the backfill had already seated the workbook's rows.
   - **The `OG2111G` case resolves correctly.** `(OG2111G, 1)` seats `OG2111G_D`, and `OG2111E_D` is quarantined with the winner named.

   **Two tables number attempts per prep method, so their attempt key now includes the method.**
   - The first rehearsal found 59 slots tied inside the workbook itself: 56 on `4.RNAIllumina` and 3 on `4.ONT`. In every one, each tube had a different prep method. The lab restarts `#` at 1 for each method: an mRNA library (`_IL`) and a ribosomal-depletion library (`_dIL`) from the same RNA are both #1, and so are the LSK and ULK kits on ONT.
   - This holds on every parent with more than one method on those two sheets. On the other seven tables, every parent with several methods keeps counting across them.
   - Keyed on `(parent, #)`, those 59 pairs were false ties. In 31 of them the importer kept a failed or held library and rejected a sequenced one.
   - So `rna_library_ilmn_attempt_key` and `ont_library_attempt_key` are now `(parent, library_method, #)`, and `is_latest` in those two browse views is per method. The change runs through `name_convert_v2.ATTEMPT_KEYS`, the importer, the staging table (`attempt_scope`) and the backfill.

   **The rehearsal was re-run with that change, from the same dump.** All six DDL files deploy and verify, both backfill passes and both imports are identical, and `diff_v2_against_live.py` reports zero UNEXPLAINED against the live copy.

   | | before the method fix | after |
   |---|---|---|
   | Tied rows quarantined by the backfill | 235 | **65** |
   | `rna_library_ilmn` / `ont_library` rows after backfill | 226 / 91 | **389 / 98** (all of live) |
   | Rejected at import, `rna_library_ilmn` / `ont_library` | 69 / 4 | **13 / 0** |
   | Open quarantine after import | 1,503 | **1,333** |

   The 65 tied rows that remain are not about method:
   - **61 are tubes renamed in the workbook.** The workbook carries the new name, which is seated. For example, `OG2111E_D` lost to `OG2111G_D`, and 47 of the 48 `dna_extraction` slots have a tube whose prefix contradicts its tissue.
   - **4 are two `dna_extraction` slots that the workbook carries neither tube for.** One of them is the typo pair `OG2274H_D_D` / `OG2274H_D2`.

   No ties remain inside the workbook, so the open decision raised by the first rehearsal no longer arises.

   Record of the original scope follows.

   **Scope widened 2026-10-05: `import_v2.py` does not currently survive the backfill at all.** Phase V.1 ran it against a cluster that had been backfilled — the state V.4 creates — and it **aborts** on `dna_extraction_attempt_key`. Against an empty `v2` it is fine (1,049 quarantined, against August's 1,004), so this appears only in the combination Phase V actually performs.

   Cause: live holds 48 colliding `(tissue_id, ext_num)` pairs across 97 rows. The backfill breaks each tie by lexicographic tube ID and quarantines the loser; for `(OG2111G, 1)` that seats `OG2111E_D` — whose prefix contradicts the tissue it is filed under — and rejects `OG2111G_D`, which is the row the workbook carries. The importer then cannot insert it, because it upserts `ON CONFLICT (dna_id)` and the colliding row has a different `dna_id`. One pair aborts the entire run, since it is a single transaction.

   **Four mapping defects also block this step**, all found by re-checking `name_convert_v2.py` against the current workbook `OceanGenomes_Database_261006.xlsx` (§0.8 of the design review). Each presents as a silent NULL, not an error, which is why running the importer did not reveal them: `illumina_library.library_plate_well` maps to a header the lab renamed to `Final Library Plate Well` (1,078 rows — a regression in the §4.1 fix); `rna_library_ilmn.library_size` maps to a header since removed; `rna_library_kinx.synthesis_conc` maps a `\r\n` where the header has a bare `\n`, so the August "FIXED" never worked and live is 0 of 189 against 110 workbook values; and `4.HiCLysate`'s `Proximity Ligation yield (ng)` (383 of 386 rows) is mapped nowhere while `v2` generates that value from a column populated on 77 *(withdrawn 2026-10-06: the column is a formula and its other 306 values are 0.0 — see the outcome above)*. Four new lab headers have no mapping or column at all.

   **Nothing in the toolchain compares the mappings to the workbook**, which is the gap all four came through. `scripts/diff_v2_against_live.py` compares DDL to database; `import_v2.py`'s unmatched-header report finds headers with no mapping but not mappings with no header. Build the inverse check before this step.

   Three further decisions, detailed in `docs/v2_scaffold_design_review.md` §0.6: whether the backfill should quarantine **both** sides of an attempt-key tie rather than seating an arbitrary winner; what the importer's conflict target should be on a table whose primary key is a mutable tube ID; and whether the importer should quarantine a database-raised violation instead of aborting the batch. The last one is the difference between a failed nightly run and one blocked row.

   Original note: `queries.py` writes **unqualified** table names, so it follows the `search_path` silently. The swap moves the nightly importer whether or not anyone intends it. `name_convert_v2.py` and `import_v2.py` already exist as the parallel path (§5 step 10); they must be the live path before the search_path changes.

**V.3 — Promote the DDL to numbered migrations. Done 2026-10-06: ported, rehearsed, and applied to live.** Plan and record: `docs/phase_v3_plan.md`.

   **Pre-flight, against live and `OceanGenomes_Database_261006.xlsx`:** no migration after `034`, so nothing reached the DDL since the re-review; `diff_v2_against_live.py` and `check_v2_mappings.py` both zero UNEXPLAINED; drift only the known `og_workflow_*` three; `audit_v2_dependents.py` 10 views, 5 triggers, 11 functions, every one with a disposition.

   **What was built.** `sql/035_v2_schema.sql` to `sql/040_v2_summary_view.sql`, in the recorded plan order (LCA tables before the summary view), with reverts in `sql/revert/`. The port changed only what the `sql/` convention requires:
   - **Every `CREATE` is guarded** — `IF NOT EXISTS`, `OR REPLACE`, and a `pg_trigger` check for the two triggers, which PostgreSQL 14 cannot guard any other way. The `prep_automation` seed is `ON CONFLICT DO NOTHING`. `bin/apply_migrations.py` recovers from a crash by replaying the file, so a file that cannot replay cannot recover.
   - **The `verify/` scripts run inside each migration, before `COMMIT`.** A failed check now rolls the deploy back, where Sqitch only reported after committing. The quarantine checks write test rows, so they run under a savepoint that discards them. A negative test — `036` with one parent FK made nullable — failed with the F7 message and left no tables.
   - **The design copies are deleted** and `diff_v2_against_live.py` reads `sql/NNN_v2_*.sql`; its `--all` report is byte-identical to the one read from `design/v2/deploy/`.

   **The backfill is not a migration, by decision.** This entry originally listed it last in the plan order. It moved to `scripts/backfill_v2.sql` instead and V.4 runs it: it refuses to run until `import_v2.py --stage-attempt-keys` has, which `bin/apply_migrations.py` cannot do, and it is built to be re-run while the lab fixes rows, which a ledgered file runs exactly once.

   **Rehearsed on a fresh restore of live** (`pg_dump` taken 2026-10-06, 35 ledger rows, 64 objects): apply; replay with the six ledger rows deleted, all no-ops; revert `040`→`035` and re-apply; then stage, backfill twice and import twice from `OceanGenomes_Database_261006.xlsx`. Every figure matches the V.2 rehearsal exactly — 65 tied rows quarantined, `rna_library_ilmn` / `ont_library` 389 / 98, 1,333 open quarantine — and both passes of each are identical.

   **Do not replay `035`–`040` after V.4.** Their embedded checks assert empty tables, which is true only at creation.

   **Applied to live 2026-10-06** with `bin/apply_migrations.py`; ledger 41 files, `--verify` clean. Afterwards:
   - The 96 `v2` objects on live match the rehearsal exactly, and the tables are empty apart from the two `prep_automation` seed rows.
   - `audit_v2_dependents.py` (10 views, 5 triggers, 11 functions), `check_drift.py` (the `og_workflow_*` three only) and `diff_v2_against_live.py` (zero UNEXPLAINED) are unchanged from the pre-flight.
   - `check_drift.py` inventories `public` only, so the `v2` objects do not register there until V.6 moves them.

   **The scheduled `import_v2.py` run is paused by the owner and stays paused until V.4's backfill has run.** Importing into an empty `v2` before the backfill is an order no rehearsal has run.

**V.4 — Backfill and reconcile, with both schemas readable. Done 2026-10-06.** Record: `docs/v2_reconciliation.md`. All figures are from `OceanGenomes_Database_261006.xlsx`.

   **Result on live:**
   - **Every row is accounted for.** `scripts/reconcile_v2.py`, new for this step, reports zero UNEXPLAINED. Every `public` key in the 12 lab tables is either loaded into `v2` or blocked with an open quarantine record; nothing is LOST and nothing is INVENTED.
   - **Values match.** All 17 tables are identical on unchanged columns, with `EXCEPT ALL` in both directions.
   - **Nothing is dropped silently.** Every value the backfill could not cast carries a `type_cast` record naming the field.
   - **Every quarantine class has a recorded cause.**
   - **The backfill is idempotent.** Pass 2 inserted 0 rows.
   - **The import works on top.** One manual `import_v2.py` exited 0, displaced nothing and matched the rehearsal. Open quarantine is 1,352.

   **Row counts were not enough, and this is the finding worth keeping.** The first reconciliation, on a fresh restore of live, found two backfill bugs that both earlier rehearsals had passed, because every count matched:
   - **`dna_extraction.ratioqubit_nanodrop` was never copied.** V.1 kept the column so its 987 hand-entered measurements would survive, and the backfill never referenced it.
   - **Values that failed a cast were nulled with no quarantine record** in every table except `sample` and one `dna_extraction` column. Examples: `>1.8`, `pooled library = 2.60ng/ul`, and plate-well IDs in `library_molarity`.

   Both were fixed (commit `c0d59d6`) and re-rehearsed before live was touched. Reconcile by key and by value, not by count.

   **Still open.** The `import_v2.py` schedule on Amphi is paused until the owner resumes it. From then on both schemas are fed nightly until V.5. `v2.v_quarantine_open` is the lab's worklist.

**V.5 — Cut over, and make the old tables fail hard rather than serve stale data.** Adopted 2026-10-05 at the owner's direction, replacing the earlier "keep `public` populated and readable until consumers are confirmed" plan. That plan's weakness is the one Finding 11 already demonstrated: a consumer still reading superseded tables gets plausible, silently-wrong answers, and nobody notices for weeks. The alternative is to break it loudly, at a moment when someone is watching and the fix is trivial.

   **Status 2026-10-13: written and rehearsed, not applied.** The cutover is `sql/044_v2_cutover.sql`, with its revert and runbook in `docs/phase_v5_plan.md`. It refuses to run without an explicit opt-in (`PGOPTIONS="-c oceanomics.v2_cutover=go"`), so an unrelated `apply_migrations.py` run cannot trigger it. The rehearsal on a restore of live passed every check, and the revert restored the schema byte for byte. It also produced two corrections to this section and one new hard prerequisite:
   - **`CREATE OR REPLACE` does not work for the two writable views.** `v2` changes some of their columns from `varchar` to `text` (F8), and `CREATE OR REPLACE VIEW` cannot change a column's type. So `044` drops and recreates `embargo_assignment_view` and `lca_validation_report_view`, restores their `INSTEAD OF UPDATE` triggers, grants and comments, and verifies all three before committing. The other five rebound views do take `CREATE OR REPLACE`. Ten views read the replaced tables, not eleven: three are replaced outright, and seven are rebound. `coverage_summary` and `goat_project_metadata_v1` read none of them.
   - **`044` mirrors grants into `v2`.** No `v2` object had any grant, and `readonly` lacked `USAGE` on the schema.
   - **`import_data.py` must be off before the cutover.** Run against a cut-over copy, it overwrote about 2,200 `v2.dna_extraction` rows and similar numbers in eight other lab tables with raw workbook values, bypassing quarantine and the value rules. It failed only on `sample` and `sequencing`, and it exited 0.

   **Deprecate the 17 superseded objects individually — not the `public` schema.** `public` keeps roughly 46 objects `v2` never touched (`raw_data`, `ref_genomes`, `draft_genomes`, the `ena_*` family, `mitogenome_data`, `master_species`, the `og_workflow_*` tables). Deprecating the schema takes all of them down too.

   **`REVOKE` does not work here, and the reason is worth recording.** The obvious way to make `public.sample` fail is to revoke read on it. It is a no-op: **everything connects as the `postgres` superuser**, and superusers bypass all permission checks. `REVOKE` only becomes an option once the non-superuser pipeline role from Phase A.3 exists, which is still outstanding. Do not plan around it until it does.

   **Rename instead.** `ALTER TABLE public.sample RENAME TO sample_pre_v2;` — `public.sample` then fails with `relation "public.sample" does not exist`, which is immediate, unambiguous, and names the problem. Unqualified `FROM sample` resolves through the `search_path` to the new table, so a well-behaved consumer never notices. Unlike dropping, it is **instantly reversible**, so this buys hard failure and keeps a rollback window. `COMMENT` each renamed object with its deprecation date and intended drop date.

   Set the `search_path` at the **database** level, not per-role, so a consumer connecting as some role nobody remembered still resolves correctly.

   **The trap — dependent views will not fail hard, they will silently follow.** This is the one thing that would defeat the whole approach, and it needs to be understood before the step is planned. **PostgreSQL views bind to table OIDs at creation time, not to names.** `public.sample_view` holds a dependency on the specific `public.sample` table, so:

   - changing the `search_path` does **not** repoint an existing view — it keeps reading `public.sample`;
   - renaming `public.sample` to `sample_pre_v2` does **not** break it either — the view follows the OID and keeps serving stale data under its own unchanged name.

   The result without action is precisely the failure being designed out: direct queries fail loudly while the views quietly return pre-cutover data. **Every dependent view must be dropped and recreated at cutover — all eleven, not only the two that reference removed columns.** See the correction to `docs/v2_cutover_dependencies.md` noted in V.1 item 5.

   Order within this step: set the database `search_path` → **`CREATE OR REPLACE`** all dependent views → pin the two functions above → rename the 17 `public` objects to `_pre_v2`.

   **`CREATE OR REPLACE VIEW`, not `DROP` + `CREATE`.** It re-parses the definition and rebinds it to whatever the `search_path` resolves to now — which is the whole point — while preserving grants to the `readonly` role, the dependent views, and the `INSTEAD OF UPDATE` triggers that a `DROP` would silently take with it. There are **two** such write paths, not one: `lca_validation_report_view` and also `embargo_assignment_view`, which the August audit classified as a plain reader. Only `summary`, `goat_species_v1` and `mitogenome_submission_view` change their output columns and so need a true `DROP` + `CREATE`.

   ~~`mitogenome_submission_view` is the one piece of DDL Phase V.1 identified and did not write.~~ **Written and applied 2026-10-13 as `sql/043_v2_mitogenome_submission_view.sql`.** `og_num` comes from `v2.sample` (the column `v2` removed from `mitogenome_data`, F2); join keys and output columns are `029`'s. Rehearsed on a 2026-10-12 restore of live (apply, replay, revert, re-apply), then applied: 2,349 rows, identical to `public.mitogenome_submission_view` under `EXCEPT ALL` in both directions, 1,180 ENA matches. Every DDL gap Phase V.1 identified is now closed.

   **Three things the 043 rehearsal surfaced that this step must handle:**
   - **No `v2` object is granted to anyone.** `035`–`043` grant nothing and the `readonly` role has no `USAGE` on schema `v2`. The cutover must grant `USAGE` on `v2` and `SELECT` on its tables and views in the same transaction as the `search_path` change, or every `readonly` consumer loses access at the swap.
   - **A second reader role, `oceangenom_web`, holds `SELECT` on `public` tables** (seen when its grants failed on a restore without the role). It is not mentioned elsewhere in this review and is likely the web front end the `og_workflow_*` tables are for (open question 16). It needs the same `v2` grants.
   - **The five pipeline-fed tables are only as fresh as the last backfill.** `scripts/backfill_v2.sql` is insert-only (`ON CONFLICT DO NOTHING`), while the mitogenome/LCA pipelines write `public`. On 2026-10-12 all five matched row for row (last `annotation_updated_at` 2026-10-05), so nothing has drifted yet — but the cutover must re-sync them, and point the pipeline writers at `v2`, or a pipeline overwrite made between backfill and cutover is lost.

   **The six samplesheet functions — reviewed 2026-10-13.** Three follow the swap unchanged (`build_final_data_compile`, `build_postcuration_samplesheet_rows`, `build_rna_kinx_samplesheet_rows`). Three break: `build_nfcore_samplesheet_rows` and `build_hicpost_samplesheet_rows` read `sequencing.og_id`, and `build_rna_kinx_samplesheet_from_run` reads `sequencing.rna_library_tube_id`. **None of them can be fixed by a migration:** the calling scripts `DROP` and re-`CREATE` them on every run, and the live `nfcore` body matches none of the three scripts in `OceanOmics-OceanGenomes-ref-genomes` — it and the `hicpost` builder come from the post-curation / genome-notes scripts under `/scratch/pawsey0964/lhuet/`, which are not on this host. Each fix is one line in the calling script (`sequencing` → `v_sequencing_browse`; `rna_library_tube_id` → `library_tube_id` on `sequencing`), verified identical against live, and must land on cutover day — it does not resolve before the `search_path` changes. Detail and the equivalence table: `docs/v2_cutover_dependencies.md`, "Functions". `scripts/audit_v2_dependents.py` now reports no unreviewed function.

   **Both nightly imports appear stopped, not only `import_v2.py`.** `public.rna_library_kinx.updated_at` has not moved since 2026-10-05 17:01, and `OG108G_R_KL` is blank in `public` but filled in `v2` from the 2026-10-06 workbook. Confirm the `fetch_excel.sh` cron on Amphi before relying on `public` as the reconcile baseline at cutover.

   **Then watch — but with less than was planned.** This step used to rely on V.0's `log_statement` tooling to surface anyone who breaks, by host and `application_name`, within a day. V.0 was dropped, so that is not available and external breakage will arrive as a person reporting it. Keep the window short but **non-zero** anyway: it is still the only period in which a broken consumer is cheaply fixable, and the rename makes the failure loud and self-describing. If appetite for `log_statement = 'all'` returns for even 48 hours around the cutover, this is the moment it is worth most — far more than a fortnight of it beforehand would have been.

   **Run `scripts/audit_v2_dependents.py` on the morning of the cutover**, not from memory. It reports the dependent views, the triggers, and the eleven unpinned functions with their recorded dispositions. Two of those dispositions are `ALTER FUNCTION ... SET search_path` statements that belong in this step: `lca_set_content_hash` and `set_updated_at` must be pinned to `public` so they cannot follow the swap into `v2` tables that no longer have the columns they maintain.

   Worth telling consumers in the same message that breaks them: most fixes are one word. The twelve **browse views** re-expose `og_id` and a derived `latest` on every child table and are inlined by the planner, so `illumina_library` → `v_illumina_library_browse` restores the removed join column at no cost. `summary` keeps all sixteen removed `sample` columns as derived output.

**V.6 — Consolidate into `public` and retire the parallel schema.** After a quiet period with no new breakage. The tables already carry their final names — decision 3 ensured `v2.sample` is schema `v2`, table `sample`, never `v2_sample` — so **nothing is renamed here; objects are moved**:

   ```sql
   ALTER TABLE v2.sample SET SCHEMA public;
   ```

   Per object, because `ALTER SCHEMA v2 RENAME TO public` is not available — `public` exists and keeps its other ~46 objects, and two schemas cannot be merged by renaming one. Then drop the `_pre_v2` tables and `DROP SCHEMA v2`.

   **What this does and does not fix.** It resolves *addressing* completely: `FROM sample` and `FROM public.sample` both reach the new table and the `search_path` stops mattering. It does nothing for *contracts* — the removed `og_id` columns, the sixteen removed `sample` columns, `status_overwrite` as `boolean`, the real date and numeric types, and the `sequencing` library registry break a stale query wherever the table sits. Consolidation is the last step of the cutover, not a way to avoid the middle ones; doing it early would only convert loud breakage into late breakage.

**V.7 — Close out.** The 17 objects become migration-covered; re-run `bin/check_drift.py --coverage` and update section 13. Phase H's remaining scope shrinks to what is genuinely beyond `v2`.

## 10. Revised Priority Backlog

### Do now

All four are done. The follow-ons each item left behind are listed with their parent below.

1. ~~Repoint the three snapshot-reading views at live tables.~~ **Done, migration `027`.** Follow up on Finding 15, which it exposed.
2. ~~Deploy the index migration.~~ **Done, migration `030`** — all 24 columns; `summary` 7.6 s → 2.0 s.
3. ~~`chmod 600` the credentials file.~~ **Done.** Now rotate the `postgres` password: it was world-readable on the host for about two months, and a `chmod` does not undo that.
4. ~~Ledger migration `026`.~~ **Done.** Write an apply/ledger script so the gap cannot reopen.

### Highest priority

1. **Rotate the `postgres` password** (Finding 14) — the only item here with a live exposure window behind it. The plumbing is done: credentials live in one file (`~/postgresql_details/oceanomics.cfg`) and `OceanOmics-Database/ROTATION.md` is the runbook, so the change itself is one line. The work is the propagation — chiefly the DBeaver users connecting as superuser from external IPs.
2. ~~**Choose one migration system and write the decision down**~~ **Done 2026-10-05** — `docs/migration_system_decision.md`. Tool only; the `v2` half of open question 8 is unbundled and still open.
3. **Answer open question 16: claim or discard the three `og_workflow_*` tables.** New top-of-list item. They arrived by direct DDL after the re-baseline, are in neither `sql/` nor the baseline, and keep the daily drift check red by deliberate choice. Cheap to resolve and it restores a working signal.
4. ~~**Answer open question 7 — which external clients read this database.**~~ **Closed by decision 2026-10-05, not answered.** The fortnight of logging will not be run; consumers hardcoding `public.` are accepted breakage. It no longer blocks the cutover. The in-database half of the question *is* answered, by `scripts/audit_v2_dependents.py`. See Phase V.0 for what the decision trades away.
5. ~~**Write catch-up migrations for the 49 objects no migration describes**~~ **Phase B's ten done 2026-10-05** (`000`, `033`, `034`). The other 39 are routed to Phases C, E, F and the `v2` cutover — each ships with the change that reworks its object. Run `bin/check_drift.py --coverage` for the current list.
6. ~~Add an apply/ledger script and a drift check.~~ **Done 2026-10-02; scheduled 2026-10-05** — `bin/drift_cron.sh` in cron, daily at 07:17. One follow-up: the host has no MTA, so surface `~/log/genomes_db_drift.FAILING` from a login banner or monitoring agent.
7. Add the seven zero-orphan FKs to `sample` — **unblocked**, `030` added the indexes they need.
8. Add import-time species validation on `sample.nominal_species_id`.
9. ~~Capture the `data_package_*` subsystem in a migration and the data dictionary.~~ **Moot 2026-10-05** — the subsystem was abandoned and dropped (`031`) rather than documented.
10. Strip dead `status_overwrite` logic from `summary` and rebuild or materialise it — less acute after `030`, but 2.0 s is still structural.

### Medium priority

1. ~~Resolve `lca_old`~~ **(done, `032`)**, then drop the `SS260818` snapshots — now unblocked and a single operation. Export `blast_filtered_lca_SS260818` first.
2. Consolidate the species tables — **`species` and `species_ncbi_assembly` only.** `master_species` and `master_species_genome` are a colleague's separate work and are out of scope; coordinate rather than change them (Finding 2, Phase E).
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
| 3 | Is `lca_old` still used by any report or user? | **No** — answered 2026-10-05. Nothing in code reads it, no view depends on it. Its 2,895 rows include 468 keys absent from live `lca`, but the LCA pipeline was re-run from scratch, so those are superseded output and must not be re-ingested. Archived to CSV and dropped (`032`). |
| 9 | Who owns the `data_package_*` subsystem, and where does its code live? | **Moot** — answered 2026-10-05. The work was abandoned and will not be resumed; the eight tables were dropped (`031`). |

Still open:

1. Which table is the authoritative species source — and does `master_species_genome` change the answer?
2. Are sample-level workflow status columns user-entered, imported, or derived?
4. Are QC records conceptually linked to samples, libraries, sequencing runs, lanes, or files?
5. Does each `sequencing` row represent a run, a library on a run, a lane, or an output file?
6. What are the required public contracts for GoaT API output?
7. Which downstream users or scripts query the database directly outside these repos? **CLOSED BY DECISION 2026-10-05, not answered — and it no longer blocks the `v2` cutover.** The owner's call: a consumer carrying hardcoded `public.` prefixes is accepted breakage, to be fixed when it fails after cutover. The instrumentation procedure below is left in place because it is the right procedure if the question is ever reopened, and because Phase V.5 may want 48 hours of it *around* the cutover, where it is worth far more than a fortnight beforehand.

   **Half of this question was answered for free, and that is the lesson worth keeping.** The procedure below finds *external* clients. Everything *inside* the database — views, triggers, functions — was in the catalog the whole time and needed no waiting at all. `scripts/audit_v2_dependents.py` (written for Phase V.1) reports it in about a second: ten dependent views, five triggers and eleven unpinned functions, including six `build_*_samplesheet*` functions feeding Nextflow that nobody had looked at and that follow the `search_path` silently. Framing the whole question as "needs a fortnight of logging" delayed the cheap half behind the expensive half for two months. When a question looks blocked on instrumentation, check what the catalog already knows first.

   Historical framing, retained: `docs/v2_cutover_dependencies.md` named it the only blocker and referred to it as "open question 10" (its numbering, not this document's). Cutover is a `search_path` swap, so the risk is a client with hardcoded `public.` prefixes, or one that silently follows the swap.

   **Partial answer, 2026-10-05.** `pg_stat_activity` shows live sessions from `130.95.40.88` (UWA) and `120.23.172.134`, across four DBeaver versions, **all connecting as the `postgres` superuser**. So there are at least two human consumers outside both repos, using a GUI client where saved queries may well carry explicit `public.` prefixes. That is evidence, not an answer: it catches whoever happened to be connected, not scheduled jobs, notebooks or dashboards.

   **How to close it — concrete procedure, written 2026-10-05.** Earlier revisions said "run `pg_stat_statements` or `log_statement = 'mod'` for a fortnight". That is too vague to act on, and **`log_statement = 'mod'` is the wrong setting for this question**: it logs DDL and data-modifying statements only. The consumers that break at cutover are overwhelmingly *readers* — a DBeaver saved query doing `SELECT ... FROM public.sample` is invisible to `'mod'`. The corrected procedure is below.

   The question has two halves, and no single setting answers both:

   | Half | What answers it | What it cannot tell you |
   |---|---|---|
   | *What SQL is being run* — does any of it carry a hardcoded `public.` prefix? | `pg_stat_statements`, or the statement log | `pg_stat_statements` normalises literals but **preserves table names**, so the `public.` prefix is visible. It records `userid`, which is useless here because everything connects as `postgres`. |
   | *Who is running it* — which host, which tool, which human? | the statement log with an attributing `log_line_prefix` | the log alone is high-volume and needs rotation managing |

   **Recommended: the statement log, because it needs no restart.** `pg_stat_statements` must be added to `shared_preload_libraries`, which requires a **server restart**; that is the single reason it is not the primary recommendation. If a restart is scheduled for other reasons, add it then — it is cheap to keep running permanently and is worth having regardless.

   Step 1 — set these in `postgresql.conf`, then `SELECT pg_reload_conf();`. All four are reload-only; **no restart, and reverting is another reload**:

   ```
   log_statement = 'all'
   log_line_prefix = '%m [%p] user=%u db=%d host=%h app=%a '
   log_rotation_age = '1d'
   log_rotation_size = '512MB'
   log_truncate_on_rotation = on
   ```

   `%h` is the client address, `%a` the `application_name` — which DBeaver, psql, psycopg2 and R's `DBI` all set, and which is the single most useful field for naming a consumer. Without a `log_line_prefix` carrying `%h` and `%a` the log tells you *what* ran but not *who*, which is half an answer.

   Step 2 — **measure the volume after 24 hours, before committing to a fortnight.** `du -sh` the log directory. This is the only real cost of the exercise and it is unknown until measured; the rotation settings above cap it, but confirm the cap is survivable on this host before leaving it running.

   Step 3 — after a fortnight, inventory. The distinct-consumer list:

   ```sh
   grep -ho 'host=[^ ]* app=[^ ]*' $PGDATA/log/*.log | sort | uniq -c | sort -rn
   ```

   And the actual blocker — statements carrying an explicit schema prefix:

   ```sh
   grep -iE 'public\.[a-z_]+' $PGDATA/log/*.log | grep -oiE 'host=[^ ]+ app=[^ ]+|public\.[a-z_]+' | sort | uniq -c
   ```

   **A fortnight, not a week**, because the risk is the consumer nobody remembers: a monthly report, a quarterly export, a notebook run when someone needs a figure. Two weeks catches weekly cadences and most ad-hoc use; it will still miss anything monthly, which is a residual risk to state rather than pretend away.

   Step 4 — classify every distinct `(host, app)` pair into one of three buckets, which is what the cutover plan actually needs:

   | Bucket | Meaning | Action at cutover |
   |---|---|---|
   | **Follows `search_path`** | unqualified table names only | Nothing. It moves to `v2` automatically — convenient, and dangerous for writers (see `queries.py` in `docs/v2_cutover_dependencies.md`). |
   | **Hardcodes `public.`** | explicit prefix | Must be found and updated, or it silently keeps reading the old tables after cutover. This is the failure mode the whole exercise exists to find. |
   | **Writes** | `INSERT` / `UPDATE` / `DELETE` | Must be updated *before* the swap, not after. |

   Step 5 — turn it back off (`log_statement = 'none'`, reload) and record the inventory in `docs/v2_cutover_dependencies.md` under its "Consumers outside this repo" section, which is where it belongs and which currently says "still open".

   **Two caveats worth stating up front.** The log captures only what runs during the window — it is evidence of presence, never of absence. And `log_statement = 'all'` writes query text to disk, so if any query embeds sensitive literals the log inherits that sensitivity; the log directory should be mode `700` for the duration, consistent with Finding 14.

New:

8. ~~Which migration system is the intended one — `sql/` + `schema_migrations`, or Sqitch?~~ **Answered 2026-10-05: `sql/` + `schema_migrations`.** Written down in `docs/migration_system_decision.md`, with the comparison that settled it. Sqitch is retired as a tool and its project files are deleted.

   ~~**The second half of this question remains open: is the `v2` redesign still the plan, or superseded?**~~ **Direction settled 2026-10-05: `v2` is the intended foundation and the project is going ahead with it.** The decision is the database owner's, recorded here so it is not re-litigated: `v2` is the step that makes the schema self-describing enough for other people to work with — real types, real foreign keys, constrained vocabularies, and 79 `COMMENT ON` statements against a live database where Finding 9 recorded 0 of 42 objects documented. Further structural change is wanted afterwards (Phase H, and the deferred `tissue_type_code` / `tissue_index` work in `lab_key_strategy.md` §6.2, which was parked precisely because it needs the ID grammar enforced first — `v2` is what enforces it). Those come *after* this foundation, not instead of it.

   **Settling the direction does not unblock the work, and the distinction matters.** Two gates remain, and both are execution gates rather than open questions:

   - **Gate 1 — ~~question 7 is the hard blocker.~~ Dropped 2026-10-05.** The instrumentation will not be run and consumers hardcoding `public.` are accepted breakage. It is no longer on the critical path. See Phase V.0 for what that trades away, and note that the *in-database* half of the question — which views, triggers and functions follow the swap — is answered for free by `scripts/audit_v2_dependents.py`, which needed no fortnight.
   - **Gate 2 — ~~the scaffold needs a fresh review before it is deployed.~~ Done 2026-10-05.** Nine defects found, six of them unknown in August, three of which would have failed outright rather than quietly. The gate did its job; see Phase V.1 and `docs/v2_scaffold_design_review.md` revision 2.

   The cost of the parked state is unchanged and measurable: **17 of the 39 still-uncovered objects are waiting on it** — the 12 lab tables, the four live LCA tables, and `goat_species_v1`. Writing `public` catch-up migrations for them duplicates DDL that `docs/v2_scaffold_design_review.md` records as already built, deployed and reverted against a throwaway cluster, constraint-tested with rejecting data, and exercised by `import_v2.py` end to end on the real workbook (20,881 rows loaded, 1,004 quarantined). With the direction now settled, those 17 are a **waiting cost rather than an open argument** — they become moot at cutover and nobody should write them by hand in the meantime.

   The DDL lived in `design/v2/`, non-executable, until Phase V.3 promoted it to `sql/035`–`040` on 2026-10-06.

   Three known defects in the `v2` scaffold, all of which Phase V.1 must resolve:

   - **Decision 1's scope boundary is out of date, and this is the significant one.** `design/v2/deploy/create_v2_lca_tables.sql` lines 5 and 31 state that `public.lca_new` and its siblings are separate concurrent work and are untouched. That was true in August. The LCA rebuild has since landed and **those tables are now the live `lca`, `lca_raw_results`, `lca_validation` and `blast_filtered_lca`** — the same four counted among the 17. So the `v2` LCA DDL was written against an assumption about table shape that no longer describes what is live, and must be re-diffed against the live catalog before it is trusted. This is independent of the cutover decision and needed doing either way.
   - **The five `v2` LCA tables have DDL but no backfill.** `design/v2/backfill_v2.sql` covers the twelve lab tables only. A cutover today would land an empty `v2.lca`, `v2.lca_raw_results`, `v2.lca_validation`, `v2.blast_filtered_lca` and `v2.mitogenome_data`.
   - **`v2.summary` reads `public.lca_validation`** (`design/v2/deploy/create_v2_summary_view.sql`, lines 128–138) even though `v2.lca_validation` exists. That looks like an oversight rather than a deliberate out-of-scope qualification — `master_species` and `ref_genomes` are schema-qualified on purpose and documented as such at the top of the same file; `lca_validation` is not.
10. ~~Were the three snapshot-reading views intended to read snapshots, or is that a leftover from the August rebuild?~~ **Answered:** a leftover. Migration `027` repointed them (Finding 11).
11. ~~Should the `SS260818` tables be archived, dropped, or retained as a rollback point?~~ **Answered 2026-10-05: archived, then dropped.** Four of the five plus `lca_old` are in `archive/snapshots_SS260818/` as verified gzipped CSV; `blast_filtered_lca_SS260818` was excluded at 4.7 MB and must be exported before its table goes. Removal is unblocked — see Phase F.
12. Is `ena_sequence_accession` expected to stay empty, and why is `ena_sample_accession` missing on 172 of 539 submissions?
13. `ont_library` and `hic_library` took zero new rows in three months, and `raw_data` took zero — expected, or a stalled import?
14. Should `ena_specimen_accessions` remain a separate specimen registry, or become a view over `sample`?
15. Does anything outside the two repositories read `design_description`? Two rows, three columns, a primary key, no foreign keys either way, and no reference from any view, script or migration. Captured in `034` so a rebuild would not lose it, but it is a removal candidate the moment question 7 can confirm no external consumer. Not dropped on the `031` / `032` precedent because those were provably dead and this is only unreferenced-as-far-as-we-can-see.
16. **Who owns `og_workflow_recommendation`, `og_workflow_assignment_log` and `og_workflow_notification`?** Three empty, well-modelled tables created by direct DDL after the 2026-10-02 re-baseline, referenced by nothing in either repository, with a `source IN ('site', 'database')` constraint suggesting a web front end. They are in neither `sql/` nor the baseline, so a rebuild loses them. The daily drift check fails on them every day by deliberate choice (Phase B.6) — **do not run `bin/check_drift.py --update` to quieten it.** Answering this is now the fastest way to get the check back to green: whoever built them should either write their catch-up migration or say they can go.

    Note this is the first real test of the governance rule adopted the same day, and the rule caught it. The tables appeared between the re-baseline and the scheduling of the check, which is precisely the window the check exists to close.

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

Unchanged, with four additions. Status as of 2026-10-05 — three met, five partly met.

| Criterion | Status |
|---|---|
| The schema can be recreated from source-controlled migrations | **No**, and now measured rather than estimated. 22 of 64 objects have a migration (was 12 of 61, and 12 of 70 before that). Of the other 42: 8 are being deleted (Phase F), 17 are closed by the Phase V cutover, 12 are folded into Phases C and E, 2 are a colleague's, and 3 are the unclaimed `og_workflow_*` tables. A rebuild attempt on a scratch database stops at `003`, on `relation "mitogenome_data" does not exist`. |
| Every active table has an owner and documented purpose | No. |
| Every active column is documented or intentionally self-evident | No. |
| There is one canonical species source | No. |
| Sample species links are valid and constrained | No. |
| Core child tables have indexed FK columns | **Met** — migration `030`, all 24 columns. |
| Major `og_id`-based tables either have FKs or documented reasons not to | No, but unblocked by `030`. |
| Workflow statuses use canonical values | No. |
| Heavy views have acceptable query plans | **Partly.** `summary` 7.6 s → 2.0 s; `goat_species_v1` unchanged. |
| Deprecated tables/columns are clearly marked and eventually removed | **Partly.** Nine removed on 2026-10-05 (`data_package_*`, `project_delivery_contact`, `lca_old`), each archived or documented first. The snapshots and the empty-column work remain; `design_description` is newly flagged (open question 15). |
| There is exactly one migration system, and the live inventory matches the baseline | **Partly, and for a new reason.** There is now exactly one migration system, declared in `docs/migration_system_decision.md`, and drift is checked daily rather than on demand. But the inventory no longer matches: three `og_workflow_*` tables arrived by direct DDL and have deliberately not been accepted into the baseline (open question 16). The first half is met; the second is red on purpose. |
| No reporting view reads a frozen snapshot unless its name says so | **Met** — migration `027`. |
| `summary` returns in under one second | **No** — 2.0 s, down from 7.6 s. Phase D is what closes the gap. |
| Database credentials are not readable by other users on the host, and pipelines do not connect as superuser | **Partly.** Credentials are in one `600` file and out of the live scripts. Everything still connects as `postgres`, and the password has not been rotated. |

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

As at review time (2026-10-02):

| System | Changes | Applied |
|---|---:|---:|
| `sql/` + `schema_migrations` | 26 | 26 applied, 25 ledgered |
| `genomes_db_review/sqitch.plan` | 8 | 0 |
| Direct DDL | 22 tables, 6 views | 22 / 6 |

As at 2026-10-05, after the Phase B close:

| System | Changes | Applied |
|---|---:|---:|
| `sql/` + `schema_migrations` — **the one system** | 35 | 35 applied, 35 ledgered |
| ~~Sqitch~~ | — | Retired. Project files deleted; the `v2` DDL it held is now `sql/035`–`040`. |
| Direct DDL | 3 tables (`og_workflow_*`) | Unclaimed — open question 16 |

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

### ~~Workshop 1: Migration governance~~ — closed 2026-10-05

Decided without a workshop. `docs/migration_system_decision.md` records which system survives; `docs/database_change_checklist.md` has the one-page rule under "Migration Governance"; the drift check runs in host cron rather than CI, because runners cannot reach the database host without committed credentials. **Still unresolved and not a workshop question: who may apply DDL.** The rule says "only through `sql/`", but everything still connects as the `postgres` superuser, so nothing enforces it — see Finding 14 and the password rotation at the top of the backlog.

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
| 2.6 | 2026-10-02 | Closed the Finding 10 mechanism and the Finding 14 plumbing. Added `bin/apply_migrations.py` (applies and ledgers in one step; aborts on hash drift; auto-detects `CONCURRENTLY`; guards the `005`/`019` replay hazard) and `bin/check_drift.py` (object inventory vs `schema/object_inventory.tsv`, plus a source-coverage report). Re-baselined `schema/`, three months stale. Separately, in `OceanOmics-Database`: the password was removed from the two live scripts into `~/postgresql_details/oceanomics.cfg` via a new `db_config.py`, `SS/` was documented as the superseded directory, and `ROTATION.md` was written. **The password value is unchanged** — this is plumbing, so rotation is now a one-line edit. Sections 9, 10 and 13 updated to reflect progress: Phase A complete, Phase B three of five, and the success criteria marked three met / four partly met. |
| 2.7 | 2026-10-05 | Removed nine objects rather than writing migrations to describe them. `031` dropped the abandoned `data_package_*` subsystem and `project_delivery_contact` (eight tables, 124 stale rows, no inbound FKs, no code references). `032` dropped `lca_old` — investigated and found to hold 468 keys absent from live `lca` plus three columns the live schema lacks, but all of it superseded by a full LCA re-run, so archived and removed. Both reverts are structure-only and were proven by a drop/revert round trip on a scratch database (211 structural facts identical). Four snapshot tables plus `lca_old` archived as gzipped CSV in `archive/snapshots_SS260818/` (2.2 MB, verified to reload `EXCEPT`-identical); `blast_filtered_lca_SS260818` deliberately excluded at 4.7 MB. Live objects 70 → 61; catch-up worklist 58 → 49. Phase F item 1 closed and the snapshot removal unblocked. |
| 2.8 | 2026-10-05 | Documentation only — no schema change. Broke Phase B.3's "49 uncovered objects" into a routing table and pushed the work into the phases that already rework each object, on the principle that a catch-up migration belongs as the first step of the change that alters the object, not as a separate job beforehand. 8 go to Phase F (deleted, no migration), 17 to the `v2` cutover, 10 to Phase C.0, 2 to Phase E.0, 10 stay in Phase B. Corrected an earlier undercount: `v2` covers **17**, not 12 — it includes the four live LCA tables and `goat_species_v1`. Recorded two `v2` gaps under open question 8 (no backfill for the five `v2` LCA tables; `v2.summary` reads `public.lca_validation` despite `v2.lca_validation` existing), and attached the DBeaver evidence from `pg_stat_activity` to question 7, the sole `v2` cutover blocker. **Scope reduction:** `master_species` and `master_species_genome` are a colleague's separate work — struck from Phase E.1, Finding 2's recommendation and the backlog so the intent is not re-derived from any of them. |
| 2.9 | 2026-10-05 | **Phase B closed.** Three pieces of work. (1) The migration-system decision, written down in `docs/migration_system_decision.md`: `sql/` + `schema_migrations` is canonical, Sqitch is retired as a tool, `sqitch.conf` and `sqitch.plan` deleted, the six `create_v2_*` changes relocated to `design/v2/` as non-executable reference DDL and the two superseded ones to `migrations/legacy/`. `migrations/README.md`, `sql/README.md` and `schema/README.md` rewritten — the first had advertised "Adopted — Sqitch" for two months while the second said the question was open. The working rule added to `docs/database_change_checklist.md`, closing Workshop 1. The decision covers the **tool only**; the `v2` go/no-go was deliberately unbundled and remains open on question 7. (2) Phase B's ten catch-up objects captured in three migrations: `000` (the ledger itself, which cannot ledger its own creation), `033` (the eight cutover-neutral views, with definitions from `pg_get_viewdef` and order from `pg_rewrite`), `034` (`design_description`). Verified a strict no-op: view definitions, column lists, row counts, the function and the trigger are all byte-identical before and after. Reverts for `033` and `034` are deliberate no-ops — a catch-up migration created nothing, so dropping what it describes is data loss, not rollback. Two things the work uncovered: `lca_validation_report_view` is a **write path** via an `INSTEAD OF UPDATE` trigger, not a read-only report, so `033` captures the trigger and function too; and `lca_results_view` reads `lca_pivot_view`, not the reverse. Coverage 12 of 61 → **22 of 64**. (3) The drift check scheduled — `bin/drift_cron.sh` daily at 07:17 in cron, running `check_drift.py` and `apply_migrations.py --verify`, silent when healthy. The host has no MTA, so it writes `~/log/genomes_db_drift.FAILING` instead of relying on cron mail. Findings 1 and 10 updated with resolution notes; Finding 1 downgraded High → Medium; Finding 10 resolved. **Three new tables found by the newly scheduled check** — `og_workflow_recommendation`, `og_workflow_assignment_log`, `og_workflow_notification` — created by direct DDL after the 2026-10-02 re-baseline, empty, well modelled, referenced by nothing in either repository. Deliberately **not** accepted into the baseline, so the daily check fails until someone claims them (open question 16). `design_description` flagged as open question 15. A rebuild attempt on a scratch database put a number on the remaining gap: it stops at `003`, on `relation "mitogenome_data" does not exist`. |
| 3.0 | 2026-10-05 | Documentation only — no schema change. **Open question 8's second half is answered: `v2` is the intended foundation and the project is going ahead with it**, recorded as the database owner's decision so it is not re-litigated. Settling the direction deliberately does *not* unblock the work, and the revision says so in both places: question 7 remains the hard blocker, and the owner added a second gate — **the August scaffold must be re-reviewed before any of its DDL is promoted to a migration**, having sat untouched for two months while the live database moved. Added **Phase V, the `v2` cutover**, as a six-step phase (V.0 instrumentation, V.1 re-review, V.2 importer first, V.3 promote to migrations, V.4 backfill and swap, V.5 close out); V.0 and V.1 are independent and should run in parallel. Rewrote open question 7 from a one-line suggestion into a five-step procedure with exact settings, and **corrected it**: it previously offered `log_statement = 'mod'`, which logs only writes and would therefore miss the read-only consumers that are the actual cutover risk — the recommendation is now `log_statement = 'all'` with an attributing `log_line_prefix`, chosen over `pg_stat_statements` because it needs a reload rather than a restart. Recorded a third scaffold defect alongside the two known ones: **`create_v2_lca_tables.sql` declares `lca_new` and siblings out of scope as concurrent work, which is no longer true** — that rebuild landed and those are now the live LCA tables, four of the 17, so the `v2` LCA DDL describes a shape that may not match live and heads the V.1 worklist. Fixed three stale references introduced by the Sqitch retirement: the `v2`-covered bullet's file paths and its incorrect claim that `goat_species_v1` is in the lab/LCA DDL (it is in `create_v2_summary_view.sql`), and `scripts/backfill_v2.sql` → `design/v2/backfill_v2.sql`. Phase H reduced — most of it is absorbed by Phase V, since `v2` already removes the derived status columns (F5) and builds the library registry (F6). |
| 3.1 | 2026-10-05 | Documentation only — no schema change. Reworked the back half of Phase V at the owner's direction, replacing "keep `public` populated and readable until consumers are confirmed" with **deprecate-and-fail-hard**: a consumer still reading superseded tables gets plausible wrong answers and nobody notices, which is Finding 11 by construction, so break it loudly while someone is watching. V.4 is now backfill and reconcile with both schemas readable; **V.5** cuts over and renames the 17 superseded `public` objects to `_pre_v2`; **V.6** consolidates the `v2` objects into `public` and retires the schema; V.7 closes out. Three mechanics recorded because each is easy to get wrong. (1) **The `public` schema itself cannot be deprecated** — it keeps ~46 objects `v2` never touched; only the 17 can be. (2) **`REVOKE` is a no-op here** — everything connects as the `postgres` superuser and superusers bypass permission checks, so it is unavailable until the non-superuser role from Phase A.3 exists; renaming is what produces a hard failure, and it is reversible, so it keeps a rollback window that dropping would not. (3) **Views bind to table OIDs, not names**, so an existing view ignores a `search_path` change *and* silently follows a rename — left alone, all eleven dependent views would keep serving pre-cutover data under unchanged names while direct queries moved to `v2`. All eleven must be dropped and recreated, not just the two referencing removed columns. That last point is a **correction to `docs/v2_cutover_dependencies.md`**, whose summary claimed a swap was "sufficient and no DDL is needed" for the nine cutover-neutral views while its own body said "recreated"; both that line and its `log_statement = 'mod'` suggestion are now corrected in place. Also recorded in V.6: consolidation fixes *addressing* and not *contracts* — removed columns and retyped columns break a stale query wherever the table sits — and the twelve browse views plus `summary` are the one-word fix for most broken consumers. |
| 3.2 | 2026-10-06 | **Phase V.2 done**, validated on a local throwaway cluster; the full-data backfill run is owed before V.4. Owner decisions: on attempt-key ties the backfill prefers the workbook's row, and the workbook wins at import; a database-raised violation is quarantined per row instead of aborting the run. New: `scripts/check_v2_mappings.py`; `import_v2.py --stage-attempt-keys` and `v2.workbook_attempt_keys`; the `displaced` and `check` quarantine types and `v2.v_quarantine_displaced`; deferrable attempt keys; five plate columns. Mapping fixes: `library_plate_well`, `synthesis_conc`, `library_size` and HiC proximity-ligation concentration on the library sheet. **Withdrew §0.8's proximity-ligation-yield finding**: the column is a formula, and its 306 "values" are 0.0. **Rehearsed on a copy of live.** The rehearsal found that `4.RNAIllumina` and `4.ONT` number attempts per prep method, so those two attempt keys gained `library_method`. That turns 59 false ties back into loaded libraries; tied rows quarantined by the backfill fall from 235 to 65. |
| 3.3 | 2026-10-06 | **Phase V.3 done: the `v2` DDL is promoted to `sql/035`–`040` and applied to live** (ledger 41, `v2` empty, all checks unchanged; `import_v2.py` schedule paused until V.4). Each file is guarded so it can be replayed, and runs its former verify script inside its own transaction. The backfill stays a script (`scripts/backfill_v2.sql`), by decision, because it needs out-of-band staging and is meant to be re-run. The `design/v2` DDL copies are deleted and `diff_v2_against_live.py` reads `sql/`. Rehearsed on a fresh restore of live: apply, replay, revert and re-apply, then a backfill and import identical to V.2 from `OceanGenomes_Database_261006.xlsx` (65 tied, 1,333 open quarantine). Corrected the dependency count from "seven triggers" to five: the audit has always reported five, and the baseline's sixth is on a `_SS260818` snapshot view, which it excludes. |
| 3.4 | 2026-10-06 | **Phase V.4 done: `v2` backfilled on live and reconciled against `public`** — zero LOST, zero INVENTED, identical on unchanged columns, every cast failure recorded, every quarantine class explained (`docs/v2_reconciliation.md`). New `scripts/reconcile_v2.py` and `scripts/run_backfill.py`. The reconciliation found and the step fixed two silent-loss bugs in the backfill that count-based rehearsals had passed: `ratioqubit_nanodrop` was never copied, and failed casts were nulled without a quarantine record. One manual `import_v2.py` run on top: exit 0, 1,352 open quarantine. The import schedule stays paused until the owner resumes it. |
| 3.5 | 2026-10-06 | **The easy unconvertible values are now converted by rule**: `OceanOmics-Database/v2_value_rules.py`, applied nightly by `import_v2.py` and once by `scripts/apply_value_rules.py`, and logged in `v2.value_conversions` (migration `041`). Owner decisions: bounds are stored as numbers, `pooled library` is not converted, no-value words count as blank, `Surface` = 0 m. On live, 925 values were converted and open quarantine fell from 1,352 to 869. The importer now closes quarantine records that no longer apply. The coordinate rule's first version floored negative serials; checking against same-location samples showed the text truncates, and the rule was fixed before live (`docs/v2_reconciliation.md`). |
| 3.6 | 2026-10-06 | **Migration `042`: `v2.sample` length is split into `length_tl_mm` / `length_fl_mm` / `length_unspecified_mm`, and depth into `depth_min_m` / `depth_max_m`**, parsed by `import_v2.py` from the workbook's single columns. Coordinates with no hemisphere, in the Australian range, are assumed south / east under their own logged rule. On live, no length or depth value went unaccounted for, and open quarantine is 702. The rehearsal caught a date-as-blank bug and a fill that would have closed 22 still-failing records (`docs/v2_reconciliation.md`). |
| 3.7 | 2026-10-13 | **Migration `043`: `v2.mitogenome_submission_view`**, the last DDL gap from Phase V.1 — `og_num` from `v2.sample`, otherwise `029`'s definition. Rehearsed on a restore of live, applied; identical to the public view (2,349 rows, 0 differences). Phase V.5 gains three prerequisites the rehearsal surfaced: `v2` grants for `readonly` and `oceangenom_web`, and a re-sync of the five pipeline-fed tables at cutover. |
| 3.8 | 2026-10-13 | **V.5 prerequisite: the six samplesheet functions reviewed.** Three follow unchanged; three break (`nfcore`, `hicpost`, `rna_kinx_from_run`), and all three are client-owned — recreated by their calling scripts on every run — so the fix is a one-line change in each script on cutover day, verified identical against live. Also found: the `public` nightly import appears to have stopped on 2026-10-05. |
| 3.9 | 2026-10-13 | **Phase V.5 written and rehearsed, not applied: migration `044_v2_cutover.sql`** and `docs/phase_v5_plan.md`. The rehearsal on a restore of live passed every check, and the revert was byte-identical. It found two defects in the first draft, both fixed: the writable views cannot take `CREATE OR REPLACE` (`varchar` to `text`), and the `readonly` grants were incomplete. It also found that the old `import_data.py` writes into `v2` after cutover and exits 0, so switching it off is now a hard prerequisite. `044` needs an explicit opt-in. |
| 3.10 | 2026-10-13 | **`044` fixed: column-level grants are now copied into `v2`.** `oceangenom_web` (the OceanGenom_Web app) updates `sample.workflow` through a column grant, which the first draft missed, so the app's Assign button would have failed after cutover. Re-tested on a schema-only restore. The runbook now records what the database shows about the web app, and an existing conflict: the nightly imports overwrite `sample.workflow` from the workbook. |
| 3.11 | 2026-10-13 | **`sample.workflow` is owned by OceanGenom_Web** (owner decision). Both importers now set it only on INSERT, `044` copies the web app's pre-cutover values into `v2`, the revert copies them back, and `reconcile_v2.py` explains differences backed by the app's assignment log. Tested on a scratch cluster. |

The previous revision is preserved at `/tmp/database_review.prev.md` at the time of writing; the authoritative history is in git.
