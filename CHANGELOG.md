# nf-core/genomeqc: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0 - [date]

## v0.0.1 (dev) - [15 June 2026]

Initial pre-release of nf-core/genomeqc, created with the [nf-core](https://nf-co.re/) template.

This is the first release of the pipeline, which compares the quality of multiple genomes and their annotations. The pipeline runs in two modes depending on the inputs provided: **Genome only** (FASTA files) and **Genome and Annotation** (FASTA plus GTF/GFF files).

### `Added`

- Added `--te_clusterer` parameter to select the repeat library clustering tool used before RepeatMasker. Accepts `linclust` (default, MMseqs2 `easy-linclust`, linear time), `mmseqs` (MMseqs2 `easy-cluster`), or `cdhit` (CD-HIT-EST).
- Added `--te_cluster_identity` parameter (default `0.8`) to set the sequence identity threshold for repeat library clustering, applied across all three tools.
- Added `--te_cluster_coverage` parameter (default `0.8`) to set the alignment coverage threshold for repeat library clustering, applied across all three tools.
- Added `--repeatmasker_speed` parameter to control RepeatMasker sensitivity: `qq` (rush, default), `q` (quick), or `default` (most sensitive).
- Added `meta.yml` for all local modules (`modules/local/*`), and nf-test coverage (`tests/main.nf.test`) for a first batch of them, following nf-core module conventions.

### `Fixed`

- Fixed `ORTHOFINDER` silently succeeding when OrthoFinder itself failed to produce `Orthogroups/Orthogroups.tsv`, which surfaced downstream as a confusing "missing output file" error in `ORTHOLOGOUS_CHROMOSOMES` instead of the real failure.
- Fixed `ORTHOLOGOUS_CHROMOSOMES` silently mapping zero genes for GFFs that use a `transcript` feature instead of `mRNA` (common in AUGUSTUS output, especially when combined with evidence from other predictors) ([#174](https://github.com/nf-core/genomeqc/issues/174)).
- Fixed `ORTHOFINDERV2` crashing under conda with a misleading "the computer ran out of RAM" message. `environment.yml` didn't pin python/numpy, so conda resolved the latest available (python 3.14, numpy 2.x); OrthoFinder 2.5.5's bundled `orthologues.py` uses a numpy indexing pattern that numpy 2.x rejects (`TypeError: only 0-dimensional arrays can be converted to Python scalars`), which OrthoFinder's own error handling reports as an OOM regardless of the real cause. Pinned python=3.12/numpy=1.26.4, matching what the module's static `biocontainers/orthofinder:2.5.5` image already uses under docker/singularity.
- Fixed `RM_DOWNLOAD_DB`'s conda environment failing to resolve (`bioconda::curl=7.80.0` doesn't exist; `curl` was never actually on bioconda). Repinned to `conda-forge::curl=7.80.0`, where that exact version is still available, keeping it consistent with the container's pinned curl version.
- Fixed CI: the `singularity`/`apptainer` nf-test matrix was failing almost every module with `Failed to create user namespace: Permission denied`. The `Setup apptainer` step never pinned a version, silently falling back to an old default (1.1.2) that predates Apptainer's AppArmor profile for Ubuntu 24.04 runners' unprivileged user-namespace restrictions. Pinned to `1.3.4`, matching `download_pipeline.yml`.
- Fixed conda/docker version drift causing "Different Snapshot" test failures in `orthologous_chromosomes`, `buscos_seqs`, `excel_report`, and `html_report`: each module's `environment.yml` was pinned to an old python/pandas version no longer matching what its Wave or biocontainers image actually serves under docker/singularity, so conda alone resolved a different (older) tool version than the two container-based profiles. Repinned each to the exact version already in use, rather than the stale original pin.
- Reverted an attempted `shiny_app` fix (`coreutils=8.31` -> `8.32`) that broke conda entirely: `coreutils=8.32` doesn't exist for `linux-64` on conda-forge (only `osx-arm64` had it, which is why it passed in local testing but failed in CI) - conda-forge's `linux-64` builds jump straight from `8.31` to `9.0`. The underlying snapshot mismatch (container's system `coreutils` reports `8.32`, conda-forge doesn't package that exact version for Linux) remains unfixed; system-level and conda-forge package version numbering for `coreutils` don't share a release schedule, so this needs a different approach than the version-pin fix used for the other four modules.
- Fixed `orthologous_chromosomes`/`buscos_seqs` under singularity reporting stale tool versions (python 3.9.23/pandas 1.5.2) that didn't match docker/conda (python 3.13.5/pandas 2.3.1): both modules hardcoded a specific Wave blob digest for singularity that was frozen at the container's original build, while the docker tag has since been rebuilt with newer package versions without the singularity reference being updated to match. Requested a fresh Wave/Seqera build for the exact same `environment.yml` spec with `format: sif` and switched both modules' singularity container to the resulting `oras://` reference, which Wave confirmed matches the current docker tag's package versions.

### `Dependencies`

### `Deprecated`

## v0.0.1 (dev) - [12 June 2026]

Initial pre-release of nf-core/genomeqc, created with the [nf-core](https://nf-co.re/) template.

This is the first release of the pipeline, which compares the quality of multiple genomes and their annotations. The pipeline runs in two modes depending on the inputs provided: **Genome only** (FASTA files) and **Genome and Annotation** (FASTA plus GTF/GFF files).

### `Added`

- Input genomes and annotations from local files or NCBI accessions, downloaded with [NCBI genome download](https://github.com/kblin/ncbi-genome-download).
- Genome completeness assessment with [BUSCO](https://busco.ezlab.org/), including a **BUSCO Ideogram** plotting the location of markers on the assembly.
- Read-based genome completeness evaluation with [Merqury](https://github.com/marbl/merqury) (optional).
- Telomeric repeat identification and visualisation with [tidk](https://github.com/tolkit/telomeric-identifier) (optional).
- Assembly contiguity and integrity statistics (N50, N90, GC%, number of sequences) with [QUAST](https://github.com/ablab/quast).
- Contamination screening with [FCS-GX](https://github.com/ncbi/fcs/wiki/FCS-GX-quickstart), [FCS-adaptor](https://github.com/ncbi/fcs/wiki/FCS-adaptor-quickstart), and [Tiara](https://ibe-uw.github.io/tiara/).
- Annotation statistics (number of genes, features, lengths) with [AGAT](https://agat.readthedocs.io/en/latest/), and a **Gene Overlaps** analysis counting overlapping genes.
- Extraction of the longest protein isoform with [GffRead](https://github.com/gpertea/gffread).
- Orthologous gene inference with [OrthoFinder](https://github.com/davidemms/OrthoFinder) (v3).
- BUSCO marker-based and orthology-based phylogenetic **Tree Summary** plots combining assembly and annotation summary statistics.
- An executable Shiny app for interactively adjusting the tree plot and summary statistics, with PNG/SVG export.
- HTML and Excel summary reports.
- Aggregated quality-control report with [MultiQC](http://multiqc.info).
- New `--tree_style` option for the **Tree Summary** plot: `roundrect` (rounded branches, new default), `ellipse` (curved branches with node points), `rectangular` (legacy look with dotted leader lines), and `circular` (fan tree with the summary statistics drawn as concentric coloured rings and a numbered species key). Selectable in the Shiny app.
- New `--circular_rings` option controlling which stats appear as rings in the circular layout (any of `ch_plot`, `len_plot`, `n50_plot`, `gene_plot`, `busco_gen_plot`, `busco_prot_plot`, `nseqs_plot`, `ortho_plot`, or `all`). The static pipeline figure defaults to a curated assembly/annotation-quality set (sequence number, N50, genome BUSCO, protein BUSCO), while the Shiny app shows every non-skipped stat.
- Circular layout: the Good/Warn/Poor key now lists the per-metric thresholds (e.g. `BUSCO genome: 95+ / 90+ / <90`), read from whichever `--quality_preset` or custom thresholds are in force.
- New `--quality_thresholds` option to override individual `--quality_preset` cut-offs from the CLI, as comma-separated `metric=good:warn` pairs (e.g. `n50=2e6:5e5,seq_number=500:5000`; metrics: `busco_complete`, `busco_duplicated`, `n50`, `seq_number`). Previously, per-metric custom thresholds were only settable interactively in the Shiny app.

### `Fixed`

- Fixed BUSCO not showing in the tree
- Fixed the Shiny app launcher pulling its container from Docker Hub instead of quay.io (the plain `docker run` does not receive the `docker.registry` prefix), which caused a `pull access denied` error.
- Shiny app: the tree-style controls now show only the options that apply to the selected layout (margin/bar/pie controls for the non-circular styles, a ring-thickness control for the circular style), added a "Ring thickness" slider for the circular layout, and clarified the "Skip Statistics" labels.
- Circular layout: the "Tip Text Size" control now scales all text (tip numbers, ring legends and the species key), and the ring legends are ordered outer-ring-first to match the ring stack.
- Shiny app: the circular layout now offers a "Quality thresholds (phylo group)" preset selector plus a "Custom..." option exposing per-metric Good/Warn cut-offs (BUSCO complete, BUSCO duplicated, N50, sequence count), and a "Print values on rings" toggle.
- Circular layout: quality statistics (sequence count, N50, BUSCO complete for genome and protein, BUSCO duplicated) are now scored as a colour-vision-safe **traffic light** (Good/Warn/Poor) against phylogenetic-group thresholds (`--quality_preset`: generic, vertebrate, insect, plant, fungi, bacteria), rather than a sequential ramp that misleadingly implied "dark = good" (it was backwards for sequence count). Descriptive statistics (genome size, gene number, ortho seqs) are drawn in a neutral **grey** ramp and grouped as a separate outer block, so they never borrow the traffic-light colours or sit interleaved with the quality rings. `--show_ring_values` prints each value on its ring as a redundant, non-colour-only encoding. Both are also settable in the Shiny app.
- Circular layout: quality rings are now placed on the outer rim and descriptive rings nearest the tree, so the judgement-carrying rings read most clearly. The Good/Warn/Poor key is now drawn explicitly rather than relying on ggplot's legend, so all three swatches always appear, even when a ring happens to be a single grade throughout.

### `Dependencies`

- Added `ggtreeExtra` and `ggnewscale` to the `genomeqc_tree` container (bumped to `v1.5`), required by the `circular` tree layout.

### `Deprecated`
