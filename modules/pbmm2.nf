process PBMM2 {
    label 'process_high'
    //publishDir "${params.results_output}qc/mapped", mode: 'copy'

    input:
        tuple val(sample_id), path(dedup_bam)
        val genome_fasta_f
        path manual_barcodes  // optional: pass [] if unused

    output:
        tuple val(sample_id), path("${dedup_bam.name.replaceAll(/\.bam/, '.mapped_chunk.realcells_only.bam')}"), emit: map_tuple
        tuple val(sample_id), path("${dedup_bam.name.replaceAll(/\.bam/, '.mapped_chunk.realcells_only.bam')}.supplementary.bam"), emit: supplementary_tuple
        tuple val(sample_id), path("${dedup_bam.name.replaceAll(/\.bam/, '.mapped_chunk.realcells_only.bam')}.nosupplementary.bam"), emit: nosupplementary_tuple

    script:
    def realcells_bam = dedup_bam.name.replaceAll(/\.bam/, '.realcells_only.bam')
    def out_bam       = dedup_bam.name.replaceAll(/\.bam/, '.mapped_chunk.realcells_only.bam')
    def tag_manual    = (manual_barcodes) ? """
bash ${baseDir}/bin/tag_manual_barcodes.sh ${manual_barcodes} ${dedup_bam} ${dedup_bam}.tmp.bam
mv ${dedup_bam}.tmp.bam ${realcells_bam}
""" : """
cp ${dedup_bam} ${realcells_bam}
"""
    """
    samtools index -@ ${task.cpus} ${dedup_bam}

    ${tag_manual}
    samtools index -@ ${task.cpus} ${realcells_bam}
    samtools view -@ ${task.cpus} -h -d rc:1 -bo ${realcells_bam}.filtered.bam ${realcells_bam}
    mv ${realcells_bam}.filtered.bam ${realcells_bam}
    samtools index -@ ${task.cpus} ${realcells_bam}

    pbmm2 align -j ${task.cpus} --preset ISOSEQ --sort ${realcells_bam} ${genome_fasta_f} ${out_bam}

    samtools index -@ ${task.cpus} ${out_bam}
    samtools view -@ ${task.cpus} -h -f 2048 -bo ${out_bam}.supplementary.bam ${out_bam}
    samtools index -@ ${task.cpus} ${out_bam}.supplementary.bam
    samtools view -@ ${task.cpus} -h -F 2048 -bo ${out_bam}.nosupplementary.bam ${out_bam}
    samtools index -@ ${task.cpus} ${out_bam}.nosupplementary.bam

    """
}
