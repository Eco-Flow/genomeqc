include { QUAST                               } from '../../../modules/nf-core/quast/main'
include { BUSCO_BUSCO                         } from '../../../modules/nf-core/busco/busco/main'
include { GENOMEBUSCOIDEOGRAM                 } from '../../../modules/local/genomebuscoideogram/main'
include { ORTHOFINDER as ORTHOFINDER_V3       } from '../../../modules/nf-core/orthofinder/main'
include { ORTHOFINDERV2                       } from '../../../modules/local/orthofinderv2/main'
include { BUSCO_TSV_TO_GFF                    } from '../../../modules/local/busco_tsv_to_gff/main'
include { ORTHOLOGOUS_CHROMOSOMES             } from '../../../modules/local/orthologous_chromosomes'
include { GAWK                                } from '../../../modules/nf-core/gawk/main'

workflow GENOME_ONLY {

    take:
    ch_fasta    // channel: [ val(meta), [ fasta ] ]
    ch_busco_db // channel: path | []

    main:
    ch_fasta.view { "Running ${it[0]} on genome only mode"}

    ch_versions   = channel.empty()

    // For tree plot
    ch_tree_data = channel.empty()

    //
    // MODULE: Run Quast
    //

    QUAST (
        ch_fasta,
        [[],[]],
        [[],[]]
    )
    ch_tree_data = ch_tree_data.mix(QUAST.out.tsv.map { tuple -> tuple[1] })

    if (!params.skip_busco) {
        BUSCO_BUSCO (
            ch_fasta,
            "genome", // hardcoded, other options ('proteins', 'transcriptome') make no sense
            params.busco_lineage,
            ch_busco_db,
            params.busco_config ?: [],
            params.busco_clean ?: []
        )
        //ch_tree_data  = ch_tree_data.mix(BUSCO_BUSCO.out.batch_summary.collect { meta, file -> file })

        //
        // GAWK
        //
        // Use GAWK to change ID from file name to meta.id

        GAWK (
            BUSCO_BUSCO.out.batch_summary,
            [],
            false
        )
        ch_tree_data  = ch_tree_data.mix(GAWK.out.output.collect { _meta, file -> file })

        //
        // BUSCO Ideogram
        //

        ch_full_table = BUSCO_BUSCO.out.full_table

        // Combined ch_fasta and BUSCO output channel into a single channel for ideogram
        ch_input_ideo = ch_fasta
                      | combine(ch_full_table, by:0)


        GENOMEBUSCOIDEOGRAM (
            ch_input_ideo
        )

        //
        // Orthofinder
        //

        // Prepare data
        ch_busco_proteins = BUSCO_BUSCO.out.single_copy_faa
                          | flatMap { meta, faas ->
                                         faas.collect { faa -> [meta, file(faa)]  }
                          }
                          | collectFile { meta, faas ->
                                            [ "${meta.id}.fasta", faas ]
                          }
                          | collect
                          | filter { file_paths ->
                                        file_paths.size() >= 3 // Ensure there are enough BUSCO proteins, otherwise skip orthofinder
                          }
                          | map { file_paths ->
                                    [[ id: 'orthofinder', mode: 'genome' ], file_paths.toSorted { a, b -> a.name <=> b.name }] // for deterministic behaviour
                          }

        //Run orthofinder
        if (params.ortho_version == 'v3') {
            ORTHOFINDER_V3 (
                ch_busco_proteins,
                [[],[]]
            )
            ch_orthofinder = ORTHOFINDER_V3.out.orthofinder
        } else if (params.ortho_version == 'v2' ) {
            ORTHOFINDERV2 (
                ch_busco_proteins
            )
            ch_orthofinder = ORTHOFINDERV2.out.orthofinder
        }
        // Transform tsv to gff for orthologous chromosomes module
        BUSCO_TSV_TO_GFF (
            BUSCO_BUSCO.out.busco_dir
        )

        //
        // MODULE: Run ORTHOLOGOUS_CHROMOSOMES
        //

        ORTHOLOGOUS_CHROMOSOMES (
            ch_orthofinder.map { _meta, folder ->
                file("${folder}/Orthogroups/Orthogroups.tsv")
            },
            BUSCO_TSV_TO_GFF.out.gff.map { _meta, gff -> gff }.collect()
        )
        //ch_tree_data = ch_tree_data.mix(ORTHOLOGOUS_CHROMOSOMES.out.species_summary)
    }

    emit:
    orthofinder             = !params.skip_busco ? ch_orthofinder : channel.empty()        // channel: [ val(meta), [folder] ]
    tree_data               = !params.skip_busco ? ch_tree_data.flatten().collect().map { files -> files.toSorted { a, b -> a.name <=> b.name } } : channel.empty() // sort for deterministic behaviour
    quast_results           = QUAST.out.results                   // channel: [ val(meta), [tsv] ]
    busco_short_summaries   = !params.skip_busco ? BUSCO_BUSCO.out.short_summaries_txt : channel.empty() // channel: [ val(meta), [txt] ]
    buscos_per_seqs         = !params.skip_busco ? GENOMEBUSCOIDEOGRAM.out.busco_mappings.collect { meta, table -> table}.map { tables -> tables.toSorted { a, b -> a.name <=> b.name } } : channel.empty() // channel: [ csv ]
    busco_batch_summaries   = !params.skip_busco ? GAWK.out.output : channel.empty()                     // channel: [ val(meta), path(tsv) ] — species-named batch summaries
    quast_tsv               = QUAST.out.tsv                       // channel: [ val(meta), path(tsv) ]

}
