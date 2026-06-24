process BCFTOOLS_INDEX
{
  label 'process_single'

  input:
    tuple val(pool_id), path(vireo_gt_vcf)

  output:
    tuple val(pool_id), path(vireo_gt_vcf), path("${vireo_gt_vcf}.tbi"), emit: pool_vcf_ch
    path "versions.yml", emit: versions

  script:
  """
    bcftools index -t ${vireo_gt_vcf}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bcftools: \$(bcftools --version 2>&1 | head -n1 | sed 's/^.*bcftools //; s/ .*\$//')
    END_VERSIONS
  """
}

process VIREO_GT_FIX_HEADER
{
  tag "${pool_id}"
  //publishDir  path: "${params.outdir}/deconvolution/infered_genotypes/${pool_id}/",
  //      saveAs: { filename -> 
  //        (filename == 'versions.yml' || filename.endsWith('_infered_genotypes.counts.txt')) ? null : filename 
  //      },
  //      mode: "${params.copy_mode}",
  //      overwrite: "true"
  //if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
  //    container "${params.yascp_container}"
  //} else {
  //    container "${params.yascp_container_docker}"
  //}

  label 'process_single'

  input:
    tuple val(pool_id), path(vireo_gt_vcf)
    path(genome)

  output:
    //tuple val(pool_id), path("${vireo_fixed_vcf}"), path("${vireo_fixed_vcf}.tbi"), emit: gt_pool
    tuple val(pool_id), path("pre_${vireo_fixed_vcf}"), path("pre_${vireo_fixed_vcf}.tbi"), emit: gt_pool
    path "versions.yml", emit: versions

  script:
  sorted_vcf = "${pool_id}_vireo_srt.vcf.gz"
  vireo_fixed_vcf = "${pool_id}_headfix_vireo.vcf.gz"


  """
    # fix header of vireo VCF
    bcftools view -h ${vireo_gt_vcf} > init_head.txt
    sed -i '/^##fileformat=VCFv.*/a ##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">' init_head.txt
    head -n -1 init_head.txt > header.txt
    echo '##INFO=<ID=AD,Number=A,Type=Integer,Description="alternative allele  (variant-by-cell) of reads">' >> header.txt
    echo '##INFO=<ID=DP,Number=1,Type=Integer,Description="depth UMIs for each variant in each cell">' >> header.txt
    echo '##INFO=<ID=PL,Number=1,Type=Integer,Description="depth UMIs for each variant in each cell">' >> header.txt
    echo '##INFO=<ID=OTH,Number=1,Type=Integer,Description="????">' >> header.txt
    echo '##FORMAT=<ID=PL,Number=G,Type=Integer,Description="???">' >> header.txt
    echo '##FORMAT=<ID=AD,Number=G,Type=Integer,Description="????n">' >> header.txt
    echo '##FORMAT=<ID=DP,Number=G,Type=Integer,Description="????n">' >> header.txt
    #samtools faidx ${genome}
    #awk '{print "##contig=<ID="\$1",length="\$2">"}' ${genome}.fai >> header.txt
    tail -n1 init_head.txt >> header.txt

    # sort VCF file (bcftools sort bails out with an error)
    bcftools view ${vireo_gt_vcf} | \
    awk '\$1 ~ /^#/ {print \$0;next} {print \$0 | "sort -k1,1V -k2,2n"}' | \
    bcftools view -Oz -o ${sorted_vcf} -

    #bcftools reheader -h header.txt ${sorted_vcf} | \
    #bcftools view | awk '{gsub(/^chr/, ""); gsub(/ID=chr/, "ID="); print}' | \
    #bcftools view -Oz -o pre_${vireo_fixed_vcf}
    bcftools reheader -h header.txt ${sorted_vcf} | \
    bcftools view -Oz -o pre_${vireo_fixed_vcf}
    tabix -p vcf pre_${vireo_fixed_vcf}
    #bcftools index -t pre_${vireo_fixed_vcf}
    #bcftools +fixref pre_${vireo_fixed_vcf} -Oz -o ${vireo_fixed_vcf} -- -d -f ${genome} -m flip-all
    #tabix -p vcf ${vireo_fixed_vcf}
    #bcftools index -t ${vireo_fixed_vcf}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bcftools: \$(bcftools --version 2>&1 | head -n1 | sed 's/^.*bcftools //; s/ .*\$//')
    END_VERSIONS

  """
}

