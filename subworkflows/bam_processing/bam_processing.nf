include { SPLIT_READS; REMOVE_PRIMER; TAG_BAM; REFINE_READS } from '../../modules/fltnc.nf'
include {BARCODE_CORRECTION; GET_BARCODES; SUPSET_BAM; DEDUP_READS; COMBINE_DEDUPS; COMBINE_MUPPED; COMBINE_MUPPED_SUPPLEMENTARY; COMBINE_MUPPED_NOSUPPLEMENTARY; BAM_STATS} from '../../modules/barcodes.nf'

include { PBMM2 } from '../../modules/pbmm2.nf'

workflow DEDUP_ONLY {
    main:
        // Load sample IDs from the sample sheet and point to published corrected BAMs
        Channel
            .fromPath(params.input_samples_path)
            .splitCsv(sep: ',', header: true)
            .map { it -> [it.sample_id, file("${params.results_output}qc/correct/${it.sample_id}.corrected.sorted.bam")] }
            .set { corrected_bam_ch }

        GET_BARCODES(corrected_bam_ch, params.number_of_chunks)
        barcode_channel = GET_BARCODES.out.barcodes_tuple.transpose()
        combined_ch = corrected_bam_ch.combine(barcode_channel, by: 0)
        SUPSET_BAM(combined_ch)
        DEDUP_READS(SUPSET_BAM.out.chunk_tuple, params.dedup_batch_size)

        deduped_chunks_ch = DEDUP_READS.out.dedup_tuple.groupTuple(size: params.number_of_chunks)
        COMBINE_DEDUPS(deduped_chunks_ch)
        BAM_STATS(COMBINE_DEDUPS.out.dedup_tuple, params.barcode_correction_method, params.barcode_correction_percentile, params.min_umi_barcodes ?: null)

    emit:
        dedup_reads = COMBINE_DEDUPS.out.dedup_tuple
}


workflow MAPPING_ONLY {
    main:
        // Load sample IDs from the sample sheet and point to published dedup BAMs
        Channel
            .fromPath(params.input_samples_path)
            .splitCsv(sep: ',', header: true)
            .map { it -> [it.sample_id, file("${params.results_output}qc/dedup/${it.sample_id}.dedup.bam")] }
            .set { dedup_bam_ch }

        dedup_bam_with_bai_ch = dedup_bam_ch
            .map { sid, bam -> [sid, bam, file("${bam}.bai")] }

        BAM_STATS(dedup_bam_with_bai_ch, params.barcode_correction_method, params.barcode_correction_percentile, params.min_umi_barcodes ?: null)

        // Re-split combined dedup BAMs into chunks for parallel mapping
        GET_BARCODES(dedup_bam_ch, params.number_of_chunks)
        barcode_channel = GET_BARCODES.out.barcodes_tuple.transpose()
        combined_ch = dedup_bam_ch.combine(barcode_channel, by: 0)
        SUPSET_BAM(combined_ch)

        // Map chunks — dedup already done, so go straight to PBMM2
        if (params.min_umi_barcodes) {
            pbmm2_ch = SUPSET_BAM.out.chunk_tuple
                .combine(BAM_STATS.out.min_umi_barcodes_txt, by: 0)
                .multiMap { sid, bam, bc ->
                    bam_tuple: tuple(sid, bam)
                    barcodes:  bc
                }
            PBMM2(pbmm2_ch.bam_tuple, params.genome_fasta_f, pbmm2_ch.barcodes)
        } else {
            PBMM2(SUPSET_BAM.out.chunk_tuple, params.genome_fasta_f, [])
        }

        mapped_chunks_ch = PBMM2.out.map_tuple.groupTuple(size: params.number_of_chunks)
        COMBINE_MUPPED(mapped_chunks_ch)

        supplementary_chunks_ch = PBMM2.out.supplementary_tuple.groupTuple(size: params.number_of_chunks)
        COMBINE_MUPPED_SUPPLEMENTARY(supplementary_chunks_ch)

        nosupplementary_chunks_ch = PBMM2.out.nosupplementary_tuple.groupTuple(size: params.number_of_chunks)
        COMBINE_MUPPED_NOSUPPLEMENTARY(nosupplementary_chunks_ch)

    emit:
        mapped_reads = COMBINE_MUPPED.out.combined_bam_tuple
        supplementary_reads = COMBINE_MUPPED_SUPPLEMENTARY.out.combined_supplementary_tuple
        nosupplementary_reads = COMBINE_MUPPED_NOSUPPLEMENTARY.out.combined_nosupplementary_tuple
}


