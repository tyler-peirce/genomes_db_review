-- scripts/backfill_v2.sql
--
-- Purpose: Copy the live public.* lab tables into the v2 schema, sending every row that
--   violates a v2 contract to v2.import_quarantine instead of dropping it or weakening the
--   schema to accommodate it (§5 step 8, decision 6).
--
-- Usage:
--     psql -h <host> -U <user> -d oceanomics_genomes -v ON_ERROR_STOP=1 -f scripts/backfill_v2.sql
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
  -- unique(tissue_id, ext_num): keep the first, quarantine the rest below
  AND NOT EXISTS (
        SELECT 1 FROM public.dna_extraction d2
         WHERE d2.tissue_id = d.tissue_id AND d2.ext_num = d.ext_num AND d2.dna_id < d.dna_id)
ORDER BY d.dna_id
ON CONFLICT (dna_id) DO NOTHING;

SELECT v2.quarantine('dna_extraction', d.dna_id, 'foreign_key',
                     'tissue_id ' || coalesce(d.tissue_id, '<null>') || ' has no tissue row',
                     to_jsonb(d), '3.DNAExtractions')
FROM public.dna_extraction d
WHERE d.dna_id IS NOT NULL AND btrim(d.dna_id) <> ''
  AND NOT EXISTS (SELECT 1 FROM v2.tissue t WHERE t.tissue_id = d.tissue_id);

SELECT v2.quarantine('dna_extraction', d.dna_id, 'unique',
                     'duplicate (tissue_id, ext_num) = (' || coalesce(d.tissue_id,'<null>')
                       || ', ' || coalesce(d.ext_num::text,'<null>') || '); the lab must renumber',
                     to_jsonb(d), '3.DNAExtractions')
FROM public.dna_extraction d
WHERE EXISTS (SELECT 1 FROM public.dna_extraction d2
               WHERE d2.tissue_id = d.tissue_id AND d2.ext_num = d.ext_num AND d2.dna_id < d.dna_id);

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
  AND NOT EXISTS (
        SELECT 1 FROM public.rna_extraction r2
         WHERE r2.tissue_id = r.tissue_id AND r2.ext_num = r.ext_num AND r2.rna_id < r.rna_id)
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
  AND NOT EXISTS (
        SELECT 1 FROM public.hic_lysate y2
         WHERE y2.tissue_id = y.tissue_id AND y2.lysate_num = y.lysate_num
           AND y2.lysate_id < y.lysate_id)
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
WHERE EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = i.illumina_library_tube_id)
  AND NOT EXISTS (SELECT 1 FROM public.illumina_library i2
                   WHERE i2.dna_id = i.dna_id AND i2.ilmn_num = i.ilmn_num
                     AND i2.illumina_library_tube_id < i.illumina_library_tube_id)
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
WHERE EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = p.pacbio_library_tube_id)
  AND NOT EXISTS (SELECT 1 FROM public.pacbio_library p2
                   WHERE p2.dna_id = p.dna_id AND p2.pacb_num = p.pacb_num
                     AND p2.pacbio_library_tube_id < p.pacbio_library_tube_id)
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
WHERE EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = o.ont_library_tube_id)
  AND NOT EXISTS (SELECT 1 FROM public.ont_library o2
                   WHERE o2.dna_id = o.dna_id AND o2.ont_num = o.ont_num
                     AND o2.ont_library_tube_id < o.ont_library_tube_id)
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
WHERE EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = h.hic_library_tube_id)
  AND NOT EXISTS (SELECT 1 FROM public.hic_library h2
                   WHERE h2.lysate_id = h.lysate_id AND h2.hic_num = h.hic_num
                     AND h2.hic_library_tube_id < h.hic_library_tube_id)
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
WHERE EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = x.rna_library_tube_id)
  AND NOT EXISTS (SELECT 1 FROM public.rna_library_ilmn x2
                   WHERE x2.rna_id = x.rna_id AND x2.rna_num = x.rna_num
                     AND x2.rna_library_tube_id < x.rna_library_tube_id)
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
WHERE EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = k.rna_library_tube_id)
  AND NOT EXISTS (SELECT 1 FROM public.rna_library_kinx k2
                   WHERE k2.rna_id = k.rna_id AND k2.rna_num = k.rna_num
                     AND k2.rna_library_tube_id < k.rna_library_tube_id)
ORDER BY k.rna_library_tube_id
ON CONFLICT (rna_library_tube_id) DO NOTHING;

-- Every library row whose registry entry could not be created — almost always a missing parent.
SELECT v2.quarantine(t.tbl, t.tube, 'foreign_key',
                     'no v2.library registry row; its parent extraction or lysate is missing',
                     t.row_json, t.sheet)
FROM (
    SELECT 'illumina_library' AS tbl, i.illumina_library_tube_id AS tube, to_jsonb(i) AS row_json, '4.Illumina' AS sheet
      FROM public.illumina_library i
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = i.illumina_library_tube_id)
    UNION ALL
    SELECT 'pacbio_library', p.pacbio_library_tube_id, to_jsonb(p), '4.PacBio'
      FROM public.pacbio_library p
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = p.pacbio_library_tube_id)
    UNION ALL
    SELECT 'ont_library', o.ont_library_tube_id, to_jsonb(o), '4.ONT'
      FROM public.ont_library o
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = o.ont_library_tube_id)
    UNION ALL
    SELECT 'hic_library', h.hic_library_tube_id, to_jsonb(h), '4.HiCLibrary'
      FROM public.hic_library h
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = h.hic_library_tube_id)
    UNION ALL
    SELECT 'rna_library_ilmn', x.rna_library_tube_id, to_jsonb(x), '4.RNAIllumina'
      FROM public.rna_library_ilmn x
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = x.rna_library_tube_id)
    UNION ALL
    SELECT 'rna_library_kinx', k.rna_library_tube_id, to_jsonb(k), '4.RNAkinnex'
      FROM public.rna_library_kinx k
     WHERE NOT EXISTS (SELECT 1 FROM v2.library l WHERE l.library_tube_id = k.rna_library_tube_id)
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
ORDER BY 1;

\echo ''
\echo '=== what is blocked, for the lab ==='
SELECT * FROM v2.v_quarantine_open;

COMMIT;
