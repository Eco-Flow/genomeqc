process MINIMAP2_TE {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/minimap2:2.28--he4a0461_1'
        : 'biocontainers/minimap2:2.28--he4a0461_1'}"

    input:
    tuple val(meta), path(genome)
    path(library)

    output:
    tuple val(meta), path("*.paf"), emit: paf
    tuple val("${task.process}"), val('minimap2'), eval('minimap2 --version'), topic: versions, emit: versions_minimap2

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    minimap2 \\
        -x asm20 \\
        -t ${task.cpus} \\
        ${args} \\
        ${genome} \\
        ${library} \\
        > ${prefix}.paf
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.paf
    """
}
