process FAMDB_PY {
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
    tuple val("${task.process}"), val('famdb.py'), eval("python /usr/local/share/RepeatMasker/famdb.py -h | grep version | cut -d' ' -f5 | sed 's/.\$//'"), emit: versions_famdb_py, topic: versions

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    def term = lineage ?: 'root'

    """
    python /usr/local/share/RepeatMasker/famdb.py \\
        -i ./ \\
        families --ancestors --descendants --curated $term -f fasta_name \\
        $args \\
        > ${term}.fasta
    """
}