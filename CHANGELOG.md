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

### `Changed`

- Expanded the `manifest.contributors` list in `nextflow.config` to credit Stephen Turner, Felipe Perez Cobos, Lauren Huet, Simon Murray, and Jacques Dainat as authors/contributors, and Mahesh Binzer-Panchal and Usman Rashid as contributors.
- Fixed a stray leading space in Fernando Duarte's name in `manifest.contributors`.

### `Fixed`

- Fixed BUSCO not showing in the tree

### `Dependencies`

### `Deprecated`
