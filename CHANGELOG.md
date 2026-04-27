# nf-core/genomeqc: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0dev - 25/04/2026

Initial release of nf-core/genomeqc, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Added `--te_clusterer` parameter to select the repeat library clustering tool used before RepeatMasker. Accepts `linclust` (default, MMseqs2 `easy-linclust`, linear time), `mmseqs` (MMseqs2 `easy-cluster`), or `cdhit` (CD-HIT-EST).
- Added `--te_cluster_identity` parameter (default `0.8`) to set the sequence identity threshold for repeat library clustering, applied across all three tools.
- Added `--te_cluster_coverage` parameter (default `0.8`) to set the alignment coverage threshold for repeat library clustering, applied across all three tools.
- Added `--repeatmasker_speed` parameter to control RepeatMasker sensitivity: `qq` (rush, default), `q` (quick), or `default` (most sensitive).
- Added `--te minimap2` mode: fast TE quantification using minimap2 (`asm20` preset) + a custom Python summary script. Produces a RepeatMasker `.tbl`-like table per genome without masking the assembly.
- Added `--te_minimap_args` parameter (default `"-k 13 -s 40"`) to control minimap2 sensitivity in `--te minimap2` mode. The default lowers the k-mer seed size and minimum alignment score relative to the `asm20` preset, giving sensitivity comparable to RepeatMasker for diverged TE copies. Pass `''` to revert to strict `asm20` defaults.

### `Fixed`

### `Dependencies`

### `Deprecated`
