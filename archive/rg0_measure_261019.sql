\pset footer off
\echo '## A counts'
select now()::timestamp(0) as measured_utc,(select count(*) from ref_genomes) ref_genomes,(select count(distinct og_id) from ref_genomes) ogs,(select count(distinct (og_id,seq_date,version)) from ref_genomes) assemblies,(select count(distinct (og_id,seq_date,version,stage,haplotype)) from ref_genomes) parts,(select count(*) from raw_qc) raw_qc,(select count(*) from hifi_reads_qc) hifi_reads_qc,(select count(*) from hic_reads_qc) hic_reads_qc,(select count(*) from ref_genomes_assembly_uploads) asm_uploads,(select count(*) from ref_genomes_sra_uploads) sra_uploads;
\echo '## B empty cells'
select sum((select count(*) from jsonb_each(to_jsonb(r) - array['og_id','seq_date','stage','haplotype','version']) e where e.value = 'null'::jsonb))::bigint empty_cells, count(*)*53 cells from ref_genomes r;
\echo '## C rows per tool (= v4 tool-table row counts)'
with f as (select *,
 num_nonnulls(num_contigs,contig_n50,contig_n50_size_mb,num_scaffolds,scaffold_n50,scaffold_n50_size_mb,largest_scaffold,largest_scaffold_size_mb,total_scaffold_length,total_scaffold_length_size_mb,gc_content_percent)>0 as gfa,
 num_nonnulls(dataset,complete,single_copy,multi_copy,fragmented,missing,n_markers,internal_stop_codon_percent,scaffold_n50_bus,contigs_n50_bus,percent_gaps,number_of_scaffolds)>0 as busco,
 num_nonnulls(unique_k_mers_assembly,k_mers_total,qv,error)>0 as mqv,
 num_nonnulls(k_mer_set,solid_k_mers,total_k_mers,completeness)>0 as mcomp,
 num_nonnulls(total,total_unmapped,total_single_sided_mapped,total_mapped,total_dups,total_nodups,cis,trans)>0 as omnic,
 num_nonnulls(format,type,num_seqs,sum_len,min_len,avg_len,max_len)>0 as seqkit,
 num_nonnulls(num_chromosomes,pct_assigned,pct_no_super,num_seq_no_super,max_len_no_super)>0 as chrom,
 num_gaps is not null as gaps, hap2_chr_level_max_len is not null as h2
 from ref_genomes) select count(*) filter (where gfa or gaps) ref_gfastats, count(*) filter (where gfa and not gaps) gfa_no_gaps, count(*) filter (where gaps and not gfa) gaps_no_gfa, count(*) filter (where busco) ref_busco, count(*) filter (where mqv) ref_merqury_qv, count(*) filter (where mcomp) ref_merqury_completeness, count(*) filter (where omnic) ref_omnic, count(*) filter (where seqkit) ref_seqkit_stats, count(*) filter (where chrom) ref_chromosome_stats, count(*) filter (where h2) hap2_chr_level, count(*) filter (where not (gfa or busco or mqv or mcomp or omnic or seqkit or chrom or gaps or h2)) all_empty from f;
\echo '## D fill patterns'
with f as (select *,
 num_nonnulls(num_contigs,contig_n50,contig_n50_size_mb,num_scaffolds,scaffold_n50,scaffold_n50_size_mb,largest_scaffold,largest_scaffold_size_mb,total_scaffold_length,total_scaffold_length_size_mb,gc_content_percent)>0 as gfa,
 num_nonnulls(dataset,complete,single_copy,multi_copy,fragmented,missing,n_markers,internal_stop_codon_percent,scaffold_n50_bus,contigs_n50_bus,percent_gaps,number_of_scaffolds)>0 as busco,
 num_nonnulls(unique_k_mers_assembly,k_mers_total,qv,error)>0 as mqv,
 num_nonnulls(k_mer_set,solid_k_mers,total_k_mers,completeness)>0 as mcomp,
 num_nonnulls(total,total_unmapped,total_single_sided_mapped,total_mapped,total_dups,total_nodups,cis,trans)>0 as omnic,
 num_nonnulls(format,type,num_seqs,sum_len,min_len,avg_len,max_len)>0 as seqkit,
 num_nonnulls(num_chromosomes,pct_assigned,pct_no_super,num_seq_no_super,max_len_no_super)>0 as chrom,
 num_gaps is not null as gaps, hap2_chr_level_max_len is not null as h2
 from ref_genomes) select count(distinct (gfa,busco,mqv,mcomp,omnic,seqkit,chrom,gaps)) patterns from f;