workflow BAM_PROCESSING {
    main:
      /// Obtaining (sample_id,bam_file) tuples from the input_samples.csv file
      Channel
        .fromPath(params.input_samples_path)
        .splitCsv(sep: ',', header: true)
        .map { it -> [it.sample_id, it.long_read_path] } // Create a tuple with bam_path and sample_id
        .set { hifi_bam_tuples }

      /// Every process from now on outputs a (sample_id,bam_file) tuple which is fed on to the next process
      SPLIT_READS(hifi_bam_tuples, params.skera_primers)
      REMOVE_PRIMER(SPLIT_READS.out.split_reads_tuple, params.tenx_primers)
      TAG_BAM(REMOVE_PRIMER.out.removed_primer_tuple)
      REFINE_READS(TAG_BAM.out.tagged_tuple, params.tenx_primers, params.min_polya_length)
      //barcode correction
      BARCODE_CORRECTION(REFINE_READS.out.refined_reads, params.threeprime_whitelist, params.barcode_correction_method, params.barcode_correction_percentile)
      GET_BARCODES(BARCODE_CORRECTION.out.barcode_corrected_tuple, params.number_of_chunks)
      barcode_channel=GET_BARCODES.out.barcodes_tuple.transpose()
      combined_ch = BARCODE_CORRECTION.out.barcode_corrected_tuple.combine(barcode_channel, by: 0)
      SUPSET_BAM(combined_ch)
      DEDUP_READS(SUPSET_BAM.out.chunk_tuple, params.dedup_batch_size)
      //these three should create combined dedup files and their stats
      deduped_chunks_ch = DEDUP_READS.out.dedup_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_DEDUPS(deduped_chunks_ch)
      BAM_STATS(COMBINE_DEDUPS.out.dedup_tuple, params.barcode_correction_method, params.barcode_correction_percentile, params.min_umi_barcodes ?: null)

      //mapping — feed per-sample barcode list to PBMM2 only when MIN_UMI_BARCODES is set
      if (params.min_umi_barcodes) {
          pbmm2_ch = DEDUP_READS.out.dedup_tuple
              .combine(BAM_STATS.out.min_umi_barcodes_txt, by: 0)
              .multiMap { sid, bam, bc ->
                  bam_tuple: tuple(sid, bam)
                  barcodes:  bc
              }
          PBMM2(pbmm2_ch.bam_tuple, params.genome_fasta_f, pbmm2_ch.barcodes)
      } else {
          PBMM2(DEDUP_READS.out.dedup_tuple, params.genome_fasta_f, [])
      }

      mapped_chunks_ch=PBMM2.out.map_tuple.groupTuple(size: params.number_of_chunks) //Adding size here to avoid waiting for all chunks across all samples to finish mapping before starting to combine. Combining runs now as soon as all chunks for a given sample are done mapping.
      COMBINE_MUPPED(mapped_chunks_ch)

      supplementary_chunks_ch = PBMM2.out.supplementary_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_MUPPED_SUPPLEMENTARY(supplementary_chunks_ch)

      nosupplementary_chunks_ch = PBMM2.out.nosupplementary_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_MUPPED_NOSUPPLEMENTARY(nosupplementary_chunks_ch)
    emit:
    mapped_reads = COMBINE_MUPPED.out.combined_bam_tuple
    supplementary_reads = COMBINE_MUPPED_SUPPLEMENTARY.out.combined_supplementary_tuple
    nosupplementary_reads = COMBINE_MUPPED_NOSUPPLEMENTARY.out.combined_nosupplementary_tuple
}


