# Design proposal: quality scoring ("traffic lights") for the circular tree plot

**Status:** Phase 1 implemented. Phase 2 (Merqury + FCS plumbing) still to do.

> **Note:** this is the original design proposal, kept for historical rationale.
> Numeric cut-offs quoted below (§3.1) predate the per-clade preset system and
> no longer match what's shipped - they show a single global proposal, not the
> six `--quality_preset` values (`generic`, `vertebrate`, `insect`, `plant`,
> `fungi`, `bacteria`) actually implemented. For current thresholds, see
> `QUALITY_PRESETS` in `bin/plot_tree_summary.R`/`bin/tree_functions.R`, or the
> "Circular tree quality scoring" section in `docs/usage.md`.

## 0. Decisions taken (review outcome)

- The static figure **mixes** traffic-lit quality rings with neutral descriptive
  rings (it is not quality-only).
- BUSCO is limited to **% complete (genome and protein)** plus an optional
  **% duplicated**. There is **no "missing" ring** — it is essentially the
  inverse of complete.
- Thresholds come from a **phylogenetic-group preset** the user selects
  (`--quality_preset`), defaulting to a deliberately lenient **`generic`**;
  eukaryote/vertebrate standards are too strict as a global default. The preset
  is also selectable in the Shiny app.
- **Printed values** are available as an opt-in redundant encoding
  (`--show_ring_values`), so the figure is not colour-only.
- The traffic light uses the **colour-vision-safe** Okabe–Ito triple.

## 1. The problem

The circular plot currently draws every ring with a sequential `low -> high`
colour ramp (light -> dark). A reader inevitably interprets **dark = high =
good**. That reading is only correct for some of the statistics:

| Ring           | Reads as "dark = good"? | Reality                                          |
| -------------- | ----------------------- | ------------------------------------------------ |
| BUSCO complete | correct                 | higher really is better                          |
| N50            | correct                 | higher really is better                          |
| **Seq number** | **wrong**               | dark = thousands of contigs = a _worse_ assembly |
| Genome size    | meaningless             | a biological property; big is not "good"         |
| Gene number    | meaningless             | varies by lineage                                |
| GC %           | meaningless             | biology, not quality                             |
| Ortho seqs     | meaningless             | synteny/descriptive                              |

So the plot is actively misleading for `Seq number`, and it implies a
good/bad judgement for several stats that simply do not have one.

## 2. Principles

1. **Split the statistics into two classes**, and colour them differently:
   - **Quality metrics** — have a defensible "good" direction and thresholds.
     Draw as a **discrete traffic light** (good / warn / poor).
   - **Descriptive metrics** — no good/bad direction. Draw with a **neutral**
     sequential palette that does not imply a judgement.
2. **Never encode a direction we cannot defend.** If a metric has no "good"
   value, it must not be traffic-lit.
3. **Thresholds are clade-dependent** and must be configurable (see §5).
4. Optional tools (Merqury, FCS, tidk) must **degrade gracefully**: if the tool
   did not run, its ring is simply absent (the existing registry already
   behaves this way).

## 3. Metric inventory

### 3.1 Quality metrics (traffic light)

Direction: ↑ = higher is better, ↓ = lower is better.

| Metric                        | Tool        | Dir | Good (green) | Warn (amber) | Poor (red) | Available today    |
| ----------------------------- | ----------- | --- | ------------ | ------------ | ---------- | ------------------ |
| BUSCO complete, genome        | BUSCO       | ↑   | ≥ 95 %       | 90–95 %      | < 90 %     | yes                |
| BUSCO complete, protein       | BUSCO       | ↑   | ≥ 95 %       | 90–95 %      | < 90 %     | yes                |
| BUSCO duplicated _(optional)_ | BUSCO       | ↓   | < 5 %        | 5–10 %       | > 10 %     | yes                |
| Scaffold N50                  | QUAST       | ↑   | ≥ 10 Mb      | 1–10 Mb      | < 1 Mb     | yes                |
| Sequence count                | QUAST       | ↓   | _see §5_     |              |            | yes                |
| Consensus QV                  | Merqury     | ↑   | ≥ 40         | 30–40        | < 30       | **needs plumbing** |
| k-mer completeness            | Merqury     | ↑   | ≥ 95 %       | 90–95 %      | < 90 %     | **needs plumbing** |
| Contamination %               | FCS-GX      | ↓   | < 0.1 %      | 0.1–1 %      | > 1 %      | **needs plumbing** |
| Adaptor hits                  | FCS-adaptor | ↓   | none         | few          | many       | **needs plumbing** |
| Foreign-domain seqs           | Tiara       | ↓   | low          |              | high       | **needs plumbing** |
| Telomere-complete scaffolds   | tidk        | ↑   | —            |              |            | **needs plumbing** |