\echo '## E tools by haplotype (dual rows)'
with f as (select *,
 num_nonnulls(num_contigs,contig_n50,contig_n50_size_mb,num_scaffolds,scaffold_n50,scaffold_n50_size_mb,largest_scaffold,largest_scaffold_size_mb,total_scaffold_length,total_scaffold_length_size_mb,gc_content_percent)>0 as gfa,
 num_nonnulls(dataset,complete,single_copy,multi_copy,fragmented,missing,n_markers,internal_stop_codon_percent,scaffold_n50_bus,contigs_n50_bus,percent_gaps,number_of_scaffolds)>0 as busco,
 num_nonnulls(unique_k_mers_assembly,k_mers_total,qv,error)>0 as mqv,
 num_nonnulls(k_mer_set,solid_k_mers,total_k_mers,completeness)>0 as mcomp,
 num_nonnulls(total,total_unmapped,total_single_sided_mapped,total_mapped,total_dups,total_nodups,cis,trans)>0 as omnic,
 num_nonnulls(format,type,num_seqs,sum_len,min_len,avg_len,max_len)>0 as seqkit,
 num_nonnulls(num_chromosomes,pct_assigned,pct_no_super,num_seq_no_super,max_len_no_super)>0 as chrom,
 num_gaps is not null as gaps, hap2_chr_level_max_len is not null as h2
 from ref_genomes) select haplotype, count(*) n, count(*) filter (where gfa) gfa, count(*) filter (where busco) busco, count(*) filter (where mqv) mqv, count(*) filter (where mcomp) mcomp, count(*) filter (where omnic) omnic, count(*) filter (where seqkit) seqkit, count(*) filter (where chrom) chrom from f group by 1 order by 1;
\echo '## F key domains'
select 'version' k, version v, count(*) from ref_genomes group by 2 union all select 'haplotype', haplotype, count(*) from ref_genomes group by 2 union all select 'stage', stage::text, count(*) from ref_genomes group by 2 union all select 'seq_date not 6 digits', seq_date, count(*) from ref_genomes where seq_date !~ '^[0-9]{6}$' group by 2 order by 1,2;
\echo '## G oddities: rows, tools filled, and the OGs other assemblies'
with f as (select *,
 num_nonnulls(num_contigs,contig_n50,contig_n50_size_mb,num_scaffolds,scaffold_n50,scaffold_n50_size_mb,largest_scaffold,largest_scaffold_size_mb,total_scaffold_length,total_scaffold_length_size_mb,gc_content_percent)>0 as gfa,
 num_nonnulls(dataset,complete,single_copy,multi_copy,fragmented,missing,n_markers,internal_stop_codon_percent,scaffold_n50_bus,contigs_n50_bus,percent_gaps,number_of_scaffolds)>0 as busco,
 num_nonnulls(unique_k_mers_assembly,k_mers_total,qv,error)>0 as mqv,
 num_nonnulls(k_mer_set,solid_k_mers,total_k_mers,completeness)>0 as mcomp,
 num_nonnulls(total,total_unmapped,total_single_sided_mapped,total_mapped,total_dups,total_nodups,cis,trans)>0 as omnic,
 num_nonnulls(format,type,num_seqs,sum_len,min_len,avg_len,max_len)>0 as seqkit,
 num_nonnulls(num_chromosomes,pct_assigned,pct_no_super,num_seq_no_super,max_len_no_super)>0 as chrom,
 num_gaps is not null as gaps, hap2_chr_level_max_len is not null as h2
 from ref_genomes) select og_id, seq_date, version, stage, haplotype, gfa,busco,mqv,mcomp,omnic,seqkit,chrom from f where version !~ '^(hic|hifi|ont)[0-9]+$' or seq_date !~ '^[0-9]{6}$' order by 1,2,3,4,5;
