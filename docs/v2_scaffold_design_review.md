# Review: `v2` Lab Schema Scaffold

Revision 2: 2026-10-05 — see §0. Revision 2.1: 2026-10-06 — Phase V.2 resolution, §0.10.
Date: 2026-08-05 (revision 1)
Scope: `design/v2/deploy/create_v2_lab_tables.sql` and its revert/verify pair, read against
`database_review.md`, `docs/lab_key_strategy.md`, `docs/data_dictionary.md`,
`docs/spreadsheet_column_gap_analysis.md`, the `schema/` baselines, the live workbook, and
`name_convert.py` / `import_data.py` / `queries.py` in the sibling `OceanOmics-Database` repo.
Status: Revision 2 complete (§0) — re-reviewed against the live catalog 2026-10-05, validated on
a throwaway cluster, not deployed. Findings reflect the eleven
decisions taken 2026-08-05 (§2); all four open questions are closed (§7); all eleven steps of
§5 are implemented. One earlier finding was withdrawn on re-measurement — see the correction
note in F4a.

## 0. Revision 2 — re-review against the live catalog, 2026-10-05

Revision 1 is retained below exactly as written. It is the record of why the scaffold has the
shape it has, and nothing in this section supersedes its findings F1–F13 or its eleven
decisions. What this section adds is the result of re-reading the DDL against the **live
catalog** rather than against revision 1's own analysis, which is Phase V.1 of
`database_review.md`.

**Why it was required.** The DDL was designed, built and constraint-tested on 2026-08-05 and
not touched again. The live database kept moving: migrations `017` through `034` landed,
including the entire LCA rebuild. Revision 1 could not have known about any of it, so its
sign-off had quietly expired. The owner's instruction on 2026-10-05 was not to promote any of
this to numbered migrations on revision 1's authority.

**Method.** Two new scripts, both read-only and both kept in the repo because the questions
they answer recur:

- `scripts/diff_v2_against_live.py` — column-by-column diff of the `v2` DDL against
  `information_schema`, with every difference classified against the finding that explains it.
  Its exit criterion is zero unexplained differences. Run it before Phase V.3.
- `scripts/audit_v2_dependents.py` — the dependent views, triggers and functions, read from
  `pg_depend`, `pg_rewrite`, `pg_trigger` and `pg_proc`. Run it again at Phase V.5.

Everything was validated on a throwaway PostgreSQL 14.24 cluster loaded from a `pg_dump` of
the current live database: all six deploy files applied, all six verify scripts passed, the
full revert sequence returned the cluster to baseline, forward re-apply succeeded, and the
backfill ran twice to identical row counts.

### 0.1 What the re-review found

Nine defects. Three would have failed outright; the rest would have lost data quietly, which
is worse.

| # | Defect | Consequence had it shipped |
|---|---|---|
| 1 | **40 columns** added by migrations `017`–`026` absent from the `v2` DDL | Silently dropped at cutover. 34 on `mitogenome_data` (depth, trna-advisory, order-variant, annotation-integrity families), `content_hash` + `taxon_rank_db` on `lca` and `lca_raw_results`, `validated_rank` + `lca_genus` on `lca_validation` |
| 2 | `lca.top_confidence_score` and `lca_raw_results.confidence_score` declared `real` | **Backfill aborts.** Migration `022` widened both to `double precision` because `real` underflows below ~1.18e-38 and HiFi hits reach 5.27e-163. 30 live rows raise `value out of range: underflow` on a `::real` cast |
| 3 | `blast_filtered_lca.taxon_id` declared `integer` | **1,009 rows rejected.** `022` made it `text` because those rows hold semicolon-separated multi-taxon lists (`104759;596308;627028`). Not an overflow — the largest single value is well inside `int4`, which is why it reads as safe |
| 4 | `v2.lca_raw_results` primary key keyed on `lca_run_date` | **Not satisfiable by live data:** 33 of 46,644 rows collide, because one BLAST accession can yield several HSPs in a run (same accession and run date, different `percent_match`). `017` made row identity content-addressed for exactly this reason |
| 5 | `content_hash` is `NOT NULL` and in two keys, with no trigger to fill it | Every insert outside the backfill fails |
| 6 | `v2.mitogenome_data.annotation` declared `NOT NULL` | 374 of 2,349 rows quarantined for a constraint no finding asked for and live does not enforce. They are simply not yet annotated — all 374 have every annotation-derived field null, all 1,975 annotated rows have every one populated |
| 7 | Registry guards in the lab backfill test `library_tube_id` alone, while the FK is on `(library_tube_id, parent_id)` | **Backfill aborts** on current data — tube ID `0` is shared by an Illumina and a PacBio library with different parents |
| 8 | Attempt-key ties filtered out with no quarantine record | **100 rows silently dropped** — neither loaded nor quarantined. The one outcome decision 6 exists to prevent, and not what `create_v2_lab_tables.sql`'s own comment says happens ("those rows quarantine for the lab to renumber") |
| 9 | `v2` carries neither `content_hash` nor the `lca_set_content_hash` trigger; `set_updated_at` has no `v2` counterpart | Migration `017`'s content-addressing silently reverted |

Items 1–6 and 9 are fixed in `design/v2/deploy/create_v2_lca_tables.sql`, 7–8 in
`design/v2/backfill_v2.sql`, each with the reasoning at the point of change.

**Four more came out of re-checking the workbook (§0.8), and they are a different class** —
every one is a `name_convert_v2.py` mapping rather than DDL, and every one presents as a silent
NULL rather than an error:

| # | Defect | Consequence |
|---|---|---|
| 10 | `illumina_library.library_plate_well` maps to `Library Plate Well`, renamed to `Final Library Plate Well` | 1,078 populated rows dropped — a regression in the fix for §4.1 |
| 11 | `rna_library_ilmn.library_size` maps to `cDNA Library Size (bp)`, removed from that sheet | column unsourced |
| 12 | `rna_library_kinx.synthesis_conc` maps a `\r\n` where the header has a bare `\n` | 110 workbook values; live is 0 of 189. The August "FIXED" note describes this bug and its fix reproduces it |
| 13 | `4.HiCLysate`'s `Proximity Ligation yield (ng)` (383 of 386 rows) is mapped nowhere, and `v2` generates yield from a column populated on 77 | 306 rows generate NULL where a measurement exists |

Plus four new lab headers with no mapping and no `v2` column: `Extract Plate name Or tube`
(274), `Extract Plate Well` (266), `Final Plate Name` (135), `Final Plate Well` (135).

### 0.2 Two findings that were right about the source and wrong about the database

This is the pattern worth carrying into future reviews, because both were careful pieces of
analysis that nonetheless reached a conclusion the database contradicts.

**§4.4 — "RNA tube-ID overlap: none".** Measured on the workbook, this is correct: the suffix
conventions (`_IL` / `_dIL` for Illumina RNA, `_KL` for Kinnex) do not collide, so a shared
registry primary key is safe. Measured on the **live tables**, 24 `_KL` tube IDs appear in
*both* `rna_library_ilmn` and `rna_library_kinx` with the same parent `rna_id` — because the
importer writes Kinnex rows into both RNA tables. The same artefact also duplicated
`kinnex_barcode` and `kinnex_primers` onto `rna_library_ilmn`, where all 16 populated rows
carry values identical to their Kinnex row. So the registry key is sound in principle and
unsatisfiable against today's rows. Handled by quarantining the duplicates rather than
widening the key to `(library_tube_id, library_type)`, which would preserve rows that should
not exist; the real fix is in the importer, before cutover.

**F4 — `dna_extraction.ratioqubit_nanodrop` is "dead on both ends".** Both halves are still
true of the import path: the mapped header does not exist in the workbook and `queries.py`
never inserted the field. But the column holds **987 populated rows** of 2,636, 277 distinct
values from -0.2 to 6.96 — real measurements that arrived by some other route, most likely
hand entry through DBeaver. Revision 1 asked "does anything write this?" and stopped. The
question that decides whether a column can be dropped is "is there anything in it?". Dropping
it would have destroyed 987 hand-entered measurements that exist nowhere else — the F4a
failure mode reached from the opposite direction. **Kept.**

