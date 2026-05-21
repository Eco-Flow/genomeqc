include { RM_DOWNLOAD_DB                      } from '../../../modules/local/repeatmasker_download_db/main'
include { FAMDB_PY_EMBL                       } from '../../../modules/local/famdb_py_embl/main'
include { CDHIT_CDHITEST                      } from '../../../modules/nf-core/cdhit/cdhitest/main'
include { MMSEQS_EASYCLUSTER                  } from '../../../modules/nf-core/mmseqs/easycluster/main'
include { MMSEQS_EASYLINCLUST                 } from '../../../modules/local/mmseqs_easylinclust/main'
include { MINIMAP2_TE                         } from '../../../modules/local/minimap2_te/main'
include { MDUST                               } from '../../../modules/nf-core/mdust/main'
include { TRF                                 } from '../../../modules/local/trf/main'
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

    // MODULE: FAMDB_PY_EMBL — extract repeat library with #Type/SubType headers for minimap2 classification
    FAMDB_PY_EMBL ( ch_h5_files, val_famdb_lineage )

    // Cluster the shared library once, broadcast to every genome
    if (val_te_clusterer == 'cdhit') {
        CDHIT_CDHITEST ( FAMDB_PY_EMBL.out.famdb_lib )
        ch_shared_lib = CDHIT_CDHITEST.out.fasta_lib | map { meta, fasta -> fasta }
    } else if (val_te_clusterer == 'mmseqs') {
        MMSEQS_EASYCLUSTER ( FAMDB_PY_EMBL.out.famdb_lib )
        ch_shared_lib = MMSEQS_EASYCLUSTER.out.representatives | map { meta, fasta -> fasta }
    } else {
        MMSEQS_EASYLINCLUST ( FAMDB_PY_EMBL.out.famdb_lib )
        ch_shared_lib = MMSEQS_EASYLINCLUST.out.representatives | map { meta, fasta -> fasta }
    }

    // MODULE: MINIMAP2_TE — align repeat library to each genome
    MINIMAP2_TE ( ch_fasta, ch_shared_lib )

    // MODULE: MDUST — soft-mask low complexity regions per genome
    MDUST ( ch_fasta )

    // MODULE: TRF — find simple/tandem repeats per genome
    TRF ( ch_fasta )

    // Join PAF, genome, dust FASTA, and TRF dat by meta.id to guarantee correct pairing
    ch_for_tbl = MINIMAP2_TE.out.paf
               | join( ch_fasta,        by: 0 )
               | join( MDUST.out.fasta, by: 0 )
               | join( TRF.out.dat,     by: 0 )

    // MODULE: TE_TBL — parse PAF + dust + TRF intervals and generate .tbl-like summary
    TE_TBL (
        ch_for_tbl.map { meta, paf, fasta, dust, trf -> tuple(meta, paf) },
        ch_for_tbl.map { meta, paf, fasta, dust, trf -> tuple(meta, fasta) },
        ch_for_tbl.map { meta, paf, fasta, dust, trf -> tuple(meta, dust) },
        ch_for_tbl.map { meta, paf, fasta, dust, trf -> tuple(meta, trf) }
    )

    emit:
    tbl            = TE_TBL.out.tbl        // channel: [ val(meta), path(tbl) ]
    repeat_library = FAMDB_PY_EMBL.out.famdb_lib // channel: [ val(meta), path(fasta) ]
}