workflow BAM_PROCESSING_SEGMENTED {
    main:
      /// Obtaining (sample_id, segmented_bam) tuples from the input_samples.csv file.
      /// Input BAMs are ALREADY segmented (i.e. the output of `pbskera split`), so the
      /// SPLIT_READS (skera) step is skipped and processing starts from REMOVE_PRIMER (lima).
      Channel
        .fromPath(params.input_samples_path)
        .splitCsv(sep: ',', header: true)
        .map { it -> [it.sample_id, file(it.long_read_path)] } // Create a tuple with sample_id and the segmented bam path
        .set { segmented_bam_tuples }

      /// Start from primer removal since reads are already segmented
      REMOVE_PRIMER(segmented_bam_tuples, params.tenx_primers)
      TAG_BAM(REMOVE_PRIMER.out.removed_primer_tuple)
      REFINE_READS(TAG_BAM.out.tagged_tuple, params.tenx_primers, params.min_polya_length)
      //barcode correction
      BARCODE_CORRECTION(REFINE_READS.out.refined_reads, params.threeprime_whitelist, params.barcode_correction_method, params.barcode_correction_percentile)
      GET_BARCODES(BARCODE_CORRECTION.out.barcode_corrected_tuple, params.number_of_chunks)
      barcode_channel=GET_BARCODES.out.barcodes_tuple.transpose()
      combined_ch = BARCODE_CORRECTION.out.barcode_corrected_tuple.combine(barcode_channel, by: 0)
      SUPSET_BAM(combined_ch)
      DEDUP_READS(SUPSET_BAM.out.chunk_tuple, params.dedup_batch_size)
      //these three should create combined dedup files and their stats
      deduped_chunks_ch = DEDUP_READS.out.dedup_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_DEDUPS(deduped_chunks_ch)
      BAM_STATS(COMBINE_DEDUPS.out.dedup_tuple, params.barcode_correction_method, params.barcode_correction_percentile, params.min_umi_barcodes ?: null)

      //mapping — feed per-sample barcode list to PBMM2 only when MIN_UMI_BARCODES is set
      if (params.min_umi_barcodes) {
          pbmm2_ch = DEDUP_READS.out.dedup_tuple
              .combine(BAM_STATS.out.min_umi_barcodes_txt, by: 0)
              .multiMap { sid, bam, bc ->
                  bam_tuple: tuple(sid, bam)
                  barcodes:  bc
              }
          PBMM2(pbmm2_ch.bam_tuple, params.genome_fasta_f, pbmm2_ch.barcodes)
      } else {
          PBMM2(DEDUP_READS.out.dedup_tuple, params.genome_fasta_f, [])
      }

      mapped_chunks_ch=PBMM2.out.map_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_MUPPED(mapped_chunks_ch)

      supplementary_chunks_ch = PBMM2.out.supplementary_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_MUPPED_SUPPLEMENTARY(supplementary_chunks_ch)

      nosupplementary_chunks_ch = PBMM2.out.nosupplementary_tuple.groupTuple(size: params.number_of_chunks)
      COMBINE_MUPPED_NOSUPPLEMENTARY(nosupplementary_chunks_ch)
    emit:
    mapped_reads = COMBINE_MUPPED.out.combined_bam_tuple
    supplementary_reads = COMBINE_MUPPED_SUPPLEMENTARY.out.combined_supplementary_tuple
    nosupplementary_reads = COMBINE_MUPPED_NOSUPPLEMENTARY.out.combined_nosupplementary_tuple
}
