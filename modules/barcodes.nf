process BARCODE_CORRECTION {
    label 'process_high'
    publishDir "${params.results_output}qc/correct", mode: 'copy', pattern: '*.json, *.corrected.sorted.tsv'

    input:
        tuple val(sample_id), path(refined_reads_bam)
        path(threeprime_whitelist)
        val barcode_correction_method
        val barcode_correction_percentile

    output:
        tuple val(sample_id), path("${sample_id}.corrected.sorted.bam"), emit: barcode_corrected_tuple
        path "*corrected.sorted*"
        path "*corrected.report*"


    script:
        """
        # Correct step
        if [[ "${barcode_correction_method}" == "percentile" ]]; then
            isoseq correct  -j ${task.cpus} --method "${barcode_correction_method}" --percentile "${barcode_correction_percentile}" --barcodes "${threeprime_whitelist}" "${refined_reads_bam}" "${sample_id}.corrected.bam"
        elif [[ "${barcode_correction_method}" == "knee" ]]; then
            isoseq correct -j ${task.cpus} --method "${barcode_correction_method}" --barcodes "${threeprime_whitelist}" "${refined_reads_bam}" "${sample_id}.corrected.bam"
        else
            echo "Invalid barcode correction method: ${barcode_correction_method}" >&2
            exit 1
        fi

        # Sort step
        samtools sort -@ ${task.cpus} -t CB "${sample_id}.corrected.bam" -o "${sample_id}.corrected.sorted.bam"
        samtools index "${sample_id}.corrected.sorted.bam"

        # BCStats step
        if [[ "${barcode_correction_method}" == "percentile" ]]; then
            isoseq bcstats --method "${barcode_correction_method}" --percentile "${barcode_correction_percentile}" --json "${sample_id}.corrected.sorted.json" -o "${sample_id}.corrected.sorted.tsv" "${sample_id}.corrected.sorted.bam"
        elif [[ "${barcode_correction_method}" == "knee" ]]; then
            isoseq bcstats --method "${barcode_correction_method}" --json "${sample_id}.corrected.sorted.json" -o "${sample_id}.corrected.sorted.tsv" "${sample_id}.corrected.sorted.bam"
        else
            echo "Invalid barcode correction method: ${barcode_correction_method}" >&2
            exit 1
        fi
        """

}

process GET_BARCODES {
    label 'process_low'
    
    input:
    tuple val(sample), path(bam)
    val(N)

    output:
    tuple val(sample), path("barcodes_*.txt"), emit: barcodes_tuple

    script:
        def K = N.toString().length() + 1
        """ 
        	samtools view ${bam} | awk '{ for(i=12;i<=NF;i++) if(\$i ~ /^CB:Z:/) {split(\$i,a,":"); print a[3]} }' | sort | uniq > tmp.txt
            #samtools view ${bam} | grep -o 'CB:Z:[^[:space:]]*' | cut -d: -f3 | sort | uniq > tmp.txt
            split -n l/${N} -d -a ${K} --additional-suffix=.txt tmp.txt barcodes_
        """

}


process SUPSET_BAM {
    label 'process_low'
       
    input:
        tuple val(sample), path(bam), path(barcodes)

    output:
        tuple val(sample), path("*.splited.bam"), emit: chunk_tuple

    script:
    	def bam_name=bam.baseName
    	def barcode_name=barcodes.baseName
        """ 
            samtools view --threads ${task.cpus} --tag-file CB:${barcodes} \
               -o ${bam_name}.${barcode_name}.splited.bam ${bam}
            samtools index -c ${bam_name}.${barcode_name}.splited.bam
        """

}
//DELETE supset_bam_with_bai
process supset_bam_with_bai {
    label 'process_low'
       
    input:
        tuple val(sample), path(bam), path(bai), path(barcodes)

    output:
        tuple val({ "${sample}___${barcodes.simpleName.replaceFirst('barcodes__','')}" }), path("*.splited.bam"), path("*.splited.bam.bai"), emit: per_donor_tuple

    script:
    	def bam_name=bam.baseName
    	def barcode_name=barcodes.baseName.replaceAll('barcodes__','')
        """ 
            samtools view --threads ${task.cpus} --tag-file CB:${barcodes} \
               -o ${bam_name}.${barcode_name}.splited.bam ${bam}
            samtools index ${bam_name}.${barcode_name}.splited.bam
        """

}

process DEDUP_READS {
    label 'process_medium'

    input:
        tuple val(sample_id), path(barcode_corrected_chunk_bam)
        val (b_size)


    output:
        tuple val(sample_id), path("${barcode_corrected_chunk_bam.name.replaceAll(/\.bam/, '.dedup.bam')}"), emit: dedup_tuple

    script:
    """
    tmp_out_bam=${barcode_corrected_chunk_bam.name.replaceAll(/\.bam/, '.dedup.tmp.bam')}
    out_bam=${barcode_corrected_chunk_bam.name.replaceAll(/\.bam/, '.dedup.bam')}
    isoseq groupdedup  -j ${task.cpus} --batch-size ${b_size} --keep-non-real-cells ${barcode_corrected_chunk_bam} \${tmp_out_bam}
    samtools index -@ ${task.cpus} \${tmp_out_bam}
    bash ${baseDir}/scripts/append_to_tag.sh -i \${tmp_out_bam} -t CB:Z -s ${sample_id} -O sam | bash ${baseDir}/scripts/append_to_readname.sh -T CB:Z -O bam -o \${out_bam}


    """
}


