include {run_isoquant_firstPass; create_model_construction_bam; run_isoquant_chunked; replace_novel_names; collect_gtfs} from '../../modules/isoquant.nf'
include {run_isoquant_firstPass_withmodelconstruction; replace_novel_names_firsPass_singlenovelname} from '../../modules/isoquant.nf'
include {collect_counts_as_mtx_perChr as collect_isoform_counts_as_mtx_perChr} from '../../modules/isoquant.nf'
include {collect_counts_as_mtx_perChr as collect_gene_counts_as_mtx_perChr} from '../../modules/isoquant.nf'
include {collect_counts_as_mtx_perChr as collect_intron_include_counts_as_mtx_perChr} from '../../modules/isoquant.nf'
include {collect_counts_as_mtx_perChr as collect_intron_exclude_counts_as_mtx_perChr} from '../../modules/isoquant.nf'
include {collect_counts_as_mtx_perChr as collect_exon_include_counts_as_mtx_perChr} from '../../modules/isoquant.nf'
include {collect_counts_as_mtx_perChr as collect_exon_exclude_counts_as_mtx_perChr} from '../../modules/isoquant.nf'

include {collect_counts_as_mtx_perChr as collect_isoform_chrM_counts_as_mtx_perChr} from '../../modules/isoquant.nf'
include {collect_counts_as_mtx_perChr as collect_gene_chrM_counts_as_mtx_perChr} from '../../modules/isoquant.nf'

include {collect_mtx_as_h5ad as collect_isoform_mtx_as_h5ad} from '../../modules/isoquant.nf'
include {collect_mtx_as_h5ad as collect_gene_mtx_as_h5ad} from '../../modules/isoquant.nf'
include {collect_mtx_as_h5ad as collect_intron_include_mtx_as_h5ad} from '../../modules/isoquant.nf'
include {collect_mtx_as_h5ad as collect_intron_exclude_mtx_as_h5ad} from '../../modules/isoquant.nf'
include {collect_mtx_as_h5ad as collect_exon_include_mtx_as_h5ad} from '../../modules/isoquant.nf'
include {collect_mtx_as_h5ad as collect_exon_exclude_mtx_as_h5ad} from '../../modules/isoquant.nf'

include {collect_mtx_as_h5ad as collect_isoform_chrM_mtx_as_h5ad} from '../../modules/isoquant.nf'
include {collect_mtx_as_h5ad as collect_gene_chrM_mtx_as_h5ad} from '../../modules/isoquant.nf'

include {format_intron_exon_grouped_counts_perChr as format_intron_grouped_counts_firstPass_perChr} from '../../modules/isoquant.nf'
include {format_intron_exon_grouped_counts_perChr as format_intron_grouped_counts_secondPass_perChr} from '../../modules/isoquant.nf'
include {format_intron_exon_grouped_counts_perChr as format_exon_grouped_counts_firstPass_perChr} from '../../modules/isoquant.nf'
include {format_intron_exon_grouped_counts_perChr as format_exon_grouped_counts_secondPass_perChr} from '../../modules/isoquant.nf'

include {find_mapped_and_unmapped_regions_per_sampleChrom; acrossSamples_mapped_unmapped_regions_perChr; suggest_splits_binarySearch; split_bams_perChunk} from '../../modules/smartSplit.nf'

workflow isoquant_twopass_perChr_wf {
  take:
    isoquant_preprocess_bam_perChr_ch
    chrom_genedb_fasta_chr_ch
  main:
    isoqunat_firsspass_input_ch=isoquant_preprocess_bam_perChr_ch
    .combine(chrom_genedb_fasta_chr_ch,by:0)

    isoquant_firstpass_output_ch=run_isoquant_firstPass(isoqunat_firsspass_input_ch)
    isoquant_firstpass_output_ch
    .map{ chrom,sample_id,isoquant_output_dir,read_assignment_f,bam -> [chrom,sample_id,read_assignment_f,bam] }
    .set{ model_construction_bam_input_ch }
    model_construction_bam_ch=create_model_construction_bam(model_construction_bam_input_ch)

    model_construction_bam_ch
    .groupTuple(by:0)
    .combine(chrom_genedb_fasta_chr_ch,by:0)
    .set{ isoquant_secondpass_input_ch }

    isoquant_secondpass_output_ch=run_isoquant_perChr(isoquant_secondpass_input_ch)



  emit:
    isoquant_secondpass_output_ch
}



