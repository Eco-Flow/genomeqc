# nf-core/genomeqc: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

### `Fixed`

- Fixed BUSCO not showing in the tree
- Fixed the Shiny app launcher pulling its container from Docker Hub instead of quay.io (the plain `docker run` does not receive the `docker.registry` prefix), which caused a `pull access denied` error.
- Shiny app: the tree-style controls now show only the options that apply to the selected layout (margin/bar/pie controls for the non-circular styles, a ring-thickness control for the circular style), added a "Ring thickness" slider for the circular layout, and clarified the "Skip Statistics" labels.
- Circular layout: the "Tip Text Size" control now scales all text (tip numbers, ring legends and the species key), and the ring legends are ordered outer-ring-first to match the ring stack.
- Circular layout: quality statistics (sequence count, N50, BUSCO complete for genome and protein, BUSCO duplicated) are now scored as a colour-vision-safe **traffic light** (Good/Warn/Poor) against phylogenetic-group thresholds (`--quality_preset`: generic, vertebrate, insect, plant, fungi, bacteria), rather than a sequential ramp that misleadingly implied "dark = good" (it was backwards for sequence count). Descriptive statistics (genome size, gene number, ortho seqs) keep a neutral sequential ramp. `--show_ring_values` prints each value on its ring as a redundant, non-colour-only encoding. Both are also settable in the Shiny app.

### `Dependencies`

- Added `ggtreeExtra` and `ggnewscale` to the `genomeqc_tree` container (bumped to `v1.5`), required by the `circular` tree layout.

### `Deprecated`
