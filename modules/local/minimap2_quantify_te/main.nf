process MINIMAP2_QUANTIFY_TE {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/mulled-v2-66534bcbb7031a148b13ccdd4cf9c17fb78049e:74a87b6a4da4c52e7f33e7d9b59a80a517a21a3c-0'
        : 'quay.io/biocontainers/mulled-v2-66534bcbb7031a148b13ccdd4cf9c17fb78049e:74a87b6a4da4c52e7f33e7d9b59a80a517a21a3c-0'}"

    input:
    tuple val(meta), path(genome)
    path(library)

    output:
    tuple val(meta), path("*.tbl"), emit: tbl
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

    te_tbl.py \\
        ${prefix}.paf \\
        ${genome} \\
        --prefix ${prefix} \\
        > ${prefix}.tbl
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.paf
    touch ${prefix}.tbl
    """
}
