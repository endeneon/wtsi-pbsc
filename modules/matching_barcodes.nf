process MATCH_BARCODES{
  label 'process_single'
  publishDir  path: "${params.results_output}deconvolution/sample_assignment/barcode_match/",
          pattern: "combined_barcode_donor_assignments.csv",
          mode: 'copy',
          overwrite: "true"
  publishDir path: "${params.results_output}deconvolution/sample_assignment/barcode_match/",
           pattern: "all_barcode_matches.tsv",
           mode: 'copy',
           overwrite: "true"
  publishDir path: "${params.results_output}deconvolution/sample_assignment/barcode_match/",
           pattern: "multiple_good_barcode_matches.tsv",
           mode: 'copy',
           overwrite: "true"

  input:
    tuple val(meta), path(vireo_list)
    path ref_barcode_list
    val threashold1
    val threashold2

  output:
    path "combined_barcode_donor_assignments.csv", emit: match_barcodes
    path "all_barcode_matches.tsv", emit: all_matches
    path "multiple_good_barcode_matches.tsv", optional: true
    path "versions.yml", emit: versions

  script:
  """
    match-barcodes.py ${ref_barcode_list} ${vireo_list} > all_barcode_matches.tsv
    filter_barcodes_res.py all_barcode_matches.tsv ${threashold1} ${threashold2} combined_barcode_donor_assignments.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
  """
}

process COMBINE_DONOR_ASIGNMENTS{
  label 'process_single'
  publishDir  path: "${params.results_output}deconvolution/sample_assignment/",
          pattern: "donor_assignment.csv",
          mode: 'copy',
          overwrite: "true"

  input:
    path files

  output:
    tuple val("donor_assignment"), path("donor_assignment.csv"), emit: match_barcodes
    path "versions.yml", emit: versions

  script:
  """
    combine_donor_assignments.py vireo_map.tsv combined_gt_donor_assignments_overall.csv combined_barcode_donor_assignments.csv donor_assignment.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
  """
}

process REPLACE_DONOR_ASIGNMENTS{
  label 'process_single'

  input:
    path(donor_asignment)
    path(manual_asignment)

  output:
    path("donor_assignment.renamed.csv"), emit: asignments
    path "versions.yml", emit: versions

  script:
  """
    replace_asignments.py ${donor_asignment} ${manual_asignment} donor_assignment.renamed.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
  """
}

process REMOVE_DONOR_ASIGNMENTS{
  label 'process_single'

  input:
    path(donor_asignment)
    path(donors_to_remove)

  output:
    path("donor_assignment.cleaned.csv"), emit: asignments
    path "versions.yml", emit: versions

  script:
  """
    remove_donor_assignments.py ${donor_asignment} ${donors_to_remove} donor_assignment.cleaned.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
  """
}

process EXTRACT_BARCODES{
  label 'process_single'

  input:
    tuple val(pool_id), val (donor_id), path(vireo_tsv)
    path(donor_asignment)

  output:
    path("*bc_list.txt.gz"), emit: asignments
    path "versions.yml", emit: versions

  script:
  """
    //remove_donor_assignments.py ${donor_asignment} ${donors_to_remove} donor_assignment.cleaned.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
  """
}
