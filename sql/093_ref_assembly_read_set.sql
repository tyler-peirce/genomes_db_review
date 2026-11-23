-- 093_ref_assembly_read_set.sql -- Every reference assembly has one HiFi read set; HiFiAdapterFilt per run.
--
-- Owner, 2026-11-23 (database_review.md Finding 17.5):
--   - Each assembly run has its own read set (GenomeScope + HiFiAdapterFilt): ref_assembly.read_set_id,
--     NOT NULL, enforced now.
--   - GenomeScope is per read set: the pool of reads that run assembled.
--   - HiFiAdapterFilt is per sequencing run (one .stats per cell BAM); a read set's figure is the sum.
-- Before: ref_read_set and ref_assembly met only through og_id + seq_date and two run lists filled
-- by different rules. 373 of 491 assemblies' PacBio links equalled a read set's runs.
--
-- Evidence (scratch on 2026-11-23, read-only; scripts in scripts/, results in sql/data/093_*.tsv):
--   - scripts/acacia_assembly_kmers.py: merqury's 31-mer total for an assembly equals
--     sum(hifi_yield - 30 * hifi_reads) over exactly the runs it was built from (OG90 v240821.hic1:
--     29,867,523,238 = OG90H_D2_SBL2_PACB_240821_AD to the base). 187 assemblies have a total on
--     Acacia; 122 solve exactly, 58 more within -1%/+6% (older hifi_read_qc yields run short).
--   - scripts/build_assembly_read_sets.py: each assembly's runs, from k-mers, then a sibling of the
--     same OG and date, then the earlier rules (links, same-date read set, cumulative match), else
--     its links, else none. sql/data/093_assembly_read_set.tsv has every decision and its source.
--   - scripts/match_adapter_filter_runs.py: 543 backed-up .stats files mapped to 295 runs; for the
--     153 read sets with both, the per-run sum equals the stored total in 152. OG57: both copies of
--     movie m64497e_231104_125241 report 1 read, the stored total is 0; the file is taken.
-- Changes:
--   - ref_hifi_adapter_filter_run: per-run counts, 302 runs (295 Acacia, 3 single-run read sets, 4 in
--     read sets whose stored total is 0). ref_hifi_adapter_filter stays a table: refdb's push writes
--     read-set totals with INSERT ... ON CONFLICT, which a view cannot take. Make it a view once the
--     push writes per run; v_ref_read_set_readiness lists the totals that disagree meanwhile.
--   - 30 new read sets (9 with no runs: batch dates such as OG711 230915, and the ONT assembly) and 3
--     corrected: OG683 241023 and OG749 250331 add the earlier run their assemblies' k-mers include;
--     OG838 240813 drops PACB_240520 (its GenomeScope input histogram equals the 240813 run alone).
--     New and corrected read sets keep the writers' key: the latest seq_date of their runs.
--   - ref_assembly.read_set_id NOT NULL. A new assembly gets one from ref_assembly_read_set_default():
--     an existing assembly with its key keeps its own (re-pushes); else the read set refdb's
--     read_set_runs() rule gives for the assembly's date (the OG's non-failed PacBio DNA runs up to
--     the date + 21 days, keyed by their latest seq_date), created if missing.
--   - refresh_assembly_runs(): an assembly's PacBio links are its read set's runs (87 added, 7 removed:
--     OG90 SBL3, OG836 SBL2, OG767 250331 and OG794 250317, which their k-mers leave out). ONT keeps
--     the date rule; Hi-C links stay hand-made. Triggers on ref_read_set_run and on
--     ref_assembly.read_set_id keep them current.
--   - v_ref_read_set_readiness: what is still missing or disagrees.
-- Not done here (writers, other repos): refdb.ensure_read_set re-adds the date rule's runs to an
-- existing read set on every push (OG838 240813 would get PACB_240520 back), and its all-None delete
-- path does not skip read sets an assembly uses (the FK refuses). HiFiAdapterFilt should push per run.
--
-- Apply: guards refuse unless live has the counts the data was built from. Replay: objects are
-- replaced and the backfill is skipped once ref_assembly.read_set_id exists.
-- Revert: sql/revert/093_ref_assembly_read_set_revert.sql.

BEGIN;

