process SQANTI3_QC {
    label 'process_high'

    publishDir "${params.results_output}results/transcript_info/sqanti3/", mode: 'copy', overwrite: true

    input:
      path(input_gtf_f)
      path(ref_gtf_f)
      path(genome_fasta_f)
      path(polya_f)
      path(cage_peak_f)
      path(polya_sites)

    output:
      path("sqanti3_qc"),                                        emit: qc_dir
      path("sqanti3_qc/transcript_models_classification.txt"),   emit: classification
      path("sqanti3_qc/transcript_models_corrected.gtf"),        emit: corrected_gtf
      path("sqanti3_qc/transcript_models_corrected.fasta"),      emit: corrected_fasta

    script:
      """
        sqanti3_qc.py \
              --isoforms ${input_gtf_f} --refGTF ${ref_gtf_f} --refFasta ${genome_fasta_f} \
              --polyA_motif_list ${polya_f} --CAGE_peak ${cage_peak_f} \
              --report pdf -n ${task.cpus} --polyA_peak ${polya_sites} \
              -d sqanti3_qc/ --include_ORF --output transcript_models
      """

}

process SQANTI3_FILTER {
  label 'process_single'

  publishDir "${params.results_output}results/transcript_info/sqanti3/", mode: 'copy', overwrite: true

  input:
    path(classification_f)
    path(corrected_gtf_f)
    path(corrected_fasta)
    path(sqanti_filter_json)
  output:
    path("sqanti3_filter"),                                         emit: filter_dir
    path("sqanti3_filter/transcript_models_pass_isoforms.txt"),             emit: pass_isoforms
    path("sqanti3_filter/*.filtered.gtf"),                          emit: filtered_gtf
  script:
  def prefix = classification_f.baseName.replace("_classification", "")
  """
  sqanti3_filter.py rules  --sqanti_class ${classification_f} \
      -j ${sqanti_filter_json} -d sqanti3_filter/ --filter_gtf ${corrected_gtf_f} --filter_faa ${corrected_fasta} --cpus ${task.cpus} --skip_report 
  python ${baseDir}/scripts/create_genedb.py -g ${corrected_gtf_f} -o sqanti3_filter/${corrected_gtf_f}.db
  python ${baseDir}/scripts/db_subset.py -d sqanti3_filter/${corrected_gtf_f}.db -i sqanti3_filter/transcript_models_pass_isoforms.txt -o sqanti3_filter/${prefix}.filtered.gtf
  python ${baseDir}/scripts/create_genedb.py -g sqanti3_filter/${prefix}.filtered.gtf -o sqanti3_filter/${prefix}.filtered.gtf.db
  """

}