**BUSCO scope (per review):** show **% complete** for **genome** and **protein**
only, plus optionally **% duplicated**. We deliberately **do not** show
_missing_: `complete + fragmented + missing ≈ 100 %`, so a missing ring is
largely the inverse of the complete ring and adds no information.

_Complete_ = Single + Duplicated. _Duplicated_ is worth its own ring because a
high value flags uncollapsed haplotypes / assembly duplication — a distinct
failure mode that a single "complete" number hides.

The default N50/QV/BUSCO cut-offs above follow EBP/VGP-style assembly
standards (contig NG50 ≈ 1 Mb, scaffold NG50 ≈ 10 Mb, QV ≥ 40,
BUSCO ≥ 90 %). They are **defaults, not law** — see §5.

### 3.2 Descriptive metrics (neutral palette, never traffic-lit)

| Metric         | Tool                 | Why not quality                                    |
| -------------- | -------------------- | -------------------------------------------------- |
| Genome size    | QUAST                | biological property                                |
| GC %           | QUAST                | biology; only extreme values hint at contamination |
| Gene number    | AGAT / gene overlaps | varies by lineage                                  |
| Ortho seqs     | OrthoFinder          | synteny/descriptive                                |
| Seqs ≥5 BUSCOs | BUSCO-derived        | ambiguous direction                                |

## 4. Colour design

A literal red/amber/green traffic light is a poor choice for red–green colour
blindness (~8 % of men). Proposal: keep the traffic-light _semantics_ but use a
colour-vision-safe triple (Okabe–Ito):

| State | Colour       | Hex       |
| ----- | ------------ | --------- |
| Good  | bluish green | `#009E73` |
| Warn  | orange       | `#E69F00` |
| Poor  | vermillion   | `#D55E00` |

These stay distinguishable under deuteranopia/protanopia while still reading as
good → bad. Descriptive rings would use a single neutral hue (e.g. greys or a
muted blue) so they are visually _distinct from_ the quality rings — the reader
can tell at a glance which rings are judgements and which are just data.

Because colour is the only channel available in a ring, we should consider a
redundant encoding (e.g. printing the value, or a hatch/opacity) so the figure
is not colour-only. **Open question** — see §8.

## 5. Thresholds: the hard part

**Absolute cut-offs do not travel across clades.** The N50 defaults above are
eukaryote-oriented and are _nonsense_ for the bacterial test data: a
_Mycoplasma_ genome is < 1 Mb in **total**, so it can never reach a 10 Mb
"green" scaffold N50. The same applies to sequence count (a good bacterial
assembly may be 1 contig; a good mammal may be thousands of scaffolds).

Options, in increasing order of robustness:

1. **Configurable absolute thresholds** (params). Simple, explicit, but the
   user must set sensible values per project.
2. **Relative / normalised metrics** — travel much better across clades:
   - N50 as a fraction of total assembly length (or `auN`).
   - Sequence count relative to the expected chromosome number.
   - Assembly size as % deviation from an expected genome size.
3. **Per-clade threshold presets** shipped with the pipeline (e.g. `vertebrate`,
   `insect`, `plant`, `bacteria`), selectable with one parameter.

**Recommendation:** implement (1) as the mechanism, ship eukaryote defaults, and
add (3) later as presets on top. Offer (2) for N50 and sequence count where the
normalisation is unambiguous.

### Config surface (implemented)

```
--quality_preset      generic|vertebrate|insect|plant|fungi|bacteria
--quality_thresholds  'metric=good:warn,metric=good:warn'   # overrides individual preset cut-offs
```

e.g. `--quality_preset bacteria --quality_thresholds 'n50=2e6:5e5,seq_number=50:500'`. Direction
(higher/lower is better) is fixed per metric and not settable from the CLI, so a threshold
cannot silently invert a metric's meaning. A file-based (`.yml`/`.json`) surface was considered
but dropped in favour of an inline string: it needs no new R dependency (no YAML/JSON parser is
installed in the `genomeqc_tree` container) and no extra Nextflow file-staging plumbing. The same
overrides are also settable interactively in the Shiny app ("Custom..." preset).

