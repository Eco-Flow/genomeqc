process TREE_SUMMARY {
    tag "$meta.id"
    label 'process_single'

    container 'ecoflowucl/genomeqc_tree:v1.4'
    publishDir "$params.outdir/tree_plots" , mode: "${params.publish_dir_mode}", pattern:"*.pdf"

    input:
    tuple val(meta), path(tree)
    tuple val(meta1), path(geno_busco)
    tuple val(meta2), path(prot_busco)
    path  multiqc_files

    output:
    path( "*.pdf"          ),                 emit: figure
    path( "*.svg"          ),                 emit: figure_svg
    tuple val(meta), path("*.tsv"),           emit: tables
    tuple val(meta), path("tree.nw"),         emit: tree
    path( "versions.yml"    ),                emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args     ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def counts_command = meta.mode == 'genome_anno' ? "gene_overlaps_table.py *.counts.tsv gene_stats.tsv --include-sense --include-antisense" : "touch gene_stats.tsv" // Genome only option needs a gene_stats file, even if it's empty. Should check for a more elegant solution
    def ortho_file = file("species_orthologous_chromosomes.tsv") ? "--ortho_file species_orthologous_chromosomes.tsv" : ''
    def geno_busco_combined = geno_busco ? '''{ head -qn 1 *-genome-busco.batch_summary_modified.txt | head -n 1; tail -q -n 1 *-genome-busco.batch_summary_modified.txt | sed -E 's/\t+/\t/g' | sed 's/\t$//g'; } > Busco_combined_geno.tsv''' : ''
    def prot_busco_combined = prot_busco ? '''{ head -qn 1 *-proteins-busco.batch_summary_modified.txt | head -n 1; tail -q -n 1 *-proteins-busco.batch_summary_modified.txt | sed -E 's/\t+/\t/g' | sed 's/\t$//g'; } > Busco_combined_prot.tsv''' : ''
    def geno_busco_file = geno_busco ? '--busco_geno Busco_combined_geno.tsv' : ''
    def prot_busco_file = prot_busco ? '--busco_prot Busco_combined_prot.tsv' : ''


    """
    #Remove unwanted extensions in the tree file
    sed \'s/\\.prot\\.fa\\.largestIsoform//g\' ${tree}/Species_Tree/SpeciesTree_rooted_node_labels.txt > tree.nw

    echo $ortho_file

    # Combine GENE OVERLAPS outputs
    ${counts_command}

    # Combine the BUSCO outputs and remove empty tabs
    ${geno_busco_combined}
    ${prot_busco_combined}

    # Combine QUAST ouput
    quast_2_table.py *quast.tsv -o Quast_to_plot.tsv -col N50,N90,"Total length","GC (%)","# contigs" -plot_types bar,bar,bar,bar,bar

    rm -f *.batch_summary_modified.txt
    rm -f *.counts.tsv
    rm -f *.quast.tsv

    # Run summary plot
    plot_tree_summary.R \\
    tree.nw \\
    Quast_to_plot.tsv \\
    gene_stats.tsv \\
    n_seqs_above_x_buscos.tsv \\
    $geno_busco_file \\
    $prot_busco_file \\
    $ortho_file \\
    $args

    # Make sure input TSV files are captured as outputs by copying them
    # This "touches" them so Nextflow sees them as process outputs
    # This is necessary because tables are inputs to the SHINY_APP process
    if [ -f "n_seqs_above_x_buscos.tsv" ]; then
        cp n_seqs_above_x_buscos.tsv n_seqs_above_x_buscos_output.tsv
    fi

    if [ -f "species_orthologous_chromosomes.tsv" ]; then
        cp species_orthologous_chromosomes.tsv species_orthologous_chromosomes_output.tsv
    fi


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Perl version: \$(perl --version | grep "version" | sed 's/.*(//g' | sed 's/[)].*//')
        Python version: \$(python3 --version | sed 's/Python //g')
        R version: \$(R --version | head -1 | cut -d" " -f3)
    END_VERSIONS
    """

}
