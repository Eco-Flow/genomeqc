process CREATEPATH {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/gnu-wget:1.18--h36e9172_9' :
        'biocontainers/gnu-wget:1.18--h36e9172_9' }"

    input:
    tuple val(meta), val(accession)

    output:
    tuple val (meta), path("*.txt"), emit: accession

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix         = task.ext.prefix ?: "${meta.id}"
    """
    echo $accession > ${prefix}.txt
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    echo $args

    touch ${prefix}.txt
    """
}
