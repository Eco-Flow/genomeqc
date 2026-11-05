#!/usr/bin/env python3

# Written by Chris Wyatt with AI assistance, released under the MIT license.
# Parses FCS-GX genome reports into a combined TSV for tree-summary pie/ring plotting
"""
Parse one or more NCBI FCS-GX `*.fcs_gx_report.txt` genome reports and produce
a combined TSV suitable for pie-chart/ring plotting in the tree summary.

The contamination percentage is the number of bases flagged as contaminant in
the report rows, divided by the total length of that species' genome FASTA.
Only rows whose action is in --actions are counted (by default EXCLUDE, TRIM
and FIX: the ranges that `fcs.py clean genome` removes or masks). Each
species' ranges are merged per sequence before summing so overlapping rows are
not double-counted. An empty report (nothing flagged) means 0% contamination.

The `run-info.agg-cvg` value in the report's JSON header is NOT used: it is
the fraction of the genome covered by hits to ANY taxon in the GX database
(including the organism's own division), so it is typically very high for
well-represented taxa and does not measure contamination.

Reports and FASTAs are paired by position: the Nth --fastas file is the genome
for the Nth --reports file.

Output columns:
  species  contaminant_pct  non_contaminant_pct  contaminant_bp  genome_bp

Percentages are 0-100 and sum to 100 per row.

Usage:
  fcsgx_report_2_table.py \\
      --reports speciesA.fcs_gx_report.txt speciesB.fcs_gx_report.txt \\
      --fastas  speciesA.fasta             speciesB.fasta.gz \\
      -o fcs_summary.tsv
"""

import argparse
import gzip
import os
import re
import sys
from collections import defaultdict

_SUFFIX_RE = re.compile(r"\.fcs_gx_report\.txt$")
DEFAULT_ACTIONS = "EXCLUDE,TRIM,FIX"


def species_name(path: str) -> str:
    """Strip the `.fcs_gx_report.txt` suffix from a filename to get the species name."""
    return _SUFFIX_RE.sub("", os.path.basename(path))


def open_maybe_gzip(path: str):
    """Open a text file for reading, transparently handling gzip compression."""
    with open(path, "rb") as fh:
        magic = fh.read(2)
    if magic == b"\x1f\x8b":
        return gzip.open(path, "rt")
    return open(path)


def genome_length(path: str) -> int:
    """Return the total number of bases across all sequences in a FASTA file."""
    total = 0
    with open_maybe_gzip(path) as fh:
        for line in fh:
            if not line.startswith(">"):
                total += len(line.strip())
    return total


def merged_length(ranges) -> int:
    """Total length covered by a list of 1-based inclusive (start, end) ranges."""
    total = 0
    cur_start = cur_end = None
    for start, end in sorted(ranges):
        if cur_end is None or start > cur_end + 1:
            if cur_end is not None:
                total += cur_end - cur_start + 1
            cur_start, cur_end = start, end
        else:
            cur_end = max(cur_end, end)
    if cur_end is not None:
        total += cur_end - cur_start + 1
    return total


def contaminant_bases(path: str, actions) -> int:
    """Return the number of contaminant bases flagged in one FCS-GX report."""
    ranges = defaultdict(list)
    with open(path) as fh:
        for line in fh:
            if not line.strip() or line.startswith("#"):
                continue  # '##' JSON header, '#' column header, or blank
            fields = line.rstrip("\n").split("\t")
            seq_id, start, end, action = fields[0], int(fields[1]), int(fields[2]), fields[4]
            if action in actions:
                ranges[seq_id].append((min(start, end), max(start, end)))
    return sum(merged_length(r) for r in ranges.values())


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--reports", nargs="+", required=True,
                    help="FCS-GX *.fcs_gx_report.txt files (one per species)")
    ap.add_argument("--fastas", nargs="+", required=True,
                    help="Genome FASTA files (optionally gzipped), in the same order as --reports")
    ap.add_argument("--actions", default=DEFAULT_ACTIONS,
                    help=f"Comma-separated FCS-GX actions counted as contamination (default: {DEFAULT_ACTIONS})")
    ap.add_argument("-o", "--output", default="-", help="Output TSV (default: stdout)")
    args = ap.parse_args()

    if len(args.reports) != len(args.fastas):
        ap.error(f"got {len(args.reports)} --reports but {len(args.fastas)} --fastas; they must pair up 1:1")

    actions = {a.strip().upper() for a in args.actions.split(",") if a.strip()}

    rows = []
    for report, fasta in zip(args.reports, args.fastas):
        try:
            genome_bp = genome_length(fasta)
            if genome_bp == 0:
                raise ValueError(f"genome FASTA {fasta} has no sequence")
            contaminant_bp = contaminant_bases(report, actions)
        except Exception as exc:
            print(f"WARNING: skipping {report}: {exc}", file=sys.stderr)
            continue
        contaminant_pct = round(100.0 * contaminant_bp / genome_bp, 4)
        non_contaminant_pct = round(100.0 - contaminant_pct, 4)
        rows.append([
            species_name(report),
            str(contaminant_pct),
            str(non_contaminant_pct),
            str(contaminant_bp),
            str(genome_bp),
        ])

    out = open(args.output, "w") if args.output != "-" else sys.stdout
    try:
        print("\t".join(["species", "contaminant_pct", "non_contaminant_pct", "contaminant_bp", "genome_bp"]), file=out)
        for row in rows:
            print("\t".join(row), file=out)
    finally:
        if args.output != "-":
            out.close()


if __name__ == "__main__":
    main()
