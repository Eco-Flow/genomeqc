process CREATE_PATH {
    tag "$meta.id"
    label 'process_single'

    conda "conda-forge::coreutils=8.31"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/gnu-wget:1.18--h36e9172_9' :
        'biocontainers/gnu-wget:1.18--h36e9172_9' }"

    input:
    tuple val(meta), val(accession)

    output:
    val meta                 , emit: meta
    path "${meta.id}.txt"     , emit: accession
    path "versions.yml"      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix         = task.ext.prefix ?: "${meta.id}"
    """
    echo $accession > ${prefix}.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        quast: \$(/bin/echo --version 2>&1 | head -n1 | cut -d" " -f4)
    END_VERSIONS
    """ 
}