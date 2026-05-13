#!/usr/bin/env python3
"""Generate a self-contained HTML quality report for GenomeQC pipeline results."""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

# ── Colour palette ────────────────────────────────────────────────────────────

BUSCO_COLORS = {
    "Single":      "#2196F3",
    "Duplicated":  "#4CAF50",
    "Fragmented":  "#FF9800",
    "Missing":     "#F44336",
}

TIDK_PALETTE = [
    "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
    "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
]

# ── Data parsers ──────────────────────────────────────────────────────────────

def parse_busco_batch_summaries(paths):
    """Return list of row-dicts from BUSCO batch_summary_modified.txt files."""
    rows = []
    for p in paths:
        with open(p) as fh:
            lines = fh.readlines()
        if len(lines) < 2:
            continue
        header = lines[0].strip().split("\t")
        for line in lines[1:]:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            row = dict(zip(header, parts + [""] * max(0, len(header) - len(parts))))
            rows.append(row)
    rows.sort(key=lambda r: r.get("Input_file", ""))
    return rows


def parse_tidk_tsvs(paths):
    """Return {species: [row_dict, ...]} from tidk aposteriori search TSV files."""
    result = {}
    for p in paths:
        species = Path(p).stem
        rows = []
        with open(p) as fh:
            lines = fh.readlines()
        if not lines:
            continue
        header = lines[0].strip().split("\t")
        for line in lines[1:]:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            row = dict(zip(header, parts))
            for k in ("window", "forward_repeat_number", "reverse_repeat_number"):
                if k in row:
                    try:
                        row[k] = int(row[k])
                    except ValueError:
                        pass
            rows.append(row)
        result[species] = rows
    return result

def read_svg(path):
    """Read SVG file, stripping the XML declaration if present."""
    content = Path(path).read_text()
    if content.lstrip().startswith("<?xml"):
        idx = content.find("<svg")
        if idx != -1:
            content = content[idx:]
    return content


# ── SVG chart generators ──────────────────────────────────────────────────────

def busco_stacked_bar_svg(rows, mode_label=""):
    if not rows:
        return "<p><em>No BUSCO data available.</em></p>"

    bar_h     = 30
    label_w   = 220
    chart_w   = 550
    pad       = 12
    legend_h  = 36
    row_gap   = 6
    header_h  = 55
    total_h   = header_h + len(rows) * (bar_h + row_gap) + legend_h + pad
    svg_w     = label_w + chart_w + pad * 2

    bars = []
    y = header_h

    for row in rows:
        species = row.get("Input_file", "Unknown")
        display = (species[:35] + "…") if len(species) > 36 else species
        try:
            single = float(row.get("Single", 0))
            dup    = float(row.get("Duplicated", 0))
            frag   = float(row.get("Fragmented", 0))
            miss   = float(row.get("Missing", 0))
        except ValueError:
            continue

        bars.append(
            f'<text x="{label_w - 6}" y="{y + bar_h // 2 + 4}" '
            f'text-anchor="end" font-size="11" font-family="sans-serif" fill="#333">'
            f'<title>{species}</title>{display}</text>'
        )

        x = label_w + pad
        for val, color, lbl in [
            (single, BUSCO_COLORS["Single"],     f"Complete Single: {single:.1f}%"),
            (dup,    BUSCO_COLORS["Duplicated"],  f"Complete Dup: {dup:.1f}%"),
            (frag,   BUSCO_COLORS["Fragmented"],  f"Fragmented: {frag:.1f}%"),
            (miss,   BUSCO_COLORS["Missing"],     f"Missing: {miss:.1f}%"),
        ]:
            w = val / 100 * chart_w
            if w > 0.5:
                bars.append(
                    f'<rect x="{x:.1f}" y="{y}" width="{w:.1f}" height="{bar_h}" '
                    f'fill="{color}" rx="2"><title>{lbl}</title></rect>'
                )
            x += w

        complete = single + dup
        bars.append(
            f'<text x="{label_w + pad + complete / 100 * chart_w + 5}" '
            f'y="{y + bar_h // 2 + 4}" font-size="10" fill="#555">{complete:.1f}%</text>'
        )
        y += bar_h + row_gap

    # Axis grid lines and tick labels
    axis = []
    for pct in range(0, 101, 20):
        xpos = label_w + pad + pct / 100 * chart_w
        axis.append(
            f'<text x="{xpos}" y="46" text-anchor="middle" font-size="10" fill="#888">{pct}%</text>'
            f'<line x1="{xpos}" y1="50" x2="{xpos}" y2="{total_h - legend_h - pad}" '
            f'stroke="#ddd" stroke-width="1" stroke-dasharray="3,3"/>'
        )

    # Legend
    ley = total_h - legend_h + 4
    legend = []
    lx = label_w + pad
    for key, color in BUSCO_COLORS.items():
        legend.append(
            f'<rect x="{lx}" y="{ley}" width="14" height="14" fill="{color}" rx="2"/>'
            f'<text x="{lx + 18}" y="{ley + 11}" font-size="11" fill="#555">{key}</text>'
        )
        lx += 110

    title_lbl = "BUSCO Completeness" + (f" — {mode_label}" if mode_label else "")
    title = (
        f'<text x="{svg_w // 2}" y="22" text-anchor="middle" '
        f'font-size="14" font-weight="600" font-family="sans-serif" fill="#222">'
        f'{title_lbl}</text>'
    )

    return (
        f'<div style="overflow-x:auto">'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{svg_w}" height="{total_h}" '
        f'style="max-width:100%;height:auto;display:block">'
        f'{title}{"".join(axis)}{"".join(bars)}{"".join(legend)}'
        f'</svg></div>'
    )


