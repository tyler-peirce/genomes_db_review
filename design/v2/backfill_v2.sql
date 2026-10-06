-- scripts/backfill_v2.sql
--
-- Purpose: Copy the live public.* lab tables AND the LCA / mitogenome tables into the v2
--   schema, sending every row that
--   violates a v2 contract to v2.import_quarantine instead of dropping it or weakening the
--   schema to accommodate it (§5 step 8, decision 6).
--
-- Usage:
--     python3 import_v2.py --stage-attempt-keys -e <workbook>     # OceanOmics-Database; required
--     psql -h <host> -U <user> -d oceanomics_genomes -v ON_ERROR_STOP=1 -f design/v2/backfill_v2.sql
--
--   The staging step records which side of each attempt-key tie the workbook still carries;
--   this script refuses to run without it (Phase V.2).
--
--   Deliberately NOT a Sqitch change. It is data movement, not schema, and it is designed to
--   be run repeatedly: each pass re-reads live, inserts what now passes, and refreshes the
--   quarantine. That is what you want while the lab is fixing rows at source — run it, hand
--   the lab v2.v_quarantine_open, wait, run it again.
--
-- Method: every table is loaded in two statements. The first inserts the rows that satisfy the
--   v2 contract; the second records the complement in quarantine with the reason. Both read the
--   same predicate, so a row can never be silently in neither. Parents are loaded before
--   children, so a child quarantined for a missing parent is genuinely missing rather than
--   merely not loaded yet.
--
-- Casting: live stores dates and measurements as text (Finding 7). Rather than cast and fail
--   the whole statement, this uses the null-on-failure helper below, and quarantines rows whose
--   text would not convert. The row still loads, with that one field null and a quarantine
--   record naming the field — losing one unparseable measurement is better than losing the row.
--
-- Covers all seventeen tables. The LCA half was added 2026-10-05; see its own header below.
--
-- Not covered here, because they need decisions the data cannot supply:
--   - the 226 legacy hic_library.prox_ligation_conc values (F13) are copied as-is into the
--     legacy column and NOT promoted to hic_lysate; the 10 conflicting lysates are quarantined
--     for the lab to resolve
--   - status_overwrite holds only 'Y' in the workbook (129 of them); anything else would be
--     new and quarantines rather than being coerced

\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------------------------
-- Cast helpers: null on failure rather than aborting the statement
-- ---------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pg_temp.try_date(t text) RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF t IS NULL OR btrim(t) = '' OR upper(btrim(t)) IN ('NA','N/A','-','?') THEN RETURN NULL; END IF;
    -- Live holds a mixture of ISO strings and Excel date serials.
    IF btrim(t) ~ '^[0-9]{5}(\.[0-9]+)?$' THEN
        RETURN DATE '1899-12-30' + (floor(btrim(t)::numeric))::integer;
    END IF;
    RETURN btrim(t)::date;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.try_real(t text) RETURNS real
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF t IS NULL OR btrim(t) = '' OR upper(btrim(t)) IN ('NA','N/A','-','?') THEN RETURN NULL; END IF;
    RETURN btrim(replace(t, ',', ''))::real;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.try_int(t text) RETURNS integer
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF t IS NULL OR btrim(t) = '' OR upper(btrim(t)) IN ('NA','N/A','-','?') THEN RETURN NULL; END IF;
    RETURN round(btrim(replace(t, ',', ''))::numeric)::integer;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

