#!/usr/bin/env python3
"""
Parse minimap2 PAF from repeat-library-vs-genome alignment.
Output a RepeatMasker .tbl-like TE composition table.

DFAM query name format: Name#Class/Family  (e.g. AluSx#SINE/Alu)
"""
import argparse
import gzip
import sys
from collections import defaultdict

# ---------------------------------------------------------------------------
# DFAM class → (broad_category, retro_subclass) mapping
# retro_subclass is only set for Retroelements (SINE/LINE/LTR); else None.
# ---------------------------------------------------------------------------

def classify(dfam_class):
    """
    Return (category, retro_subclass).
    category        – top-level group for the .tbl table
    retro_subclass  – 'SINE', 'LINE', 'LTR', or None
    """
    top = dfam_class.split('/')[0]
    if top == 'SINE':
        return 'Retroelement', 'SINE'
    if top == 'LINE':
        return 'Retroelement', 'LINE'
    if top in ('LTR', 'DIRS', 'PLE'):
        return 'Retroelement', 'LTR'
    if top == 'Retroposon':
        return 'Retroelement', 'Other_retro'
    if top == 'DNA':
        return 'DNA', None
    if top == 'RC':
        return 'RC', None
    if top in ('rRNA', 'snRNA', 'srpRNA', 'tRNA', 'scRNA'):
        return 'Small_RNA', None
    if top == 'Satellite':
        return 'Satellite', None
    if top == 'Simple_repeat':
        return 'Simple_repeat', None
    if top == 'Low_complexity':
        return 'Low_complexity', None
    return 'Unclassified', None


# ---------------------------------------------------------------------------
# Interval helpers
# ---------------------------------------------------------------------------

def merge(intervals):
    """Merge overlapping (start, end) pairs; return sorted non-overlapping list."""
    result = []
    for s, e in sorted(intervals):
        if result and s <= result[-1][1]:
            result[-1] = (result[-1][0], max(result[-1][1], e))
        else:
            result.append((s, e))
    return result


def covered(intervals):
    return sum(e - s for s, e in merge(intervals))


# ---------------------------------------------------------------------------
# Simple repeat intervals from TRF -ngs output
# ---------------------------------------------------------------------------

def parse_trf_dat(path):
    """Parse TRF output (produced with -ngs flag) to get simple repeat intervals.

    The -ngs format has @seqname header lines followed by one hit per line:
      start end period_size copy_number consensus_size pct_match pct_indel score A C G T entropy consensus sequence

    Positions are 1-based; we return 0-based half-open intervals.
    Returns: {chrom: [(start, end), ...]}
    """
    intervals = defaultdict(list)
    chrom = None
    with open(path) as fh:
        for line in fh:
            line = line.rstrip()
            if not line:
                continue
            if line.startswith('@'):
                chrom = line[1:].split()[0]
            elif chrom is not None:
                parts = line.split()
                if len(parts) >= 2:
                    intervals[chrom].append((int(parts[0]) - 1, int(parts[1])))
    return intervals


# ---------------------------------------------------------------------------
# Low-complexity intervals from mdust soft-masked FASTA
# ---------------------------------------------------------------------------

def parse_dust_fasta(path):
    """Extract low-complexity intervals from a soft-masked FASTA (mdust output).

    mdust lowercases low-complexity bases in-place.  We scan each sequence for
    runs of lowercase characters and return them as 0-based half-open intervals.

    Returns: {chrom: [(start, end), ...]}
    """
    opener = gzip.open if path.endswith('.gz') else open
    intervals = defaultdict(list)
    chrom = None
    pos = 0
    in_lc = False
    lc_start = 0
    with opener(path, 'rt') as fh:
        for line in fh:
            line = line.rstrip('\n')
            if line.startswith('>'):
                if in_lc and chrom is not None:
                    intervals[chrom].append((lc_start, pos))
                chrom = line[1:].split()[0]
                pos = 0
                in_lc = False
            else:
                for ch in line:
                    is_lc = ch.islower()
                    if is_lc and not in_lc:
                        lc_start = pos
                        in_lc = True
                    elif not is_lc and in_lc:
                        intervals[chrom].append((lc_start, pos))
                        in_lc = False
                    pos += 1
    if in_lc and chrom is not None:
        intervals[chrom].append((lc_start, pos))
    return intervals


# ---------------------------------------------------------------------------
# Genome FASTA stats
# ---------------------------------------------------------------------------

def fasta_stats(path):
    """Return (n_seqs, total_bp, nx_bp, gc_bp)."""
    opener = gzip.open if path.endswith('.gz') else open
    n_seqs = total = nx = gc = 0
    with opener(path, 'rt') as fh:
        for line in fh:
            if line.startswith('>'):
                n_seqs += 1
            else:
                seq = line.strip().upper()
                total += len(seq)
                nx    += seq.count('N') + seq.count('X')
                gc    += seq.count('G') + seq.count('C')
    return n_seqs, total, nx, gc


