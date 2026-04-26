include { RM_DOWNLOAD_DB                      } from '../../../modules/local/repeatmasker_download_db/main'
include { FAMDB_PY                            } from '../../../modules/local/famdb.py/main'
include { CDHIT_CDHITEST                      } from '../../../modules/nf-core/cdhit/cdhitest/main'
include { MMSEQS_EASYCLUSTER                  } from '../../../modules/nf-core/mmseqs/easycluster/main'
include { MMSEQS_EASYLINCLUST                 } from '../../../modules/local/mmseqs_easylinclust/main'
include { MINIMAP2_TE                         } from '../../../modules/local/minimap2_te/main'
include { TE_TBL                              } from '../../../modules/local/te_tbl/main'


workflow FASTA_QUANTIFY_TE {

    take:
    ch_fasta          // channel: [ val(meta), path(fasta) ]
    ch_rm_db          // channel: [ val(meta), val(db_url) ] ; Channel.empty() if not downloading
    ch_famdb_lib      // channel: [ val(meta), path(h5) ]   ; Channel.empty() if not pre-staged
    val_famdb_lineage // val: lineage string for famdb extraction (e.g. 'hymenoptera'), or ''
    val_te_clusterer  // val: 'linclust' (default), 'mmseqs', or 'cdhit'

    main:

    // MODULE: RM_DOWNLOAD_DB
    RM_DOWNLOAD_DB ( ch_rm_db )

    // Collect all h5 partitions for famdb.py (runs once per lineage)
    ch_h5_files = RM_DOWNLOAD_DB.out.h5
                | mix(ch_famdb_lib)
                | map { meta, h5 -> h5 }
                | collect
                | map { h5_files -> tuple([id: 'famdb'], h5_files) }

    // MODULE: FAMDB_PY — extract curated repeat library once for the lineage
    FAMDB_PY ( ch_h5_files, val_famdb_lineage )

    // Cluster the shared library once, broadcast to every genome
    if (val_te_clusterer == 'cdhit') {
        CDHIT_CDHITEST ( FAMDB_PY.out.famdb_lib )
        ch_shared_lib = CDHIT_CDHITEST.out.fasta_lib | map { meta, fasta -> fasta }
    } else if (val_te_clusterer == 'mmseqs') {
        MMSEQS_EASYCLUSTER ( FAMDB_PY.out.famdb_lib )
        ch_shared_lib = MMSEQS_EASYCLUSTER.out.representatives | map { meta, fasta -> fasta }
    } else {
        MMSEQS_EASYLINCLUST ( FAMDB_PY.out.famdb_lib )
        ch_shared_lib = MMSEQS_EASYLINCLUST.out.representatives | map { meta, fasta -> fasta }
    }

    // MODULE: MINIMAP2_TE — align repeat library to each genome
    MINIMAP2_TE ( ch_fasta, ch_shared_lib )

    // MODULE: TE_TBL — parse PAF and generate .tbl-like summary
    TE_TBL ( MINIMAP2_TE.out.paf, ch_fasta )

    emit:
    tbl            = TE_TBL.out.tbl        // channel: [ val(meta), path(tbl) ]
    repeat_library = FAMDB_PY.out.famdb_lib // channel: [ val(meta), path(fasta) ]
}