-- 'Y'/'N' and the stray numerics of F4a. Only 'Y' means true; anything numeric returns null
-- and is quarantined separately below.
CREATE OR REPLACE FUNCTION pg_temp.try_flag(t text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN t IS NULL THEN NULL
                WHEN upper(btrim(t)) IN ('Y','YES','TRUE','T') THEN true
                WHEN upper(btrim(t)) IN ('N','NO','FALSE','F') THEN false
                ELSE NULL END;
$$;

-- True when a text value was meant to hold something but did not survive the cast, i.e. the
-- case worth telling the lab about. Blank and explicit NA are not failures.
CREATE OR REPLACE FUNCTION pg_temp.cast_failed(raw text, converted anyelement) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    SELECT raw IS NOT NULL
       AND btrim(raw) <> ''
       AND upper(btrim(raw)) NOT IN ('NA','N/A','-','?')
       AND converted IS NULL;
$$;

-- ---------------------------------------------------------------------------------------
-- Attempt-key ties, resolved against the workbook (Phase V.2)
-- ---------------------------------------------------------------------------------------
--
-- Nine tables carry `*_attempt_key UNIQUE (parent, num)`. Live breaks it: measured 2026-10-05,
-- rna_library_ilmn 107 of 389, dna_extraction 49 (48 pairs), hic_lysate 9, ont_library 4,
-- pacbio_library 3, illumina_library 1, rna_library_kinx 1. These are lost data, not
-- duplicates: two real attempts numbered the same. The lab keeps creating them, so this is a
-- standing rule, not a one-off cleanup. The rule itself is described at the tie quarantine
-- statement at the end of the lab half.

DO $$
DECLARE
    n     bigint;
    files text;
BEGIN
    SELECT count(*), string_agg(DISTINCT workbook_file, ', ')
      INTO n, files FROM v2.workbook_attempt_keys;
    IF n = 0 THEN
        RAISE EXCEPTION 'v2.workbook_attempt_keys is empty: run `import_v2.py --stage-attempt-keys -e <workbook>` first. Without it every attempt-key tie would be resolved arbitrarily.';
    END IF;
    RAISE NOTICE 'Attempt-key ties resolved against % (% staged rows)', files, n;
END $$;

CREATE TEMP TABLE attempt_rows ON COMMIT DROP AS
SELECT 'dna_extraction'::text AS tbl, d.dna_id::text AS row_key, d.tissue_id::text AS parent,
       d.ext_num::text AS num, '3.DNAExtractions'::text AS sheet, to_jsonb(d) AS row_json
  FROM public.dna_extraction d
UNION ALL
SELECT 'rna_extraction', r.rna_id, r.tissue_id, r.ext_num::text, '3.RNAExtractions', to_jsonb(r)
  FROM public.rna_extraction r
UNION ALL
SELECT 'hic_lysate', y.lysate_id, y.tissue_id, y.lysate_num::text, '4.HiCLysate', to_jsonb(y)
  FROM public.hic_lysate y
UNION ALL
SELECT 'illumina_library', i.illumina_library_tube_id, i.dna_id, i.ilmn_num::text, '4.Illumina', to_jsonb(i)
  FROM public.illumina_library i
UNION ALL
SELECT 'pacbio_library', p.pacbio_library_tube_id, p.dna_id, p.pacb_num::text, '4.PacBio', to_jsonb(p)
  FROM public.pacbio_library p
UNION ALL
SELECT 'ont_library', o.ont_library_tube_id, o.dna_id, o.ont_num::text, '4.ONT', to_jsonb(o)
  FROM public.ont_library o
UNION ALL
SELECT 'hic_library', h.hic_library_tube_id, h.lysate_id, h.hic_num::text, '4.HiCLibrary', to_jsonb(h)
  FROM public.hic_library h
UNION ALL
SELECT 'rna_library_ilmn', x.rna_library_tube_id, x.rna_id, x.rna_num::text, '4.RNAIllumina', to_jsonb(x)
  FROM public.rna_library_ilmn x
UNION ALL
SELECT 'rna_library_kinx', k.rna_library_tube_id, k.rna_id, k.rna_num::text, '4.RNAkinnex', to_jsonb(k)
  FROM public.rna_library_kinx k;

-- A NULL parent or attempt number never ties: the UNIQUE constraint does not compare NULLs.
-- A row counts as "in the workbook" only under the same (parent, attempt) -- a tube the lab
-- has since moved to another tissue or renumbered does not vouch for this slot.
CREATE TEMP TABLE attempt_tie_losers ON COMMIT DROP AS
WITH tied AS (
    SELECT a.*,
           EXISTS (SELECT 1 FROM v2.workbook_attempt_keys w
                    WHERE w.source_table = a.tbl AND w.row_key = a.row_key
                      AND w.parent_key = a.parent AND w.attempt_num::text = a.num) AS in_workbook
    FROM attempt_rows a
    WHERE a.row_key IS NOT NULL AND a.parent IS NOT NULL AND a.num IS NOT NULL
),
grp AS (
    SELECT tbl, parent, num,
           count(DISTINCT row_key) FILTER (WHERE in_workbook) AS n_workbook,
           min(row_key) FILTER (WHERE in_workbook)            AS workbook_key,
           string_agg(DISTINCT row_key, ', ' ORDER BY row_key) AS tied_keys
    FROM tied
    GROUP BY tbl, parent, num
    HAVING count(DISTINCT row_key) > 1
)
SELECT t.tbl, t.row_key, t.sheet, t.row_json,
       format('(%s, %s) is shared by %s; ', t.parent, t.num, g.tied_keys) ||
       CASE WHEN g.n_workbook = 1
            THEN format('the workbook carries %s for this attempt, so this row was not loaded',
                        g.workbook_key)
            WHEN g.n_workbook = 0
            THEN 'the workbook carries none of them, so none was loaded; renumber or retire them at source'
            ELSE 'the workbook carries more than one, so none was loaded; renumber one at source'
       END AS detail
FROM tied t
JOIN grp g USING (tbl, parent, num)
WHERE NOT (g.n_workbook = 1 AND t.in_workbook);

CREATE INDEX ON attempt_tie_losers (tbl, row_key);
ANALYZE attempt_tie_losers;

-- ---------------------------------------------------------------------------------------
-- 1. sample
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.sample (
    og_id, project_id, field_id, nominal_species_id, common_name, collector, contact,
    date_collected, sex, weight, lengthtl_and_lengthfl, country, state, location,
    latitude_collection, longitude_collection, depth_collection, collection_method,
    preservation_method, sample_condition, photo_voucher, photo_id, specimen_voucher,
    voucher_id, comments, workflow, priority, ilmn, hifi, hic, nano, rna, ilrna,
    assigned_species, eschmeyer_id, ncbi_sample_name, ncbi_biosample_id, hifi_lca_outcome,
    ncbi_id, tol_id, ncbi_bioproject_id_lvl_3_hifi, bioproject_id_haplotype_1,
    bioproject_id_haplotype_2, bioproject_sequencing_data, ncbi_assembly_upload,
    ncbi_raw_reads_upload, hifi_public, illumina_lca, ncbi_bioproject_id_draft,
    draft_sra_accessions, draft_assembly_accession, embargo_status)
SELECT s.og_id, s.project_id, s.field_id, s.nominal_species_id, s.common_name, s.collector,
       s.contact, s.date_collected, s.sex,
       pg_temp.try_real(s.weight), pg_temp.try_real(s.lengthtl_and_lengthfl),
       s.country, s.state, s.location,
       pg_temp.try_real(s.latitude_collection)::double precision,
       pg_temp.try_real(s.longitude_collection)::double precision,
       pg_temp.try_real(s.depth_collection),
       s.collection_method, s.preservation_method, s.sample_condition, s.photo_voucher,
       s.photo_id, s.specimen_voucher, s.voucher_id, s.comments,
       s.workflow::text, s.priority,
       -- Y/N flags, not counts: measured against the workbook these hold 'Y'/'N'. `ilmn`,
       -- `rna` and `ilrna` are additionally contaminated with leaked status text
       -- ('Awaiting Status', 'Sequenced', comma-combined strings), which null out here and
       -- quarantine below.
       pg_temp.try_flag(s.ilmn), pg_temp.try_flag(s.hifi), pg_temp.try_flag(s.hic),
       pg_temp.try_flag(s.nano), pg_temp.try_flag(s.rna), pg_temp.try_flag(s.ilrna),
       s.assigned_species, s.eschmeyer_id, s.ncbi_sample_name, s.ncbi_biosample_id,
       s.hifi_lca_outcome, s.ncbi_id, s.tol_id, s.ncbi_bioproject_id_lvl_3_hifi,
       s.bioproject_id_haplotype_1, s.bioproject_id_haplotype_2, s.bioproject_sequencing_data,
       s.ncbi_assembly_upload, s.ncbi_raw_reads_upload, s.hifi_public, s.illumina_lca,
       s.ncbi_bioproject_id_draft, s.draft_sra_accessions, s.draft_assembly_accession,
       s.embargo_status::text
FROM public.sample s
WHERE s.og_id IS NOT NULL AND btrim(s.og_id) <> ''
ON CONFLICT (og_id) DO NOTHING;

SELECT v2.quarantine('sample', s.og_id, 'not_null', 'og_id is null or blank',
                     to_jsonb(s), '1.MetaData')
FROM public.sample s
WHERE s.og_id IS NULL OR btrim(s.og_id) = '';

SELECT v2.quarantine('sample', s.og_id, 'type_cast',
                     concat_ws('; ',
                       CASE WHEN pg_temp.cast_failed(s.weight, pg_temp.try_real(s.weight))
                            THEN 'weight=' || s.weight END,
                       CASE WHEN pg_temp.cast_failed(s.depth_collection, pg_temp.try_real(s.depth_collection))
                            THEN 'depth_collection=' || s.depth_collection END,
                       CASE WHEN pg_temp.cast_failed(s.latitude_collection, pg_temp.try_real(s.latitude_collection))
                            THEN 'latitude_collection=' || s.latitude_collection END,
                       CASE WHEN pg_temp.cast_failed(s.longitude_collection, pg_temp.try_real(s.longitude_collection))
                            THEN 'longitude_collection=' || s.longitude_collection END),
                     to_jsonb(s), '1.MetaData')
FROM public.sample s
WHERE pg_temp.cast_failed(s.weight, pg_temp.try_real(s.weight))
   OR pg_temp.cast_failed(s.depth_collection, pg_temp.try_real(s.depth_collection))
   OR pg_temp.cast_failed(s.latitude_collection, pg_temp.try_real(s.latitude_collection))
   OR pg_temp.cast_failed(s.longitude_collection, pg_temp.try_real(s.longitude_collection));

-- The planning flags hold only Y/N in the current workbook, so this should match nothing.
-- Kept as a guard: these are booleans in v2, and status text leaking into them — the Finding 7
-- failure mode — must surface rather than silently becoming null.
SELECT v2.quarantine('sample', s.og_id, 'lookup',
                     concat_ws('; ',
                       CASE WHEN pg_temp.cast_failed(s.ilmn,  pg_temp.try_flag(s.ilmn))  THEN 'ilmn='  || s.ilmn  END,
                       CASE WHEN pg_temp.cast_failed(s.hifi,  pg_temp.try_flag(s.hifi))  THEN 'hifi='  || s.hifi  END,
                       CASE WHEN pg_temp.cast_failed(s.hic,   pg_temp.try_flag(s.hic))   THEN 'hic='   || s.hic   END,
                       CASE WHEN pg_temp.cast_failed(s.nano,  pg_temp.try_flag(s.nano))  THEN 'nano='  || s.nano  END,
                       CASE WHEN pg_temp.cast_failed(s.rna,   pg_temp.try_flag(s.rna))   THEN 'rna='   || s.rna   END,
                       CASE WHEN pg_temp.cast_failed(s.ilrna, pg_temp.try_flag(s.ilrna)) THEN 'ilrna=' || s.ilrna END)
                       || ' — expected Y or N in a planning flag',
                     to_jsonb(s), 'Summary')
FROM public.sample s
WHERE pg_temp.cast_failed(s.ilmn,  pg_temp.try_flag(s.ilmn))
   OR pg_temp.cast_failed(s.hifi,  pg_temp.try_flag(s.hifi))
   OR pg_temp.cast_failed(s.hic,   pg_temp.try_flag(s.hic))
   OR pg_temp.cast_failed(s.nano,  pg_temp.try_flag(s.nano))
   OR pg_temp.cast_failed(s.rna,   pg_temp.try_flag(s.rna))
   OR pg_temp.cast_failed(s.ilrna, pg_temp.try_flag(s.ilrna));

-- ---------------------------------------------------------------------------------------
-- 2. tissue
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.tissue (tissue_id, og_id, alt_id, tissue, extracted, freezer, shelf, rack,
                       level, box, comment)
SELECT t.tissue_id, t.og_id, t.alt_id, t.tissue, t.extracted, t.freezer, t.shelf, t.rack,
       t.level, t.box, t.comment
FROM public.tissue t
WHERE t.tissue_id IS NOT NULL AND btrim(t.tissue_id) <> '' AND t.tissue_id <> '0'
  AND EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = t.og_id)
ON CONFLICT (tissue_id) DO NOTHING;

SELECT v2.quarantine('tissue', t.tissue_id,
                     CASE WHEN t.tissue_id IS NULL OR btrim(t.tissue_id) = '' OR t.tissue_id = '0'
                          THEN 'not_null' ELSE 'foreign_key' END,
                     CASE WHEN t.tissue_id IS NULL OR btrim(t.tissue_id) = '' OR t.tissue_id = '0'
                          THEN 'tissue_id is blank or the placeholder 0 (lab_key_strategy.md §2)'
                          ELSE 'og_id ' || coalesce(t.og_id, '<null>') || ' has no sample row' END,
                     to_jsonb(t), '2.Tissue')
FROM public.tissue t
WHERE t.tissue_id IS NULL OR btrim(t.tissue_id) = '' OR t.tissue_id = '0'
   OR NOT EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = t.og_id);

-- ---------------------------------------------------------------------------------------
-- 3. dna_extraction
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.dna_extraction (
    dna_id, tissue_id, ext_num, status, extraction_method, extraction_date,
    extraction_batch_id, final_buffer, volume, qubit_conc, nano_drop_conc, ratio_260_280,
    ratio_260_230, total_yield, gdna_femtol_id, av_size, extraction_qc, comment,
    dna_freezer, dna_shelf, dna_rack, dna_level, dna_box, dna_notes, status_overwrite)
SELECT DISTINCT ON (d.dna_id)
       d.dna_id, d.tissue_id, d.ext_num, d.status, d.extraction_method,
       pg_temp.try_date(d.extraction_date), d.extraction_batch_id, d.final_buffer, d.volume,
       d.qubit_conc, d.nano_drop_conc,
       pg_temp.try_real(d.ratio_260_280), pg_temp.try_real(d.ratio_260_230),
       pg_temp.try_real(d.total_yield), d.gdna_femtol_id, pg_temp.try_real(d.av_size),
       d.extraction_qc, d.comment, d.dna_freezer, d.dna_shelf, d.dna_rack, d.dna_level,
       d.dna_box, d.dna_notes, pg_temp.try_flag(d.status_overwrite::text)
FROM public.dna_extraction d
WHERE d.dna_id IS NOT NULL AND btrim(d.dna_id) <> ''
  AND EXISTS (SELECT 1 FROM v2.tissue t WHERE t.tissue_id = d.tissue_id)
  -- attempt-key ties: seat only the workbook's row (see attempt_tie_losers above)
  AND NOT EXISTS (SELECT 1 FROM pg_temp.attempt_tie_losers z
                   WHERE z.tbl = 'dna_extraction' AND z.row_key = d.dna_id::text)
ORDER BY d.dna_id
ON CONFLICT (dna_id) DO NOTHING;

