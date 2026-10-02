# Lab-Side Key Strategy

Date: 2026-07-07  
Status: Revised recommendation after read-only review of live lab identifiers  
Scope: Primary key design for sample, tissue, extraction, library, lysate, and sequencing tables

## 1. Context

The current lab-side database uses human-readable, concatenated identifiers as primary keys. For example:

- `sample.og_id` identifies the sample.
- `tissue.tissue_id` is derived from `og_id` plus tissue type or tissue descriptor.
- Downstream extraction and library IDs are similarly built from previous identifiers plus a new suffix.

The bioinformatics side often uses composite primary keys across several descriptive fields to achieve a similar effect. This makes rows understandable in DBeaver and makes some joins feel straightforward because the identifying context is embedded directly in the key.

The lab data currently comes from an Excel spreadsheet that is updated nightly. The spreadsheet already uses these concatenated identifiers as the working identifiers for physical lab objects and process steps. That matters: these values are not just cosmetic display labels; they are the operational IDs used by the source system.

The tradeoff is that the database stores repeated context in many places, and key values can become long, fragile, and difficult to change. In this database, however, the observed lab IDs are generally short and mostly consistent.

## 2. Live Data Observations

Read-only checks against the live database show that the lab naming convention is already widely used and mostly follows a parent-prefix pattern.

Examples:

```text
sample:          OG1
tissue:          OG1G
dna extraction:  OG1G_D
illumina lib:    OG1G_D_IL
pacbio lib:      OG1G_D_SBL
rna extraction:  OG1G_R
rna illumina:    OG1G_R_IL
hic lysate:      OG1G-1
hic library:     OG1G-1_HICL
```

Observed parent-prefix match rates:

| Relationship | Matching rows |
|---|---:|
| `dna_id` starts with `tissue_id` | 2,258 / 2,273 |
| `rna_id` starts with `tissue_id` | 262 / 262 |
| `illumina_library_tube_id` starts with `dna_id` | 1,724 / 1,724 |
| `pacbio_library_tube_id` starts with `dna_id` | 425 / 427 |
| `ont_library_tube_id` starts with `dna_id` | 98 / 98 |
| `hic_library_tube_id` starts with `lysate_id` | 326 / 326 |
| `rna_library_ilmn.rna_library_tube_id` starts with `rna_id` | 271 / 271 |
| `rna_library_kinx.rna_library_tube_id` starts with `rna_id` | 176 / 177 |

Observed ID lengths are also modest:

| Identifier | Min length | Max length | Average length |
|---|---:|---:|---:|
| `tissue.tissue_id` | 0 | 9 | 6.91 |
| `dna_extraction.dna_id` | 1 | 11 | 8.51 |
| `illumina_library.illumina_library_tube_id` | 9 | 14 | 11.56 |
| `pacbio_library.pacbio_library_tube_id` | 1 | 15 | 12.54 |
| `hic_library.hic_library_tube_id` | 11 | 15 | 13.03 |

The main issue is not that the IDs are too long. The main issue is that the convention is not fully enforced. Examples found include:

- Blank `tissue_id`.
- Placeholder IDs such as `0`.
- Malformed IDs such as `)G2112_D`.
- Missing Hi-C lysate suffixes such as `OG111G-`.
- Parent-prefix mismatches such as `dna_id = OG1623_D` for `tissue_id = OG1623W`.

These are validation problems more than primary-key design problems.

## 3. Recommendation

For the current Excel-driven lab workflow, keep the existing spreadsheet identifiers as the primary keys or at least as the authoritative business keys. Do not switch the lab side to wide composite primary keys.

In short:

```text
Near-term key: existing spreadsheet/lab ID
Main improvement: enforce naming rules and parent links
Optional future key: generated internal ID only if application needs require it
```

Because the spreadsheet is the nightly source, using the spreadsheet's own stable identifiers is simpler than introducing generated surrogate IDs immediately. A surrogate-key model would require a mapping layer from spreadsheet IDs to database IDs on every import. That can be worthwhile later, but it is not the first improvement I would make.

The better near-term target is:

- Keep `tissue_id`, `dna_id`, `rna_id`, and library tube IDs as the row identifiers used by Excel and DBeaver.
- Add or keep foreign keys between those IDs.
- Add validation checks so each child ID matches the expected parent ID pattern.
- Keep an explicit column for the immediate parent only, even though it repeats part of the child ID. Do not store grandparent or higher ancestors — see §6.0.
- Use views to show full lineage and to catch malformed IDs.

