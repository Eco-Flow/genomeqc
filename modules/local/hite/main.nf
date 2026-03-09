process HITE {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "docker.io/kanghu/hite:3.3.3"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*_hite_results") , emit: hite_results
    path "versions.yml"      , emit: versions

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Unzip the genome and make sure it does not have internal new line characters.
    if [ -f *.gz ]; then
      gunzip -c "$fasta" > myunzip.fa
      #myunzip.fa=\$(gunzip -c "$fasta")
      awk '/^>/ { print (NR==1 ? "" : RS) \$0; next } { printf "%s", \$0 } END { printf RS }' myunzip.fa > genome_line_removal.fasta
    else
      awk '/^>/ { print (NR==1 ? "" : RS) \$0; next } { printf "%s", \$0 } END { printf RS }' $fasta > genome_line_removal.fasta
    fi

    # Capture the current working directory
    mydir=`pwd`

    # Create the output directory
    mkdir -p \${mydir}/${prefix}_hite_results

    newpath=`realpath genome_line_removal.fasta`

    cd /HiTE

    echo \$TMPDIR

    python main.py \\
    --genome \${newpath} \\
    --out_dir \${mydir}/${prefix}_hite_results \\
    --thread ${task.cpus} \\
    --work_dir \$TMPDIR
    $args

    cat <<-END_VERSIONS > \${mydir}/versions.yml
    "${task.process}":
       Python version: \$(python --version | cut -f 2 -d " ")
        HiTE version: 3.2.0
       Repeat Masker version: \$(RepeatMasker | grep version | cut -f 3 -d " ")
       Repeat Modeler version: \$(RepeatModeler | grep /opt/conda/envs/HiTE/share/RepeatModeler/RepeatModeler | cut -f 3 -d " ")
        LTRPipeline version: \$(LTRPipeline -version)
    END_VERSIONS
    """
}
