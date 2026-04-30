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

    # Run TRF per sequence so output is written incrementally.
    # With -ngs, TRF buffers output until a whole sequence is done; a single
    # large chromosome can stall the job for hours with nothing written.
    python3 - << 'PYEOF'
import subprocess, os, tempfile, sys

fasta_in = "${fasta_input}"
dat_out  = "${prefix}.trf.dat"
args     = "${args}".split()

with open(fasta_in) as fh, open(dat_out, 'w') as out:
    name = None
    seq_lines = []
    def run_trf(name, seq_lines):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.fa', delete=False) as tmp:
            tmp.write('>' + name + '\\n')
            tmp.writelines(seq_lines)
            tmpname = tmp.name
        try:
            r = subprocess.run(
                ['trf', tmpname, '2', '7', '7', '80', '10', '50', '500', '-ngs', '-h'] + args,
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
            )
            out.write(r.stdout)
        finally:
            os.unlink(tmpname)
    for line in fh:
        if line.startswith('>'):
            if name:
                run_trf(name, seq_lines)
            name = line[1:].split()[0]
            seq_lines = []
        else:
            seq_lines.append(line)
    if name:
        run_trf(name, seq_lines)
PYEOF
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.trf.dat
    """
}
