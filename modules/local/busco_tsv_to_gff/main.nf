process BUSCO_TSV_TO_GFF {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/python:3.9--1'
        : 'quay.io/biocontainers/python:3.9--1'}"

    input:
    tuple val(meta), path(busco_dir)

    output:
    tuple val(meta), path("${meta.id}_busco.gff"), emit: gff
    tuple val(meta), path("${meta.id}_busco_stats.json"), emit: stats
    //tuple val("${task.process}"), val('python'), eval('python3 --version | sed "s/Python //g"'), emit: versions_python, topic: versions

    script:
    """
    # Convert a BUSCO full_table.tsv into a GFF3 of gene locations plus a JSON stats summary
    busco_tsv_to_gff.py ${busco_dir} ${meta.id}
    """

    stub:
    """
    touch ${meta.id}_busco.gff
    touch ${meta.id}_busco_stats.json
    """
}