# ---------------------------------------------------------------------------
# PAF parsing
# ---------------------------------------------------------------------------

def parse_paf(path, min_mapq=0, min_aln=50):
    """
    Returns:
        by_chrom  – {chrom: {(category, retro_sub): [(start, end)]}}
                    retro_sub is 'SINE'/'LINE'/'LTR'/None
    """
    by_chrom = defaultdict(lambda: defaultdict(list))

    with open(path) as fh:
        for line in fh:
            f = line.split('\t')
            if len(f) < 12:
                continue

            query   = f[0]
            chrom   = f[5]
            t_start = int(f[7])
            t_end   = int(f[8])
            mapq    = int(f[11])
            aln_len = int(f[10])

            if mapq < min_mapq or aln_len < min_aln:
                continue

            dfam_class      = query.split('#', 1)[1] if '#' in query else 'Unknown'
            category, rsub  = classify(dfam_class)

            by_chrom[chrom][(category, rsub)].append((t_start, t_end))

    return by_chrom


# ---------------------------------------------------------------------------
# Coverage helpers
# ---------------------------------------------------------------------------

def cov_for(by_chrom, category, retro_sub=None):
    """Total unique bases covered for a (category, retro_sub) key."""
    all_ivs = []
    for chrom_data in by_chrom.values():
        all_ivs.extend(chrom_data.get((category, retro_sub), []))
    return covered(all_ivs)


def elem_for(by_chrom, category, retro_sub=None):
    """Number of non-overlapping intervals (proxy for insertion count)."""
    total = 0
    for chrom_data in by_chrom.values():
        total += len(merge(chrom_data.get((category, retro_sub), [])))
    return total


def total_masked_bp(by_chrom):
    """Total unique bases covered by any TE across the whole genome."""
    total = 0
    for chrom_data in by_chrom.values():
        all_ivs = [iv for ivs in chrom_data.values() for iv in ivs]
        total += covered(all_ivs)
    return total


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

DSEP = "=" * 50
SEP  = "-" * 50

HEADER = """\
{dsep}
file name: {fname}
sequences:         {n_seqs:>9}
total length: {total:>13,} bp  ({excl:,} bp excl N/X-runs)
GC level:         {gc_pct:>6.2f} %
bases covered: {masked:>11,} bp ({masked_pct:>5.2f} %)
{dsep}
               number of      length   percentage
               elements*    occupied  of sequence
{sep}"""

ROW = "{label:<26} {n:>9}  {bp:>11,} bp  {pct:>6.2f} %"


def pct(bp, total):
    return 100.0 * bp / total if total else 0.0


def row(label, n, bp, total_bp):
    return ROW.format(label=label, n=n, bp=bp, pct=pct(bp, total_bp))


