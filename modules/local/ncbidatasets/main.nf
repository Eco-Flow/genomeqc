process NCBIDATASETS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    // TODO: replace with the container line produced by building a Wave container
    // (community.wave.seqera.io) for conda-forge::ncbi-datasets-cli=18.33.1 + conda-forge::unzip=6.0.
    // The biocontainers/galaxydepot image (quay.io/biocontainers/ncbi-datasets-cli:14.26.0) is stale
    // (May 2023) and no longer works against the current NCBI Datasets API.
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/ncbi-datasets-cli_unzip:03bbdda8a37f3942':
        'community.wave.seqera.io/library/ncbi-datasets-cli_unzip:309cc8f32cdb32b2' }"

    input:
    tuple val(meta), val(accession)

    output:
    tuple val(meta), path("*.fna.gz"), emit: fasta
    tuple val(meta), path("*.gff.gz"), emit: gff, optional: true
    tuple val("${task.process}"), val('ncbidatasets'), eval("datasets --version"), topic: versions, emit: versions_ncbidatasets

    when:
    task.ext.when == null || task.ext.when

    script:
    def args      = task.ext.args ?: ''
    def prefix    = task.ext.prefix ?: "${meta.id}"
    def is_refseq  = accession.startsWith('GCF_')
    def include_ds = is_refseq ? 'genome,gff3' : 'genome'
    """
    datasets download genome accession ${accession} \\
        $args \\
        --include ${include_ds} \\
        --filename ${prefix}.zip

    unzip -p ${prefix}.zip ncbi_dataset/data/${accession}/*.fna | gzip -n > ${prefix}.fna.gz

    if ${is_refseq}; then
        unzip -p ${prefix}.zip ncbi_dataset/data/${accession}/genomic.gff | gzip -n > ${prefix}.gff.gz
    fi

    rm ${prefix}.zip
    """

    stub:
    def prefix    = task.ext.prefix ?: "${meta.id}"
    def is_refseq = accession.startsWith('GCF_')
    """
    echo "" | gzip -n > ${prefix}.fna.gz
    ${is_refseq ? "echo \"\" | gzip -n > ${prefix}.gff.gz" : ''}
    """
}
