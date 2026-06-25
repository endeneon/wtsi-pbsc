nextflow.enable.dsl=2

process BAM_TO_BIGWIG {
    label 'process_medium'
    // deeptools is NOT in the default Iso-Seq container (wtsi_pbsc_tools.sif only
    // ships samtools + bedtools, and no bedGraphToBigWig). Pull a dedicated image
    // instead, following the same per-process container pattern as SQANTI3.
    // bamCoverage reads chromosome sizes from the BAM header, so no external
    // hg38.chrom.sizes file is required.
    container 'https://depot.galaxyproject.org/singularity/deeptools:3.5.6--pyhdfd78af_0'
    publishDir "${params.results_output}results/bigwig", mode: 'copy'

    input:
        // Final genome-aligned, deduplicated, real-cells-only BAM + its index
        // (COMBINE_MUPPED.out.combined_bam_tuple).
        tuple val(sample_id), path(bam), path(bai)

    output:
        tuple val(sample_id), path("${sample_id}.mapped.realcells_only.rpkm.bw"), emit: bigwig_tuple

    script:
    """
    bamCoverage \\
        --bam ${bam} \\
        --outFileName ${sample_id}.mapped.realcells_only.rpkm.bw \\
        --outFileFormat bigwig \\
        --binSize 20 \\
        --normalizeUsing RPKM \\
        --numberOfProcessors ${task.cpus}
    """
}
