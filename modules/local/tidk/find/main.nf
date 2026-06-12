process TIDK_FIND {
    tag "$meta.id"
    label 'process_low'

    // TODO nf-core: See section in main README for further information regarding finding and adding container addresses to the section below.
    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/tidk:0.2.7--h6872113_0':
        'quay.io/biocontainers/tidk:0.2.7--h6872113_0' }"

    input:
    tuple val(meta), path(fasta)
    val clade

    output:
    tuple val(meta), path("*.tsv")          , emit: tsv         , optional: true
    tuple val("${task.process}"), val('tidk'), eval("tidk --version | sed 's/tidk //'"), emit: versions_tidk, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    tidk build

    tidk \\
        find \\
        --clade $clade \\
        --output $prefix \\
        --dir tidk \\
        $args \\
        $fasta

    mv \\
        tidk/${prefix}_telomeric_repeat_windows.tsv \\
        ${prefix}.tsv \\
        || echo "TSV file was not produced"

    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}.tsv

    """
}