select og_id, seq_date, version, string_agg(distinct stage::text, ',') stages, count(*) from ref_genomes where og_id in ('OG108','OG820','OG906') group by 1,2,3 order by 1,2,3;
\echo '## H orphans (og_id not in sample) and likely parents'
with f as (select *,
 num_nonnulls(num_contigs,contig_n50,contig_n50_size_mb,num_scaffolds,scaffold_n50,scaffold_n50_size_mb,largest_scaffold,largest_scaffold_size_mb,total_scaffold_length,total_scaffold_length_size_mb,gc_content_percent)>0 as gfa,
 num_nonnulls(dataset,complete,single_copy,multi_copy,fragmented,missing,n_markers,internal_stop_codon_percent,scaffold_n50_bus,contigs_n50_bus,percent_gaps,number_of_scaffolds)>0 as busco,
 num_nonnulls(unique_k_mers_assembly,k_mers_total,qv,error)>0 as mqv,
 num_nonnulls(k_mer_set,solid_k_mers,total_k_mers,completeness)>0 as mcomp,
 num_nonnulls(total,total_unmapped,total_single_sided_mapped,total_mapped,total_dups,total_nodups,cis,trans)>0 as omnic,
 num_nonnulls(format,type,num_seqs,sum_len,min_len,avg_len,max_len)>0 as seqkit,
 num_nonnulls(num_chromosomes,pct_assigned,pct_no_super,num_seq_no_super,max_len_no_super)>0 as chrom,
 num_gaps is not null as gaps, hap2_chr_level_max_len is not null as h2
 from ref_genomes) select 'ref_genomes' t, og_id, seq_date, version, stage, haplotype, gfa,busco,mqv,mcomp,omnic from f where not exists (select 1 from sample s where s.og_id=f.og_id) order by 2,3,4,5,6;
select 'raw_qc' t, r.*, exists (select 1 from raw_qc q where q.og_id = substring(r.og_id from '^OG[0-9]+')) parent_has_raw_qc from raw_qc r where not exists (select 1 from sample s where s.og_id=r.og_id);
select og_id, seq_date, version, count(*) from ref_genomes where og_id in ('OG88','OG90') group by 1,2,3 order by 1,2,3;
\echo '## I all-empty row'
with f as (select *,
 num_nonnulls(num_contigs,contig_n50,contig_n50_size_mb,num_scaffolds,scaffold_n50,scaffold_n50_size_mb,largest_scaffold,largest_scaffold_size_mb,total_scaffold_length,total_scaffold_length_size_mb,gc_content_percent)>0 as gfa,
 num_nonnulls(dataset,complete,single_copy,multi_copy,fragmented,missing,n_markers,internal_stop_codon_percent,scaffold_n50_bus,contigs_n50_bus,percent_gaps,number_of_scaffolds)>0 as busco,
 num_nonnulls(unique_k_mers_assembly,k_mers_total,qv,error)>0 as mqv,
 num_nonnulls(k_mer_set,solid_k_mers,total_k_mers,completeness)>0 as mcomp,
 num_nonnulls(total,total_unmapped,total_single_sided_mapped,total_mapped,total_dups,total_nodups,cis,trans)>0 as omnic,
 num_nonnulls(format,type,num_seqs,sum_len,min_len,avg_len,max_len)>0 as seqkit,
 num_nonnulls(num_chromosomes,pct_assigned,pct_no_super,num_seq_no_super,max_len_no_super)>0 as chrom,
 num_gaps is not null as gaps, hap2_chr_level_max_len is not null as h2
 from ref_genomes) select og_id, seq_date, version, stage, haplotype from f where not (gfa or busco or mqv or mcomp or omnic or seqkit or chrom or gaps or h2);
\echo '## J hifi1 rows carrying OMNIC'
with f as (select *,
 num_nonnulls(num_contigs,contig_n50,contig_n50_size_mb,num_scaffolds,scaffold_n50,scaffold_n50_size_mb,largest_scaffold,largest_scaffold_size_mb,total_scaffold_length,total_scaffold_length_size_mb,gc_content_percent)>0 as gfa,
 num_nonnulls(dataset,complete,single_copy,multi_copy,fragmented,missing,n_markers,internal_stop_codon_percent,scaffold_n50_bus,contigs_n50_bus,percent_gaps,number_of_scaffolds)>0 as busco,
 num_nonnulls(unique_k_mers_assembly,k_mers_total,qv,error)>0 as mqv,
 num_nonnulls(k_mer_set,solid_k_mers,total_k_mers,completeness)>0 as mcomp,
 num_nonnulls(total,total_unmapped,total_single_sided_mapped,total_mapped,total_dups,total_nodups,cis,trans)>0 as omnic,
 num_nonnulls(format,type,num_seqs,sum_len,min_len,avg_len,max_len)>0 as seqkit,
 num_nonnulls(num_chromosomes,pct_assigned,pct_no_super,num_seq_no_super,max_len_no_super)>0 as chrom,
 num_gaps is not null as gaps, hap2_chr_level_max_len is not null as h2
 from ref_genomes) select f.og_id, f.seq_date, f.stage, f.haplotype, (select string_agg(distinct g.version||'/'||g.seq_date, ',') from ref_genomes g where g.og_id=f.og_id and g.version like 'hic%') hic_assemblies from f where version='hifi1' and omnic order by 1,2,3,4;
