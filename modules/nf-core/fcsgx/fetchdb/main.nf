process FCSGX_FETCHDB {
    tag "$manifest"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ncbi-fcs-gx:0.5.4--h4ac6f70_1':
        'biocontainers/ncbi-fcs-gx:0.5.4--h4ac6f70_1' }"

    input:
    val manifest // URL of manifest. Should not stage locally.

    output:
    path "$prefix"      , emit: database
    path "versions.yml" , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // def args = task.ext.args ?: ''
    def basename = manifest.toString().tokenize('/')[-1].tokenize('?')[0]
    prefix = task.ext.prefix ?: "gxdb_${basename}"
    """
    sync_files.py \\
        get \\
        --mft $manifest \\
        --dir $prefix

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fcs_gx: \$( gx --help | sed '/build/!d; s/.*:v//; s/-.*//' )
    END_VERSIONS
    """

    stub:
    // def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "gxdb_${basename}"
    """
    touch ${prefix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fcs_gx: \$( gx --help | sed '/build/!d; s/.*:v//; s/-.*//' )
    END_VERSIONS
    """
}
