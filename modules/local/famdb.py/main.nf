process FAMDB_PY {
    tag "$meta.id"
    label 'process_single'

    //conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/repeatmasker:4.2.2--pl5321hdfd78af_0':
        'biocontainers/repeatmasker:4.2.2--pl5321hdfd78af_0' }"

    input:
    tuple val(meta), path(h5_dir)
    val(lineage)

    output:
    tuple val(meta), path("*.fasta"), emit: famdb_lib
    path "versions.yml"             , emit: versions

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    python /usr/local/share/RepeatMasker/famdb.py \
    -i $h5_dir \
    families -f fasta_name \
    -d \
    $args \
    $lineage > ${lineage}.fasta

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
    famdb.py: \$(python /usr/local/share/RepeatMasker/famdb.py -h | grep version | cut -d" " -f5 | sed 's/.\$//g')
    END_VERSIONS
    """
}