with f as (select *,
 num_nonnulls(num_contigs,contig_n50,contig_n50_size_mb,num_scaffolds,scaffold_n50,scaffold_n50_size_mb,largest_scaffold,largest_scaffold_size_mb,total_scaffold_length,total_scaffold_length_size_mb,gc_content_percent)>0 as gfa,
 num_nonnulls(dataset,complete,single_copy,multi_copy,fragmented,missing,n_markers,internal_stop_codon_percent,scaffold_n50_bus,contigs_n50_bus,percent_gaps,number_of_scaffolds)>0 as busco,
 num_nonnulls(unique_k_mers_assembly,k_mers_total,qv,error)>0 as mqv,
 num_nonnulls(k_mer_set,solid_k_mers,total_k_mers,completeness)>0 as mcomp,
 num_nonnulls(total,total_unmapped,total_single_sided_mapped,total_mapped,total_dups,total_nodups,cis,trans)>0 as omnic,
 num_nonnulls(format,type,num_seqs,sum_len,min_len,avg_len,max_len)>0 as seqkit,
 num_nonnulls(num_chromosomes,pct_assigned,pct_no_super,num_seq_no_super,max_len_no_super)>0 as chrom,
 num_gaps is not null as gaps, hap2_chr_level_max_len is not null as h2
 from ref_genomes) select count(distinct (og_id,seq_date)) hifi1_asm_with_omnic, count(*) rows, count(*) filter (where stage=1) stage1 from f where version='hifi1' and omnic;
\echo '## K run matches: PacBio HiFi (not Kinnex) / ONT, on (og_id, seq_date)'
with a as (select distinct og_id, seq_date, version from ref_genomes), m as (select a.*, (select count(*) from v_sequencing_browse s where s.og_id=a.og_id and s.seq_date=a.seq_date and s.technology in ('PacBio HIFI','PacBio','ONT') and coalesce(s.library_type,'') !~* 'rna|kinx') n from a) select left(version,3) strat, count(*) asm, count(*) filter (where n=1) one, count(*) filter (where n>1) multi, count(*) filter (where n=0) none from m group by rollup(1) order by 1;
select distinct library_type, technology from v_sequencing_browse where technology in ('PacBio HIFI','PacBio','ONT','PacBio Kinnex') order by 2,1;
\echo '## L unmatched and multi-matched assemblies'
with a as (select distinct og_id, seq_date, version from ref_genomes) select a.og_id, a.seq_date, a.version, (select string_agg(s.sequencing_id||'('||s.technology||')', ', ' order by s.seq_date) from v_sequencing_browse s where s.og_id=a.og_id and s.technology in ('PacBio HIFI','PacBio','ONT')) long_read_rows_for_og from a where (select count(*) from v_sequencing_browse s where s.og_id=a.og_id and s.seq_date=a.seq_date and s.technology in ('PacBio HIFI','PacBio','ONT')) <> 1 order by 1,2,3;
\echo '## M size_mb = round(bp/1e6, 2) test'
select count(*) filter (where contig_n50 is not null) n1, count(*) filter (where contig_n50_size_mb is distinct from round(contig_n50/1e6,2) and contig_n50 is not null) bad_contig_n50,
 count(*) filter (where scaffold_n50_size_mb is distinct from round(scaffold_n50/1e6,2) and scaffold_n50 is not null) bad_scaf_n50,
 count(*) filter (where largest_scaffold_size_mb is distinct from round(largest_scaffold/1e6,2) and largest_scaffold is not null) bad_largest,
 count(*) filter (where total_scaffold_length_size_mb is distinct from round(total_scaffold_length/1e6,2) and total_scaffold_length is not null) bad_total,
 count(*) filter (where contig_n50_size_mb is not null and contig_n50 is null) mb_without_bp from ref_genomes;
