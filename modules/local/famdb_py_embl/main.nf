process FAMDB_PY_EMBL {
    tag "$meta.id"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/repeatmasker:4.2.2--pl5321hdfd78af_0':
        'biocontainers/repeatmasker:4.2.2--pl5321hdfd78af_0' }"

    input:
    tuple val(meta), path(h5_dir)
    val(lineage)

    output:
    tuple val(meta), path("*.fasta"), emit: famdb_lib

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def term = lineage ?: 'root'

    """
    python /usr/local/share/RepeatMasker/famdb.py \\
        -i ./ \\
        families --descendants $term -f embl \\
        $args \\
        | famdb_embl_to_fasta.py \\
        > ${term}.fasta
    """

    stub:
    def term = lineage ?: 'root'
    """
    touch ${term}.fasta
    """
}