## 4. Why Concatenated Lab IDs Are Acceptable Here

Concatenated readable keys are often risky, but they are acceptable in this specific workflow if the team treats them as real lab/tube identifiers and enforces the convention.

Reasons they fit this database:

- They already exist in the source spreadsheet.
- They are used by lab users to identify real workflow objects.
- They are short enough that index width is not a major concern at current scale.
- They make DBeaver and spreadsheet review easier.
- They avoid maintaining a separate import mapping table just to translate spreadsheet IDs to generated IDs.

The risks still exist:

- They duplicate parent data into child identifiers.
- They make renaming or correcting parent values difficult.
- They make IDs encode business rules that may change.
- They can create ambiguity when the same sample has multiple tissues of the same type.
- They encourage downstream tables to parse meaning from IDs instead of joining to parent tables.
- They can become inconsistent if manually entered or generated by multiple import scripts.

The renaming risk deserves particular attention, because the materialized-path structure makes it cascade. Correcting a single typo in an `og_id` changes the primary key of every descendant row — the tissue, its extractions, and every library built from them. `ON UPDATE CASCADE` handles this mechanically, but it rewrites identifiers that are already printed on physical tubes and recorded in the source spreadsheet, so the database and the freezer can disagree.

This, rather than key length or row counts, is the condition that would justify moving to surrogate keys later: if parent ID corrections become frequent, the cascade cost stops being theoretical.

The right response is not necessarily to replace them. The right response is to validate them.

## 5. Why Not Use Composite Primary Keys Everywhere?

Composite keys are valid and can be a good design when the combined fields are truly the natural identity of a row. They are especially reasonable for immutable analysis outputs, such as:

```text
mitogenome_data: og_id + tech + seq_date + code
lca: og_id + tech + seq_date + code + annotation + region + run_date
```

However, for lab workflow tables, composite keys often become cumbersome because the entities are physical or process objects:

- A sample can have many tissues.
- A tissue can have many extractions.
- An extraction can produce many libraries.
- A library can be sequenced multiple times.
- A sequencing run can include many libraries.

Those relationships are easier to model with compact primary keys and explicit foreign keys.

## 6. Recommended Pattern

### 6.0 Core Rule: Store Only the Immediate Parent

The lab IDs form a **materialized path**: each primary key is its parent's primary key plus one additional qualifier, so every key carries its full ancestor chain the way a filesystem path does.

```text
OG1  ->  OG1G  ->  OG1G_D  ->  OG1G_D_IL
```

This produces one rule that applies to every lab table:

**Store exactly one foreign key per table, pointing one level up. Do not store grandparent or higher ancestors as columns.**

Store the immediate parent even though it is technically derivable from the child's own key. It should not be parsed out at query time, because the delimiters are not uniform between levels — `OG1 -> OG1G` uses no separator, `OG1G -> OG1G_D` uses `_`, and `OG1G -> OG1G-1` uses `-`. There is no single strip-the-suffix rule, a real foreign key constraint cannot be enforced against a computed prefix, and joins on a stored indexed column are cheaper than joins on `substring()`.

Do not store anything above the immediate parent. A column such as `og_id` on `dna_extraction` is one indexed join away through `tissue`, adds no integrity guarantee, and creates a value that can silently disagree with its own ancestor. Every such column requires a "should match the upstream ancestor" check that only runs at import and only detects drift after it has already happened. Removing the column removes the rule.

Where ancestor context is genuinely wanted for browsing or filtering, expose it through the views in §7 rather than as a stored column.

### 6.1 Sample

`og_id` is already a meaningful project identifier and is acceptable as the sample key.

Recommended structure:

```text
sample
  og_id               text primary key
  nominal_species_id  text
  ...
```

An optional generated `sample_pk` can be added later if an application layer requires it, but it is not necessary for the current spreadsheet-driven workflow.

### 6.2 Tissue

Recommended structure:

```text
tissue
  tissue_id           text primary key
  og_id               text not null references sample(og_id)
  tissue              text not null
  tissue_type_code    text generated always as (...) stored
  tissue_index        integer generated always as (...) stored
  ...
```

Example:

```text
tissue_id:         OG123G2
og_id:             OG123
tissue:            Gills
tissue_type_code:  G
tissue_index:      2
```

`tissue_id` follows a parent-prefix grammar: `og_id` plus a single-letter tissue type code, plus an optional trailing index when a sample has more than one tissue of the same type (`OG123G` for the first gill tissue, `OG123G2` for the second).