process GT_MATCH_POOL_AGAINST_PANEL
{
  tag "${pool_id}_vs_${panel_id}"
  publishDir  path: "${params.results_output}deconvolution/sample_assignment/gtmatch/${pool_id}",
          pattern: "*.csv",
          mode: 'copy',
          overwrite: "true"

  //if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
  //    container "${params.yascp_container}"
  //} else {
  //    container "${params.yascp_container_docker}"
  //}

  label 'process_single'

  input:
    tuple val(pool_id), path(vireo_gt_vcf), path(vireo_gt_tbi), val(panel_id), path(ref_gt_vcf), path(ref_gt_csi)

  output:
    tuple val(pool_panel_id), path("${gt_check_output_txt}"), emit:gtcheck_results
    path "versions.yml", emit: versions

  script:
  pool_panel_id = "pool_${pool_id}_panel_${panel_id}"
  panel_filnam = "${ref_gt_vcf}" - (~/\.[bv]cf(\.gz)?$/)
  gt_check_output_txt = "${pool_id}_gtcheck_${panel_filnam}.txt"
  """
    #bcftools isec -n=2 -p isec_res ${ref_gt_vcf} ${vireo_gt_vcf}
    #bcftools view -Oz -o ref_isec.vcf.gz isec_res/0000.vcf
    #bcftools view -Oz -o vireo_isec.vcf.gz isec_res/0001.vcf
    #bcftools index -t ref_isec.vcf.gz
    #bcftools index -t vireo_isec.vcf.gz
    #bcftools gtcheck --no-HWE-prob -g ref_isec.vcf.gz vireo_isec.vcf.gz > ${gt_check_output_txt}
    bcftools gtcheck --no-HWE-prob -g ${ref_gt_vcf} ${vireo_gt_vcf} > ${gt_check_output_txt}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bcftools: \$(bcftools --version 2>&1 | head -n1 | sed 's/^.*bcftools //; s/ .*\$//')
    END_VERSIONS
  """
}

process ASSIGN_DONOR_FROM_PANEL
{
  // sum gtcheck discrepancy scores from multiple ouputput files of the same panel
  tag "${pool_panel_id}"
  label 'process_single'
  publishDir  path: "${params.results_output}deconvolution/sample_assignment/gtmatch/${pool_id}",
          pattern: "*.csv",
          mode: 'copy',
          overwrite: "true"
  //if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
  //    container "${params.yascp_container}"
  //} else {
  //    container "${params.yascp_container_docker}"
  //}

  input:
    tuple val(pool_panel_id), path(gtcheck_output_files)

  output:
    tuple val(pool_id), path("${assignment_table_out}"), emit: gtcheck_assignments
    //path("${score_table_out}", emit: gtcheck_scores)
    path "versions.yml", emit: versions

  

  script:
  (_, pool_id) = ("${pool_panel_id}" =~ /^pool_(\S+)_panel_/)[0]
  score_table_out = "${pool_panel_id}_gtcheck_score_table.csv"
  assignment_table_out = "${pool_panel_id}_gtcheck_donor_assignments.csv"

  """
    gtcheck_assign.py ${pool_panel_id} ${gtcheck_output_files}
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
  """
}

process ASSIGN_DONOR_OVERALL
{
  // decide final donor assignment across different panels from per-panel donor assignments
  tag "${pool_id}"
  label 'process_single'
  publishDir  path: "${params.results_output}deconvolution/sample_assignment/gtmatch/${pool_id}",
          pattern: "*.csv",
          mode: 'copy',
          overwrite: "true"

  //if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
  //    container "${params.yascp_container}"
  //} else {
  //    container "${params.yascp_container_docker}"
  //}

  input:
    tuple val(pool_id), path(gtcheck_assign_files)

  output:
    tuple val(pool_id), path("${donor_assignment_file}"), emit: donor_assignments
    //path(stats_assignment_table_out), emit: donor_match_table
    tuple val(pool_id),path(stats_assignment_table_out), emit: donor_match_table_with_pool_id
    //path("*.csv")
    path "versions.yml", emit: versions

  script:
  donor_assignment_file = "${pool_id}_gt_donor_assignments.csv"
  stats_assignment_table_out = "stats_${pool_id}_gt_donor_assignments.csv"
  """
    gtcheck_assign_summary.py ${donor_assignment_file} ${params.ZSCORE_THRESH} ${params.ZSCORE_DIST_THRESH} ${gtcheck_assign_files}
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        python library csv: \$(python -c "import csv; print(csv.__version__)")
        python library pandas: \$(python -c "import pandas; print(pandas.__version__)")
    END_VERSIONS
  """
}

process COMBINE_ASSIGN
{
  // decide final donor assignment across different panels from per-panel donor assignments
  tag "${pool_id}"
  label 'process_single'
  publishDir  path: "${params.results_output}deconvolution/sample_assignment/gtmatch",
          pattern: "combined_*.csv",
          mode: 'copy',
          overwrite: "true"

  //if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
  //    container "${params.yascp_container}"
  //} else {
  //    container "${params.yascp_container_docker}"
  //}

  input:
    path assignment_table

  output:
    path("combined_*.csv"), emit: donor_match_tables
    path("combined_gt_donor_assignments_overall.csv"), emit: gt_match_table
    path "versions.yml", emit: versions

  script:
  """
    combine_assignments.py ${params.ZSCORE_THRESH} ${params.ZSCORE_DIST_THRESH}
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
  """
}