SELECT v2.quarantine('dna_extraction', d.dna_id, 'foreign_key',
                     'tissue_id ' || coalesce(d.tissue_id, '<null>') || ' has no tissue row',
                     to_jsonb(d), '3.DNAExtractions')
FROM public.dna_extraction d
WHERE d.dna_id IS NOT NULL AND btrim(d.dna_id) <> ''
  AND NOT EXISTS (SELECT 1 FROM v2.tissue t WHERE t.tissue_id = d.tissue_id);

-- Attempt-key ties are quarantined once, for all nine tables, at the end of the lab half.

-- F4a. The workbook holds only 'Y' here, so this should match nothing. It is kept as a guard:
-- status_overwrite is now a boolean the summary view filters on, and a value that is neither
-- Y nor N should surface rather than silently becoming null.
SELECT v2.quarantine('dna_extraction', d.dna_id, 'type_cast',
                     'status_overwrite = ' || d.status_overwrite
                       || ' — expected Y or N (F4a)',
                     to_jsonb(d), '3.DNAExtractions')
FROM public.dna_extraction d
WHERE d.status_overwrite IS NOT NULL
  AND btrim(d.status_overwrite::text) <> ''
  AND pg_temp.try_flag(d.status_overwrite::text) IS NULL;

SELECT v2.quarantine('dna_extraction', d.dna_id, 'type_cast',
                     'extraction_date = ' || d.extraction_date || ' did not parse; loaded as null',
                     to_jsonb(d), '3.DNAExtractions')
FROM public.dna_extraction d
WHERE pg_temp.cast_failed(d.extraction_date, pg_temp.try_date(d.extraction_date));

-- ---------------------------------------------------------------------------------------
-- 4. rna_extraction
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.rna_extraction (
    rna_id, tissue_id, ext_num, status, extraction_method, extraction_date,
    extraction_batch_id, final_buffer, volume, qubit_conc, nano_drop_conc, ratio_260_280,
    ratio_260_230, total_yield, tapestation_id, rna_dv200, rin, extraction_qc, comment,
    rna_freezer, rna_shelf, rna_rack, rna_level, rna_box, rna_notes, status_overwrite)
SELECT DISTINCT ON (r.rna_id)
       r.rna_id, r.tissue_id, r.ext_num, r.status, r.extraction_method, r.extraction_date,
       r.extraction_batch_id, r.final_buffer, r.volume, r.qubit_conc, r.nano_drop_conc,
       pg_temp.try_real(r.ratio_260_280), pg_temp.try_real(r.ratio_260_230),
       r.total_yield, r.tapestation_id, r.rna_dv200, pg_temp.try_real(r.rin),
       r.extraction_qc, r.comment, r.rna_freezer,
       pg_temp.try_int(r.rna_shelf), pg_temp.try_int(r.rna_rack),
       r.rna_level, r.rna_box, r.rna_notes, pg_temp.try_flag(r.status_overwrite::text)
FROM public.rna_extraction r
WHERE r.rna_id IS NOT NULL AND btrim(r.rna_id) <> ''
  AND EXISTS (SELECT 1 FROM v2.tissue t WHERE t.tissue_id = r.tissue_id)
  -- attempt-key ties: seat only the workbook's row (see attempt_tie_losers above)
  AND NOT EXISTS (SELECT 1 FROM pg_temp.attempt_tie_losers z
                   WHERE z.tbl = 'rna_extraction' AND z.row_key = r.rna_id::text)
ORDER BY r.rna_id
ON CONFLICT (rna_id) DO NOTHING;

SELECT v2.quarantine('rna_extraction', r.rna_id, 'foreign_key',
                     'tissue_id ' || coalesce(r.tissue_id, '<null>') || ' has no tissue row',
                     to_jsonb(r), '3.RNAExtractions')
FROM public.rna_extraction r
WHERE r.rna_id IS NOT NULL AND btrim(r.rna_id) <> ''
  AND NOT EXISTS (SELECT 1 FROM v2.tissue t WHERE t.tissue_id = r.tissue_id);

-- ---------------------------------------------------------------------------------------
-- 5. hic_lysate
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.hic_lysate (lysate_id, tissue_id, lysate_num, lysate_status, lysate_prep_date,
                           lysate_batch_id, lysate_conc, total_lysate, lysate_cde,
                           lysate_comments)
SELECT DISTINCT ON (y.lysate_id)
       y.lysate_id, y.tissue_id, y.lysate_num, y.lysate_status, y.lysate_prep_date,
       y.lysate_batch_id, y.lysate_conc, y.total_lysate, y.lysate_cde, y.lysate_comments
FROM public.hic_lysate y
WHERE y.lysate_id IS NOT NULL AND btrim(y.lysate_id) <> ''
  AND EXISTS (SELECT 1 FROM v2.tissue t WHERE t.tissue_id = y.tissue_id)
  -- attempt-key ties: seat only the workbook's row (see attempt_tie_losers above)
  AND NOT EXISTS (SELECT 1 FROM pg_temp.attempt_tie_losers z
                   WHERE z.tbl = 'hic_lysate' AND z.row_key = y.lysate_id::text)
ORDER BY y.lysate_id
ON CONFLICT (lysate_id) DO NOTHING;

SELECT v2.quarantine('hic_lysate', y.lysate_id, 'foreign_key',
                     'tissue_id ' || coalesce(y.tissue_id, '<null>') || ' has no tissue row',
                     to_jsonb(y), '4.HiCLysate')
FROM public.hic_lysate y
WHERE y.lysate_id IS NOT NULL AND btrim(y.lysate_id) <> ''
  AND NOT EXISTS (SELECT 1 FROM v2.tissue t WHERE t.tissue_id = y.tissue_id);

-- F13. The lysate-side proximity-ligation columns do not exist live, so there is nothing to
-- copy into them; the values live on hic_library and stay there (see step 8 below). Where one
-- lysate's libraries disagree, the lab must choose before anything can be promoted.
SELECT v2.quarantine('hic_lysate', h.lysate_id, 'conflicting_value',
                     'Hi-C libraries for this lysate record different proximity ligation '
                       || 'concentrations (' || string_agg(DISTINCT h.prox_ligation_conc::text, ', ')
                       || '); promotion to hic_lysate.prox_ligation_conc is blocked until the '
                       || 'lab picks one (F13)',
                     jsonb_build_object('lysate_id', h.lysate_id,
                                        'values', jsonb_agg(DISTINCT h.prox_ligation_conc)),
                     '4.HiCLibrary')
FROM public.hic_library h
WHERE h.prox_ligation_conc IS NOT NULL
GROUP BY h.lysate_id
HAVING count(DISTINCT h.prox_ligation_conc) > 1;

-- ---------------------------------------------------------------------------------------
-- 6. library registry  (F6) — built from the five live library tables
-- ---------------------------------------------------------------------------------------
--
-- Built before the technology tables, because each of those now has a composite FK into it.
--
-- NOTE, 2026-10-05 (Phase V.1). Each technology table's guard below tests the registry on the
-- FULL PAIR (library_tube_id, parent_id), not on library_tube_id alone as it did until today.
-- The composite FK is on the pair, so a tube-only test can pass where the FK then fails, and
-- that is not hypothetical: it aborted the whole backfill on current data.
--
-- The cause is a tube ID reused across two library types. v2.library makes library_tube_id a
-- primary key -- unique across ALL technologies -- which §4.4 of the design review verified
-- was safe. It verified it against the SPREADSHEET, where the suffix conventions (_IL / _dIL
-- for Illumina RNA, _KL for Kinnex) genuinely do not collide, and concluded "overlap between
-- the two: zero". It never checked the database, and the database disagrees: 25 tube IDs are
-- reused across types, 24 of them _KL tubes present in BOTH rna_library_ilmn and
-- rna_library_kinx with the same parent rna_id, plus the junk id '0' shared by an Illumina
-- and a PacBio library with different parents.
--
-- The 24 are an importer artefact, the same one that duplicated kinnex_barcode and
-- kinnex_primers onto rna_library_ilmn: Kinnex rows are being written into both RNA tables.
-- So §4.4's conclusion is right about the source and wrong about the destination, and the
-- registry key is sound in principle while being unsatisfiable against today's rows.
--
-- Handled by quarantining the losers rather than by widening the key to
-- (library_tube_id, library_type), because the rows are duplicates that should not exist at
-- all -- widening the key would preserve them. Decision 6: quarantine the row, do not weaken
-- the schema. The lab gets the list; the real fix is in the importer, before cutover.

INSERT INTO v2.library (library_tube_id, library_type, dna_id)
SELECT DISTINCT ON (i.illumina_library_tube_id) i.illumina_library_tube_id, 'illumina', i.dna_id
FROM public.illumina_library i
WHERE i.illumina_library_tube_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM v2.dna_extraction d WHERE d.dna_id = i.dna_id)
ORDER BY i.illumina_library_tube_id
ON CONFLICT (library_tube_id) DO NOTHING;

INSERT INTO v2.library (library_tube_id, library_type, dna_id)
SELECT DISTINCT ON (p.pacbio_library_tube_id) p.pacbio_library_tube_id, 'pacbio', p.dna_id
FROM public.pacbio_library p
WHERE p.pacbio_library_tube_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM v2.dna_extraction d WHERE d.dna_id = p.dna_id)
ORDER BY p.pacbio_library_tube_id
ON CONFLICT (library_tube_id) DO NOTHING;

INSERT INTO v2.library (library_tube_id, library_type, dna_id)
SELECT DISTINCT ON (o.ont_library_tube_id) o.ont_library_tube_id, 'ont', o.dna_id
FROM public.ont_library o
WHERE o.ont_library_tube_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM v2.dna_extraction d WHERE d.dna_id = o.dna_id)
ORDER BY o.ont_library_tube_id
ON CONFLICT (library_tube_id) DO NOTHING;