## 6. Plumbing plan (Merqury + FCS)

Good news: the channels already exist in `workflows/genomeqc.nf` and currently
feed `HTML_REPORT`. Routing them into `TREE_SUMMARY` is mostly adding module
inputs, not building new plumbing.

| Channel                                             | Defined at        | Currently used by |
| --------------------------------------------------- | ----------------- | ----------------- |
| `ch_merqury_qv` (`MERQURY_MERQURY.out.assembly_qv`) | `genomeqc.nf:219` | —                 |
| `ch_merqury_stats` (`.out.stats`)                   | `genomeqc.nf:220` | —                 |
| `ch_fcsgx` (`DECONTAMINATION.out.fcs_gx_report`)    | `genomeqc.nf:417` | `HTML_REPORT`     |
| `ch_fcsadp` (`.out.adaptor_report`)                 | `genomeqc.nf:418` | `HTML_REPORT`     |
| `ch_tiara` (`.out.tiara_cleaned`)                   | `genomeqc.nf:419` | `HTML_REPORT`     |

Work required:

1. Add optional inputs to `modules/local/tree_summary.nf` for the Merqury and
   FCS files (optional, so the module still runs when those tools are skipped).
2. Pass the existing channels in `workflows/genomeqc.nf`.
3. Write small parsers (a `*_2_table.py`, mirroring `quast_2_table.py`) to
   reduce each tool's output to one value per species:
   - **Merqury QV** — `${prefix}.qv`: tab-separated, QV is a numeric column.
   - **Merqury completeness** — `*.completeness.stats`: completeness %.
   - **FCS-GX** — `*.fcs_gx_report.txt`: sum the lengths of sequences actioned
     as `EXCLUDE`/`TRIM`, divide by assembly length → contamination %.
     > The exact column layouts must be **verified against real outputs** before
     > coding; the above is from the module definitions, not from inspecting a
     > real run.
4. Add the new stats to the ring registry in `build_circular_plot`
   (`bin/plot_tree_summary.R` and `bin/tree_functions.R`) with a `scale`
   (`quality` | `descriptive`) and a `direction`.

**Gating:** Merqury only runs when reads (FASTQ) are supplied; FCS only when
`--gxdb`/`--gxdb_manifest` is set. Both rings must therefore be optional — the
registry's "no data → no ring" behaviour already covers this.

## 7. Implementation phases

- **Phase 1 — DONE.** The ring registry now tags each stat as `quality` (discrete
  traffic light, scored against the selected preset) or `descriptive`
  (sequential ramp, no good/bad implied). Quality rings: sequence count, N50,
  BUSCO complete (genome + protein), BUSCO duplicated. All quality rings share a
  single Good/Warn/Poor legend, so a **ring key (inner -> outer)** is drawn
  alongside the species key to identify them. New options:
  `--quality_preset`, `--quality_thresholds` (per-metric overrides on top of the
  preset), `--show_ring_values` (plus the equivalents in the Shiny app).
  **This fixes the misleading sequence-count colour.**
- **Phase 2.** Plumb Merqury (QV, k-mer completeness) and FCS-GX
  (contamination %) into `TREE_SUMMARY`; add their rings.
- **Phase 3 (optional).** tidk telomere completeness, FCS-adaptor, Tiara;
  per-clade threshold presets.

## 8. Open questions

1. **Legend for traffic lights.** A discrete good/warn/poor legend replaces the
   continuous colourbar. Do we also want to keep the underlying value visible
   (e.g. printed in the ring, or a tooltip in the Shiny app)?
2. **Redundant encoding.** Colour-only is an accessibility risk. Worth adding a
   value label or texture?
3. **Mixed figure.** Should a single plot be allowed to mix traffic-light rings
   and neutral descriptive rings (recommended), or should quality and
   descriptive be separate figures?
4. **Static default.** Should the curated static figure default to
   _quality-only_ rings (BUSCO ×2, N50, seq count, + QV/contamination when
   available)?
5. **Threshold defaults.** Ship eukaryote defaults (and document that the
   bacterial test profile will look "red"), or ship no defaults and require the
   user to opt in to traffic lights?
