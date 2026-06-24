nextflow.enable.dsl=2

///Modules
include {SQANTI3_QC; SQANTI3_FILTER} from './modules/sqanti3.nf'

///Subworkflows
include {BAM_PROCESSING; BAM_PROCESSING_SEGMENTED; MAPPING_ONLY; DEDUP_ONLY} from './subworkflows/bam_processing/bam_processing.nf'
include {DECONVOLUTION} from './subworkflows/deconvolution/deconvolution.nf'
include {ISOQUANT_TWOPASS_PROCESS} from './subworkflows/isoquant_recipes/isoquant_twopass_process.nf'
include {PFAM_ANNOTATION_WF} from './subworkflows/pfam_annotation/pfam_annotation.nf'

include {mtx_subset_wf} from './subworkflows/core/mtx_subset.nf'


//include {customPublish as customPublishFilteredH5ADIsoform} from './modules/customPublish.nf'
//include {customPublish as customPublishFilteredMTXIsoform} from  './modules/customPublish.nf'


/// Setting default parameters
if(!params.barcode_correction_percentile) {
  params.barcode_correction_percentile=98
}
if(!params.min_polya_length) {
  params.min_polya_length=20
}

//if(!params.exclude_samples) {
//  params.exclude_samples=[]
//}


assert params.run_mode in ['with_quant', 'pre_quant'] : "ERROR: params.run_mode must be one of: 'with_quant', 'pre_quant'"


workflow full{
  BAM_PROCESSING()
  mapped_reads=BAM_PROCESSING.out.mapped_reads
  if (params.run_deconvolution == 'TRUE') {
    DECONVOLUTION(mapped_reads)
    mapped_reads=DECONVOLUTION.out.fullBam_ch
  }
  mapped_reads.view()
  if (params.run_mode == 'with_quant'){ 
    ISOQUANT_TWOPASS_PROCESS(mapped_reads)
  }
}

workflow full_segmented{
  // Same as `full` but the input BAMs are already segmented (output of `pbskera split`),
  // so the skera SPLIT_READS step is skipped and processing starts from REMOVE_PRIMER.
  BAM_PROCESSING_SEGMENTED()
  mapped_reads=BAM_PROCESSING_SEGMENTED.out.mapped_reads
  if (params.run_deconvolution == 'TRUE') {
    DECONVOLUTION(mapped_reads)
    mapped_reads=DECONVOLUTION.out.fullBam_ch
  }
  mapped_reads.view()
  if (params.run_mode == 'with_quant'){ 
    ISOQUANT_TWOPASS_PROCESS(mapped_reads)
  }
}

workflow bam_processing_wf {
    // Independent workflow entry for deconvolution
    BAM_PROCESSING()
}

workflow bam_processing_segmented_wf {
    // Independent workflow entry for already-segmented input BAMs (skips skera SPLIT_READS)
    BAM_PROCESSING_SEGMENTED()
}

workflow mapping_only_wf {
    MAPPING_ONLY()
}

workflow dedup_only_wf {
    DEDUP_ONLY()
}

workflow deconvolution_wf {
    // Independent workflow entry for deconvolution
    input_ch = 'independent workflow'
    DECONVOLUTION(input_ch)
}

workflow isoquant_twopass_wf {
    input_ch = 'independent workflow'
    ISOQUANT_TWOPASS_PROCESS(input_ch)
}

workflow pfam_annotation_wf {
    input_ch = 'independent workflow'
    PFAM_ANNOTATION_WF(input_ch)
}


///////////////////////////////////////
//recheck below
///////////////////////////////////////



workflow sqanti3 {

  def input_gtf_f="${params.results_output}results/gtf/transcript_models.gtf"
  SQANTI3_QC(input_gtf_f,params.gtf_f,params.genome_fasta_f,params.polya_f,params.cage_peak_f,params.polya_sites)
  SQANTI3_FILTER(SQANTI3_QC.out.classification, SQANTI3_QC.out.corrected_gtf, SQANTI3_QC.out.corrected_fasta, params.sqanti_filter_json)
  Channel
  .fromPath("${params.results_output}results/counts/isoform/MTX/*/matrix.mtx")
  .map{path -> path.parent}
  .set{prefiltered_mtx_dir_ch}
  mtx_subset_output_ch=mtx_subset_wf(prefiltered_mtx_dir_ch, SQANTI3_FILTER.out.pass_isoforms)
  mtx_subset_output_ch.h5ad_file.view()

///  customPublishFilteredH5ADIsoform(mtx_subset_output_ch.h5ad_file,"${params.results_output}results/counts_sqanti3/isoform/H5AD/")
///  customPublishFilteredMTXIsoform((mtx_subset_output_ch.isoform_mtx).collect(),"${params.results_output}results/counts_sqanti3/isoform/MTX/")

}