workflow collect_exon_intron_coutns_perChr_wf {
  take:
    isoquant_firstpass_output_ch
    isoquant_output_novel_names_ch
    bam_nums_perChr_ch
    chunks
  main:
    /////////////////////////////////////////////////////////
    //////COLLECTION INTRON/EXON GROUPED COUNTS////////////
    /////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////
    //////A)Collecting intron grouped counts as MTX//////////
    /////////////////////////////////////////////////////////


    isoquant_firstpass_output_ch
    ///.filter{tpl -> (tpl[0]=='chr2') && (tpl[1]=='Isogut15045390') }
    .map{chrom,sample_id,isoquant_output_dir,read_assignments_f,processed_bam -> [chrom,"${sample_id}.${chrom}.intron_grouped_counts","${isoquant_output_dir}/${sample_id}.${chrom}/${sample_id}.${chrom}.intron_grouped_tag_CB_counts.tsv"]} | format_intron_grouped_counts_firstPass_perChr | set{firstPass_intron_grouped_formatted_ch}

    isoquant_output_novel_names_ch
    ///.filter{tpl -> tpl[1]=='chr2_137822130_165323855'}
    .map{chrom,programmaticRegion,isoquant_output_dir -> [chrom,"${programmaticRegion}.intron_grouped_counts","${isoquant_output_dir}/${programmaticRegion}.intron_grouped_tag_CB_counts.tsv"]} | format_intron_grouped_counts_secondPass_perChr | set{secondPass_intron_grouped_formatted_ch}

    firstPass_intron_grouped_formatted_ch
        .combine(bam_nums_perChr_ch,by:0)
        .map{chrom, include_f,exclude_f,chrom_sample_size -> [groupKey(chrom,chrom_sample_size),include_f]}
        .groupTuple(by:0)
        .map {tpl -> [tpl[0],tpl[1]]}
        .combine(
        secondPass_intron_grouped_formatted_ch
            .map{chrom, prefix,intron_f -> [groupKey(chrom,chunks),intron_f]}
            .groupTuple(by:0)
            .map {tpl -> [tpl[0],tpl[1]]}
        ,by:0
        )
        .map { chrom, firstPasslist, secondPasslist -> [chrom, firstPasslist + secondPasslist] } | collect_intron_include_counts_as_mtx_perChr | set{intron_include_mtx}

        collect_intron_include_mtx_as_h5ad(intron_include_mtx.chrom_mtx | collect, 'introns_include')

    firstPass_intron_grouped_formatted_ch
        .combine(bam_nums_perChr_ch,by:0)
        .map{chrom, include_f,exclude_f,chrom_sample_size -> [groupKey(chrom,chrom_sample_size),exclude_f]}
        .groupTuple(by:0)
        .map {tpl -> [tpl[0],tpl[1]]}
        .combine(
        secondPass_intron_grouped_formatted_ch
            .map{chrom, prefix,intron_f -> [groupKey(chrom,chunks),intron_f]}
            .groupTuple(by:0)
            .map {tpl -> [tpl[0],tpl[1]]}
        ,by:0
        )
        .map { chrom, firstPasslist, secondPasslist -> [chrom, firstPasslist + secondPasslist] } | collect_intron_exclude_counts_as_mtx_perChr | set{intron_exclude_mtx}

        collect_intron_exclude_mtx_as_h5ad(intron_exclude_mtx.chrom_mtx | collect, 'introns_exclude')




        /////////////////////////////////////////////////////////
        //////A)Collecting exon grouped counts as MTX//////////
        /////////////////////////////////////////////////////////

        isoquant_firstpass_output_ch
        ///.filter{tpl -> (tpl[0]=='chr2') && (tpl[1]=='Isogut15045390') }
        .map{chrom,sample_id,isoquant_output_dir,read_assignments_f,processed_bam -> [chrom,"${sample_id}.${chrom}.exon_grouped_counts","${isoquant_output_dir}/${sample_id}.${chrom}/${sample_id}.${chrom}.exon_grouped_tag_CB_counts.tsv"]} | format_exon_grouped_counts_firstPass_perChr | set{firstPass_exon_grouped_formatted_ch}

        isoquant_output_novel_names_ch
        ///.filter{tpl -> tpl[1]=='chr2_137822130_165323855'}
        .map{chrom,programmaticRegion,isoquant_output_dir -> [chrom,"${programmaticRegion}.exon_grouped_counts","${isoquant_output_dir}/${programmaticRegion}.exon_grouped_tag_CB_counts.tsv"]} | format_exon_grouped_counts_secondPass_perChr | set{secondPass_exon_grouped_formatted_ch}


        firstPass_exon_grouped_formatted_ch
            .combine(bam_nums_perChr_ch,by:0)
            .map{chrom, include_f,exclude_f,chrom_sample_size -> [groupKey(chrom,chrom_sample_size),include_f]}
            .groupTuple(by:0)
            .map {tpl -> [tpl[0],tpl[1]]}
            .combine(
            secondPass_exon_grouped_formatted_ch
                .map{chrom, prefix,exon_f -> [groupKey(chrom,chunks),exon_f]}
                .groupTuple(by:0)
                .map {tpl -> [tpl[0],tpl[1]]}
            ,by:0
            )
            .map { chrom, firstPasslist, secondPasslist -> [chrom, firstPasslist + secondPasslist] } | collect_exon_include_counts_as_mtx_perChr | set{exon_include_mtx}

            collect_exon_include_mtx_as_h5ad(exon_include_mtx.chrom_mtx | collect, 'exons_include_mtx')

        firstPass_exon_grouped_formatted_ch
            .combine(bam_nums_perChr_ch,by:0)
            .map{chrom, include_f,exclude_f,chrom_sample_size -> [groupKey(chrom,chrom_sample_size),exclude_f]}
            .groupTuple(by:0)
            .map {tpl -> [tpl[0],tpl[1]]}
            .combine(
            secondPass_exon_grouped_formatted_ch
                .map{chrom, prefix,exon_f -> [groupKey(chrom,chunks),exon_f]}
                .groupTuple(by:0)
                .map {tpl -> [tpl[0],tpl[1]]}
            ,by:0
            )
            .map { chrom, firstPasslist, secondPasslist -> [chrom, firstPasslist + secondPasslist] } | collect_exon_exclude_counts_as_mtx_perChr | set{exon_exclude_mtx}

            collect_exon_exclude_mtx_as_h5ad(exon_exclude_mtx.chrom_mtx | collect, 'exons_exclude_mtx')

    /////////////////////////////////////////////////////////
    //////END: COLLECTION INTRON/EXON GROUPED COUNTS////////////
    /////////////////////////////////////////////////////////
}


