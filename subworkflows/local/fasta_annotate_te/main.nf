include { RM_DOWNLOAD_DB              } from '../../../modules/local/repeatmasker_download_db/main'
include { FAMDB_PY_EMBL               } from '../../../modules/local/famdb_py_embl/main'
include { REPEATMODELER_BUILDDATABASE } from '../../../modules/nf-core/repeatmodeler/builddatabase/main'
include { REPEATMODELER_REPEATMODELER } from '../../../modules/nf-core/repeatmodeler/repeatmodeler/main'
include { CAT_CAT                     } from '../../../modules/nf-core/cat/cat/main'
include { CDHIT_CDHITEST              } from '../../../modules/nf-core/cdhit/cdhitest/main'
include { MMSEQS_EASYCLUSTER          } from '../../../modules/nf-core/mmseqs/easycluster/main'
include { MMSEQS_EASYLINCLUST         } from '../../../modules/local/mmseqs_easylinclust/main'
include { REPEATMASKER_REPEATMASKER   } from '../../../modules/nf-core/repeatmasker/repeatmasker/main'
include { HITE                        } from '../../../modules/local/hite/main'
include { TE_TBL_2_TABLE              } from '../../../modules/local/te_tbl_2_table/main'


workflow FASTA_ANNOTATE_TE {

    take:
    ch_fasta              // channel: [ val(meta), path(fasta) ]
    ch_rm_db              // channel: [ val(meta), val(db_url) ] ; Channel.empty() if not downloading
    ch_famdb_lib          // channel: [ val(meta), path(h5) ]   ; Channel.empty() if not pre-staged
    val_famdb_lineage     // val: lineage string for famdb extraction (e.g. 'hymenoptera'), or ''
    val_run_repeatmodeler // val: boolean – run de novo RepeatModeler (slow, adds 24-48 h per genome)
    val_te_clusterer      // val: clustering tool – 'linclust' (default), 'mmseqs', or 'cdhit'

    main:
    def ch_te_masked     = channel.empty()
    def ch_te_out        = channel.empty()
    def ch_te_tbl        = channel.empty()
    def ch_te_gff        = channel.empty()
    def ch_clustered_lib = channel.empty()

    ch_rm_db = channel.empty()

    // Run with HITE or Repeatmasker/Repeatmodeler
    if (params.te == 'hite') {
        HITE ( ch_fasta )
        ch_te_tbl = HITE.out.tbl
    }

    if (params.te == 'repeatmasker') {
        // MODULE: RM_DOWNLOAD_DB
        // Download h5 partition files from DFAM — versions flow via Channel.topic('versions')
        // skip if ch_rm_db is empty
        RM_DOWNLOAD_DB ( ch_rm_db.filter { _meta, db_url -> db_url != [] } )

        // Collect all h5 partitions (downloaded + any pre-staged) for famdb.py.
        // famdb.py uses '-i ./' so all files must be staged in the same work directory.
        // If both ch_rm_db and ch_famdb_lib are empty this channel never emits,
        // FAMDB_PY does not run, and the pipeline falls back to RepeatModeler alone.
        ch_h5_files = RM_DOWNLOAD_DB.out.h5
                    | mix(ch_famdb_lib)
                    | map { meta, h5 -> h5 }
                    | collect
                    | map { h5_files -> tuple([id: 'famdb'], h5_files) }

        // MODULE: FAMDB_PY_EMBL
        // Extract repeat library with #Type/SubType headers — runs once per lineage
        FAMDB_PY_EMBL (
            ch_h5_files,
            val_famdb_lineage
        )

        if (val_run_repeatmodeler) {
            // Per-genome path: RepeatModeler produces a genome-specific de novo library,
            // which is merged with the shared famdb library before clustering.

            REPEATMODELER_BUILDDATABASE ( ch_fasta )
            REPEATMODELER_REPEATMODELER ( REPEATMODELER_BUILDDATABASE.out.db )
            ch_modeler_fasta = REPEATMODELER_REPEATMODELER.out.fasta

            ch_famdb_fasta = FAMDB_PY_EMBL.out.famdb_lib | map { _meta, fasta -> fasta }

            // Genomes where RepeatModeler succeeded: pair [famdb, modeler] for CAT_CAT.
            ch_famdb_with_modeler = ch_modeler_fasta
                                  | combine(ch_famdb_fasta)
                                  | map { meta, modeler, famdb -> tuple(meta, [famdb, modeler]) }

            // RepeatModeler channel is empty when it finds no repeat families,
            // so genomes with no hits would be silently dropped from ch_modeler_fasta.
            // Build a famdb-only fallback for every genome so none are lost.
            ch_famb_without_modeler = ch_fasta
                                   | combine(ch_famdb_fasta)
                                   | map { meta, _fasta, famdb -> tuple(meta, [famdb]) }

            // Merge: use both [famdb, modeler] when RepeatModeler produced output, else only [famdb].
            // remainder: true keeps genomes absent from ch_famdb_with_modeler (no modeler hits).
            ch_combined_libs = ch_famb_without_modeler
                             | join(ch_famdb_with_modeler, by: 0, remainder: true)
                             | map { meta, famdb_list, both_list ->
                                 tuple(meta, both_list ?: famdb_list)
                             }


            // MODULE: CAT_CAT — concatenate famdb and de novo libraries (per genome)
            CAT_CAT ( ch_combined_libs )

            if (val_te_clusterer == 'cdhit') {
                CDHIT_CDHITEST ( CAT_CAT.out.file_out )
                ch_clustered_lib = CDHIT_CDHITEST.out.fasta
            } else if (val_te_clusterer == 'linclust') {
                MMSEQS_EASYLINCLUST ( CAT_CAT.out.file_out )
                ch_clustered_lib = MMSEQS_EASYLINCLUST.out.representatives
            } else {
                MMSEQS_EASYCLUSTER ( CAT_CAT.out.file_out )
                ch_clustered_lib = MMSEQS_EASYCLUSTER.out.representatives
            }

        } else {
            // Shared path: cluster the famdb library once, then broadcast to every genome.
            // CAT_CAT is not needed — there is only one input library.

            if (val_te_clusterer == 'cdhit') {
                CDHIT_CDHITEST ( FAMDB_PY_EMBL.out.famdb_lib )
                ch_shared_lib = CDHIT_CDHITEST.out.fasta | map { meta, fasta -> fasta }
            } else if (val_te_clusterer == 'linclust') {
                MMSEQS_EASYLINCLUST ( FAMDB_PY_EMBL.out.famdb_lib )
                ch_shared_lib = MMSEQS_EASYLINCLUST.out.representatives | map { meta, fasta -> fasta }
            } else {
                MMSEQS_EASYCLUSTER ( FAMDB_PY_EMBL.out.famdb_lib )
                ch_shared_lib = MMSEQS_EASYCLUSTER.out.representatives | map { meta, fasta -> fasta }
            }

            // Pair each genome's meta with the single shared library
            ch_clustered_lib = ch_fasta
                             | map { meta, fasta -> meta }
                             | combine(ch_shared_lib)
                             | map { meta, lib -> tuple(meta, lib) }
        }

        // MODULE: REPEATMASKER_REPEATMASKER
        // Soft-mask repeat elements in each genome using its paired repeat library
        REPEATMASKER_REPEATMASKER (
            ch_fasta,
            ch_clustered_lib
        )

        ch_te_masked = REPEATMASKER_REPEATMASKER.out.masked
        ch_te_out    = REPEATMASKER_REPEATMASKER.out.out
        ch_te_tbl    = REPEATMASKER_REPEATMASKER.out.tbl
        ch_te_gff    = REPEATMASKER_REPEATMASKER.out.gff
    }

    // Collect all TBL files into a single channel for parsing. If no TBL files are found, return an empty channel instead of failing.
    ch_te_tbl_collect = ch_te_tbl.map { _meta, f -> f }.collect()

    // Parse TBL table into TSV format (this is only needed for the tree plot, which requires a single TSV table)
    TE_TBL_2_TABLE (
        ch_te_tbl_collect.map { f -> tuple([id:'te_table'], f) }
    )

    emit:
    masked          = ch_te_masked                 // channel: [ val(meta), path(masked) ]
    out             = ch_te_out                    // channel: [ val(meta), path(out) ]
    tbl             = ch_te_tbl                     // channel: [ val(meta), path(tbl) ]
    tbl_collected   = ch_te_tbl_collect            // channel: [ val(meta), path(tbl) ]
    tbl_tsv         = TE_TBL_2_TABLE.out.table     // channel: [ val(meta), path(tsv) ]
    gff             = ch_te_gff        // channel: [ val(meta), path(gff) ]
    repeat_library  = ch_clustered_lib // channel: [ val(meta), path(fasta) ]

}