INSERT INTO v2.library (library_tube_id, library_type, lysate_id)
SELECT DISTINCT ON (h.hic_library_tube_id) h.hic_library_tube_id, 'hic', h.lysate_id
FROM public.hic_library h
WHERE h.hic_library_tube_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM v2.hic_lysate y WHERE y.lysate_id = h.lysate_id)
ORDER BY h.hic_library_tube_id
ON CONFLICT (library_tube_id) DO NOTHING;

INSERT INTO v2.library (library_tube_id, library_type, rna_id)
SELECT DISTINCT ON (x.rna_library_tube_id) x.rna_library_tube_id, 'rna_ilmn', x.rna_id
FROM public.rna_library_ilmn x
WHERE x.rna_library_tube_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM v2.rna_extraction r WHERE r.rna_id = x.rna_id)
ORDER BY x.rna_library_tube_id
ON CONFLICT (library_tube_id) DO NOTHING;

-- §4.4 confirmed zero tube-ID overlap between the two RNA sheets, so this cannot collide with
-- the Illumina RNA libraries above. The ON CONFLICT is belt and braces: if it ever fires, the
-- premise of the shared registry key has changed and should be re-examined.
INSERT INTO v2.library (library_tube_id, library_type, rna_id)
SELECT DISTINCT ON (k.rna_library_tube_id) k.rna_library_tube_id, 'rna_kinx', k.rna_id
FROM public.rna_library_kinx k
WHERE k.rna_library_tube_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM v2.rna_extraction r WHERE r.rna_id = k.rna_id)
ORDER BY k.rna_library_tube_id
ON CONFLICT (library_tube_id) DO NOTHING;

SELECT v2.quarantine('library', k.rna_library_tube_id, 'duplicate_source_row',
                     'tube ID present in both RNA library tables — §4.4 measured zero overlap, '
                       || 'so this is new and invalidates the shared registry key',
                     to_jsonb(k), '4.RNAkinnex')
FROM public.rna_library_kinx k
WHERE EXISTS (SELECT 1 FROM public.rna_library_ilmn x
               WHERE x.rna_library_tube_id = k.rna_library_tube_id);

-- ---------------------------------------------------------------------------------------
-- 7. Technology library tables
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.illumina_library (illumina_library_tube_id, dna_id, ilmn_num, ilmn_status,
                                 library_method, library_date, library_id, index_set,
                                 index_well, index_idx, library_qubit_conc, il_comments,
                                 status_overwrite)
SELECT DISTINCT ON (i.illumina_library_tube_id)
       i.illumina_library_tube_id, i.dna_id, i.ilmn_num, i.ilmn_status, i.library_method,
       pg_temp.try_date(i.library_date), i.library_id, i.index_set, i.index_well, i.index_idx,
       pg_temp.try_real(i.library_qubit_conc), i.il_comments,
       pg_temp.try_flag(i.status_overwrite::text)
FROM public.illumina_library i
WHERE EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = i.illumina_library_tube_id AND l.dna_id = i.dna_id)
  -- attempt-key ties: seat only the workbook's row (see attempt_tie_losers above)
  AND NOT EXISTS (SELECT 1 FROM pg_temp.attempt_tie_losers z
                   WHERE z.tbl = 'illumina_library' AND z.row_key = i.illumina_library_tube_id::text)
ORDER BY i.illumina_library_tube_id
ON CONFLICT (illumina_library_tube_id) DO NOTHING;

-- prep_automation, library_plate_well and index_plate are new columns with no live source —
-- they have only ever existed in the spreadsheet (§4.1). They stay null until the importer
-- change of §5 step 10 lands and the next nightly run populates them.

INSERT INTO v2.pacbio_library (pacbio_library_tube_id, dna_id, pacb_num, pacb_status,
                               dna_treatment, shear_femtol_id, shear_av_size, library_method,
                               library_date, library_id, index_well, barcode, seq_femto_id,
                               seq_av_size, library_conc, comment, status_overwrite)
SELECT DISTINCT ON (p.pacbio_library_tube_id)
       p.pacbio_library_tube_id, p.dna_id, p.pacb_num, p.pacb_status, p.dna_treatment,
       p.shear_femtol_id, p.shear_av_size, p.library_method,
       pg_temp.try_date(p.library_date), p.library_id, p.index_well, p.barcode,
       p.seq_femto_id, p.seq_av_size, p.library_conc, p.comment,
       pg_temp.try_flag(p.status_overwrite::text)
FROM public.pacbio_library p
WHERE EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = p.pacbio_library_tube_id AND l.dna_id = p.dna_id)
  -- attempt-key ties: seat only the workbook's row (see attempt_tie_losers above)
  AND NOT EXISTS (SELECT 1 FROM pg_temp.attempt_tie_losers z
                   WHERE z.tbl = 'pacbio_library' AND z.row_key = p.pacbio_library_tube_id::text)
ORDER BY p.pacbio_library_tube_id
ON CONFLICT (pacbio_library_tube_id) DO NOTHING;

INSERT INTO v2.ont_library (ont_library_tube_id, dna_id, ont_num, ont_status, library_method,
                            library_type, library_date, library_id, est_loading_size,
                            ont_comments, status_overwrite)
SELECT DISTINCT ON (o.ont_library_tube_id)
       o.ont_library_tube_id, o.dna_id, o.ont_num, o.ont_status, o.library_method,
       o.library_type, pg_temp.try_date(o.library_date), o.library_id, o.est_loading_size,
       o.ont_comments, pg_temp.try_flag(o.status_overwrite::text)
FROM public.ont_library o
WHERE EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = o.ont_library_tube_id AND l.dna_id = o.dna_id)
  -- attempt-key ties: seat only the workbook's row (see attempt_tie_losers above)
  AND NOT EXISTS (SELECT 1 FROM pg_temp.attempt_tie_losers z
                   WHERE z.tbl = 'ont_library' AND z.row_key = o.ont_library_tube_id::text)
ORDER BY o.ont_library_tube_id
ON CONFLICT (ont_library_tube_id) DO NOTHING;

-- prox_ligation_conc goes into the LEGACY column, deliberately (F13). It is not promoted to
-- hic_lysate: 226 of these have no lysate-row equivalent and 10 lysates disagree across their
-- libraries, which is quarantined above.
INSERT INTO v2.hic_library (hic_library_tube_id, lysate_id, hic_num, hic_status, library_method,
                            library_date, library_id, prox_ligation_conc, purified_dna_total,
                            index_set, library_conc, library_size, hic_comments,
                            status_overwrite)
SELECT DISTINCT ON (h.hic_library_tube_id)
       h.hic_library_tube_id, h.lysate_id, h.hic_num, h.hic_status, h.library_method,
       pg_temp.try_date(h.library_date), h.library_id, h.prox_ligation_conc,
       h.purified_dna_total, h.index_set, h.library_conc, h.library_size, h.hic_comments,
       pg_temp.try_flag(h.status_overwrite::text)
FROM public.hic_library h
WHERE EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = h.hic_library_tube_id AND l.lysate_id = h.lysate_id)
  -- attempt-key ties: seat only the workbook's row (see attempt_tie_losers above)
  AND NOT EXISTS (SELECT 1 FROM pg_temp.attempt_tie_losers z
                   WHERE z.tbl = 'hic_library' AND z.row_key = h.hic_library_tube_id::text)
ORDER BY h.hic_library_tube_id
ON CONFLICT (hic_library_tube_id) DO NOTHING;

INSERT INTO v2.rna_library_ilmn (rna_library_tube_id, rna_id, rna_num, rna_status,
                                 library_method, library_date, library_id, library_size,
                                 perc_product, library_qubit_conc, library_molarity, index_set,
                                 index_well, index_inx, comments, status_overwrite)
SELECT DISTINCT ON (x.rna_library_tube_id)
       x.rna_library_tube_id, x.rna_id, x.rna_num, x.rna_status, x.library_method,
       pg_temp.try_date(x.library_date), x.library_id, x.library_size, x.perc_product,
       x.library_qubit_conc, pg_temp.try_real(x.library_molarity), x.index_set, x.index_well,
       x.index_inx, x.comments, pg_temp.try_flag(x.status_overwrite::text)
FROM public.rna_library_ilmn x
WHERE EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = x.rna_library_tube_id AND l.rna_id = x.rna_id)
  -- attempt-key ties: seat only the workbook's row (see attempt_tie_losers above)
  AND NOT EXISTS (SELECT 1 FROM pg_temp.attempt_tie_losers z
                   WHERE z.tbl = 'rna_library_ilmn' AND z.row_key = x.rna_library_tube_id::text)
ORDER BY x.rna_library_tube_id
ON CONFLICT (rna_library_tube_id) DO NOTHING;

-- kinnex_primers / kinnex_barcode are dropped from v2.rna_library_ilmn (F4). If live holds any,
-- that is misplaced Kinnex data and must be moved, not deleted.
SELECT v2.quarantine('rna_library_ilmn', x.rna_library_tube_id, 'conflicting_value',
                     'kinnex_primers/kinnex_barcode hold values on the Illumina RNA table; '
                       || 'those columns are dropped in v2 (F4) — migrate to rna_library_kinx',
                     to_jsonb(x), '4.RNAIllumina')
FROM public.rna_library_ilmn x
WHERE coalesce(btrim(x.kinnex_primers), '') <> '' OR coalesce(btrim(x.kinnex_barcode), '') <> '';

INSERT INTO v2.rna_library_kinx (rna_library_tube_id, rna_id, rna_num, rna_status,
                                 library_method, processing_comment, synthesis_date,
                                 part1_batch_id, synthesis_conc, part2_batch_id,
                                 final_qubit_conc, library_size, kinnex_primers, kinnex_barcode,
                                 pool_id, plate, plate_location, comments, status_overwrite)