////////////////////////////////
//////chrM workflows///////////
///////////////////////////////
workflow isoquant_chrM {
  take:
    isoquant_preprocess_bam_perChr_ch
    chrom_genedb_fasta_chr_ch
    chrom_sizes_f
  main:
    ///////////////////////////////////////////////////////
    //////////////////A-FIRST PASS/////////////////////////
    ///////////////////////////////////////////////////////
    isoqunat_firsspass_input_ch=isoquant_preprocess_bam_perChr_ch
    .combine(chrom_genedb_fasta_chr_ch,by:0)
    //.filter{tpl -> tpl[1]=="Isogut15045373"}
    isoqunat_firsspass_input_ch.groupTuple(by:0).map{tpl -> [tpl[0],(tpl[1]).size()]}.set{bam_nums_perChr_ch}
    isoquant_firstpass_output_ch=run_isoquant_firstPass_withmodelconstruction(isoqunat_firsspass_input_ch)

    isoquant_firstpass_output_ch.map{chrom,sample_id,isoquant_output_dir,isoquant_assignment_f, isoquant_input_bam -> [chrom,sample_id,isoquant_output_dir]}
    .set{replace_novel_names_input_ch}

  
    //Updating names of novel transcript so they don't clash between chunks
    isoquant_output_novel_names_ch=replace_novel_names_firsPass_singlenovelname(replace_novel_names_input_ch)
    
    ///////////////////////////////////////////////////////
    //////////////////END: FIRST PASS//////////////////////
    ///////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////
    //////////////////B-OUTPUT CHANNELs/////////////////////////
    ////////////////////////////////////////////////////////////
    //Setting up output channel for: counts, GTF, reads
    isoquant_output_novel_names_ch.map{chrom,sample_id,isoquant_output_dir -> [chrom,"${isoquant_output_dir}/${sample_id}.${chrom}.discovered_transcript_grouped_tag_CB_counts.linear.tsv"]}.groupTuple(by:0).set{output_isoform_counts_ch}
    isoquant_output_novel_names_ch.map{chrom,sample_id,isoquant_output_dir -> [chrom,"${isoquant_output_dir}/${sample_id}.${chrom}.discovered_gene_grouped_tag_CB_counts.linear.tsv"]}.groupTuple(by:0).set{output_gene_counts_ch}
    isoquant_output_novel_names_ch.map{chrom,sample_id,isoquant_output_dir -> [chrom,"${isoquant_output_dir}/${sample_id}.${chrom}.transcript_models.gtf"]}.groupTuple(by:0).set{output_existing_gtf_ch}
    isoquant_output_novel_names_ch.map{chrom,sample_id,isoquant_output_dir -> [chrom,"${isoquant_output_dir}/${sample_id}.${chrom}.extended_annotation.gtf"]}.groupTuple(by:0).set{output_extended_gtf_ch}
    isoquant_output_novel_names_ch.map{chrom,sample_id,isoquant_output_dir -> [chrom,"${isoquant_output_dir}/${sample_id}.${chrom}.corrected_reads.bed.gz"]}.groupTuple(by:0).set{output_corrected_reads_ch}
    isoquant_output_novel_names_ch.map{chrom,sample_id,isoquant_output_dir -> [chrom,"${isoquant_output_dir}/${sample_id}.${chrom}.read_assignments.tsv.gz"]}.groupTuple(by:0).set{output_assignment_reads_ch}
    isoquant_output_novel_names_ch.map{chrom,sample_id,isoquant_output_dir -> [chrom,"${isoquant_output_dir}/${sample_id}.${chrom}.transcript_model_reads.tsv.gz"]}.groupTuple(by:0).set{output_transcriptmodel_reads_ch}


    ///////////////////////////////////////////////////////
    //////////////////END: OUTPUT CHANNELS/////////////////
    ///////////////////////////////////////////////////////

  emit:
    isoform_counts=output_isoform_counts_ch
    gene_counts=output_gene_counts_ch
    existing_gtf=output_existing_gtf_ch
    extended_gtf=output_extended_gtf_ch
    assignment_reads=output_assignment_reads_ch
    transcriptmodel_reads=output_transcriptmodel_reads_ch
    corrected_reads=output_corrected_reads_ch
    nums_ch=bam_nums_perChr_ch
}

