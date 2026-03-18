process GENE_OVERLAPS {
    tag "$meta.id"
    label 'process_single'
    container 'ecoflowucl/gene_overlap:v1.0'

    input:
    tuple val(meta), path(gff)

    output:
    tuple val(meta), path("*.summary.tsv"), emit: overlap_detailed_summary
    tuple val(meta), path("*.counts.tsv") , emit: overlap_counts
    tuple val("${task.process}"), val('rscript'), eval('    Rscript -e "cat(as.character(getRversion()))"'), emit: versions_rscript, topic: versions
    tuple val("${task.process}"), val('genomicranges'), eval('Rscript -e "cat(as.character(packageVersion(\'GenomicRanges\')))"'), emit: versions_genomicranges, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #Run overlap R script
    gene_overlaps.R $gff ${prefix}.summary.tsv ${prefix}.counts.tsv

    """
}