SELECT DISTINCT ON (k.rna_library_tube_id)
       k.rna_library_tube_id, k.rna_id, k.rna_num, k.rna_status, k.library_method,
       k.processing_comment, k.synthesis_date, k.part1_batch_id, k.synthesis_conc,
       k.part2_batch_id, k.final_qubit_conc, k.library_size, k.kinnex_primers, k.kinnex_barcode,
       k.pool_id, k.plate, k.plate_location, k.comments,
       pg_temp.try_flag(k.status_overwrite::text)
FROM public.rna_library_kinx k
WHERE EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = k.rna_library_tube_id AND l.rna_id = k.rna_id)
  -- attempt-key ties: seat only the workbook's row (see attempt_tie_losers above)
  AND NOT EXISTS (SELECT 1 FROM pg_temp.attempt_tie_losers z
                   WHERE z.tbl = 'rna_library_kinx' AND z.row_key = k.rna_library_tube_id::text)
ORDER BY k.rna_library_tube_id
ON CONFLICT (rna_library_tube_id) DO NOTHING;

-- Every library row with no matching (library_tube_id, parent_id) registry entry. Two causes,
-- and the reason text names both because they need different fixes: a missing parent is the
-- lab's to resolve, a tube ID already registered to another library is the importer's.
SELECT v2.quarantine(t.tbl, t.tube, 'foreign_key',
                     'no v2.library registry row for (tube_id, parent): either the parent '
                     'extraction/lysate is missing, or this tube_id is already registered to '
                     'a different library -- see the §4.4 note where the registry is built',
                     t.row_json, t.sheet)
FROM (
    SELECT 'illumina_library' AS tbl, i.illumina_library_tube_id AS tube, to_jsonb(i) AS row_json, '4.Illumina' AS sheet
      FROM public.illumina_library i
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = i.illumina_library_tube_id AND l.dna_id = i.dna_id)
    UNION ALL
    SELECT 'pacbio_library', p.pacbio_library_tube_id, to_jsonb(p), '4.PacBio'
      FROM public.pacbio_library p
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = p.pacbio_library_tube_id AND l.dna_id = p.dna_id)
    UNION ALL
    SELECT 'ont_library', o.ont_library_tube_id, to_jsonb(o), '4.ONT'
      FROM public.ont_library o
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = o.ont_library_tube_id AND l.dna_id = o.dna_id)
    UNION ALL
    SELECT 'hic_library', h.hic_library_tube_id, to_jsonb(h), '4.HiCLibrary'
      FROM public.hic_library h
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = h.hic_library_tube_id AND l.lysate_id = h.lysate_id)
    UNION ALL
    SELECT 'rna_library_ilmn', x.rna_library_tube_id, to_jsonb(x), '4.RNAIllumina'
      FROM public.rna_library_ilmn x
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = x.rna_library_tube_id AND l.rna_id = x.rna_id)
    UNION ALL
    SELECT 'rna_library_kinx', k.rna_library_tube_id, to_jsonb(k), '4.RNAkinnex'
      FROM public.rna_library_kinx k
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = k.rna_library_tube_id AND l.rna_id = k.rna_id)
) t;

-- ---------------------------------------------------------------------------------------
-- 8. sequencing  — five polymorphic columns collapse to one registry reference (F6)
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.sequencing (sequencing_id, library_tube_id, technology, instrument, run_date,
                           run_id, cell_id, smrt_num, seq_type, design_no, seq_comments)
SELECT q.sequencing_id,
       coalesce(q.illumina_library_tube_id, q.pacbio_library_tube_id, q.ont_library_tube_id,
                q.hic_library_tube_id, q.rna_library_tube_id) AS library_tube_id,
       q.technology, q.instrument, pg_temp.try_date(q.run_date), q.run_id, q.cell_id,
       q.smrt_num, q.seq_type, q.design_no, q.seq_comments
FROM public.sequencing q
WHERE EXISTS (SELECT 1 FROM v2.library l
               WHERE l.library_tube_id = coalesce(q.illumina_library_tube_id,
                        q.pacbio_library_tube_id, q.ont_library_tube_id,
                        q.hic_library_tube_id, q.rna_library_tube_id))
ON CONFLICT (sequencing_id) DO NOTHING;

-- The 40 rows with no library link at all, which the old five-column design permitted.
SELECT v2.quarantine('sequencing', q.sequencing_id, 'not_null',
                     'no library tube ID in any of the five live columns; v2.sequencing '
                       || 'requires exactly one (F6)',
                     to_jsonb(q), '5.Sequencing')
FROM public.sequencing q
WHERE num_nonnulls(nullif(q.illumina_library_tube_id, ''), nullif(q.pacbio_library_tube_id, ''),
                   nullif(q.ont_library_tube_id, ''), nullif(q.hic_library_tube_id, ''),
                   nullif(q.rna_library_tube_id, '')) = 0;

-- Rows naming more than one library: the old design had no constraint preventing it.
SELECT v2.quarantine('sequencing', q.sequencing_id, 'conflicting_value',
                     'more than one library tube ID set across the five live columns; only one '
                       || 'can be carried into v2 (F6)',
                     to_jsonb(q), '5.Sequencing')
FROM public.sequencing q
WHERE num_nonnulls(nullif(q.illumina_library_tube_id, ''), nullif(q.pacbio_library_tube_id, ''),
                   nullif(q.ont_library_tube_id, ''), nullif(q.hic_library_tube_id, ''),
                   nullif(q.rna_library_tube_id, '')) > 1;

SELECT v2.quarantine('sequencing', q.sequencing_id, 'foreign_key',
                     'library tube ID not found in the registry; its library row was itself rejected',
                     to_jsonb(q), '5.Sequencing')
FROM public.sequencing q
WHERE num_nonnulls(nullif(q.illumina_library_tube_id, ''), nullif(q.pacbio_library_tube_id, ''),
                   nullif(q.ont_library_tube_id, ''), nullif(q.hic_library_tube_id, ''),
                   nullif(q.rna_library_tube_id, '')) = 1
  AND NOT EXISTS (SELECT 1 FROM v2.library l
                   WHERE l.library_tube_id = coalesce(q.illumina_library_tube_id,
                            q.pacbio_library_tube_id, q.ont_library_tube_id,
                            q.hic_library_tube_id, q.rna_library_tube_id));

-- =======================================================================================
-- LCA / mitogenome tables
-- =======================================================================================
--
-- Added 2026-10-05 by the Phase V.1 re-review. The August backfill covered the twelve lab
-- tables only, so a cutover would have landed an empty v2.lca, v2.lca_raw_results,
-- v2.lca_validation, v2.blast_filtered_lca and v2.mitogenome_data while the public ones
-- were renamed away. Same two-statement pattern as above: the rows that satisfy the
-- contract, then the complement in quarantine with a reason.
--
-- Load order is forced by the v2 foreign keys, which live does not have:
--
--     mitogenome_data                        (FK -> v2.sample)
--       -> lca_validation, lca, lca_raw_results
--                                            (FK -> v2.sample AND -> v2.mitogenome_data
--                                             on (og_id, tech, seq_date, code))
--     blast_filtered_lca                     (FK -> v2.sample only)
--
-- Measured against live on 2026-10-05, every one of these predicates passes on every row:
-- 0 null key columns, 0 og_id values absent from sample, 0 rows without a mitogenome
-- parent, and 0 duplicates under any of the five primary keys. The LCA rebuild produced
-- clean data. The quarantine statements are still here, because "clean today" is not a
-- constraint and the nightly pipeline keeps writing.
--
-- Two things that are NOT done here, deliberately:
--
--   content_hash is not inserted. It is NOT NULL and part of two primary keys, and
--   v2.lca_set_content_hash() fills it on BEFORE INSERT. Note the consequence: a v2 hash
--   is NOT equal to the public hash for the same logical row, because the hash covers
--   every column and v2 dropped og_num (F2). Reconcile these tables on their business
--   keys at V.4, never on content_hash.
--
--   lca_raw_results.lca_run_date is cast to text on the way in. Live stores it as integer
--   here and text on lca; v2 aligns both to text (F8), so this one column needs the cast
--   and no other does.

-- ---------------------------------------------------------------------------------------
-- 14. mitogenome_data
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.mitogenome_data (
    og_id, tech, seq_date, code, stats, length, length_emma, seqlength_12s,
    seqlength_16s, seqlength_co1, cds_no, trna_no, rrna_no, status, genbank, rrna12s,
    rrna16s, atp6, atp8, cox1, cox2, cox3, cytb, nad1, nad2, nad3, nad4, nad4l, nad5,
    nad6, trna_phe, trna_val, trna_leuuag, trna_leuuaa, trna_ile, trna_met, trna_thr,
    trna_pro, trna_lys, trna_asp, trna_glu, trna_sergcu, trna_seruga, trna_tyr,
    trna_cys, trna_trp, trna_ala, trna_asn, trna_gly, trna_arg, trna_his, trna_gln,
    manual_curation_notes, bankit, genbank_accession, annotation,
    date_submitted_genbank, avg_coverage, avg_base_coverage, atp6_trans, atp8_trans,
    cox1_trans, cox2_trans, cox3_trans, cytb_trans, nad1_trans, nad2_trans, nad3_trans,
    nad4_trans, nad4l_trans, nad5_trans, nad6_trans, extra_genes, missing_genes,
    order_correct, passed, mean_depth, median_depth, depth_sd, depth_cv, breadth_1x,
    breadth_10x, mito_mapped_reads, total_reads, mito_read_fraction,
    depth_target_length_bp, depth_target_fasta, depth_method, depth_measured_at,
    trna_advisory, order_variant, order_deviation, annotation_gaps,
    order_variant_taxon_check, order_status, order_deviation_detail,
    expected_lineage_genes, missing_expected_lineage_genes, lineage_gene_advisories,
    mitos_unmapped_features, mitos_known_auxiliary_features, duplicate_loci,
    annotation_integrity_status, annotation_integrity_issues, atp9, atp9_trans, mtmuts,
    mtmuts_trans, annotation_stats_version, annotation_updated_at)
