include { RM_DOWNLOAD_DB              } from '../../../modules/local/repeatmasker_download_db/main'
include { FAMDB_PY                    } from '../../../modules/local/famdb.py/main'
include { REPEATMODELER_BUILDDATABASE } from '../../../modules/nf-core/repeatmodeler/builddatabase/main'
include { REPEATMODELER_REPEATMODELER } from '../../../modules/nf-core/repeatmodeler/repeatmodeler/main'
include { CAT_CAT                     } from '../../../modules/nf-core/cat/cat/main'
include { CDHIT_CDHITEST              } from '../../../modules/nf-core/cdhit/cdhitest/main'
include { MMSEQS_EASYCLUSTER          } from '../../../modules/nf-core/mmseqs/easycluster/main'
include { MMSEQS_EASYLINCLUST         } from '../../../modules/local/mmseqs_easylinclust/main'
include { REPEATMASKER_REPEATMASKER   } from '../../../modules/nf-core/repeatmasker/repeatmasker/main'


workflow FASTA_ANNOTATE_TE {

    take:
    ch_fasta              // channel: [ val(meta), path(fasta) ]
    ch_rm_db              // channel: [ val(meta), val(db_url) ] ; Channel.empty() if not downloading
    ch_famdb_lib          // channel: [ val(meta), path(h5) ]   ; Channel.empty() if not pre-staged
    val_famdb_lineage     // val: lineage string for famdb extraction (e.g. 'hymenoptera'), or ''
    val_run_repeatmodeler // val: boolean – run de novo RepeatModeler (slow, adds 24-48 h per genome)
    val_te_clusterer      // val: clustering tool – 'linclust' (default), 'mmseqs', or 'cdhit'

    main:

    // MODULE: RM_DOWNLOAD_DB
    // Download h5 partition files from DFAM — versions flow via Channel.topic('versions')
    RM_DOWNLOAD_DB ( ch_rm_db )

    // Collect all h5 partitions (downloaded + any pre-staged) for famdb.py.
    // famdb.py uses '-i ./' so all files must be staged in the same work directory.
    // If both ch_rm_db and ch_famdb_lib are empty this channel never emits,
    // FAMDB_PY does not run, and the pipeline falls back to RepeatModeler alone.
    ch_h5_files = RM_DOWNLOAD_DB.out.h5
                | mix(ch_famdb_lib)
                | map { meta, h5 -> h5 }
                | collect
                | map { h5_files -> tuple([id: 'famdb'], h5_files) }

    // MODULE: FAMDB_PY
    // Extract curated repeat library from collected h5 partitions — runs once per lineage
    FAMDB_PY (
        ch_h5_files,
        val_famdb_lineage
    )

    if (val_run_repeatmodeler) {
        // Per-genome path: RepeatModeler produces a genome-specific de novo library,
        // which is merged with the shared famdb library before clustering.

        REPEATMODELER_BUILDDATABASE ( ch_fasta )
        REPEATMODELER_REPEATMODELER ( REPEATMODELER_BUILDDATABASE.out.db )
        ch_modeler_fasta = REPEATMODELER_REPEATMODELER.out.fasta

        ch_famdb_fasta = FAMDB_PY.out.famdb_lib | map { meta, fasta -> fasta }

        // [famdb, modeler] when both are available; [modeler] when famdb was skipped
        ch_famdb_with_modeler = ch_modeler_fasta
                              | combine(ch_famdb_fasta)
                              | map { meta, modeler, famdb -> tuple(meta, [famdb, modeler]) }

        ch_combined_libs = ch_modeler_fasta
                         | map { meta, fasta -> tuple(meta, [fasta]) }
                         | join(ch_famdb_with_modeler, by: 0, remainder: true)
                         | map { meta, modeler_list, both_list ->
                             tuple(meta, both_list ?: modeler_list)
                         }

        // MODULE: CAT_CAT — concatenate famdb and de novo libraries (per genome)
        CAT_CAT ( ch_combined_libs )

        if (val_te_clusterer == 'cdhit') {
            CDHIT_CDHITEST ( CAT_CAT.out.file_out )
            ch_clustered_lib = CDHIT_CDHITEST.out.fasta_lib
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
            CDHIT_CDHITEST ( FAMDB_PY.out.famdb_lib )
            ch_shared_lib = CDHIT_CDHITEST.out.fasta_lib | map { meta, fasta -> fasta }
        } else if (val_te_clusterer == 'linclust') {
            MMSEQS_EASYLINCLUST ( FAMDB_PY.out.famdb_lib )
            ch_shared_lib = MMSEQS_EASYLINCLUST.out.representatives | map { meta, fasta -> fasta }
        } else {
            MMSEQS_EASYCLUSTER ( FAMDB_PY.out.famdb_lib )
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

    emit:
    masked          = REPEATMASKER_REPEATMASKER.out.masked  // channel: [ val(meta), path(masked) ]
    out             = REPEATMASKER_REPEATMASKER.out.out     // channel: [ val(meta), path(out) ]
    tbl             = REPEATMASKER_REPEATMASKER.out.tbl     // channel: [ val(meta), path(tbl) ]
    gff             = REPEATMASKER_REPEATMASKER.out.gff     // channel: [ val(meta), path(gff) ]
    repeat_library  = ch_clustered_lib                      // channel: [ val(meta), path(fasta) ]
}