process COMBINE_DEDUPS {
    label 'process_low'
    publishDir "${params.results_output}qc/dedup", mode: 'copy'

    input:
        tuple val(sample_id), path(dedup_bam_chunks)


    output:
        tuple val(sample_id), path("${sample_id}.dedup.bam"), path("${sample_id}.dedup.bam.bai"), emit: dedup_tuple

    script:
    """
    echo "test" > test.txt
 	samtools merge -f ${sample_id}.dedup.bam ${dedup_bam_chunks.join(' ')}
    samtools index -@ ${task.cpus} ${sample_id}.dedup.bam

    """
}

process COMBINE_MUPPED {
    label 'process_low'
    publishDir "${params.results_output}qc/mapped", mode: 'copy'

    input:
        tuple val(sample_id), path(mapped_bam_chunks)


    output:
        tuple val(sample_id), path("${sample_id}.mapped.realcells_only.bam"), path("${sample_id}.mapped.realcells_only.bam.bai"), emit: combined_bam_tuple

    script:
    """
 	samtools merge -@ ${task.cpus} -f ${sample_id}.mapped.realcells_only.merged.bam ${mapped_bam_chunks.join(' ')}
    samtools sort -@ ${task.cpus} -o ${sample_id}.mapped.realcells_only.bam ${sample_id}.mapped.realcells_only.merged.bam
    samtools index -@ ${task.cpus} ${sample_id}.mapped.realcells_only.bam
    """
}


process COMBINE_MUPPED_SUPPLEMENTARY {
    label 'process_low'
    publishDir "${params.results_output}qc/mapped", mode: 'copy'

    input:
        tuple val(sample_id), path(supplementary_bam_chunks)

    output:
        tuple val(sample_id), path("${sample_id}.mapped.realcells_only.supplementary.bam"), path("${sample_id}.mapped.realcells_only.supplementary.bam.bai"), emit: combined_supplementary_tuple

    script:
    """
    samtools merge -@ ${task.cpus} -f ${sample_id}.mapped.realcells_only.supplementary.merged.bam ${supplementary_bam_chunks.join(' ')}
    samtools sort -@ ${task.cpus} -o ${sample_id}.mapped.realcells_only.supplementary.bam ${sample_id}.mapped.realcells_only.supplementary.merged.bam
    samtools index -@ ${task.cpus} ${sample_id}.mapped.realcells_only.supplementary.bam
    """
}


process COMBINE_MUPPED_NOSUPPLEMENTARY {
    label 'process_low'
    publishDir "${params.results_output}qc/mapped", mode: 'copy'

    input:
        tuple val(sample_id), path(nosupplementary_bam_chunks)

    output:
        tuple val(sample_id), path("${sample_id}.mapped.realcells_only.nosupplementary.bam"), path("${sample_id}.mapped.realcells_only.nosupplementary.bam.bai"), emit: combined_nosupplementary_tuple

    script:
    """
    samtools merge -@ ${task.cpus} -f ${sample_id}.mapped.realcells_only.nosupplementary.merged.bam ${nosupplementary_bam_chunks.join(' ')}
    samtools sort -@ ${task.cpus} -o ${sample_id}.mapped.realcells_only.nosupplementary.bam ${sample_id}.mapped.realcells_only.nosupplementary.merged.bam
    samtools index -@ ${task.cpus} ${sample_id}.mapped.realcells_only.nosupplementary.bam
    """
}


process BAM_STATS {
    label 'process_low'
    publishDir "${params.results_output}qc/dedup", mode: 'copy'

    input:
        tuple val(sample_id), path(dedup_bam), path("${sample_id}.dedup.bam.bai")
        val barcode_correction_method
        val barcode_correction_percentile
        val min_umi_barcodes  // optional: pass null to skip barcode filtering


    output:
        path "*.dedup.json"
        path "*.dedup.tsv"
        tuple val(sample_id), path("${sample_id}.min_umi_barcodes.txt"), optional: true, emit: min_umi_barcodes_txt


    script:
    def filter_cmd = (min_umi_barcodes != null) ? """
python ${baseDir}/bin/filter_bam_stats_barcodes.py -b ${sample_id}.dedup.tsv -o ${sample_id}.min_umi_barcodes.txt --min_umi ${min_umi_barcodes}
""" : ""
    """
    if [[ "${barcode_correction_method}" == "percentile" ]]; then
      isoseq bcstats  -j ${task.cpus} --method ${barcode_correction_method} --percentile ${barcode_correction_percentile} --json ${sample_id}.dedup.json -o ${sample_id}.dedup.tsv ${sample_id}.dedup.bam
    elif [[ "${barcode_correction_method}" == "knee" ]]; then
      isoseq bcstats  -j ${task.cpus} --method ${barcode_correction_method} --json ${sample_id}.dedup.json -o ${sample_id}.dedup.tsv ${sample_id}.dedup.bam
    else
        echo "Invalid barcode correction method: ${barcode_correction_method}" >&2
        exit 1
    fi

    ${filter_cmd}
    """
}


