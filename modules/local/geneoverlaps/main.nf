process GENEOVERLAPS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'oras://community.wave.seqera.io/library/r-base_r-dplyr_bioconductor-genomicranges:1e8d4970099749e4'
        : 'community.wave.seqera.io/library/bioconductor-genomicranges_r-dplyr:f1274f1f9e8a019d' }"

    input:
    tuple val(meta), path(gff)

    output:
    tuple val(meta), path("*.summary.tsv"), emit: overlap_detailed_summary
    tuple val(meta), path("*.counts.tsv") , emit: overlap_counts
    tuple val("${task.process}"), val('r_base'), eval('Rscript -e "cat(as.character(getRversion()))"'), emit: versions_r_base, topic: versions
    tuple val("${task.process}"), val('genomicranges'), eval('Rscript -e "cat(as.character(packageVersion(\'GenomicRanges\')))"'), emit: versions_genomicranges, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #Run overlap R script
    gene_overlaps.R $gff ${prefix}.summary.tsv ${prefix}.counts.tsv

    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    echo $args

    touch ${prefix}.summary.tsv
    touch ${prefix}.counts.tsv
    """
}
