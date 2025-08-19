process SHINY_APP {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
    'https://depot.galaxyproject.org/singularity/ubuntu:22.04' :
    'nf-core/ubuntu:22.04' }"

    input:
    tuple val(meta), path(tables)
    tuple val(meta), path(tree)
    path(functions)
    path(app)


    output:
    tuple val(meta), path("app/shiny_app.sh"), emit: shiny_app
    path("app"), emit: shiny_app_files
    path "versions.yml"           , emit: versions

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def docker_url   = "quay.io/fduarte001/genomeqc_tree:0.4"
    def results_path = file(params.outdir).toAbsolutePath()
    """
    mkdir app

    # Pick a free port starting at 8000
    cat <<'EOF' > shiny_app.sh
    PORT=8000
    while lsof -i :\$PORT >/dev/null 2>&1; do
        PORT=\$((PORT+1))
    done
    EOF

    echo 'echo "Using port \$PORT"' >> shiny_app.sh

    # Mount directory is executable directory (\$0)
    echo 'cd \$(dirname \$0)' >> shiny_app.sh

    echo 'CONTAINER_ID=\$(docker run -d -v \$(pwd):/app -p 8000:8000 $docker_url)' >> shiny_app.sh
    echo 'sleep 2' >> shiny_app.sh

    # Ensure the container is stopped when script exits
    cat <<'EOF' >> shiny_app.sh
    cleanup() {
        echo "Stopping container \$CONTAINER_ID"
        podman stop "\$CONTAINER_ID" >/dev/null 2>&1
    }
    trap cleanup EXIT
    EOF

    # Make sure app can be opened in any OS (Darwin is for mac)
    cat <<'EOF' >> shiny_app.sh
    OS_TYPE=\$(uname)
    if [[ "\$OS_TYPE" == "Darwin" ]]; then
        open http://localhost:8000
    elif [[ "\$OS_TYPE" == "Linux" ]]; then
        xdg-open http://localhost:8000
    elif [[ "\$OS_TYPE" == "MINGW"* || "\$OS_TYPE" == "CYGWIN"* ]]; then
        start http://localhost:8000
    else
        echo "Please open your browser at http://localhost:8000"
    fi
    EOF

    chmod +x shiny_app.sh

    mv *.tsv app/
    mv tree.nw app/
    mv *.R app/
    mv shiny_app.sh app/

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
    python: \$(bash --version | head -n1 | cut -d" " -f4)
    END_VERSIONS
    """
}
