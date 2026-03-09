#!/usr/bin/env Rscript

# Code written by Chris Wyatt with some editing by ChatGPT

library(dplyr)
library(GenomicRanges)

# Parse command-line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    stop("Usage: overlap_analysis.R <input_gff_file> <output_table>")
}

input_gff_file <- args[1]
output_table <- args[2]
output_count <- args[3]

# Helper function to read a GFF file and convert it into a GRanges object
read_gff_to_granges <- function(gff_file) {
    gff_data <- read.delim(gff_file, header = FALSE, comment.char = "#")
    colnames(gff_data) <- c("seqname", "source", "feature", "start", "end",
                            "score", "strand", "frame", "attribute")
    gff_data <- gff_data %>%
      filter(strand %in% c("-","+"))

    gr <- GRanges(
        seqnames = gff_data$seqname,
        ranges = IRanges(start = gff_data$start, end = gff_data$end),
        strand = gff_data$strand,
        feature = gff_data$feature,
        attribute = gff_data$attribute
    )
    return(gr)
}

print("Parsing GFF..")
# Load GFF file into GRanges
gr <- read_gff_to_granges(input_gff_file)

print("Filering gene features...")
# Filter only "gene" features
genes <- gr[gr$feature == "gene"]
total_genes <- length(genes)

print("Finding overlaps...")
# Find overlaps
overlap_results <- findOverlaps(genes, genes, ignore.strand = FALSE)

# Initialize counts
sense_count_within <- 0
antisense_count_within <- 0

# extract indices once
q_idx <- queryHits(overlap_results)
s_idx <- subjectHits(overlap_results)

# filter self-overlaps
keep <- q_idx != s_idx
q_idx <- q_idx[keep]
s_idx <- s_idx[keep]

# extract genes
q_genes <- genes[q_idx]
s_genes <- genes[s_idx]

# overlap ranges in bulk
overlaps <- pintersect(ranges(q_genes), ranges(s_genes))
overlap_len <- width(overlaps)

# query/subject lengths
q_len <- width(ranges(q_genes))
s_len <- width(ranges(s_genes))

# percentage overlaps
q_pct <- (overlap_len / q_len) * 100
s_pct <- (overlap_len / s_len) * 100

# strands
q_strand <- as.character(strand(q_genes))
s_strand <- as.character(strand(s_genes))

# overlap type
overlap_type <- ifelse(
  !is.na(q_strand) & !is.na(s_strand),
  ifelse(q_strand == s_strand, "sense", "antisense"),
  "unknown"
)

# counters for fully contained overlaps
sense_count_within     <- sum(q_pct == 100 & overlap_type == "sense")
antisense_count_within <- sum(q_pct == 100 & overlap_type == "antisense")

# results data.frame all at once
results <- data.frame(
  query_gene        = q_genes$attribute,
  subject_gene      = s_genes$attribute,
  query_start       = start(q_genes),
  query_end         = end(q_genes),
  subject_start     = start(s_genes),
  subject_end       = end(s_genes),
  query_strand      = q_strand,
  subject_strand    = s_strand,
  overlap_type      = overlap_type,
  query_overlap_pct = q_pct,
  subject_overlap_pct = s_pct,
  stringsAsFactors = FALSE
)

# optional: progress indicator (print every 5%)
n <- length(q_idx)
steps <- seq(0, 100, by = 5)
for (pct in steps) {
  idx <- floor(pct/100 * n)
  if (idx > 0) message("Processed ", pct, "% (", idx, " overlaps)")
}

print("Writing to output...")
# Write results to output file
write.table(results, file = output_table, sep = "\t", row.names = FALSE, quote = FALSE)

# Print the summary
cat("Number of genes fully contained in sense direction:", sense_count_within, "\n")
cat("Number of genes fully contained in antisense direction:", antisense_count_within, "\n")
cat("Overlap analysis complete. Results saved to:", output_table, "\n")

# Calculate total number of overlapping genes
total_overlapping_genes <- length(unique(c(results$query_gene, results$subject_gene)))

# Create summary statistics table
summary_stats <- data.frame(
    Statistic = c("Total number of genes",
                  "Number of genes fully contained in sense direction",
                  "Number of genes fully contained in antisense direction",
                  "Total number of overlapping genes"),
    Count = c(total_genes,
              sense_count_within,
              antisense_count_within,
              total_overlapping_genes)
)

# Write summary statistics table
write.table(summary_stats, file=output_count, sep="\t", quote=FALSE, row.names=FALSE)

# Print the summary
cat("Total number of genes:", total_genes, "\n")
cat("Number of genes fully contained in sense direction:", sense_count_within, "\n")
cat("Number of genes fully contained in antisense direction:", antisense_count_within, "\n")
cat("Total number of overlapping genes:", total_overlapping_genes, "\n")
cat("Overlap analysis complete. Results saved to:", output_table, "\n")
cat("Summary statistics saved to:", output_count, "\n")
