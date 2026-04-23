include { RM_DOWNLOAD_DB              } from '../../../modules/local/repeatmasker_download_db/main'
include { FAMDB_PY                    } from '../../../modules/local/famdb.py/main'
include { REPEATMODELER_BUILDDATABASE } from '../../../modules/nf-core/repeatmodeler/builddatabase/main'
include { REPEATMODELER_REPEATMODELER } from '../../../modules/nf-core/repeatmodeler/repeatmodeler/main'
include { CAT_CAT                     } from '../../../modules/nf-core/cat/cat/main'
include { CDHIT_CDHITEST              } from '../../../modules/nf-core/cdhit/cdhitest/main'
include { REPEATMASKER_REPEATMASKER   } from '../../../modules/nf-core/repeatmasker/repeatmasker/main'


workflow FASTA_ANNOTATE_TE {

    take:
    ch_fasta            // channel: [ val(meta), path(fasta) ]
    ch_rm_db            // channel: [ val(meta), val(db_url) ] ; Channel.empty() if not downloading
    ch_famdb_lib        // channel: [ val(meta), path(h5) ]   ; Channel.empty() if not pre-staged
    val_famdb_lineage   // val: lineage string for famdb extraction (e.g. 'hymenoptera'), or ''

    main:
    ch_versions = Channel.empty()

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
    // Extract curated repeat library from collected h5 partitions
    FAMDB_PY (
        ch_h5_files,
        val_famdb_lineage
    )
    ch_versions = ch_versions.mix(FAMDB_PY.out.versions.first())

    // MODULE: REPEATMODELER_BUILDDATABASE
    // Build BLAST-format database for de novo repeat discovery
    REPEATMODELER_BUILDDATABASE ( ch_fasta )
    ch_versions = ch_versions.mix(REPEATMODELER_BUILDDATABASE.out.versions.first())

    // MODULE: REPEATMODELER_REPEATMODELER
    // Perform de novo transposable element discovery
    REPEATMODELER_REPEATMODELER ( REPEATMODELER_BUILDDATABASE.out.db )
    ch_versions = ch_versions.mix(REPEATMODELER_REPEATMODELER.out.versions.first())

    // Combine the curated famdb library with the de novo RepeatModeler library.
    // When FAMDB_PY did not run (no h5 input), ch_famdb_combined is empty and the
    // join with remainder: true falls back to the RepeatModeler-only channel.
    // Build per-genome repeat library list: [famdb.fa, rm.fa] when FAMDB_PY ran,
    // or [rm.fa] alone when no h5 input was provided (ch_famdb_combined is empty).
    ch_famdb_combined = FAMDB_PY.out.famdb_lib
                      | map { meta, fasta -> fasta }
                      | combine(REPEATMODELER_REPEATMODELER.out.fasta)
                      | map { famdb_fasta, meta, modeler_fasta ->
                          tuple(meta, [famdb_fasta, modeler_fasta])
                      }

    ch_combined_libs  = REPEATMODELER_REPEATMODELER.out.fasta
                      | map { meta, fasta -> tuple(meta, [fasta]) }
                      | join(ch_famdb_combined, by: 0, remainder: true)
                      | map { meta, modeler_files, combined_files ->
                          tuple(meta, combined_files ?: modeler_files)
                      }

    // MODULE: CAT_CAT
    // Concatenate curated and de novo repeat libraries
    CAT_CAT ( ch_combined_libs )
    ch_versions = ch_versions.mix(CAT_CAT.out.versions.first())

    // MODULE: CDHIT_CDHITEST
    // Cluster sequences and remove redundancy from the combined library
    CDHIT_CDHITEST ( CAT_CAT.out.file_out )
    ch_versions = ch_versions.mix(CDHIT_CDHITEST.out.versions.first())

    // MODULE: REPEATMASKER_REPEATMASKER
    // Soft-mask repeat elements in the genome using the combined repeat library
    REPEATMASKER_REPEATMASKER (
        ch_fasta,
        CDHIT_CDHITEST.out.fasta_lib
    )
    ch_versions = ch_versions.mix(REPEATMASKER_REPEATMASKER.out.versions.first())

    emit:
    masked          = REPEATMASKER_REPEATMASKER.out.masked  // channel: [ val(meta), path(masked) ]
    out             = REPEATMASKER_REPEATMASKER.out.out     // channel: [ val(meta), path(out) ]
    tbl             = REPEATMASKER_REPEATMASKER.out.tbl     // channel: [ val(meta), path(tbl) ]
    gff             = REPEATMASKER_REPEATMASKER.out.gff     // channel: [ val(meta), path(gff) ]
    repeat_library  = CDHIT_CDHITEST.out.fasta_lib          // channel: [ val(meta), path(fasta) ]
    versions        = ch_versions                           // channel: [ versions.yml ]
}