def tidk_line_svg(species, rows, width=700, height=200):
    """Generate an inline SVG line chart for tidk window repeat counts."""
    if not rows:
        return ""

    chroms = {}
    for r in rows:
        cid = r.get("id", "chr")
        chroms.setdefault(cid, []).append(r)

    max_val = max(
        (max(r["forward_repeat_number"] + r["reverse_repeat_number"] for r in rs)
         for rs in chroms.values()),
        default=1,
    )
    max_window = max(
        (max(r["window"] for r in rs) for rs in chroms.values()),
        default=1,
    )

    pl, pr, pt, pb = 55, 15, 30, 45
    pw = width - pl - pr
    ph = height - pt - pb

    def tx(w):
        return pl + w / max_window * pw

    def ty(v):
        return pt + ph - v / max(max_val, 1) * ph

    lines_svg = []
    for i, (cid, chrom_rows) in enumerate(list(chroms.items())[:10]):
        color = TIDK_PALETTE[i % len(TIDK_PALETTE)]
        fwd = " ".join(f"{tx(r['window']):.1f},{ty(r['forward_repeat_number']):.1f}" for r in chrom_rows)
        rev = " ".join(f"{tx(r['window']):.1f},{ty(r['reverse_repeat_number']):.1f}" for r in chrom_rows)
        lines_svg.append(
            f'<polyline points="{fwd}" fill="none" stroke="{color}" stroke-width="1.5" opacity="0.9">'
            f'<title>{cid} (forward)</title></polyline>'
            f'<polyline points="{rev}" fill="none" stroke="{color}" stroke-width="1.5" opacity="0.5" stroke-dasharray="4,2">'
            f'<title>{cid} (reverse)</title></polyline>'
        )

    y_grid = []
    for pct in range(0, 101, 25):
        ypos = ty(max_val * pct / 100)
        val_label = int(max_val * pct / 100)
        y_grid.append(
            f'<text x="{pl - 5}" y="{ypos + 4}" text-anchor="end" font-size="9" fill="#888">{val_label}</text>'
            f'<line x1="{pl}" y1="{ypos}" x2="{pl + pw}" y2="{ypos}" stroke="#eee" stroke-width="1"/>'
        )

    x_grid = []
    for pct in range(0, 101, 25):
        xpos = tx(max_window * pct / 100)
        label = f"{int(max_window * pct / 100 / 1000)}k"
        x_grid.append(
            f'<text x="{xpos}" y="{pt + ph + 14}" text-anchor="middle" font-size="9" fill="#888">{label}</text>'
        )

    # legend for chromosomes
    leg = []
    for i, cid in enumerate(list(chroms.keys())[:10]):
        color = TIDK_PALETTE[i % len(TIDK_PALETTE)]
        lx = pl + i * 68
        if lx + 60 > width:
            break
        leg.append(
            f'<rect x="{lx}" y="{pt + ph + 25}" width="10" height="10" fill="{color}"/>'
            f'<text x="{lx + 13}" y="{pt + ph + 34}" font-size="9" fill="#555">{cid[:8]}</text>'
        )

    border = f'<rect x="{pl}" y="{pt}" width="{pw}" height="{ph}" fill="none" stroke="#ccc" stroke-width="1"/>'
    title_svg = (
        f'<text x="{width // 2}" y="18" text-anchor="middle" '
        f'font-size="12" font-weight="600" font-family="sans-serif" fill="#333">'
        f'Telomere repeats — {species}</text>'
    )
    axis_labels = (
        f'<text x="{pl - 40}" y="{pt + ph // 2}" text-anchor="middle" '
        f'font-size="9" fill="#888" transform="rotate(-90 {pl - 40} {pt + ph // 2})">Repeat count</text>'
        f'<text x="{pl + pw // 2}" y="{pt + ph + 38}" text-anchor="middle" font-size="9" fill="#888">Genomic position</text>'
    )

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'style="max-width:100%;height:auto;display:block">'
        f'{title_svg}{border}{"".join(y_grid)}{"".join(x_grid)}{axis_labels}'
        f'{"".join(lines_svg)}{"".join(leg)}'
        f'</svg>'
    )