select og_id, seq_date, version, stage, haplotype, contig_n50, contig_n50_size_mb, round(contig_n50/1e6,2) calc from ref_genomes where contig_n50_size_mb is distinct from round(contig_n50/1e6,2) and contig_n50 is not null limit 5;
\echo '## N raw_qc split'
select count(*) total, count(*) filter (where num_nonnulls(homozygosity,heterozygosity,genomesize,repeatsize,uniquesize,modelfit,errorrate)>0) genomescope_rows, count(*) filter (where contam_reads is not null) contam_rows, count(*) filter (where num_nonnulls(homozygosity,heterozygosity,genomesize,repeatsize,uniquesize,modelfit,errorrate,contam_reads)=0) empty from raw_qc;
\echo '## O hifi_reads_qc -> sequencing by (tube rebuilt, run)'
with q as (select h.*, og_id||tissue||'_'||ext_type||'_'||lib_code tube from hifi_reads_qc h) select count(*) rows, count(*) filter (where exists (select 1 from library l where l.library_tube_id=q.tube)) tube_exists, count(*) filter (where (select count(*) from sequencing s where s.library_tube_id=q.tube and s.run_id=q.run_id)=1) one_seq, count(*) filter (where (select count(*) from sequencing s where s.library_tube_id=q.tube and s.run_id=q.run_id)>1) multi_seq, count(*) filter (where not exists (select 1 from sequencing s where s.run_id=q.run_id)) run_not_in_sequencing from q;
\echo '## P hic_reads_qc -> Hi-C sequencing row of the same OG and tissue on the run'
select count(*) rows, count(*) filter (where (select count(*) from v_sequencing_browse s where s.og_id=q.og_id and s.run_id=q.run_id and s.technology='Hi-C' and s.tissue_id like q.og_id||q.tissue||'%')=1) one_seq, count(*) filter (where (select count(*) from v_sequencing_browse s where s.og_id=q.og_id and s.run_id=q.run_id and s.technology='Hi-C' and s.tissue_id like q.og_id||q.tissue||'%')>1) multi_seq, count(*) filter (where not exists (select 1 from sequencing s where s.run_id=q.run_id)) run_not_in_sequencing, count(*) filter (where lane='') blank_lane, count(*) filter (where run_id='') blank_run, count(*) filter (where ext_type='' or lib_code='') blank_ext_or_lib, count(*) filter (where not exists (select 1 from sample s where s.og_id=q.og_id)) orphan from hic_reads_qc q;
select count(*) filter (where not exists (select 1 from sample s where s.og_id=h.og_id)) hifi_orphan from hifi_reads_qc h;
\echo '## Q uploads'
select ncbi_status, count(*) from ref_genomes_sra_uploads group by 1 order by 1;
select coalesce(data_type,'<null>') data_type, count(*) from ref_genomes_sra_uploads group by 1 order by 1;
select count(*) filter (where not exists (select 1 from sample s where s.og_id=u.og_id)) sra_orphan, count(*) filter (where og_id is null) sra_null_og from ref_genomes_sra_uploads u;
select count(*) n, count(bioproject_hap1) bp1, count(bioproject_hap2) bp2, count(assembly_accession_hap1) aa1, count(assembly_accession_hap2) aa2, count(gca_accession_hap1) gca1, count(gca_accession_hap2) gca2, count(*) filter (where num_nonnulls(bioproject_hap1,assembly_accession_hap1,gca_accession_hap1)=0) no_hap1, count(*) filter (where num_nonnulls(bioproject_hap2,assembly_accession_hap2,gca_accession_hap2)=0) no_hap2 from ref_genomes_assembly_uploads;
select embargo_status, count(*) from ref_genomes_assembly_uploads group by 1;
with c as (select og_id, count(distinct (seq_date,version)) n from ref_genomes where stage=3 group by 1) select count(*) filter (where c.n=1) one_curated, count(*) filter (where c.n>1) multi_curated, count(*) filter (where c.n is null) no_curated from ref_genomes_assembly_uploads u left join c using (og_id);
\echo '## R readers: views and functions'
select distinct dependent_ns.nspname||'.'||dependent_view.relname as view, source_table.relname src from pg_depend join pg_rewrite on pg_depend.objid=pg_rewrite.oid join pg_class dependent_view on pg_rewrite.ev_class=dependent_view.oid join pg_class source_table on pg_depend.refobjid=source_table.oid join pg_namespace dependent_ns on dependent_ns.oid=dependent_view.relnamespace join pg_namespace sn on sn.oid=source_table.relnamespace where sn.nspname='public' and source_table.relname in ('ref_genomes','raw_qc','hifi_reads_qc','hic_reads_qc','ref_genomes_assembly_uploads','ref_genomes_sra_uploads') and dependent_view.relname<>source_table.relname order by 2,1;
select n.nspname||'.'||p.oid::regprocedure fn, p.prolang::regclass is null, l.lanname, p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname not in ('pg_catalog','information_schema') and prosrc ~* 'ref_genomes|raw_qc|hifi_reads_qc|hic_reads_qc';
\echo '## S grants'
select table_name, grantee, string_agg(privilege_type,',' order by privilege_type) from information_schema.role_table_grants where table_schema='public' and table_name in ('ref_genomes','raw_qc','hifi_reads_qc','hic_reads_qc','ref_genomes_assembly_uploads','ref_genomes_sra_uploads') and grantee<>'postgres' group by 1,2 order by 1,2;