`tissue_type_code` and `tissue_index` should be **generated columns parsed from `tissue_id`**, not independently entered or independently updatable fields. `tissue_id` stays the authoritative value: it is the string the lab actually writes on tubes and in the spreadsheet, and it does not always parse cleanly (see §2 — blank IDs, `0` placeholders, malformed IDs such as `)G2112_D`, missing suffixes such as `OG111G-`). Storing type/index as ordinary editable columns would let them drift from `tissue_id`, and there is no well-defined value for them on rows that don't match the grammar. Generated columns avoid drift by construction and simply return null on non-conforming rows, which doubles as a cheap "does this parse?" check.

Do not add these generated columns until the naming grammar is enforced (§9). Parsing against still-dirty data means writing exception handling for malformed rows in two places — import validation and the generation expression — instead of once, during cleanup.

Recommended validation:

```text
tissue_id should begin with og_id
tissue_id should not be blank
tissue_id should not be a placeholder such as 0
```

Do not rely on `og_id + tissue` as a composite key. The live data shows many duplicate `og_id + tissue` combinations, so `tissue_id` is the better key.

### 6.3 DNA/RNA Extractions

Recommended structure:

```text
dna_extraction
  dna_id                   text primary key
  tissue_id                text not null references tissue(tissue_id)
  ext_num                  integer
  status                   text
  extraction_date          date
  ...
```

Note that `og_id` is deliberately absent, per §6.0. It is reachable through `tissue_id -> tissue.og_id` in a single indexed join, and storing it here would introduce a value that can disagree with the parent tissue's own `og_id`.

Recommended validation:

```text
dna_id should begin with tissue_id
rna_id should begin with tissue_id
```

Optional uniqueness rules:

```text
unique(tissue_id, ext_num) where valid
```

This should only be added after cleaning existing duplicate component groups.

### 6.4 Library Tables

Short-term, each existing library table can follow the same pattern:

```text
illumina_library
  illumina_library_tube_id   text primary key
  dna_id                     text not null references dna_extraction(dna_id)
  ilmn_num                   integer
  ...
```

As in §6.3, no `og_id` column. The library tables sit three levels below `sample`, so storing ancestors here would mean carrying `dna_id`, `tissue_id`, and `og_id` together with three separate drift checks, when only `dna_id` is needed to reach all of them.

Recommended validation:

```text
illumina_library_tube_id should begin with dna_id
pacbio_library_tube_id should begin with dna_id
ont_library_tube_id should begin with dna_id
rna_library_tube_id should begin with rna_id
hic_library_tube_id should begin with lysate_id
```

Long-term, the six library tables should be given a shared identity, but not a shared set of attributes. These are two different proposals and only the first one is worth doing.

**The attributes do not unify.** The six tables record genuinely different measurements, because the bench protocols are different:

| Table | Cols | Technology-specific columns |
| --- | --- | --- |
| `illumina_library` | 14 | `index_set`, `index_well`, `index_idx`, `library_qubit_conc` |
| `pacbio_library` | 18 | `dna_treatment`, `index_well`, `barcode`, `shear_femtol_id`, `shear_av_size`, `seq_femto_id`, `seq_av_size`, `library_conc` |
| `ont_library` | 12 | `library_type`, `est_loading_size` |
| `hic_library` | 15 | `prox_ligation_conc`, `purified_dna_total`, `index_set`, `library_conc`, `library_size` |
| `rna_library_ilmn` | 19 | `library_size`, `perc_product`, `library_qubit_conc`, `library_molarity`, `index_set`, `index_well`, `index_inx` |
| `rna_library_kinx` | 22 | `processing_comment`, `synthesis_date`, `part1_batch_id`, `part2_batch_id`, `synthesis_conc`, `final_qubit_conc`, `library_size`, `kinnex_primers`, `kinnex_barcode`, `pool_id`, `plate`, `plate_location` |

Only eight columns are common to all six: the tube ID, the parent ID, `*_num`, `*_status`, `library_method`, a comment field, `status_overwrite`, and `og_id`. `library_date` and `library_id` are present in five of six — `rna_library_kinx` records `synthesis_date` instead. Merging that core would also require reconciling type drift that has accumulated across the tables: `library_qubit_conc` is `text` in `illumina_library` but `real` in `rna_library_ilmn`, `library_date` is `text` everywhere, and `rna_library_kinx` uses `character varying` throughout while the others use `text`.

**The identity does unify, and that is the part with a payoff.** The concrete problem is §6.5: `sequencing` currently carries five nullable library columns, one per technology. Solving that needs a single FK target, which is a question of identity, not of attributes. A thin registry provides one without moving any data:

