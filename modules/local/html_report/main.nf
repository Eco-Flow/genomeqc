process HTML_REPORT {
    tag "genomeqc_report"
    label 'process_single'

    container 'ecoflowucl/genomeqc_tree:v1.4'
    publishDir "$params.outdir/report", mode: "${params.publish_dir_mode}", pattern: "*.html"

    input:
    path busco_tables,       stageAs: "busco/*"           // batch_summary_modified.txt files (one per species)
    path tidk_tsvs,          stageAs: "tidk/*"            // tidk aposteriori search TSV files
    path tidk_apriori_tsvs,  stageAs: "tidk_apriori/*"   // tidk apriori search TSV files (optional)
    path fcsgx_reports,      stageAs: "fcsgx/*"           // FCS-GX report files (optional)
    path fcsadp_reports,     stageAs: "fcsadp/*"          // FCS-Adaptor report files (optional)
    path tiara_reports,      stageAs: "tiara/*"           // Tiara classification files (optional)
    path busco_seqs_table,   stageAs: "busco_seqs/*"      // ortho_seqs.py output (optional)

    output:
    path "genomeqc_report.html", emit: report
    tuple val("${task.process}"), val('python'), eval('python3 --version | sed "s/Python //g"'), emit: versions_python, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def busco_arg        = busco_tables      ? "--busco_tables busco/*"             : ""
    def tidk_tsv_arg     = tidk_tsvs         ? "--tidk_tsvs tidk/*"                 : ""
    def tidk_apriori_arg = tidk_apriori_tsvs ? "--tidk_apriori_tsvs tidk_apriori/*" : ""
    def fcsgx_arg        = fcsgx_reports     ? "--fcsgx_reports fcsgx/*"            : ""
    def fcsadp_arg       = fcsadp_reports    ? "--fcsadp_reports fcsadp/*"          : ""
    def tiara_arg        = tiara_reports     ? "--tiara_reports tiara/*"            : ""
    def busco_seqs_arg   = busco_seqs_table  ? "--busco_seqs_table busco_seqs/*"    : ""
    """
    generate_report.py \\
        ${busco_arg} \\
        ${tidk_tsv_arg} \\
        ${tidk_apriori_arg} \\
        ${fcsgx_arg} \\
        ${fcsadp_arg} \\
        ${tiara_arg} \\
        ${busco_seqs_arg} \\
        --output genomeqc_report.html
    """
}
