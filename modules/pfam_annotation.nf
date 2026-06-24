process GFFREAD_PROTEINS {
    label 'process_single'

    publishDir "${params.results_output}results/transcript_info/pfam/", mode: 'copy', overwrite: true

    input:
      path(filtered_gtf)
      path(genome_fasta)

    output:
      path("proteins.faa"), emit: proteins_faa

    script:
      """
      gffread ${filtered_gtf} -g ${genome_fasta} -y proteins.faa
      """
}

process HMMSCAN_PFAM {
    label 'process_medium'

    publishDir "${params.results_output}results/transcript_info/pfam/", mode: 'copy', overwrite: true

    input:
      path(proteins_faa)

    output:
      path("pfam.domtblout"), emit: domtblout
      path("pfam.tblout"),    emit: tblout

    script:
      """
      hmmscan \
        --domtblout pfam.domtblout \
        --tblout pfam.tblout \
        --cpu ${task.cpus} \
        --cut_ga \
        ${params.pfam_db} \
        ${proteins_faa}
      """
}