///////////////////////////////////////////////
/////////////COLLECTION WORKFLOWS//////////////
///////////////////////////////////////////////
workflow collect_gene_isoform_counts_perChr_wf {
  take:
    isoform_counts_ch
    gene_counts_ch
  main:

    //Collecting isoform as MTX
    isoform_mtx=collect_isoform_counts_as_mtx_perChr(isoform_counts_ch,isoform_counts_ch.map{chrom,counts_f -> "${params.results_output}results/counts/isoform/MTX/"})
    gene_mtx=collect_gene_counts_as_mtx_perChr(gene_counts_ch,gene_counts_ch.map{chrom,counts_f -> "${params.results_output}results/counts/gene/MTX/"})

    isoform_h5ad=collect_isoform_mtx_as_h5ad(isoform_mtx.chrom_mtx | collect, 'isoforms',"${params.results_output}results/counts/isoform/H5AD/")
    gene_h5ad=collect_gene_mtx_as_h5ad(gene_mtx.chrom_mtx | collect, 'genes',"${params.results_output}results/counts/gene/H5AD/")
  emit:
    isoform_h5ad=isoform_h5ad.h5ad_file
    isoform_mtx=isoform_mtx.chrom_mtx
    gene_h5ad=gene_h5ad.h5ad_file
    gene_mtx=gene_mtx.chrom_mtx

}
workflow collect_output_wf {

  take:
    isoform_counts_ch
    gene_counts_ch
    existing_gtf_ch
    extended_gtf_ch
    assignment_reads_ch
    transcriptmodel_reads_ch
    corrected_reads_ch
  main:
    ///////////////////////////////////////////////////////
    //////////////////B-COLLECTING OUTPUT/////////////////////////
    ///////////////////////////////////////////////////////
    //Collect counts as MTX/H5AD
    isoform_gene_mtx_h5ad=collect_gene_isoform_counts_perChr_wf(isoform_counts_ch,gene_counts_ch)

    ///5-Collecting transcript model GTFs
    isoform_gene_mtx_h5ad.isoform_mtx.map{mtx_dir -> "${mtx_dir}/genes.tsv"}.collect().set{mtx_isoform_fs}
    existing_gtf_ch.map{chrom,gtf_fs -> gtf_fs}.collect().set{input_gtf_ch}
    gtfs=collect_gtfs(input_gtf_ch,params.gtf_f,mtx_isoform_fs,"${params.results_output}results/gtf/")
    extended_gtf=gtfs[0]
    existing_gtf=gtfs[1]
    // assignment_reads_ch.view()


}
workflow isoquant_twopass_chunked_wf {
  take:
    isoquant_preprocess_bam_perChr_ch
    chrom_genedb_fasta_chr_ch
    chrom_sizes_f
    chunks
  main:
    ///////////////////////////////////////////////////////
    //////////////////A-FIRST PASS/////////////////////////
    ///////////////////////////////////////////////////////
    isoqunat_firsspass_input_ch=isoquant_preprocess_bam_perChr_ch
    .combine(chrom_genedb_fasta_chr_ch,by:0)
    isoqunat_firsspass_input_ch.groupTuple(by:0).map{tpl -> [tpl[0],(tpl[1]).size()]}.set{bam_nums_perChr_ch}
    isoquant_firstpass_output_ch=run_isoquant_firstPass(isoqunat_firsspass_input_ch)
    isoquant_firstpass_output_ch
    .map{ chrom,sample_id,isoquant_output_dir,read_assignment_f,bam -> [chrom,sample_id,read_assignment_f,bam] }
    .set{ model_construction_bam_input_ch }
    model_construction_bam_ch=create_model_construction_bam(model_construction_bam_input_ch)
    ////////////////////////////////////////////////////////////
    //////////////////END: A-FIRST PASS/////////////////////////
    ////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////
    //////////////////B-SECOND PASS/////////////////////////
    ///////////////////////////////////////////////////////
    ///sharding
    mapped_unmapped_regions_tuple_ch=find_mapped_and_unmapped_regions_per_sampleChrom(model_construction_bam_ch,chrom_sizes_f)

    ///adding sample size to the group key before grouping tuples so that generation of mapped_unmapped_regions_groupedTuple_ch is not blocked untill all samples/chrom is finished
    mapped_unmapped_regions_tuple_ch
    .combine(bam_nums_perChr_ch,by:0)
    .map{chrom,sample_id,unmapped_bed,mapped_bed,chrom_sample_size -> [groupKey(chrom,chrom_sample_size),sample_id,unmapped_bed,mapped_bed]}
    .groupTuple(by:0)
    .set{mapped_unmapped_regions_groupedTuple_ch}

    ///findint intersection of unmapped regions across samples per chromosome
    acrossSamples_mapped_unmapped_regions_perChr_ch=acrossSamples_mapped_unmapped_regions_perChr(mapped_unmapped_regions_groupedTuple_ch)


    /// Merging grouped BAM tuples with unmapped BED files (again adding size as groupkey)
    model_construction_bam_ch
    .combine(bam_nums_perChr_ch,by:0)
    .map{chrom, sample_id,read_assignment_f, bam, chrom_sample_size -> [groupKey(chrom,chrom_sample_size),sample_id,read_assignment_f, bam]}
    .groupTuple(by:0)
    .combine(acrossSamples_mapped_unmapped_regions_perChr_ch.unmapped_bed,by:0)
    .set { modelconstructionBam_unmappedbed_tuples_ch }

    suggested_splits_ch=suggest_splits_binarySearch(modelconstructionBam_unmappedbed_tuples_ch,chunks,chrom_sizes_f)


    suggested_splits_ch.flatMap { tuple ->
        def chrom = tuple[0]     // Extract chrom from the tuple
        def filePath = tuple[3]  // Get the last item in the tuple (path to file)
        file(filePath).text.split('\n') // Read file content and split into lines
            .findAll { it }             // Remove empty lines
            .collect { line ->          // Format each line and pair it with chrom
                def cols = line.split('\t') // Split line into columns by tab
                def formattedRegion = cols[0]+":"+cols[1]+"-"+cols[2] // Region formatting
                def programmaticRegion=cols[0]+"_"+cols[1]+"_"+cols[2]
                [chrom, formattedRegion,programmaticRegion] // Return chrom and formatted line as a pair
            }
    }.set {chrom_region_ch}

    /// Splitting BAMs according to suggested regions
    model_construction_bam_ch
      .combine(bam_nums_perChr_ch,by:0)
      .map{chrom, sample_id,read_assignment_f, bam, chrom_sample_size -> [groupKey(chrom,chrom_sample_size),sample_id,read_assignment_f, bam]}
      .groupTuple(by:0)
      .combine(chrom_region_ch,by:0)
      .set {modelconstructionBam_Region_groupedTuple_ch}
    modelconstructionRegionBam=split_bams_perChunk(modelconstructionBam_Region_groupedTuple_ch,"mapped.realcells_only.processed.model_construction_reads")


    ///Runnning second pass
    modelconstructionRegionBam
    .map {chrom, sample_ids, bams, bais, formattedRegion, programmaticRegion, counts_f  -> [chrom, sample_ids, bams, bais, formattedRegion, programmaticRegion ] }
    .combine(chrom_genedb_fasta_chr_ch,by:0)
    .set {isoquant_chunked_input}

    isoquant_secondpass_output_ch=run_isoquant_chunked(isoquant_chunked_input)

    
    isoquant_secondpass_output_ch
    ///.filter{tpl -> (tpl[1] == 'chr1_227459712_248956421') || (tpl[1] == 'chr1_159501669_170660798')}
    .set{replace_novel_names_input_ch}


    //1-Updating names of novel transcript so they don't clash between chunks
    isoquant_output_novel_names_ch=replace_novel_names(replace_novel_names_input_ch)
  

    ////////////////////////////////////////////////////////////
    //////////////////B-OUTPUT CHANNELs/////////////////////////
    ////////////////////////////////////////////////////////////
    //Setting up output channel for: counts, GTF, reads

    //Combining transcript-level counts channels from first and second passes
    //NOTE: first-pass is keyed by bam_num (#samples) and second-pass by #regions; these
    //sizes differ, so a groupKey-based combine(by:0) never matches (GroupKey equality
    //includes the size hint) and silently drops the chunked chromosomes. Mixing both
    //per-chrom streams and grouping by chrom is robust to a variable number of split
    //regions per chromosome.
    isoquant_firstpass_output_ch
    .map{chrom,sample_id,isoquant_output_dir,read_assignment_f,bam_f -> [chrom,"${isoquant_output_dir}/${sample_id}.${chrom}/${sample_id}.${chrom}.transcript_grouped_tag_CB_counts.linear.tsv"]}
    .mix(
      isoquant_output_novel_names_ch.map{chrom,programmaticRegion,isoquant_output_dir -> [chrom,"${isoquant_output_dir}/${programmaticRegion}.discovered_transcript_grouped_tag_CB_counts.linear.noknown.tsv"]}
    )
    .groupTuple(by:0)
    .set{output_isoform_counts_ch}

    //Combining gene-level counts channels from first and second passes (see note above)
    isoquant_firstpass_output_ch
    .map{chrom,sample_id,isoquant_output_dir,read_assignment_f,bam_f -> [chrom,"${isoquant_output_dir}/${sample_id}.${chrom}/${sample_id}.${chrom}.gene_grouped_tag_CB_counts.linear.tsv"]}
    .mix(
      isoquant_output_novel_names_ch.map{chrom,programmaticRegion,isoquant_output_dir -> [chrom,"${isoquant_output_dir}/${programmaticRegion}.discovered_gene_grouped_tag_CB_counts.linear.tsv"]}
    )
    .groupTuple(by:0)
    .set{output_gene_counts_ch}

    //Collecting transcript models GTFs. 
    isoquant_output_novel_names_ch.map{chrom,programmaticRegion,isoquant_output_dir -> [groupKey(chrom,chunks),"${isoquant_output_dir}/${programmaticRegion}.transcript_models.gtf"]}.groupTuple(by:0)
    .set{output_existing_gtf_ch}

    //Collecting transcript models extended GTFs. 
    isoquant_output_novel_names_ch.map{chrom,programmaticRegion,isoquant_output_dir -> [groupKey(chrom,chunks),"${isoquant_output_dir}/${programmaticRegion}.extended_annotation.gtf"]}.groupTuple(by:0)
    .set{output_extended_gtf_ch}

    //Collecting corrected reads beds from first/second passes
    isoquant_firstpass_output_ch.combine(bam_nums_perChr_ch,by:0)
    .map{chrom,sample_id,isoquant_output_dir,read_assignment_f,bam_f,bam_num -> [groupKey(chrom,bam_num),"${isoquant_output_dir}/${sample_id}.${chrom}/${sample_id}.${chrom}.corrected_reads.bed.gz"]}
    .groupTuple(by:0)
    .combine(
      isoquant_output_novel_names_ch.map{chrom,programmaticRegion,isoquant_output_dir -> [groupKey(chrom,chunks),"${isoquant_output_dir}/${programmaticRegion}.corrected_reads.bed.gz"]}.groupTuple(by:0),
      by:0
    )
    .map{chrom,firstPass,secondPass -> [chrom,firstPass+secondPass]}
    .set{output_corrected_reads_ch}

    //Collecting read assignments from first/second passes
    isoquant_firstpass_output_ch.combine(bam_nums_perChr_ch,by:0)
    .map{chrom,sample_id,isoquant_output_dir,read_assignment_f,bam_f,bam_num -> [groupKey(chrom,bam_num),"${isoquant_output_dir}/${sample_id}.${chrom}/${sample_id}.${chrom}.read_assignments.tsv.gz"]}
    .groupTuple(by:0)
    .combine(
      isoquant_output_novel_names_ch.map{chrom,programmaticRegion,isoquant_output_dir -> [groupKey(chrom,chunks),"${isoquant_output_dir}/${programmaticRegion}.read_assignments.tsv.gz"]}.groupTuple(by:0),
      by:0
    )
    .map{chrom,firstPass,secondPass -> [chrom,firstPass+secondPass]}
    .set{output_assignment_reads_ch}

    //Collecting novel transcripts reads
    isoquant_output_novel_names_ch.map{chrom,programmaticRegion,isoquant_output_dir -> [groupKey(chrom,chunks),"${isoquant_output_dir}/${programmaticRegion}.transcript_model_reads.tsv.gz"]}.groupTuple(by:0)
    .set{output_transcriptmodel_reads_ch}


    ///////////////////////////////////////////////////////
    //////////////////END: OUTPUT CHANNELS/////////////////
    ///////////////////////////////////////////////////////

  emit:
    isoform_counts=output_isoform_counts_ch
    gene_counts=output_gene_counts_ch
    existing_gtf=output_existing_gtf_ch
    extended_gtf=output_extended_gtf_ch
    assignment_reads=output_assignment_reads_ch
    transcriptmodel_reads=output_transcriptmodel_reads_ch
    corrected_reads=output_corrected_reads_ch
    nums_ch=bam_nums_perChr_ch
  
}