-- Per-run HiFiAdapterFilt -----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.ref_hifi_adapter_filter_run (
    sequencing_id text PRIMARY KEY REFERENCES public.sequencing (sequencing_id) ON DELETE CASCADE,
    contam_reads  bigint NOT NULL CHECK (contam_reads >= 0),
    source        text,
    loaded_at     timestamp with time zone NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.ref_hifi_adapter_filter_run_pacbio_only() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  tech  text;
  ltype text;
BEGIN
  SELECT s.technology, s.library_type INTO tech, ltype
    FROM public.v_sequencing_browse s WHERE s.sequencing_id = NEW.sequencing_id;
  IF tech IS NULL OR tech NOT IN ('PacBio HIFI', 'PacBio') OR ltype IS DISTINCT FROM 'pacbio' THEN
    RAISE EXCEPTION 'ref_hifi_adapter_filter_run: % is % / % sequencing; HiFiAdapterFilt runs on PacBio DNA',
      NEW.sequencing_id, coalesce(tech, 'unknown'), coalesce(ltype, 'unknown');
  END IF;
  RETURN NEW;
END
$fn$;
DROP TRIGGER IF EXISTS ref_hifi_adapter_filter_run_pacbio_only ON public.ref_hifi_adapter_filter_run;
CREATE TRIGGER ref_hifi_adapter_filter_run_pacbio_only BEFORE INSERT OR UPDATE ON public.ref_hifi_adapter_filter_run
  FOR EACH ROW EXECUTE FUNCTION public.ref_hifi_adapter_filter_run_pacbio_only();

-- Data (sql/data/093_*.tsv, 2026-11-23) ------------------------------------------------------------

CREATE TEMP TABLE d_adapter (
    sequencing_id text PRIMARY KEY,
    contam_reads  bigint NOT NULL,
    source        text NOT NULL
) ON COMMIT DROP;
INSERT INTO d_adapter VALUES
  ('OG100W_D2_SBL_PACB_240116_LAAD', 0, 'acacia: oceanomics-filtered-reads:OG100/hifi/qc_stats/OG100_m84154_240116_091558_s2.hifi_reads.bc2045.stats;OG100/hifi/qc_stats/OG100_m84154_240116_091558_s2.hifi_reads.unassigned.stats'),
  ('OG101H_D_SBL2_PACB_240206_AD', 0, 'acacia: oceanomics-filtered-reads:OG101/hifi/qc_stats/m84154_240207_144331_s3.hifi_reads.bc2054.stats;OG101/hifi/qc_stats/m84154_240207_144331_s3.hifi_reads.unassigned.stats'),
  ('OG104M_D_SBL2_PACB_241127_AD', 0, 'acacia: oceanomics-filtered-reads:OG104/hifi/OG104_OG104_m84154_241127_054344_s3.hifi_reads.bc2025.stats'),
  ('OG104M_D_SBL_PACB_250113_AD', 0, 'acacia: oceanomics-filtered-reads:OG104/hifi/OG104_OG104_m84154_250114_103159_s3.hifi_reads.bc2003.stats;OG104/hifi/OG104_OG104_m84154_250114_103159_s3.hifi_reads.unassigned.stats'),
  ('OG105H_D_SBL_PACB_231027_ADLA', 0, 'acacia: oceanomics-filtered-reads:OG105/hifi/qc_stats/OG105_m64497e_231101_183905.hifi_reads.bc2031--bc2031.stats;OG105/hifi/qc_stats/OG105_m64497e_231101_183905.unbarcoded.hifi_reads.stats;OG105/hifi/qc_stats/OG105_m64497e_231103_034603.hifi_reads.bc2031--bc2031.stats;OG105/hifi/qc_stats/OG105_m64497e_231103_034603.unbarcoded.hifi_reads.stats'),
  ('OG106G_D2_SBL_PACB_240927_LA', 0, 'acacia: oceanomics-filtered-reads:OG106/hifi/OG106_m84154_240927_145748_s4.hifi_reads.bc2058.stats'),
  ('OG107G_D_SBL_PACB_240125_LA', 0, 'acacia: oceanomics-filtered-reads:OG107/hifi/qc_stats/m64497e_240125_060256.hifi_reads.bc2042--bc2042.stats;OG107/hifi/qc_stats/m64497e_240125_060256.unbarcoded.hifi_reads.stats;OG107/hifi/qc_stats/m64497e_240126_131338.hifi_reads.bc2042--bc2042.stats;OG107/hifi/qc_stats/m64497e_240126_131338.unbarcoded.hifi_reads.stats'),
  ('OG108H_D_SBL_PACB_231027_ADLA', 0, 'acacia: oceanomics-filtered-reads:OG108/hifi/qc_stats/OG108_m64497e_231031_093234.hifi_reads.bc2030--bc2030.stats;OG108/hifi/qc_stats/OG108_m64497e_231031_093234.unbarcoded.hifi_reads.stats'),
  ('OG109M_D_SBL_PACB_250828_AD', 0, 'acacia: oceanomics-filtered-reads:OG109/hifi/OG109_m84154_250828_080825_s2.hifi_reads.stats'),
  ('OG10G_D_SBL_PACB_230209_LP', 0, 'acacia: oceanomics-filtered-reads:OG10/hifi/qc_stats/m64497e_230209_083103.hifi_reads.bc2001--bc2001.stats;OG10/hifi/qc_stats/m64497e_230209_083103.unbarcoded.hifi_reads.stats;OG10/hifi/qc_stats/m64497e_230210_181327.hifi_reads.bc2001--bc2001.stats;OG10/hifi/qc_stats/m64497e_230210_181327.unbarcoded.hifi_reads.stats'),
  ('OG111H_D_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG111/hifi/OG111_m84154_241018_072321_s3.hifi_reads.bc2082.stats'),
  ('OG113G_D_SBL_PACB_231027_ADLA', 0, 'acacia: oceanomics-filtered-reads:OG113/hifi/qc_stats/OG113_m64497e_231028_151022.hifi_reads.bc2033--bc2033.stats;OG113/hifi/qc_stats/OG113_m64497e_231028_151022.unbarcoded.hifi_reads.stats;OG113/hifi/qc_stats/OG113_m64497e_231030_002313.hifi_reads.bc2033--bc2033.stats;OG113/hifi/qc_stats/OG113_m64497e_231030_002313.unbarcoded.hifi_reads.stats'),
  ('OG114H_D_SBL2_PACB_240116_LAAD', 0, 'acacia: oceanomics-filtered-reads:OG114/hifi/qc_stats/OG114_m84154_240116_131450_s4.hifi_reads.bc2043.stats;OG114/hifi/qc_stats/OG114_m84154_240116_131450_s4.hifi_reads.unassigned.stats'),
  ('OG115H_D_SBL_PACB_240125_LA', 0, 'acacia: oceanomics-filtered-reads:OG115/hifi/qc_stats/m64497e_240127_203512.hifi_reads.bc2044--bc2044.stats;OG115/hifi/qc_stats/m64497e_240127_203512.unbarcoded.hifi_reads.stats;OG115/hifi/qc_stats/m64497e_240129_035650.hifi_reads.bc2044--bc2044.stats;OG115/hifi/qc_stats/m64497e_240129_035650.unbarcoded.hifi_reads.stats'),
  ('OG1161B_D4_SBL_PACB_250113_AD', 0, 'acacia: oceanomics-filtered-reads:OG1161/hifi/OG1161_OG1161_m84154_250114_063309_s1.hifi_reads.bc2030.stats;OG1161/hifi/OG1161_OG1161_m84154_250114_063309_s1.hifi_reads.unassigned.stats'),
  ('OG1161B_D5_SBL_PACB_250113_AD', 0, 'acacia: oceanomics-filtered-reads:OG1161/hifi/OG1161_OG1161_m84154_250114_083230_s2.hifi_reads.bc2050.stats;OG1161/hifi/OG1161_OG1161_m84154_250114_083230_s2.hifi_reads.unassigned.stats'),
  ('OG11G_D_SBL_PACB_230825_AD', 0, 'acacia: oceanomics-filtered-reads:OG11/hifi/qc_stats/OG11_m64497e_230828_002959.hifi_reads.bc2023--bc2023.stats;OG11/hifi/qc_stats/OG11_m64497e_230828_002959.unbarcoded.hifi_reads.stats;OG11/hifi/qc_stats/OG11_m64497e_230829_094307.hifi_reads.bc2023--bc2023.stats;OG11/hifi/qc_stats/OG11_m64497e_230829_094307.unbarcoded.hifi_reads.stats'),
  ('OG1297B_D_SBL_PACB_250818_AD', 0, 'acacia: oceanomics-filtered-reads:OG1297/hifi/OG1297_m84154_250818_075539_s1.hifi_reads.bc2018.stats;OG1297/hifi/OG1297_m84154_250818_075539_s1.hifi_reads.unassigned.stats;OG1297/hifi/OG1297_m84154_250818_095657_s2.hifi_reads.bc2018.stats;OG1297/hifi/OG1297_m84154_250818_095657_s2.hifi_reads.unassigned.stats'),
  ('OG12G_D_SBL_PACB_230512_AD', 0, 'acacia: oceanomics-filtered-reads:OG12/hifi/qc_stats/m64497e_230515_024824.hifi_reads.bc2007--bc2007.stats;OG12/hifi/qc_stats/m64497e_230515_024824.unbarcoded.hifi_reads.stats;OG12/hifi/qc_stats/m64497e_230516_115543.hifi_reads.bc2007--bc2007.stats;OG12/hifi/qc_stats/m64497e_230516_115543.unbarcoded.hifi_reads.stats'),
  ('OG1326H_D2_SBL_PACB_260730_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1326/hifi/OG1326_m84154_260730_095056_s4.hifi_reads.bc2040.stats'),
  ('OG1369H_D_SBL_PACB_260227_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1369/hifi/OG1369_m84154_260227_073225_s1.hifi_reads.bc2027.stats'),
  ('OG13G_D_SBL_PACB_230209_LP', 0, 'acacia: oceanomics-filtered-reads:OG13/hifi/qc_stats/m64497e_230212_034047.hifi_reads.bc2002--bc2002.stats;OG13/hifi/qc_stats/m64497e_230212_034047.unbarcoded.hifi_reads.stats;OG13/hifi/qc_stats/m64497e_230223_080147.hifi_reads.bc2002--bc2002.stats'),
  ('OG1422H_D_SBL_PACB_260227_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1422/hifi/OG1422_m84154_260228_133037_s2.hifi_reads.bc2028.stats'),
  ('OG1454H_D_SBL_PACB_260227_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1454/hifi/OG1454_m84154_260228_133037_s2.hifi_reads.bc2029.stats'),
  ('OG1454H_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG1454/hifi/OG1454_m84154_260722_083928_s1.hifi_reads.bc2029.stats'),
  ('OG1455H_D_SBL_PACB_260331_AMDLA', 0, 'acacia: oceanomics-filtered-reads:OG1455/hifi/OG1455_m84154_260331_060713_s1.hifi_reads.bc2030.stats;OG1455/hifi/OG1455_m84154_260331_060713_s1.hifi_reads.unassigned.stats'),
  ('OG14G_D_SBL_PACB_230209_LP', 0, 'acacia: oceanomics-filtered-reads:OG14/hifi/qc_stats/m64497e_230213_143552.hifi_reads.bc2003--bc2003.stats;OG14/hifi/qc_stats/m64497e_230213_143552.unbarcoded.hifi_reads.stats;OG14/hifi/qc_stats/m64497e_230223_080147.hifi_reads.bc2003--bc2003.stats'),
  ('OG1560G_D_SBL_PACB_260408_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1560/hifi/OG1560_m84154_260408_090630_s1.hifi_reads.bc2032.stats;OG1560/hifi/OG1560_m84154_260408_090630_s1.hifi_reads.unassigned.stats'),
  ('OG1568G_D_SBL_PACB_261102_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1568/hifi/OG1568_m84154_261103_094620_s3.hifi_reads.bc2050.stats'),
  ('OG1573M_D_SBL_PACB_260626_AMDTW', 0, 'acacia: oceanomics-filtered-reads:OG1573/hifi/OG1573_m84154_260626_075836_s1.hifi_reads.bc2096.stats;OG1573/hifi/OG1573_m84154_260626_075836_s1.hifi_reads.unassigned.stats'),
  ('OG1582W_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG1582/hifi/OG1582_m84154_260722_094402_s3.hifi_reads.bc2027.stats'),
  ('OG1585M_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG1585/hifi/OG1585_m84154_260722_101618_s4.hifi_reads.bc2023.stats'),
  ('OG1591M_D_SBL_PACB_261102_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1591/hifi/OG1591_m84154_261102_085434_s2.hifi_reads.bc2043.stats'),
  ('OG1592W_D_SBL_PACB_261102_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1592/hifi/OG1592_m84154_261103_101747_s4.hifi_reads.bc2035.stats'),
  ('OG15G_D_SBL_PACB_230413_AD', 0, 'acacia: oceanomics-filtered-reads:OG15/hifi/qc_stats/m64497e_230416_021242.hifi_reads.bc2005--bc2005.stats;OG15/hifi/qc_stats/m64497e_230416_021242.unbarcoded.hifi_reads.stats;OG15/hifi/qc_stats/m64497e_230417_130841.hifi_reads.bc2005--bc2005.stats;OG15/hifi/qc_stats/m64497e_230417_130841.unbarcoded.hifi_reads.stats'),
  ('OG1613M_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1613/hifi/OG1613_m84154_260604_164957_s3.hifi_reads.bc2088.stats;OG1613/hifi/OG1613_m84154_260604_164957_s3.hifi_reads.unassigned.stats'),
  ('OG1639G_D_SBL_PACB_260626_AMDTW', 0, 'acacia: oceanomics-filtered-reads:OG1639/hifi/OG1639_m84154_260627_115156_s1.hifi_reads.bc2001.stats'),
  ('OG1643M_D_SBL_PACB_261102_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1643/hifi/OG1643_m84154_261102_092601_s3.hifi_reads.bc2028.stats'),
  ('OG1650H_D_SBL_PACB_260331_AMDLA', 0, 'acacia: oceanomics-filtered-reads:OG1650/hifi/OG1650_m84154_260331_080833_s2.hifi_reads.bc2033.stats;OG1650/hifi/OG1650_m84154_260331_080833_s2.hifi_reads.unassigned.stats'),
  ('OG1651G_D2_SBL_PACB_260522_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1651/hifi/OG1651_m84154_260522_074822_s1.hifi_reads.bc2061.stats'),
  ('OG1653G_D_SBL_PACB_261102_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1653/hifi/OG1653_m84154_261103_101747_s4.hifi_reads.bc2051.stats'),
  ('OG1663G_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1663/hifi/OG1663_m84154_260604_144645_s2.hifi_reads.bc2009.stats'),
  ('OG1678G_D2_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1678/hifi/OG1678_m84154_260603_105325_s2.hifi_reads.bc2004.stats'),
  ('OG1681M_D_SBL_PACB_261102_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1681/hifi/OG1681_m84154_261103_091453_s2.hifi_reads.bc2025.stats'),
  ('OG1699G_D_SBL_PACB_260421_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1699/hifi/OG1699_m84154_260421_072235_s1.hifi_reads.bc2067.stats;OG1699/hifi/OG1699_m84154_260421_072235_s1.hifi_reads.unassigned.stats'),
  ('OG16G_D_SBL_PACB_240427_LA', 0, 'acacia: oceanomics-filtered-reads:OG16/hifi/qc_stats/OG16_m84154_240417_083812_s1.hifi_reads.bc2079.stats;OG16/hifi/qc_stats/OG16_m84154_240417_083812_s1.hifi_reads.unassigned.stats'),
  ('OG1701G_D_SBL_PACB_260428_AMD', 0, 'acacia: oceanomics-filtered-reads:OG1701/hifi/OG1701_m84154_260428_065028_s1.hifi_reads.bc2065.stats;OG1701/hifi/OG1701_m84154_260428_065028_s1.hifi_reads.unassigned.stats'),
  ('OG1G_D_SBL_PACB_230525_AD', 0, 'acacia: oceanomics-filtered-reads:OG1/hifi/qc_stats/m64497e_230525_065409.hifi_reads.bc2009--bc2009.stats;OG1/hifi/qc_stats/m64497e_230525_065409.unbarcoded.hifi_reads.stats;OG1/hifi/qc_stats/m64497e_230526_155933.hifi_reads.bc2009--bc2009.stats;OG1/hifi/qc_stats/m64497e_230526_155933.unbarcoded.hifi_reads.stats'),
  ('OG2087E_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2087/hifi/OG2087_m84154_260721_085324_s2.hifi_reads.bc2037.stats'),
  ('OG2088G_D_SBL_PACB_260414_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2088/hifi/OG2088_m84154_260414_082242_s1.hifi_reads.bc2069.stats;OG2088/hifi/OG2088_m84154_260414_082242_s1.hifi_reads.unassigned.stats'),
  ('OG2089G_D_SBL_PACB_260227_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2089/hifi/OG2089_m84154_260227_093340_s2.hifi_reads.bc2020.stats'),
  ('OG2089G_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2089/hifi/OG2089_m84154_260721_082111_s1.hifi_reads.bc2020.stats'),
  ('OG2090E_D_SBL_PACB_260303_AD', 0, 'acacia: oceanomics-filtered-reads:OG2090/hifi/OG2090_m84154_260303_065318_s1.hifi_reads.bc2022.stats;OG2090/hifi/OG2090_m84154_260303_065318_s1.hifi_reads.unassigned.stats'),
  ('OG2092E_D_SBL_PACB_260626_AMDTW', 0, 'acacia: oceanomics-filtered-reads:OG2092/hifi/OG2092_m84154_260627_180132_s4.hifi_reads.bc2089.stats;OG2092/hifi/OG2092_m84154_260627_180132_s4.hifi_reads.unassigned.stats'),
  ('OG2093E_D_SBL_PACB_260227_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2093/hifi/OG2093_m84154_260228_112832_s1.hifi_reads.bc2021.stats'),
  ('OG2093E_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2093/hifi/OG2093_m84154_260721_092541_s3.hifi_reads.bc2021.stats'),
  ('OG2095G_D_SBL_PACB_261102_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2095/hifi/OG2095_m84154_261103_094620_s3.hifi_reads.bc2030.stats'),
  ('OG2097E_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2097/hifi/OG2097_m84154_260722_083928_s1.hifi_reads.bc2006.stats'),
  ('OG2098M_D_SBL_PACB_260511_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2098/hifi/OG2098_m84154_260511_090209_s2.hifi_reads.bc2079.stats;OG2098/hifi/OG2098_m84154_260511_090209_s2.hifi_reads.unassigned.stats'),
  ('OG2099M_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2099/hifi/OG2099_m84154_260603_085016_s1.hifi_reads.bc2090.stats;OG2099/hifi/OG2099_m84154_260603_085016_s1.hifi_reads.unassigned.stats'),
  ('OG2100G_D_SBL_PACB_260227_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2100/hifi/OG2100_m84154_260228_112832_s1.hifi_reads.bc2023.stats'),
  ('OG2100G_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2100/hifi/OG2100_m84154_260721_092541_s3.hifi_reads.bc2023.stats'),
  ('OG2102G_D_SBL_PACB_260227_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2102/hifi/OG2102_m84154_260227_093340_s2.hifi_reads.bc2024.stats'),
  ('OG2104E_D_SBL_PACB_260414_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2104/hifi/OG2104_m84154_260414_102403_s2.hifi_reads.bc2066.stats;OG2104/hifi/OG2104_m84154_260414_102403_s2.hifi_reads.unassigned.stats'),
  ('OG2105G_D_SBL2_PACB_260421_AMD', 0, 'zero_total: ref_hifi_adapter_filter: read set 63 (OG2105 260421) total 0 over 2 runs'),
  ('OG2105G_D_SBL_PACB_260421_AMD', 0, 'zero_total: ref_hifi_adapter_filter: read set 63 (OG2105 260421) total 0 over 2 runs'),
  ('OG2109M_D_SBL_PACB_260626_AMDTW', 0, 'acacia: oceanomics-filtered-reads:OG2109/hifi/OG2109_m84154_260627_135518_s2.hifi_reads.bc2022.stats;OG2109/hifi/OG2109_m84154_260627_135518_s2.hifi_reads.unassigned.stats'),
  ('OG2112M_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2112/hifi/OG2112_m84154_260603_105325_s2.hifi_reads.bc2080.stats'),
  ('OG2113M_D_SBL_PACB_260522_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2113/hifi/OG2113_m84154_260522_115428_s3.hifi_reads.bc2053.stats;OG2113/hifi/OG2113_m84154_260522_115428_s3.hifi_reads.unassigned.stats'),
  ('OG2116M_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2116/hifi/OG2116_m84154_260603_145925_s4.hifi_reads.bc2094.stats;OG2116/hifi/OG2116_m84154_260603_145925_s4.hifi_reads.unassigned.stats'),
  ('OG2118E_D_SBL_PACB_260626_AMDTW', 0, 'acacia: oceanomics-filtered-reads:OG2118/hifi/OG2118_m84154_260626_100143_s2.hifi_reads.bc2095.stats;OG2118/hifi/OG2118_m84154_260626_100143_s2.hifi_reads.unassigned.stats'),
  ('OG2119E_D_SBL_PACB_260408_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2119/hifi/OG2119_m84154_260408_110745_s2.hifi_reads.bc2034.stats;OG2119/hifi/OG2119_m84154_260408_110745_s2.hifi_reads.unassigned.stats'),
  ('OG2120E_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2120/hifi/OG2120_m84154_260721_095758_s4.hifi_reads.bc2081.stats'),
  ('OG2121E_D_SBL_PACB_260511_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2121/hifi/OG2121_m84154_260511_110417_s3.hifi_reads.bc2082.stats;OG2121/hifi/OG2121_m84154_260511_110417_s3.hifi_reads.unassigned.stats'),
  ('OG2122E_D_SBL_PACB_260511_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2122/hifi/OG2122_m84154_260511_130624_s4.hifi_reads.bc2083.stats;OG2122/hifi/OG2122_m84154_260511_130624_s4.hifi_reads.unassigned.stats'),
  ('OG2123E_D2_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2123/hifi/OG2123_m84154_260721_085324_s2.hifi_reads.bc2054.stats'),
  ('OG2124G_D_SBL_PACB_260421_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2124/hifi/OG2124_m84154_260421_112603_s3.hifi_reads.bc2059.stats;OG2124/hifi/OG2124_m84154_260421_112603_s3.hifi_reads.unassigned.stats'),
  ('OG2126E_D_SBL_PACB_260511_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2126/hifi/OG2126_m84154_260512_105713_s1.hifi_reads.bc2078.stats;OG2126/hifi/OG2126_m84154_260512_105713_s1.hifi_reads.unassigned.stats'),
  ('OG2126E_D_SBL_PACB_260730_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2126/hifi/OG2126_m84154_260730_081409_s1.hifi_reads.bc2078.stats;OG2126/hifi/OG2126_m84154_260730_081409_s1.hifi_reads.unassigned.stats'),
  ('OG2127E_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2127/hifi/OG2127_m84154_260603_125624_s3.hifi_reads.bc2084.stats'),
  ('OG2128E_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2128/hifi/OG2128_m84154_260603_125624_s3.hifi_reads.bc2085.stats'),
  ('OG2128E_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2128/hifi/OG2128_m84154_260721_095758_s4.hifi_reads.bc2085.stats'),
  ('OG2130G_D_SBL_PACB_260428_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2130/hifi/OG2130_m84154_260428_085154_s2.hifi_reads.bc2077.stats;OG2130/hifi/OG2130_m84154_260428_085154_s2.hifi_reads.unassigned.stats'),
  ('OG2131E_D_SBL_PACB_260511_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2131/hifi/OG2131_m84154_260512_125916_s2.hifi_reads.bc2086.stats;OG2131/hifi/OG2131_m84154_260512_125916_s2.hifi_reads.unassigned.stats'),
  ('OG2132E_D_SBL_PACB_260408_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2132/hifi/OG2132_m84154_260408_130952_s3.hifi_reads.bc2044.stats;OG2132/hifi/OG2132_m84154_260408_130952_s3.hifi_reads.unassigned.stats'),
  ('OG2133E_D_SBL_PACB_260522_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2133/hifi/OG2133_m84154_260522_074822_s1.hifi_reads.bc2003.stats'),
  ('OG2134E_D_SBL_PACB_260511_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2134/hifi/OG2134_m84154_260512_150116_s3.hifi_reads.bc2087.stats;OG2134/hifi/OG2134_m84154_260512_150116_s3.hifi_reads.unassigned.stats'),
  ('OG2135E_D_SBL_PACB_260730_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2135/hifi/OG2135_m84154_260730_095056_s4.hifi_reads.bc2031.stats'),
  ('OG2136E_D_SBL_PACB_260730_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2136/hifi/OG2136_m84154_260730_091839_s3.hifi_reads.bc2033.stats'),
  ('OG2137E_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2137/hifi/OG2137_m84154_260722_091145_s2.hifi_reads.bc2014.stats'),
  ('OG2138E_D_SBL_PACB_260626_AMDTW', 0, 'acacia: oceanomics-filtered-reads:OG2138/hifi/OG2138_m84154_260626_120458_s3.hifi_reads.bc2029.stats;OG2138/hifi/OG2138_m84154_260626_120458_s3.hifi_reads.unassigned.stats'),
  ('OG2139E_D_SBL_PACB_260721_AD', 0, 'acacia: oceanomics-filtered-reads:OG2139/hifi/OG2139_m84154_260722_091145_s2.hifi_reads.bc2051.stats'),
  ('OG2142G_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2142/hifi/OG2142_m84154_260604_124345_s1.hifi_reads.bc2010.stats'),
  ('OG2143E_D_SBL_PACB_260421_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2143/hifi/OG2143_m84154_260421_132813_s4.hifi_reads.bc2062.stats;OG2143/hifi/OG2143_m84154_260421_132813_s4.hifi_reads.unassigned.stats'),
  ('OG2145G_D_SBL_PACB_260522_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2145/hifi/OG2145_m84154_260522_135728_s4.hifi_reads.bc2068.stats;OG2145/hifi/OG2145_m84154_260522_135728_s4.hifi_reads.unassigned.stats'),
  ('OG2145G_D_SBL_PACB_260730_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2145/hifi/OG2145_m84154_260730_091839_s3.hifi_reads.bc2068.stats'),
  ('OG2146H_D_SBL_PACB_260414_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2146/hifi/OG2146_m84154_260414_122609_s3.hifi_reads.bc2058.stats;OG2146/hifi/OG2146_m84154_260414_122609_s3.hifi_reads.unassigned.stats'),
  ('OG2151H_D_SBL_PACB_260421_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2151/hifi/OG2151_m84154_260422_111851_s1.hifi_reads.bc2060.stats;OG2151/hifi/OG2151_m84154_260422_111851_s1.hifi_reads.unassigned.stats'),
  ('OG2156H_D_SBL_PACB_260408_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2156/hifi/OG2156_m84154_260408_151158_s4.hifi_reads.bc2035.stats;OG2156/hifi/OG2156_m84154_260408_151158_s4.hifi_reads.unassigned.stats'),
  ('OG2159H_D_SBL_PACB_260408_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2159/hifi/OG2159_m84154_260409_130247_s1.hifi_reads.bc2036.stats;OG2159/hifi/OG2159_m84154_260409_130247_s1.hifi_reads.unassigned.stats'),
  ('OG2161H_D_SBL_PACB_260331_AMDLA', 0, 'acacia: oceanomics-filtered-reads:OG2161/hifi/OG2161_m84154_260401_100330_s1.hifi_reads.bc2037.stats;OG2161/hifi/OG2161_m84154_260401_100330_s1.hifi_reads.unassigned.stats;OG2161/hifi/OG2161_m84154_260401_140756_s3.hifi_reads.bc2041.stats;OG2161/hifi/OG2161_m84154_260401_140756_s3.hifi_reads.unassigned.stats'),
  ('OG2163H_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2163/hifi/OG2163_m84154_260604_124345_s1.hifi_reads.bc2018.stats'),
  ('OG2164H_D_SBL_PACB_260331_AMDLA', 0, 'acacia: oceanomics-filtered-reads:OG2164/hifi/OG2164_m84154_260401_160959_s4.hifi_reads.bc2039.stats;OG2164/hifi/OG2164_m84154_260401_160959_s4.hifi_reads.unassigned.stats'),
  ('OG2165H_D_SBL_PACB_260428_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2165/hifi/OG2165_m84154_260428_105403_s3.hifi_reads.bc2064.stats;OG2165/hifi/OG2165_m84154_260428_105403_s3.hifi_reads.unassigned.stats'),
  ('OG2166H_D_SBL_PACB_260331_AMDLA', 0, 'acacia: oceanomics-filtered-reads:OG2166/hifi/OG2166_m84154_260331_101042_s3.hifi_reads.bc2040.stats;OG2166/hifi/OG2166_m84154_260331_101042_s3.hifi_reads.unassigned.stats'),
  ('OG2177H_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2177/hifi/OG2177_m84154_260604_185305_s4.hifi_reads.bc2017.stats'),
  ('OG2178H_D_SBL_PACB_260408_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2178/hifi/OG2178_m84154_260409_150449_s2.hifi_reads.bc2045.stats;OG2178/hifi/OG2178_m84154_260409_150449_s2.hifi_reads.unassigned.stats'),
  ('OG2179M_D_SBL_PACB_260428_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2179/hifi/OG2179_m84154_260428_125610_s4.hifi_reads.bc2046.stats;OG2179/hifi/OG2179_m84154_260428_125610_s4.hifi_reads.unassigned.stats'),
  ('OG2182H_D2_SBL_PACB_260331_AMDLA', 0, 'acacia: oceanomics-filtered-reads:OG2182/hifi/OG2182_m84154_260331_121250_s4.hifi_reads.bc2042.stats;OG2182/hifi/OG2182_m84154_260331_121250_s4.hifi_reads.unassigned.stats'),
  ('OG2188H_D_SBL_PACB_260408_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2188/hifi/OG2188_m84154_260409_170655_s3.hifi_reads.bc2047.stats;OG2188/hifi/OG2188_m84154_260409_170655_s3.hifi_reads.unassigned.stats'),
  ('OG2189H_D_SBL_PACB_260414_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2189/hifi/OG2189_m84154_260414_142815_s4.hifi_reads.bc2043.stats;OG2189/hifi/OG2189_m84154_260414_142815_s4.hifi_reads.unassigned.stats'),
  ('OG2200H_D_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2200/hifi/OG2200_m84154_260604_144645_s2.hifi_reads.bc2020.stats'),
  ('OG2202H_D_SBL_PACB_260331_AMDLA', 0, 'acacia: oceanomics-filtered-reads:OG2202/hifi/OG2202_m84154_260401_120542_s2.hifi_reads.bc2048.stats;OG2202/hifi/OG2202_m84154_260401_120542_s2.hifi_reads.unassigned.stats'),
  ('OG2203H_D_SBL_PACB_260408_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2203/hifi/OG2203_m84154_260409_190903_s4.hifi_reads.bc2049.stats;OG2203/hifi/OG2203_m84154_260409_190903_s4.hifi_reads.unassigned.stats'),
  ('OG2205H_D_SBL_PACB_260522_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2205/hifi/OG2205_m84154_260522_095124_s2.hifi_reads.bc2005.stats'),
  ('OG2209H_D_SBL_PACB_260626_AMDTW', 0, 'acacia: oceanomics-filtered-reads:OG2209/hifi/OG2209_m84154_260627_115156_s1.hifi_reads.bc2013.stats'),
  ('OG2218H_D_SBL_PACB_260428_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2218/hifi/OG2218_m84154_260429_104657_s1.hifi_reads.bc2038.stats;OG2218/hifi/OG2218_m84154_260429_104657_s1.hifi_reads.unassigned.stats'),
  ('OG2220H_D_SBL_PACB_260421_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2220/hifi/OG2220_m84154_260422_152311_s3.hifi_reads.bc2063.stats;OG2220/hifi/OG2220_m84154_260422_152311_s3.hifi_reads.unassigned.stats'),
  ('OG2227H_D2_SBL_PACB_260414_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2227/hifi/OG2227_m84154_260415_121904_s1.hifi_reads.bc2071.stats;OG2227/hifi/OG2227_m84154_260415_121904_s1.hifi_reads.unassigned.stats'),
  ('OG2237H_D_SBL_PACB_260414_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2237/hifi/OG2237_m84154_260415_142111_s2.hifi_reads.bc2075.stats;OG2237/hifi/OG2237_m84154_260415_142111_s2.hifi_reads.unassigned.stats'),
  ('OG2241H_D2_SBL_PACB_260414_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2241/hifi/OG2241_m84154_260415_162313_s3.hifi_reads.bc2073.stats;OG2241/hifi/OG2241_m84154_260415_162313_s3.hifi_reads.unassigned.stats'),
  ('OG2242H_D_SBL_PACB_260414_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2242/hifi/OG2242_m84154_260415_182521_s4.hifi_reads.bc2072.stats;OG2242/hifi/OG2242_m84154_260415_182521_s4.hifi_reads.unassigned.stats'),
  ('OG2266H_D_SBL_PACB_260511_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2266/hifi/OG2266_m84154_260512_170333_s4.hifi_reads.bc2056.stats;OG2266/hifi/OG2266_m84154_260512_170333_s4.hifi_reads.unassigned.stats'),
  ('OG2268H_D2_SBL_PACB_260428_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2268/hifi/OG2268_m84154_260429_124906_s2.hifi_reads.bc2076.stats;OG2268/hifi/OG2268_m84154_260429_124906_s2.hifi_reads.unassigned.stats'),
  ('OG2269G_D_SBL_PACB_260428_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2269/hifi/OG2269_m84154_260429_145110_s3.hifi_reads.bc2074.stats;OG2269/hifi/OG2269_m84154_260429_145110_s3.hifi_reads.unassigned.stats'),
  ('OG2317B_D_SBL2_PACB_260303_AD', 0, 'acacia: oceanomics-filtered-reads:OG2317/hifi/OG2317_m84154_260304_104941_s1.hifi_reads.bc2031.stats;OG2317/hifi/OG2317_m84154_260304_104941_s1.hifi_reads.unassigned.stats'),
  ('OG2317B_D_SBL_PACB_260303_AD', 0, 'acacia: oceanomics-filtered-reads:OG2317/hifi/OG2317_m84154_260303_085443_s2.hifi_reads.bc2025.stats;OG2317/hifi/OG2317_m84154_260303_085443_s2.hifi_reads.unassigned.stats'),
  ('OG2320B_D2_SBL_PACB_260303_AD', 0, 'acacia: oceanomics-filtered-reads:OG2320/hifi/OG2320_m84154_260304_125148_s2.hifi_reads.bc2026.stats;OG2320/hifi/OG2320_m84154_260304_125148_s2.hifi_reads.unassigned.stats'),
  ('OG2325H_D2_SBL_PACB_260428_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2325/hifi/OG2325_m84154_260429_165315_s4.hifi_reads.bc2070.stats;OG2325/hifi/OG2325_m84154_260429_165315_s4.hifi_reads.unassigned.stats'),
  ('OG2408B_D_SBL_PACB_261102_AMD', 0, 'acacia: oceanomics-filtered-reads:OG2408/hifi/OG2408_m84154_261102_095728_s4.hifi_reads.bc2034.stats;OG2408/hifi/OG2408_m84154_261103_084326_s1.hifi_reads.bc2034.stats'),
  ('OG27B_D_SBL_PACB_230512_AD', 0, 'acacia: oceanomics-filtered-reads:OG27/hifi/qc_stats/m64497e_230517_210015.hifi_reads.bc2008--bc2008.stats;OG27/hifi/qc_stats/m64497e_230517_210015.unbarcoded.hifi_reads.stats;OG27/hifi/qc_stats/m64497e_230519_061404.hifi_reads.bc2008--bc2008.stats;OG27/hifi/qc_stats/m64497e_230519_061404.unbarcoded.hifi_reads.stats;OG27/hifi/qc_stats/m64497e_230520_153629.hifi_reads.bc2008--bc2008.stats;OG27/hifi/qc_stats/m64497e_230520_153629.unbarcoded.hifi_reads.stats;OG27/hifi/qc_stats/m64497e_230522_004953.hifi_reads.bc2008--bc2008.stats;OG27/hifi/qc_stats/m64497e_230522_004953.unbarcoded.hifi_reads.stats'),
  ('OG28B_D4_SBL_PACB_230811_AD', 0, 'acacia: oceanomics-filtered-reads:OG28/hifi/qc_stats/m64497e_230811_065205.hifi_reads.bc2018--bc2018.stats;OG28/hifi/qc_stats/m64497e_230811_065205.unbarcoded.hifi_reads.stats;OG28/hifi/qc_stats/m64497e_230812_160012.hifi_reads.bc2018--bc2018.stats;OG28/hifi/qc_stats/m64497e_230812_160012.unbarcoded.hifi_reads.stats'),
  ('OG28B_D5_SBL_PACB_230811_AD', 0, 'acacia: oceanomics-filtered-reads:OG28/hifi/qc_stats/m64497e_230814_010940.hifi_reads.bc2019--bc2019.stats;OG28/hifi/qc_stats/m64497e_230814_010940.unbarcoded.hifi_reads.stats;OG28/hifi/qc_stats/m64497e_230815_101907.hifi_reads.bc2019--bc2019.stats;OG28/hifi/qc_stats/m64497e_230815_101907.unbarcoded.hifi_reads.stats'),
  ('OG28B_D6_SBL_PACB_230811_AD', 0, 'acacia: oceanomics-filtered-reads:OG28/hifi/qc_stats/m64497e_230816_192825.hifi_reads.bc2020--bc2020.stats;OG28/hifi/qc_stats/m64497e_230816_192825.unbarcoded.hifi_reads.stats;OG28/hifi/qc_stats/m64497e_230818_043800.hifi_reads.bc2020--bc2020.stats;OG28/hifi/qc_stats/m64497e_230818_043800.unbarcoded.hifi_reads.stats'),
  ('OG28B_D7_SBL_PACB_230811_AD', 0, 'acacia: oceanomics-filtered-reads:OG28/hifi/qc_stats/m64497e_230819_134819.hifi_reads.bc2021--bc2021.stats;OG28/hifi/qc_stats/m64497e_230819_134819.unbarcoded.hifi_reads.stats;OG28/hifi/qc_stats/m64497e_230820_230056.hifi_reads.bc2021--bc2021.stats;OG28/hifi/qc_stats/m64497e_230820_230056.unbarcoded.hifi_reads.stats'),
  ('OG2G_D_SBL_PACB_230413_AD', 0, 'acacia: oceanomics-filtered-reads:OG2/hifi/qc_stats/m64497e_230413_073127.hifi_reads.bc2004--bc2004.stats;OG2/hifi/qc_stats/m64497e_230413_073127.unbarcoded.hifi_reads.stats;OG2/hifi/qc_stats/m64497e_230414_164504.hifi_reads.bc2004--bc2004.stats;OG2/hifi/qc_stats/m64497e_230414_164504.unbarcoded.hifi_reads.stats'),
  ('OG35W_D_SBL_PACB_231027_ADLA', 0, 'acacia: oceanomics-filtered-reads:OG35/hifi/qc_stats/OG35_m64497e_231027_055916.hifi_reads.bc2034--bc2034.stats;OG35/hifi/qc_stats/OG35_m64497e_231027_055916.unbarcoded.hifi_reads.stats'),
  ('OG36W_D_SBL_PACB_230724_AD', 0, 'acacia: oceanomics-filtered-reads:OG36/hifi/qc_stats/m64497e_230724_040003.hifi_reads.bc2016--bc2016.stats;OG36/hifi/qc_stats/m64497e_230724_040003.unbarcoded.hifi_reads.stats;OG36/hifi/qc_stats/m64497e_230725_130633.hifi_reads.bc2016--bc2016.stats;OG36/hifi/qc_stats/m64497e_230725_130633.unbarcoded.hifi_reads.stats'),
  ('OG37G_D_SBL_PACB_240116_LAAD', 0, 'acacia: oceanomics-filtered-reads:OG37/hifi/qc_stats/OG37_m84154_240116_111524_s3.hifi_reads.bc2047.stats'),
  ('OG38G_D_SBL_PACB_230609_AD', 0, 'acacia: oceanomics-filtered-reads:OG38/hifi/qc_stats/m64497e_230612_002959.hifi_reads.bc2013--bc2013.stats;OG38/hifi/qc_stats/m64497e_230612_002959.unbarcoded.hifi_reads.stats;OG38/hifi/qc_stats/m64497e_230613_112714.hifi_reads.bc2013--bc2013.stats;OG38/hifi/qc_stats/m64497e_230613_112714.unbarcoded.hifi_reads.stats'),
  ('OG39H_D_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG39/hifi/OG39_m84154_241018_072321_s3.hifi_reads.bc2081.stats'),
  ('OG3G_D_SBL_PACB_230825_AD', 1, 'acacia: oceanomics-filtered-reads:OG3/hifi/qc_stats/OG3_m64497e_230825_054920.hifi_reads.bc2022--bc2022.stats;OG3/hifi/qc_stats/OG3_m64497e_230825_054920.unbarcoded.hifi_reads.stats;OG3/hifi/qc_stats/OG3_m64497e_230826_145707.hifi_reads.bc2022--bc2022.stats;OG3/hifi/qc_stats/OG3_m64497e_230826_145707.unbarcoded.hifi_reads.stats'),
  ('OG40H_D2_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG40/hifi/OG40_m84154_241005_164630_s1.hifi_reads.bc2074.stats'),
  ('OG42G_D_SBL2_PACB_240215_AD', 0, 'acacia: oceanomics-filtered-reads:OG42/hifi/qc_stats/m84154_240215_063713_s1.hifi_reads.bc2040.stats;OG42/hifi/qc_stats/m84154_240215_063713_s1.hifi_reads.unassigned.stats'),
  ('OG46G_D_SBL_PACB_240215_AD', 0, 'acacia: oceanomics-filtered-reads:OG46/hifi/qc_stats/m84154_240215_083635_s2.hifi_reads.bc2055.stats;OG46/hifi/qc_stats/m84154_240215_083635_s2.hifi_reads.unassigned.stats'),
  ('OG47G_D_SBL_PACB_231115_LA', 0, 'acacia: oceanomics-filtered-reads:OG47/hifi/qc_stats/OG47_m64497e_231129_075512.hifi_reads.bc2036--bc2036.stats;OG47/hifi/qc_stats/OG47_m64497e_231129_075512.unbarcoded.hifi_reads.stats;OG47/hifi/qc_stats/OG47_m64497e_231202_024948.hifi_reads.bc2036--bc2036.stats;OG47/hifi/qc_stats/OG47_m64497e_231202_024948.unbarcoded.hifi_reads.stats'),
  ('OG52G_D_SBL_PACB_230825_AD', 0, 'acacia: oceanomics-filtered-reads:OG52/hifi/qc_stats/OG52_m64497e_230830_185351.hifi_reads.bc2024--bc2024.stats;OG52/hifi/qc_stats/OG52_m64497e_230830_185351.unbarcoded.hifi_reads.stats;OG52/hifi/qc_stats/OG52_m64497e_230901_041018.hifi_reads.bc2024--bc2024.stats;OG52/hifi/qc_stats/OG52_m64497e_230901_041018.unbarcoded.hifi_reads.stats'),
  ('OG53G_D2_SBL2_PACB_230915_LP', 0, 'acacia: oceanomics-filtered-reads:OG53/hifi/qc_stats/OG53_m64497e_230918_013528.hifi_reads.bc2028--bc2028.stats;OG53/hifi/qc_stats/OG53_m64497e_230918_013528.unbarcoded.hifi_reads.stats'),
  ('OG53G_D2_SBL_PACB_230915_LP', 0, 'acacia: oceanomics-filtered-reads:OG53/hifi/qc_stats/OG53_m64497e_230919_104447.hifi_reads.bc2027--bc2027.stats;OG53/hifi/qc_stats/OG53_m64497e_230919_104447.unbarcoded.hifi_reads.stats'),
  ('OG54G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG54/hifi/OG54_m84154_241005_224423_s4.hifi_reads.bc2080.stats'),
  ('OG55G_D_SBL_PACB_231115_LA', 0, 'acacia: oceanomics-filtered-reads:OG55/hifi/qc_stats/OG55_m64497e_231130_171106.hifi_reads.bc2037--bc2037.stats;OG55/hifi/qc_stats/OG55_m64497e_231130_171106.unbarcoded.hifi_reads.stats;OG55/hifi/qc_stats/OG55_m64497e_231203_120153.hifi_reads.bc2037--bc2037.stats;OG55/hifi/qc_stats/OG55_m64497e_231203_120153.unbarcoded.hifi_reads.stats'),
  ('OG56G_D_SBL_PACB_240116_LAAD', 0, 'acacia: oceanomics-filtered-reads:OG56/hifi/qc_stats/OG56_m84154_240116_111524_s3.hifi_reads.bc2046.stats'),
  ('OG57G_D_SBL_PACB_231027_ADLA', 1, 'acacia: oceanomics-filtered-reads:OG57/hifi/qc_stats/OG57_m64497e_231104_125241.hifi_reads.bc2029--bc2029.stats;OG57/hifi/qc_stats/OG57_m64497e_231104_125241.unbarcoded.hifi_reads.stats;OG57/hifi/qc_stats/m64497e_231105_222750.hifi_reads.bc2029--bc2029.stats;OG57/hifi/qc_stats/m64497e_231105_222750.unbarcoded.hifi_reads.stats'),
  ('OG58W_D2_SBL_PACB_250704_AD', 0, 'acacia: oceanomics-filtered-reads:OG58/hifi/OG58_m84154_250704_053846_s1.hifi_reads.bc2002.stats'),
  ('OG5G_D2_SBL_PACB_240116_LAAD', 0, 'acacia: oceanomics-filtered-reads:OG5/hifi/qc_stats/OG5_m84154_240116_071633_s1.hifi_reads.bc2038.stats;OG5/hifi/qc_stats/OG5_m84154_240116_071633_s1.hifi_reads.unassigned.stats'),
  ('OG5G_D_SBL2_PACB_230628_AD', 1, 'acacia: oceanomics-filtered-reads:OG5/hifi/qc_stats/m64497e_230628_072209.hifi_reads.bc2014--bc2014.stats;OG5/hifi/qc_stats/m64497e_230628_072209.unbarcoded.hifi_reads.stats;OG5/hifi/qc_stats/m64497e_230629_162514.hifi_reads.bc2014--bc2014.stats;OG5/hifi/qc_stats/m64497e_230629_162514.unbarcoded.hifi_reads.stats'),
  ('OG5G_D_SBL_PACB_230609_AD', 0, 'acacia: oceanomics-filtered-reads:OG5/hifi/qc_stats/m64497e_230609_041535.hifi_reads.bc2011--bc2011.stats;OG5/hifi/qc_stats/m64497e_230609_041535.unbarcoded.hifi_reads.stats;OG5/hifi/qc_stats/m64497e_230610_151031.hifi_reads.bc2011--bc2011.stats;OG5/hifi/qc_stats/m64497e_230610_151031.unbarcoded.hifi_reads.stats'),
  ('OG60M_D_SBL_PACB_241127_AD', 0, 'acacia: oceanomics-filtered-reads:OG60/hifi/OG60_OG60_m84154_241127_074314_s1.hifi_reads.bc2027.stats;OG60/hifi/OG60_m84154_241127_074314_s1.hifi_reads.unassigned.stats'),
  ('OG61W_D_SBL_PACB_250317_AD', 0, 'single_run: ref_hifi_adapter_filter: read set 4 (OG61 250317), its only run'),
  ('OG62G_D_SBL2_PACB_250307_AD', 0, 'acacia: oceanomics-filtered-reads:OG62/hifi/OG62G_D_m84154_250307_141311_s4.hifi_reads.bc2010.stats'),
  ('OG62G_D_SBL_PACB_250317_AD', 0, 'acacia: oceanomics-filtered-reads:OG62/hifi/OG62_m84154_250317_102301_s1.hifi_reads.bc2002.stats'),
  ('OG637B_D3_SBL2_PACB_240206_AD', 0, 'acacia: oceanomics-filtered-reads:OG637/hifi/qc_stats/m84154_240206_105116_s3.hifi_reads.bc2053.stats;OG637/hifi/qc_stats/m84154_240206_105116_s3.hifi_reads.unassigned.stats'),
  ('OG637B_D3_SBL_PACB_240206_AD', 0, 'acacia: oceanomics-filtered-reads:OG637/hifi/qc_stats/m84154_240206_065238_s1.hifi_reads.bc2052.stats;OG637/hifi/qc_stats/m84154_240206_065238_s1.hifi_reads.unassigned.stats;OG637/hifi/qc_stats/m84154_240206_085202_s2.hifi_reads.bc2052.stats;OG637/hifi/qc_stats/m84154_240206_085202_s2.hifi_reads.unassigned.stats'),
  ('OG645H_D_SBL_PACB_240427_LA', 0, 'acacia: oceanomics-filtered-reads:OG645/hifi/qc_stats/OG645_m84154_240417_123653_s3.hifi_reads.bc2071.stats;OG645/hifi/qc_stats/OG645_m84154_240417_123653_s3.hifi_reads.unassigned.stats'),
  ('OG646G_D_SBL_PACB_240821_AD', 0, 'acacia: oceanomics-filtered-reads:OG646/hifi/qc_stats/OG646_m84154_240821_064447_s2.hifi_reads.bc2085.stats'),
  ('OG647H_D_SBL_PACB_240501_AD', 0, 'acacia: oceanomics-filtered-reads:OG647/hifi/qc_stats/OG647_m84154_240501_045633_s1.hifi_reads.bc2086.stats;OG647/hifi/qc_stats/OG647_m84154_240501_045633_s1.hifi_reads.unassigned.stats'),
  ('OG648G_D2_SBL_PACB_250704_AD', 0, 'acacia: oceanomics-filtered-reads:OG648/hifi/OG648_m84154_250704_074014_s2.hifi_reads.bc2005.stats'),
  ('OG649H_D2_SBL2_PACB_240427_LA', 0, 'acacia: oceanomics-filtered-reads:OG649/hifi/qc_stats/OG649_m84154_240417_143607_s4.hifi_reads.bc2082.stats;OG649/hifi/qc_stats/OG649_m84154_240417_143607_s4.hifi_reads.unassigned.stats'),
  ('OG64W_D_SBL_PACB_250307_AD', 0, 'acacia: oceanomics-filtered-reads:OG64/hifi/OG64W_m84154_250307_121350_s3.hifi_reads.bc2082.stats'),
  ('OG650H_D_SBL_PACB_240327_LA', 0, 'acacia: oceanomics-filtered-reads:OG650/hifi/qc_stats/OG650_m84154_240327_080554_s1.hifi_reads.bc2056.stats;OG650/hifi/qc_stats/OG650_m84154_240327_080554_s1.hifi_reads.unassigned.stats'),
  ('OG651H_D_SBL_PACB_240327_LA', 0, 'acacia: oceanomics-filtered-reads:OG651/hifi/qc_stats/OG651_m84154_240327_140354_s4.hifi_reads.bc2065.stats;OG651/hifi/qc_stats/OG651_m84154_240327_140354_s4.hifi_reads.unassigned.stats'),
  ('OG652H_D_SBL_PACB_240327_LA', 0, 'acacia: oceanomics-filtered-reads:OG652/hifi/qc_stats/OG652_m84154_240328_115748_s1.hifi_reads.bc2066.stats;OG652/hifi/qc_stats/OG652_m84154_240328_115748_s1.hifi_reads.unassigned.stats'),
  ('OG654H_D_SBL_PACB_240327_LA', 0, 'acacia: oceanomics-filtered-reads:OG654/hifi/qc_stats/OG654_m84154_240327_100514_s2.hifi_reads.bc2057.stats;OG654/hifi/qc_stats/OG654_m84154_240327_100514_s2.hifi_reads.unassigned.stats'),
  ('OG657H_D_SBL_PACB_240501_AD', 0, 'acacia: oceanomics-filtered-reads:OG657/hifi/qc_stats/OG657_m84154_240501_065558_s2.hifi_reads.bc2087.stats;OG657/hifi/qc_stats/OG657_m84154_240501_065558_s2.hifi_reads.unassigned.stats'),
  ('OG658H_D_SBL_PACB_240327_LA', 0, 'acacia: oceanomics-filtered-reads:OG658/hifi/qc_stats/OG658_m84154_240328_155632_s3.hifi_reads.bc2067.stats;OG658/hifi/qc_stats/OG658_m84154_240328_155632_s3.hifi_reads.unassigned.stats'),
  ('OG659H_D_SBL2_PACB_240427_LA', 0, 'acacia: oceanomics-filtered-reads:OG659/hifi/qc_stats/OG659_m84154_240418_142925_s2.hifi_reads.bc2084.stats;OG659/hifi/qc_stats/OG659_m84154_240418_142925_s2.hifi_reads.unassigned.stats'),
  ('OG65W_D_SBL_PACB_250704_AD', 0, 'acacia: oceanomics-filtered-reads:OG65/hifi/OG65_m84154_250704_114431_s4.hifi_reads.bc2003.stats'),
  ('OG660H_D2_SBL2_PACB_240228_AD', 0, 'acacia: oceanomics-filtered-reads:OG660/hifi/qc_stats/m84154_240228_085647_s1.hifi_reads.bc2064.stats'),
  ('OG660H_D2_SBL_PACB_240228_AD', 0, 'acacia: oceanomics-filtered-reads:OG660/hifi/qc_stats/m84154_240228_085647_s1.hifi_reads.bc2063.stats'),
  ('OG662G_D_SBL_PACB_240327_LA', 0, 'acacia: oceanomics-filtered-reads:OG662/hifi/qc_stats/OG662_m84154_240328_235550_s4.hifi_reads.bc2068.stats;OG662/hifi/qc_stats/OG662_m84154_240328_235550_s4.hifi_reads.unassigned.stats'),
  ('OG664H_D_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG664/hifi/OG664_m84154_241018_092240_s1.hifi_reads.bc2091.stats'),
  ('OG665H_D_SBL_PACB_240501_AD', 0, 'acacia: oceanomics-filtered-reads:OG665/hifi/qc_stats/OG665_m84154_240501_085523_s3.hifi_reads.bc2069.stats;OG665/hifi/qc_stats/OG665_m84154_240501_085523_s3.hifi_reads.unassigned.stats'),
  ('OG666H_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG666/hifi/OG666_m84154_241004_125220_s4.hifi_reads.bc2071.stats'),
  ('OG672H_D2_SBL_PACB_240215_AD', 0, 'acacia: oceanomics-filtered-reads:OG672/hifi/qc_stats/m84154_240215_123526_s4.hifi_reads.bc2048.stats;OG672/hifi/qc_stats/m84154_240215_123526_s4.hifi_reads.unassigned.stats'),
  ('OG673H_D_SBL2_PACB_240427_LA', 0, 'acacia: oceanomics-filtered-reads:OG673/hifi/OG673_m84154_240418_162849_s3.hifi_reads.bc2081.stats;OG673/hifi/qc_stats/OG673_m84154_240418_162849_s3.hifi_reads.unassigned.stats'),
  ('OG675G_D2_SBL2_PACB_250828_AD', 0, 'acacia: oceanomics-filtered-reads:OG675/hifi/OG675_m84154_250828_101137_s3.hifi_reads.stats'),
  ('OG676H_D_SBL_PACB_240327_LA', 0, 'acacia: oceanomics-filtered-reads:OG676/hifi/qc_stats/OG676_m84154_240327_120429_s3.hifi_reads.bc2059.stats;OG676/hifi/qc_stats/OG676_m84154_240327_120429_s3.hifi_reads.unassigned.stats'),
  ('OG678H_D_SBL_PACB_240327_LA', 0, 'acacia: oceanomics-filtered-reads:OG678/hifi/qc_stats/OG678_m84154_240328_135706_s2.hifi_reads.bc2070.stats;OG678/hifi/qc_stats/OG678_m84154_240328_135706_s2.hifi_reads.unassigned.stats'),
  ('OG679H_D_SBL_PACB_250307_AD', 0, 'acacia: oceanomics-filtered-reads:OG679/hifi/OG679H_m84154_250307_101432_s2.hifi_reads.bc2085.stats'),
  ('OG67W_D_SBL_PACB_241127_AD', 0, 'acacia: oceanomics-filtered-reads:OG67/hifi/OG67_OG67_m84154_241127_114221_s4.hifi_reads.bc2028.stats;OG67/hifi/OG67_m84154_241127_114221_s4.hifi_reads.unassigned.stats'),
  ('OG680G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG680/hifi/OG680_m84154_241004_065438_s1.hifi_reads.bc2065.stats'),
  ('OG681H_D_SBL_PACB_250307_AD', 0, 'acacia: oceanomics-filtered-reads:OG681/hifi/OG681H_m84154_250307_101432_s2.hifi_reads.bc2086.stats'),
  ('OG683H_D_SBL2_PACB_240821_AD', 0, 'acacia: oceanomics-filtered-reads:OG683/hifi/qc_stats/OG683_m84154_240821_064447_s2.hifi_reads.bc2088.stats'),
  ('OG683H_D_SBL2_PACB_241023_AD', 0, 'acacia: oceanomics-filtered-reads:OG683/hifi/OG683_m84154_241025_000410_s4.hifi_reads.bc2088.stats'),
  ('OG686H_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG686/hifi/OG686_m84154_241005_144457_s3.hifi_reads.bc2077.stats'),
  ('OG695H_D_SBL3_PACB_240520_LA', 0, 'acacia: oceanomics-filtered-reads:OG695/hifi/qc_stats/OG695_m84154_240520_074142_s2.hifi_reads.bc2093.stats;OG695/hifi/qc_stats/OG695_m84154_240520_074142_s2.hifi_reads.unassigned.stats'),
  ('OG696H_D_SBL_PACB_240228_AD', 0, 'acacia: oceanomics-filtered-reads:OG696/hifi/qc_stats/OG696_m84154_240228_105612_s2.hifi_reads.bc2060.stats;OG696/hifi/qc_stats/OG696_m84154_240228_105612_s2.hifi_reads.unassigned.stats'),
  ('OG698H_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG698/hifi/OG698_m84154_241005_144457_s3.hifi_reads.bc2072.stats'),
  ('OG699H_D_SBL_PACB_250317_AD', 0, 'acacia: oceanomics-filtered-reads:OG699/hifi/OG699_m84154_250318_141450_s1.hifi_reads.bc2087.stats'),
  ('OG6G_D_SBL2_PACB_230628_AD', 0, 'acacia: oceanomics-filtered-reads:OG6/hifi/qc_stats/m64497e_230701_013313.hifi_reads.bc2015--bc2015.stats;OG6/hifi/qc_stats/m64497e_230701_013313.unbarcoded.hifi_reads.stats;OG6/hifi/qc_stats/m64497e_230702_104117.hifi_reads.bc2015--bc2015.stats;OG6/hifi/qc_stats/m64497e_230702_104117.unbarcoded.hifi_reads.stats'),
  ('OG701H_D_SBL2_PACB_240427_LA', 0, 'acacia: oceanomics-filtered-reads:OG701/hifi/qc_stats/OG701_m84154_240418_182815_s4.hifi_reads.bc2083.stats;OG701/hifi/qc_stats/OG701_m84154_240418_182815_s4.hifi_reads.unassigned.stats'),
  ('OG702G_D_SBL_PACB_240501_AD', 0, 'acacia: oceanomics-filtered-reads:OG702/hifi/qc_stats/OG702_m84154_240501_105447_s4.hifi_reads.bc2075.stats;OG702/hifi/qc_stats/OG702_m84154_240501_105447_s4.hifi_reads.unassigned.stats'),
  ('OG704H_D_SBL2_PACB_240417_LA', 0, 'acacia: oceanomics-filtered-reads:OG704/hifi/qc_stats/OG704_m84154_240418_202742_s1.hifi_reads.bc2080.stats;OG704/hifi/qc_stats/OG704_m84154_240418_202742_s1.hifi_reads.unassigned.stats'),
  ('OG706H_D5_SBL_PACB_240228_AD', 0, 'acacia: oceanomics-filtered-reads:OG706/hifi/qc_stats/OG706_m84154_240228_125536_s3.hifi_reads.bc2062.stats;OG706/hifi/qc_stats/OG706_m84154_240228_125536_s3.hifi_reads.unassigned.stats;OG706/hifi/qc_stats/OG706_m84154_240228_145455_s4.hifi_reads.bc2062.stats;OG706/hifi/qc_stats/OG706_m84154_240228_145455_s4.hifi_reads.unassigned.stats'),
  ('OG706H_D_SBL2_PACB_240206_AD', 0, 'acacia: oceanomics-filtered-reads:OG706/hifi/qc_stats/OG706_m84154_240207_104437_s1.hifi_reads.bc2051.stats;OG706/hifi/qc_stats/OG706_m84154_240207_104437_s1.hifi_reads.unassigned.stats;OG706/hifi/qc_stats/OG706_m84154_240207_124405_s2.hifi_reads.bc2051.stats;OG706/hifi/qc_stats/OG706_m84154_240207_124405_s2.hifi_reads.unassigned.stats'),
  ('OG706H_D_SBL_PACB_240206_AD', 0, 'acacia: oceanomics-filtered-reads:OG706/hifi/qc_stats/OG706_m84154_240206_125036_s4.hifi_reads.bc2050.stats;OG706/hifi/qc_stats/OG706_m84154_240206_125036_s4.hifi_reads.unassigned.stats'),
  ('OG709G_D_SBL_PACB_240501_AD', 0, 'acacia: oceanomics-filtered-reads:OG709/hifi/qc_stats/OG709_m84154_240502_104757_s2.hifi_reads.bc2089.stats;OG709/hifi/qc_stats/OG709_m84154_240502_104757_s2.hifi_reads.unassigned.stats'),
  ('OG70W_D_SBL_PACB_250307_AD', 0, 'acacia: oceanomics-filtered-reads:OG70/hifi/OG70_m84154_250307_081514_s1.hifi_reads.bc2083.stats'),
  ('OG711O_D2_SBL_PACB_240501_AD', 0, 'acacia: oceanomics-filtered-reads:OG711/hifi/qc_stats/OG711_m84154_240502_124721_s3.hifi_reads.bc2090.stats;OG711/hifi/qc_stats/OG711_m84154_240502_124721_s3.hifi_reads.unassigned.stats'),
  ('OG711O_D3_SBL_PACB_260603_AMD', 0, 'acacia: oceanomics-filtered-reads:OG711/hifi/OG711_m84154_260604_185305_s4.hifi_reads.bc2008.stats'),
  ('OG716O_D_SBL2_PACB_260730_AMD', 0, 'acacia: oceanomics-filtered-reads:OG716/hifi/OG716_m84154_260730_084622_s2.hifi_reads.bc2091.stats;OG716/hifi/OG716_m84154_260730_084622_s2.hifi_reads.unassigned.stats'),
  ('OG716O_D_SBL_PACB_250704_AD', 0, 'acacia: oceanomics-filtered-reads:OG716/hifi/OG716_m84154_250704_114431_s4.hifi_reads.bc2007.stats'),
  ('OG716O_D_SBL_PACB_250717_AD', 0, 'acacia: oceanomics-filtered-reads:OG716/hifi/OG716_m84154_250717_081617_s1.hifi_reads.bc2007.stats'),
  ('OG721G_D2_SBL_PACB_240501_AD', 0, 'acacia: oceanomics-filtered-reads:OG721/hifi/qc_stats/OG721_m84154_240502_144647_s4.hifi_reads.bc2091.stats;OG721/hifi/qc_stats/OG721_m84154_240502_144647_s4.hifi_reads.unassigned.stats'),
  ('OG72H_D_SBL_PACB_241023_AD', 0, 'acacia: oceanomics-filtered-reads:OG72/hifi/OG72_OG72_m84154_241025_000410_s4.hifi_reads.bc2001.stats'),
  ('OG73W_D_SBL_PACB_250307_AD', 0, 'single_run: ref_hifi_adapter_filter: read set 44 (OG73 250307), its only run'),
  ('OG748H_D_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG748/hifi/OG748_m84154_241018_092240_s1.hifi_reads.bc2083.stats'),
  ('OG749H_D_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG749/hifi/OG749_m84154_241018_112158_s2.hifi_reads.bc2084.stats'),
  ('OG749H_D_SBL_PACB_250331_LA', 0, 'acacia: oceanomics-filtered-reads:OG749/hifi/OG794_m84154_250318_201423_s4.hifi_reads.bc2091.stats'),
  ('OG750G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG750/hifi/OG750_m84154_241005_164630_s1.hifi_reads.bc2073.stats'),
  ('OG751G_D_SBL_PACB_250317_AD', 0, 'acacia: oceanomics-filtered-reads:OG751/hifi/OG751_m84154_250318_161447_s2.hifi_reads.bc2088.stats'),
  ('OG755H_D_SBL_PACB_240821_AD', 0, 'acacia: oceanomics-filtered-reads:OG755/hifi/OG755_m84154_240821_084417_s3.hifi_reads.bc2048--bc2048.stats;OG755/hifi/qc_stats/OG755_m84154_240821_084417_s3.hifi_reads.bc2048.stats'),
  ('OG756G_D_SBL_PACB_250704_AD', 0, 'acacia: oceanomics-filtered-reads:OG756/hifi/OG756_m84154_250704_094223_s3.hifi_reads.bc2008.stats'),
  ('OG757G_D_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG757/hifi/OG757_m84154_241018_132112_s4.hifi_reads.bc2085.stats'),
  ('OG758M_D_SBL_PACB_241127_AD', 0, 'acacia: oceanomics-filtered-reads:OG758/hifi/OG758_OG758_m84154_241127_094241_s2.hifi_reads.bc2005.stats;OG758/hifi/OG758_m84154_241127_094241_s2.hifi_reads.unassigned.stats'),
  ('OG759H_D_SBL_PACB_240520_LA', 0, 'acacia: oceanomics-filtered-reads:OG759/hifi/qc_stats/OG759_m84154_240520_094106_s3.hifi_reads.bc2003.stats;OG759/hifi/qc_stats/OG759_m84154_240520_094106_s3.hifi_reads.unassigned.stats'),
  ('OG760H_D2_SBL_PACB_240520_LA', 0, 'acacia: oceanomics-filtered-reads:OG760/hifi/qc_stats/OG760_m84154_240520_114025_s4.hifi_reads.bc2005.stats;OG760/hifi/qc_stats/OG760_m84154_240520_114025_s4.hifi_reads.unassigned.stats'),
  ('OG762H_D_SBL2_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG762/hifi/OG762_m84154_241018_112158_s2.hifi_reads.bc2092.stats;OG762/hifi/OG762_m84154_241019_191434_s1.hifi_reads.bc2092.stats'),
  ('OG765W_D_SBL_PACB_240821_AD', 0, 'acacia: oceanomics-filtered-reads:OG765/hifi/qc_stats/OG765_m84154_240821_104345_s4.hifi_reads.bc2049.stats'),
  ('OG766G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG766/hifi/OG766_m84154_241004_085350_s2.hifi_reads.bc2066.stats'),
  ('OG767G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG767/hifi/OG767_m84154_241004_085350_s2.hifi_reads.bc2067.stats'),
  ('OG769G_D_SBL_PACB_250828_AD', 0, 'acacia: oceanomics-filtered-reads:OG769/hifi/OG769_m84154_250828_121453_s4.hifi_reads.stats'),
  ('OG76G_D_SBL_PACB_230825_AD', 0, 'acacia: oceanomics-filtered-reads:OG76/hifi/qc_stats/OG76_m64497e_230902_133514.hifi_reads.bc2025--bc2025.stats;OG76/hifi/qc_stats/OG76_m64497e_230902_133514.unbarcoded.hifi_reads.stats;OG76/hifi/qc_stats/OG76_m64497e_230903_225708.hifi_reads.stats'),
  ('OG770M_D_SBL_PACB_241127_AD', 0, 'acacia: oceanomics-filtered-reads:OG770/hifi/OG770_OG770_m84154_241127_114221_s4.hifi_reads.bc2006.stats'),
  ('OG775G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG775/hifi/OG775_m84154_241005_224423_s4.hifi_reads.bc2076.stats'),
  ('OG777G_D_SBL_PACB_240520_LA', 0, 'acacia: oceanomics-filtered-reads:OG777/hifi/qc_stats/OG777_m84154_240520_133947_s1.hifi_reads.bc2007.stats;OG777/hifi/qc_stats/OG777_m84154_240520_133947_s1.hifi_reads.unassigned.stats'),
  ('OG778H_D_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG778/hifi/OG778_m84154_241019_171510_s3.hifi_reads.bc2086.stats'),
  ('OG781G_D_SBL3_PACB_260421_AMD', 0, 'acacia: oceanomics-filtered-reads:OG781/hifi/OG781_m84154_260422_172523_s4.hifi_reads.bc2089.stats;OG781/hifi/OG781_m84154_260422_172523_s4.hifi_reads.unassigned.stats'),
  ('OG781G_D_SBL_PACB_250317_AD', 0, 'acacia: oceanomics-filtered-reads:OG781/hifi/OG781_m84154_250318_181437_s3.hifi_reads.bc2089.stats;OG781/hifi/OG781_m84154_250318_181437_s3.hifi_reads.unassigned.stats'),
  ('OG784G_D_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG784/hifi/OG784_m84154_241019_191434_s1.hifi_reads.bc2050.stats'),
  ('OG785G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG785/hifi/OG785_m84154_241004_105305_s3.hifi_reads.bc2068.stats'),
  ('OG787G_D_SBL_PACB_240927_LA', 0, 'acacia: oceanomics-filtered-reads:OG787/hifi/OG787_m84154_240927_085954_s1.hifi_reads.bc2060.stats'),
  ('OG788G_D_SBL_PACB_240927_LA', 0, 'acacia: oceanomics-filtered-reads:OG788/hifi/OG788_m84154_240927_105921_s2.hifi_reads.bc2061.stats'),
  ('OG78W_D2_SBL_PACB_260626_AMDTW', 0, 'acacia: oceanomics-filtered-reads:OG78/hifi/OG78_m84154_260626_140812_s4.hifi_reads.bc2092.stats;OG78/hifi/OG78_m84154_260626_140812_s4.hifi_reads.unassigned.stats'),
  ('OG790G_D_SBL_PACB_250704_AD', 0, 'acacia: oceanomics-filtered-reads:OG790/hifi/OG790_m84154_250704_053846_s1.hifi_reads.bc2009.stats'),
  ('OG793G_D_SBL_PACB_250317_AD', 0, 'acacia: oceanomics-filtered-reads:OG793/hifi/OG793_m84154_250318_161447_s2.hifi_reads.bc2090.stats'),
  ('OG794G_D_SBL_PACB_250307_AD', 0, 'acacia: oceanomics-filtered-reads:OG794/hifi/OG794G_m84154_250307_121350_s3.hifi_reads.bc2091.stats'),
  ('OG799H_D2_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG799/hifi/OG799_m84154_241019_171510_s3.hifi_reads.bc2089.stats'),
  ('OG79G_D_SBL_PACB_240427_LA', 0, 'acacia: oceanomics-filtered-reads:OG79/hifi/qc_stats/OG79_m84154_240417_103732_s2.hifi_reads.bc2074.stats;OG79/hifi/qc_stats/OG79_m84154_240417_103732_s2.hifi_reads.unassigned.stats'),
  ('OG7G_D2_SBL_PACB_230915_LP', 0, 'acacia: oceanomics-filtered-reads:OG7/hifi/qc_stats/OG7_m64497e_230915_072411.hifi_reads.bc2026--bc2026.stats;OG7/hifi/qc_stats/OG7_m64497e_230915_072411.unbarcoded.hifi_reads.stats;OG7/hifi/qc_stats/OG7_m64497e_230916_162914.hifi_reads.bc2026--bc2026.stats;OG7/hifi/qc_stats/OG7_m64497e_230916_162914.unbarcoded.hifi_reads.stats'),
  ('OG800H_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG800/hifi/OG800_m84154_241005_184550_s2.hifi_reads.bc2075.stats'),
  ('OG801L_D_SBL_PACB_250828_AD', 0, 'acacia: oceanomics-filtered-reads:OG801/hifi/OG801_m84154_250828_060513_s1.hifi_reads.bc2016.stats'),
  ('OG803G_D_SBL_PACB_240927_LA', 0, 'acacia: oceanomics-filtered-reads:OG803/hifi/OG803_m84154_240927_105921_s2.hifi_reads.bc2063.stats'),
  ('OG804G_D_SBL2_PACB_260522_AMD', 0, 'acacia: oceanomics-filtered-reads:OG804/hifi/OG804_m84154_260522_095124_s2.hifi_reads.bc2002.stats'),
  ('OG804G_D_SBL_PACB_250717_AD', 0, 'acacia: oceanomics-filtered-reads:OG804/hifi/OG804_m84154_250717_121941_s3.hifi_reads.bc2010.stats'),
  ('OG804G_D_SBL_PACB_260227_AMD', 0, 'acacia: oceanomics-filtered-reads:OG804/hifi/OG804_m84154_260227_073225_s1.hifi_reads.bc2010.stats'),
  ('OG808H_D_SBL_PACB_240520_LA', 0, 'acacia: oceanomics-filtered-reads:OG808/hifi/qc_stats/OG808_m84154_240521_173345_s2.hifi_reads.bc2095.stats;OG808/hifi/qc_stats/OG808_m84154_240521_173345_s2.hifi_reads.unassigned.stats'),
  ('OG810G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG810/hifi/OG810_m84154_241004_105305_s3.hifi_reads.bc2069.stats'),
  ('OG811G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG811/hifi/OG811_m84154_241004_065438_s1.hifi_reads.bc2070.stats'),
  ('OG813G_D_SBL_PACB_250704_AD', 0, 'acacia: oceanomics-filtered-reads:OG813/hifi/OG813_m84154_250704_074014_s2.hifi_reads.bc2011.stats'),
  ('OG819H_D_SBL_PACB_250717_AD', 0, 'acacia: oceanomics-filtered-reads:OG819/hifi/OG819_m84154_250717_142145_s4.hifi_reads.bc2012.stats'),
  ('OG81W_D_SBL_PACB_250704_AD', 0, 'acacia: oceanomics-filtered-reads:OG81/hifi/OG81_m84154_250704_094223_s3.hifi_reads.bc2004.stats'),
  ('OG820G_D_SBL_PACB_240501_AD', 0, 'acacia: oceanomics-filtered-reads:OG820/hifi/OG820_m84154_240502_164600_s1.hifi_reads.bc2092.stats;OG820/hifi/qc_stats/OG820_m84154_240502_164600_s1.hifi_reads.unassigned.stats'),
  ('OG824H_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG824/hifi/OG824_m84154_241005_184550_s2.hifi_reads.bc2078.stats'),
  ('OG829H_D2_SBL_PACB_240927_LA', 0, 'acacia: oceanomics-filtered-reads:OG829/hifi/OG829_m84154_240927_125837_s3.hifi_reads.bc2028.stats'),
  ('OG834H_D2_SBL_PACB_240927_LA', 0, 'acacia: oceanomics-filtered-reads:OG834/hifi/OG834_m84154_240927_145748_s4.hifi_reads.bc2029.stats'),
  ('OG836B_D_SBL_PACB_240520_LA', 0, 'acacia: oceanomics-filtered-reads:OG836/hifi/qc_stats/OG836_m84154_240521_193304_s3.hifi_reads.bc2001.stats;OG836/hifi/qc_stats/OG836_m84154_240521_193304_s3.hifi_reads.unassigned.stats;OG836/hifi/qc_stats/OG836_m84154_240521_213218_s4.hifi_reads.bc2001.stats;OG836/hifi/qc_stats/OG836_m84154_240521_213218_s4.hifi_reads.unassigned.stats'),
  ('OG837B_D3_SBL_PACB_240813_AD', 0, 'acacia: oceanomics-filtered-reads:OG837/hifi/qc_stats/OG837_m84154_240813_061757_s1.hifi_reads.bc2051.stats;OG837/hifi/qc_stats/OG837_m84154_240813_061757_s1.hifi_reads.unassigned.stats;OG837/hifi/qc_stats/OG837_m84154_240813_081715_s2.hifi_reads.bc2051.stats;OG837/hifi/qc_stats/OG837_m84154_240813_081715_s2.hifi_reads.unassigned.stats'),
  ('OG838B2_D_SBL_PACB_240813_AD', 0, 'acacia: oceanomics-filtered-reads:OG838/hifi/qc_stats/OG838_m84154_240813_101636_s3.hifi_reads.bc2053.stats;OG838/hifi/qc_stats/OG838_m84154_240813_101636_s3.hifi_reads.unassigned.stats;OG838/hifi/qc_stats/OG838_m84154_240813_121558_s4.hifi_reads.bc2053.stats;OG838/hifi/qc_stats/OG838_m84154_240813_121558_s4.hifi_reads.unassigned.stats'),
  ('OG838B_D_SBL_PACB_240520_LA', 0, 'acacia: oceanomics-filtered-reads:OG838/hifi/qc_stats/m84154_240521_233138_s1.hifi_reads.bc2004.stats;OG838/hifi/qc_stats/m84154_240521_233138_s1.hifi_reads.unassigned.stats'),
  ('OG844H_D4_SBL_PACB_241023_AD', 0, 'acacia: oceanomics-filtered-reads:OG844/hifi/OG844_m84154_241023_101241_s1.hifi_reads.bc2093.stats;OG844/hifi/OG844_m84154_241023_121159_s2.hifi_reads.bc2093.stats'),
  ('OG844H_D5_SBL_PACB_241023_AD', 0, 'acacia: oceanomics-filtered-reads:OG844/hifi/OG844_m84154_241024_180537_s3.hifi_reads.bc2094.stats'),
  ('OG844H_D5_SBL_PACB_260511_AMD', 0, 'acacia: oceanomics-filtered-reads:OG844/hifi/OG844_m84154_260511_070046_s1.hifi_reads.bc2094.stats;OG844/hifi/OG844_m84154_260511_070046_s1.hifi_reads.unassigned.stats'),
  ('OG845H_D2_SBL2_PACB_241023_AD', 0, 'zero_total: ref_hifi_adapter_filter: read set 215 (OG845 241023) total 0 over 3 runs'),
  ('OG845H_D2_SBL_PACB_241018_LA', 0, 'acacia: oceanomics-filtered-reads:OG845/hifi/OG845_m84154_241018_132112_s4.hifi_reads.bc2087.stats;OG845/hifi/OG845_m84154_241019_211402_s2.hifi_reads.bc2087.stats'),
  ('OG845H_D2_SBL_PACB_241023_AD', 0, 'zero_total: ref_hifi_adapter_filter: read set 215 (OG845 241023) total 0 over 3 runs'),
  ('OG847M_D2_SBL_PACB_260626_AMDTW', 0, 'acacia: oceanomics-filtered-reads:OG847/hifi/OG847_m84154_260627_155826_s3.hifi_reads.bc2093.stats;OG847/hifi/OG847_m84154_260627_155826_s3.hifi_reads.unassigned.stats'),
  ('OG848U_D_SBL2_PACB_241127_AD', 0, 'acacia: oceanomics-filtered-reads:OG848/hifi/OG848_OG848_m84154_241127_054344_s3.hifi_reads.bc2026.stats'),
  ('OG848U_D_SBL_PACB_250113_AD', 0, 'acacia: oceanomics-filtered-reads:OG848/hifi/OG848_OG848_m84154_250114_123120_s4.hifi_reads.bc2007.stats;OG848/hifi/OG848_OG848_m84154_250114_123120_s4.hifi_reads.unassigned.stats'),
  ('OG849U_D_SBL_PACB_241127_AD', 0, 'acacia: oceanomics-filtered-reads:OG849/hifi/OG849_OG849_m84154_241127_094241_s2.hifi_reads.bc2009.stats'),
  ('OG852O_D_SBL_PACB_250717_AD', 0, 'acacia: oceanomics-filtered-reads:OG852/hifi/OG852_m84154_250717_142145_s4.hifi_reads.bc2013.stats'),
  ('OG853O_D_SBL_PACB_250717_AD', 0, 'acacia: oceanomics-filtered-reads:OG853/hifi/OG853_m84154_250717_101735_s2.hifi_reads.bc2014.stats'),
  ('OG855H_D_SBL_PACB_240821_AD', 0, 'acacia: oceanomics-filtered-reads:OG855/hifi/qc_stats/OG855_m84154_240821_104345_s4.hifi_reads.bc2055.stats'),
  ('OG856H_D_SBL_PACB_240821_AD', 0, 'single_run: ref_hifi_adapter_filter: read set 126 (OG856 240821), its only run'),
  ('OG859B_D2_SBL_PACB_241023_AD', 0, 'acacia: oceanomics-filtered-reads:OG859/hifi/OG859_m84154_241023_081319_s3.hifi_reads.bc2096.stats'),
  ('OG859B_D_SBL_PACB_241023_AD', 0, 'acacia: oceanomics-filtered-reads:OG859/hifi/OG859_m84154_241023_141118_s4.hifi_reads.bc2095.stats'),
  ('OG85H_D_SBL_PACB_240927_LA', 0, 'acacia: oceanomics-filtered-reads:OG85/hifi/OG85_m84154_240927_085954_s1.hifi_reads.bc2057.stats'),
  ('OG860H_D_SBL_PACB_240927_LA', 0, 'acacia: oceanomics-filtered-reads:OG860/hifi/OG860_m84154_240927_125837_s3.hifi_reads.bc2064.stats'),
  ('OG863G_D_SBL_PACB_241004_LA', 0, 'acacia: oceanomics-filtered-reads:OG863/hifi/OG863_m84154_241004_125220_s4.hifi_reads.bc2079.stats'),
  ('OG865G_D_SBL2_PACB_250818_AD', 0, 'acacia: oceanomics-filtered-reads:OG865/hifi/OG865_amplify_m84154_250818_115906_s3.hifi_reads.stats'),
  ('OG866G_D_SBL_PACB_241023_AD', 0, 'acacia: oceanomics-filtered-reads:OG866/hifi/OG866_m84154_241024_220430_s2.hifi_reads.bc2056.stats'),
  ('OG868M_D_SBL_PACB_250317_AD', 0, 'acacia: oceanomics-filtered-reads:OG868/hifi/OG868_m84154_250318_201423_s4.hifi_reads.bc2094.stats'),
  ('OG869M_D_SBL3_PACB_250818_AD', 0, 'acacia: oceanomics-filtered-reads:OG869/hifi/OG869_amplify_m84154_250818_140110_s4.hifi_reads.stats'),
  ('OG88G_D_SBL_PACB_230724_AD', 0, 'acacia: oceanomics-filtered-reads:OG88/hifi/qc_stats/m64497e_230726_221540.hifi_reads.bc2017--bc2017.stats;OG88/hifi/qc_stats/m64497e_230726_221540.unbarcoded.hifi_reads.stats;OG88/hifi/qc_stats/m64497e_230728_091325.hifi_reads.bc2017--bc2017.stats;OG88/hifi/qc_stats/m64497e_230728_091325.unbarcoded.hifi_reads.stats'),
  ('OG8G_D_SBL_PACB_230512_AD', 0, 'acacia: oceanomics-filtered-reads:OG8/hifi/qc_stats/m64497e_230512_083815.hifi_reads.bc2006--bc2006.stats;OG8/hifi/qc_stats/m64497e_230512_083815.unbarcoded.hifi_reads.stats;OG8/hifi/qc_stats/m64497e_230513_174108.hifi_reads.bc2006--bc2006.stats;OG8/hifi/qc_stats/m64497e_230513_174108.unbarcoded.hifi_reads.stats'),
  ('OG907H_D_SBL_PACB_250828_AD', 0, 'acacia: oceanomics-filtered-reads:OG907/hifi/OG907_m84154_250828_060513_s1.hifi_reads.bc2017.stats'),
  ('OG90H_D2_SBL2_PACB_240821_AD', 0, 'acacia: oceanomics-filtered-reads:OG90/hifi/qc_stats/OG90_m84154_240821_044521_s1.hifi_reads.bc2047.stats'),
  ('OG90H_D2_SBL3_PACB_240821_AD', 0, 'acacia: oceanomics-filtered-reads:OG90_bc2008/hifi/qc_stats/OG90_bc2008_m84154_240821_044521_s1.hifi_reads.bc2008.stats'),
  ('OG910H_D_SBL_PACB_241127_AD', 0, 'acacia: oceanomics-filtered-reads:OG910/hifi/OG910_OG910_m84154_241127_074314_s1.hifi_reads.bc2029.stats'),
  ('OG95H_D_SBL_PACB_230525_AD', 0, 'acacia: oceanomics-filtered-reads:OG95/hifi/qc_stats/m64497e_230528_010643.hifi_reads.bc2010--bc2010.stats;OG95/hifi/qc_stats/m64497e_230528_010643.unbarcoded.hifi_reads.stats;OG95/hifi/qc_stats/m64497e_230529_102918.hifi_reads.bc2010--bc2010.stats;OG95/hifi/qc_stats/m64497e_230529_102918.unbarcoded.hifi_reads.stats'),
  ('OG99G_D2_SBL_PACB_240215_AD', 0, 'acacia: oceanomics-filtered-reads:OG99/hifi/qc_stats/m84154_240215_103559_s3.hifi_reads.bc2041.stats;OG99/hifi/qc_stats/m84154_240215_103559_s3.hifi_reads.unassigned.stats'),
  ('OG9G_D3_SBL_PACB_240206_AD', 0, 'acacia: oceanomics-filtered-reads:OG9/hifi/qc_stats/m84154_240207_164300_s4.hifi_reads.bc2049.stats;OG9/hifi/qc_stats/m84154_240207_164300_s4.hifi_reads.unassigned.stats')
;

CREATE TEMP TABLE d_read_set (
    og_id       text NOT NULL,
    seq_date    text NOT NULL,
    action      text NOT NULL CHECK (action IN ('new', 'correct')),
    read_set_id bigint,          -- the read set corrected
    runs_before text[] NOT NULL,
    runs_after  text[] NOT NULL,
    PRIMARY KEY (og_id, seq_date)
) ON COMMIT DROP;
INSERT INTO d_read_set VALUES
  ('OG2126', '260511', 'new', NULL, '{}'::text[], ARRAY['OG2126E_D_SBL_PACB_260511_AMD']::text[]),
  ('OG2145', '260522', 'new', NULL, '{}'::text[], ARRAY['OG2145G_D_SBL_PACB_260522_AMD']::text[]),
  ('OG39', '250331', 'new', NULL, '{}'::text[], ARRAY['OG39H_D_SBL_PACB_241018_LA', 'OG39H_D_SBL_PACB_250331_LA']::text[]),
  ('OG5', '240116', 'new', NULL, '{}'::text[], ARRAY['OG5G_D2_SBL_PACB_240116_LAAD']::text[]),
  ('OG54', '250331', 'new', NULL, '{}'::text[], ARRAY['OG54G_D_SBL2_PACB_250331_LA', 'OG54G_D_SBL_PACB_241004_LA']::text[]),
  ('OG56', '250704', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG62', '250307', 'new', NULL, '{}'::text[], ARRAY['OG62G_D_SBL2_PACB_250307_AD']::text[]),
  ('OG637', '241031', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG647', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG657', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG673', '240417', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG683', '240821', 'new', NULL, '{}'::text[], ARRAY['OG683H_D_SBL2_PACB_240821_AD']::text[]),
  ('OG683', '241023', 'correct', 27, ARRAY['OG683H_D_SBL2_PACB_241023_AD']::text[], ARRAY['OG683H_D_SBL2_PACB_240821_AD', 'OG683H_D_SBL2_PACB_241023_AD']::text[]),
  ('OG709', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG711', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG716', '250704', 'new', NULL, '{}'::text[], ARRAY['OG716O_D_SBL_PACB_250704_AD']::text[]),
  ('OG721', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG749', '241018', 'new', NULL, '{}'::text[], ARRAY['OG749H_D_SBL_PACB_241018_LA']::text[]),
  ('OG749', '250331', 'correct', 238, ARRAY['OG749H_D_SBL_PACB_250331_LA']::text[], ARRAY['OG749H_D_SBL_PACB_241018_LA', 'OG749H_D_SBL_PACB_250331_LA']::text[]),
  ('OG756', '250717', 'new', NULL, '{}'::text[], ARRAY['OG756G_D_SBL_PACB_250704_AD', 'OG756G_D_SBL_PACB_250717_AD']::text[]),
  ('OG778', '250331', 'new', NULL, '{}'::text[], ARRAY['OG778H_D_SBL_PACB_241018_LA', 'OG778H_D_SBL_PACB_250331_LA']::text[]),
  ('OG781', '250317', 'new', NULL, '{}'::text[], ARRAY['OG781G_D_SBL_PACB_250317_AD']::text[]),
  ('OG788', '250505', 'new', NULL, '{}'::text[], ARRAY['OG788G_D_SBL_PACB_240927_LA', 'OG788G_D_SBL_PACB_250505_LA']::text[]),
  ('OG804', '250717', 'new', NULL, '{}'::text[], ARRAY['OG804G_D_SBL_PACB_250717_AD']::text[]),
  ('OG804', '260227', 'new', NULL, '{}'::text[], ARRAY['OG804G_D_SBL_PACB_260227_AMD']::text[]),
  ('OG820', '230915', 'new', NULL, '{}'::text[], '{}'::text[]),
  ('OG834', '250331', 'new', NULL, '{}'::text[], ARRAY['OG834H_D2_SBL_PACB_240927_LA', 'OG834H_D2_SBL_PACB_250331_LA']::text[]),
  ('OG838', '240520', 'new', NULL, '{}'::text[], ARRAY['OG838B_D_SBL_PACB_240520_LA']::text[]),
  ('OG838', '240813', 'correct', 206, ARRAY['OG838B2_D_SBL_PACB_240813_AD', 'OG838B_D_SBL_PACB_240520_LA']::text[], ARRAY['OG838B2_D_SBL_PACB_240813_AD']::text[]),
  ('OG844', '241023', 'new', NULL, '{}'::text[], ARRAY['OG844H_D4_SBL_PACB_241023_AD', 'OG844H_D5_SBL_PACB_241023_AD']::text[]),
  ('OG863', '250331', 'new', NULL, '{}'::text[], ARRAY['OG863G_D_SBL_PACB_250331_LA']::text[]),
  ('OG866', '250505', 'new', NULL, '{}'::text[], ARRAY['OG866G_D_SBL_PACB_241023_AD', 'OG866G_D_SBL_PACB_250505_LA']::text[]),
  ('OG869', '250307', 'new', NULL, '{}'::text[], ARRAY['OG869M_D_SBL_PACB_250307_AD']::text[])
;

CREATE TEMP TABLE d_assembly (
    assembly_id   bigint PRIMARY KEY,
    og_id         text NOT NULL,
    seq_date      text NOT NULL,
    version       text NOT NULL,
    read_set_date text NOT NULL,   -- with og_id, the read set's key
    runs          text[] NOT NULL, -- its runs, as checked after the backfill
    runs_from     text NOT NULL
) ON COMMIT DROP;
INSERT INTO d_assembly VALUES
  (1, 'OG706', '240206', 'hic2', '240206', ARRAY['OG706H_D_SBL2_PACB_240206_AD', 'OG706H_D_SBL_PACB_240206_AD']::text[], 'links'),
  (2, 'OG665', '240501', 'hifi1', '240501', ARRAY['OG665H_D_SBL_PACB_240501_AD']::text[], 'sibling'),
  (3, 'OG781', '260421', 'hifi1', '260421', ARRAY['OG781G_D_SBL3_PACB_260421_AMD', 'OG781G_D_SBL_PACB_250317_AD']::text[], 'sibling'),
  (4, 'OG680', '241004', 'hic1', '241004', ARRAY['OG680G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (5, 'OG706', '240206', 'hifi1', '240206', ARRAY['OG706H_D_SBL2_PACB_240206_AD', 'OG706H_D_SBL_PACB_240206_AD']::text[], 'links'),
  (6, 'OG803', '240927', 'hic1', '240927', ARRAY['OG803G_D_SBL_PACB_240927_LA']::text[], 'kmer'),
  (7, 'OG101', '240206', 'hic1', '240206', ARRAY['OG101H_D_SBL2_PACB_240206_AD']::text[], 'kmer_approx'),
  (8, 'OG2177', '260603', 'hifi1', '260603', ARRAY['OG2177H_D_SBL_PACB_260603_AMD']::text[], 'links'),
  (9, 'OG100', '240116', 'hic2', '240116', ARRAY['OG100W_D2_SBL_PACB_240116_LAAD']::text[], 'links'),
  (10, 'OG651', '240327', 'hifi1', '240327', ARRAY['OG651H_D_SBL_PACB_240327_LA']::text[], 'links'),
  (11, 'OG836', '240520', 'hic1', '240520', ARRAY['OG836B_D_SBL_PACB_240520_LA']::text[], 'same_date'),
  (12, 'OG2116', '260603', 'hifi1', '260603', ARRAY['OG2116M_D_SBL_PACB_260603_AMD']::text[], 'links'),
  (13, 'OG660', '240228', 'hic1', '240228', ARRAY['OG660H_D2_SBL2_PACB_240228_AD', 'OG660H_D2_SBL_PACB_240228_AD']::text[], 'links'),
  (14, 'OG763', '251117', 'hifi1', '251117', '{}'::text[], 'same_date'),
  (15, 'OG113', '231027', 'hic1', '231027', ARRAY['OG113G_D_SBL_PACB_231027_ADLA']::text[], 'kmer_approx'),
  (16, 'OG696', '240228', 'hifi1', '240228', ARRAY['OG696H_D_SBL_PACB_240228_AD']::text[], 'sibling'),
  (17, 'OG2092', '260626', 'hifi1', '260626', ARRAY['OG2092E_D_SBL_PACB_260626_AMDTW']::text[], 'links'),
  (18, 'OG2188', '260408', 'hifi1', '260408', ARRAY['OG2188H_D_SBL_PACB_260408_AMD']::text[], 'sibling'),
  (19, 'OG824', '241004', 'hic1', '241004', ARRAY['OG824H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (20, 'OG42', '240215', 'hifi1', '240215', ARRAY['OG42G_D_SBL2_PACB_240215_AD']::text[], 'links'),
  (21, 'OG650', '240327', 'hic1', '240327', ARRAY['OG650H_D_SBL_PACB_240327_LA']::text[], 'links'),
  (22, 'OG81', '250704', 'hifi1', '250704', ARRAY['OG81W_D_SBL_PACB_250704_AD']::text[], 'sibling'),
  (23, 'OG2202', '260331', 'hic2', '260331', ARRAY['OG2202H_D_SBL_PACB_260331_AMDLA']::text[], 'kmer_approx'),
  (24, 'OG675', '250828', 'hic1', '250828', ARRAY['OG675G_D2_SBL2_PACB_250828_AD']::text[], 'kmer'),
  (25, 'OG2268', '260428', 'hifi1', '260428', ARRAY['OG2268H_D2_SBL_PACB_260428_AMD']::text[], 'links'),
  (26, 'OG665', '240501', 'hic2', '240501', ARRAY['OG665H_D_SBL_PACB_240501_AD']::text[], 'kmer'),
  (27, 'OG7', '230915', 'hic1', '230915', ARRAY['OG7G_D2_SBL_PACB_230915_LP']::text[], 'links'),
  (28, 'OG711', '230915', 'hifi1', '230915', '{}'::text[], 'none'),
  (29, 'OG2143', '260421', 'hifi1', '260421', ARRAY['OG2143E_D_SBL_PACB_260421_AMD']::text[], 'links'),
  (30, 'OG2163', '260603', 'hifi1', '260603', ARRAY['OG2163H_D_SBL_PACB_260603_AMD']::text[], 'sibling'),
  (31, 'OG10', '230209', 'hic2', '230209', ARRAY['OG10G_D_SBL_PACB_230209_LP']::text[], 'kmer_approx'),
  (32, 'OG81', '250704', 'hic1', '250704', ARRAY['OG81W_D_SBL_PACB_250704_AD']::text[], 'kmer'),
  (33, 'OG646', '240821', 'hic1', '240821', ARRAY['OG646G_D_SBL_PACB_240821_AD']::text[], 'kmer'),
  (34, 'OG819', '250704', 'hic2', '250717', ARRAY['OG819H_D_SBL_PACB_250717_AD']::text[], 'kmer'),
  (35, 'OG35', '231027', 'hic1', '231027', ARRAY['OG35W_D_SBL_PACB_231027_ADLA']::text[], 'links'),
  (36, 'OG699', '250317', 'hifi1', '250317', ARRAY['OG699H_D_SBL_PACB_250317_AD']::text[], 'sibling'),
  (37, 'OG775', '241004', 'hic1', '241004', ARRAY['OG775G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (38, 'OG2128', '260603', 'hifi1', '260603', ARRAY['OG2128E_D_SBL_PACB_260603_AMD']::text[], 'links'),
  (39, 'OG107', '240125', 'hifi1', '240125', ARRAY['OG107G_D_SBL_PACB_240125_LA']::text[], 'sibling'),
  (40, 'OG860', '240927', 'hic1', '240927', ARRAY['OG860H_D_SBL_PACB_240927_LA']::text[], 'sibling'),
  (41, 'OG85', '240927', 'hifi1', '240927', ARRAY['OG85H_D_SBL_PACB_240927_LA']::text[], 'kmer'),
  (42, 'OG67', '241127', 'hifi1', '241127', ARRAY['OG67W_D_SBL_PACB_241127_AD']::text[], 'sibling'),
  (43, 'OG848', '250113', 'hifi1', '250113', ARRAY['OG848U_D_SBL2_PACB_241127_AD', 'OG848U_D_SBL_PACB_250113_AD']::text[], 'same_date'),
  (44, 'OG683', '240821', 'hifi1', '240821', ARRAY['OG683H_D_SBL2_PACB_240821_AD']::text[], 'links_only'),
  (45, 'OG2205', '260522', 'hifi1', '260522', ARRAY['OG2205H_D_SBL_PACB_260522_AMD']::text[], 'links'),
  (46, 'OG804', '260227', 'hifi1', '260227', ARRAY['OG804G_D_SBL_PACB_260227_AMD']::text[], 'links_only'),
  (47, 'OG664', '241018', 'hic1', '241018', ARRAY['OG664H_D_SBL_PACB_241018_LA']::text[], 'kmer'),
  (48, 'OG860', '240927', 'hifi1', '240927', ARRAY['OG860H_D_SBL_PACB_240927_LA']::text[], 'kmer'),
  (49, 'OG790', '250704', 'hic1', '250704', ARRAY['OG790G_D_SBL_PACB_250704_AD']::text[], 'kmer'),
  (50, 'OG100', '240116', 'hic1', '240116', ARRAY['OG100W_D2_SBL_PACB_240116_LAAD']::text[], 'links'),
  (51, 'OG79', '240427', 'hifi1', '240427', ARRAY['OG79G_D_SBL_PACB_240427_LA']::text[], 'sibling'),
  (52, 'OG2165', '260428', 'hifi1', '260428', ARRAY['OG2165H_D_SBL_PACB_260428_AMD']::text[], 'links'),
  (53, 'OG2146', '260414', 'hifi1', '260414', ARRAY['OG2146H_D_SBL_PACB_260414_AMD']::text[], 'sibling'),
  (54, 'OG749', '250331', 'hifi1', '250331', ARRAY['OG749H_D_SBL_PACB_241018_LA', 'OG749H_D_SBL_PACB_250331_LA']::text[], 'sibling'),
  (55, 'OG72', '241023', 'hifi1', '241023', ARRAY['OG72H_D_SBL_PACB_241023_AD']::text[], 'sibling'),
  (56, 'OG748', '241018', 'hifi1', '241018', ARRAY['OG748H_D_SBL_PACB_241018_LA']::text[], 'sibling'),
  (57, 'OG751', '250317', 'hic1', '250317', ARRAY['OG751G_D_SBL_PACB_250317_AD']::text[], 'kmer_approx'),
  (58, 'OG16', '240427', 'hifi1', '240427', ARRAY['OG16G_D_SBL_PACB_240427_LA']::text[], 'links'),
  (59, 'OG767', '250331', 'hifi1', '241004', ARRAY['OG767G_D_SBL_PACB_241004_LA']::text[], 'sibling'),
  (60, 'OG1', '230525', 'hifi1', '230525', ARRAY['OG1G_D_SBL_PACB_230525_AD']::text[], 'links'),
  (61, 'OG681', '250307', 'hic1', '250307', ARRAY['OG681H_D_SBL_PACB_250307_AD']::text[], 'kmer'),
  (62, 'OG2164', '260331', 'hic1', '260331', ARRAY['OG2164H_D_SBL_PACB_260331_AMDLA']::text[], 'kmer_approx'),
  (63, 'OG658', '240327', 'hic1', '240327', ARRAY['OG658H_D_SBL_PACB_240327_LA']::text[], 'kmer_approx'),
  (64, 'OG78', '260626', 'hifi1', '260626', ARRAY['OG78W_D2_SBL_PACB_260626_AMDTW']::text[], 'sibling'),
  (65, 'OG799', '241018', 'hifi1', '241018', ARRAY['OG799H_D2_SBL_PACB_241018_LA']::text[], 'links'),
  (66, 'OG784', '241018', 'hifi1', '241018', ARRAY['OG784G_D_SBL_PACB_241018_LA']::text[], 'sibling'),
  (67, 'OG57', '231027', 'hic1', '231027', ARRAY['OG57G_D_SBL_PACB_231027_ADLA']::text[], 'kmer_approx'),
  (68, 'OG757', '241018', 'hifi1', '241018', ARRAY['OG757G_D_SBL_PACB_241018_LA']::text[], 'sibling'),
  (69, 'OG114', '240116', 'hifi1', '240116', ARRAY['OG114H_D_SBL2_PACB_240116_LAAD']::text[], 'links'),
  (70, 'OG70', '250307', 'hifi1', '250307', ARRAY['OG70W_D_SBL_PACB_250307_AD']::text[], 'sibling'),
  (71, 'OG1326', '260730', 'hic1', '260730', ARRAY['OG1326H_D2_SBL_PACB_260730_AMD']::text[], 'kmer'),
  (72, 'OG62', '250307', 'hic1', '250307', ARRAY['OG62G_D_SBL2_PACB_250307_AD']::text[], 'kmer'),
  (73, 'OG866', '250505', 'hifi1', '250505', ARRAY['OG866G_D_SBL_PACB_241023_AD', 'OG866G_D_SBL_PACB_250505_LA']::text[], 'sibling'),
  (74, 'OG666', '241004', 'hic1', '241004', ARRAY['OG666H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (75, 'OG686', '241004', 'hifi1', '241004', ARRAY['OG686H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (76, 'OG651', '240327', 'hic1', '240327', ARRAY['OG651H_D_SBL_PACB_240327_LA']::text[], 'links'),
  (77, 'OG2242', '260414', 'hifi1', '260414', ARRAY['OG2242H_D_SBL_PACB_260414_AMD']::text[], 'sibling'),
  (78, 'OG686', '241004', 'hic1', '241004', ARRAY['OG686H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (79, 'OG778', '250331', 'hifi1', '250331', ARRAY['OG778H_D_SBL_PACB_241018_LA', 'OG778H_D_SBL_PACB_250331_LA']::text[], 'sibling'),
  (80, 'OG2102', '260227', 'hifi1', '260227', ARRAY['OG2102G_D_SBL_PACB_260227_AMD']::text[], 'links'),
  (81, 'OG5', '240116', 'hifi1', '240116', ARRAY['OG5G_D2_SBL_PACB_240116_LAAD']::text[], 'links_only'),
  (82, 'OG2088', '260414', 'hifi1', '260414', ARRAY['OG2088G_D_SBL_PACB_260414_AMD']::text[], 'sibling'),
  (83, 'OG2090', '260303', 'hifi1', '260303', ARRAY['OG2090E_D_SBL_PACB_260303_AD']::text[], 'links'),
  (84, 'OG2266', '260511', 'hifi1', '260511', ARRAY['OG2266H_D_SBL_PACB_260511_AMD']::text[], 'links'),
  (85, 'OG13', '230212', 'hifi1', '230209', ARRAY['OG13G_D_SBL_PACB_230209_LP']::text[], 'cumulative'),
  (86, 'OG1161', '250113', 'hifi1', '250113', ARRAY['OG1161B_D4_SBL_PACB_250113_AD', 'OG1161B_D5_SBL_PACB_250113_AD']::text[], 'sibling'),
  (87, 'OG808', '240520', 'hifi1', '240520', ARRAY['OG808H_D_SBL_PACB_240520_LA']::text[], 'sibling'),
  (88, 'OG845', '241023', 'hic1', '241023', ARRAY['OG845H_D2_SBL2_PACB_241023_AD', 'OG845H_D2_SBL_PACB_241018_LA', 'OG845H_D2_SBL_PACB_241023_AD']::text[], 'same_date'),
  (89, 'OG2088', '260414', 'hic2', '260414', ARRAY['OG2088G_D_SBL_PACB_260414_AMD']::text[], 'sibling'),
  (90, 'OG12', '230512', 'hifi1', '230512', ARRAY['OG12G_D_SBL_PACB_230512_AD']::text[], 'links'),
  (91, 'OG6', '230702', 'hifi1', '230628', ARRAY['OG6G_D_SBL2_PACB_230628_AD']::text[], 'cumulative'),
  (92, 'OG762', '241019', 'hic1', '241018', ARRAY['OG762H_D_SBL2_PACB_241018_LA']::text[], 'cumulative'),
  (93, 'OG721', '240501', 'hic1', '240501', ARRAY['OG721G_D2_SBL_PACB_240501_AD']::text[], 'kmer_approx'),
  (94, 'OG750', '241105', 'hic3', '241004', ARRAY['OG750G_D_SBL_PACB_241004_LA']::text[], 'cumulative'),
  (95, 'OG7', '230915', 'hifi1', '230915', ARRAY['OG7G_D2_SBL_PACB_230915_LP']::text[], 'links'),
  (96, 'OG763', '251117', 'hic1', '251117', '{}'::text[], 'same_date'),
  (97, 'OG1678', '260603', 'hifi1', '260603', ARRAY['OG1678G_D2_SBL_PACB_260603_AMD']::text[], 'links'),
  (98, 'OG114', '240116', 'hic2', '240116', ARRAY['OG114H_D_SBL2_PACB_240116_LAAD']::text[], 'links'),
  (99, 'OG749', '241018', 'hic1', '241018', ARRAY['OG749H_D_SBL_PACB_241018_LA']::text[], 'links_only'),
  (100, 'OG647', '240501', 'hic1', '240501', ARRAY['OG647H_D_SBL_PACB_240501_AD']::text[], 'kmer_approx'),
  (101, 'OG40', '241004', 'hic1', '241004', ARRAY['OG40H_D2_SBL_PACB_241004_LA']::text[], 'kmer'),
  (102, 'OG647', '240501', 'hifi1', '240501', ARRAY['OG647H_D_SBL_PACB_240501_AD']::text[], 'sibling'),
  (103, 'OG62', '250307', 'hifi1', '250307', ARRAY['OG62G_D_SBL2_PACB_250307_AD']::text[], 'sibling'),
  (104, 'OG804', '260522', 'hifi1', '260522', ARRAY['OG804G_D_SBL2_PACB_260522_AMD', 'OG804G_D_SBL_PACB_250717_AD']::text[], 'sibling'),
  (105, 'OG88', '230728', 'hic1', '230724', ARRAY['OG88G_D_SBL_PACB_230724_AD']::text[], 'cumulative'),
  (106, 'OG2237', '260414', 'hic1', '260414', ARRAY['OG2237H_D_SBL_PACB_260414_AMD']::text[], 'kmer_approx'),
  (107, 'OG72', '241023', 'hic1', '241023', ARRAY['OG72H_D_SBL_PACB_241023_AD']::text[], 'kmer'),
  (108, 'OG759', '250520', 'hifi1', '240520', ARRAY['OG759H_D_SBL_PACB_240520_LA']::text[], 'sibling'),
  (109, 'OG679', '250307', 'hic1', '250307', ARRAY['OG679H_D_SBL_PACB_250307_AD']::text[], 'kmer'),
  (110, 'OG14', '230223', 'hifi1', '230209', ARRAY['OG14G_D_SBL_PACB_230209_LP']::text[], 'cumulative'),
  (111, 'OG709', '230915', 'hifi1', '230915', '{}'::text[], 'none'),
  (112, 'OG65', '250704', 'hic1', '250704', ARRAY['OG65W_D_SBL_PACB_250704_AD']::text[], 'kmer'),
  (113, 'OG13', '230212', 'hic1', '230209', ARRAY['OG13G_D_SBL_PACB_230209_LP']::text[], 'cumulative'),
  (114, 'OG683', '241025', 'hic1', '241023', ARRAY['OG683H_D_SBL2_PACB_240821_AD', 'OG683H_D_SBL2_PACB_241023_AD']::text[], 'kmer'),
  (115, 'OG1613', '260603', 'hifi1', '260603', ARRAY['OG1613M_D_SBL_PACB_260603_AMD']::text[], 'sibling'),
  (116, 'OG5', '240116', 'hic2', '240116', ARRAY['OG5G_D2_SBL_PACB_240116_LAAD']::text[], 'links_only'),
  (117, 'OG2189', '260414', 'hifi1', '260414', ARRAY['OG2189H_D_SBL_PACB_260414_AMD']::text[], 'links'),
  (118, 'OG701', '240509', 'hic1', '240427', ARRAY['OG701H_D_SBL2_PACB_240427_LA']::text[], 'cumulative'),
  (119, 'OG749', '241018', 'hifi1', '241018', ARRAY['OG749H_D_SBL_PACB_241018_LA']::text[], 'links_only'),
  (120, 'OG2127', '260603', 'hic2', '260603', ARRAY['OG2127E_D_SBL_PACB_260603_AMD']::text[], 'kmer'),
  (121, 'OG785', '241004', 'hifi1', '241004', ARRAY['OG785G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (122, 'OG56', '250704', 'hifi1', '250704', '{}'::text[], 'none'),
  (123, 'OG910', '241127', 'hic1', '241127', ARRAY['OG910H_D_SBL_PACB_241127_AD']::text[], 'kmer'),
  (124, 'OG662', '240327', 'hifi1', '240327', ARRAY['OG662G_D_SBL_PACB_240327_LA']::text[], 'sibling'),
  (125, 'OG61', '250318', 'hifi1', '250317', ARRAY['OG61W_D_SBL_PACB_250317_AD']::text[], 'sibling'),
  (126, 'OG820', '240502', 'hifi1', '240501', ARRAY['OG820G_D_SBL_PACB_240501_AD']::text[], 'sibling'),
  (127, 'OG38', '230609', 'hic1', '230609', ARRAY['OG38G_D_SBL_PACB_230609_AD']::text[], 'links'),
  (128, 'OG2093', '260227', 'hifi1', '260227', ARRAY['OG2093E_D_SBL_PACB_260227_AMD']::text[], 'links'),
  (129, 'OG800', '241004', 'hifi1', '241004', ARRAY['OG800H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (130, 'OG648', '250704', 'hifi1', '250704', ARRAY['OG648G_D2_SBL_PACB_250704_AD']::text[], 'sibling'),
  (131, 'OG54', '241004', 'hifi1', '241004', ARRAY['OG54G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (132, 'OG755', '240821', 'hifi1', '240821', ARRAY['OG755H_D_SBL_PACB_240821_AD']::text[], 'kmer_approx'),
  (133, 'OG647', '230915', 'hifi1', '230915', '{}'::text[], 'none'),
  (134, 'OG658', '240327', 'hifi1', '240327', ARRAY['OG658H_D_SBL_PACB_240327_LA']::text[], 'sibling'),
  (135, 'OG698', '241004', 'hifi1', '241004', ARRAY['OG698H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (136, 'OG683', '241025', 'hifi1', '241023', ARRAY['OG683H_D_SBL2_PACB_240821_AD', 'OG683H_D_SBL2_PACB_241023_AD']::text[], 'sibling'),
  (137, 'OG2227', '260414', 'hifi1', '260414', ARRAY['OG2227H_D2_SBL_PACB_260414_AMD']::text[], 'links'),
  (138, 'OG856', '240821', 'hic1', '240821', ARRAY['OG856H_D_SBL_PACB_240821_AD']::text[], 'kmer'),
  (139, 'OG64', '250307', 'hifi1', '250307', ARRAY['OG64W_D_SBL_PACB_250307_AD']::text[], 'links'),
  (140, 'OG855', '240821', 'hifi1', '240821', ARRAY['OG855H_D_SBL_PACB_240821_AD']::text[], 'sibling'),
  (141, 'OG8', '230512', 'hifi1', '230512', ARRAY['OG8G_D_SBL_PACB_230512_AD']::text[], 'sibling'),
  (142, 'OG793', '250317', 'hifi1', '250317', ARRAY['OG793G_D_SBL_PACB_250317_AD']::text[], 'sibling'),
  (143, 'OG637', '240206', 'hifi1', '240206', ARRAY['OG637B_D3_SBL2_PACB_240206_AD', 'OG637B_D3_SBL_PACB_240206_AD']::text[], 'links'),
  (144, 'OG2104', '260414', 'hifi1', '260414', ARRAY['OG2104E_D_SBL_PACB_260414_AMD']::text[], 'sibling'),
  (145, 'OG2124', '260421', 'hic1', '260421', ARRAY['OG2124G_D_SBL_PACB_260421_AMD']::text[], 'kmer_approx'),
  (146, 'OG2124', '260421', 'hifi1', '260421', ARRAY['OG2124G_D_SBL_PACB_260421_AMD']::text[], 'sibling'),
  (147, 'OG750', '241004', 'hic1', '241004', ARRAY['OG750G_D_SBL_PACB_241004_LA']::text[], 'sibling'),
  (148, 'OG90', '240821', 'hifi1', '240821', ARRAY['OG90H_D2_SBL2_PACB_240821_AD']::text[], 'sibling'),
  (149, 'OG811', '241004', 'hic1', '241004', ARRAY['OG811G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (150, 'OG46', '240215', 'hic1', '240215', ARRAY['OG46G_D_SBL_PACB_240215_AD']::text[], 'links'),
  (151, 'OG2130', '260428', 'hifi1', '260428', ARRAY['OG2130G_D_SBL_PACB_260428_AMD']::text[], 'links'),
  (152, 'OG856', '240821', 'hifi1', '240821', ARRAY['OG856H_D_SBL_PACB_240821_AD']::text[], 'kmer'),
  (153, 'OG751', '250317', 'hifi1', '250317', ARRAY['OG751G_D_SBL_PACB_250317_AD']::text[], 'sibling'),
  (154, 'OG38', '230609', 'hifi1', '230609', ARRAY['OG38G_D_SBL_PACB_230609_AD']::text[], 'links'),
  (155, 'OG28', '230811', 'hic1', '230811', ARRAY['OG28B_D4_SBL_PACB_230811_AD', 'OG28B_D5_SBL_PACB_230811_AD', 'OG28B_D6_SBL_PACB_230811_AD', 'OG28B_D7_SBL_PACB_230811_AD']::text[], 'links'),
  (156, 'OG866', '250505', 'hic1', '250505', ARRAY['OG866G_D_SBL_PACB_241023_AD', 'OG866G_D_SBL_PACB_250505_LA']::text[], 'kmer'),
  (157, 'OG53', '230915', 'hic1', '230915', ARRAY['OG53G_D2_SBL2_PACB_230915_LP', 'OG53G_D2_SBL_PACB_230915_LP']::text[], 'links'),
  (158, 'OG2242', '260414', 'hic1', '260414', ARRAY['OG2242H_D_SBL_PACB_260414_AMD']::text[], 'kmer_approx'),
  (159, 'OG2098', '260511', 'hifi1', '260511', ARRAY['OG2098M_D_SBL_PACB_260511_AMD']::text[], 'links'),
  (160, 'OG844', '241023', 'hic1', '241023', ARRAY['OG844H_D4_SBL_PACB_241023_AD', 'OG844H_D5_SBL_PACB_241023_AD']::text[], 'kmer'),
  (161, 'OG2138', '260626', 'hifi1', '260626', ARRAY['OG2138E_D_SBL_PACB_260626_AMDTW']::text[], 'links'),
  (162, 'OG1369', '260227', 'hifi1', '260227', ARRAY['OG1369H_D_SBL_PACB_260227_AMD']::text[], 'links'),
  (163, 'OG646', '240821', 'hifi1', '240821', ARRAY['OG646G_D_SBL_PACB_240821_AD']::text[], 'sibling'),
  (164, 'OG2', '230414', 'hic1', '230413', ARRAY['OG2G_D_SBL_PACB_230413_AD']::text[], 'cumulative'),
  (165, 'OG678', '240327', 'hifi1', '240327', ARRAY['OG678H_D_SBL_PACB_240327_LA']::text[], 'sibling'),
  (166, 'OG105', '231027', 'hifi1', '231027', ARRAY['OG105H_D_SBL_PACB_231027_ADLA']::text[], 'sibling'),
  (167, 'OG2105', '260421', 'hifi1', '260421', ARRAY['OG2105G_D_SBL2_PACB_260421_AMD', 'OG2105G_D_SBL_PACB_260421_AMD']::text[], 'sibling'),
  (168, 'OG824', '241004', 'hifi1', '241004', ARRAY['OG824H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (169, 'OG678', '240327', 'hic2', '240327', ARRAY['OG678H_D_SBL_PACB_240327_LA']::text[], 'kmer_approx'),
  (170, 'OG767', '250331', 'hic1', '241004', ARRAY['OG767G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (171, 'OG863', '241004', 'hifi1', '241004', ARRAY['OG863G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (172, 'OG2241', '260414', 'hifi1', '260414', ARRAY['OG2241H_D2_SBL_PACB_260414_AMD']::text[], 'links'),
  (173, 'OG704', '240427', 'hic1', '240417', ARRAY['OG704H_D_SBL2_PACB_240417_LA']::text[], 'kmer_approx'),
  (174, 'OG804', '250717', 'hifi1', '250717', ARRAY['OG804G_D_SBL_PACB_250717_AD']::text[], 'links_only'),
  (175, 'OG788', '250505', 'hifi1', '250505', ARRAY['OG788G_D_SBL_PACB_240927_LA', 'OG788G_D_SBL_PACB_250505_LA']::text[], 'sibling'),
  (176, 'OG750', '241004', 'hifi1', '241004', ARRAY['OG750G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (177, 'OG2126', '260730', 'hifi1', '260730', ARRAY['OG2126E_D_SBL_PACB_260511_AMD', 'OG2126E_D_SBL_PACB_260730_AMD']::text[], 'sibling'),
  (178, 'OG2209', '260626', 'hifi1', '260626', ARRAY['OG2209H_D_SBL_PACB_260626_AMDTW']::text[], 'links'),
  (179, 'OG56', '240116', 'hifi1', '240116', ARRAY['OG56G_D_SBL_PACB_240116_LAAD']::text[], 'links'),
  (180, 'OG865', '250818', 'hifi1', '250818', ARRAY['OG865G_D_SBL2_PACB_250818_AD']::text[], 'links'),
  (181, 'OG79', '240427', 'hic1', '240427', ARRAY['OG79G_D_SBL_PACB_240427_LA']::text[], 'kmer_approx'),
  (182, 'OG39', '250331', 'hifi1', '250331', ARRAY['OG39H_D_SBL_PACB_241018_LA', 'OG39H_D_SBL_PACB_250331_LA']::text[], 'sibling'),
  (183, 'OG716', '260730', 'hifi1', '260730', ARRAY['OG716O_D_SBL2_PACB_260730_AMD']::text[], 'links'),
  (184, 'OG654', '240327', 'hifi1', '240327', ARRAY['OG654H_D_SBL_PACB_240327_LA']::text[], 'sibling'),
  (185, 'OG811', '241004', 'hifi1', '241004', ARRAY['OG811G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (186, 'OG1663', '260603', 'hifi1', '260603', ARRAY['OG1663G_D_SBL_PACB_260603_AMD']::text[], 'sibling'),
  (187, 'OG1639', '260626', 'hifi1', '260626', ARRAY['OG1639G_D_SBL_PACB_260626_AMDTW']::text[], 'links'),
  (188, 'OG810', '241004', 'hic2', '241004', ARRAY['OG810G_D_SBL_PACB_241004_LA']::text[], 'sibling'),
  (189, 'OG829', '240927', 'hifi1', '240927', ARRAY['OG829H_D2_SBL_PACB_240927_LA']::text[], 'kmer'),
  (190, 'OG73', '250704', 'hic1', '250307', ARRAY['OG73W_D_SBL_PACB_250307_AD']::text[], 'kmer'),
  (191, 'OG15', '230413', 'hifi1', '230413', ARRAY['OG15G_D_SBL_PACB_230413_AD']::text[], 'links'),
  (192, 'OG749', '250331', 'hic2', '250331', ARRAY['OG749H_D_SBL_PACB_241018_LA', 'OG749H_D_SBL_PACB_250331_LA']::text[], 'kmer'),
  (193, 'OG2089', '260227', 'hifi1', '260227', ARRAY['OG2089G_D_SBL_PACB_260227_AMD']::text[], 'links'),
  (194, 'OG67', '241127', 'hic1', '241127', ARRAY['OG67W_D_SBL_PACB_241127_AD']::text[], 'kmer'),
  (195, 'OG748', '241018', 'hic1', '241018', ARRAY['OG748H_D_SBL_PACB_241018_LA']::text[], 'kmer'),
  (196, 'OG849', '241127', 'hifi1', '241127', ARRAY['OG849U_D_SBL_PACB_241127_AD']::text[], 'sibling'),
  (197, 'OG106', '240927', 'hic1', '240927', ARRAY['OG106G_D2_SBL_PACB_240927_LA']::text[], 'kmer'),
  (198, 'OG758', '241127', 'hifi1', '241127', ARRAY['OG758M_D_SBL_PACB_241127_AD']::text[], 'sibling'),
  (199, 'OG61', '250318', 'hic1', '250317', ARRAY['OG61W_D_SBL_PACB_250317_AD']::text[], 'kmer'),
  (200, 'OG696', '240228', 'hic1', '240228', ARRAY['OG696H_D_SBL_PACB_240228_AD']::text[], 'kmer_approx'),
  (201, 'OG766', '241004', 'hifi1', '241004', ARRAY['OG766G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (202, 'OG813', '250704', 'hifi1', '250704', ARRAY['OG813G_D_SBL_PACB_250704_AD']::text[], 'sibling'),
  (203, 'OG2218', '260428', 'hifi1', '260428', ARRAY['OG2218H_D_SBL_PACB_260428_AMD']::text[], 'links'),
  (204, 'OG2166', '260331', 'hifi1', '260331', ARRAY['OG2166H_D_SBL_PACB_260331_AMDLA']::text[], 'links'),
  (205, 'OG837', '240813', 'hifi1', '240813', ARRAY['OG837B_D3_SBL_PACB_240813_AD']::text[], 'sibling'),
  (206, 'OG659', '240427', 'hic2', '240427', ARRAY['OG659H_D_SBL2_PACB_240427_LA']::text[], 'kmer_approx'),
  (207, 'OG808', '240520', 'hic2', '240520', ARRAY['OG808H_D_SBL_PACB_240520_LA']::text[], 'kmer_approx'),
  (208, 'OG777', '240520', 'hic1', '240520', ARRAY['OG777G_D_SBL_PACB_240520_LA']::text[], 'kmer_approx'),
  (209, 'OG849', '241127', 'hic1', '241127', ARRAY['OG849U_D_SBL_PACB_241127_AD']::text[], 'kmer'),
  (210, 'OG5', '230628', 'hifi1', '230628', ARRAY['OG5G_D_SBL2_PACB_230628_AD', 'OG5G_D_SBL_PACB_230609_AD']::text[], 'same_date'),
  (211, 'OG775', '241004', 'hifi1', '241004', ARRAY['OG775G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (212, 'OG113', '231027', 'hifi1', '231027', ARRAY['OG113G_D_SBL_PACB_231027_ADLA']::text[], 'sibling'),
  (213, 'OG676', '240327', 'hifi1', '240327', ARRAY['OG676H_D_SBL_PACB_240327_LA']::text[], 'sibling'),
  (214, 'OG37', '240116', 'hifi1', '240116', ARRAY['OG37G_D_SBL_PACB_240116_LAAD']::text[], 'links'),
  (215, 'OG1454', '260227', 'hifi1', '260227', ARRAY['OG1454H_D_SBL_PACB_260227_AMD']::text[], 'links'),
  (216, 'OG2112', '260603', 'hifi1', '260603', ARRAY['OG2112M_D_SBL_PACB_260603_AMD']::text[], 'sibling'),
  (217, 'OG777', '240520', 'hifi1', '240520', ARRAY['OG777G_D_SBL_PACB_240520_LA']::text[], 'sibling'),
  (218, 'OG2145', '260730', 'hifi1', '260730', ARRAY['OG2145G_D_SBL_PACB_260522_AMD', 'OG2145G_D_SBL_PACB_260730_AMD']::text[], 'sibling'),
  (219, 'OG100', '240116', 'hifi1', '240116', ARRAY['OG100W_D2_SBL_PACB_240116_LAAD']::text[], 'links'),
  (220, 'OG11', '230825', 'hifi1', '230825', ARRAY['OG11G_D_SBL_PACB_230825_AD']::text[], 'links'),
  (221, 'OG1699', '260421', 'hifi1', '260421', ARRAY['OG1699G_D_SBL_PACB_260421_AMD']::text[], 'links'),
  (222, 'OG2142', '260603', 'hifi1', '260603', ARRAY['OG2142G_D_SBL_PACB_260603_AMD']::text[], 'links'),
  (223, 'OG2136', '260730', 'hifi1', '260730', ARRAY['OG2136E_D_SBL_PACB_260730_AMD']::text[], 'links'),
  (224, 'OG680', '241004', 'hifi1', '241004', ARRAY['OG680G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (225, 'OG838', '240520', 'hifi1', '240520', ARRAY['OG838B_D_SBL_PACB_240520_LA']::text[], 'links_only'),
  (226, 'OG60', '241127', 'hifi1', '241127', ARRAY['OG60M_D_SBL_PACB_241127_AD']::text[], 'links'),
  (227, 'OG907', '250828', 'hic1', '250828', ARRAY['OG907H_D_SBL_PACB_250828_AD']::text[], 'kmer'),
  (228, 'OG767', '241004', 'hifi1', '241004', ARRAY['OG767G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (229, 'OG113', '231028', 'hic1', '231027', ARRAY['OG113G_D_SBL_PACB_231027_ADLA']::text[], 'kmer_approx'),
  (230, 'OG58', '250704', 'hic1', '250704', ARRAY['OG58W_D2_SBL_PACB_250704_AD']::text[], 'kmer'),
  (231, 'OG2127', '260603', 'hifi1', '260603', ARRAY['OG2127E_D_SBL_PACB_260603_AMD']::text[], 'sibling'),
  (232, 'OG40', '241004', 'hifi1', '241004', ARRAY['OG40H_D2_SBL_PACB_241004_LA']::text[], 'kmer'),
  (233, 'OG2202', '260331', 'hifi1', '260331', ARRAY['OG2202H_D_SBL_PACB_260331_AMDLA']::text[], 'sibling'),
  (234, 'OG79', '240427', 'hic2', '240427', ARRAY['OG79G_D_SBL_PACB_240427_LA']::text[], 'sibling'),
  (235, 'OG55', '231115', 'hifi1', '231115', ARRAY['OG55G_D_SBL_PACB_231115_LA']::text[], 'sibling'),
  (236, 'OG2200', '260603', 'hifi1', '260603', ARRAY['OG2200H_D_SBL_PACB_260603_AMD']::text[], 'links'),
  (237, 'OG838', '240813', 'hifi1', '240813', ARRAY['OG838B2_D_SBL_PACB_240813_AD']::text[], 'sibling'),
  (238, 'OG37', '240116', 'hic2', '240116', ARRAY['OG37G_D_SBL_PACB_240116_LAAD']::text[], 'links'),
  (239, 'OG54', '250331', 'hifi1', '250331', ARRAY['OG54G_D_SBL2_PACB_250331_LA', 'OG54G_D_SBL_PACB_241004_LA']::text[], 'sibling'),
  (240, 'OG659', '240427', 'hifi1', '240427', ARRAY['OG659H_D_SBL2_PACB_240427_LA']::text[], 'sibling'),
  (241, 'OG637', '240521', 'hic1', '240206', ARRAY['OG637B_D3_SBL2_PACB_240206_AD', 'OG637B_D3_SBL_PACB_240206_AD']::text[], 'cumulative'),
  (242, 'OG12', '230516', 'hifi1', '230512', ARRAY['OG12G_D_SBL_PACB_230512_AD']::text[], 'cumulative'),
  (243, 'OG810', '241004', 'hifi1', '241004', ARRAY['OG810G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (244, 'OG790', '250704', 'hifi1', '250704', ARRAY['OG790G_D_SBL_PACB_250704_AD']::text[], 'sibling'),
  (245, 'OG53', '230915', 'hifi1', '230915', ARRAY['OG53G_D2_SBL2_PACB_230915_LP', 'OG53G_D2_SBL_PACB_230915_LP']::text[], 'links'),
  (246, 'OG673', '240417', 'hifi1', '240417', '{}'::text[], 'none'),
  (247, 'OG2133', '260522', 'hifi1', '260522', ARRAY['OG2133E_D_SBL_PACB_260522_AMD']::text[], 'links'),
  (248, 'OG1651', '260522', 'hifi1', '260522', ARRAY['OG1651G_D2_SBL_PACB_260522_AMD']::text[], 'links'),
  (249, 'OG2119', '260408', 'hic1', '260408', ARRAY['OG2119E_D_SBL_PACB_260408_AMD']::text[], 'kmer_approx'),
  (250, 'OG2237', '260414', 'hifi1', '260414', ARRAY['OG2237H_D_SBL_PACB_260414_AMD']::text[], 'sibling'),
  (251, 'OG9', '240206', 'hifi1', '240206', ARRAY['OG9G_D3_SBL_PACB_240206_AD']::text[], 'links'),
  (252, 'OG838', '240813', 'hic1', '240813', ARRAY['OG838B2_D_SBL_PACB_240813_AD']::text[], 'kmer_approx'),
  (253, 'OG2146', '260414', 'hic1', '260414', ARRAY['OG2146H_D_SBL_PACB_260414_AMD']::text[], 'kmer_approx'),
  (254, 'OG1701', '260428', 'hifi1', '260428', ARRAY['OG1701G_D_SBL_PACB_260428_AMD']::text[], 'links'),
  (255, 'OG657', '230915', 'hifi1', '230915', '{}'::text[], 'none'),
  (256, 'OG847', '260626', 'hifi1', '260626', ARRAY['OG847M_D2_SBL_PACB_260626_AMDTW']::text[], 'links'),
  (257, 'OG793', '250317', 'hic2', '250317', ARRAY['OG793G_D_SBL_PACB_250317_AD']::text[], 'kmer_approx'),
  (258, 'OG2161', '260331', 'hifi1', '260331', ARRAY['OG2161H_D_SBL_PACB_260331_AMDLA']::text[], 'links'),
  (259, 'OG6', '230702', 'hic1', '230628', ARRAY['OG6G_D_SBL2_PACB_230628_AD']::text[], 'cumulative'),
  (260, 'OG702', '240501', 'hic2', '240501', ARRAY['OG702G_D_SBL_PACB_240501_AD']::text[], 'kmer_approx'),
  (261, 'OG36', '230724', 'hic1', '230724', ARRAY['OG36W_D_SBL_PACB_230724_AD']::text[], 'links'),
  (262, 'OG65', '250704', 'hifi1', '250704', ARRAY['OG65W_D_SBL_PACB_250704_AD']::text[], 'sibling'),
  (263, 'OG99', '240215', 'hic1', '240215', ARRAY['OG99G_D2_SBL_PACB_240215_AD']::text[], 'kmer_approx'),
  (264, 'OG721', '230915', 'hifi1', '230915', '{}'::text[], 'none'),
  (265, 'OG859', '241023', 'hic2', '241023', ARRAY['OG859B_D2_SBL_PACB_241023_AD', 'OG859B_D_SBL_PACB_241023_AD']::text[], 'kmer'),
  (266, 'OG637', '240521', 'hifi1', '240206', ARRAY['OG637B_D3_SBL2_PACB_240206_AD', 'OG637B_D3_SBL_PACB_240206_AD']::text[], 'cumulative'),
  (267, 'OG2182', '260331', 'hifi1', '260331', ARRAY['OG2182H_D2_SBL_PACB_260331_AMDLA']::text[], 'links'),
  (268, 'OG756', '250704', 'hifi1', '250717', ARRAY['OG756G_D_SBL_PACB_250704_AD', 'OG756G_D_SBL_PACB_250717_AD']::text[], 'sibling'),
  (269, 'OG803', '240927', 'hifi1', '240927', ARRAY['OG803G_D_SBL_PACB_240927_LA']::text[], 'kmer'),
  (270, 'OG64', '250728', 'hifi1', '250307', ARRAY['OG64W_D_SBL_PACB_250307_AD']::text[], 'sibling'),
  (271, 'OG1161', '250113', 'hic2', '250113', ARRAY['OG1161B_D4_SBL_PACB_250113_AD', 'OG1161B_D5_SBL_PACB_250113_AD']::text[], 'kmer'),
  (272, 'OG2220', '260421', 'hifi1', '260421', ARRAY['OG2220H_D_SBL_PACB_260421_AMD']::text[], 'links'),
  (273, 'OG2104', '260414', 'hic2', '260414', ARRAY['OG2104E_D_SBL_PACB_260414_AMD']::text[], 'kmer_approx'),
  (274, 'OG54', '250331', 'hic1', '250331', ARRAY['OG54G_D_SBL2_PACB_250331_LA', 'OG54G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (275, 'OG766', '241004', 'hic1', '241004', ARRAY['OG766G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (276, 'OG770', '241127', 'hic1', '241127', ARRAY['OG770M_D_SBL_PACB_241127_AD']::text[], 'kmer'),
  (277, 'OG2109', '260626', 'hifi1', '260626', ARRAY['OG2109M_D_SBL_PACB_260626_AMDTW']::text[], 'links'),
  (278, 'OG648', '250704', 'hic1', '250704', ARRAY['OG648G_D2_SBL_PACB_250704_AD']::text[], 'kmer'),
  (279, 'OG76', '230825', 'hic1', '230825', ARRAY['OG76G_D_SBL_PACB_230825_AD']::text[], 'links'),
  (280, 'OG2202', '260331', 'hic1', '260331', ARRAY['OG2202H_D_SBL_PACB_260331_AMDLA']::text[], 'kmer_approx'),
  (281, 'OG760', '240520', 'hic1', '240520', ARRAY['OG760H_D2_SBL_PACB_240520_LA']::text[], 'kmer_approx'),
  (282, 'OG39', '250331', 'hic1', '250331', ARRAY['OG39H_D_SBL_PACB_241018_LA', 'OG39H_D_SBL_PACB_250331_LA']::text[], 'kmer'),
  (283, 'OG834', '240927', 'hifi1', '240927', ARRAY['OG834H_D2_SBL_PACB_240927_LA']::text[], 'kmer'),
  (284, 'OG645', '240427', 'hic1', '240427', ARRAY['OG645H_D_SBL_PACB_240427_LA']::text[], 'links'),
  (285, 'OG756', '250704', 'hic1', '250717', ARRAY['OG756G_D_SBL_PACB_250704_AD', 'OG756G_D_SBL_PACB_250717_AD']::text[], 'kmer'),
  (286, 'OG804', '260522', 'hic1', '260522', ARRAY['OG804G_D_SBL2_PACB_260522_AMD', 'OG804G_D_SBL_PACB_250717_AD']::text[], 'kmer'),
  (287, 'OG910', '241127', 'hifi1', '241127', ARRAY['OG910H_D_SBL_PACB_241127_AD']::text[], 'sibling'),
  (288, 'OG2151', '260421', 'hifi1', '260421', ARRAY['OG2151H_D_SBL_PACB_260421_AMD']::text[], 'links'),
  (289, 'OG844', '241023', 'hifi1', '241023', ARRAY['OG844H_D4_SBL_PACB_241023_AD', 'OG844H_D5_SBL_PACB_241023_AD']::text[], 'sibling'),
  (290, 'OG820', '240502', 'hic2', '240501', ARRAY['OG820G_D_SBL_PACB_240501_AD']::text[], 'kmer'),
  (291, 'OG2179', '260428', 'hifi1', '260428', ARRAY['OG2179M_D_SBL_PACB_260428_AMD']::text[], 'links'),
  (292, 'OG664', '241018', 'hifi1', '241018', ARRAY['OG664H_D_SBL_PACB_241018_LA']::text[], 'sibling'),
  (293, 'OG104', '250113', 'hifi1', '250113', ARRAY['OG104M_D_SBL2_PACB_241127_AD', 'OG104M_D_SBL_PACB_250113_AD']::text[], 'same_date'),
  (294, 'OG2127', '260603', 'hic1', '260603', ARRAY['OG2127E_D_SBL_PACB_260603_AMD']::text[], 'kmer'),
  (295, 'OG90', '240821', 'hic1', '240821', ARRAY['OG90H_D2_SBL2_PACB_240821_AD']::text[], 'kmer'),
  (296, 'OG778', '241018', 'hifi1', '241018', ARRAY['OG778H_D_SBL_PACB_241018_LA']::text[], 'links'),
  (297, 'OG3', '230825', 'hifi1', '230825', ARRAY['OG3G_D_SBL_PACB_230825_AD']::text[], 'links'),
  (298, 'OG57', '231027', 'hifi1', '231027', ARRAY['OG57G_D_SBL_PACB_231027_ADLA']::text[], 'sibling'),
  (299, 'OG2122', '260511', 'hic1', '260511', ARRAY['OG2122E_D_SBL_PACB_260511_AMD']::text[], 'kmer_approx'),
  (300, 'OG95', '230529', 'hic1', '230525', ARRAY['OG95H_D_SBL_PACB_230525_AD']::text[], 'cumulative'),
  (301, 'OG61', '250317', 'hic1', '250317', ARRAY['OG61W_D_SBL_PACB_250317_AD']::text[], 'kmer'),
  (302, 'OG2113', '260522', 'hifi1', '260522', ARRAY['OG2113M_D_SBL_PACB_260522_AMD']::text[], 'links'),
  (303, 'OG679', '250307', 'hifi1', '250307', ARRAY['OG679H_D_SBL_PACB_250307_AD']::text[], 'sibling'),
  (304, 'OG910', '241127', 'hic2', '241127', ARRAY['OG910H_D_SBL_PACB_241127_AD']::text[], 'kmer'),
  (305, 'OG794', '250307', 'hifi1', '250307', ARRAY['OG794G_D_SBL_PACB_250307_AD']::text[], 'links'),
  (306, 'OG759', '240520', 'hifi1', '240520', ARRAY['OG759H_D_SBL_PACB_240520_LA']::text[], 'links'),
  (307, 'OG800', '241004', 'hic1', '241004', ARRAY['OG800H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (308, 'OG704', '240417', 'hifi1', '240417', ARRAY['OG704H_D_SBL2_PACB_240417_LA']::text[], 'links'),
  (309, 'OG1560', '260408', 'hifi1', '260408', ARRAY['OG1560G_D_SBL_PACB_260408_AMD']::text[], 'links'),
  (310, 'OG56', '250704', 'hic1', '250704', '{}'::text[], 'none'),
  (311, 'OG652', '240327', 'hic1', '240327', ARRAY['OG652H_D_SBL_PACB_240327_LA']::text[], 'kmer'),
  (312, 'OG799', '241019', 'hifi1', '241018', ARRAY['OG799H_D2_SBL_PACB_241018_LA']::text[], 'sibling'),
  (313, 'OG787', '240927', 'hifi1', '240927', ARRAY['OG787G_D_SBL_PACB_240927_LA']::text[], 'kmer'),
  (314, 'OG645', '240417', 'hifi1', '240427', ARRAY['OG645H_D_SBL_PACB_240427_LA']::text[], 'sibling'),
  (315, 'OG836', '240520', 'hifi1', '240520', ARRAY['OG836B_D_SBL_PACB_240520_LA']::text[], 'same_date'),
  (316, 'OG105', '231027', 'hic1', '231027', ARRAY['OG105H_D_SBL_PACB_231027_ADLA']::text[], 'kmer_approx'),
  (317, 'OG2135', '260730', 'hifi1', '260730', ARRAY['OG2135E_D_SBL_PACB_260730_AMD']::text[], 'links'),
  (318, 'OG9', '240206', 'hic1', '240206', ARRAY['OG9G_D3_SBL_PACB_240206_AD']::text[], 'links'),
  (319, 'OG3', '230825', 'hic1', '230825', ARRAY['OG3G_D_SBL_PACB_230825_AD']::text[], 'links'),
  (320, 'OG46', '240215', 'hifi1', '240215', ARRAY['OG46G_D_SBL_PACB_240215_AD']::text[], 'links'),
  (321, 'OG106', '240927', 'hifi1', '240927', ARRAY['OG106G_D2_SBL_PACB_240927_LA']::text[], 'kmer'),
  (322, 'OG654', '240327', 'hic1', '240327', ARRAY['OG654H_D_SBL_PACB_240327_LA']::text[], 'kmer'),
  (323, 'OG696', '240228', 'hic2', '240228', ARRAY['OG696H_D_SBL_PACB_240228_AD']::text[], 'kmer_approx'),
  (324, 'OG12', '230516', 'hic1', '230512', ARRAY['OG12G_D_SBL_PACB_230512_AD']::text[], 'cumulative'),
  (325, 'OG701', '240427', 'hifi1', '240427', ARRAY['OG701H_D_SBL2_PACB_240427_LA']::text[], 'links'),
  (326, 'OG652', '240327', 'hifi1', '240327', ARRAY['OG652H_D_SBL_PACB_240327_LA']::text[], 'sibling'),
  (327, 'OG1297', '250818', 'hifi1', '250818', ARRAY['OG1297B_D_SBL_PACB_250818_AD']::text[], 'links'),
  (328, 'OG820', '240501', 'hic1', '240501', ARRAY['OG820G_D_SBL_PACB_240501_AD']::text[], 'kmer_approx'),
  (329, 'OG55', '231115', 'hic1', '231115', ARRAY['OG55G_D_SBL_PACB_231115_LA']::text[], 'kmer_approx'),
  (330, 'OG2203', '260408', 'hifi1', '260408', ARRAY['OG2203H_D_SBL_PACB_260408_AMD']::text[], 'sibling'),
  (331, 'OG657', '250110', 'hic1', '240501', ARRAY['OG657H_D_SBL_PACB_240501_AD']::text[], 'kmer_approx'),
  (332, 'OG855', '240821', 'hic1', '240821', ARRAY['OG855H_D_SBL_PACB_240821_AD']::text[], 'kmer'),
  (333, 'OG1650', '260331', 'hifi1', '260331', ARRAY['OG1650H_D_SBL_PACB_260331_AMDLA']::text[], 'links'),
  (334, 'OG813', '250704', 'hic2', '250704', ARRAY['OG813G_D_SBL_PACB_250704_AD']::text[], 'kmer'),
  (335, 'OG866', '241023', 'hifi1', '241023', ARRAY['OG866G_D_SBL_PACB_241023_AD']::text[], 'links'),
  (336, 'OG2119', '260408', 'hifi1', '260408', ARRAY['OG2119E_D_SBL_PACB_260408_AMD']::text[], 'sibling'),
  (337, 'OG755', '240821', 'hic1', '240821', ARRAY['OG755H_D_SBL_PACB_240821_AD']::text[], 'kmer_approx'),
  (338, 'OG804', '260522', 'hic2', '260522', ARRAY['OG804G_D_SBL2_PACB_260522_AMD', 'OG804G_D_SBL_PACB_250717_AD']::text[], 'sibling'),
  (339, 'OG2159', '260408', 'hifi1', '260408', ARRAY['OG2159H_D_SBL_PACB_260408_AMD']::text[], 'links'),
  (340, 'OG2122', '260511', 'hifi1', '260511', ARRAY['OG2122E_D_SBL_PACB_260511_AMD']::text[], 'sibling'),
  (341, 'OG681', '250307', 'hifi1', '250307', ARRAY['OG681H_D_SBL_PACB_250307_AD']::text[], 'sibling'),
  (342, 'OG108', '231027', 'hic1', '231027', ARRAY['OG108H_D_SBL_PACB_231027_ADLA']::text[], 'kmer_approx'),
  (343, 'OG39', '241018', 'hifi1', '241018', ARRAY['OG39H_D_SBL_PACB_241018_LA']::text[], 'links'),
  (344, 'OG70', '250307', 'hic1', '250307', ARRAY['OG70W_D_SBL_PACB_250307_AD']::text[], 'kmer'),
  (345, 'OG52', '230825', 'hic1', '230825', ARRAY['OG52G_D_SBL_PACB_230825_AD']::text[], 'links'),
  (346, 'OG784', '241018', 'hic1', '241018', ARRAY['OG784G_D_SBL_PACB_241018_LA']::text[], 'kmer'),
  (347, 'OG2121', '260511', 'hifi1', '260511', ARRAY['OG2121E_D_SBL_PACB_260511_AMD']::text[], 'sibling'),
  (348, 'OG666', '241004', 'hifi1', '241004', ARRAY['OG666H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (349, 'OG765', '240821', 'hic1', '240821', ARRAY['OG765W_D_SBL_PACB_240821_AD']::text[], 'kmer'),
  (350, 'OG859', '241023', 'hifi1', '241023', ARRAY['OG859B_D2_SBL_PACB_241023_AD', 'OG859B_D_SBL_PACB_241023_AD']::text[], 'sibling'),
  (351, 'OG799', '241019', 'hic1', '241018', ARRAY['OG799H_D2_SBL_PACB_241018_LA']::text[], 'kmer'),
  (352, 'OG662', '240327', 'hic1', '240327', ARRAY['OG662G_D_SBL_PACB_240327_LA']::text[], 'kmer_approx'),
  (353, 'OG1573', '260626', 'hifi1', '260626', ARRAY['OG1573M_D_SBL_PACB_260626_AMDTW']::text[], 'sibling'),
  (354, 'OG115', '240125', 'hifi1', '240125', ARRAY['OG115H_D_SBL_PACB_240125_LA']::text[], 'sibling'),
  (355, 'OG47', '231115', 'hic1', '231115', ARRAY['OG47G_D_SBL_PACB_231115_LA']::text[], 'links'),
  (356, 'OG785', '241004', 'hic2', '241004', ARRAY['OG785G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (357, 'OG794', '250317', 'hic2', '250307', ARRAY['OG794G_D_SBL_PACB_250307_AD']::text[], 'kmer'),
  (358, 'OG52', '230825', 'hifi1', '230825', ARRAY['OG52G_D_SBL_PACB_230825_AD']::text[], 'links'),
  (359, 'OG906', '250212', 'hifi1', '250212', '{}'::text[], 'same_date'),
  (360, 'OG10', '230209', 'hifi1', '230209', ARRAY['OG10G_D_SBL_PACB_230209_LP']::text[], 'sibling'),
  (361, 'OG853', '250717', 'hifi1', '250717', ARRAY['OG853O_D_SBL_PACB_250717_AD']::text[], 'links'),
  (362, 'OG765', '240821', 'hifi1', '240821', ARRAY['OG765W_D_SBL_PACB_240821_AD']::text[], 'sibling'),
  (363, 'OG16', '240417', 'hifi1', '240427', ARRAY['OG16G_D_SBL_PACB_240427_LA']::text[], 'cumulative'),
  (364, 'OG111', '241018', 'hifi1', '241018', ARRAY['OG111H_D_SBL_PACB_241018_LA']::text[], 'sibling'),
  (365, 'OG107', '240125', 'hic1', '240125', ARRAY['OG107G_D_SBL_PACB_240125_LA']::text[], 'kmer_approx'),
  (366, 'OG8', '230512', 'hic1', '230512', ARRAY['OG8G_D_SBL_PACB_230512_AD']::text[], 'kmer_approx'),
  (367, 'OG711', '260603', 'hifi1', '260603', ARRAY['OG711O_D3_SBL_PACB_260603_AMD']::text[], 'links'),
  (368, 'OG863', '250331', 'hifi1', '250331', ARRAY['OG863G_D_SBL_PACB_250331_LA']::text[], 'links_only'),
  (369, 'OG101', '240206', 'hifi1', '240206', ARRAY['OG101H_D_SBL2_PACB_240206_AD']::text[], 'sibling'),
  (370, 'OG637', '241031', 'ont1', '241031', '{}'::text[], 'none'),
  (371, 'OG781', '250317', 'hifi1', '250317', ARRAY['OG781G_D_SBL_PACB_250317_AD']::text[], 'links_only'),
  (372, 'OG2178', '260408', 'hifi1', '260408', ARRAY['OG2178H_D_SBL_PACB_260408_AMD']::text[], 'sibling'),
  (373, 'OG16', '240417', 'hic1', '240427', ARRAY['OG16G_D_SBL_PACB_240427_LA']::text[], 'cumulative'),
  (374, 'OG14', '230209', 'hic1', '230209', ARRAY['OG14G_D_SBL_PACB_230209_LP']::text[], 'links'),
  (375, 'OG762', '241018', 'hifi1', '241018', ARRAY['OG762H_D_SBL2_PACB_241018_LA']::text[], 'links'),
  (376, 'OG47', '231115', 'hifi1', '231115', ARRAY['OG47G_D_SBL_PACB_231115_LA']::text[], 'links'),
  (377, 'OG2317', '260303', 'hifi1', '260303', ARRAY['OG2317B_D_SBL2_PACB_260303_AD', 'OG2317B_D_SBL_PACB_260303_AD']::text[], 'links'),
  (378, 'OG863', '250331', 'hic1', '250331', ARRAY['OG863G_D_SBL_PACB_250331_LA']::text[], 'links_only'),
  (379, 'OG845', '241023', 'hifi1', '241023', ARRAY['OG845H_D2_SBL2_PACB_241023_AD', 'OG845H_D2_SBL_PACB_241018_LA', 'OG845H_D2_SBL_PACB_241023_AD']::text[], 'same_date'),
  (380, 'OG760', '240520', 'hifi1', '240520', ARRAY['OG760H_D2_SBL_PACB_240520_LA']::text[], 'sibling'),
  (381, 'OG649', '240417', 'hifi1', '240427', ARRAY['OG649H_D2_SBL2_PACB_240427_LA']::text[], 'sibling'),
  (382, 'OG645', '240417', 'hic1', '240427', ARRAY['OG645H_D_SBL_PACB_240427_LA']::text[], 'kmer_approx'),
  (383, 'OG829', '240927', 'hic1', '240927', ARRAY['OG829H_D2_SBL_PACB_240927_LA']::text[], 'kmer'),
  (384, 'OG2126', '260511', 'hifi1', '260511', ARRAY['OG2126E_D_SBL_PACB_260511_AMD']::text[], 'links_only'),
  (385, 'OG2164', '260331', 'hifi1', '260331', ARRAY['OG2164H_D_SBL_PACB_260331_AMDLA']::text[], 'sibling'),
  (386, 'OG695', '240520', 'hic1', '240520', ARRAY['OG695H_D_SBL3_PACB_240520_LA']::text[], 'kmer_approx'),
  (387, 'OG781', '260421', 'hic1', '260421', ARRAY['OG781G_D_SBL3_PACB_260421_AMD', 'OG781G_D_SBL_PACB_250317_AD']::text[], 'kmer_approx'),
  (388, 'OG695', '240520', 'hifi1', '240520', ARRAY['OG695H_D_SBL3_PACB_240520_LA']::text[], 'sibling'),
  (389, 'OG99', '240215', 'hifi1', '240215', ARRAY['OG99G_D2_SBL_PACB_240215_AD']::text[], 'sibling'),
  (390, 'OG2088', '260414', 'hic1', '260414', ARRAY['OG2088G_D_SBL_PACB_260414_AMD']::text[], 'kmer_approx'),
  (391, 'OG1', '230525', 'hic1', '230525', ARRAY['OG1G_D_SBL_PACB_230525_AD']::text[], 'links'),
  (392, 'OG36', '230724', 'hifi1', '230724', ARRAY['OG36W_D_SBL_PACB_230724_AD']::text[], 'links'),
  (393, 'OG716', '250704', 'hifi1', '250704', ARRAY['OG716O_D_SBL_PACB_250704_AD']::text[], 'links_only'),
  (394, 'OG1663', '260603', 'hic2', '260603', ARRAY['OG1663G_D_SBL_PACB_260603_AMD']::text[], 'kmer'),
  (395, 'OG657', '250110', 'hifi1', '240501', ARRAY['OG657H_D_SBL_PACB_240501_AD']::text[], 'sibling'),
  (396, 'OG111', '241018', 'hic1', '241018', ARRAY['OG111H_D_SBL_PACB_241018_LA']::text[], 'kmer'),
  (397, 'OG2131', '260511', 'hifi1', '260511', ARRAY['OG2131E_D_SBL_PACB_260511_AMD']::text[], 'links'),
  (398, 'OG701', '240509', 'hifi1', '240427', ARRAY['OG701H_D_SBL2_PACB_240427_LA']::text[], 'cumulative'),
  (399, 'OG702', '240501', 'hifi1', '240501', ARRAY['OG702G_D_SBL_PACB_240501_AD']::text[], 'sibling'),
  (400, 'OG2178', '260408', 'hic1', '260408', ARRAY['OG2178H_D_SBL_PACB_260408_AMD']::text[], 'kmer_approx'),
  (401, 'OG2325', '260428', 'hifi1', '260428', ARRAY['OG2325H_D2_SBL_PACB_260428_AMD']::text[], 'links'),
  (402, 'OG95', '230525', 'hifi1', '230525', ARRAY['OG95H_D_SBL_PACB_230525_AD']::text[], 'links'),
  (403, 'OG837', '240813', 'hic1', '240813', ARRAY['OG837B_D3_SBL_PACB_240813_AD']::text[], 'kmer_approx'),
  (404, 'OG844', '260511', 'hifi1', '260511', ARRAY['OG844H_D5_SBL_PACB_260511_AMD']::text[], 'links'),
  (405, 'OG28', '230811', 'hifi1', '230811', ARRAY['OG28B_D4_SBL_PACB_230811_AD', 'OG28B_D5_SBL_PACB_230811_AD', 'OG28B_D6_SBL_PACB_230811_AD', 'OG28B_D7_SBL_PACB_230811_AD']::text[], 'links'),
  (406, 'OG2132', '260408', 'hifi1', '260408', ARRAY['OG2132E_D_SBL_PACB_260408_AMD']::text[], 'sibling'),
  (407, 'OG1455', '260331', 'hifi1', '260331', ARRAY['OG1455H_D_SBL_PACB_260331_AMDLA']::text[], 'links'),
  (408, 'OG672', '240215', 'hifi1', '240215', ARRAY['OG672H_D2_SBL_PACB_240215_AD']::text[], 'links'),
  (409, 'OG108', '231027', 'hifi1', '231027', ARRAY['OG108H_D_SBL_PACB_231027_ADLA']::text[], 'sibling'),
  (410, 'OG869', '250307', 'hifi1', '250307', ARRAY['OG869M_D_SBL_PACB_250307_AD']::text[], 'links_only'),
  (411, 'OG759', '250520', 'hic1', '240520', ARRAY['OG759H_D_SBL_PACB_240520_LA']::text[], 'kmer_approx'),
  (412, 'OG106', '240927', 'hic2', '240927', ARRAY['OG106G_D2_SBL_PACB_240927_LA']::text[], 'kmer'),
  (413, 'OG660', '240228', 'hifi1', '240228', ARRAY['OG660H_D2_SBL2_PACB_240228_AD', 'OG660H_D2_SBL_PACB_240228_AD']::text[], 'links'),
  (414, 'OG778', '250331', 'hic1', '250331', ARRAY['OG778H_D_SBL_PACB_241018_LA', 'OG778H_D_SBL_PACB_250331_LA']::text[], 'kmer'),
  (415, 'OG2188', '260408', 'hic1', '260408', ARRAY['OG2188H_D_SBL_PACB_260408_AMD']::text[], 'kmer_approx'),
  (416, 'OG852', '250717', 'hifi1', '250717', ARRAY['OG852O_D_SBL_PACB_250717_AD']::text[], 'links'),
  (417, 'OG35', '231027', 'hifi1', '231027', ARRAY['OG35W_D_SBL_PACB_231027_ADLA']::text[], 'links'),
  (418, 'OG1573', '260626', 'hic2', '260626', ARRAY['OG1573M_D_SBL_PACB_260626_AMDTW']::text[], 'kmer_approx'),
  (419, 'OG113', '231028', 'hifi1', '231027', ARRAY['OG113G_D_SBL_PACB_231027_ADLA']::text[], 'sibling'),
  (420, 'OG819', '250717', 'hifi1', '250717', ARRAY['OG819H_D_SBL_PACB_250717_AD']::text[], 'links'),
  (421, 'OG676', '240327', 'hic1', '240327', ARRAY['OG676H_D_SBL_PACB_240327_LA']::text[], 'kmer_approx'),
  (422, 'OG659', '240418', 'hic1', '240427', ARRAY['OG659H_D_SBL2_PACB_240427_LA']::text[], 'cumulative'),
  (423, 'OG1422', '260227', 'hifi1', '260227', ARRAY['OG1422H_D_SBL_PACB_260227_AMD']::text[], 'links'),
  (424, 'OG2145', '260522', 'hifi1', '260522', ARRAY['OG2145G_D_SBL_PACB_260522_AMD']::text[], 'links_only'),
  (425, 'OG27', '230512', 'hifi1', '230512', ARRAY['OG27B_D_SBL_PACB_230512_AD']::text[], 'links'),
  (426, 'OG769', '250828', 'hic1', '250828', ARRAY['OG769G_D_SBL_PACB_250828_AD']::text[], 'kmer'),
  (427, 'OG2320', '260303', 'hifi1', '260303', ARRAY['OG2320B_D2_SBL_PACB_260303_AD']::text[], 'links'),
  (428, 'OG2100', '260227', 'hifi1', '260227', ARRAY['OG2100G_D_SBL_PACB_260227_AMD']::text[], 'links'),
  (429, 'OG834', '250331', 'hic1', '250331', ARRAY['OG834H_D2_SBL_PACB_240927_LA', 'OG834H_D2_SBL_PACB_250331_LA']::text[], 'kmer'),
  (430, 'OG13', '230223', 'hifi1', '230209', ARRAY['OG13G_D_SBL_PACB_230209_LP']::text[], 'cumulative'),
  (431, 'OG2', '230413', 'hifi1', '230413', ARRAY['OG2G_D_SBL_PACB_230413_AD']::text[], 'links'),
  (432, 'OG1613', '260603', 'hic2', '260603', ARRAY['OG1613M_D_SBL_PACB_260603_AMD']::text[], 'kmer_approx'),
  (433, 'OG64', '250728', 'hic1', '250307', ARRAY['OG64W_D_SBL_PACB_250307_AD']::text[], 'kmer'),
  (434, 'OG659', '240418', 'hifi1', '240427', ARRAY['OG659H_D_SBL2_PACB_240427_LA']::text[], 'cumulative'),
  (435, 'OG2156', '260408', 'hic1', '260408', ARRAY['OG2156H_D_SBL_PACB_260408_AMD']::text[], 'kmer_approx'),
  (436, 'OG2134', '260511', 'hifi1', '260511', ARRAY['OG2134E_D_SBL_PACB_260511_AMD']::text[], 'links'),
  (437, 'OG58', '250704', 'hifi1', '250704', ARRAY['OG58W_D2_SBL_PACB_250704_AD']::text[], 'sibling'),
  (438, 'OG14', '230209', 'hifi1', '230209', ARRAY['OG14G_D_SBL_PACB_230209_LP']::text[], 'links'),
  (439, 'OG11', '230825', 'hic1', '230825', ARRAY['OG11G_D_SBL_PACB_230825_AD']::text[], 'links'),
  (440, 'OG115', '240125', 'hic1', '240125', ARRAY['OG115H_D_SBL_PACB_240125_LA']::text[], 'kmer_approx'),
  (441, 'OG770', '241127', 'hifi1', '241127', ARRAY['OG770M_D_SBL_PACB_241127_AD']::text[], 'sibling'),
  (442, 'OG758', '241127', 'hic1', '241127', ARRAY['OG758M_D_SBL_PACB_241127_AD']::text[], 'kmer'),
  (443, 'OG834', '250331', 'hifi1', '250331', ARRAY['OG834H_D2_SBL_PACB_240927_LA', 'OG834H_D2_SBL_PACB_250331_LA']::text[], 'sibling'),
  (444, 'OG85', '240927', 'hic1', '240927', ARRAY['OG85H_D_SBL_PACB_240927_LA']::text[], 'kmer'),
  (445, 'OG788', '240927', 'hifi1', '240927', ARRAY['OG788G_D_SBL_PACB_240927_LA']::text[], 'kmer'),
  (446, 'OG820', '230915', 'hifi1', '230915', '{}'::text[], 'none'),
  (447, 'OG2156', '260408', 'hifi1', '260408', ARRAY['OG2156H_D_SBL_PACB_260408_AMD']::text[], 'sibling'),
  (448, 'OG649', '240417', 'hic1', '240427', ARRAY['OG649H_D2_SBL2_PACB_240427_LA']::text[], 'kmer_approx'),
  (449, 'OG88', '230728', 'hifi1', '230724', ARRAY['OG88G_D_SBL_PACB_230724_AD']::text[], 'cumulative'),
  (450, 'OG650', '240327', 'hifi1', '240327', ARRAY['OG650H_D_SBL_PACB_240327_LA']::text[], 'links'),
  (451, 'OG788', '250505', 'hic1', '250505', ARRAY['OG788G_D_SBL_PACB_240927_LA', 'OG788G_D_SBL_PACB_250505_LA']::text[], 'kmer'),
  (452, 'OG863', '241004', 'hic1', '241004', ARRAY['OG863G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (453, 'OG801', '250828', 'hic1', '250828', ARRAY['OG801L_D_SBL_PACB_250828_AD']::text[], 'kmer'),
  (454, 'OG6', '230628', 'hifi1', '230628', ARRAY['OG6G_D_SBL2_PACB_230628_AD']::text[], 'links'),
  (455, 'OG757', '241018', 'hic1', '241018', ARRAY['OG757G_D_SBL_PACB_241018_LA']::text[], 'kmer'),
  (456, 'OG868', '250317', 'hifi1', '250317', ARRAY['OG868M_D_SBL_PACB_250317_AD']::text[], 'links'),
  (457, 'OG95', '230529', 'hifi1', '230525', ARRAY['OG95H_D_SBL_PACB_230525_AD']::text[], 'cumulative'),
  (458, 'OG762', '241019', 'hifi1', '241018', ARRAY['OG762H_D_SBL2_PACB_241018_LA']::text[], 'cumulative'),
  (459, 'OG906', '250212', 'hic1', '250212', '{}'::text[], 'same_date'),
  (460, 'OG810', '241004', 'hic1', '241004', ARRAY['OG810G_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (461, 'OG2269', '260428', 'hifi1', '260428', ARRAY['OG2269G_D_SBL_PACB_260428_AMD']::text[], 'links'),
  (462, 'OG787', '240927', 'hic1', '240927', ARRAY['OG787G_D_SBL_PACB_240927_LA']::text[], 'kmer'),
  (463, 'OG1326', '260730', 'hifi1', '260730', ARRAY['OG1326H_D2_SBL_PACB_260730_AMD']::text[], 'sibling'),
  (464, 'OG2118', '260626', 'hifi1', '260626', ARRAY['OG2118E_D_SBL_PACB_260626_AMDTW']::text[], 'links'),
  (465, 'OG672', '240215', 'hic1', '240215', ARRAY['OG672H_D2_SBL_PACB_240215_AD']::text[], 'links'),
  (466, 'OG2132', '260408', 'hic1', '260408', ARRAY['OG2132E_D_SBL_PACB_260408_AMD']::text[], 'kmer_approx'),
  (467, 'OG2099', '260603', 'hifi1', '260603', ARRAY['OG2099M_D_SBL_PACB_260603_AMD']::text[], 'links'),
  (468, 'OG15', '230413', 'hic1', '230413', ARRAY['OG15G_D_SBL_PACB_230413_AD']::text[], 'links'),
  (9830, 'OG698', '241004', 'hic1', '241004', ARRAY['OG698H_D_SBL_PACB_241004_LA']::text[], 'kmer'),
  (9849, 'OG2089', '260721', 'hic1', '260721', ARRAY['OG2089G_D_SBL_PACB_260227_AMD', 'OG2089G_D_SBL_PACB_260721_AD']::text[], 'kmer'),
  (9852, 'OG2093', '260721', 'hic1', '260721', ARRAY['OG2093E_D_SBL_PACB_260227_AMD', 'OG2093E_D_SBL_PACB_260721_AD']::text[], 'kmer'),
  (9855, 'OG2112', '260603', 'hic1', '260603', ARRAY['OG2112M_D_SBL_PACB_260603_AMD']::text[], 'kmer'),
  (9858, 'OG2121', '260511', 'hic1', '260511', ARRAY['OG2121E_D_SBL_PACB_260511_AMD']::text[], 'kmer'),
  (9861, 'OG2126', '260730', 'hic1', '260730', ARRAY['OG2126E_D_SBL_PACB_260511_AMD', 'OG2126E_D_SBL_PACB_260730_AMD']::text[], 'kmer'),
  (9864, 'OG2128', '260721', 'hic1', '260721', ARRAY['OG2128E_D_SBL_PACB_260603_AMD', 'OG2128E_D_SBL_PACB_260721_AD']::text[], 'kmer'),
  (9867, 'OG2163', '260603', 'hic1', '260603', ARRAY['OG2163H_D_SBL_PACB_260603_AMD']::text[], 'kmer'),
  (9870, 'OG2203', '260408', 'hic1', '260408', ARRAY['OG2203H_D_SBL_PACB_260408_AMD']::text[], 'kmer'),
  (9873, 'OG673', '240427', 'hic1', '240427', ARRAY['OG673H_D_SBL2_PACB_240427_LA']::text[], 'kmer'),
  (9876, 'OG699', '250317', 'hic1', '250317', ARRAY['OG699H_D_SBL_PACB_250317_AD']::text[], 'kmer'),
  (9879, 'OG78', '260626', 'hic1', '260626', ARRAY['OG78W_D2_SBL_PACB_260626_AMDTW']::text[], 'kmer'),
  (10058, 'OG1568', '261102', 'hifi1', '261102', ARRAY['OG1568G_D_SBL_PACB_261102_AMD']::text[], 'links'),
  (10060, 'OG1591', '261102', 'hifi1', '261102', ARRAY['OG1591M_D_SBL_PACB_261102_AMD']::text[], 'links'),
  (10062, 'OG1592', '261102', 'hifi1', '261102', ARRAY['OG1592W_D_SBL_PACB_261102_AMD']::text[], 'links'),
  (10064, 'OG1643', '261102', 'hifi1', '261102', ARRAY['OG1643M_D_SBL_PACB_261102_AMD']::text[], 'links'),
  (10066, 'OG1653', '261102', 'hifi1', '261102', ARRAY['OG1653G_D_SBL_PACB_261102_AMD']::text[], 'links'),
  (10068, 'OG1681', '261102', 'hifi1', '261102', ARRAY['OG1681M_D_SBL_PACB_261102_AMD']::text[], 'links'),
  (10070, 'OG2095', '261102', 'hifi1', '261102', ARRAY['OG2095G_D_SBL_PACB_261102_AMD']::text[], 'links'),
  (10072, 'OG2408', '261102', 'hifi1', '261102', ARRAY['OG2408B_D_SBL_PACB_261102_AMD']::text[], 'links'),
  (10078, 'OG2105', '260421', 'hic1', '260421', ARRAY['OG2105G_D_SBL2_PACB_260421_AMD', 'OG2105G_D_SBL_PACB_260421_AMD']::text[], 'kmer'),
  (10088, 'OG2145', '260730', 'hic1', '260730', ARRAY['OG2145G_D_SBL_PACB_260522_AMD', 'OG2145G_D_SBL_PACB_260730_AMD']::text[], 'kmer'),
  (10423, 'OG2119', '260408', 'hic2', '260408', ARRAY['OG2119E_D_SBL_PACB_260408_AMD']::text[], 'kmer_approx')
;

CREATE TEMP TABLE d_link (
    change        text NOT NULL CHECK (change IN ('added', 'removed')),
    assembly_id   bigint NOT NULL,
    sequencing_id text NOT NULL,
    PRIMARY KEY (assembly_id, sequencing_id)
) ON COMMIT DROP;
INSERT INTO d_link (assembly_id, sequencing_id, change)
SELECT v.*, 'added' FROM (VALUES
  (3, 'OG781G_D_SBL_PACB_250317_AD'),
  (34, 'OG819H_D_SBL_PACB_250717_AD'),
  (43, 'OG848U_D_SBL2_PACB_241127_AD'),
  (54, 'OG749H_D_SBL_PACB_241018_LA'),
  (59, 'OG767G_D_SBL_PACB_241004_LA'),
  (73, 'OG866G_D_SBL_PACB_241023_AD'),
  (79, 'OG778H_D_SBL_PACB_241018_LA'),
  (85, 'OG13G_D_SBL_PACB_230209_LP'),
  (88, 'OG845H_D2_SBL_PACB_241018_LA'),
  (91, 'OG6G_D_SBL2_PACB_230628_AD'),
  (92, 'OG762H_D_SBL2_PACB_241018_LA'),
  (94, 'OG750G_D_SBL_PACB_241004_LA'),
  (104, 'OG804G_D_SBL_PACB_250717_AD'),
  (105, 'OG88G_D_SBL_PACB_230724_AD'),
  (108, 'OG759H_D_SBL_PACB_240520_LA'),
  (110, 'OG14G_D_SBL_PACB_230209_LP'),
  (113, 'OG13G_D_SBL_PACB_230209_LP'),
  (114, 'OG683H_D_SBL2_PACB_240821_AD'),
  (114, 'OG683H_D_SBL2_PACB_241023_AD'),
  (118, 'OG701H_D_SBL2_PACB_240427_LA'),
  (125, 'OG61W_D_SBL_PACB_250317_AD'),
  (126, 'OG820G_D_SBL_PACB_240501_AD'),
  (136, 'OG683H_D_SBL2_PACB_240821_AD'),
  (136, 'OG683H_D_SBL2_PACB_241023_AD'),
  (156, 'OG866G_D_SBL_PACB_241023_AD'),
  (164, 'OG2G_D_SBL_PACB_230413_AD'),
  (170, 'OG767G_D_SBL_PACB_241004_LA'),
  (173, 'OG704H_D_SBL2_PACB_240417_LA'),
  (175, 'OG788G_D_SBL_PACB_240927_LA'),
  (177, 'OG2126E_D_SBL_PACB_260511_AMD'),
  (182, 'OG39H_D_SBL_PACB_241018_LA'),
  (190, 'OG73W_D_SBL_PACB_250307_AD'),
  (192, 'OG749H_D_SBL_PACB_241018_LA'),
  (199, 'OG61W_D_SBL_PACB_250317_AD'),
  (210, 'OG5G_D_SBL_PACB_230609_AD'),
  (218, 'OG2145G_D_SBL_PACB_260522_AMD'),
  (229, 'OG113G_D_SBL_PACB_231027_ADLA'),
  (239, 'OG54G_D_SBL_PACB_241004_LA'),
  (241, 'OG637B_D3_SBL2_PACB_240206_AD'),
  (241, 'OG637B_D3_SBL_PACB_240206_AD'),
  (242, 'OG12G_D_SBL_PACB_230512_AD'),
  (259, 'OG6G_D_SBL2_PACB_230628_AD'),
  (266, 'OG637B_D3_SBL2_PACB_240206_AD'),
  (266, 'OG637B_D3_SBL_PACB_240206_AD'),
  (268, 'OG756G_D_SBL_PACB_250717_AD'),
  (270, 'OG64W_D_SBL_PACB_250307_AD'),
  (274, 'OG54G_D_SBL_PACB_241004_LA'),
  (282, 'OG39H_D_SBL_PACB_241018_LA'),
  (285, 'OG756G_D_SBL_PACB_250717_AD'),
  (286, 'OG804G_D_SBL_PACB_250717_AD'),
  (290, 'OG820G_D_SBL_PACB_240501_AD'),
  (293, 'OG104M_D_SBL2_PACB_241127_AD'),
  (300, 'OG95H_D_SBL_PACB_230525_AD'),
  (312, 'OG799H_D2_SBL_PACB_241018_LA'),
  (314, 'OG645H_D_SBL_PACB_240427_LA'),
  (324, 'OG12G_D_SBL_PACB_230512_AD'),
  (331, 'OG657H_D_SBL_PACB_240501_AD'),
  (338, 'OG804G_D_SBL_PACB_250717_AD'),
  (351, 'OG799H_D2_SBL_PACB_241018_LA'),
  (357, 'OG794G_D_SBL_PACB_250307_AD'),
  (363, 'OG16G_D_SBL_PACB_240427_LA'),
  (373, 'OG16G_D_SBL_PACB_240427_LA'),
  (379, 'OG845H_D2_SBL_PACB_241018_LA'),
  (381, 'OG649H_D2_SBL2_PACB_240427_LA'),
  (382, 'OG645H_D_SBL_PACB_240427_LA'),
  (387, 'OG781G_D_SBL_PACB_250317_AD'),
  (395, 'OG657H_D_SBL_PACB_240501_AD'),
  (398, 'OG701H_D_SBL2_PACB_240427_LA'),
  (411, 'OG759H_D_SBL_PACB_240520_LA'),
  (414, 'OG778H_D_SBL_PACB_241018_LA'),
  (419, 'OG113G_D_SBL_PACB_231027_ADLA'),
  (422, 'OG659H_D_SBL2_PACB_240427_LA'),
  (429, 'OG834H_D2_SBL_PACB_240927_LA'),
  (430, 'OG13G_D_SBL_PACB_230209_LP'),
  (433, 'OG64W_D_SBL_PACB_250307_AD'),
  (434, 'OG659H_D_SBL2_PACB_240427_LA'),
  (443, 'OG834H_D2_SBL_PACB_240927_LA'),
  (448, 'OG649H_D2_SBL2_PACB_240427_LA'),
  (449, 'OG88G_D_SBL_PACB_230724_AD'),
  (451, 'OG788G_D_SBL_PACB_240927_LA'),
  (457, 'OG95H_D_SBL_PACB_230525_AD'),
  (458, 'OG762H_D_SBL2_PACB_241018_LA'),
  (9849, 'OG2089G_D_SBL_PACB_260227_AMD'),
  (9852, 'OG2093E_D_SBL_PACB_260227_AMD'),
  (9861, 'OG2126E_D_SBL_PACB_260511_AMD'),
  (9864, 'OG2128E_D_SBL_PACB_260603_AMD'),
  (10088, 'OG2145G_D_SBL_PACB_260522_AMD')
) AS v (assembly_id, sequencing_id)
UNION ALL
SELECT v.*, 'removed' FROM (VALUES
  (11, 'OG836B_D_SBL2_PACB_240520_LA'),
  (59, 'OG767G_D_SBL_PACB_250331_LA'),
  (148, 'OG90H_D2_SBL3_PACB_240821_AD'),
  (170, 'OG767G_D_SBL_PACB_250331_LA'),
  (295, 'OG90H_D2_SBL3_PACB_240821_AD'),
  (315, 'OG836B_D_SBL2_PACB_240520_LA'),
  (357, 'OG794G_D_SBL_PACB_250317_AD')
) AS v (assembly_id, sequencing_id);

-- Backfill (first application only) ---------------------------------------------------------------

DO $backfill$
DECLARE
  bad record;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'ref_assembly' AND column_name = 'read_set_id') THEN
    RAISE NOTICE '093: ref_assembly.read_set_id exists; backfill skipped (replay)';
    RETURN;
  END IF;

  -- The state the data was built from (live, 2026-11-23).
  IF (SELECT count(*) FROM ref_assembly) <> 491 OR (SELECT count(*) FROM ref_read_set) <> 260
     OR (SELECT count(*) FROM ref_read_set_run) <> 282 OR (SELECT count(*) FROM ref_assembly_run) <> 458
     OR (SELECT count(*) FROM ref_hifi_adapter_filter) <> 160
     OR (SELECT count(*) FROM ref_hifi_adapter_filter_run) <> 0 THEN
    RAISE EXCEPTION '093: live is not the state the data was built from (491 assemblies, 260 read sets, '
      '282 read-set runs, 458 assembly runs, 160 adapter rows); rebuild sql/data/093_* first';
  END IF;
  SELECT d.assembly_id INTO bad FROM d_assembly d LEFT JOIN ref_assembly a USING (assembly_id)
   WHERE (a.og_id, a.seq_date, a.version) IS DISTINCT FROM (d.og_id, d.seq_date, d.version) LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION '093: assembly % is not as the data has it', bad.assembly_id;
  END IF;
  IF (SELECT count(*) FROM d_assembly) <> 491 THEN
    RAISE EXCEPTION '093: the data has % assemblies, not 491', (SELECT count(*) FROM d_assembly);
  END IF;
  FOR bad IN
    SELECT d.og_id, d.seq_date FROM d_read_set d
      LEFT JOIN ref_read_set rs ON rs.read_set_id = d.read_set_id
     WHERE d.action = 'correct'
       AND ((rs.og_id, rs.seq_date) IS DISTINCT FROM (d.og_id, d.seq_date)
            OR NOT (d.runs_before @> ARRAY(SELECT sequencing_id FROM ref_read_set_run r WHERE r.read_set_id = d.read_set_id)
                    AND d.runs_before <@ ARRAY(SELECT sequencing_id FROM ref_read_set_run r WHERE r.read_set_id = d.read_set_id)))
    UNION ALL
    SELECT d.og_id, d.seq_date FROM d_read_set d JOIN ref_read_set rs USING (og_id, seq_date) WHERE d.action = 'new'
  LOOP
    RAISE EXCEPTION '093: read set % % is not as the data has it', bad.og_id, bad.seq_date;
  END LOOP;

  INSERT INTO ref_hifi_adapter_filter_run (sequencing_id, contam_reads, source)
  SELECT sequencing_id, contam_reads, source FROM d_adapter;

  INSERT INTO ref_read_set (og_id, seq_date) SELECT og_id, seq_date FROM d_read_set WHERE action = 'new';
  DELETE FROM ref_read_set_run r USING d_read_set d
   WHERE d.action = 'correct' AND r.read_set_id = d.read_set_id AND r.sequencing_id <> ALL (d.runs_after);
  INSERT INTO ref_read_set_run (read_set_id, sequencing_id)
  SELECT rs.read_set_id, unnest(d.runs_after) FROM d_read_set d JOIN ref_read_set rs USING (og_id, seq_date)
  ON CONFLICT DO NOTHING;

  ALTER TABLE ref_assembly ADD COLUMN read_set_id bigint REFERENCES ref_read_set (read_set_id);
  UPDATE ref_assembly a SET read_set_id = rs.read_set_id
    FROM d_assembly d JOIN ref_read_set rs ON rs.og_id = d.og_id AND rs.seq_date = d.read_set_date
   WHERE a.assembly_id = d.assembly_id;

  -- Each assembly's read set has the runs the evidence gave it.
  SELECT d.assembly_id, d.og_id, d.seq_date, d.version INTO bad
    FROM d_assembly d JOIN ref_assembly a USING (assembly_id)
   WHERE a.read_set_id IS NULL
      OR NOT (d.runs @> ARRAY(SELECT sequencing_id FROM ref_read_set_run r WHERE r.read_set_id = a.read_set_id)
              AND d.runs <@ ARRAY(SELECT sequencing_id FROM ref_read_set_run r WHERE r.read_set_id = a.read_set_id))
   LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION '093: assembly % (% %.%) did not get the read set the data gives it',
      bad.assembly_id, bad.og_id, bad.seq_date, bad.version;
  END IF;
  ALTER TABLE ref_assembly ALTER COLUMN read_set_id SET NOT NULL;

  CREATE TEMP TABLE d_links_before ON COMMIT DROP AS SELECT assembly_id, sequencing_id FROM ref_assembly_run;
  RAISE NOTICE '093: % per-run HiFiAdapterFilt rows, % new and % corrected read sets, read sets for % assemblies',
    (SELECT count(*) FROM ref_hifi_adapter_filter_run), (SELECT count(*) FROM d_read_set WHERE action = 'new'),
    (SELECT count(*) FROM d_read_set WHERE action = 'correct'), (SELECT count(*) FROM ref_assembly WHERE read_set_id IS NOT NULL);
END
$backfill$;

CREATE INDEX IF NOT EXISTS ref_assembly_read_set_id_idx ON public.ref_assembly (read_set_id);

-- Run links from the read set ----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.refresh_assembly_runs(p_og_ids text[],
                                                        p_sequencing_ids text[] DEFAULT '{}')
RETURNS void
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  -- Mito: every link is derived, so drop one the rule no longer gives (080, unchanged).
  DELETE FROM mito_assembly_run r
   USING mito_assembly a
   WHERE a.assembly_id = r.assembly_id
     AND (a.og_id = ANY (p_og_ids) OR r.sequencing_id = ANY (p_sequencing_ids))
     AND NOT EXISTS (SELECT 1 FROM v_sequencing_browse s
                      WHERE s.sequencing_id = r.sequencing_id
                        AND s.og_id = a.og_id AND s.seq_date = a.seq_date
                        AND mito_run_matches(a.tech, s.technology, s.library_type, s.instrument));

  INSERT INTO mito_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT a.assembly_id, s.sequencing_id
    FROM mito_assembly a
    JOIN v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
   WHERE a.og_id = ANY (p_og_ids)
     AND mito_run_matches(a.tech, s.technology, s.library_type, s.instrument)
  ON CONFLICT DO NOTHING;

  -- Ref: drop a link its row can no longer have (another OG, not PacBio/ONT/Hi-C DNA, failed: what
  -- ref_assembly_run_genomic_only refuses), and a PacBio link that is not a run of the assembly's
  -- read set (093). ONT and Hi-C links chosen by hand stay.
  DELETE FROM ref_assembly_run r
   USING ref_assembly a
   WHERE a.assembly_id = r.assembly_id
     AND (a.og_id = ANY (p_og_ids) OR r.sequencing_id = ANY (p_sequencing_ids))
     AND (NOT EXISTS (SELECT 1 FROM v_sequencing_browse s
                       WHERE s.sequencing_id = r.sequencing_id AND s.og_id = a.og_id
                         AND s.technology IN ('PacBio HIFI', 'PacBio', 'ONT', 'Hi-C')
                         AND s.library_type IN ('pacbio', 'ont', 'hic')
                         AND s.status IS DISTINCT FROM 'Failed')
          OR (EXISTS (SELECT 1 FROM v_sequencing_browse s
                       WHERE s.sequencing_id = r.sequencing_id
                         AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio')
              AND NOT EXISTS (SELECT 1 FROM ref_read_set_run rr
                               WHERE rr.read_set_id = a.read_set_id AND rr.sequencing_id = r.sequencing_id)));

  -- PacBio: the read set's runs (093). A failed run produced no reads to build from (069).
  INSERT INTO ref_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT a.assembly_id, rr.sequencing_id
    FROM ref_assembly a
    JOIN ref_read_set_run rr ON rr.read_set_id = a.read_set_id
    JOIN v_sequencing_browse s ON s.sequencing_id = rr.sequencing_id AND s.og_id = a.og_id
   WHERE (a.og_id = ANY (p_og_ids) OR rr.sequencing_id = ANY (p_sequencing_ids))
     AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio'
     AND s.status IS DISTINCT FROM 'Failed'
  ON CONFLICT DO NOTHING;

  -- ONT: the OG's non-failed ONT DNA rows of the assembly's seq_date (080's rule).
  INSERT INTO ref_assembly_run (assembly_id, sequencing_id)
  SELECT DISTINCT a.assembly_id, s.sequencing_id
    FROM ref_assembly a
    JOIN v_sequencing_browse s ON s.og_id = a.og_id AND s.seq_date = a.seq_date
   WHERE a.og_id = ANY (p_og_ids)
     AND s.technology = 'ONT' AND s.library_type = 'ont'
     AND s.status IS DISTINCT FROM 'Failed'
  ON CONFLICT DO NOTHING;
END
$fn$;
COMMENT ON FUNCTION public.refresh_assembly_runs(text[], text[]) IS
  'Re-derive mito_assembly_run and ref_assembly_run for the assemblies of the OGs given and the links '
  'of the sequencing rows given. Mito: the rule of v3.sync_mito() (055); a link it no longer gives is '
  'removed. Ref: PacBio links are the runs of the assembly''s read set (093); ONT links the OG''s '
  'non-failed ONT rows of its seq_date (069); a link its row can no longer have is removed, and Hi-C '
  'links chosen by hand stay. Called by triggers on mito_assembly, ref_assembly, ref_read_set_run, '
  'sequencing and library. 080, 093.';

CREATE OR REPLACE FUNCTION public.ref_assembly_runs_link() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
  -- The ref writers' upsert sets og_id = EXCLUDED.og_id on every push; that changes nothing.
  IF TG_OP = 'INSERT'
     OR (NEW.og_id, NEW.seq_date, NEW.read_set_id) IS DISTINCT FROM (OLD.og_id, OLD.seq_date, OLD.read_set_id) THEN
    PERFORM refresh_assembly_runs(ARRAY[NEW.og_id]);
  END IF;
  RETURN NULL;
END
$fn$;
COMMENT ON FUNCTION public.ref_assembly_runs_link() IS
  'Links a new, re-keyed or re-read-set reference assembly to its runs (refresh_assembly_runs). 080, 093.';
DROP TRIGGER IF EXISTS ref_assembly_runs_link ON ref_assembly;
CREATE TRIGGER ref_assembly_runs_link AFTER INSERT OR UPDATE OF og_id, seq_date, read_set_id ON ref_assembly
  FOR EACH ROW EXECUTE FUNCTION ref_assembly_runs_link();

CREATE OR REPLACE FUNCTION public.ref_read_set_run_assembly_runs() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
DECLARE
  ids bigint[];
BEGIN
  ids := CASE TG_OP WHEN 'INSERT' THEN ARRAY[NEW.read_set_id]
                    WHEN 'DELETE' THEN ARRAY[OLD.read_set_id]
                    ELSE ARRAY[NEW.read_set_id, OLD.read_set_id] END;
  PERFORM refresh_assembly_runs(ARRAY(SELECT DISTINCT og_id FROM ref_assembly WHERE read_set_id = ANY (ids)));
  RETURN NULL;
END
$fn$;
COMMENT ON FUNCTION public.ref_read_set_run_assembly_runs() IS
  'A run added to or removed from a read set is added to or removed from the PacBio links of the '
  'assemblies built from it (refresh_assembly_runs). 093.';
DROP TRIGGER IF EXISTS ref_read_set_run_assembly_runs ON ref_read_set_run;
CREATE TRIGGER ref_read_set_run_assembly_runs AFTER INSERT OR UPDATE OR DELETE ON ref_read_set_run
  FOR EACH ROW EXECUTE FUNCTION ref_read_set_run_assembly_runs();

-- A new assembly's read set ------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ref_assembly_read_set_default() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
DECLARE
  k   text;
  ids text[];
  rid bigint;
BEGIN
  IF NEW.read_set_id IS NOT NULL THEN
    RETURN NEW;
  END IF;
  -- A re-push (INSERT ... ON CONFLICT DO UPDATE) keeps the assembly's own read set.
  SELECT a.read_set_id INTO rid FROM ref_assembly a
   WHERE a.og_id = NEW.og_id AND a.seq_date = NEW.seq_date AND a.version = NEW.version;
  IF rid IS NULL THEN
    -- refdb.read_set_runs(): the OG's non-failed PacBio DNA rows up to the date + 21 days, keyed by
    -- their latest seq_date (the date itself when there are none).
    SELECT coalesce(max(s.seq_date), NEW.seq_date), coalesce(array_agg(s.sequencing_id), '{}')
      INTO k, ids
      FROM v_sequencing_browse s
     WHERE s.og_id = NEW.og_id AND s.technology IN ('PacBio HIFI', 'PacBio') AND s.library_type = 'pacbio'
       AND s.status IS DISTINCT FROM 'Failed' AND s.seq_date ~ '^[0-9]{6}$'
       AND to_date(s.seq_date, 'YYMMDD') <= to_date(NEW.seq_date, 'YYMMDD') + 21;
    SELECT rs.read_set_id INTO rid FROM ref_read_set rs
     WHERE rs.og_id = NEW.og_id AND coalesce(rs.seq_date, '') = k;
    IF rid IS NULL THEN
      INSERT INTO ref_read_set (og_id, seq_date) VALUES (NEW.og_id, k) RETURNING read_set_id INTO rid;
      INSERT INTO ref_read_set_run (read_set_id, sequencing_id) SELECT rid, unnest(ids);
    END IF;
  END IF;
  NEW.read_set_id := rid;
  RETURN NEW;
END
$fn$;
COMMENT ON FUNCTION public.ref_assembly_read_set_default() IS
  'BEFORE INSERT on ref_assembly: a row without read_set_id takes that of the assembly with its key '
  '(a re-push), else the read set refdb.read_set_runs() gives for its date (the OG''s non-failed PacBio '
  'DNA runs up to the date + 21 days, keyed by their latest seq_date), created with those runs if '
  'missing. An existing read set''s runs are not changed. 093.';
DROP TRIGGER IF EXISTS ref_assembly_read_set_default ON ref_assembly;
CREATE TRIGGER ref_assembly_read_set_default BEFORE INSERT ON ref_assembly
  FOR EACH ROW EXECUTE FUNCTION ref_assembly_read_set_default();

-- What is still missing ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.v_ref_read_set_readiness AS
 WITH used AS (
         SELECT a.read_set_id,
            string_agg(a.seq_date || '.' || a.version, ', ' ORDER BY a.seq_date, a.version) AS assemblies
           FROM ref_assembly a
          GROUP BY a.read_set_id
        ), runs AS (
         SELECT r.read_set_id,
            count(*) AS n_runs,
            count(f.sequencing_id) AS n_counted,
            sum(f.contam_reads) AS contam_reads,
            string_agg(r.sequencing_id, ', ' ORDER BY r.sequencing_id) FILTER (WHERE f.sequencing_id IS NULL) AS uncounted
           FROM ref_read_set_run r
             LEFT JOIN ref_hifi_adapter_filter_run f USING (sequencing_id)
          GROUP BY r.read_set_id
        )
 SELECT rs.og_id,
    rs.seq_date,
    rs.read_set_id,
    i.issue,
    i.detail,
    u.assemblies
   FROM ref_read_set rs
     LEFT JOIN used u USING (read_set_id)
     LEFT JOIN runs n USING (read_set_id)
     LEFT JOIN ref_hifi_adapter_filter h USING (read_set_id)
     CROSS JOIN LATERAL (VALUES
        ('no GenomeScope'::text, NULL::text,
         u.read_set_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM ref_genomescope g WHERE g.read_set_id = rs.read_set_id)),
        ('no runs', NULL,
         n.read_set_id IS NULL
           AND NOT EXISTS (SELECT 1 FROM ref_read_set_external x WHERE x.read_set_id = rs.read_set_id)),
        ('runs without a HiFiAdapterFilt count', n.uncounted, n.uncounted IS NOT NULL),
        ('HiFiAdapterFilt total differs from its runs',
         format('ref_hifi_adapter_filter %s, ref_hifi_adapter_filter_run sum %s', h.contam_reads, n.contam_reads),
         h.contam_reads IS NOT NULL AND n.n_runs = n.n_counted AND h.contam_reads <> n.contam_reads),
        ('used by no assembly', NULL, u.read_set_id IS NULL)
     ) AS i(issue, detail, applies)
  WHERE i.applies;

-- Comments -----------------------------------------------------------------------------------------

COMMENT ON TABLE public.ref_hifi_adapter_filter_run IS
  'HiFiAdapterFilt per PacBio sequencing row: reads removed as adapter-contaminated, summed over the '
  'row''s cells (one .stats per cell BAM). A read set''s figure is the sum over its runs. Backfilled '
  'from the Acacia .stats files and the read-set totals (093, sql/data/093_adapter_filter_run.tsv); '
  'no writer yet (the push writes ref_hifi_adapter_filter).';
COMMENT ON COLUMN public.ref_hifi_adapter_filter_run.sequencing_id IS 'The PacBio DNA sequencing row (FK to sequencing; trigger).';
COMMENT ON COLUMN public.ref_hifi_adapter_filter_run.contam_reads IS
  'HiFi reads HiFiAdapterFilt removed as adapter-contaminated, over the row''s cells.';
COMMENT ON COLUMN public.ref_hifi_adapter_filter_run.source IS
  'Where the count came from: acacia (the .stats files), single_run or zero_total (a read-set total '
  'that fixes it), with the detail.';
COMMENT ON COLUMN public.ref_hifi_adapter_filter_run.loaded_at IS 'When the row was written.';
COMMENT ON TABLE public.ref_hifi_adapter_filter IS
  'HiFiAdapterFilt: reads removed as adapter-contaminated, per HiFi read set (ref_read_set), as the '
  'push writes it (0a_push_hifiadapt_results_to_sqldb.py, ref repo). The per-run counts are in '
  'ref_hifi_adapter_filter_run; v_ref_read_set_readiness lists totals that differ from their sum. '
  'To become a view over ref_hifi_adapter_filter_run once the push writes per run (093).';
COMMENT ON TABLE public.ref_read_set IS
  'A HiFi read set: the PacBio reads one reference-pipeline run took in for an OG. Every assembly has '
  'one (ref_assembly.read_set_id, 093), and its GenomeScope (ref_genomescope) is of these reads. '
  'seq_date is the latest seq_date of its sequencing rows, or the assembly''s or samplesheet''s date '
  'when it has none. Migrations 062, 093.';
COMMENT ON COLUMN public.ref_assembly.read_set_id IS
  'The HiFi read set the assembly was built from (FK to ref_read_set); its runs are the assembly''s '
  'PacBio links in ref_assembly_run. Backfilled from merqury k-mer totals where Acacia has them '
  '(093, sql/data/093_assembly_read_set.tsv); a new assembly gets one from '
  'ref_assembly_read_set_default().';
COMMENT ON TABLE public.ref_assembly_run IS
  'The sequencing rows an assembly was built from: PacBio (the runs of its read set, 093), ONT (the '
  'OG''s non-failed ONT rows of its seq_date) and Hi-C (by hand, until writers record it). Kept current '
  'by refresh_assembly_runs() from triggers on ref_assembly, ref_read_set_run, sequencing and library '
  '(080, 093).';
COMMENT ON VIEW public.v_ref_read_set_readiness IS
  'Read sets with something missing or inconsistent: an assembly''s read set with no GenomeScope, no '
  'runs (not external), runs without a per-run HiFiAdapterFilt count, a stored total that differs from '
  'the per-run sum, or used by no assembly. assemblies lists the assemblies built from it. 093.';
COMMENT ON VIEW public.v_ref_assembly_run_readiness IS
  'Assemblies with no run link, and the OG''s PacBio/ONT DNA rows to choose from: their read set has '
  'no runs (v_ref_read_set_readiness) and no ONT row has their seq_date. Give the read set its runs, '
  'or fix the date (080, 093).';

-- Links, checks and probes -------------------------------------------------------------------------

DO $check$
DECLARE
  n     bigint;
  added bigint;
  gone  bigint;
  src   record;
  rid   bigint;
  before_rs bigint;
BEGIN
  PERFORM refresh_assembly_runs(ARRAY(SELECT og_id FROM sample));

  -- Every assembly's PacBio links are its read set's runs.
  SELECT count(*) INTO n
    FROM ref_assembly a
   WHERE NOT (ARRAY(SELECT r.sequencing_id FROM ref_assembly_run r JOIN sequencing s USING (sequencing_id)
                     WHERE r.assembly_id = a.assembly_id AND s.technology IN ('PacBio HIFI', 'PacBio'))
              @> ARRAY(SELECT rr.sequencing_id FROM ref_read_set_run rr WHERE rr.read_set_id = a.read_set_id)
          AND ARRAY(SELECT r.sequencing_id FROM ref_assembly_run r JOIN sequencing s USING (sequencing_id)
                     WHERE r.assembly_id = a.assembly_id AND s.technology IN ('PacBio HIFI', 'PacBio'))
              <@ ARRAY(SELECT rr.sequencing_id FROM ref_read_set_run rr WHERE rr.read_set_id = a.read_set_id));
  IF n > 0 THEN
    RAISE EXCEPTION '093: % assemblies'' PacBio links are not their read set''s runs', n;
  END IF;

  -- On the first application, exactly the links the data expects changed.
  IF to_regclass('pg_temp.d_links_before') IS NOT NULL THEN
    SELECT count(*) INTO added FROM (
      SELECT assembly_id, sequencing_id FROM ref_assembly_run EXCEPT SELECT * FROM d_links_before
      EXCEPT SELECT assembly_id, sequencing_id FROM d_link WHERE change = 'added') x;
    SELECT count(*) INTO gone FROM (
      SELECT * FROM d_links_before EXCEPT SELECT assembly_id, sequencing_id FROM ref_assembly_run
      EXCEPT SELECT assembly_id, sequencing_id FROM d_link WHERE change = 'removed') x;
    SELECT count(*) INTO n FROM d_link l
     WHERE (l.change = 'added') = NOT EXISTS (SELECT 1 FROM ref_assembly_run r
                                               WHERE r.assembly_id = l.assembly_id AND r.sequencing_id = l.sequencing_id);
    IF added + gone + n > 0 THEN
      RAISE EXCEPTION '093: run links changed other than the data says (% unexpected added, % unexpected removed, % expected not done)',
        added, gone, n;
    END IF;
    RAISE NOTICE '093: run links % -> % (% added, % removed)', (SELECT count(*) FROM d_links_before),
      (SELECT count(*) FROM ref_assembly_run), (SELECT count(*) FROM d_link WHERE change = 'added'),
      (SELECT count(*) FROM d_link WHERE change = 'removed');
  END IF;

  -- Stored read-set totals equal their per-run sums wherever every run is counted, but OG57.
  SELECT count(*) INTO n FROM v_ref_read_set_readiness
   WHERE issue = 'HiFiAdapterFilt total differs from its runs' AND og_id <> 'OG57';
  IF n > 0 THEN
    RAISE EXCEPTION '093: % read-set HiFiAdapterFilt totals differ from their runs', n;
  END IF;

  -- Probes, inside a sub-block that is always rolled back.
  BEGIN
    before_rs := (SELECT count(*) FROM ref_read_set);
    -- 1. A re-push of an existing assembly keeps its read set and creates none (OG767 v250331: the
    --    k-mers say 241004 only; the date rule would give 241004 + 250331).
    SELECT a.assembly_id, a.og_id, a.seq_date, a.version, a.read_set_id INTO src
      FROM ref_assembly a WHERE a.og_id = 'OG767' AND a.seq_date = '250331' AND a.version = 'hic1';
    INSERT INTO ref_assembly (og_id, seq_date, version) VALUES (src.og_id, src.seq_date, src.version)
      ON CONFLICT (og_id, seq_date, version) DO UPDATE SET og_id = EXCLUDED.og_id;
    IF (SELECT read_set_id FROM ref_assembly WHERE assembly_id = src.assembly_id) <> src.read_set_id
       OR (SELECT count(*) FROM ref_read_set) <> before_rs THEN
      RAISE EXCEPTION '093 probe 1: a re-push changed the read set';
    END IF;
    -- 2. A new assembly takes the date rule's read set (OG2126 260730: 260511 + 260730, existing).
    INSERT INTO ref_assembly (og_id, seq_date, version) VALUES ('OG2126', '260730', 'hifi9')
      RETURNING read_set_id INTO rid;
    IF rid IS DISTINCT FROM (SELECT read_set_id FROM ref_read_set WHERE og_id = 'OG2126' AND seq_date = '260730')
       OR (SELECT count(*) FROM ref_assembly_run r JOIN ref_assembly a USING (assembly_id)
            WHERE a.og_id = 'OG2126' AND a.version = 'hifi9') <> 2 THEN
      RAISE EXCEPTION '093 probe 2: a new assembly did not get the date rule''s read set and its 2 runs';
    END IF;
    -- 3. A new assembly whose read set does not exist creates it, with no runs for an OG with none.
    SELECT s.og_id INTO src FROM sample s
     WHERE s.og_id ~ '^OG[0-9]+$'
       AND NOT EXISTS (SELECT 1 FROM v_sequencing_browse q WHERE q.og_id = s.og_id AND q.library_type = 'pacbio')
       AND NOT EXISTS (SELECT 1 FROM ref_read_set rs WHERE rs.og_id = s.og_id)
     ORDER BY s.og_id LIMIT 1;
    INSERT INTO ref_assembly (og_id, seq_date, version) VALUES (src.og_id, '991231', 'hifi1')
      RETURNING read_set_id INTO rid;
    IF NOT EXISTS (SELECT 1 FROM ref_read_set WHERE read_set_id = rid AND og_id = src.og_id AND seq_date = '991231')
       OR EXISTS (SELECT 1 FROM ref_read_set_run WHERE read_set_id = rid) THEN
      RAISE EXCEPTION '093 probe 3: no new empty read set for %', src.og_id;
    END IF;
    -- 4. A run added to a read set reaches its assemblies' links, and leaves with it (OG838 240813).
    rid := (SELECT read_set_id FROM ref_read_set WHERE og_id = 'OG838' AND seq_date = '240813');
    INSERT INTO ref_read_set_run VALUES (rid, 'OG838B_D_SBL_PACB_240520_LA');
    IF (SELECT count(*) FROM ref_assembly_run r JOIN ref_assembly a USING (assembly_id)
         WHERE a.read_set_id = rid AND r.sequencing_id = 'OG838B_D_SBL_PACB_240520_LA')
       <> (SELECT count(*) FROM ref_assembly WHERE read_set_id = rid) THEN
      RAISE EXCEPTION '093 probe 4: an added read-set run did not reach the assemblies';
    END IF;
    DELETE FROM ref_read_set_run WHERE read_set_id = rid AND sequencing_id = 'OG838B_D_SBL_PACB_240520_LA';
    IF EXISTS (SELECT 1 FROM ref_assembly_run r JOIN ref_assembly a USING (assembly_id)
                WHERE a.read_set_id = rid AND r.sequencing_id = 'OG838B_D_SBL_PACB_240520_LA') THEN
      RAISE EXCEPTION '093 probe 4: a removed read-set run stayed linked';
    END IF;
    -- 5. A read set an assembly uses cannot be deleted.
    BEGIN
      DELETE FROM ref_read_set WHERE read_set_id = rid;
      RAISE EXCEPTION '093 probe 5: a used read set was deleted';
    EXCEPTION WHEN foreign_key_violation THEN
      NULL;
    END;
    RAISE EXCEPTION 'probe093';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'probe093' THEN
      RAISE;
    END IF;
  END;
  RAISE NOTICE '093: checks and probes passed';
END
$check$;

COMMIT;
