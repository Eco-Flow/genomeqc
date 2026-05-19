process HTML_REPORT {
    tag "genomeqc_report"
    label 'process_single'

    container 'ecoflowucl/genomeqc_tree:v1.4'
    publishDir "$params.outdir/report", mode: "${params.publish_dir_mode}", pattern: "*.html"

    input:
    path busco_tables,       stageAs: "busco/*"         // batch_summary_modified.txt files (one per species)
    path tidk_tsvs,          stageAs: "tidk/*"          // tidk aposteriori search TSV files
    path tidk_apriori_tsvs,  stageAs: "tidk_apriori/*"  // tidk apriori search TSV files (optional)

    output:
    path "genomeqc_report.html", emit: report
    tuple val("${task.process}"), val('python'), eval('python3 --version | sed "s/Python //g"'), emit: versions_python, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def busco_arg         = busco_tables      ? "--busco_tables busco/*"                  : ""
    def tidk_tsv_arg      = tidk_tsvs         ? "--tidk_tsvs tidk/*"                      : ""
    def tidk_apriori_arg  = tidk_apriori_tsvs ? "--tidk_apriori_tsvs tidk_apriori/*"      : ""
    """
    generate_report.py \\
        ${busco_arg} \\
        ${tidk_tsv_arg} \\
        ${tidk_apriori_arg} \\
        --output genomeqc_report.html
    """
}
