

process MPILEUP {
    label 'process_single'
    publishDir "${params.results_output}deconvolution/mpileup", mode: 'copy'

    input:
        tuple val(sample_id), path(bam), path(bam_bai)
        path(ref_gen)
    output:
        tuple val(sample_id), path(bam), path(bam_bai), path("${sample_id}__barcodes.txt"), path("${sample_id}__piled_up_reads.vcf")
    script:
    """
        samtools view ${bam} | awk '{ for(i=12;i<=NF;i++) if(\$i ~ /^CB:Z:/) {split(\$i,a,":"); print a[3]} }' | sort | uniq > ${sample_id}__barcodes.txt
        # Step 1: Generate VCF of observed SNPs using bcftools mpileup and call
        bcftools mpileup \
        -f ${ref_gen} \
        -q 20 -Q 20 \
        -a AD,DP \
        -Ou ${bam} | \
        bcftools call -mv -Ov -o ${sample_id}__piled_up_reads.vcf
    """
}

process SUBSET_VCF {
    label 'process_single'
    publishDir "${params.results_output}deconvolution/mpileup", mode: 'copy'

    input:
        tuple val(sample_id), path(bam), path(bam_bai), path(sample_id__barcodes), path(sample_id__piled_up_reads)
        path(subset_regions_bed)
    output:
        tuple val(sample_id), path(bam), path(bam_bai), path(sample_id__barcodes), path("${sample_id}__piled_up_reads__subset.vcf.gz")
    script:
    """
        bgzip -c ${sample_id__piled_up_reads} > ${sample_id}__tmp.vcf.gz
        tabix -p vcf ${sample_id}__tmp.vcf.gz
        bcftools view -R ${subset_regions_bed} ${sample_id}__tmp.vcf.gz -Oz -o ${sample_id}__piled_up_reads__subset.vcf.gz
    """
}

process CELLSNP {
    label 'process_low'
    container "https://depot.galaxyproject.org/singularity/cellsnp-lite:1.2.3--ha0c3a46_6"
    publishDir "${params.results_output}deconvolution/cellsnp", mode: 'copy'

    input:
        tuple val(sample_id), path(bam), path(bam_bai), path(barcodes), path(piled_up_reads)
    output:
        tuple val(sample_id),path("cellsnp__${sample_id}")
    script:
    """
        # Step 2: Run CellSNP-lite to extract SNPs per cell
        cellsnp-lite \
        -s ${bam} \
        -O cellsnp__${sample_id} \
        -b ${barcodes} \
        -R ${piled_up_reads} \
        -p $task.cpus \
        --minMAF 0.01 \
        --minCOUNT 1 \
        --gzip \
        --cellTAG CB \
        --UMItag None
    """
}



process VIREO {
    label 'process_medium'

    container "https://depot.galaxyproject.org/singularity/vireosnp:0.5.9--pyh7e72e81_0"

    publishDir "${params.results_output}deconvolution/vireo", mode: 'copy', pattern: "{vireo__*,barcodes__*.tsv}"
    

    input:
        tuple val(sample_id),path(cellsnp),val(nr_samples)
    output:
        tuple val(sample_id), path("barcodes__*.tsv"), emit: barcodes_tuple
        tuple val(sample_id), path("${sample_id}.bc_list.txt.gz"), emit: barcode_list
        path("vireo__${sample_id}"), emit: vireo_results
        tuple val(sample_id), path("vireo__${sample_id}/GT_donors.vireo.vcf.gz"), emit: sample_donor_vcf//, path("vireo__${sample_id}/GT_donors.vireo.vcf.gz.csi"), emit: sample_donor_vcf
        tuple val(sample_id), path("vireo__${sample_id}/donor_ids.tsv"), emit: sample_donor_ids

    script:
    """
        # Step 3: Run Vireo for donor deconvolution without genotypes
        vireo \
        -c ${cellsnp} \
        -N ${nr_samples} \
        -o vireo__${sample_id} \
        --randSeed 1 \
        --nInit 200 \
        -p $task.cpus

        #Split the donor barcodes in an independent files for next step of bam splits.
        awk 'NR > 1 && \$2 != "unassigned" && \$2 != "doublet" {print > ("barcodes__" \$2 ".tsv")}' vireo__${sample_id}/donor_ids.tsv
        cat barcodes__*.tsv | awk -F'\t' -v prefix="${sample_id}_" 'BEGIN {OFS="\t"} NF >= 2 {print \$1, prefix\$2}' > ${sample_id}.bc_list.txt
        gzip ${sample_id}.bc_list.txt
    """
}

