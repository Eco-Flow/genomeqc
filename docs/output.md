# nf-core/genomeqc: Output

## Introduction

This document describes the output produced by the nf-core/genomeqc.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

<!-- [pigz uncompress](#pigz-uncompress) - Uncompresses FASTA and GFF files -->
<!-- [FastaValidator](#fastavalidator) Validate FASTA files -->
<!-- [AGAT convert sp_GXF2GXF]() - Standataizes gff files -->

- [NCBI genome download](#ncbi-genome-download) - Download genomes and their annotations from RefSeq and GenBank.
- Genome quality metrics:
  - [Quast](#quast) - Genome quality and contiguity metrics.
  - [tidk](#tidk) - Identify telomeric repeats.
  - [Merqury](#merqury) - Genome completeness and accuracy based on raw sequecing k-mer counts.
- Annotation quality metrics:
  - [AGAT sp_statistics](#agat-sp_statistics) - Gene statistics.
  - [AGAT sp_keep_longest_isoform](#agat-sp_keep_longest_isoform) - Filter longest isoform from GXF file.
  - [Gene overlaps](#gene-overlaps) - Find overlapping genes (sense and antisense).
- [Decontamination](#decontamination):
  - [FCS-GX](#fcs-gx) - Foreign genome contamination screening.
  - [FCS-adaptor](#fcs-adaptor) - Adaptor and vector contamination screening.
  - [FCS-adaptor clean genome](#fcs-adaptor-clean-genome) Removal of contamination from assembly.
  - [Tiara](#tiara) - Sequence classification (domain and organelle level).
- [GffRead](#gffread) - Extract longest isoform from FASTA file.
- [BUSCO](#busco) - Genome completeness based on single copy markers.
- [Orthofinder](#orthofinder) - Phylogenetic orthology inference.
- [Tree summary](#tree-summary) - Phylogenetic summary plot.
- [Shiny app](#shiny-app) - Dynamic tree summary plot adjuster.
- [MultiQC](#multiqc) - Aggregate report describing results and QC from the whole pipeline.
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution.

<!--### Pigz Uncompress

pigz is used to uncompress `.gz` input files, as some nf-core/genomeqc modules require uncompressed files as input. -->

### Decontamination

#### FCS-GX

[FCS-GX](https://github.com/ncbi/fcs/wiki/FCS-GX-quickstart) is a module in NCBI’s FCS (Foreign Contamination Screening) toolkit designed to detect contaminant sequences of foreign organisms from genome assemblies.

It generates a report with assembly sequence classifications, contamination summaries, and cleaning recommendations.

<details markdown="1">
<summary>Output files</summary>

- `decontamination/fcs-gx`
  - `<assembly>_<taxid>.fsc_gx_report.txt`: Summary report with sequence classification and cleaning recommendations.
  - `<assembly>_<taxid>.taxonomy.rpt`: Detailed breakdown of sequence classification.

</details>

#### FCS-Adaptor

[FCS-Adaptor](https://github.com/ncbi/fcs/wiki/FCS-adaptor-quickstart#clean-the-genome) is part of the NCBI's FCS toolkit. It’s specifically designed to detect adaptor and vector contamination that sometimes remain in genome assemblies.

It generates a report with a list of sequences flagged as adaptor or vector matches, cleaning recommendations, and the cleaned genome assembly.

<details markdown="1">
<summary>Output files</summary>

- `decontamination/fcs-adaptor`
  - `<assembly>.cleaned_sequences.fa.gz`: Genome assembly with contaminant regions removed.
  - `<assembly>.fsc_adaptor_report.txt`: Summary report with flagged sequences and cleaning recommendations.

</details>

:::note
We recommend ignoring the cleaned genome assembly output by this module, as the vector and adapter removal is done by the **FCS-GX clean genome** module (see below).
:::

#### FCS-GX clean genome

[FCS-GX clean genome]() is based on a command of the NCBI's FCS toolkit which applies the recommended cleaning actions to the genome assembly based on the screening results.

It outputs a cleaned version of the genome assembly based on the recommended actions from **FCS-GX** and **FCS-Adaptor**, with the contaminant sequences removed and sequences with local contaminants trimmed.

<details markdown="1">
<summary>Output files</summary>

- `decontamination/cleaned_genome`
  - `<assembly>.cleaned.fasta`: Genome assembly with contaminant sequences removed and contaminant regions trimmed.
  - `<assembly>.contaminants.fasta`: Sequences classified as contaminants.

</details>

#### Tiara

[Tiara](https://ibe-uw.github.io/tiara/) is a deep learning–based classifier designed to identify eukaryotic, archaeal, and bacterial sequences, as well as organelle genomes.

It outputs a report with each sequence of the genome assembly labelled as Eukarya, Archea, Bacteria, organelle or unknown.

<details markdown="1">
<summary>Output files</summary>

- `decontamination/tiara`
  - `<assembly>.txt
`: Report with sequence classifications.
  - `log_<assembly>.txt`: Log file with classification statistics and model information.

</details>

### NCBI genome download

[NCBI genome download](https://github.com/kblin/ncbi-genome-download) is a tool for downloading assemblies from the NCBI FTP site.

It inputs RefSeq or GeneBank assembly accessions and downloads the respective assembly (RefSeq and GeneBank) and annotation (RefSeq only) in FASTA and GFF formats. If local files are provided, this step is skipped.

<details markdown="1">
<summary>Output files</summary>

- `ncbigenomedownload/`
  - `<assembly>.fa.gz`: Genome assembly in FASTA format (GeneBank and RefSeq outputs).
  - `<assembly>.gff3.gz`: Annotation in GFF format (RefSeq output).

</details>

This directory will only be present if `--save_assembly` flag is set.

### Quast

[Quast](https://github.com/ablab/quast) provides different quality metrics about the genome assembly. It computes contiguity stats (N50, N90), genome size, GC% content and number of sequences.

It generates a report in different formats, as well as an HTML file with in integrated contig viewer.

<details markdown="1">
<summary>Output files</summary>

- `quast/<species_name>/`
  - `icarus.html`: Contig viewer in HTML format
  - `report.html`: Assembly stats in HTML format
  - `report.pdf`: Assembly stats in tsv format
  - `report.tsv`: Assembly QC as HTML report

</details>

### tidk

[tidk](https://github.com/tolkit/telomeric-identifier) is a tool to identify and visualise telomeric repeats from asseblies.

It will use a known telomeric repeat as input string, and will find occurrences of these sequence in windows across the genome.

<details markdown="1">
<summary>Output files</summary>

- `tidk/`
  - `<species_name>.tsv`: Report with the number of repeats found in different number of windows
  - `<species_name>.svg`: Plot with the repeat distribution

</details>

To run nf-core/genomeqc with tidk, the flag `--run_tidk` must be provided.

![output_example_tidk](images/output_example/meles_meles_tidk.png)

### Merqury

[Merqury](https://github.com/marbl/merqury) uses k-mers from sequencing reads to evaluate the assembly quality and completness without the need of a high quality reference.

It generates a histogram relating k-mer counts in the read set to their associated counts in the assembly, as well as a completness report.

<details markdown="1">
<summary>Output files</summary>

- `merqury/`
  - `<assembly>.html`: Contig viewer in HTML format
  - `<assembly>.html`: Assembly stats in HTML format
  - `<assembly>.pdf`: Assembly stats in tsv format
  - `<assembly>.tsv`: Assembly QC as HTML report

</details>

To run nf-core/genomeqc with merqury, the flag `--run_merqury` must be provided.

### AGAT sp_statistics

[AGAT sp_statistics](https://agat.readthedocs.io/en/latest/tools/agat_sp_statistics.html) computes several annotation metrics such as number of genes, transcripts, exons, etc.

<details markdown="1">
<summary>Output files</summary>

- `agat/`
  - `<species_name>.stats.txt`: Contig viewr in HTML format

</details>

### AGAT sp_keep_longest_isoform

[AGAT sp_keep_longest_isoform](https://agat.readthedocs.io/en/latest/tools/agat_sp_keep_longest_isoform.html) filters GXF file to keep the longest isoform per gene. Longest isoforms are recommended as input for both BUSCO and Orthofinder.

<details markdown="1">
<summary>Output files</summary>

- `longest/`
  - `<species_name>.longest.g*f`: Contig viewr in HTML format

</details>

This directory will only be present if `--save_longest_isoform` flag is set.

### Gene overlaps

**Gene overlaps** is a local module based on the R package [GenomicRanges](https://bioconductor.org/packages/release/bioc/html/GenomicRanges.html), used for manipulating genomic intervals. It finds the number of genes that are overlapping in the GXF file, which can be used as a metric to evaluate the quality of the annotation.

It outputs a brief report with information about the number of reads, the number of genes fully contained in sense direction and in the antisense direction, and the total number of overlapping genes.

<details markdown="1">
<summary>Output files</summary>

- `longest/`
  - `Count.<species_name>.tsv`: Report in tsv format

</details>

### GffRead

[GffRead](https://github.com/gpertea/gffread) extracts the protein sequences using the genome assembly and annoation as input.

<details markdown="1">
<summary>Output files</summary>

- `gffread/`
  - `<species_name>.longest.fasta`: Report in tsv format

</details>

This directory will only be present if `--save_extracted_seqs` flag is set.

### BUSCO

[BUSCO](https://busco.ezlab.org/) is a tool for assessing the quality of assemblies based on the presence of single copy orthotologues. It computes the compleness based on evolutionarily informed expectations of gene content, whether this single copy markers are present in single copy, duplicated, fragmented or absent.

It outputs a report with completness stats, a summarized table with these stats, and an ideaogram with single copy markers mapped against each chromosome or sequence.

<details markdown="1">
<summary>Output files</summary>

- `busco/`
  - `short_summary.specific.<busco_db>.<species_name>.fasta.txt` Completness report in tsv format
  - `<species_name>-<busco_db>-busco.batch_summary.txt`: Summarized completness report in tsv format
  - `<species_name>_<lineage>.png` Ideogram with the location of single copy markers
  </details>

![output_example_busco](images/output_example/syngnathus_acus_ideogram.png)

### Orthofinder

[Orthofinder](https://github.com/davidemms/OrthoFinder) finds groups of orthologous genes and uses these orthologous genes for phylogenetic inference.

It output a rooted species tree which is later used to present the quality stats of the assemblies.

### Tree summary

**Tree summary** is a local module that takes the rooted trees species from Orthofinder, as well as the ouput statistics from the mentioned tools.

The idea of the tree summary is to give some phylogenetic context to the quality stats, which might help users when evaluating the integrity of the assemblies.

<details markdown="1">
<summary>Output files</summary>

- `tree_summary/`
  - `tree_plot.pdf` Tree summary with quality statistics

</details>

![output_example_tree](images/output_example/tree_plot.png)

### Shiny App

**The shiny app** module uses [Shiny](https://shiny.posit.co/), a package to build interactive web apps from R, to create a dynamic plot adjuster to modify the tree plot in real time. It allows to change plot parameters such as margins, branch length, text size, etc., as well as adding and removing summary statistics next to the tree tips. The modified plot can be saved as a png/svg.

The app has two tabs, the **Plot Controls** tab to adjust the plot and remove/add features, and an **Export Settings** tab, that allows to preview the plot to export, change export settings, and save the plot as plot as png/svg.

<details markdown="1">
<summary>Output files</summary>

- `shiny/app/`
  - `shiny_app.sh`: excutable to run the shiny app. It can be executed it using `bash shiny_app.sh`.
  - `shiny_app.R`: script containing the code to run the app.
  - `tree_functions.R`: script containing the code with the functions used by the app.

</details>

![output_example_tree](images/output_example/shiny_app.png)

### Reports

The pipeline summarises the results from the tools above into two reports: a HTML report and an Excel spreadsheet.

The **HTML report** is a single-file report with one tab per tool. The BUSCO, Telomeres, FCS-GX, FCS-Adaptor and Tiara tabs are only shown if the corresponding tool was run. The Telomeres tab includes a chromosome selector for assemblies with multiple sequences, and a toggle to switch between the a priori and a posteriori tidk searches when both were run.

The **Excel report** contains the same summary statistics as separate tables.

**Agat** results are missing from the HTML report, and are not shown in the Excel report. This is yet to be fixed.

<details markdown="1">
<summary>Output files</summary>

- `report/`
  - `genomeqc_report.html`: Self-contained HTML report summarising the results from all the tools above.
  - `genomeqc_tables.xlsx`: Excel spreadsheet with the same summary statistics.

</details>

![output_example_report](images/output_example/report_example.png)

### MultiQC

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. Most of the pipeline QC results are visualised in the report and further statistics are available in the report data directory.

Results generated by MultiQC collate pipeline QC from supported tools e.g. FastQC. The pipeline has special steps which also allow the software versions to be reported in the MultiQC output for future traceability. For more information about how to use MultiQC reports, see <http://multiqc.info>.

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

### Pipeline information

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.
  - Parameters used by the pipeline run: `params.json`.

</details>
