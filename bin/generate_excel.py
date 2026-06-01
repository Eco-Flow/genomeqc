#!/usr/bin/env python3
"""Generate an Excel workbook with raw data tables from GenomeQC pipeline results.

Each tool's output is placed in a separate sheet. Multiple per-species files of
the same type are concatenated into one sheet (with the species name prepended
as an extra column where the format allows).

No external dependencies — XLSX is written using only the Python standard library.
"""

import argparse
import io
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape as _xe


# ── Minimal XLSX writer ───────────────────────────────────────────────────────

class _XLSX:
    """Write a simple xlsx workbook with no external dependencies."""

    def __init__(self):
        self._sheets = []   # [(safe_name, rows)]

    def add_sheet(self, name, rows):
        safe = name[:31].translate(str.maketrans(r'/\[]*?:', '-------'))
        self._sheets.append((safe, list(rows)))

    def save(self, path):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("[Content_Types].xml", self._content_types())
            zf.writestr("_rels/.rels",          self._root_rels())
            zf.writestr("xl/workbook.xml",       self._workbook())
            zf.writestr("xl/_rels/workbook.xml.rels", self._wb_rels())
            zf.writestr("xl/styles.xml",         self._styles())
            for i, (_, rows) in enumerate(self._sheets, 1):
                zf.writestr(f"xl/worksheets/sheet{i}.xml", self._sheet(rows))
        Path(path).write_bytes(buf.getvalue())

    # ── XML fragments ─────────────────────────────────────────────────────────

    def _content_types(self):
        overrides = "\n".join(
            f'<Override PartName="/xl/worksheets/sheet{i}.xml" '
            f'ContentType="application/vnd.openxmlformats-officedocument'
            f'.spreadsheetml.worksheet+xml"/>'
            for i in range(1, len(self._sheets) + 1)
        )
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml"  ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/styles.xml"   ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            f'{overrides}</Types>'
        )

    def _root_rels(self):
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            'Target="xl/workbook.xml"/>'
            '</Relationships>'
        )

    def _workbook(self):
        sheets = "".join(
            f'<sheet name="{_xe(name)}" sheetId="{i}" r:id="rId{i}"/>'
            for i, (name, _) in enumerate(self._sheets, 1)
        )
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            f'<sheets>{sheets}</sheets></workbook>'
        )

    def _wb_rels(self):
        rels = "".join(
            f'<Relationship Id="rId{i}" '
            f'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            f'Target="worksheets/sheet{i}.xml"/>'
            for i in range(1, len(self._sheets) + 1)
        )
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'{rels}</Relationships>'
        )

    def _styles(self):
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<fonts><font><sz val="11"/><name val="Calibri"/></font></fonts>'
            '<fills>'
            '<fill><patternFill patternType="none"/></fill>'
            '<fill><patternFill patternType="gray125"/></fill>'
            '</fills>'
            '<borders><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
            '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
            '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
            '</styleSheet>'
        )

    @staticmethod
    def _col_letter(idx):
        """0-based column index → Excel letter (A, B, …, Z, AA, …)."""
        s = ""
        idx += 1
        while idx:
            idx, r = divmod(idx - 1, 26)
            s = chr(65 + r) + s
        return s

    def _sheet(self, rows):
        rows_xml = []
        for r_i, row in enumerate(rows, 1):
            cells = []
            for c_i, val in enumerate(row):
                ref = f"{self._col_letter(c_i)}{r_i}"
                txt = "" if val is None else str(val)
                cells.append(
                    f'<c r="{ref}" t="inlineStr"><is><t>{_xe(txt)}</t></is></c>'
                )
            rows_xml.append(f'<row r="{r_i}">{"".join(cells)}</row>')
        return (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            f'<sheetData>{"".join(rows_xml)}</sheetData>'
            '</worksheet>'
        )


# ── Summary-table parsers (mirror generate_report.py) ────────────────────────

def _parse_busco_batch_summaries(paths):
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
            rows.append(dict(zip(header, parts + [""] * max(0, len(header) - len(parts)))))
    rows.sort(key=lambda r: r.get("Input_file", ""))
    return rows


def _parse_tidk_tsvs(paths):
    """Return {species: [row_dict, ...]} from tidk aposteriori search TSV files."""
    result = {}
    for p in paths:
        species = Path(p).stem.split(".")[0]
        rows = []
        header = None
        with open(p) as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.startswith("##"):
                    continue
                if header is None:
                    header = line.lstrip("#").lstrip().split("\t")
                    continue
                parts = line.split("\t")
                rows.append(dict(zip(header, parts + [""] * max(0, len(header) - len(parts)))))
        if header is not None:
            result[species] = rows
    return result


