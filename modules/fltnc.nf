process SPLIT_READS {

    label 'process_high'

    publishDir "${params.results_output}qc/skera_reports", mode: 'copy', pattern: '*.segmented.summary.json, *.segmented.read_lengths.csv, *.segmented.summary.csv'

    input:
	   tuple val(sample_id), path(input_bam)
     val skera_primers

    output:
      tuple val(sample_id), path("${sample_id}.segmented.bam"), emit: split_reads_tuple
      path "${sample_id}.segmented.summary.json"
      path "${sample_id}.segmented.summary.csv"
      path "${sample_id}.segmented.read_lengths.csv"
    script:
    """
    pbskera split -j ${task.cpus} ${input_bam} ${skera_primers} ${sample_id}.segmented.bam
    """

    stub:
    """
    touch ${sample_id}.segmented.bam
    pbskera split --help
    """
}

process REMOVE_PRIMER {
    label 'process_high'

    publishDir "${params.results_output}qc/lima_reports", mode: 'copy', pattern: "*.lima.summary"

    input:
      tuple val(sample_id), path(segmented_bam)
      val tenx_primers

    output:
      tuple val(sample_id), path("${sample_id}.5p--3p.bam"), emit: removed_primer_tuple
      path "${sample_id}.lima.summary"

    script:
    """
    lima -j ${task.cpus} ${segmented_bam} ${tenx_primers} ${sample_id}.bam --isoseq
    """
    stub:
    """
    touch ${sample_id}.5p--3p.bam
    lima --help
    """


}

process TAG_BAM {
    label 'process_medium'

    input:
      tuple val(sample_id), path(primer_removed_bam)

    output:
    tuple val(sample_id), path("${sample_id}.flt.bam"), emit: tagged_tuple

    script:
    """
    isoseq tag -j ${task.cpus} ${primer_removed_bam} ${sample_id}.flt.bam --design T-12U-16B
    """
    stub:
    """
    touch ${sample_id}.flt.bam
    isoseq tag --help
    """

}

process REFINE_READS {
    label 'process_high'

    publishDir "${params.results_output}qc/refined", mode: 'copy', pattern: '*.fltnc.consensusreadset.xml, *.fltnc.filter_summary.report.json, *.fltnc.report.csv'


    input:
      tuple val(sample_id), path(tagged_bam)
      val tenx_primers
      val min_polya_length

    output:
      tuple val(sample_id), path("${sample_id}.fltnc.bam"), emit: refined_reads
      path "${sample_id}.fltnc.consensusreadset.xml"
      path "${sample_id}.fltnc.filter_summary.report.json"
      path "${sample_id}.fltnc.report.csv"

    script:
    """
    isoseq refine ${tagged_bam} ${tenx_primers} ${sample_id}.fltnc.bam  -j ${task.cpus} --require-polya --min-polya-length ${min_polya_length}
    samtools index ${sample_id}.fltnc.bam
    """
    stub:
    """
    touch ${sample_id}.fltnc.bam
    """
}
