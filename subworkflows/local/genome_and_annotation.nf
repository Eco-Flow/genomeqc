
include { AGAT_CONVERTSPGXF2GXF               } from '../../modules/nf-core/agat/convertspgxf2gxf'
include { AGAT_SPKEEPLONGESTISOFORM           } from '../../modules/nf-core/agat/spkeeplongestisoform'
include { BUSCO_BUSCO as BUSCO_GENOME         } from '../../modules/nf-core/busco/busco/main'
include { BUSCO_BUSCO as BUSCO_PROTEINS       } from '../../modules/nf-core/busco/busco/main'
include { QUAST                               } from '../../modules/nf-core/quast/main'
include { AGAT_SPSTATISTICS                   } from '../../modules/nf-core/agat/spstatistics/main'
include { GENOMEANNOTATIONBUSCOIDEOGRAM    } from '../../modules/local/genomeannotationbuscoideogram/main'
include { GFFREAD                             } from '../../modules/nf-core/gffread/main'
include { GFFREAD as GFFREAD_VALIDATE         } from '../../modules/nf-core/gffread/main'
include { ORTHOFINDER as ORTHOFINDER_V3       } from '../../modules/nf-core/orthofinder/main'
include { ORTHOFINDERV2                      } from '../../modules/local/orthofinderv2/main'
include { GENEOVERLAPS                       } from '../../modules/local/geneoverlaps/main'
include { ORTHOLOGOUS_CHROMOSOMES             } from '../../modules/local/orthologous_chromosomes'
include { GAWK as GAWK_GENO                   } from '../../modules/nf-core/gawk/main'
include { GAWK as GAWK_PROT                   } from '../../modules/nf-core/gawk/main'

