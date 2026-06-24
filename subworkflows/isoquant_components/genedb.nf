

process create_genedb_fasta_perChr {
  label 'process_single'

  input:
      tuple val(chrom), path(gtf_f), path(fasta_f)
  output:
      tuple val(chrom), path("${chrom}.gtf.db"), path("${chrom}.fa"), path("${chrom}.fa.fai")
  script:
  """
  awk -v chrom="${chrom}" '{if(\$1 ~ /^#/){print; next} else {if (\$1==chrom){print}} }' ${gtf_f} > "${chrom}.gtf"
  python ${baseDir}/scripts/create_genedb.py -g "${chrom}.gtf" -o "${chrom}.gtf.db"
  samtools faidx ${fasta_f} ${chrom} > "${chrom}.fa"
  samtools faidx "${chrom}.fa"
  """
}
workflow genedb_perChr_wf {
  take:
    chrom_ch
    gtf_f
    genome_fasta_f
  main:
    chrom_ch
    .map {chrom -> [chrom,params.gtf_f,params.genome_fasta_f]}
    .set {chrom_genedb_fasta_chr_input_ch}
    chrom_genedb_fasta_chr_ch=create_genedb_fasta_perChr(chrom_genedb_fasta_chr_input_ch)
  emit:
    chrom_genedb_fasta_chr_ch

}
