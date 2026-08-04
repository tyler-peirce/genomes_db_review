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
- Keep the explicit parent columns, such as `og_id`, `tissue_id`, `dna_id`, and `rna_id`, even if they repeat part of the ID.
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
  ...
```

Example:

```text
tissue_id:  OG123G
og_id:      OG123
tissue:     Gills
```

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
  og_id                    text not null references sample(og_id)
  ext_num                  integer
  status                   text
  extraction_date          date
  ...
```

Recommended validation:

```text
dna_id should begin with tissue_id
rna_id should begin with tissue_id
og_id should match the parent tissue's og_id
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
  og_id                      text not null references sample(og_id)
  ilmn_num                   integer
  ...
```

Recommended validation:

```text
illumina_library_tube_id should begin with dna_id
pacbio_library_tube_id should begin with dna_id
ont_library_tube_id should begin with dna_id
rna_library_tube_id should begin with rna_id
hic_library_tube_id should begin with lysate_id
og_id should match the upstream sample
```

Long-term, consider a unified `library` table:

```text
library
  library_tube_id    text primary key
  library_type        text not null
  source_type         text not null
  source_id           text not null
  status              text
  library_date        date
  ...
```

Subtype-specific tables can remain for technology-specific fields.

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
  t.tissue_type,
  t.tissue_index,
  t.freezer,
  t.shelf,
  t.rack,
  t.box,
  t.comment
FROM tissue t
JOIN sample s ON s.og_id = t.og_id;
```

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
5. Add or validate foreign keys between current text IDs.
6. Add supporting indexes on FK columns.
7. Add optional uniqueness rules on component fields only where the data supports them.
8. Create browse and quality-control views for DBeaver users.
9. Consider generated surrogate keys later only if a new application, ORM, or integration requires them.

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
- Keep explicit parent FK columns even if they repeat information embedded in the ID.
- Build browse views so DBeaver users retain readability.
- Use explicit foreign keys and indexes for joins.

This fits the current Excel-driven process while still improving database integrity.