def write_tbl(out, fname, gs, by_chrom, dust_intervals=None, trf_intervals=None):
    n_seqs, total_bp, nx_bp, gc_bp = gs
    excl_bp    = total_bp - nx_bp
    gc_pct     = pct(gc_bp, excl_bp)

    # Low complexity from mdust (DUST algorithm) or fall back to library hits
    if dust_intervals is not None:
        all_dust     = [iv for ivs in dust_intervals.values() for iv in ivs]
        lowc_bp_dust = covered(all_dust)
        lowc_n_dust  = sum(len(merge(ivs)) for ivs in dust_intervals.values())
    else:
        lowc_bp_dust = None

    # Simple repeats from TRF or fall back to library hits
    if trf_intervals is not None:
        all_trf     = [iv for ivs in trf_intervals.values() for iv in ivs]
        simp_bp_trf = covered(all_trf)
        simp_n_trf  = sum(len(merge(ivs)) for ivs in trf_intervals.values())
    else:
        simp_bp_trf = None

    # Total masked = TE hits + dust low-complexity + TRF simple repeats
    masked = total_masked_bp(by_chrom)
    if lowc_bp_dust is not None:
        masked += lowc_bp_dust
    if simp_bp_trf is not None:
        masked += simp_bp_trf
    masked_pct = pct(masked, total_bp)

    print(HEADER.format(
        dsep       = DSEP,
        sep        = SEP,
        fname      = fname,
        n_seqs     = n_seqs,
        total      = total_bp,
        excl       = excl_bp,
        gc_pct     = gc_pct,
        masked     = masked,
        masked_pct = masked_pct,
    ), file=out)

    # Retroelements
    sine_bp  = cov_for(by_chrom, 'Retroelement', 'SINE')
    line_bp  = cov_for(by_chrom, 'Retroelement', 'LINE')
    ltr_bp   = cov_for(by_chrom, 'Retroelement', 'LTR')
    oret_bp  = cov_for(by_chrom, 'Retroelement', 'Other_retro')
    retro_bp = sine_bp + line_bp + ltr_bp + oret_bp

    sine_n   = elem_for(by_chrom, 'Retroelement', 'SINE')
    line_n   = elem_for(by_chrom, 'Retroelement', 'LINE')
    ltr_n    = elem_for(by_chrom, 'Retroelement', 'LTR')
    oret_n   = elem_for(by_chrom, 'Retroelement', 'Other_retro')
    retro_n  = sine_n + line_n + ltr_n + oret_n

    print(row("Retroelements",       retro_n, retro_bp, total_bp), file=out)
    print(row("   SINEs:",           sine_n,  sine_bp,  total_bp), file=out)
    print(row("   LINEs:",           line_n,  line_bp,  total_bp), file=out)
    print(row("   LTR elements:",    ltr_n,   ltr_bp,   total_bp), file=out)
    if oret_bp:
        print(row("   Other retroelements:", oret_n, oret_bp, total_bp), file=out)

    # DNA / RC / Unclassified
    dna_bp  = cov_for(by_chrom, 'DNA')
    rc_bp   = cov_for(by_chrom, 'RC')
    unk_bp  = cov_for(by_chrom, 'Unclassified')
    dna_n   = elem_for(by_chrom, 'DNA')
    rc_n    = elem_for(by_chrom, 'RC')
    unk_n   = elem_for(by_chrom, 'Unclassified')

    print(row("DNA transposons",  dna_n, dna_bp, total_bp), file=out)
    print(row("Rolling-circles",  rc_n,  rc_bp,  total_bp), file=out)
    print(row("Unclassified",     unk_n, unk_bp, total_bp), file=out)

    interspersed = retro_bp + dna_bp + rc_bp + unk_bp
    print(SEP, file=out)
    print(f"Total interspersed repeats: {interspersed:>11,} bp  {pct(interspersed, total_bp):>6.2f} %", file=out)
    print(SEP, file=out)

    # Other categories
    srna_bp  = cov_for(by_chrom, 'Small_RNA')
    sat_bp   = cov_for(by_chrom, 'Satellite')
    srna_n   = elem_for(by_chrom, 'Small_RNA')
    sat_n    = elem_for(by_chrom, 'Satellite')

    # Simple repeats: use TRF if available, else fall back to library hits
    if simp_bp_trf is not None:
        simp_bp, simp_n = simp_bp_trf, simp_n_trf
    else:
        simp_bp = cov_for(by_chrom, 'Simple_repeat')
        simp_n  = elem_for(by_chrom, 'Simple_repeat')

    # Low complexity: use mdust if available, else fall back to library hits
    if lowc_bp_dust is not None:
        lowc_bp, lowc_n = lowc_bp_dust, lowc_n_dust
    else:
        lowc_bp = cov_for(by_chrom, 'Low_complexity')
        lowc_n  = elem_for(by_chrom, 'Low_complexity')

    print(row("Small RNA",      srna_n, srna_bp, total_bp), file=out)
    print(row("Satellites",     sat_n,  sat_bp,  total_bp), file=out)
    print(row("Simple repeats", simp_n, simp_bp, total_bp), file=out)
    print(row("Low complexity", lowc_n, lowc_bp, total_bp), file=out)
    print(DSEP, file=out)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('paf',    help='minimap2 PAF file')
    ap.add_argument('genome', help='genome FASTA (gzipped ok)')
    ap.add_argument('--dust-fasta', default=None, help='mdust soft-masked FASTA for low-complexity detection')
    ap.add_argument('--trf-dat',   default=None, help='TRF -ngs output for simple/tandem repeat detection')
    ap.add_argument('--prefix',   default=None, help='sample name for header')
    ap.add_argument('--min-mapq', type=int, default=0,  help='minimum mapping quality (default: 0)')
    ap.add_argument('--min-aln',  type=int, default=50, help='minimum alignment length bp (default: 50)')
    args = ap.parse_args()

    fname          = args.prefix or args.genome
    gs             = fasta_stats(args.genome)
    by_chrom       = parse_paf(args.paf, min_mapq=args.min_mapq, min_aln=args.min_aln)
    dust_intervals = parse_dust_fasta(args.dust_fasta) if args.dust_fasta else None
    trf_intervals  = parse_trf_dat(args.trf_dat)       if args.trf_dat   else None
    write_tbl(sys.stdout, fname, gs, by_chrom, dust_intervals, trf_intervals)


if __name__ == '__main__':
    main()
