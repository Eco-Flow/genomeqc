process BUSCO_SEQS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'oras://community.wave.seqera.io/library/pandas_python:2c576cde050ae1c2'
        : 'community.wave.seqera.io/library/python_pip_pandas:2fd05a70c67560f2'}"

    input:
    tuple val(meta), path(tables)

    output:
    tuple val(meta), path("*.tsv"), emit: table
    tuple val("${task.process}"), val('python'), eval('python3 --version | sed "s/Python //g"'), emit: versions_python, topic: versions

    script:
    def args = task.ext.args ?: ''
    def prefix         = task.ext.prefix ?: "${meta.id}"
    """
    # Count sequences with Complete_BUSCOs above the threshold
    ortho_seqs.py \\
    -i $tables \\
    $args

    """

    stub:
    """
    touch n_seqs_above_x_buscos.tsv
    """
}