def _parse_busco_seqs_table(path):
    """Return ({species: count}, col_label) from ortho_seqs.py TSV output."""
    result = {}
    col_label = "Seqs above threshold"
    with open(path) as fh:
        lines = fh.readlines()
    if not lines:
        return result, col_label
    header = lines[0].strip().split("\t")
    count_col = next((h for h in header if h.startswith("Num_Seqs_Above_")), None)
    if count_col:
        threshold = count_col.replace("Num_Seqs_Above_", "")
        col_label = f"Seqs >{threshold} BUSCOs"
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t")
        row = dict(zip(header, parts))
        sp_id = row.get("Id", "")
        if sp_id and count_col:
            try:
                result[sp_id] = int(row[count_col])
            except (ValueError, KeyError):
                result[sp_id] = "—"
    return result, col_label


def _summary_rows(busco_rows, tidk_data, busco_seqs_data=None, busco_seqs_col=None):
    """Build the summary table rows (header + data) mirroring the HTML overview."""
    species_set = {r.get("Input_file", "") for r in busco_rows} | set(tidk_data.keys())
    species_list = sorted(s for s in species_set if s)
    busco_by_species = {r.get("Input_file", ""): r for r in busco_rows}

    cols = ["Species", "BUSCO complete (%)", "BUSCO lineage",
            "Scaffold N50", "# scaffolds", "Telomeric repeat"]
    if busco_seqs_data is not None:
        cols.append(busco_seqs_col or "Seqs above threshold")
    rows = [cols]
    for sp in species_list:
        br = busco_by_species.get(sp, {})
        try:
            complete = f"{float(br.get('Complete', 0)):.1f}%"
        except (ValueError, TypeError):
            complete = br.get("Complete", "—") or "—"
        n50        = br.get("Scaffold N50", "—") or "—"
        n_scaffolds = br.get("Number of scaffolds", "—") or "—"
        lineage    = br.get("Dataset", "—") or "—"
        tidk_sp    = tidk_data.get(sp, [])
        repeat     = tidk_sp[0].get("telomeric_repeat", "—") if tidk_sp else "—"
        cells = [sp, complete, lineage, n50, n_scaffolds, repeat]
        if busco_seqs_data is not None:
            cells.append(str(busco_seqs_data.get(sp, "—")))
        rows.append(cells)
    return rows


# ── TSV/TXT readers ───────────────────────────────────────────────────────────

def _read_tsv(path, skip_comment=True):
    """Yield rows (list of str) from a TSV, stripping leading # from header."""
    with open(path) as fh:
        first = True
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            if skip_comment and line.startswith("##"):
                continue  # metadata lines (e.g. FCS-GX JSON header) — always skip
            if first and skip_comment:
                line = line.lstrip("#").lstrip()
                first = False
            elif skip_comment and line.startswith("#"):
                continue
            yield line.split("\t")


def _combine_tsv_files(paths, add_species_col=True):
    """Concatenate multiple TSV files into a single list of rows.

    When add_species_col is True, a 'species' column is prepended and the
    header is written once (from the first file).
    """
    rows = []
    header_written = False
    for p in sorted(paths, key=lambda x: Path(x).name):
        species = Path(p).stem.split(".")[0]  # strip extra suffixes
        file_rows = list(_read_tsv(p))
        if not file_rows:
            continue
        if not header_written:
            header = (["species"] + file_rows[0]) if add_species_col else file_rows[0]
            rows.append(header)
            header_written = True
            data_rows = file_rows[1:]
        else:
            data_rows = file_rows[1:]   # skip repeated header
        if data_rows:
            for r in data_rows:
                rows.append(([species] + r) if add_species_col else r)
        elif add_species_col:
            rows.append([species, "no contamination detected"] + [""] * (len(file_rows[0]) - 1))
    return rows


def _agat_stats_rows(paths):
    """Parse AGAT spstatistics *.txt files (key: value text format) into rows."""
    rows = [["species", "metric", "value"]]
    for p in sorted(paths, key=lambda x: Path(x).name):
        species = Path(p).stem
        with open(p) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("-"):
                    continue
                if ":" in line:
                    key, _, val = line.partition(":")
                    rows.append([species, key.strip(), val.strip()])
    return rows


