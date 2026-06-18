/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { MERYL_UNIONSUM                           } from '../modules/nf-core/meryl/unionsum/main'
include { MERYL_COUNT                              } from '../modules/nf-core/meryl/count/main'
include { MERQURY_MERQURY                          } from '../modules/nf-core/merqury/merqury/main'
include { CREATEPATH                              } from '../modules/local/createpath/main'
include { NCBIGENOMEDOWNLOAD                       } from '../modules/nf-core/ncbigenomedownload/main'
include { PIGZ_UNCOMPRESS as UNCOMPRESS_FASTA      } from '../modules/nf-core/pigz/uncompress/main'
include { PIGZ_UNCOMPRESS as UNCOMPRESS_GXF        } from '../modules/nf-core/pigz/uncompress/main'
include { GENOME_ONLY                              } from '../subworkflows/local/genome_only'
include { GENOME_AND_ANNOTATION                    } from '../subworkflows/local/genome_and_annotation'
include { TREESUMMARY as TREE_SUMMARY_GENO_ANNO   } from '../modules/local/treesummary/main'
include { TREESUMMARY as TREE_SUMMARY_GENO        } from '../modules/local/treesummary/main'
include { FASTA_EXPLORE_SEARCH_PLOT_TIDK           } from '../subworkflows/nf-core/fasta_explore_search_plot_tidk/main'
include { DECONTAMINATION                          } from '../subworkflows/local/decontamination'
include { BUSCO_SEQS as BUSCO_SEQS_GENOME_ANNO     } from '../modules/local/buscos_seqs/main'
include { BUSCO_SEQS as BUSCO_SEQS_GENOME          } from '../modules/local/buscos_seqs/main'
include { SHINY_APP as SHINY_APP_GENOME_ANNO       } from '../modules/local/shiny_app/main'
include { SHINY_APP as SHINY_APP_GENOME            } from '../modules/local/shiny_app/main'
include { HTML_REPORT as HTML_REPORT_GENOME_ANNO   } from '../modules/local/html_report/main'
include { HTML_REPORT as HTML_REPORT_GENOME        } from '../modules/local/html_report/main'
include { EXCEL_REPORT as EXCEL_REPORT_GENOME_ANNO } from '../modules/local/excel_report/main'
include { EXCEL_REPORT as EXCEL_REPORT_GENOME      } from '../modules/local/excel_report/main'
include { HITE                                     } from '../modules/local/hite/main'
include { FASTA_ANNOTATE_TE                        } from '../subworkflows/local/fasta_annotate_te/main'
include { TE_TBL_2_TABLE                           } from '../modules/local/te_tbl_2_table/main'
include { MULTIQC                                  } from '../modules/nf-core/multiqc/main'
include { validateInputSamplesheet                 } from '../subworkflows/local/utils_nfcore_genomeqc_pipeline'
include { paramsSummaryMap                         } from 'plugin/nf-schema'
include { paramsSummaryMultiqc                     } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML                   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText                   } from '../subworkflows/local/utils_nfcore_genomeqc_pipeline'
include { multimapChannel                          } from '../subworkflows/local/utils_nfcore_genomeqc_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow GENOMEQC {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    ch_input = ch_samplesheet
                | map { samplesheet ->
                    validateInputSamplesheet(samplesheet) // Input validation (check local subworkflow for how function works)
                }
                | branch { rows ->
                    ncbi  : rows.size == 3 // channel: [ val(meta), val(refseq), val(fastq) ]
                    local : rows.size == 4 // channel: [ val(meta), val(fasta), val(gxf), val(fastq) ]
                }

    //
    // MODULE: Run create_path
    //

    // ch_input.ncbi is now a 3-element tuple, last element is the fastq.
    // We need to remove it before CREATEPATH
    ch_input.ncbi
        | map { meta, refseq, _fq -> tuple( meta, refseq ) }
        | CREATEPATH

    // For NCBIGENOMEDOWNLOAD

    ch_ncbi_input = CREATEPATH.out.accession
                    | multiMap {
                        meta, accession ->
                            meta      : meta
                            accession : accession
                    }

    //
    // MODULE: Run ncbigenomedownlaod for RefSeq IDs
    //

    NCBIGENOMEDOWNLOAD (
        ch_ncbi_input.meta,
        ch_ncbi_input.accession,
        [],
        params.groups
    )

    //
    // Perpare fasta channels
    //

    // fasta. We use mix() here becuase when local files are present,
    // then RefSeq IDs should be missing, and viceversa
    fasta        = ch_input.local
                 | map { meta, fasta, _gxf, _fq -> tuple( meta, fasta) }
                 | mix ( NCBIGENOMEDOWNLOAD.out.fna )

    // Filter fasta files by extension and create channels for each file type
    gz_fasta     = fasta.filter { _meta, fasta_compressed -> fasta_compressed.name.endsWith(".gz") }
    non_gz_fasta = fasta.filter { _meta, fasta_uncompressed -> !fasta_uncompressed.name.endsWith(".gz") }

    // Run module uncompress_fasta and combine channels back
    // together so that all the uncompressed files are in channels
    UNCOMPRESS_FASTA ( gz_fasta )
    ch_fasta     = UNCOMPRESS_FASTA.out.file.mix(non_gz_fasta)

    //
    // Perpare gxf channels
    //

    // gxf. We use mix() here becuase when local files are present,
    // then RefSeq IDs should be missing, and viceversa
    gxf         = ch_input.local
                | map { meta, _fasta, gxf, _fq ->  tuple( meta,  gxf) }
                | mix ( NCBIGENOMEDOWNLOAD.out.gff )

    // Filter gxf files by extension and create channels for each file type
    gz_gxf      = gxf.filter { _meta, gxf_compressed -> gxf_compressed  && gxf_compressed.name.endsWith(".gz")  } // Filter non empty and compressed gxf (channel to be uncompressed)
    non_gz_gxf  = gxf.filter { _meta, gxf_uncompressed -> !gxf_uncompressed || !gxf_uncompressed.name.endsWith(".gz") } // Filter empty and uncompressed gxf (not uncompressed)

    // Run module uncompress_GXF and combine channels back
    // together so that all the uncompressed files are in channels
    UNCOMPRESS_GXF( gz_gxf )
    ch_gxf      = UNCOMPRESS_GXF.out.file.mix(non_gz_gxf)

    //
    // Perpare gxf channels
    //

    // FASTQ file is optional in the samplesheet.
    // First, get it like you do for gxf and fasta

    ch_fastq = ch_input.ncbi
                | map{ meta, _refseq, fq -> tuple( meta, fq ) }
                | mix( ch_input.local.map { meta, _fasta_local, _gxf_local, fq -> tuple( meta, fq ) } )

    //
    // Define multi-channel objects for every process/subworkflow
    //

    // Combine both fasta, gxf and fastq channels into a single multi-channel object
    // using multiMap, so that they are in sync
    // If element (fasta, gxf, fq) is empty, it will return an empty (null) channel
    // Check multimapChannel function below

    ch_input       = ch_fasta // channel: [ val(meta), val(fasta), val(gxf), val(fastq) ]
                   | join(ch_gxf, remainder: true)           // full outer: gxf is optional
                   | join(ch_fastq, remainder: true) // left outer: fastq is optional, drop fastq-only entries

    // Split into two channels according to the presence/absence of an annotation
    ch_input_anno  = ch_input.filter { _meta, _fasta_annotation, gxf_annotation, _fastq ->  gxf_annotation } // gxf is present. Channel will run on genome and annotation
                   | multimapChannel // Notice only fasta channel and gxf are necessary here
    ch_input_geno  = ch_input.filter { _meta, _fasta_genome, gxf_genome, _fastq ->  !gxf_genome }// gxf is missing. Channel will run on genome only
                   | multimapChannel // Notice only fasta channel is necessary here

    // Merqury
    ch_input_merq  = ch_input.filter { _meta, _fasta_merqury, _gxf_merqury, fastq -> fastq } // filter rows where fastq is present
                   | multimapChannel // Notice only fasta and fastq channels are necessary here

    // Decontamination subworkflow
    ch_input_decon = ch_fasta.filter { meta, _fasta_decon -> meta.taxid } // filter rows where taxid is present. Run decon on those

    // For TIDK the ch_fasta channel will work

    //
    // Run DECONTAMINATION
    //

    // If statement in case people give taxids but no database.
    // This way subworkflow won't try to run (otherwise it'll just fail)
    // Add warning in parameter/input validation plugin
    if ( params.gxdb || params.gxdb_manifiest ) {
        DECONTAMINATION (
            ch_input_decon,
            params.ramdisk ?: [],
            params.gxdb ?: [],
            params.gxdb_manifiest ? file(params.gxdb_manifiest) : []
        )
    }

    //
    // Run TIDK
    //

    ch_repeat = params.repeat ? ch_fasta.map { meta, _fasta_repeat -> [ meta, params.repeat ] } : channel.empty()

    if (!params.skip_tidk) {
        FASTA_EXPLORE_SEARCH_PLOT_TIDK (
            ch_fasta,
            ch_repeat
        )
    }

    // Merqury: Evaluate genome assemblies with k-mers and more
    // https://github.com/marbl/merqury
    // Only run if not skipping and fastq is provided in the samplesheet
    // MODULE: MERYL_COUNT
    MERYL_COUNT(
        ch_input_merq.fq,
        params.kvalue
    )
    ch_meryl_db = MERYL_COUNT.out.meryl_db
    // MODULE: MERYL_UNIONSUM
    MERYL_UNIONSUM(
        ch_meryl_db,
        params.kvalue
    )
    ch_meryl_union = MERYL_UNIONSUM.out.meryl_db
    // MODULE: MERQURY_MERQURY
    ch_merqury_inputs = ch_meryl_union.join(ch_input_merq.fasta)

    MERQURY_MERQURY ( ch_merqury_inputs )
    ch_merqury_qv                           = MERQURY_MERQURY.out.assembly_qv
    ch_merqury_stats                        = MERQURY_MERQURY.out.stats
    ch_merqury_spectra_cn_fl_png            = MERQURY_MERQURY.out.spectra_cn_fl_png
    ch_merqury_spectra_asm_fl_png           = MERQURY_MERQURY.out.spectra_asm_fl_png
    ch_hapmers_blob_png                     = MERQURY_MERQURY.out.hapmers_blob_png
    ch_merqury_outputs                      = ch_merqury_qv
                                            | mix(ch_merqury_stats)
                                            | mix(ch_merqury_spectra_cn_fl_png)
                                            | mix(ch_merqury_spectra_asm_fl_png)
                                            | mix(ch_hapmers_blob_png)
                                            | flatMap { _meta, data -> data }

    //
    // SUBWORKFLOW: Annotate transposable elements
    //
    if (params.te == 'hite') {
        HITE ( ch_fasta )
    }

    if (params.te == 'repeatmasker') {
        // Skip download when a pre-staged famdb library is already provided
        ch_rm_db_input = (params.RM_download_db && params.RM_db && !params.famdb_library)
                       ? channel.fromList(params.RM_db)
                           .map { db -> tuple([id: file(db).getBaseName()], db) }
                       : channel.empty()

        // Accepts a single file path or a glob pattern (e.g. '/path/FamDB*')
        ch_famdb_lib_input = params.famdb_library
                           ? channel.fromPath(params.famdb_library)
                               .map { path -> tuple([id: path.baseName], path) }
                           : channel.empty()

        FASTA_ANNOTATE_TE (
            ch_fasta,
            ch_rm_db_input,
            ch_famdb_lib_input,
            params.famdb_lineage ?: '',
            params.run_repeatmodeler,
            params.te_clusterer
        )
    }

    // RepeatMasker .tbl summaries for the HTML/Excel reports (empty if TE annotation was skipped)
    ch_repeatmasker_tbl = (params.te == 'repeatmasker')
                        ? FASTA_ANNOTATE_TE.out.tbl.map { _meta, f -> f }.collect().ifEmpty([[],[]]) // If no repeatmasker results are found, return an empty channel instead of failing
                        : channel.empty()

    // RepeatMasker .tbl summaries for tree plots
    TE_TBL_2_TABLE (
        ch_repeatmasker_tbl.map { f -> tuple([id:'te_table'], f) }
    )

    ch_te_table = TE_TBL_2_TABLE.out.table.ifEmpty([])

    //
    // SUBWORKFLOWS: Run genome only or genome + annotation subworkflows
    //
    // Run genome only or genome + gxf
    if (params.genome_only) {
        GENOME_ONLY (
            ch_input_anno.fasta.mix(ch_input_geno.fasta)
        )
        ch_multiqc_files = ch_multiqc_files
                         | mix(GENOME_ONLY.out.quast_results.map { _meta, results -> results })
                         | mix(GENOME_ONLY.out.busco_short_summaries.map { _meta, txt -> txt })

        //
        // MODULE: Run HTML REPORT (genome only mode)
        //
        ch_report_busco_go = GENOME_ONLY.out.busco_batch_summaries
                           | map { _meta, f -> f }
                           | collect
                           | first
        ch_report_tidk_tsv_go        = params.skip_tidk ? channel.value([]) : FASTA_EXPLORE_SEARCH_PLOT_TIDK.out.aposteriori_tsv.map { _meta, f -> f }.collect().first()
        ch_report_tidk_apriori_go    = (params.skip_tidk || !params.repeat) ? channel.value([]) : FASTA_EXPLORE_SEARCH_PLOT_TIDK.out.apriori_tsv.map { _meta, f -> f }.collect().first()

        ch_fcsgx_go  = (params.gxdb || params.gxdb_manifiest) ? DECONTAMINATION.out.fcs_gx_report.map { _meta, f -> f }.collect().first()  : channel.value([])
        ch_fcsadp_go = (params.gxdb || params.gxdb_manifiest) ? DECONTAMINATION.out.adaptor_report.map { _meta, f -> f }.collect().first()  : channel.value([])
        ch_tiara_go  = (params.gxdb || params.gxdb_manifiest) ? DECONTAMINATION.out.tiara_cleaned.map  { _meta, f -> f }.collect().first()  : channel.value([])

        BUSCO_SEQS_GENOME (
            GENOME_ONLY.out.buscos_per_seqs.map { tables -> [[id:"tables"], tables] }
        )

        HTML_REPORT_GENOME (
            ch_report_busco_go,
            channel.value([]),     // no protein BUSCO in genome-only mode
            ch_report_tidk_tsv_go,
            ch_report_tidk_apriori_go,
            ch_fcsgx_go,
            ch_fcsadp_go,
            ch_tiara_go,
            BUSCO_SEQS_GENOME.out.table.map { _meta, f -> f }.ifEmpty([]),
            ch_repeatmasker_tbl.ifEmpty([])
        )

        //
        // MODULE: Run EXCEL REPORT (genome only mode)
        //
        ch_excel_quast_go = GENOME_ONLY.out.quast_tsv.map { _meta, f -> f }.collect()
        ch_tidk_go        = params.skip_tidk ? channel.value([]) : FASTA_EXPLORE_SEARCH_PLOT_TIDK.out.aposteriori_tsv.map { _meta, f -> f }.collect().first()

        EXCEL_REPORT_GENOME (
            ch_report_busco_go,
            channel.value([]),     // no protein BUSCO in genome-only mode
            ch_excel_quast_go,
            [],     // no AGAT in genome-only mode
            ch_tidk_go,
            ch_fcsgx_go,
            ch_fcsadp_go,
            ch_tiara_go,
            BUSCO_SEQS_GENOME.out.table.map { _meta, f -> f }.ifEmpty([]),     // no busco_seqs in genome-only mode
            ch_repeatmasker_tbl.ifEmpty([])
        )
    } else {
        GENOME_ONLY (
            ch_input_geno.fasta
        )
        GENOME_AND_ANNOTATION (
            ch_input_anno.fasta,
            ch_input_anno.gxf
        )
        ch_multiqc_files = ch_multiqc_files
                         | mix(GENOME_AND_ANNOTATION.out.quast_results.map { _meta, results -> results })
                         | mix(GENOME_AND_ANNOTATION.out.busco_short_summaries_prot.map { _meta, txt -> txt })

        //
        // MODULE: run BUSCO SEQS
        //
        // Number of sequences with more than x complete single copy buscos
        // this should depend on whether protein mode was used or not
        if(!params.skip_busco){
        BUSCO_SEQS_GENOME_ANNO(
            GENOME_AND_ANNOTATION.out.buscos_per_seqs.map { tables -> [[id:"tables"], tables] }
        )

        BUSCO_SEQS_GENOME(
            GENOME_ONLY.out.buscos_per_seqs.map { tables -> [[id:"tables"], tables] }
        )

        // Prepare channels for tree plot
        ch_tree_genome_anno = GENOME_AND_ANNOTATION.out.tree_data
                            | concat(BUSCO_SEQS_GENOME_ANNO.out.table.map { _meta, table -> table})
                            | collect
        ch_tree_genome      = GENOME_ONLY.out.tree_data
                            | concat(BUSCO_SEQS_GENOME.out.table.map { _meta, table -> table})
                            | collect
        }

        // Optional channel for HTML report: empty list if BUSCO_SEQS_GENOME_ANNO produced no output
        ch_busco_seqs_ga_file = BUSCO_SEQS_GENOME_ANNO.out.table
                              | mix (BUSCO_SEQS_GENOME.out.table)
                              | map { _meta, f -> f }
                              | ifEmpty([]) // If no busco seqs are found, return an empty channel instead of failing

        //
        // MODULE: Run TREE SUMMARY
        //
        // Prepare busco channel for genome and annotation
        // First for genome completness
        ch_busco_geno_anno1 = GENOME_AND_ANNOTATION.out.busco_short_summaries_geno
                            | map { _meta, file -> file }
                            | collect
                            | map { files -> tuple( [id:"busco_geno_anno"], files )}
        // Then for annotation completeness
        ch_busco_geno_anno2 = GENOME_AND_ANNOTATION.out.busco_short_summaries_prot
                            | map { _meta, file -> file }
                            | collect
                            | map { files -> tuple( [id:"busco_geno_anno"], files )}
        // Combine both channels into a multi-channel object
        ch_busco_geno_anno  = ch_busco_geno_anno1.join(ch_busco_geno_anno2)
                            | multiMap {
                                meta, geno_files, prot_files ->
                                    geno      : geno_files ? tuple( meta, geno_files ) : [[],[]]
                                    prot      : prot_files ? tuple( meta, prot_files ) : [[],[]]
                            }
        // Prepare busco channel for genome only
        ch_busco_geno       = GENOME_ONLY.out.busco_short_summaries
                            | map { _meta, file -> file }
                            | collect
                            | map { files -> tuple( [id:"busco_geno"], files )}
                            | ifEmpty([[],[]]) // If no busco results are found, return an empty channel instead of failing

        ch_busco_geno       = GENOME_ONLY.out.busco_short_summaries
                            | map { _meta, file -> file }
                            | collect
                            | map { files -> tuple( [id:"busco_geno"], files )}
                            | ifEmpty([[],[]]) // If no busco results are found, return an empty channel instead of failing

        // Run TREE SUMMARY for genome and annotation
        if(!params.skip_busco) {
        TREE_SUMMARY_GENO_ANNO (
            GENOME_AND_ANNOTATION.out.orthofinder,
            ch_busco_geno_anno.geno,
            ch_busco_geno_anno.prot,
            ch_te_table,
            ch_tree_genome_anno
        )

        // Run TREE SUMMARY for genome only
        TREE_SUMMARY_GENO (
            GENOME_ONLY.out.orthofinder,
            ch_busco_geno, // If no busco results are found, return an empty channel instead of failing
            [[],[]], // No busco proteins for genome only (busco runs on genome)
            ch_te_table,
            ch_tree_genome
        )

        //
        // MODULE: Run SHINY APP
        //
        // Prepare script with functions channel
        ch_functions = channel.fromPath("$projectDir/bin/tree_functions.R", checkIfExists: true)
        ch_app       = channel.fromPath("$projectDir/bin/shiny_app.R", checkIfExists: true)

        // For genome and annotation
        SHINY_APP_GENOME_ANNO (
            TREE_SUMMARY_GENO_ANNO.out.tables.join(TREE_SUMMARY_GENO_ANNO.out.tree, by:0),
            ch_functions,
            ch_app
        )

        // For genome only
        SHINY_APP_GENOME (
            TREE_SUMMARY_GENO.out.tables.join(TREE_SUMMARY_GENO.out.tree, by:0),
            ch_functions,
            ch_app
        )
        }

        //
        // MODULE: Run HTML REPORT (genome + annotation mode)
        //
        ch_report_busco = GENOME_AND_ANNOTATION.out.busco_short_summaries_geno
                        | map { _meta, f -> f }
                        | mix( GENOME_ONLY.out.busco_batch_summaries.map { _meta, f -> f } )
                        | collect
                        | first
        // Protein BUSCO only exists for annotated genomes; ifEmpty keeps the
        // report running when no annotations are present in this branch.
        ch_report_busco_prot = GENOME_AND_ANNOTATION.out.busco_short_summaries_prot
                        | map { _meta, f -> f }
                        | collect
                        | ifEmpty( [] )
                        | first
        ch_tidk                = params.skip_tidk ? channel.value([]) : FASTA_EXPLORE_SEARCH_PLOT_TIDK.out.aposteriori_tsv.map { _meta, f -> f }.collect().first()
        ch_report_tidk_apriori = (params.skip_tidk || !params.repeat) ? channel.value([]) : FASTA_EXPLORE_SEARCH_PLOT_TIDK.out.apriori_tsv.map { _meta, f -> f }.collect()

        ch_fcsgx  = (params.gxdb || params.gxdb_manifiest) ? DECONTAMINATION.out.fcs_gx_report.map { _meta, f -> f }.collect().first()  : channel.value([])
        ch_fcsadp = (params.gxdb || params.gxdb_manifiest) ? DECONTAMINATION.out.adaptor_report.map { _meta, f -> f }.collect().first()  : channel.value([])
        ch_tiara  = (params.gxdb || params.gxdb_manifiest) ? DECONTAMINATION.out.tiara_cleaned.map  { _meta, f -> f }.collect().first()  : channel.value([])

        HTML_REPORT_GENOME_ANNO (
            ch_report_busco,
            ch_report_busco_prot,
            ch_tidk,
            ch_report_tidk_apriori,
            ch_fcsgx,
            ch_fcsadp,
            ch_tiara,
            ch_busco_seqs_ga_file,
            ch_repeatmasker_tbl
        )

        //
        // MODULE: Run EXCEL REPORT (genome + annotation mode)
        //
        ch_excel_quast  = GENOME_AND_ANNOTATION.out.quast_tsv.map { _meta, f -> f }
                        | mix( GENOME_ONLY.out.quast_tsv.map { _meta, f -> f } )
                        | collect
        ch_excel_agat   = GENOME_AND_ANNOTATION.out.agat_stats.map { _meta, f -> f }.collect().ifEmpty([])

        EXCEL_REPORT_GENOME_ANNO (
            ch_report_busco,
            ch_report_busco_prot,
            ch_excel_quast,
            ch_excel_agat.ifEmpty([]),
            ch_tidk,
            ch_fcsgx,
            ch_fcsadp,
            ch_tiara,
            ch_busco_seqs_ga_file,
            ch_repeatmasker_tbl
        )
    }

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name: 'nf_core_'  +  'genomeqc_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))

    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'genomeqc'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    emit:
    multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
