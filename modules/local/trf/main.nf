process TRF {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/trf:4.09.1--h031d066_4'
        : 'quay.io/biocontainers/trf:4.09.1--h031d066_4'}"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.trf.dat"), emit: dat
    tuple val("${task.process}"), val('trf'), val('4.09.1'), topic: versions, emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def fasta_input = fasta.name.endsWith('.gz') ? "${prefix}.fasta" : "$fasta"
    def decompress  = fasta.name.endsWith('.gz') ? "gunzip -c ${fasta} > ${fasta_input}" : ""
    """
    $decompress

    trf \\
        ${fasta_input} \\
        2 7 7 80 10 50 500 \\
        -ngs -h \\
        $args \\
        > ${prefix}.trf.dat || true
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.trf.dat
    """
}