The general lesson: an analysis of the source is not an analysis of the destination. Both
findings would have survived any amount of re-reading of the documents; only querying the
database exposed them.

### 0.3 Column dispositions

Every live column absent from the `v2` DDL now falls into one of three buckets, and
`scripts/diff_v2_against_live.py` enforces that the third is empty:

- **Intentional removal**, citing a revision 1 finding — F1 `og_id` on child tables, F2
  `og_num`, F4/F5 the seventeen `sample` columns, F6 the five `sequencing` tube-ID columns.
- **Added by a migration after 2026-08-05** — the 40 columns of item 1 above. All restored.
  A migration that was worth writing is not something a redesign gets to discard in silence.
- **Added by the lab after 2026-08-05.** Seven columns. Six were already documented as
  deliberate `DROPPED:` notes in the DDL, and re-measurement confirms all six:
  `sample.illumina_public` (0/3294 populated, against `hifi_public`'s 8),
  `tissue.field_id` (7202 of 7241 rows match `sample.field_id` exactly; the 27 that differ are
  the spreadsheet formula returning `0` against a null), the two `rna_library_ilmn` Kinnex
  columns (§0.2), and `rna_library_kinx.created_at`/`updated_at` (dropped on consistency
  grounds — they exist on one table of twelve). The seventh is `ratioqubit_nanodrop`, which
  was wrong; see §0.2.

  Note the `created_at`/`updated_at` decision also retires the `set_updated_at` trigger. That
  is correct but it must not lapse unnoticed: the function has to be **pinned to `public`** at
  cutover so it cannot follow the `search_path` into a `v2` table with no such column.

### 0.4 Dependents: the audit was too narrow, and functions were never in it

`docs/v2_cutover_dependencies.md` is corrected in place. The four substantive changes:

1. **The audit covered the twelve lab tables; `v2` recreates seventeen.** Ten non-snapshot
   views read the seventeen. **`mitogenome_submission_view` was never audited and it breaks** —
   it selects `m.og_num` straight from `mitogenome_data`, which F2 removes. It has been
   reworked three times since revision 1 (`027`, `028`, `029`). **This is the one piece of DDL
   this re-review identified and did not write**; it needs a `v2` equivalent or a rewrite
   before Phase V.5.
2. **There are two writable views, not one.** `embargo_assignment_view` was classified as a
   plain reader of seven `sample` columns. It carries `trg_embargo_assignment_view_upd`, an
   `INSTEAD OF UPDATE` trigger that writes to `sample`.
3. **Eleven of this database's own functions follow the cutover silently.** None pins a
   `search_path`; the database- and role-level settings are both unset and the session default
   is `"$user", public`. Six are `build_*_samplesheet*` functions generating Nextflow
   samplesheets from `sample` and `sequencing` — and `sequencing` loses its five library
   tube-ID columns under F6. Dispositions (pin / follow / rewrite) are recorded in
   `scripts/audit_v2_dependents.py`, which reports any function lacking one. The pinning
   `ALTER FUNCTION`s are Phase V.5 work: V.1 changed no live object.
4. **`CREATE OR REPLACE VIEW`, not `DROP` + `CREATE`.** Revision 1's cutover document said the
   nine cutover-neutral views needed "no DDL" because a `search_path` swap would resolve them,
   which is wrong — views bind to OIDs — and the correction then over-prescribed a drop.
   `CREATE OR REPLACE` rebinds through the `search_path` while preserving grants, dependent
   views and both `INSTEAD OF` triggers, which a `DROP` silently destroys.

### 0.5 Validation, against revision 1's numbers

**Source workbook: `OceanGenomes_Database_261006.xlsx`** (2026-10-06, 5.3 MB). Naming it
matters — see §0.8. An earlier pass of this revision used
`OceanGenomes_Databasev5.Feb24_260804.xlsx`, the August workbook, and the importer figures
below were wrong as a result.

Backfill, which reads the live database rather than the workbook:

| | revision 1 (2026-08-05) | revision 2 (2026-10-06) |
|---|---|---|
| Twelve lab tables loaded | 20,881 | **21,926** |
| Five LCA tables loaded | n/a — no backfill existed | **298,076** (0 quarantined) |
| Quarantined | 1,004 | **870** |

`import_v2.py`, which reads the workbook, against an empty `v2`:

| | revision 1 | Aug workbook | **Oct workbook** |
|---|---|---|---|
| Twelve lab tables loaded | 20,881 | — | **21,347** |
| Rejected outright | — | — | **243** |
| Degraded (loaded, one field nulled) | — | — | **1,137** |
| Quarantine rows total | 1,004 | 1,049 | **1,292** |

**The quarantine count is up 23% on the August workbook, and that is a finding, not noise** —
Phase V.1 item 6 said to treat it as one. Four drivers, in order of size:

- `sample` `type_cast` **584 → 761** (+177). The largest single movement and the one to chase
  first: 761 of 3,294 sample rows now carry at least one field that will not convert.
- `sequencing` `foreign_key` **31 → 68** (+37). Rows pointing at a library that does not exist,
  more than doubled.
- `rna_library_ilmn` `type_cast` **4 → 29** (+25).
- `rna_library_ilmn` `unique` 53 → 56, and it remains by far the worst table in relative
  terms: **69 of 334 rows rejected outright, only 265 loaded.**

The backfill's own figures above are unaffected by the workbook version, since it reads the
database.

The attempt-key ties are worth watching rather than filing, because they are growing: revision
1 cites "5 of 2,223" on `dna_extraction` and "53 of 321" on `4.RNAIllumina` as the worst case.
Measured now: `rna_library_ilmn` **107 of 389**, `dna_extraction` 49, `hic_lysate` 9,
`ont_library` 4, `pacbio_library` 3, `illumina_library` 1, `rna_library_kinx` 1. The lab keeps
creating them, so this needs a standing report, not a cleanup.

### 0.6 `import_v2.py` cannot run after the backfill — and this is a cutover blocker

Phase V.1 item 6 said to re-run `import_v2.py` against the current workbook. Doing so exposed
a defect that only appears in the exact combination Phase V creates, which is why nobody had
seen it.

**Against an empty `v2` the importer completes.** It quarantines 1,292 rows against the current
workbook — up 23% on the August workbook and up 29% on revision 1's 1,004; see §0.5 for the
drivers. "Completes" is not "is fine".

**Against a backfilled `v2` it aborts** with
`duplicate key value violates unique constraint "dna_extraction_attempt_key"`. That is the
sequence Phase V actually performs: V.4 backfills `v2` from `public`, and V.2 requires the
importer to be the live path before the swap. So the first nightly run after the backfill fails.

The mechanism, traced on `(tissue_id, ext_num) = (OG2111G, 1)`:

1. `public.dna_extraction` holds **three** rows for tissue `OG2111G`: `OG2111G_D2` (#2),
   `OG2111G_D` (#1) and `OG2111E_D` (#1). The last two collide on the attempt key, and
   `OG2111E_D`'s own prefix disagrees with the tissue it is filed under — one of 48 such rows.
2. The backfill breaks the tie **by lexicographic tube ID**, so `OG2111E_D` wins and
   `OG2111G_D` is quarantined. The tie-break is arbitrary by construction, and here it seats
   the suspect row and rejects the one the workbook carries.
3. The workbook supplies `OG2111G_D` for that attempt. The importer upserts
   `ON CONFLICT (dna_id)` — `dna_id` being the primary key — which does not match
   `OG2111E_D`. The attempt-key `UNIQUE` then rejects the insert.
4. The whole run aborts in one transaction, so **one bad pair blocks every table**.

There are **48 colliding `(tissue_id, ext_num)` pairs across 97 rows** in live
`dna_extraction`, so this is not a single-row curiosity.

Three things follow, and none of them is a `v2` DDL change — this is Phase V.2 work, in the
sibling repo, and it needs a decision rather than a patch:

- **The backfill should not seat an arbitrary winner.** Preferring the lexicographically-first
  tube ID is indefensible once you see it choose a row whose prefix contradicts its parent.
  Better options are to quarantine *both* sides of a tie, so nothing is seated until the lab
  resolves it, or to prefer the row the workbook still contains. The current behaviour is
  recorded in `backfill_v2.sql` and flagged there.
- **`ON CONFLICT (primary_key)` is the wrong conflict target for a table with an attempt key.**
  The importer can only ever reconcile rows that agree on `dna_id`, and tube IDs are mutable —
  which is how the database accumulates rows the workbook no longer has.
- **The importer must not abort the batch on one constraint violation.** Its own design note
  says a row violating a `v2` constraint "goes to `v2.import_quarantine` with the reason". That
  is true of the checks it performs itself and not true of a violation the database raises, and
  the difference is a failed nightly run versus one quarantined row.

This also qualifies the V.2 instruction "importer changes land before the swap, never after".
They have to, and as it stands they cannot: the importer does not survive contact with a
backfilled schema.

### 0.7 Build order changed

Steps 5 and 6 are swapped: **LCA tables before the summary view.** Repointing `v2.summary` at
`v2.lca_validation` makes the summary view depend on them. Recorded in
`design/v2/README.md`, in the `-- requires:` headers, and in Phase V.3. Deploying in the old
order now fails at deploy time rather than resolving to the wrong schema, which is the
outcome to want.

### 0.8 Assumptions re-checked against the current workbook

Every workbook-derived claim in revision 1 was re-measured against
**`OceanGenomes_Database_261006.xlsx`** (2026-10-06). An earlier pass of this revision used the
August workbook, `OceanGenomes_Databasev5.Feb24_260804.xlsx`, which was the same mistake the
whole re-review exists to catch, one level up: validating a design against a stale source.
**Both the workbook filename and its date belong in any figure quoted from it.** The workbook
is not under version control and its name carries the date, so this is cheap to get right and
invisible when got wrong.

All fourteen sheets still exist with the same names. Every sheet has grown; `1.MetaData` is now
3,294 rows, matching live `sample` exactly.

#### Claims that re-measure as still true

- **F5 / decision 9 — the six technology columns hold Y/N only.** Still exactly `{Y, N}` in
  October, and the counts barely move (`ilmn` 1522Y/187N, `hifi` 284/1476, `hic` 267/1479,
  `nano` 34/1463, `rna` 167/1474, `ilrna` 169/1470 → **166/1473**). `boolean` is right.
- **F13 — proximity-ligation yield is conc × 40.** Exact on all 77 rows where both are
  populated: min, median and max of the ratio are all 40.000. The formula in
  `v2.hic_lysate.prox_ligation_yield` is correct. Its *direction* is not — see below.
- **Attempt-key ties in the workbook are stable:** `3.DNAExtractions` 5 → 4,
  `4.RNAIllumina` 9 → 9, `4.HiCLysate` 1 → 1, `4.RNAkinnex` 1 → 1. Revision 1's "5 of 2,223"
  and "8 repeated IDs on 4.RNAIllumina" still hold. Note these are *workbook* ties; the much
  larger figures in §0.1 item 8 (107 on `rna_library_ilmn`, 49 on `dna_extraction`) are *live
  database* ties and come from a different measurement.
- The multi-alternative mappings (`sample.og_id` ← `Specimen ID`/`OGID`, `sample.field_id` ←
  `Field Identifier`/`Field_Identifier`) still resolve.

#### Mappings that worked in August and are dead now

Checked by resolving every `(table, column) → header` pair in `name_convert_v2.py` against the
October headers, rather than by running the importer — a dead mapping produces a silent NULL,
so running the importer does not reveal it.

| v2 column | mapped header | what happened | rows affected |
|---|---|---|---|
| `illumina_library.library_plate_well` | `Library Plate Well` | renamed to **`Final Library Plate Well`** | **1,078 populated** |
| `rna_library_ilmn.library_size` | `cDNA Library Size (bp)` | header removed from `4.RNAIllumina` entirely (it survives on `4.RNAkinnex`) | column now unsourced |

The first is a regression in the fix for §4.1. `library_plate_well` was added to `v2`
*specifically* because 1,523 rows of hand-entered plate positions were being dropped nightly;
the header has since been renamed and the new mapping no longer matches, so `v2` would drop
1,078 of them again. **F4a's failure mode, inside the fix for F4a.**

#### New headers with nowhere to go

Added since August, populated, and mapped to nothing — so `v2` would drop them:

| sheet | header | populated |
|---|---|---|
| `3.DNAExtractions` | `Extract Plate name Or tube` | 274 |
| `3.DNAExtractions` | `Extract Plate Well` | 266 |
| `4.RNAIllumina` | `Final Plate Name` | 135 |
| `4.RNAIllumina` | `Final Plate Well` | 135 |

These are the same *kind* of column §4.1 catalogued and `v2` adopted — hand-entered plate and
well positions. The lab is evidently still extending its plate tracking, which means §4.1 is
not a closed list and will need re-running before each promotion, not once.

#### Two defects that have nothing to do with the workbook version

Both would have been found against either workbook. They surfaced only because this pass
checked mappings against headers instead of trusting the importer to complain.

1. **`rna_library_kinx.synthesis_conc` has never worked, and the August "fix" did not fix it.**
   `name_convert_v2.py` records this under FIXED: "the real header contains an embedded CRLF:
   `cDNA Concentration \r\n(end of section 1 conc)`". The real header contains a bare **LF**
   (`0x0a`), in the August workbook and the October one alike. The corrected mapping specifies
   `\r\n`, so it still never matches. The workbook holds **110 populated values** and live
   `rna_library_kinx.synthesis_conc` is **0 of 189**. Revision 1 diagnosed the bug correctly and
   then wrote a fix that reproduces it.

2. **WITHDRAWN 2026-10-06 — see §0.10.** The yield column is a formula on every row, and the
   306 "recorded yields" below are all 0.0. The finding is kept as written so the error is
   visible.

   **`4.HiCLysate`'s `Proximity Ligation yield (ng)` — 383 of 386 rows — is mapped nowhere, and
   `v2` derives that value from a column with 77.** `v2.hic_lysate.prox_ligation_yield` is
   `GENERATED ALWAYS AS (prox_ligation_conc * 40)`, and `prox_ligation_conc` maps to
   `Proximity Ligation Conc. (ng/uL)`, which is populated on 77 rows. So **306 rows have a
   recorded yield and will generate NULL.** The derivation is exactly right and pointed the
   wrong way: since yield = conc × 40 holds exactly, `conc = yield / 40` recovers all 306.
   Either map the yield column and generate `conc` from it, or fall back to `yield / 40` when
   `conc` is absent.

   §4.1 also mis-states this sheet's counts — it lists `Proximity Ligation prep date` at 356
   rows (actually **82**) and `Proximity Ligation Conc. (ng/uL)` at 80 (actually **77**), and
   omits the yield column altogether, which is the most-populated of the three.

#### What this means for Phase V.3

`scripts/diff_v2_against_live.py` compares the DDL to the database. Nothing compares
`name_convert_v2.py` to the workbook, and that is the gap all four findings above came through.
Three of the four are invisible from the database alone, because a dead mapping and a dropped
column both look like a NULL. **A mapping-vs-workbook check belongs alongside the column diff
before V.3 promotes anything**, and `import_v2.py`'s unmatched-header report is not a substitute:
it lists headers with no mapping, and says nothing about a mapping with no header.

### 0.9 What revision 2 did not change

- **Decisions 1–11 all stand.** Item 6 above is the only place where a `NOT NULL` was relaxed,
  and that constraint was never one of the decisions.
- **Findings F1–F13 all stand**, with the two qualifications in §0.2.
- **No live object was touched.** Everything was validated against a throwaway cluster; the
  live database was read and never written. `bin/check_drift.py` output is unchanged.
- **`sql/033_catchup_core_views.sql` still carries the uncorrected "no DDL is needed"
  sentence** in its header comment. Deliberate: `033` is applied and ledgered, and
  `docs/database_change_checklist.md` forbids editing an applied file because
  `bin/apply_migrations.py` refuses to continue when a SHA-256 stops matching. A comment is
  not worth breaking the ledger for; `docs/v2_cutover_dependencies.md` is the correction of
  record.

### 0.10 Revision 2.1 — Phase V.2 resolution, 2026-10-06

§0.6's three decisions were taken by the owner, and §0.8's gap now has a tool.
`database_review.md` Phase V.2 holds the full outcome and figures. The points that change
this document:

- **§0.6 is resolved.**
  - **The backfill seats the workbook's side of a tie.** If the workbook carries none of the
    tied rows, or more than one, the backfill seats none of them.
  - **The workbook wins at import.**
    - A seated row the workbook no longer carries is displaced into `v2.v_quarantine_displaced`.
    - It is kept instead if libraries or sequencing hang off it, and the workbook row is
      quarantined.
    - A renumber or a swap of two tubes applies in one upsert, because the attempt keys are
      now deferrable.
  - **A violation the database raises quarantines one row.** It no longer aborts the batch.
  - **Tested on a local cluster.** With `OG2111E_D` seated in `(OG2111G, 1)` after a backfill,
    the importer now completes and seats `OG2111G_D`.
- **§0.8 has a tool:** `scripts/check_v2_mappings.py` runs a mapping-versus-workbook check.
  - It reproduced the three header defects.
  - It found four hand-entered headers this section missed.
  - Every column it allows is either a measured formula or an owner decision.
- **§0.8 item 2 is withdrawn.**
  - Checked cell by cell, `Proximity Ligation yield (ng)` is `=IF(R="NA","NA",R*40)` on all
    386 rows of `OceanGenomes_Database_261006.xlsx`, with no typed values.
  - It was counted as 383 populated because pandas reads cached formula results, and an empty
    concentration makes the formula return 0.0.
  - The F13 design stands as built: yield is generated from concentration, and the
    concentration (77 values) is the measurement. Inverting it, as recommended, would have
    stored 306 false zeros.
  - The method lesson is the same as §0.2, one level down: a populated count does not show a
    column is data. Check whether the values are typed or computed.
- **F13 is qualified, not reversed.** The lab still records proximity-ligation concentration on
  `4.HiCLibrary` (264 numeric values, against 77 on `4.HiCLysate`).
  - By owner decision, those values load into the legacy `hic_library.prox_ligation_conc` until
    the lab moves to the lysate sheet.
  - `v_hic_library_browse` already keeps the two apart as `prox_ligation_conc` and
    `prox_ligation_conc_legacy`.

- **F7's attempt key was wrong on two tables, and this changes a claim made since August.**
  - `4.RNAIllumina` and `4.ONT` number attempts per prep method, not per parent. On every
    parent with more than one method, `#` restarts at 1 for each method (51 RNAs; 3 DNAs).
  - The "53 of 321 on 4.RNAIllumina, the worst case" cited for the attempt key since revision 1,
    and the 107 live "ties" in §0.5, were these pairs, not numbering mistakes.
  - Both keys are now `(parent, library_method, #)`. On the other seven tables the key stands as
    designed: every parent with several methods keeps counting across them.
  - On a copy of live, tied rows quarantined by the backfill fell from 235 to 65, and every one
    that remains is a tube renamed or mistyped in live.

## 1. Summary

The Phase 0 work is solid — baseline export, live inventories, Sqitch adoption, gap analysis.
The parallel-schema approach is the right mechanism, and it is what makes the staged
migrations in `database_review.md` §9 skippable: Phases 3–6 are staged the way they are to
manage risk on *populated* tables, and none of that risk exists on an empty schema.

The problem is what was built with it. `create_v2_lab_tables.sql` is a **structural clone of
the live tables plus 12 new columns**. Defects the review and the key strategy already
identified are reproduced in tables that hold no data and have no consumers — the moment when
fixing them is free. Most directly, it contradicts `docs/lab_key_strategy.md` §6.0, added in
the same working set, by carrying regexp-derived `og_id` columns on nine of twelve tables.

A separate re-review of the workbook (§4) found the gap analysis was itself incomplete: a
further **14 columns of hand-entered lab data** are dropped by the nightly import, and 17
`sample` columns are fed from a *derived* Excel sheet.

## 2. Decisions taken (2026-08-05)

| # | Decision | Effect on this review |
|---|---|---|
| 1 | `lca_new` / `lca_*_new` tables are **out of scope** — separate concurrent work producing a fresh dataset. Do not modify. | F9 no longer proposes unifying their naming. But the LCA/mitogenome tables **do** still need v2 equivalents built to the new design; added as §5 step 11. |
| 2 | **Keep `status_overwrite`.** The lab uses it to mark which row is reported in `summary`. | F4 downgraded: it is not dead, it is *starved*. The fix is in `name_convert.py`, not the schema. See F4a. |
| 3 | The `v2` schema and the `v2_` prefix are **one and the same thing** — a schema named `v2` holding tables with their final names (`v2.sample`, `v2.tissue`). | F9 resolved. Cutover becomes a `search_path` / `ALTER SCHEMA` swap with no renaming. |
| 4 | **Library registry is in scope.** | F6 becomes a build item, not an option. Strongly reinforced by §4.3. |
| 5 | The workbook's `Summary` sheet is fully derived; **do not reproduce it from the spreadsheet**. Rebuild it as a database view. | F5 widens from 2 columns to 17. See F5 revised. |
| 6 | Rows violating new NOT NULL / FK / type constraints go to a **quarantine table** for fixing at source. | Added as §5 step 9 with a concrete shape. |
| 7 | RNA tube-ID overlap between the two RNA library tables was unknown. | **Answered — zero overlap.** See §4.4. |
| 8 | **Capture both `Latest` and `Status Overwrite`**; `Latest` is what the Summary sheet looks up, `Status Overwrite` is believed to be used elsewhere. One can be dropped later. | Partly resolved by evidence: `Latest` turns out to be 100% derivable and needs no column. See F4a. |
| 9 | Keep `ilmn`, `hifi`, `hic`, `nano`, `rna`, `ilrna`, `workflow`, `priority` on `sample`. | F5 open question closed. Eight columns survive from `Summary`; nine existing `sample` columns go, plus the two the scaffold was about to add. |
| 10 | `Manual/ Automated Method` is **one shared vocabulary** across tables. | Becomes a lookup table with a `check`/FK. Immediately catches a live typo — see F12. |
| 11 | `hic_lysate` proximity-ligation data and `hic_library.prox_ligation_conc` are **the same value captured in two spots** — measured at the lysate stage and transcribed onto the library sheet; the lysate sheet is newer and so sparser. **Keep both for now**, remove one later. | Confirmed empirically (50/52 agreement; all conflicts predate the lysate column; the value exists before any library does). Lysate column is current, library column becomes legacy read-only. See F13. |

## 3. Findings on the scaffold

### F1. Regexp-derived `og_id` columns contradict `lab_key_strategy.md` §6.0

Severity: High

Nine v2 tables carry a generated `og_id`: `dna_extraction` and `rna_extraction` (from
`tissue_id`), the five library tables (from `dna_id` / `lysate_id` / `rna_id`), and
`sequencing` (from `sequencing_id`). All use a regexp capture such as
`regexp_replace(dna_id, '^([^0-9]*[0-9]+).*$', '\1')`.

§6.0 rejects exactly this, on three grounds that all apply:

- It is a **grandparent or great-grandparent column** — `v2.illumina_library.og_id` is three
  levels up.
- It is **parsed from the ID**, which §6.0 rules out because "the delimiters are not uniform
  between levels."
- It **cannot carry a foreign key**, and none of the nine does.

`v2_hic_lysate` is the tell: it is the one child table without an `og_id`, and nothing about
it is worse for the omission.

A further hazard specific to the chosen expression: `regexp_replace` returns its **input
unchanged** when the pattern does not match. A malformed ID such as `)G2112_D` yields
`)G2112` as an `og_id`, silently, rather than failing or nulling.

Fix: drop all nine. Recover `og_id` through the browse views of §7 of the key strategy, which
are inlined by the planner and cost the same as a hand-written join.

Knock-on, and it is real: `summary` joins `dna_extraction`, `illumina_library` and others on
`og_id` directly (`schema/current_views.sql:242-270`). Those joins must route through
`tissue`. This is cutover work either way — the views get repointed at `v2` regardless — but
it should be scheduled, not discovered.

### F2. `og_num` on `v2_dna_extraction` computes the wrong number

Severity: High (correctness)

```sql
og_num integer GENERATED ALWAYS AS ((regexp_replace(tissue_id, '[^0-9]', '', 'g'))::integer) STORED
```

This strips *every* non-digit, concatenating the sample number with the tissue index. Per
§6.2, `OG123G2` is the second gill tissue of sample `OG123`:

| `tissue_id` | Correct | Produced |
|---|---:|---:|
| `OG1623W` | 1623 | 1623 |
| `OG123G2` | 123 | **1232** |

Sibling tables use the `^([^0-9]*[0-9]+).*$` capture and get this right; this one column uses
a different formula. Second failure mode: a `tissue_id` with no digits gives `''::integer`,
which raises — so the insert fails rather than the row being flagged. Live data contains blank
and `0` placeholder tissue IDs (key strategy §2). `v2_sample.og_num`
(`SUBSTRING(og_id FROM 3)::integer`) and `v2_sequencing.og_num` share that cast-failure mode.

Fix: if `og_num` survives at all — it exists only for numeric sort order — derive it once,
from `og_id`, null-on-non-match:
`NULLIF(substring(og_id from '^OG([0-9]+)$'), '')::integer`.

### F3. Text columns that should be typed were copied forward

Severity: High

`database_review.md` Finding 7 is the second-longest section of the review and the scaffold
does not act on it. In brand-new empty tables:

- `v2_dna_extraction.extraction_date` is `text` — while `v2_rna_extraction.extraction_date`
  in the same file is `date` and `v2_hic_lysate.lysate_prep_date` is `date`.
- `library_date` is `text` in all five library tables that have it.
- `v2_sequencing.run_date` and `seq_date` are `text`.
- `ratio_260_280`, `ratio_260_230`, `total_yield`, `av_size` are `text` on
  `v2_dna_extraction`, beside `qubit_conc` / `nano_drop_conc` which are `real`.
- `library_qubit_conc` is `text` on `v2_illumina_library` and `real` on
  `v2_rna_library_ilmn` — the exact type drift §6.4 names as a blocker to unifying the
  library tables, carried into the new ones.
- `v2_sample.weight`, `depth_collection`, `lengthtl_and_lengthfl`, `latitude_collection`,
  `longitude_collection` are `text`.

The reason to leave these as `text` live is that conversion needs profiling and cleanup of
existing values. That does not apply to an empty table — the cost moves to the backfill,
which is where a bad value should surface, and decision 6 gives it somewhere to go.

`v2_sample.ont_num` is a special case: see F5, it is not numeric at all.

### F4. Columns already classified as dead were copied into the new tables

Severity: Medium-High

| Column(s) | Copied into | Status |
|---|---|---|
| `illumina_sequencing`, `hifi_sequencing`, `hic_sequencing`, `nanopore_sequencing`, `rna_extraction`, `rna_ilmn_sequencing`, `rna_kinnex_sequencing`, `illumina_public`, `summary_comments` | `v2_sample` | 0/2,675 filled; flagged "Deprecated or derived" |
| `kinnex_primers`, `kinnex_barcode` | `v2_rna_library_ilmn` | §6.4: wrong table, no spreadsheet source, no consumer — "confirm empty and then drop" |
| `ratioqubit_nanodrop` | `v2_dna_extraction` | Dead on both ends: header doesn't exist *and* `queries.py` never inserts it |

`v2_sample.rna_extraction` is a text column whose name collides with the `rna_extraction`
table, and it is empty. Dropping it removes a genuine source of confusion.

### F4a. `status_overwrite` — keep the column; `Latest` needs no column at all (decisions 2, 8)

Severity: High, and it is a data-loss bug rather than a schema defect

Per decision 2 this column stays. The re-review confirms *why* it is empty, and it is not
because the lab stopped using it: every lab sheet carries a `Status Overwrite` or
`Overwrite Status` column plus a `Latest` column, and **none of them is in
`name_convert.py`.** The import matches headers by exact string and silently drops anything
unmatched, so the lab has been filling a field that never reaches the database while `summary`
reads a column that is always null.

Decision 8 was to capture both. Measuring them changes what that means for each one.

**`Latest` is fully derived and should not be a column.** It is 100% formula on every sheet,
and after normalising row numbers the formula is byte-identical across four sheets:

```excel
IF($B2="","",IF(MAX(IF($B:$B=$B2,$C:$C))=$C2,"Y","N"))
```

`B` is the parent ID, `C` is `#`. `Latest` means *this row has the highest attempt number for
its parent* — a window function, not lab judgement:

```sql
row_number() over (partition by <parent_id> order by ext_num desc) = 1
```

Put it on the browse views (§5 step 5), where it stays correct by construction, rather than
storing a flag the importer would have to keep in sync. This also removes it as an importer
change.

Worth noting: the formula is only correct if `#` is unique per parent, and 64 rows break that
— **53 of them on `4.RNAIllumina`**, plus 5 on `3.DNAExtractions`, 3 on `4.ONT` and 1 each on
`4.HiCLysate`, `4.HiCLibrary` and `4.RNAkinnex`. §6.3's `unique(parent_id, ext_num)` is still
worth enforcing, and those 64 rows are exactly where the workbook's own `Latest` column is
wrong today, marking several rows `Y` at once. `4.RNAIllumina` needs the lab to renumber before
it can load in full: on a trial import 259 of its 321 rows load and 62 quarantine.

**`status_overwrite` is a clean `Y` flag that has simply never been imported.** Across all
eight sheets that carry it, the column holds **129 `Y` values and nothing else** — no `N`, no
other value. Two of the eight columns (`4.ONT`, `4.RNAkinnex`) exist but are entirely empty.

So: type it `boolean` in `v2`, and map both header spellings in the importer. That is the whole
fix; there is no data cleanup to do first.

> **Correction, 2026-08-05.** This finding first reported ~2,054 stray numerics in this column,
> and recommended quarantining them. That was wrong, and the cause was a bug in the throwaway
> XML reader used for the first pass rather than anything in the workbook — it could not match
> self-closing empty cells, so it attributed the neighbouring cell's shared-string *index* to
> the empty column and reported those indices as numeric data. Re-derived with openpyxl the
> column is clean. Two other findings were affected and are corrected in place below; the rest
> of the analysis was cross-checked and is unchanged.

Decision 8's "we can always remove one later" resolves cleanly: keep `status_overwrite` as a
stored boolean, and `latest` as a derived view column.

### F5. `sample` carries 17 columns copied from a derived Excel sheet (decision 5)

Severity: High — widened substantially by the re-review

`name_convert.py` maps `sample` to **two** sheets, `["Summary", "1.MetaData"]`, and applies
every `sample` column mapping to both. Measuring formula density per column on the `Summary`
sheet (full table in `spreadsheet_column_gap_analysis.md`) shows what that pulls in:

- **100% formula (pure lookups and rollups):** `og_id`, `project_id`, `field_id`,
  `nominal_species_id`, `common_name`, `collector`, `contact`, `tissues`, `extracted`,
  `extraction_queue`, `il_status`, `pb_status`, `hic_status`, `ont_num`, `rna_status`,
  `ilrna_status`. Per decision 5 these should not exist in `v2.sample`; `summary` should
  compute them.
- **Kept (decision 9):** `workflow` and `priority`, plus `ilmn`, `hifi`, `hic`, `nano`, `rna`,
  `ilrna`. Eight columns in total, all hand-entered. These are the lab's *intent* — what is
  planned for each sample — which the database cannot derive from the child tables however
  complete they are.

  The six are **Y/N flags, not counts**: measured against the workbook each holds exactly two
  values (`ilmn` 1,522 Y / 187 N, `hifi` 284/1,476, `hic` 267/1,479, `nano` 34/1,463,
  `rna` 167/1,474, `ilrna` 169/1,470). They answer "is this sample slated for this technology?"
  That also explains the live `summary` view's `CASE WHEN s.illumina_sequencing = 'N'` guard:
  the intent was always a flag, the guard was just pointed at a dead column. They are `boolean`
  in v2.

So `v2.sample` = the `1.MetaData` columns + those eight.

Note that seven of the sixteen 100%-formula Summary columns — `og_id`, `project_id`,
`field_id`, `nominal_species_id`, `common_name`, `collector`, `contact` — are formulas *on the
Summary sheet* but real hand-entered columns on `1.MetaData`. They stay; only their Summary
duplication goes. What actually leaves `sample` is nine columns (`tissues`, `extracted`,
`extraction_queue`, `il_status`, `pb_status`, `hic_status`, `ont_num`, `rna_status`,
`ilrna_status`) plus the two the scaffold was about to add (`rna_processing_comment`,
`rna_kinnex_status`).

`v2.summary` exposes the derived actual alongside each flag (`ilmn` slated vs `count(*)` of
Illumina libraries). "Slated for Illumina but no Illumina library exists" is the thing the lab
is currently eyeballing by hand, and it is the natural place for a "behind plan" report later.

Two consequences worth calling out:

**This is the root cause of the status chaos in Finding 7.** The 47 distinct
`sample.rna_status` values and the comma-combined statuses are Excel string concatenation
being persisted. Removing the columns removes the problem at source; normalising them in the
database would have been treating a symptom.

**`sample.ont_num` does not hold a number.** It is mapped to `NanoPore Status` and holds
status text; `sample.nano` holds the count. This is why Finding 7 lists it among
"numeric-like fields stored as text" — it is not numeric, it is misnamed. It disappears
under decision 5 either way.

Also: the two new columns the scaffold added from `Summary` — `rna_kinnex_status`
(100% formula) and `rna_processing_comment` (38%) — should not be added. `rna_kinnex_status`
is a rollup of `rna_library_kinx.rna_status`; `rna_processing_comment` duplicates
`rna_library_kinx.processing_comment`. The other ten new columns are from `1.MetaData` and
`2.Tissue` and are genuine.

### F6. `v2_sequencing` keeps the five nullable polymorphic library columns

Severity: High — now in scope (decision 4)

The scaffold reproduces the five columns, four FKs, and the un-FK-able `rna_library_tube_id`,
with no constraint on how many may be non-null, so the "40 rows with zero library links" case
from the review can recur.

§4.3 below makes the case stronger than the original review did: the **spreadsheet already
uses the single-column model**, and the five-column fan-out is invented by the importer. The
registry restores the source's own shape rather than imposing a new one.

Build it as §6.4 specifies — typed nullable parent columns with
`check (num_nonnulls(dna_id, rna_id, lysate_id) = 1)`, not a `source_type`/`source_id` pair.
On the open question §6.4 raises about parentage living in two places, its own recommendation
(keep the parent column on both, add the composite FK if provable agreement is wanted) still
stands and is unaffected by anything found here.

### F7. Missing constraints that are free on an empty schema

Severity: Medium

- **No `NOT NULL` on any parent FK column.** §6.2/§6.3 specify `not null references`.
  `v2_tissue.og_id`, `v2_dna_extraction.tissue_id`, `v2_rna_extraction.tissue_id`,
  `v2_hic_lysate.tissue_id` and every library parent column are nullable. Decision 6 removes
  the reason to leave them permissive.
- **No FK from `v2_rna_library_kinx.rna_id` to `v2_rna_extraction`.** The inline comment
  justifies this as matching live, but live lacks it because of unvalidated data — and there
  is no data here to validate. Add it; the one bad row surfaces at backfill, which is when
  you want it.
- **No indexes at all beyond the PKs**, so Finding 4 is reproduced from scratch. They belong
  in the same change as the tables.
- **No unique constraints** such as §6.3's `unique(tissue_id, ext_num)`. Reasonable to defer,
  worth recording if deferred.
- **No table or column `COMMENT`s.** Finding 9 recorded 0/42 objects documented, and the data
  dictionary already contains the text.

### F8. Type-system drift preserved in `v2_rna_library_kinx`

Severity: Low-Medium

It uses `character varying(n)` throughout — `varchar(50)`, `varchar(100)`, `varchar(20)`,
`varchar(5)` — while the other eleven tables use `text`; §6.4 names this drift explicitly. It
is also the only table with `created_at` / `updated_at`, so audit columns exist on one table
of twelve. `plate_location varchar(5)` and `kinnex_barcode varchar(20)` are caps that break on
the first unanticipated value for no benefit.

Fix: standardise on `text`; decide audit columns all-or-nothing.

### F9. Naming — resolved by decision 3

`lca_new` keeps its `_new` suffix and is out of scope (decision 1). The lab schema becomes a
`v2` schema with final table names (decision 3), so cutover is a `search_path` or
`ALTER SCHEMA` swap and no object is ever renamed. Two things to check when building it:
cross-schema references need qualifying, and anything with a hardcoded `public.` — including
`queries.py`, which writes unqualified table names — needs auditing.

### F10. Cutover dependencies are not tracked anywhere

Severity: Medium

Eleven views read the live lab tables. `summary` alone has ~10 correlated subqueries against
`dna_extraction`, `illumina_library` and friends, several using the `og_id` columns F1
removes; `sample_view`, `coverage_summary`, `embargo_assignment_view` and the two GoaT views
also depend on this set. Nothing records which views, functions, or external scripts must
change at cutover, and open question 10 of the review — which consumers query the database
from outside this repo — is still unanswered and is a cutover blocker.

Suggested artifact: `docs/v2_cutover_dependencies.md`.

### F11. Scope boundary of the twelve tables is undocumented

Severity: Low

Several non-scaffolded tables reference this set by `og_id` or tube ID: `rna_qc_kinnex`,
`raw_data`, `raw_qc`, `hifi_reads_qc`, `hic_reads_qc`, `draft_genomes`, `ref_genomes`. State
whether they are cutover-neutral or need a follow-up change.

### F12. `Manual/ Automated Method` — one vocabulary, and it already has a typo (decision 10)

Severity: Medium — small change, immediate payoff

Both sheets use the same two-value vocabulary, hand-entered, no formulas:

| Sheet | Filled | Values |
|---|---:|---|
| `4.PacBio` | 362 | `Manual` (258), `Automated Biomek i7` (104) |
| `4.Illumina` | 1,723 | `Auomated Biomek i7` (941), `Manual` (782) |

`4.Illumina` spells it **`Auomated`** — missing the `t` — in all 941 rows. Decision 10 is
therefore not just tidiness: a shared lookup catches this on the first import, whereas two
free-text columns carry the typo into `v2` permanently and split every future
"how many were automated" query in two.

Build it as a small `v2.prep_method_automation` lookup (`code`, `label`) referenced by FK from
both `illumina_library` and `pacbio_library`, seeded with `Manual` and `Automated Biomek i7`.
The 941 misspelled rows normalise during backfill; if any value appears that is in neither, it
quarantines rather than silently creating a third category. A `check` constraint would also
work, but a lookup table means adding the next instrument is a data change, not a migration.

### F13. Proximity ligation belongs on `hic_lysate` (decision 11)

Severity: Medium-High — confirmed, with a caveat that needs the lab

Decision 11 is empirically correct. Joined on `Lysate Tube ID`, where both sheets carry a
value they agree **50 times out of 52**. Same measurement.

The lab's account of it — measured at the lysate stage, transcribed onto the library sheet,
with the lysate sheet being newer and therefore sparser — holds up under three tests.

**The split is chronological.** The lab moved the record onto the lysate sheet during 2025–26,
where `Proximity Ligation prep date` and the derived `Proximity Ligation yield (ng)` already
live:

| | n | Median library prep date |
|---|---:|---|
| Library rows whose lysate *also* carries the value | 52 | 2026-04-15 |
| Library rows whose lysate does *not* | 223 | 2025-05-28 |

**All conflicts predate the lysate column.** 19 lysates have more than one Hi-C library; 10 of
them disagree on the value (`OG767G-1`: `33.3` vs `4.36`; `OG1161B-1`: `0.2`, `0.65`, `6.58`).
**Zero of those 19 — conflicting or agreeing — has a lysate-sheet value.** Every conflict sits
in the pre-lysate-column era, and there is not one conflict among the rows where the lysate
column is in use. The disagreements are transcription noise from when the value was recorded
per library row, not evidence that proximity ligation is a per-library measurement.

**The value exists before the library does.** 28 lysates carry a prox conc while no library of
theirs carries one, several having no Hi-C library on the sheet at all (`OG73W-1`, `OG675L-1`,
`OG109M-2`). A measurement recorded before any library exists cannot be an attribute of one.
This is the structural argument and it does not depend on the timeline.

**Model (decision 11, revised): keep both columns, with explicit and different roles.**

- `v2.hic_lysate` gains `prox_ligation_date date`, `prox_ligation_conc real`, and
  `prox_ligation_yield` derived rather than stored. This is the **current** field: the
  importer writes it, `summary` and the browse views read it, and it is the one the lab fills.
- `v2.hic_library.prox_ligation_conc` is retained as a **legacy, read-only** column carrying
  the 226 historical values that have no lysate-row equivalent. The importer stops writing it.

This is not indecision. It is what makes the column removable later: the 226 legacy values
cannot be migrated up cleanly, because 10 of their lysates hold conflicting values and no
rule picks a winner. Keeping them in place preserves the record losslessly, and the column
can be dropped once the lab has either resolved those 10 or agreed the history is
disposable. Comment both columns to that effect in the DDL, so the split is documented rather
than rediscovered.

Two typing notes for the backfill: the lysate column contains the literal strings `NA` and `0`
(e.g. `OG73W-1`, `OG109M-1`), so a `real` column sends them to quarantine — correct behaviour,
but expect them on the first run.

## 4. Independent re-review of the workbook

The earlier `spreadsheet_column_gap_analysis.md` was taken as an input to the first pass of
this review, not re-derived. Re-deriving it — every header of every sheet compared
programmatically against `EXCEL_TO_DB_COLS`, with formula density measured per column to
separate entered data from Excel lookups — found it incomplete. Details are now recorded in
that document; the summary is below.

### 4.1 Fourteen further columns of hand-entered data are dropped nightly

The first pass excluded a block of columns as "duplicate identifying info" without checking
them individually. Formula analysis separates the genuine duplicates (~100% formula) from
typed-in data (0% formula). The latter:

| Table | Column | Rows filled |
|---|---|---:|
| `illumina_library` | `Manual/ Automated Method` | 1,607 |
| `illumina_library` | `Library Plate Well` | 1,523 |
| `illumina_library` | `Index Plate` | 1,297 |
| `sequencing` | `Status` | 4,004 |
| `pacbio_library` | `SRE Kit` | 394 |
| `pacbio_library` | `Manual/ Automated Method` | 365 |
| `pacbio_library` | `Final Pre-Library Prep Conc. (ng/uL)` | 194 |
| `pacbio_library` | `Post-SRE Conc. (ng/uL)` | 191 |
| `hic_lysate` | `Prep Method` | 386 |
| `hic_lysate` | `Proximity Ligation prep date` | 356 |
| `hic_lysate` | `Proximity Ligation Conc. (ng/uL)` | 80 |
| `rna_extraction` | `gDNA? >7,000bp %` | 185 |
| `rna_library_kinx` | `Sequencing Sample ID` | 148 |

Notable: `sequencing` has **no status column at all** and 4,004 rows carry one. `hic_lysate`
has no method and no proximity-ligation columns; that step is currently captured only through
`hic_library.prox_ligation_conc`, mapped from a differently-cased header on a different sheet.

All of these should be added to the `v2` DDL, and to `name_convert.py`.

### 4.2 A fourth dead mapping

The first pass found three mappings pointing at headers that no longer exist. There is a
fourth: `sequencing.seq_type` → `"Type"`. It causes no data loss, because `import_data.py`
computes `seq_type` itself — but the dead entry is misleading and would start overriding the
computed value if a `Type` header were ever added.

### 4.3 The spreadsheet already uses the library-registry model

`5.Sequencing` has one `Library Tube ID` column (4,014 rows). It is not in `name_convert.py`;
`import_data.py:129-167` fans it out into the five `sequencing.*_library_tube_id` columns by
branching on `technology` and testing for `_D` / `_R` substrings in the ID.

So the polymorphic design is **introduced by the importer**, not inherited from the source.
The registry restores the source's own shape. It also explains why `rna_library_tube_id` is
the one library column with no FK: it receives libraries from both the Illumina-RNA and
Kinnex branches.

Two side effects worth noting: this mapping is invisible to anyone reviewing
`name_convert.py`, and the `_D`/`_R` substring test will misfire on any tube ID not following
the convention.

### 4.4 RNA tube-ID overlap: none (answers decision 7)

| Sheet | Rows | Distinct `Library Tube ID` |
|---|---:|---:|
| `4.RNAIllumina` | 321 | 312 |
| `4.RNAkinnex` | 175 | 174 |

**Overlap between the two: zero.** The suffix conventions differ — `_IL` / `_dIL` for
Illumina RNA, `_KL` for Kinnex — so a shared registry primary key is safe. §6.4's open
question is closed.

The within-sheet duplicates are a separate problem: 8 repeated IDs on `4.RNAIllumina` and 1
on `4.RNAkinnex`. Because `queries.py` upserts `ON CONFLICT (rna_library_tube_id) DO UPDATE`,
the last row silently wins and the earlier one is lost. These are quarantine candidates.

## 5. Recommended build order

**All eleven steps are built** (2026-08-05), as six Sqitch changes plus a backfill script and
a parallel importer:

| Step | Artefact |
|---|---|
| 1 | `design/v2/deploy/create_v2_schema.sql` |
| 2–4 | `design/v2/deploy/create_v2_lab_tables.sql` — a full replacement of the earlier structural clone, not a patch |
| 5 | `design/v2/deploy/create_v2_browse_views.sql` |
| 6–7 | `docs/v2_cutover_dependencies.md`, then `design/v2/deploy/create_v2_summary_view.sql` |
| 8 | `design/v2/backfill_v2.sql` |
| 9 | `design/v2/deploy/create_v2_quarantine.sql` |
| 10 | `OceanOmics-Database/name_convert_v2.py`, `import_v2.py` |
| 11 | `design/v2/deploy/create_v2_lca_tables.sql` |

Every change was deployed, verified and reverted against a throwaway PostgreSQL 14 cluster
loaded with the live schema; each constraint was tested by feeding it the data it exists to
reject; the backfill was run to idempotency against fixtures built from the documented defects;
and `import_v2.py` was run end-to-end against the real workbook, loading 20,881 rows and
quarantining 1,004.

The dependency inventory (step 7) paid for itself immediately: because decision 3 makes cutover
a `search_path` swap, a view only breaks if it references something v2 *removed*. Auditing on
that basis reduced eleven views to **two** needing a rebuild.

1. ~~**`CREATE SCHEMA v2`**; tables take final names (decision 3).~~ Done.
2. ~~Core lab tables~~ **Done.** With: no derived `og_id` / `og_num` (F1, F2); `date` and numeric types
   (F3); dead columns omitted (F4); `status_overwrite` as `boolean` and no `latest` column
   (F4a); `sample` reduced to `1.MetaData` columns plus the eight from decision 9 (F5);
   `NOT NULL` parent FKs, the Kinnex FK, `unique(parent_id, ext_num)`, FK indexes, `COMMENT`s
   (F7); `text` throughout (F8).
3. ~~The 14 newly-found columns~~ **Done.** From §4.1, including `sequencing.status` and the `hic_lysate`
   proximity-ligation columns (F13 — `hic_library.prox_ligation_conc` is retained as a
   commented legacy column, not dropped and not written to).
4. ~~The `library` registry~~ **Done.** With `sequencing` repointed at it (F6, decision 4); and the
   `prep_method_automation` lookup referenced from `illumina_library` and `pacbio_library`
   (F12, decision 10).
5. ~~Browse views~~ **Done.** Twelve of them (`v_tissue_browse`, `v_dna_extraction_browse`, `v_library_browse`, …), each exposing `og_id` and
   a derived `latest`. These land **with or before** step 2, since they are how `og_id` is
   recovered after F1 and how `latest` is recovered after F4a.
6. ~~A `v2.summary` view~~ **Done.** Reproducing the Summary sheet's rollups from the child tables
   (decision 5). This is what replaces the 16 removed `sample` columns, so it is not
   optional. It should also expose planned-vs-actual for the six count columns (F5).
7. ~~Remaining dependent views repointed~~ **Done.** The inventory in
   `docs/v2_cutover_dependencies.md` established that nine of eleven views are
   cutover-neutral under a `search_path` swap; only `summary` and `goat_species_v1` reference
   removed columns, and both are rebuilt in `create_v2_summary_view`.
8. ~~Backfill from live.~~ **Done** — `design/v2/backfill_v2.sql`, re-runnable and idempotent.
9. ~~**Quarantine tables**~~ **Done** (decision 6) — `design/v2/deploy/create_v2_quarantine.sql`. One `v2.import_quarantine` table:
   `source_table`, `source_row_key`, `violation_type`, `violation_detail`, `raw_row jsonb`,
   `first_seen`, `resolved_at` — written by both the backfill and the nightly import. A
   single `jsonb` table avoids maintaining a shadow schema of 12 quarantine tables, and lets
   you query "everything currently blocked" in one place. It should also catch the
   source-side duplicate tube IDs from §4.4, which no constraint will otherwise reveal.
10. ~~Importer changes in `OceanOmics-Database`~~ **Done**, as a parallel path (`name_convert_v2.py`, `import_v2.py`) so the live nightly job keeps running until cutover: 35 new mappings, `status_overwrite` in
    both header spellings and dropping the numerics to quarantine (F4a), the four dead
    mappings (§4.2), normalising `Auomated` → `Automated Biomek i7` (F12), writing to `v2`,
    and reading the single `Library Tube ID` into the registry instead of fanning it out.
    `Latest` needs no mapping — it is a view column.
11. ~~**v2 equivalents of the LCA/mitogenome tables**~~ **Done** (decision 1) — `design/v2/deploy/create_v2_lca_tables.sql`, built to the same rules.
    `lca_new` and its siblings are untouched and remain your concurrent pipeline's tables;
    this is a separate later change and should not block the lab schema.

Deliberately still deferred: the generated `tissue_type_code` / `tissue_index` columns from
§6.2. Its own reasoning — don't parse until the grammar is enforced — still holds, and it is
the one place the phased approach remains correct.

Note that after cutover `add_core_lookup_indexes` becomes partly moot, since half its indexes
are on the `og_id` columns F1 removes. It is correct against today's tables; it just should
not be used as a template for the v2 index set.

## 6. What is right and should not change

- Sqitch adoption, no credentials committed, `migrations/legacy/` preserved with a README
  explaining the supersession.
- `-- no-transaction` correctly applied to the `CONCURRENTLY` index change, with the reason
  recorded in the README safety rules.
- The `Purpose / Review source / Expected impact` comment convention, applied consistently.
- The verify script genuinely verifies — existence, emptiness, spot-checks on new columns —
  rather than being the stub Sqitch generates. It could also assert FKs and PKs exist.
- The revert script drops in correct FK-dependency order.
- The `spreadsheet_column_gap_analysis.md` insight that `import_data.py` silently drops any
  unmatched header remains the highest-value finding in the repo. The re-review extends its
  reach; it does not overturn it.
- §6.0 and §6.4 of `lab_key_strategy.md` are well-argued, and §6.4's "the identity unifies,
  the attributes don't" is the right call — now corroborated by §4.3.

## 7. Open questions — all four closed 2026-08-05

| # | Question | Resolution |
|---|---|---|
| 1 | `Latest` vs `Status Overwrite` (F4a) | Capture both (decision 8). Evidence refines it: `Latest` is 100% formula, `MAX(#) per parent`, so it becomes a **view column, not a stored one**. `status_overwrite` stays, typed `boolean` — it holds 129 `Y` values and nothing else. |
| 2 | The six count columns (F5) | **Keep** all six, plus `workflow` and `priority` (decision 9). They record intent, not actuals, so they are not derivable. They turned out to be **Y/N flags rather than counts** — "is this sample slated for this technology?" — so they are typed `boolean`; planned-vs-actual is surfaced in `v2.summary`. |
| 3 | `Manual/ Automated Method` vocabulary (F12) | **One shared vocabulary** (decision 10) → lookup table + FK from both library tables. Catches the `Auomated` typo sitting in 941 live rows. |
| 4 | Proximity ligation (F13) | **Same value in two places** (decision 11), measured at the lysate stage. Confirmed: 50/52 agreement, all 19 multi-library conflicts predate the lysate column, and 28 lysates carry the value before any library exists. **Keep both**: `hic_lysate` is the live field, `hic_library.prox_ligation_conc` becomes legacy read-only holding the 226 unmigratable historical values. |

## 8. What is left, now that the build is done

Nothing outstanding is a schema question. What remains needs either the lab or the team:

**For the lab — 1,004 quarantined rows.** (Revision 2: **870**, against 21,926 loaded; see
§0.5. The breakdown below is revision 1's and the shape of it still holds.) A trial import of
the current workbook loads 20,881 rows and blocks 1,004. Hand them `SELECT * FROM v2.v_quarantine_open`. The two worth naming:

- **`4.RNAIllumina` reuses attempt numbers on 53 of its 321 rows**, so only 259 load. This is
  also why its `Latest` column is wrong today: `MAX(#)` ties and flags several rows at once.
  Renumbering is the fix and it has to happen in the workbook.
- **31 sequencing rows point at a library that does not exist**, and 33 more have either no
  library tube ID or more than one. The five-column design let those through.

The rest are unparseable measurements (`weight`, `av_size`, the 260/280 ratios) that load with
that one field null, plus 24 duplicated source keys where the current importer's
`ON CONFLICT DO UPDATE` silently lets the last row win.

**For the team — ~~the one genuine cutover blocker~~.** Open question 10 of
`database_review.md` (question 7 in its current numbering): which consumers query this
database from outside these two repos. **Closed by decision 2026-10-05 rather than answered** —
consumers hardcoding `public.` are accepted breakage. It no longer blocks the cutover. The
in-database half is answered by `scripts/audit_v2_dependents.py`; see §0.4. Note the trap recorded there: `queries.py` writes *unqualified* table names, so
it follows the `search_path` — the cutover moves the live importer silently, which means the
importer work must land before the swap, not after.

**Two judgement calls deliberately left open**, both flagged in the DDL rather than decided:

- The dead `CASE WHEN s.illumina_sequencing = 'N' THEN ''` guards in `summary` are now
  *recoverable* — the planning columns turn out to be Y/N flags, so the guard's intent was
  always expressible. `v2.summary` does not switch them on, because samples flagged `N` would
  start showing blank instead of a status, and that is a lab-facing behaviour change.
- `hic_library.prox_ligation_conc` is legacy and read-only by comment, not by constraint. A
  trigger or column-level `REVOKE` would enforce it if you would rather not rely on the note.