workflow GENOME_AND_ANNOTATION {

    take:
    ch_fasta // channel: [ val(meta), [ fasta ] ]
    ch_gxf   // channel: [ val(meta), [ gxf ] ]
    ch_busco_db // channel: [ val(lineage) ]

    main:
    ch_fasta.view { "Running ${it[0]} on genome and annotation mode"}

    ch_versions  = channel.empty()

    // For tree plot
    ch_tree_data = channel.empty()

    //
    // MODULE: Run AGAT convertspgxf2gxf or GFFREAD validate
    //

    // Fix and standarize GXF
    if ( params.val_tool == "agat" ) {
        AGAT_CONVERTSPGXF2GXF (
            ch_gxf
        )
        ch_gxf_agat  = AGAT_CONVERTSPGXF2GXF.out.output_gff
    } else if ( params.val_tool == "gffread" ) {
        GFFREAD_VALIDATE (
            ch_gxf,
            []
        )
        ch_gxf_agat  = GFFREAD_VALIDATE.out.gffread_gff
    }

    //
    // MODULE: Run AGAT longest isoform
    //


    AGAT_SPKEEPLONGESTISOFORM (
        ch_gxf_agat,
        []

    )

    // Get longest isoform from gff
    ch_gxf_long  = AGAT_SPKEEPLONGESTISOFORM.out.gff


    //
    // Prepare input multichannel
    //

    // Combine inputs (fasta, gff from AGAT (unfiltered) and gff from AGAT_SPKEEPLONGESTISOFORM (filtered)))
    // into a single multichannel so that they are in sync
    ch_input     = ch_fasta
        | combine(ch_gxf_agat, by:0) // by:0 | Only combine when both channels share the same id
        | combine(ch_gxf_long, by:0)
        | multiMap {
            meta, fasta, gxf_unfilt, gxf_filt -> // "null" probably not necessary
                fasta      : fasta      ? tuple( meta, file(fasta)      ) : null // channel: [ val(meta), [ fasta ] ]
                gxf_unfilt : gxf_unfilt ? tuple( meta, file(gxf_unfilt) ) : null // channel: [ val(meta), [ gxf ] ], unfiltered
                gxf_filt   : gxf_filt   ? tuple( meta, file(gxf_filt)   ) : null // channel: [ val(meta), [ gxf ] ], filtered for longest isoform
        }

    //
    // Run AGAT Spstatistics
    //

    AGAT_SPSTATISTICS (
        ch_input.gxf_unfilt
    )

    //
    // MODULE: Run gene overlap module
    //

    GENEOVERLAPS {
        ch_input.gxf_filt
    }
    ch_tree_data = ch_tree_data.mix(GENEOVERLAPS.out.overlap_counts.collect { _meta, file -> file })

    //
    // MODULE: Run Quast
    //

    QUAST (
        ch_input.fasta,
        [[],[]],
        ch_input.gxf_unfilt
    )

    // For tree

    ch_tree_data = ch_tree_data.mix(QUAST.out.tsv.map { tuple -> tuple[1] })

    //
    // MODULE: Run GFFREAD
    //

    GFFREAD (
        ch_input.gxf_filt,
        ch_input.fasta.map { _meta, fasta -> fasta}
    )

    //
    // MODULE: Run Orthofinder
    //

    // Prepare orthofinder input channel
    ortho_ch     = GFFREAD.out.gffread_fasta
        | map { _meta, fasta ->
            fasta // We only need the fastas
        }
        | collect // Collect all fasta in a single tuple
        | filter { fastas ->
            fastas.size() >= 3 // Ensure we have at least 4 genomes for orthofinder, otherwise it won't run
        }
        | map { fastas ->
            [[id:'orthofinder', mode:'genome_anno'], fastas]
        }

    // Run orthofinder
    if (params.ortho_version == 'v3') {
        ORTHOFINDER_V3 (
            ortho_ch,
            [[],[]]
        )
        ch_orthofinder = ORTHOFINDER_V3.out.orthofinder
    } else if (params.ortho_version == 'v2' ) {
        ORTHOFINDERV2 (
            ortho_ch
        )
        ch_orthofinder = ORTHOFINDERV2.out.orthofinder
    }

    //
    // MODULE: Run ORTHOLOGOUS_CHROMOSOMES
    //

    ORTHOLOGOUS_CHROMOSOMES (
        ch_orthofinder.map { _meta, folder ->
            file("${folder}/Orthogroups/Orthogroups.tsv")
        },
        AGAT_SPKEEPLONGESTISOFORM.out.gff.map { _meta, gff -> gff }.collect()
    )
    //ch_tree_data = ch_tree_data.mix(ORTHOLOGOUS_CHROMOSOMES.out.species_summary)

    //
    // MODULE: Run BUSCO for genome annotation
    //

    if(!params.skip_busco) {
        BUSCO_GENOME (
            ch_fasta,
            'genome',
            params.busco_lineage,
            ch_busco_db,
            params.busco_config ?: [],
            params.busco_clean ?: []
        )

        //
        // MODULE: Run BUSCO for proteins
        //

        BUSCO_PROTEINS (
            GFFREAD.out.gffread_fasta,
            'proteins',
            params.busco_lineage,
            ch_busco_db,
            params.busco_config ?: [],
            params.busco_clean ?: []
        )

        //
        // GAWK
        //
        // Use GAWK to change ID from file name to meta.id
        // For BUSCO genome
        GAWK_GENO (
            BUSCO_GENOME.out.batch_summary,
            [],
            false
        )

        // For BUSCO protein
        GAWK_PROT (
            BUSCO_PROTEINS.out.batch_summary,
            [],
            false
        )

        //
        // Plot BUSCO ideogram
        //

        // Prepare BUSCO output
        ch_busco_full_table = BUSCO_PROTEINS.out.full_table
                            | map { meta, full_tables ->
                                def lineages = full_tables.toString().split('/')[-2].replaceAll('run_', '').replaceAll('_odb\\d+', '')
                                [meta.id, lineages, full_tables]
                            }
                            | groupTuple(by: 0)
                            | map { id, lineages, full_tables ->
                                [id, lineages.flatten(), full_tables.flatten()]
                            }

        // Add genome to channel
        fnaChannel_busco    = ch_input.fasta
                            | map { meta, fasta ->
                                [meta.id, fasta]
                            }

        // Prepare GXF channel of ideogram
        ch_gxf_busco        = ch_input.gxf_filt
                            | map { meta, gxf ->
                                [meta.id, gxf]
                            }

        // Combine BUSCO, AGAT, and genome outputs
        ch_plot_input       = ch_busco_full_table
                            | join(fnaChannel_busco)
                            | join(ch_gxf_busco)
                            | flatMap { genusspeci, lineages, full_tables, fasta, gxf ->
                                lineages.withIndex().collect { lineage, index ->
                                    [genusspeci, lineage, full_tables[index], fasta, gxf]
                                }
                            }

        GENOMEANNOTATIONBUSCOIDEOGRAM ( ch_plot_input )
    }

    emit:
    orthofinder                = ch_orthofinder         // channel: [ val(meta), [folder] ]
    tree_data                  = ch_tree_data.flatten().collect()
    quast_results              = QUAST.out.results                   // channel: [ val(meta), [tsv] ]
    busco_short_summaries_geno = !params.skip_busco ? GAWK_GENO.out.output : Channel.empty()
    busco_short_summaries_prot = !params.skip_busco ? GAWK_PROT.out.output : Channel.empty()
    quast_tsv                  = QUAST.out.tsv                       // channel: [ val(meta), path(tsv) ]
    agat_stats                 = AGAT_SPSTATISTICS.out.stats_txt     // channel: [ val(meta), path(txt) ]
    orthologous_chromosomes    = ORTHOLOGOUS_CHROMOSOMES.out.species_summary // channel: [ path(tsv) ]
    buscos_per_seqs            = !params.skip_busco ? GENOMEANNOTATIONBUSCOIDEOGRAM.out.busco_mappings.collect { meta, table -> table} : channel.empty() // channel: [ val(meta), [csv] ]
    versions                   = ch_versions                   // channel: [ versions.yml ]
}
