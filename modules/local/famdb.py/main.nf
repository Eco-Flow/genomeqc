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
    # Derive the db prefix from the first staged .h5 file.
    # famdb.py -i expects a prefix, not a directory:
    #   dfam38-1_full.0.h5, dfam38-1_full.1.h5  →  prefix = ./dfam38-1_full
    #   RepeatMaskerLib.h5                        →  prefix = ./RepeatMaskerLib
    h5=\$(ls *.h5 | sort | head -1)
    db_prefix=\$(echo "\${h5}" | sed 's/\\.[0-9]*\\.h5\$//' | sed 's/\\.h5\$//')

    python /usr/local/share/RepeatMasker/famdb.py \\
        -i "./\${db_prefix}" \\
        families $term -f fasta_name \\
        $args \\
        > ${term}.fasta
    """
}