def _quast_rows(paths):
    """Combine per-species QUAST report TSVs.

    QUAST TSV is transposed (metric rows, species column). Each file has
    two columns: metric name and value. We pivot to species-as-columns.
    """
    # Read all files first
    species_data = {}  # species -> {metric: value}
    metric_order = []
    for p in sorted(paths, key=lambda x: Path(x).name):
        species = Path(p).stem.replace(".quast", "")
        data = {}
        file_rows = list(_read_tsv(p, skip_comment=False))
        for row in file_rows:
            if len(row) >= 2:
                metric = row[0]
                val    = row[1]
                data[metric] = val
                if metric not in metric_order:
                    metric_order.append(metric)
        species_data[species] = data

    if not species_data:
        return []

    species_list = sorted(species_data.keys())
    header = ["metric"] + species_list
    rows = [header]
    for m in metric_order:
        rows.append([m] + [species_data[sp].get(m, "") for sp in species_list])
    return rows


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description="Generate an Excel workbook with raw GenomeQC result tables."
    )
    ap.add_argument("--busco_tables",         nargs="*", default=[], metavar="TSV",
                    help="BUSCO batch_summary_modified.txt files")
    ap.add_argument("--busco_seqs_table",     default=None, metavar="TSV",
                    help="ortho_seqs.py output TSV (sequences above BUSCO threshold)")
    ap.add_argument("--quast_tsvs",           nargs="*", default=[], metavar="TSV",
                    help="Per-species QUAST report TSV files")
    ap.add_argument("--agat_stats",           nargs="*", default=[], metavar="TXT",
                    help="AGAT spstatistics *.txt files")
    ap.add_argument("--tidk_tsvs",            nargs="*", default=[], metavar="TSV",
                    help="tidk aposteriori search TSV files")
    ap.add_argument("--fcs_gx_reports",       nargs="*", default=[], metavar="TXT",
                    help="FCS-GX *.fcs_gx_report.txt files (optional)")
    ap.add_argument("--fcs_adaptor_reports",  nargs="*", default=[], metavar="TXT",
                    help="FCS-Adaptor *.fcs_adaptor_report.txt files (optional)")
    ap.add_argument("--tiara_reports",        nargs="*", default=[], metavar="TXT",
                    help="Tiara classification *.txt files (optional)")
    ap.add_argument("--output", default="genomeqc_tables.xlsx", metavar="XLSX",
                    help="Output Excel file (default: genomeqc_tables.xlsx)")
    args = ap.parse_args()

    wb = _XLSX()
    added = 0

    # ── Summary sheet (first) ─────────────────────────────────────────────────
    busco_rows_dicts = _parse_busco_batch_summaries(args.busco_tables) if args.busco_tables else []
    tidk_data_dicts  = _parse_tidk_tsvs(args.tidk_tsvs)               if args.tidk_tsvs  else {}
    busco_seqs_data, busco_seqs_col = (
        _parse_busco_seqs_table(args.busco_seqs_table)
        if args.busco_seqs_table else (None, None)
    )
    if busco_rows_dicts or tidk_data_dicts:
        summary = _summary_rows(busco_rows_dicts, tidk_data_dicts, busco_seqs_data, busco_seqs_col)
        wb.add_sheet("Summary", summary)
        added += 1

    if args.busco_tables:
        rows = _combine_tsv_files(args.busco_tables, add_species_col=False)
        if rows:
            wb.add_sheet("BUSCO", rows)
            added += 1

    if args.quast_tsvs:
        rows = _quast_rows(args.quast_tsvs)
        if rows:
            wb.add_sheet("Assembly_QUAST", rows)
            added += 1

    if args.agat_stats:
        rows = _agat_stats_rows(args.agat_stats)
        if rows:
            wb.add_sheet("Annotation_AGAT", rows)
            added += 1

    if args.tidk_tsvs:
        rows = _combine_tsv_files(args.tidk_tsvs, add_species_col=True)
        if rows:
            wb.add_sheet("Telomeres_tidk", rows)
            added += 1

    if args.fcs_gx_reports:
        rows = _combine_tsv_files(args.fcs_gx_reports, add_species_col=True)
        if rows:
            wb.add_sheet("FCS_GX", rows)
            added += 1

    if args.fcs_adaptor_reports:
        rows = _combine_tsv_files(args.fcs_adaptor_reports, add_species_col=True)
        if rows:
            wb.add_sheet("FCS_Adaptor", rows)
            added += 1

    if args.tiara_reports:
        rows = _combine_tsv_files(args.tiara_reports, add_species_col=True)
        if rows:
            wb.add_sheet("Tiara", rows)
            added += 1

    if added == 0:
        print("WARNING: no input data found; writing empty workbook.", file=sys.stderr)
        wb.add_sheet("empty", [["no data"]])

    wb.save(args.output)
    print(f"Workbook written to {args.output} ({added} sheet(s))", file=sys.stderr)


if __name__ == "__main__":
    main()
