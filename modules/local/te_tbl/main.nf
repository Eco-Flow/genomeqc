process TE_TBL {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/repeatmasker:4.2.2--pl5321hdfd78af_0'
        : 'biocontainers/repeatmasker:4.2.2--pl5321hdfd78af_0'}"

    input:
    tuple val(meta), path(paf)
    tuple val(meta2), path(genome)

    output:
    tuple val(meta), path("*.tbl"), emit: tbl

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix   = task.ext.prefix   ?: "${meta.id}"
    def min_mapq = task.ext.min_mapq ?: 0
    def min_aln  = task.ext.min_aln  ?: 50
    """
    te_tbl.py \\
        ${paf} \\
        ${genome} \\
        --prefix ${prefix} \\
        --min-mapq ${min_mapq} \\
        --min-aln  ${min_aln} \\
        > ${prefix}.tbl
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.tbl
    """
}
