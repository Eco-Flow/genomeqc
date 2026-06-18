process RM_CONCAT_DB {
    tag "concat_h5"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
              'https://depot.galaxyproject.org/singularity/pbh5tools:0.8.0--py27heb79e2c_5':
              'biocontainers/pbh5tools:0.8.0--py27heb79e2c_5' }"

    input:
    path h5_files

    output:
    path "dfam_full.h5", emit: h5
    tuple val("${task.process}"), val('<htools5>'),
    eval('htools5 --version | head -1 | cut -d " " -f2'), emit: versions, topic: versions

    script:
    def sorted_files = h5_files.sort().join(' ')
    """
    h5copy -i ${sorted_files} -o dfam_full.h5 -s ./ -d ./
    """
}
