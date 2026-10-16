# Phase R, R.5 record: writers and readers against `v3`

Run 2026-10-16. Runbook: [`assembly_relations_runbook_r0_r5.md`](assembly_relations_runbook_r0_r5.md)
R.5.

- **Writers:** run on a throwaway PostgreSQL 14 cluster restored from a `pg_dump` of live
  taken after `054` (`en_AU.UTF-8`, as live; roles `readonly` and `oceangenom_web`
  recreated), with `055` applied.
- **Readers:** run on live, read-only.
- **Pairing:** each old writer is the `inverts-dev` / `master` version, writing `public`. Each
  new one is the `phase-r-v3` branch, run with `PGOPTIONS='-c search_path=v3,public'`. Both
  write from the same input files.

## Branches

| Repo | Branch | Commit | Change |
|---|---|---|---|
| `Oceanomics-OceanGenomes-Mitogenomes` | `phase-r-v3` (from `inverts-dev`) | `f3f629f` | `push_mtdna_assm_results.py`, `push_emma_annotation_results.py`, `audit_ena_readiness.py`, `tests/unit/test_push_emma_column_parity.py` |
| `OceanOmics-OceanGenomes-Draft-Genomes` | `phase-r-v3` (from `master`) | `4d1fa2f` | `bin/draft_genome_stats.py`, `tests/test_draft_genome_stats_backfill.py` |
| `OceanOmics-Database` | `phase-r-import` (from `main`) | `8c698e9`, `e82e75c` | the stale-sequencing work already in production, committed; then S.1 (`seq_type`) |

- None is pushed or deployed, except that `OceanOmics-Database`'s working copy is what cron
  runs (see S.1).
- Unit tests: mitogenome 25 of 25 in the touched modules (`unittest`; there is no pytest in
  the venv). Draft: 132 of 132.
- **Unchanged on purpose:**
  - every status line `compile_upload_report.py` parses;
  - the overwrite policy (`decide_write`) and the depth-only guard;
  - `BUSCO_KEYMAP`, which waits for R.0.4;
  - the six draft `push_*` CLIs and every Nextflow module.

## R.5.3 Writers

### Mitogenome

Inputs were built from OG3129 `ilmn.260925.getorg1770` (emma102, 16,506 bp, measured depth),
written under the rehearsal key `OG3129.ilmn.991231.rehearsal`.

| Check | Result |
|---|---|
| Old writers → `public`, new → `v3`, same inputs | `v3.mitogenome_data` and `public.mitogenome_data` equal on all 102 columns except the two write timestamps: **0 rows differ either way** |
| Second annotator (`mitos2110`), both writers | `v3`: **two annotations, emma102 and mitos2110; emma102 unchanged**; 0 selected. `public` (old writer): mitos2110 only. The overwrite is gone |
| Rerun without `--force` | Preserved: "row already exists; pass --force to overwrite", and "already carries a measured depth; left untouched" |
| Failed-to-assemble rerun with `--force` | Refused: "refusing to overwrite with 'failed to assemble'" |
| `--force` rerun with no depth | Assembly rewritten; stored depth kept (`remap_full_v1`, 7312.04) |
| New assembly with no depth, then a depth without `--force` | Recorded `not_measured`, then "Depth metrics added … (assembly stats preserved)" |
| Old writers after a simulated merge (tables moved out, `v3` views moved into `public`, on a clone) | Assembly: "cannot insert into view "mitogenome_data"". Annotation: fails on the dropped `seqlength_12s`. **Both fail loudly** |
| `is_selected` set on one annotation | `v3.mitogenome_data`, `v3.mitogenome_submission_view` and `public.summary` **byte-identical**. Only `v_mito_annotation_genes` changes. `pg_depend`: no other view uses the column. No pipeline code names it |

### Draft genome

Inputs were the test suite's archive builder, under OG2613 / 260724. That is a real NovaSeq DNA
library, `OG2613F_D_IL_NOVA_260724_JP`, with no draft yet.

| Check | Result |
|---|---|
| Old six CLIs → `public`, new → `v3`, same files | `v3.draft_genomes` and `public.draft_genomes` equal on all 103 columns: **0 rows differ either way** |
| Run link | `OG2613F_D_IL_NOVA_260724_JP`; `v_draft_genome_status`: 7 processes, not reads-only |
| Hi-C-only draft (OG1573 / 260706) | Rejected at the fastp step: "only Hi-C hic sequencing matches this draft…". Nothing written |
| Draft ahead of the workbook (no sequencing row) | Written, with a warning that the link will follow |
| Old draft writer after a simulated merge | "cannot insert into view "draft_genomes"" |

**Found here, and fixed by `055`.** The first draft rehearsal (OG659 / 260817) linked a draft
to `OG659L_R_IL_NOVA_260817_LA`, an RNA library. Technology does not separate DNA from RNA:
Illumina RNA (`rna_ilmn`, 294 rows) and PacBio Kinnex RNA (`rna_kinx`, 137) share a technology
with the DNA libraries.
- On live, no real draft was affected. One HiFi mitogenome was linked to an RNA Kinnex library.
- `055` adds `library_type` to both run-link rules and to the `draft_genome_run` trigger. It
  removed that one link on live, and the writer got the same rule.
- Rehearsed: the trigger rejects an `rna_ilmn` library, the revert gives an identical schema,
  and replay is clean.

## R.5.4 Readers on live, read-only

Each reader's own query ran on live under the default `search_path` (the old tables) and
again under `v3, public` (the compatibility views). The results were compared by md5.

| Reader | Rows | Result |
|---|---:|---|
| `audit_ena_readiness.py`: biosample list | 1,626 | identical |
| `audit_ena_readiness.py`: depth counts (new per-assembly query) | 2,371 / 1,954 / 1,954 | identical, and equal to the old query on the old table |
| `audit_ena_readiness.py`: per-sample candidates | 2,371 | identical |
| `backfill_ena_specimen_accessions.py`: og_id list | 3,401 | identical |
| `prepare_ena_metadata.py`: `mean_depth` by assembly | 2,371 | identical |
| `mitogenome_submission_view` | 2,371 | identical |
| Draft `fetch_database_record()` (its 87 columns, all drafts) | 1,720 | identical |
| `v_genome_size_comparison` | 1,203 | identical |
| `summary` | 3,401 | identical |

**Found, not caused by Phase R:** `build_source_modifiers.py` (mitogenome pipeline, `bin/`,
around line 385) joins `sequencing_info`. No such relation exists in any schema on live, so
that query fails today against `public` as well. It needs its own fix in the mitogenome
pipeline. It is outside this phase and is not changed on `phase-r-v3`.

## S.1 `seq_type`

- **Commits:** `OceanOmics-Database` `e82e75c` on `phase-r-import`. Before it, `8c698e9`
  commits the stale-sequencing work that had been running in production uncommitted since
  2026-10-16.
- **Rehearsal** (real runs, twice, against the restore):
  - `seq_type` NULL 193 → 0, and the rows are unchanged at 4,460;
  - open quarantine unchanged at 720, so nothing new was quarantined;
  - every value matches its library type, and the second run is a no-op.
- **Live `--dry-run`:** exit 0, rolled back. The only sequencing `check` quarantine is the known
  `OG779G_D2_IL_NEXT_`.
- **Pending:** the 18:00 UTC import applies it, because cron runs this working copy. Check the
  next morning: `SELECT count(*) FROM sequencing WHERE seq_type IS NULL` should be 0.