```text
library
  library_tube_id   text primary key
  library_type      text not null   -- illumina | pacbio | ont | hic | rna_ilmn | rna_kinx
  dna_id            text references dna_extraction(dna_id)
  rna_id            text references rna_extraction(rna_id)
  lysate_id         text references hic_lysate(lysate_id)
  check (num_nonnulls(dna_id, rna_id, lysate_id) = 1)
```

The six existing tables keep every column they have and gain a foreign key to `library(library_tube_id)`. Nothing is normalised away and no types need reconciling.

**Open question: where parentage lives.** Once `library` carries `dna_id`, the `dna_id` on `illumina_library` is describing a grandparent, which is what §6.0 says not to store. Strict consistency would move parentage entirely into the registry, leaving the technology tables holding only their technology-specific attributes.

The recommendation here is to keep the parent column on both, for two reasons. It remains a real foreign key rather than a text column reconstructed from the ID, so it cannot silently drift the way the `og_id` columns removed in §6.3 and §6.4 could — the failure §6.0 is protecting against does not apply. And it keeps direct queries such as `SELECT * FROM illumina_library WHERE dna_id = ...` working without a join, which matters for the DBeaver workflow in §7.

The cost is a genuine one and should be recorded rather than hidden: the parent is stored in two places, so the import must write both consistently, and a mismatch between `library.dna_id` and `illumina_library.dna_id` becomes possible. If the registry is adopted, decide this explicitly. Adding a foreign key from `illumina_library(illumina_library_tube_id, dna_id)` to a matching unique constraint on `library(library_tube_id, dna_id)` would make the two provably agree, at the cost of an extra composite index per technology table.

Note that the parent is expressed as three typed nullable columns with a check constraint, not as a `source_type` plus `source_id` pair. The latter is a polymorphic reference: it cannot carry a real foreign key constraint, so it would trade away exactly the guarantee §6.0 relies on. The typed form keeps all three references enforceable at the cost of two null columns per row.

This would also close two gaps that exist today:

- `sequencing.rna_library_tube_id` has no foreign key at all, while the other four library columns on `sequencing` do. It cannot be constrained, because it may point at either `rna_library_ilmn` or `rna_library_kinx`. A registry gives it one target.
- `rna_library_kinx.rna_id` has no foreign key to `rna_extraction`, unlike `rna_library_ilmn.rna_id`. This is already open in the data dictionary.

A registry primary key would additionally detect any tube ID recorded in both RNA tables, which is worth confirming before the two are given a common parent.

**One cleanup to do first.** `rna_library_ilmn` defines `kinnex_primers` and `kinnex_barcode`, which belong to the Kinnex protocol and not to Illumina RNA prep. They appear to be legacy:

- The `4.RNAIllumina` sheet has no Kinnex headers, so the import has no source to populate them from. This is the same defect already recorded for `rna_library_ilmn.perc_product` in `docs/spreadsheet_column_gap_analysis.md`.
- No view, function, or script reads them. Every consumer of the Kinnex fields — including `build_rna_kinx_samplesheet_rows` — reads `rna_library_kinx`.

They should be confirmed empty against the live database and then dropped. If they hold values, that is historical Kinnex data sitting in the wrong table and needs to be migrated rather than deleted.

### 6.5 Sequencing

Sequencing should not need five nullable library FK columns.

Preferred long-term model:

```text
sequencing_run
  sequencing_run_id   bigint generated identity primary key
  run_id              text not null
  instrument          text
  run_date            date

sequencing_run_library
  sequencing_run_id   bigint not null references sequencing_run(sequencing_run_id)
  library_tube_id     text not null references library(library_tube_id)
  lane                text
  cell_id             text
  seq_type            text
  primary key (sequencing_run_id, library_tube_id)
```

This matches the real-world relationship: runs contain libraries, and libraries can appear in sequencing runs.

## 7. DBeaver Usability

The current key strategy partly exists because users inspect base tables directly in DBeaver. That is a real workflow need, but it does not have to dictate the physical key design.

Better options:

### Option A: Human-readable display columns

Keep columns such as:

- `og_id`
- `human_tissue_id`
- `human_extraction_id`
- `human_library_id`

These can be unique and visible without being the primary key.

### Option B: Browse views

Create views specifically for DBeaver users:

```text
v_tissue_browse
v_dna_extraction_browse
v_library_browse
v_sequencing_browse
```

Example browse view:

```sql
CREATE VIEW v_tissue_browse AS
SELECT
  s.og_id,
  t.tissue_id,
  t.tissue,
  t.tissue_type_code,
  t.tissue_index,
  t.freezer,
  t.shelf,
  t.rack,
  t.box,
  t.comment
FROM tissue t
JOIN sample s ON s.og_id = t.og_id;
```

These views are also how ancestor context is recovered once the redundant columns of §6.0 are gone. Because a plain view is inlined by the query planner, selecting `og_id` through the view costs the same as writing the join by hand:

```sql
CREATE VIEW v_dna_extraction_browse AS
SELECT
  t.og_id,
  d.tissue_id,
  d.dna_id,
  d.ext_num,
  d.status,
  d.extraction_date
FROM dna_extraction d
JOIN tissue t ON t.tissue_id = d.tissue_id;
```

A view can be used anywhere a table can, including as a join target in larger queries and as a filter target such as `WHERE og_id = 'OG123'`. Note that multi-table views like these are for reading only — nightly import code should still insert and update against the base tables.

This gives users readable rows without forcing every table to repeat parent identifiers.

### Option C: DBeaver virtual columns or saved SQL views

DBeaver can work well with views or saved queries. If base-table browsing is the main reason for descriptive PKs, curated browse views are the cleaner compromise.

## 8. Suggested Naming Convention

Use clear separation between internal keys and readable identifiers:

| Purpose | Naming pattern | Example |
|---|---|---|
| Lab/source ID | current spreadsheet ID name | `tissue_id`, `dna_id` |
| Optional future internal PK | `<entity>_pk` | `tissue_pk` |
| Parent FK | parent spreadsheet ID name | `og_id`, `tissue_id`, `dna_id` |
| Existing project ID | keep existing name | `og_id` |

Important: because the current database already uses names like `tissue_id` for human-readable IDs, a migration will need careful naming.

Safer transition naming:

```text
existing tissue_id       remains temporarily as readable ID
new tissue_pk            internal generated primary key
future human_tissue_id   optional renamed readable ID
```

## 9. Migration Approach

Do not change all keys at once. For the current workflow, the migration should focus on validation and constraints first, not replacing keys.

Recommended phased approach:

1. Document the expected naming grammar for each lab table.
2. Add nightly import checks that reject blank, `0`, malformed, or parent-mismatched IDs.
3. Add reports for existing exceptions.
4. Clean existing malformed IDs in the spreadsheet/source workflow.
5. Confirm empty and then drop columns that have neither a spreadsheet source nor a consumer, such as `rna_library_ilmn.kinnex_primers` and `rna_library_ilmn.kinnex_barcode` (see §6.4).
6. Add or validate foreign keys between current text IDs.
7. Add supporting indexes on FK columns.
8. Add optional uniqueness rules on component fields only where the data supports them.
9. Once the naming grammar is enforced, add generated columns (e.g. `tissue_type_code`, `tissue_index`) parsed from lab IDs for queryability — do not add these earlier, since they will silently null out on still-malformed rows (see §6.2).
10. Create browse and quality-control views for DBeaver users.
11. Introduce the thin `library` registry table (§6.4) and repoint `sequencing` at it (§6.5), leaving the six library tables and their columns in place.
12. Consider generated surrogate keys later only if a new application, ORM, or integration requires them.

This lets the database become cleaner without fighting the spreadsheet workflow.

## 10. When Composite Keys Still Make Sense

Composite keys can still be useful when all of these are true:

- The fields are immutable.
- The fields genuinely define the row.
- The fields are not expected to be corrected or renamed.
- The table is mostly append-only.
- The key is not repeatedly referenced by many child tables.

This often fits bioinformatics result tables better than lab workflow tables.

Examples where composite keys may remain reasonable:

- Analysis result tables.
- Import staging tables.
- Run output tables.
- File inventory tables where the natural path/run/lane combination is stable.

## 11. Decision Summary

Recommended direction:

- Keep the current spreadsheet/lab IDs as the primary or authoritative business keys for now.
- Do not use wide composite primary keys as the main lab-side pattern.
- Do not introduce surrogate keys as the first cleanup step.
- Add validation so each child ID correctly extends its parent ID.
- Store one FK per table, pointing at the immediate parent only. Reach higher ancestors by joining, not by duplicating columns.
- Give the library tables a shared identity through a thin registry, not a shared set of attributes. Their columns differ by protocol and should stay where they are.
- Build browse views so DBeaver users retain readability.
- Use explicit foreign keys and indexes for joins.

This fits the current Excel-driven process while still improving database integrity.
