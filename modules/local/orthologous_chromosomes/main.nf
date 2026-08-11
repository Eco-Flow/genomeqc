process ORTHOLOGOUS_CHROMOSOMES {
    tag "orthologous_chromosomes"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/b3/b39f468dbf576d7e8e3e2913cb1deaaf172f194bf7c76ce80a2b8940a7c492a4/data'
        : 'community.wave.seqera.io/library/python_pip_pandas:2fd05a70c67560f2'}"

    input:
    path orthogroups_tsv
    path gff_files

    output:
    path "species_orthologous_chromosomes.tsv", emit: species_summary
    path "pairwise_chromosome_orthology.tsv", emit: pairwise_summary
    path "debug_gene_mapping.txt", emit: debug_info
    tuple val("${task.process}"), val('python'), eval('python --version | sed "s/Python //g"'), emit: versions_python, topic: versions
    tuple val("${task.process}"), val('pandas'), eval('python -c "import pandas as pd; print(pd.__version__)"'), emit: versions_pandas, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    # Map orthogroup genes onto their chromosomes via the per-species GFFs,
    # then tally how often chromosome pairs co-occur across species.
    orthologous_chromosomes.py \\
        --orthogroups ${orthogroups_tsv} \\
        --gff ${gff_files} \\
        --pairwise-out pairwise_chromosome_orthology.tsv \\
        --species-out species_orthologous_chromosomes.tsv \\
        --debug-out debug_gene_mapping.txt
    """

    stub:
    """
    touch species_orthologous_chromosomes.tsv
    touch pairwise_chromosome_orthology.tsv
    touch debug_gene_mapping.txt
    """
}
