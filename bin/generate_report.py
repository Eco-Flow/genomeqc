#!/usr/bin/env python3
"""Generate a self-contained HTML quality report for GenomeQC pipeline results."""

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path


def _safe_id(s):
    return re.sub(r'[^a-zA-Z0-9]', '_', s)

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


def tidk_line_svg(species, rows, width=700, height=220, plot_id=None):
    """Return an HTML block (optional chromosome dropdown + SVG waveform).

    Mirrors the original tidk SVG plot: one path per chromosome, y encodes total
    repeat count (fwd+rev) with high density plotted toward the top.
    A chromosome selector dropdown is shown when the species has >1 sequence.
    """
    if not rows:
        return ""

    chroms = {}
    for r in rows:
        cid = r.get("id", "chr")
        chroms.setdefault(cid, []).append(r)

    # plot_id lets the caller differentiate IDs when both modes share a page
    sp_id = _safe_id(plot_id if plot_id else species)

    # Use fwd+rev sum as the signal value
    max_sum = max(
        (r["forward_repeat_number"] + r["reverse_repeat_number"]
         for rs in chroms.values() for r in rs),
        default=1,
    ) or 1
    max_window = max(
        (r["window"] for rs in chroms.values() for r in rs),
        default=1,
    ) or 1

    pl, pr, pt, pb = 50, 15, 30, 50
    pw = width - pl - pr
    ph = height - pt - pb
    baseline_y = pt + ph  # SVG y of zero-count baseline (bottom of plot)

    def tx(w):
        return pl + w / max_window * pw

    def ty(s):
        return baseline_y - s / max_sum * ph

    paths_svg = []
    for i, (cid, chrom_rows) in enumerate(list(chroms.items())[:10]):
        color = TIDK_PALETTE[i % len(TIDK_PALETTE)]
        cid_safe = _safe_id(cid)
        s0 = chrom_rows[0]["forward_repeat_number"] + chrom_rows[0]["reverse_repeat_number"]
        pts = [f"M{pl:.1f},{ty(s0):.1f}"]
        for r in chrom_rows:
            s = r["forward_repeat_number"] + r["reverse_repeat_number"]
            pts.append(f"L{tx(r['window']):.1f},{ty(s):.1f}")
        paths_svg.append(
            f'<path id="tp-{sp_id}-{cid_safe}" d="{" ".join(pts)}" fill="none" '
            f'stroke="{color}" stroke-width="1.5" opacity="0.85">'
            f'<title>{cid}</title></path>'
        )

    # Baseline
    baseline = (
        f'<line x1="{pl}" y1="{baseline_y}" x2="{pl + pw}" y2="{baseline_y}" '
        f'stroke="#ccc" stroke-width="1"/>'
    )

    # Horizontal grid lines
    y_grid = []
    for pct in (25, 50, 75, 100):
        ypos = ty(max_sum * pct / 100)
        y_grid.append(
            f'<line x1="{pl}" y1="{ypos:.1f}" x2="{pl + pw}" y2="{ypos:.1f}" '
            f'stroke="#eee" stroke-width="1" stroke-dasharray="3,3"/>'
            f'<text x="{pl - 4}" y="{ypos + 4:.1f}" text-anchor="end" '
            f'font-size="9" fill="#aaa">{int(max_sum * pct / 100)}</text>'
        )

    # X-axis ticks
    x_grid = []
    for pct in range(0, 101, 25):
        xpos = tx(max_window * pct / 100)
        mbp = max_window * pct / 100 / 1_000_000
        label = f"{mbp:.2f}Mb" if mbp >= 0.1 else f"{int(max_window * pct / 100 / 1000)}k"
        x_grid.append(
            f'<line x1="{xpos:.1f}" y1="{baseline_y}" x2="{xpos:.1f}" y2="{baseline_y + 4}" '
            f'stroke="#bbb" stroke-width="1"/>'
            f'<text x="{xpos:.1f}" y="{baseline_y + 14}" text-anchor="middle" '
            f'font-size="9" fill="#888">{label}</text>'
        )

    # Chromosome legend (below x-axis)
    leg = []
    n_chroms = min(len(chroms), 10)
    leg_item_w = min(80, pw // max(n_chroms, 1))
    for i, cid in enumerate(list(chroms.keys())[:10]):
        color = TIDK_PALETTE[i % len(TIDK_PALETTE)]
        lx = pl + i * leg_item_w
        if lx + leg_item_w > pl + pw:
            break
        leg.append(
            f'<line x1="{lx}" y1="{baseline_y + 28}" x2="{lx + 12}" y2="{baseline_y + 28}" '
            f'stroke="{color}" stroke-width="2"/>'
            f'<text x="{lx + 15}" y="{baseline_y + 32}" font-size="9" fill="#555">{cid[:10]}</text>'
        )

    border = (
        f'<rect x="{pl}" y="{pt}" width="{pw}" height="{ph}" '
        f'fill="none" stroke="#ccc" stroke-width="1"/>'
    )
    title_svg = (
        f'<text x="{width // 2}" y="18" text-anchor="middle" '
        f'font-size="12" font-weight="600" font-family="sans-serif" fill="#333">'
        f'{species}</text>'
    )
    y_axis_label = (
        f'<text x="{pl - 38}" y="{pt + ph // 2}" text-anchor="middle" '
        f'font-size="9" fill="#888" '
        f'transform="rotate(-90 {pl - 38} {pt + ph // 2})">Repeat density</text>'
    )

    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'style="max-width:100%;height:auto;display:block">'
        f'{title_svg}{border}{baseline}'
        f'{"".join(y_grid)}{"".join(x_grid)}'
        f'{y_axis_label}'
        f'{"".join(paths_svg)}'
        f'{"".join(leg)}'
        f'</svg>'
    )

    # Chromosome selector dropdown — only rendered when there are multiple sequences
    if len(chroms) > 1:
        chrom_items = []
        for i, cid in enumerate(list(chroms.keys())[:10]):
            cid_safe = _safe_id(cid)
            color = TIDK_PALETTE[i % len(TIDK_PALETTE)]
            chrom_items.append(
                f'<label>'
                f'<input type="checkbox" value="{cid_safe}" checked '
                f'onchange="tidkUpdate(\'{sp_id}\')">'
                f'<span class="chrom-swatch" style="background:{color}"></span>'
                f'{cid}'
                f'</label>'
            )
        dropdown = (
            f'<div class="chrom-select-wrap">'
            f'<button class="chrom-btn" onclick="tidkToggleMenu(\'{sp_id}\',event)">'
            f'Sequences ▾</button>'
            f'<div class="chrom-menu" id="cmenu-{sp_id}">'
            f'<div class="chrom-menu-actions">'
            f'<button onclick="tidkSelectAll(\'{sp_id}\')">All</button>'
            f'<button onclick="tidkSelectNone(\'{sp_id}\')">None</button>'
            f'</div>'
            f'{"".join(chrom_items)}'
            f'</div>'
            f'</div>'
        )
    else:
        dropdown = ""

    return f'{dropdown}{svg}'


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
.tidk-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(660px,1fr));gap:16px}
.tidk-item{background:#fff;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,.08);padding:12px}
.tidk-item h3{font-size:13px;font-weight:600;margin-bottom:8px;color:#333}
.chrom-select-wrap{position:relative;display:inline-block;margin-bottom:8px}
.chrom-btn{background:#f0f4ff;border:1px solid #c5cae9;border-radius:4px;padding:4px 10px;cursor:pointer;font-size:12px;color:#3949ab;line-height:1.4}
.chrom-btn:hover{background:#e8eaf6}
.chrom-menu{position:absolute;top:calc(100% + 4px);left:0;background:#fff;border:1px solid #ddd;border-radius:6px;box-shadow:0 4px 12px rgba(0,0,0,.12);padding:8px;z-index:100;min-width:180px;max-height:260px;overflow-y:auto;display:none}
.chrom-menu.open{display:block}
.chrom-menu label{display:flex;align-items:center;gap:6px;padding:3px 4px;font-size:12px;cursor:pointer;white-space:nowrap;border-radius:3px}
.chrom-menu label:hover{background:#f5f5f5}
.chrom-menu input[type=checkbox]{cursor:pointer}
.chrom-swatch{display:inline-block;width:10px;height:10px;border-radius:2px;flex-shrink:0}
.chrom-menu-actions{display:flex;gap:6px;margin-bottom:6px;padding-bottom:6px;border-bottom:1px solid #eee}
.chrom-menu-actions button{flex:1;background:#f0f4ff;border:1px solid #c5cae9;border-radius:3px;padding:2px 6px;font-size:11px;cursor:pointer;color:#3949ab}
.chrom-menu-actions button:hover{background:#e8eaf6}
.tidk-mode-toggle{display:flex;gap:4px;margin-bottom:8px;flex-wrap:wrap}
.tidk-mode-toggle button{background:#f5f5f5;border:1px solid #ddd;border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;color:#555;transition:background .1s,border-color .1s}
.tidk-mode-toggle button.active{background:#e3f2fd;border-color:#90caf9;color:#1565C0;font-weight:600}
.tidk-mode-toggle button:hover:not(.active){background:#ebebeb}
.tidk-mode-toggle code{font-size:11px;background:rgba(0,0,0,.06);padding:1px 4px;border-radius:3px}
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

function tidkToggleMenu(spId, event) {
  event.stopPropagation();
  var menu = document.getElementById('cmenu-' + spId);
  menu.classList.toggle('open');
}

function tidkUpdate(spId) {
  var menu = document.getElementById('cmenu-' + spId);
  menu.querySelectorAll('input[type=checkbox]').forEach(function(cb) {
    var path = document.getElementById('tp-' + spId + '-' + cb.value);
    if (path) path.style.display = cb.checked ? '' : 'none';
  });
}

function tidkSelectAll(spId) {
  var menu = document.getElementById('cmenu-' + spId);
  menu.querySelectorAll('input[type=checkbox]').forEach(function(cb) { cb.checked = true; });
  tidkUpdate(spId);
}

function tidkSelectNone(spId) {
  var menu = document.getElementById('cmenu-' + spId);
  menu.querySelectorAll('input[type=checkbox]').forEach(function(cb) { cb.checked = false; });
  tidkUpdate(spId);
}

document.addEventListener('click', function(e) {
  if (!e.target.closest('.chrom-select-wrap')) {
    document.querySelectorAll('.chrom-menu.open').forEach(function(m) { m.classList.remove('open'); });
  }
});

function tidkSetMode(spId, mode) {
  ['aposteriori', 'apriori'].forEach(function(m) {
    var el = document.getElementById('plot-' + m + '-' + spId);
    if (el) el.style.display = (m === mode) ? '' : 'none';
  });
  var toggle = document.getElementById('mode-' + spId);
  if (toggle) toggle.querySelectorAll('button').forEach(function(btn) {
    btn.classList.toggle('active', btn.dataset.mode === mode);
  });
}
"""

# ── Main HTML assembly ────────────────────────────────────────────────────────

def build_html(busco_rows, tidk_data, tidk_apriori_data=None):
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
    all_tidk_species = sorted(set(tidk_data.keys()) | set((tidk_apriori_data or {}).keys()))
    if all_tidk_species:
        tabs.append(("tidk", "Telomeres"))
        items = []
        for sp in all_tidk_species:
            post_rows = tidk_data.get(sp, [])
            pre_rows  = (tidk_apriori_data or {}).get(sp, [])
            sp_id     = _safe_id(sp)
            has_both  = bool(post_rows and pre_rows)

            repeat = (post_rows or pre_rows)[0].get("telomeric_repeat", "—")
            repeat_badge = (
                f'<span class="badge badge-green">Repeat: {repeat}</span>'
                if repeat != "—" else ""
            )

            if has_both:
                # Repeat badges for each mode
                post_repeat = post_rows[0].get("telomeric_repeat", "—")
                pre_repeat  = pre_rows[0].get("telomeric_repeat", "—")
                toggle = (
                    f'<div class="tidk-mode-toggle" id="mode-{sp_id}">'
                    f'<button class="active" data-mode="aposteriori" '
                    f'onclick="tidkSetMode(\'{sp_id}\',\'aposteriori\')">'
                    f'A posteriori'
                    f'{f" &middot; <code>{post_repeat}</code>" if post_repeat != "—" else ""}'
                    f'</button>'
                    f'<button data-mode="apriori" '
                    f'onclick="tidkSetMode(\'{sp_id}\',\'apriori\')">'
                    f'A priori'
                    f'{f" &middot; <code>{pre_repeat}</code>" if pre_repeat != "—" else ""}'
                    f'</button>'
                    f'</div>'
                )
                plot_content = (
                    f'{toggle}'
                    f'<div id="plot-aposteriori-{sp_id}">'
                    f'{tidk_line_svg(sp, post_rows, plot_id=sp + "__post")}</div>'
                    f'<div id="plot-apriori-{sp_id}" style="display:none">'
                    f'{tidk_line_svg(sp, pre_rows, plot_id=sp + "__pre")}</div>'
                )
            elif post_rows:
                plot_content = tidk_line_svg(sp, post_rows)
            else:
                plot_content = tidk_line_svg(sp, pre_rows)

            items.append(
                f'<div class="tidk-item">'
                f'<h3>{sp} {repeat_badge}</h3>'
                f'{plot_content}</div>'
            )

        panels.append(
            f'<div id="tidk" class="tab-panel">'
            f'<div class="card">'
            f'<h2>Telomeric repeat analysis</h2>'
            f'<p style="margin-bottom:14px;font-size:12px;color:#888">'
            f'Total telomere repeat density (forward + reverse) per 10 kb window.</p>'
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
        "--tidk_apriori_tsvs", nargs="*", default=[],
        metavar="TSV",
        help="tidk apriori search TSV files (one per species)",
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
    tidk_data         = parse_tidk_tsvs(args.tidk_tsvs)         if args.tidk_tsvs         else {}
    tidk_apriori_data = parse_tidk_tsvs(args.tidk_apriori_tsvs) if args.tidk_apriori_tsvs else None

    if not busco_rows and not tidk_data and not tidk_apriori_data:
        print("WARNING: no input data found; generating empty report.", file=sys.stderr)

    html = build_html(busco_rows, tidk_data, tidk_apriori_data)

    Path(args.output).write_text(html)
    print(f"Report written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
