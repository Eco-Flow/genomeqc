process TRF {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/trf:4.09.1--h031d066_4'
        : 'quay.io/biocontainers/trf:4.09.1--h031d066_4'}"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.trf.dat"), emit: dat
    tuple val("${task.process}"), val('trf'), val('4.09.1'), topic: versions, emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def fasta_input = fasta.name.endsWith('.gz') ? "${prefix}.fasta" : "$fasta"
    def decompress  = fasta.name.endsWith('.gz') ? "gunzip -c ${fasta} > ${fasta_input}" : ""
    """
    $decompress

    # Split genome into 250 kb chunks (mirroring RepeatMasker's internal TRF batching).
    # Each chunk header embeds the parent sequence name and chunk offset so that
    # reported coordinates can be shifted back to genome space after TRF runs.
    mkdir -p trf_split

    awk -v chunk=250000 '
    BEGIN { n=0; off=0; buf=""; hdr="" }
    /^>/ {
        if (hdr != "" && buf != "") {
            n++; f = sprintf("trf_split/%07d.fa", n)
            print ">" hdr "__OFF__" off > f; print buf > f; close(f)
        }
        hdr = substr(\$0,2); split(hdr,a," "); hdr=a[1]
        off=0; buf=""; next
    }
    {
        buf = buf \$0
        while (length(buf) >= chunk) {
            n++; f = sprintf("trf_split/%07d.fa", n)
            print ">" hdr "__OFF__" off > f
            print substr(buf,1,chunk) > f; close(f)
            off += chunk; buf = substr(buf, chunk+1)
        }
    }
    END {
        if (hdr != "" && buf != "") {
            n++; f = sprintf("trf_split/%07d.fa", n)
            print ">" hdr "__OFF__" off > f; print buf > f; close(f)
        }
    }' ${fasta_input}

    # Run TRF on each chunk; strip the __OFF__ marker from the header and
    # shift start/end coordinates by the chunk offset before appending.
    touch ${prefix}.trf.dat
    for fa in trf_split/*.fa; do
        trf "\${fa}" 2 7 7 80 10 50 500 -ngs -h $args 2>/dev/null \\
        | awk '
            /^@/ {
                name = substr(\$0,2)
                n = split(name, a, "__OFF__")
                seqname = a[1]; off = (n>1) ? a[2]+0 : 0
                print "@" seqname; next
            }
            NF >= 2 { \$1 += off; \$2 += off; print; next }
            { print }
        ' >> ${prefix}.trf.dat || true
    done

    rm -rf trf_split
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.trf.dat
    """
}
