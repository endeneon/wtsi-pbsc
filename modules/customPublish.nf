process customPublish {
    cache false
    label 'process_single'


    input:
      path(toPublish)
      val(publishDest)

    output:
      val("${publishDest}"), emit: output_dir
      path('DONE.txt')


    script:
      """
      fs=(${toPublish.join(' ')})
      mkdir -p ${publishDest}
      for f in "\${fs[@]}"; do
        if [[ -d \$f ]]; then
          if [[ -d "${publishDest}\${f}" ]]; then rm -r "${publishDest}\${f}"; fi;
          cp -Lr \$f ${publishDest}
        elif [[ -f \$f ]]; then
          cp \$f ${publishDest}
        fi;
      done;
      echo 'DONE' > DONE.txt
      """

}
