process RM_CONCAT_DB {
    tag "concat_h5"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
              'https://depot.galaxyproject.org/singularity/pbh5tools%3A0.8.0--py27_0':
              'biocontainers/pbh5tools%3A0.8.0--py27_0' }" 

    input:
    path h5_files  

    output:
    path "dfam_full.h5", emit: h5
    tuple val("${task.process}"), val('<htools5>'), 
    eval('htools5 --version | head -1 | cut -d " " -f2'), emit: versions, topic: versions

    script:
    def sorted_files = h5_files.sort().join(' ')
    """
    h5copy -i ${sorted_files} -o dfam_full.h5
    """
}