SELECT m.og_id, m.tech, m.seq_date, m.code, m.stats, m.length, m.length_emma,
       m.seqlength_12s, m.seqlength_16s, m.seqlength_co1, m.cds_no, m.trna_no,
       m.rrna_no, m.status, m.genbank, m.rrna12s, m.rrna16s, m.atp6, m.atp8, m.cox1,
       m.cox2, m.cox3, m.cytb, m.nad1, m.nad2, m.nad3, m.nad4, m.nad4l, m.nad5, m.nad6,
       m.trna_phe, m.trna_val, m.trna_leuuag, m.trna_leuuaa, m.trna_ile, m.trna_met,
       m.trna_thr, m.trna_pro, m.trna_lys, m.trna_asp, m.trna_glu, m.trna_sergcu,
       m.trna_seruga, m.trna_tyr, m.trna_cys, m.trna_trp, m.trna_ala, m.trna_asn,
       m.trna_gly, m.trna_arg, m.trna_his, m.trna_gln, m.manual_curation_notes,
       m.bankit, m.genbank_accession, m.annotation, m.date_submitted_genbank,
       m.avg_coverage, m.avg_base_coverage, m.atp6_trans, m.atp8_trans, m.cox1_trans,
       m.cox2_trans, m.cox3_trans, m.cytb_trans, m.nad1_trans, m.nad2_trans,
       m.nad3_trans, m.nad4_trans, m.nad4l_trans, m.nad5_trans, m.nad6_trans,
       m.extra_genes, m.missing_genes, m.order_correct, m.passed, m.mean_depth,
       m.median_depth, m.depth_sd, m.depth_cv, m.breadth_1x, m.breadth_10x,
       m.mito_mapped_reads, m.total_reads, m.mito_read_fraction,
       m.depth_target_length_bp, m.depth_target_fasta, m.depth_method,
       m.depth_measured_at, m.trna_advisory, m.order_variant, m.order_deviation,
       m.annotation_gaps, m.order_variant_taxon_check, m.order_status,
       m.order_deviation_detail, m.expected_lineage_genes,
       m.missing_expected_lineage_genes, m.lineage_gene_advisories,
       m.mitos_unmapped_features, m.mitos_known_auxiliary_features, m.duplicate_loci,
       m.annotation_integrity_status, m.annotation_integrity_issues, m.atp9,
       m.atp9_trans, m.mtmuts, m.mtmuts_trans, m.annotation_stats_version,
       m.annotation_updated_at
FROM public.mitogenome_data m
WHERE m.og_id IS NOT NULL AND btrim(m.og_id) <> ''
  AND m.tech IS NOT NULL AND btrim(m.tech) <> ''
  AND m.seq_date IS NOT NULL AND btrim(m.seq_date) <> ''
  AND m.code IS NOT NULL AND btrim(m.code) <> ''
ON CONFLICT DO NOTHING;

SELECT v2.quarantine('mitogenome_data',
                     coalesce(m.og_id::text,'?') || '.' || coalesce(m.tech::text,'?') || '.' || coalesce(m.seq_date::text,'?') || '.' || coalesce(m.code::text,'?'),
                     'not_null', 'a key column is null or blank',
                     to_jsonb(m), '1.MetaData')
FROM public.mitogenome_data m
WHERE m.og_id IS NULL OR btrim(m.og_id) = ''
     OR m.tech IS NULL OR btrim(m.tech) = ''
     OR m.seq_date IS NULL OR btrim(m.seq_date) = ''
     OR m.code IS NULL OR btrim(m.code) = '';

SELECT v2.quarantine('mitogenome_data',
                     coalesce(m.og_id::text,'?') || '.' || coalesce(m.tech::text,'?') || '.' || coalesce(m.seq_date::text,'?') || '.' || coalesce(m.code::text,'?'),
                     'missing_parent', 'og_id is not in sample',
                     to_jsonb(m), '1.MetaData')
FROM public.mitogenome_data m
WHERE m.og_id IS NOT NULL AND btrim(m.og_id) <> ''
  AND m.tech IS NOT NULL AND btrim(m.tech) <> ''
  AND m.seq_date IS NOT NULL AND btrim(m.seq_date) <> ''
  AND m.code IS NOT NULL AND btrim(m.code) <> ''
  AND NOT EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = m.og_id);

-- ---------------------------------------------------------------------------------------
-- 15. lca_validation
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.lca_validation (
    og_id, tech, validated_species_name, validator, nominal_species_id_lca_comment,
    validator_2, data_release, validated_rank, lca_genus, seq_date, code, annotation,
    row_created_on)
SELECT v.og_id, v.tech, v.validated_species_name, v.validator,
       v.nominal_species_id_lca_comment, v.validator_2, v.data_release,
       v.validated_rank, v.lca_genus, v.seq_date, v.code, v.annotation, v.row_created_on
FROM public.lca_validation v
WHERE v.og_id IS NOT NULL AND btrim(v.og_id) <> ''
  AND v.tech IS NOT NULL AND btrim(v.tech) <> ''
  AND v.seq_date IS NOT NULL AND btrim(v.seq_date) <> ''
  AND v.code IS NOT NULL AND btrim(v.code) <> ''
  AND v.annotation IS NOT NULL AND btrim(v.annotation) <> ''
  AND EXISTS (SELECT 1 FROM v2.mitogenome_data p
               WHERE p.og_id = v.og_id AND p.tech = v.tech
                 AND p.seq_date = v.seq_date AND p.code = v.code)
ON CONFLICT DO NOTHING;

SELECT v2.quarantine('lca_validation',
                     coalesce(v.og_id::text,'?') || '.' || coalesce(v.tech::text,'?') || '.' || coalesce(v.seq_date::text,'?') || '.' || coalesce(v.code::text,'?') || '.' || coalesce(v.annotation::text,'?'),
                     'not_null', 'a key column is null or blank',
                     to_jsonb(v), 'LCA')
FROM public.lca_validation v
WHERE v.og_id IS NULL OR btrim(v.og_id) = ''
     OR v.tech IS NULL OR btrim(v.tech) = ''
     OR v.seq_date IS NULL OR btrim(v.seq_date) = ''
     OR v.code IS NULL OR btrim(v.code) = ''
     OR v.annotation IS NULL OR btrim(v.annotation) = '';

SELECT v2.quarantine('lca_validation',
                     coalesce(v.og_id::text,'?') || '.' || coalesce(v.tech::text,'?') || '.' || coalesce(v.seq_date::text,'?') || '.' || coalesce(v.code::text,'?') || '.' || coalesce(v.annotation::text,'?'),
                     'missing_parent', 'og_id is not in sample',
                     to_jsonb(v), 'LCA')
FROM public.lca_validation v
WHERE v.og_id IS NOT NULL AND btrim(v.og_id) <> ''
  AND v.tech IS NOT NULL AND btrim(v.tech) <> ''
  AND v.seq_date IS NOT NULL AND btrim(v.seq_date) <> ''
  AND v.code IS NOT NULL AND btrim(v.code) <> ''
  AND v.annotation IS NOT NULL AND btrim(v.annotation) <> ''
  AND NOT EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = v.og_id);

SELECT v2.quarantine('lca_validation',
                     coalesce(v.og_id::text,'?') || '.' || coalesce(v.tech::text,'?') || '.' || coalesce(v.seq_date::text,'?') || '.' || coalesce(v.code::text,'?') || '.' || coalesce(v.annotation::text,'?'),
                     'missing_parent',
                     'no mitogenome_data row for (og_id, tech, seq_date, code)',
                     to_jsonb(v), 'LCA')
FROM public.lca_validation v
WHERE v.og_id IS NOT NULL AND btrim(v.og_id) <> ''
  AND v.tech IS NOT NULL AND btrim(v.tech) <> ''
  AND v.seq_date IS NOT NULL AND btrim(v.seq_date) <> ''
  AND v.code IS NOT NULL AND btrim(v.code) <> ''
  AND v.annotation IS NOT NULL AND btrim(v.annotation) <> ''
  AND EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = v.og_id)
  AND NOT EXISTS (SELECT 1 FROM v2.mitogenome_data p
                   WHERE p.og_id = v.og_id AND p.tech = v.tech
                     AND p.seq_date = v.seq_date AND p.code = v.code);

-- ---------------------------------------------------------------------------------------
-- 16. lca
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.lca (
    og_id, tech, seq_date, code, annotation, "region", lca_run_date, species_in_lca,
    number_unq_blast_hits, domain, phylum, "class", "order", family, genus,
    specific_epiphet, species, scientific_name_authorship, taxon_rank, top_taxon_id,
    taxon_id_db, top_accession_id, accession_id_ref_db, top_percent_query_cover,
    top_percent_query_cover_hsp, alignment_length, subject_length, sequence_length,
    top_confidence_score, top_percent_match, taxon_rank_db)
SELECT l.og_id, l.tech, l.seq_date, l.code, l.annotation, l."region", l.lca_run_date,
       l.species_in_lca, l.number_unq_blast_hits, l.domain, l.phylum, l."class",
       l."order", l.family, l.genus, l.specific_epiphet, l.species,
       l.scientific_name_authorship, l.taxon_rank, l.top_taxon_id, l.taxon_id_db,
       l.top_accession_id, l.accession_id_ref_db, l.top_percent_query_cover,
       l.top_percent_query_cover_hsp, l.alignment_length, l.subject_length,
       l.sequence_length, l.top_confidence_score, l.top_percent_match, l.taxon_rank_db