# ── HTML helpers ──────────────────────────────────────────────────────────────

def _th(cells):
    return "<tr>" + "".join(f"<th>{c}</th>" for c in cells) + "</tr>"


def _td(cells):
    return "<tr>" + "".join(f"<td>{c}</td>" for c in cells) + "</tr>"


def busco_table_html(rows):
    cols = ["Input_file", "Dataset", "Complete", "Single", "Duplicated",
            "Fragmented", "Missing", "n_markers", "Scaffold N50", "Number of scaffolds"]
    available = [c for c in cols if any(c in r for r in rows)]
    header = _th(available)
    body = "\n".join(_td([row.get(c, "") for c in available]) for row in rows)
    return f'<table class="table">{header}{body}</table>'


def summary_table_html(busco_rows, tidk_data):
    """Cross-tool summary table shown on the Overview tab."""
    # Collect unique species from all data sources
    species_set = {r.get("Input_file", "") for r in busco_rows} | set(tidk_data.keys())
    species_list = sorted(s for s in species_set if s)

    busco_by_species = {r.get("Input_file", ""): r for r in busco_rows}

    header = _th(["Species", "BUSCO complete (%)", "BUSCO lineage",
                   "Scaffold N50", "# scaffolds", "Telomeric repeat"])
    rows_html = []
    for sp in species_list:
        br = busco_by_species.get(sp, {})
        try:
            complete = f"{float(br.get('Complete', 0)):.1f}%"
        except ValueError:
            complete = br.get("Complete", "—")
        n50 = br.get("Scaffold N50", "—") or "—"
        n_scaffolds = br.get("Number of scaffolds", "—") or "—"
        lineage = br.get("Dataset", "—") or "—"
        # get telomeric repeat from tidk data (first row's telomeric_repeat column)
        tidk_rows = tidk_data.get(sp, [])
        repeat = tidk_rows[0].get("telomeric_repeat", "—") if tidk_rows else "—"
        rows_html.append(_td([sp, complete, lineage, n50, n_scaffolds, repeat]))
    body = "\n".join(rows_html)
    return f'<table class="table">{header}{body}</table>'


