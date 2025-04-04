
include { QUAST                               } from '../../modules/nf-core/quast/main'
include { BUSCO_BUSCO                         } from '../../modules/nf-core/busco/busco/main'
include { GENOME_ONLY_BUSCO_IDEOGRAM          } from '../../modules/local/genome_only_busco_ideogram'
include { ORTHOFINDER                         } from '../../modules/nf-core/orthofinder/main'

workflow GENOME_ONLY {

    take:
    ch_fasta // channel: [ val(meta), [ fasta ] ]

    main:
    ch_fasta.view { "Running ${it[0]} on genome only mode"}

    ch_versions   = Channel.empty()

    QUAST ( 
        ch_fasta,
        [[],[]],
        [[],[]]
    )
    ch_versions   = ch_versions.mix(QUAST.out.versions.first())

    BUSCO_BUSCO (
        ch_fasta,
        "genome", // hardcoded, other options ('proteins', 'transcriptome') make no sense
        params.busco_lineage,
        params.busco_lineages_path ?: [],
        params.busco_config ?: []
    )
    ch_versions   = ch_versions.mix(BUSCO_BUSCO.out.versions.first())
    ch_full_table = BUSCO_BUSCO.out.full_table

    // Combined ch_fasta and BUSCO output channel into a single channel for ideogram
    ch_input_ideo = ch_fasta
                  | combine(ch_full_table, by:0)


    GENOME_ONLY_BUSCO_IDEOGRAM (
        ch_input_ideo
    )
    ch_versions   = ch_versions.mix(GENOME_ONLY_BUSCO_IDEOGRAM.out.versions.first())


    ch_busco_proteins = BUSCO_BUSCO.out.prodigal_prots

    ch_busco_proteins.view()



    ch_busco_proteins
    .view { meta, file -> "Debug input: meta=$meta, file=$file" }


renamed_files = ch_busco_proteins
    .map { meta, file -> 
        def new_name = "${meta.id}.predicted.faa"
        def original_path = file.toString()
        def parent_dir = file.getParent()
        def new_file = "${parent_dir}/${new_name}"
        file.renameTo(new_file)
        println "Debug map: new_name=$new_name, new_path=${new_file}"
        return new_file
    }
    .collect()
    .map { file_paths -> 
        println "Debug file_paths: $file_paths"
        return [[ id: 'orthofinder_run' ], file_paths]
    }


    
renamed_files.view { meta, files -> 
    println "Debug output: meta=$meta"
    files.each { println "File: $it" }
}



    //Run orthofinder
    ORTHOFINDER (
        renamed_files,
        [[],[]]
    )
    ch_versions  = ch_versions.mix(ORTHOFINDER.out.versions)

    emit:
    quast_results         = QUAST.out.results                   // channel: [ val(meta), [tsv] ]
    busco_short_summaries = BUSCO_BUSCO.out.short_summaries_txt // channel: [ val(meta), [txt] ]

    versions = ch_versions                                      // channel: [ versions.yml ]
}