FROM public.lca l
WHERE l.og_id IS NOT NULL AND btrim(l.og_id) <> ''
  AND l.tech IS NOT NULL AND btrim(l.tech) <> ''
  AND l.seq_date IS NOT NULL AND btrim(l.seq_date) <> ''
  AND l.code IS NOT NULL AND btrim(l.code) <> ''
  AND l.annotation IS NOT NULL AND btrim(l.annotation) <> ''
  AND l."region" IS NOT NULL AND btrim(l."region") <> ''
  AND l.lca_run_date IS NOT NULL AND btrim(l.lca_run_date) <> ''
  AND EXISTS (SELECT 1 FROM v2.mitogenome_data p
               WHERE p.og_id = l.og_id AND p.tech = l.tech
                 AND p.seq_date = l.seq_date AND p.code = l.code)
ON CONFLICT DO NOTHING;

SELECT v2.quarantine('lca',
                     coalesce(l.og_id::text,'?') || '.' || coalesce(l.tech::text,'?') || '.' || coalesce(l.seq_date::text,'?') || '.' || coalesce(l.code::text,'?') || '.' || coalesce(l.annotation::text,'?') || '.' || coalesce(l."region"::text,'?') || '.' || coalesce(l.lca_run_date::text,'?'),
                     'not_null', 'a key column is null or blank',
                     to_jsonb(l), 'LCA')
FROM public.lca l
WHERE l.og_id IS NULL OR btrim(l.og_id) = ''
     OR l.tech IS NULL OR btrim(l.tech) = ''
     OR l.seq_date IS NULL OR btrim(l.seq_date) = ''
     OR l.code IS NULL OR btrim(l.code) = ''
     OR l.annotation IS NULL OR btrim(l.annotation) = ''
     OR l."region" IS NULL OR btrim(l."region") = ''
     OR l.lca_run_date IS NULL OR btrim(l.lca_run_date) = '';

SELECT v2.quarantine('lca',
                     coalesce(l.og_id::text,'?') || '.' || coalesce(l.tech::text,'?') || '.' || coalesce(l.seq_date::text,'?') || '.' || coalesce(l.code::text,'?') || '.' || coalesce(l.annotation::text,'?') || '.' || coalesce(l."region"::text,'?') || '.' || coalesce(l.lca_run_date::text,'?'),
                     'missing_parent', 'og_id is not in sample',
                     to_jsonb(l), 'LCA')
FROM public.lca l
WHERE l.og_id IS NOT NULL AND btrim(l.og_id) <> ''
  AND l.tech IS NOT NULL AND btrim(l.tech) <> ''
  AND l.seq_date IS NOT NULL AND btrim(l.seq_date) <> ''
  AND l.code IS NOT NULL AND btrim(l.code) <> ''
  AND l.annotation IS NOT NULL AND btrim(l.annotation) <> ''
  AND l."region" IS NOT NULL AND btrim(l."region") <> ''
  AND l.lca_run_date IS NOT NULL AND btrim(l.lca_run_date) <> ''
  AND NOT EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = l.og_id);

SELECT v2.quarantine('lca',
                     coalesce(l.og_id::text,'?') || '.' || coalesce(l.tech::text,'?') || '.' || coalesce(l.seq_date::text,'?') || '.' || coalesce(l.code::text,'?') || '.' || coalesce(l.annotation::text,'?') || '.' || coalesce(l."region"::text,'?') || '.' || coalesce(l.lca_run_date::text,'?'),
                     'missing_parent',
                     'no mitogenome_data row for (og_id, tech, seq_date, code)',
                     to_jsonb(l), 'LCA')
FROM public.lca l
WHERE l.og_id IS NOT NULL AND btrim(l.og_id) <> ''
  AND l.tech IS NOT NULL AND btrim(l.tech) <> ''
  AND l.seq_date IS NOT NULL AND btrim(l.seq_date) <> ''
  AND l.code IS NOT NULL AND btrim(l.code) <> ''
  AND l.annotation IS NOT NULL AND btrim(l.annotation) <> ''
  AND l."region" IS NOT NULL AND btrim(l."region") <> ''
  AND l.lca_run_date IS NOT NULL AND btrim(l.lca_run_date) <> ''
  AND EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = l.og_id)
  AND NOT EXISTS (SELECT 1 FROM v2.mitogenome_data p
                   WHERE p.og_id = l.og_id AND p.tech = l.tech
                     AND p.seq_date = l.seq_date AND p.code = l.code);

-- ---------------------------------------------------------------------------------------
-- 17. lca_raw_results
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.lca_raw_results (
    og_id, tech, seq_date, code, annotation, sequence_region, lca_run_date, domain,
    phylum, "class", "order", family, genus, specific_epiphet, scientific_name,
    scientific_name_authorship, taxon_rank, taxon_id, taxon_id_db,
    verbatim_identification, accession_id, accession_id_ref_db, percent_match,
    percent_query_cover, percent_query_cover_hsp, alignment_length, subject_length,
    sequence_length, confidence_score, taxon_rank_db)
SELECT r.og_id, r.tech, r.seq_date, r.code, r.annotation, r.sequence_region,
       r.lca_run_date::text, r.domain, r.phylum, r."class", r."order", r.family,
       r.genus, r.specific_epiphet, r.scientific_name, r.scientific_name_authorship,
       r.taxon_rank, r.taxon_id, r.taxon_id_db, r.verbatim_identification,
       r.accession_id, r.accession_id_ref_db, r.percent_match, r.percent_query_cover,
       r.percent_query_cover_hsp, r.alignment_length, r.subject_length,
       r.sequence_length, r.confidence_score, r.taxon_rank_db
FROM public.lca_raw_results r
WHERE r.og_id IS NOT NULL AND btrim(r.og_id) <> ''
  AND r.tech IS NOT NULL AND btrim(r.tech) <> ''
  AND r.seq_date IS NOT NULL AND btrim(r.seq_date) <> ''
  AND r.code IS NOT NULL AND btrim(r.code) <> ''
  AND r.annotation IS NOT NULL AND btrim(r.annotation) <> ''
  AND r.sequence_region IS NOT NULL AND btrim(r.sequence_region) <> ''
  AND r.lca_run_date IS NOT NULL
  AND r.accession_id IS NOT NULL AND btrim(r.accession_id) <> ''
  AND EXISTS (SELECT 1 FROM v2.mitogenome_data p
               WHERE p.og_id = r.og_id AND p.tech = r.tech
                 AND p.seq_date = r.seq_date AND p.code = r.code)
ON CONFLICT DO NOTHING;

SELECT v2.quarantine('lca_raw_results',
                     coalesce(r.og_id::text,'?') || '.' || coalesce(r.tech::text,'?') || '.' || coalesce(r.seq_date::text,'?') || '.' || coalesce(r.code::text,'?') || '.' || coalesce(r.annotation::text,'?') || '.' || coalesce(r.sequence_region::text,'?') || '.' || coalesce(r.lca_run_date::text,'?') || '.' || coalesce(r.accession_id::text,'?'),
                     'not_null', 'a key column is null or blank',
                     to_jsonb(r), 'LCA')
FROM public.lca_raw_results r
WHERE r.og_id IS NULL OR btrim(r.og_id) = ''
     OR r.tech IS NULL OR btrim(r.tech) = ''
     OR r.seq_date IS NULL OR btrim(r.seq_date) = ''
     OR r.code IS NULL OR btrim(r.code) = ''
     OR r.annotation IS NULL OR btrim(r.annotation) = ''
     OR r.sequence_region IS NULL OR btrim(r.sequence_region) = ''
     OR r.lca_run_date IS NULL
     OR r.accession_id IS NULL OR btrim(r.accession_id) = '';

SELECT v2.quarantine('lca_raw_results',
                     coalesce(r.og_id::text,'?') || '.' || coalesce(r.tech::text,'?') || '.' || coalesce(r.seq_date::text,'?') || '.' || coalesce(r.code::text,'?') || '.' || coalesce(r.annotation::text,'?') || '.' || coalesce(r.sequence_region::text,'?') || '.' || coalesce(r.lca_run_date::text,'?') || '.' || coalesce(r.accession_id::text,'?'),
                     'missing_parent', 'og_id is not in sample',
                     to_jsonb(r), 'LCA')
FROM public.lca_raw_results r
WHERE r.og_id IS NOT NULL AND btrim(r.og_id) <> ''
  AND r.tech IS NOT NULL AND btrim(r.tech) <> ''
  AND r.seq_date IS NOT NULL AND btrim(r.seq_date) <> ''
  AND r.code IS NOT NULL AND btrim(r.code) <> ''
  AND r.annotation IS NOT NULL AND btrim(r.annotation) <> ''
  AND r.sequence_region IS NOT NULL AND btrim(r.sequence_region) <> ''
  AND r.lca_run_date IS NOT NULL
  AND r.accession_id IS NOT NULL AND btrim(r.accession_id) <> ''
  AND NOT EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = r.og_id);

SELECT v2.quarantine('lca_raw_results',
                     coalesce(r.og_id::text,'?') || '.' || coalesce(r.tech::text,'?') || '.' || coalesce(r.seq_date::text,'?') || '.' || coalesce(r.code::text,'?') || '.' || coalesce(r.annotation::text,'?') || '.' || coalesce(r.sequence_region::text,'?') || '.' || coalesce(r.lca_run_date::text,'?') || '.' || coalesce(r.accession_id::text,'?'),
                     'missing_parent',
                     'no mitogenome_data row for (og_id, tech, seq_date, code)',
                     to_jsonb(r), 'LCA')