# ── Inline CSS + JS ───────────────────────────────────────────────────────────

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;font-size:14px;color:#222;background:#f5f6fa}
header{background:#1565C0;color:#fff;padding:14px 24px;display:flex;align-items:center;gap:12px}
header h1{font-size:20px;font-weight:600}
header span{font-size:12px;opacity:.7}
.container{max-width:1200px;margin:24px auto;padding:0 16px}
nav.tabs{display:flex;gap:0;border-bottom:2px solid #e0e0e0;margin-bottom:20px;flex-wrap:wrap}
nav.tabs button{background:none;border:none;padding:10px 20px;cursor:pointer;font-size:14px;color:#555;border-bottom:3px solid transparent;margin-bottom:-2px;transition:color .15s,border-color .15s}
nav.tabs button:hover{color:#1565C0}
nav.tabs button.active{color:#1565C0;border-bottom-color:#1565C0;font-weight:600}
.tab-panel{display:none}
.tab-panel.active{display:block}
.card{background:#fff;border-radius:8px;box-shadow:0 1px 4px rgba(0,0,0,.1);padding:20px 24px;margin-bottom:20px}
.card h2{font-size:16px;font-weight:600;margin-bottom:14px;color:#1565C0}
.card h3{font-size:14px;font-weight:600;margin:16px 0 8px;color:#333}
table.table{width:100%;border-collapse:collapse;font-size:13px}
table.table th{background:#e3f2fd;color:#1565C0;padding:8px 10px;text-align:left;font-weight:600;white-space:nowrap}
table.table td{padding:7px 10px;border-bottom:1px solid #f0f0f0}
table.table tr:hover td{background:#fafafa}
.badge{display:inline-block;padding:2px 8px;border-radius:99px;font-size:11px;font-weight:600}
.badge-blue{background:#e3f2fd;color:#1565C0}
.badge-green{background:#e8f5e9;color:#2e7d32}
.badge-orange{background:#fff3e0;color:#e65100}
.tag{font-size:11px;color:#888}
.tidk-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:16px}
.tidk-item{background:#fff;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,.08);padding:12px}
.tidk-item h3{font-size:13px;font-weight:600;margin-bottom:8px;color:#333}
footer{text-align:center;padding:24px;font-size:12px;color:#aaa}
"""

TAB_JS = """
document.querySelectorAll('nav.tabs button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('nav.tabs button').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById(btn.dataset.tab).classList.add('active');
  });
});
"""

# ── Main HTML assembly ────────────────────────────────────────────────────────

def build_html(busco_rows, tidk_data, tidk_svgs):
    tabs = []
    panels = []
    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    # ── Overview tab ──────────────────────────────────────────────────────────
    tabs.append(("overview", "Overview"))
    n_species = len({r.get("Input_file") for r in busco_rows} | set(tidk_data.keys()))
    lineages  = sorted({r.get("Dataset", "") for r in busco_rows if r.get("Dataset")})
    badges = " ".join(
        f'<span class="badge badge-blue">{lg}</span>' for lg in lineages
    )
    summary_tbl = summary_table_html(busco_rows, tidk_data) if (busco_rows or tidk_data) else "<p>No data available.</p>"

    panels.append(
        f'<div id="overview" class="tab-panel active">'
        f'<div class="card">'
        f'<h2>Run summary</h2>'
        f'<p><strong>{n_species}</strong> species analysed &nbsp;·&nbsp; '
        f'BUSCO lineage(s): {badges or "—"} &nbsp;·&nbsp; '
        f'<span class="tag">Generated {now}</span></p>'
        f'</div>'
        f'<div class="card"><h2>Per-species overview</h2>{summary_tbl}</div>'
        f'</div>'
    )

    # ── BUSCO tab ─────────────────────────────────────────────────────────────
    if busco_rows:
        tabs.append(("busco", "BUSCO"))
        chart = busco_stacked_bar_svg(busco_rows)
        table = busco_table_html(busco_rows)
        panels.append(
            f'<div id="busco" class="tab-panel">'
            f'<div class="card"><h2>Completeness chart</h2>{chart}</div>'
            f'<div class="card"><h2>Completeness table</h2>'
            f'<p style="margin-bottom:10px;font-size:12px;color:#888">Hover chart bars for tooltips. '
            f'C(S) = Complete single-copy &nbsp;·&nbsp; C(D) = Complete duplicated &nbsp;·&nbsp; '
            f'F = Fragmented &nbsp;·&nbsp; M = Missing</p>'
            f'{table}</div></div>'
        )

    # ── Telomeres tab ─────────────────────────────────────────────────────────
    if tidk_data or tidk_svgs:
        tabs.append(("tidk", "Telomeres"))
        species_list = sorted(set(tidk_data.keys()) | set(tidk_svgs.keys()))
        items = []
        for sp in species_list:
            # prefer pre-rendered SVG; fall back to generating from TSV
            if sp in tidk_svgs:
                plot_html = (
                    f'<div style="overflow-x:auto">{tidk_svgs[sp]}</div>'
                )
            elif sp in tidk_data:
                plot_html = tidk_line_svg(sp, tidk_data[sp])
            else:
                plot_html = "<p><em>No plot data available.</em></p>"

            # show top repeat
            td_rows = tidk_data.get(sp, [])
            repeat = td_rows[0].get("telomeric_repeat", "—") if td_rows else "—"
            repeat_badge = f'<span class="badge badge-green">Repeat: {repeat}</span>' if repeat != "—" else ""

            items.append(
                f'<div class="tidk-item">'
                f'<h3>{sp} {repeat_badge}</h3>'
                f'{plot_html}</div>'
            )

        panels.append(
            f'<div id="tidk" class="tab-panel">'
            f'<div class="card">'
            f'<h2>Telomeric repeat analysis</h2>'
            f'<p style="margin-bottom:14px;font-size:12px;color:#888">'
            f'Solid lines = forward strand &nbsp;·&nbsp; Dashed lines = reverse strand</p>'
            f'<div class="tidk-grid">{"".join(items)}</div>'
            f'</div></div>'
        )

    # ── Assemble page ─────────────────────────────────────────────────────────
    tab_nav = "\n".join(
        f'<button data-tab="{tid}" class="{"active" if i == 0 else ""}">{label}</button>'
        for i, (tid, label) in enumerate(tabs)
    )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GenomeQC Report</title>
<style>{CSS}</style>
</head>
<body>
<header>
  <svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
    <circle cx="14" cy="14" r="13" stroke="white" stroke-width="2"/>
    <path d="M7 14 Q10 7 14 14 Q18 21 21 14" stroke="white" stroke-width="2" fill="none"/>
    <circle cx="14" cy="14" r="2.5" fill="white"/>
  </svg>
  <div>
    <h1>GenomeQC Report</h1>
    <span>nf-core/genomeqc &nbsp;·&nbsp; {now}</span>
  </div>
</header>
<div class="container">
  <nav class="tabs">{tab_nav}</nav>
  {"".join(panels)}
</div>
<footer>Generated by <strong>nf-core/genomeqc</strong> — <a href="https://github.com/nf-core/genomeqc" style="color:#888">github.com/nf-core/genomeqc</a></footer>
<script>{TAB_JS}</script>
</body>
</html>
"""


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Generate a self-contained HTML report for GenomeQC results."
    )
    parser.add_argument(
        "--busco_tables", nargs="*", default=[],
        metavar="TSV",
        help="BUSCO batch_summary_modified.txt files (one per species or combined)",
    )
    parser.add_argument(
        "--tidk_tsvs", nargs="*", default=[],
        metavar="TSV",
        help="tidk aposteriori search TSV files (one per species)",
    )
    parser.add_argument(
        "--tidk_svgs", nargs="*", default=[],
        metavar="SVG",
        help="tidk aposteriori plot SVG files (one per species)",
    )
    parser.add_argument(
        "--output", default="genomeqc_report.html",
        metavar="HTML",
        help="Output HTML file path (default: genomeqc_report.html)",
    )
    args = parser.parse_args()

    # Parse BUSCO
    busco_rows = parse_busco_batch_summaries(args.busco_tables) if args.busco_tables else []

    # Parse tidk TSVs
    tidk_data = parse_tidk_tsvs(args.tidk_tsvs) if args.tidk_tsvs else {}

    # Read tidk SVGs  – key by stem (species name)
    tidk_svgs = {}
    for p in (args.tidk_svgs or []):
        tidk_svgs[Path(p).stem] = read_svg(p)

    if not busco_rows and not tidk_data and not tidk_svgs:
        print("WARNING: no input data found; generating empty report.", file=sys.stderr)

    html = build_html(busco_rows, tidk_data, tidk_svgs)

    Path(args.output).write_text(html)
    print(f"Report written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