FROM public.lca_raw_results r
WHERE r.og_id IS NOT NULL AND btrim(r.og_id) <> ''
  AND r.tech IS NOT NULL AND btrim(r.tech) <> ''
  AND r.seq_date IS NOT NULL AND btrim(r.seq_date) <> ''
  AND r.code IS NOT NULL AND btrim(r.code) <> ''
  AND r.annotation IS NOT NULL AND btrim(r.annotation) <> ''
  AND r.sequence_region IS NOT NULL AND btrim(r.sequence_region) <> ''
  AND r.lca_run_date IS NOT NULL
  AND r.accession_id IS NOT NULL AND btrim(r.accession_id) <> ''
  AND EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = r.og_id)
  AND NOT EXISTS (SELECT 1 FROM v2.mitogenome_data p
                   WHERE p.og_id = r.og_id AND p.tech = r.tech
                     AND p.seq_date = r.seq_date AND p.code = r.code);

-- ---------------------------------------------------------------------------------------
-- 18. blast_filtered_lca
-- ---------------------------------------------------------------------------------------

INSERT INTO v2.blast_filtered_lca (
    og_id, tech, seq_date, code, annotation, match_sequence_id, taxon_id,
    scientific_name, common_name, kingdoms, percent_identity, alignment_length,
    query_length, subject_length, mismatch, gap_open, gaps, query_start, query_end,
    subject_start, subject_end, subject_title, evalue, bit_score, query_coverage,
    subject_coverage, "region", blast_run_date)
SELECT b.og_id, b.tech, b.seq_date, b.code, b.annotation, b.match_sequence_id,
       b.taxon_id, b.scientific_name, b.common_name, b.kingdoms, b.percent_identity,
       b.alignment_length, b.query_length, b.subject_length, b.mismatch, b.gap_open,
       b.gaps, b.query_start, b.query_end, b.subject_start, b.subject_end,
       b.subject_title, b.evalue, b.bit_score, b.query_coverage, b.subject_coverage,
       b."region", b.blast_run_date
FROM public.blast_filtered_lca b
WHERE b.og_id IS NOT NULL AND btrim(b.og_id) <> ''
  AND b.tech IS NOT NULL AND btrim(b.tech) <> ''
  AND b.seq_date IS NOT NULL AND btrim(b.seq_date) <> ''
  AND b.code IS NOT NULL AND btrim(b.code) <> ''
  AND b.annotation IS NOT NULL AND btrim(b.annotation) <> ''
  AND b.match_sequence_id IS NOT NULL AND btrim(b.match_sequence_id) <> ''
  AND b."region" IS NOT NULL AND btrim(b."region") <> ''
ON CONFLICT DO NOTHING;

SELECT v2.quarantine('blast_filtered_lca',
                     coalesce(b.og_id::text,'?') || '.' || coalesce(b.tech::text,'?') || '.' || coalesce(b.seq_date::text,'?') || '.' || coalesce(b.code::text,'?') || '.' || coalesce(b.annotation::text,'?') || '.' || coalesce(b.match_sequence_id::text,'?') || '.' || coalesce(b."region"::text,'?'),
                     'not_null', 'a key column is null or blank',
                     to_jsonb(b), 'LCA')
FROM public.blast_filtered_lca b
WHERE b.og_id IS NULL OR btrim(b.og_id) = ''
     OR b.tech IS NULL OR btrim(b.tech) = ''
     OR b.seq_date IS NULL OR btrim(b.seq_date) = ''
     OR b.code IS NULL OR btrim(b.code) = ''
     OR b.annotation IS NULL OR btrim(b.annotation) = ''
     OR b.match_sequence_id IS NULL OR btrim(b.match_sequence_id) = ''
     OR b."region" IS NULL OR btrim(b."region") = '';

SELECT v2.quarantine('blast_filtered_lca',
                     coalesce(b.og_id::text,'?') || '.' || coalesce(b.tech::text,'?') || '.' || coalesce(b.seq_date::text,'?') || '.' || coalesce(b.code::text,'?') || '.' || coalesce(b.annotation::text,'?') || '.' || coalesce(b.match_sequence_id::text,'?') || '.' || coalesce(b."region"::text,'?'),
                     'missing_parent', 'og_id is not in sample',
                     to_jsonb(b), 'LCA')
FROM public.blast_filtered_lca b
WHERE b.og_id IS NOT NULL AND btrim(b.og_id) <> ''
  AND b.tech IS NOT NULL AND btrim(b.tech) <> ''
  AND b.seq_date IS NOT NULL AND btrim(b.seq_date) <> ''
  AND b.code IS NOT NULL AND btrim(b.code) <> ''
  AND b.annotation IS NOT NULL AND btrim(b.annotation) <> ''
  AND b.match_sequence_id IS NOT NULL AND btrim(b.match_sequence_id) <> ''
  AND b."region" IS NOT NULL AND btrim(b."region") <> ''
  AND NOT EXISTS (SELECT 1 FROM v2.sample s WHERE s.og_id = b.og_id);


-- ---------------------------------------------------------------------------------------
-- Attempt-key ties: the rows the earliest-attempt filters discard
-- ---------------------------------------------------------------------------------------
--
-- Added 2026-10-05 (Phase V.1 item 6). Every insert above that targets a table with an
-- `*_attempt_key UNIQUE (parent, num)` constraint filters out the losers of a (parent, num)
-- tie. Before this statement existed the losers were simply not inserted and nothing recorded
-- them: 100 rows left the backfill without landing in either v2 or the quarantine.
--
-- That is the one outcome decision 6 exists to prevent, and it is also not what the schema
-- says happens. create_v2_lab_tables.sql's comment on dna_extraction_attempt_key states that
-- tied rows "quarantine for the lab to renumber". The constraint was written; the quarantine
-- statement was not. This is it.
--
-- The counts have roughly doubled since August, which is the other reason this matters. The
-- August note cites "5 of 2,223" on dna_extraction and "53 of 321" on 4.RNAIllumina as the
-- worst case. Measured against live 2026-10-05: rna_library_ilmn 107 of 389, dna_extraction
-- 49, hic_lysate 9, ont_library 4, pacbio_library 3, illumina_library 1, rna_library_kinx 1,
-- hic_library 0, rna_extraction 0. The ties are not a fixed historical artefact -- the lab
-- keeps creating them -- so this needs to be a standing report, not a one-off cleanup.
--
-- These rows are lost data, not duplicates: a tie means two real attempts were numbered the
-- same, so choosing one by tube-ID order is arbitrary. The lab renumbers, the next run loads
-- both.
--
-- THE TIE-BREAK, changed 2026-10-06 (Phase V.2, owner decision: prefer the workbook row).
-- Until then this seated the lexicographically-first tube ID of every tie. That was arbitrary
-- and sometimes wrong in a way that compounded: on (tissue_id, ext_num) = ('OG2111G', 1) it
-- seated `OG2111E_D` -- a row whose own prefix contradicts the tissue it is filed under -- and
-- quarantined `OG2111G_D`, the row the workbook actually carries. import_v2.py could not then
-- correct it, and aborted.
--
-- Now a tie is resolved against the workbook, staged by `import_v2.py --stage-attempt-keys`
-- into v2.workbook_attempt_keys (the guard at the top refuses to run without it):
--   - exactly one tied row appears in the workbook under the same (parent, attempt): it is
--     seated, and the others quarantine;
--   - none, or more than one, does: nothing is seated and every tied row quarantines. The
--     backfill does not pick a winner the lab has not picked.
-- The losers are computed once, in attempt_tie_losers, and both the nine inserts above and
-- this statement read it, so a tied row is always in exactly one of v2 or the quarantine.

-- 'unique' rather than a new violation_type: the quarantine vocabulary already defines it as
-- "collides with an existing row", which is exactly what an attempt-key tie is.
SELECT v2.quarantine(z.tbl, z.row_key, 'unique', z.detail, z.row_json, z.sheet)
FROM pg_temp.attempt_tie_losers z;

-- ---------------------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------------------

\echo ''
\echo '=== rows loaded ==='
SELECT 'sample' AS table_name, count(*) FROM v2.sample
UNION ALL SELECT 'tissue',            count(*) FROM v2.tissue
UNION ALL SELECT 'dna_extraction',    count(*) FROM v2.dna_extraction
UNION ALL SELECT 'rna_extraction',    count(*) FROM v2.rna_extraction
UNION ALL SELECT 'hic_lysate',        count(*) FROM v2.hic_lysate
UNION ALL SELECT 'library',           count(*) FROM v2.library
UNION ALL SELECT 'illumina_library',  count(*) FROM v2.illumina_library
UNION ALL SELECT 'pacbio_library',    count(*) FROM v2.pacbio_library
UNION ALL SELECT 'ont_library',       count(*) FROM v2.ont_library
UNION ALL SELECT 'hic_library',       count(*) FROM v2.hic_library
UNION ALL SELECT 'rna_library_ilmn',  count(*) FROM v2.rna_library_ilmn
UNION ALL SELECT 'rna_library_kinx',  count(*) FROM v2.rna_library_kinx
UNION ALL SELECT 'sequencing',        count(*) FROM v2.sequencing
UNION ALL SELECT 'mitogenome_data',    count(*) FROM v2.mitogenome_data
UNION ALL SELECT 'lca',                count(*) FROM v2.lca
UNION ALL SELECT 'lca_validation',     count(*) FROM v2.lca_validation
UNION ALL SELECT 'lca_raw_results',    count(*) FROM v2.lca_raw_results
UNION ALL SELECT 'blast_filtered_lca', count(*) FROM v2.blast_filtered_lca
ORDER BY 1;

\echo ''
\echo '=== what is blocked, for the lab ==='
SELECT * FROM v2.v_quarantine_open;

COMMIT;
