"""Evaluate the independent rim count on the 13 straight-on labelled field photos.

For each photo the archived production detections (reports/field-labelled-20261007/raw)
are regrouped into stack columns with ``layer_span.count_layers_by_span`` exactly as the
Worker does, ``rim_count`` is run on the EXIF-transposed image, and the result is scored
against the per-stack reference in per_stack_counts.csv (``assistant_count``; blank where
the stack was left unresolved). Writes results.csv, README.md and one overlay per photo.

This is tuning on the same set the thresholds were chosen on, not validation. The photos
are WhatsApp copies (0.2-1.9 MP); originals from the field carry more detail.

Usage (from the repository root, PYTHONPATH="work/vision-deps;backend"):
  python scripts/evaluate_rim_count.py [--out reports/rim-count-20261009]
                                       [--params '{"smooth_fraction": 0.12}']
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import asdict
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

from app.vision.layer_span import count_layers_by_span
from app.vision.rim_count import DEFAULT_PARAMS, RimParams, rim_count

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "reports" / "field-labelled-20261007" / "raw"
REFERENCE = ROOT / "reports" / "field-labelled-20261007" / "per_stack_counts.csv"
ORIGINALS = ROOT / "datasets" / "field-2026-10" / "labelled-20261007" / "originals"
STRAIGHT_ON = [1, 2, 4, 8, 9, 19, 20, 21, 23, 24, 30, 34, 50]


def archived_detections() -> dict[int, list[dict]]:
    """First archived response per image id (images 1 and 2 were sent twice with identical results)."""
    found: dict[int, list[dict]] = {}
    for path in sorted(RAW.glob("batch-*.json")):
        record = json.loads(path.read_text())
        for view, image_id in record["ids"].items():
            if image_id in STRAIGHT_ON and image_id not in found:
                found[image_id] = record["response"]["views"][view]["detections"]
    return found


def load_bgr(image_id: int) -> np.ndarray:
    path = next(ORIGINALS.glob(f"img-{image_id:02d}.*"))
    with Image.open(path) as picture:
        rgb = np.asarray(ImageOps.exif_transpose(picture).convert("RGB"))
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)


def references() -> dict[tuple[int, int], int | None]:
    table: dict[tuple[int, int], int | None] = {}
    with REFERENCE.open(newline="") as handle:
        for row in csv.DictReader(handle):
            value = row["assistant_count"].strip()
            table[(int(row["image"]), int(row["col"]))] = int(value) if value else None
    return table


def draw_overlay(
    image: np.ndarray, columns: list[dict], results: list[dict], params: RimParams
) -> np.ndarray:
    canvas = image.copy()
    height, width = canvas.shape[:2]
    for column, result in zip(columns, results, strict=True):
        pad = (column["x_max"] - column["x_min"]) * params.widen_fraction / 2.0
        xa = int(max(0.0, column["x_min"] - pad))
        xb = int(min(float(width), column["x_max"] + pad))
        margin = params.window_fraction * column["pitch_px"]
        ya = int(max(0.0, column["y_first"] - margin))
        yb = int(min(float(height), column["y_last"] + margin))
        cv2.rectangle(canvas, (xa, ya), (xb - 1, yb - 1), (255, 160, 0), 1)
        core = int(round((xb - xa) * (1.0 - params.core_fraction) / 2.0))
        for y in result["peaks_y"]:
            cv2.line(canvas, (xa + core, int(round(y))), (xb - core, int(round(y))), (0, 0, 255), 1)
        label = f"c{column['column']} span {column['span_count']} rim {result['rim_count']}"
        colour = (0, 200, 0) if result["agrees_with_span"] else (0, 0, 255)
        cv2.putText(canvas, label, (xa + 2, max(12, ya - 4)), cv2.FONT_HERSHEY_SIMPLEX, 0.4, colour, 1)
    return canvas


def evaluate(out_dir: Path, params: RimParams) -> list[dict]:
    overlays = out_dir / "overlays"
    overlays.mkdir(parents=True, exist_ok=True)
    detections = archived_detections()
    reference = references()
    rows = []
    for image_id in STRAIGHT_ON:
        image = load_bgr(image_id)
        columns = count_layers_by_span(detections[image_id])
        results = rim_count(image, columns, params)
        cv2.imwrite(str(overlays / f"img-{image_id:02d}.png"), draw_overlay(image, columns, results, params))
        for column, result in zip(columns, results, strict=True):
            ref = reference.get((image_id, column["column"]))
            rows.append(
                {
                    "image": image_id,
                    "col": column["column"],
                    "reference": "" if ref is None else ref,
                    "span_count": column["span_count"],
                    "rim_count": "" if result["rim_count"] is None else result["rim_count"],
                    "agrees": "" if result["agrees_with_span"] is None else int(result["agrees_with_span"]),
                    "confidence": result["confidence"],
                    "perspective_gradient": "" if result["perspective_gradient"] is None
                    else result["perspective_gradient"],
                    "model_boxes": column["model_boxes"],
                    "pitch_px": column["pitch_px"],
                    "inferred_rims": result["inferred_rims"],
                    "peaks": len(result["peaks_y"]),
                    "note": result["note"],
                }
            )
    with (out_dir / "results.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return rows


def summarise(rows: list[dict]) -> dict:
    scored = [r for r in rows if r["reference"] != "" and r["rim_count"] != ""]
    unscored = [r for r in rows if r["reference"] == ""]
    none_count = sum(r["rim_count"] == "" for r in rows)
    stats = {"columns": len(rows), "scored": len(scored), "unresolved": len(unscored), "rim_none": none_count}
    for key in ("rim_count", "span_count"):
        stats[f"{key}_exact"] = sum(int(r[key]) == int(r["reference"]) for r in scored)
        stats[f"{key}_within1"] = sum(abs(int(r[key]) - int(r["reference"])) <= 1 for r in scored)
    span_wrong = [r for r in scored if int(r["span_count"]) != int(r["reference"])]
    span_right = [r for r in scored if int(r["span_count"]) == int(r["reference"])]
    stats["span_wrong"] = len(span_wrong)
    stats["caught"] = sum(int(r["rim_count"]) != int(r["span_count"]) for r in span_wrong)
    stats["caught_and_exact"] = sum(int(r["rim_count"]) == int(r["reference"]) for r in span_wrong)
    stats["span_right"] = len(span_right)
    stats["false_alarms"] = sum(int(r["rim_count"]) != int(r["span_count"]) for r in span_right)
    high = [r for r in scored if float(r["confidence"]) >= 0.6]
    stats["high_confidence"] = len(high)
    stats["high_confidence_exact"] = sum(int(r["rim_count"]) == int(r["reference"]) for r in high)
    high_right = [r for r in high if int(r["span_count"]) == int(r["reference"])]
    high_wrong = [r for r in high if int(r["span_count"]) != int(r["reference"])]
    stats["high_confidence_false_alarms"] = sum(
        int(r["rim_count"]) != int(r["span_count"]) for r in high_right
    )
    stats["high_confidence_caught"] = sum(int(r["rim_count"]) != int(r["span_count"]) for r in high_wrong)
    stats["high_confidence_span_wrong"] = sum(int(r["span_count"]) != int(r["reference"]) for r in high)
    return stats


def write_readme(out_dir: Path, rows: list[dict], stats: dict, params: RimParams) -> None:
    def pct(a: int, b: int) -> str:
        return f"{a}/{b} ({100.0 * a / b:.0f}%)" if b else f"{a}/{b}"

    lines = [
        "# Independent rim count vs span count - 9 October 2026",
        "",
        "Second, detector-independent layer count per stack column from horizontal rim edges in the",
        "image (`backend/app/vision/rim_count.py`), compared with the production span count",
        "(`layer_span.count_layers_by_span`) on the 13 straight-on labelled field photos",
        "(1, 2, 4, 8, 9, 19, 20, 21, 23, 24, 30, 34, 50). Produced by `scripts/evaluate_rim_count.py`.",
        "",
        "**Read this first.** The thresholds below were chosen by sweeping them on these same 13",
        "photos and picking the best catch/false-alarm trade-off. This is tuning, not validation;",
        "the numbers are optimistic for new photos. All 13 are WhatsApp copies (0.2-1.9 MP, no EXIF,",
        "chroma-subsampled); originals captured in the field carry more detail per layer, which should",
        "help the edge signal but has not been measured.",
        "",
        "## Inputs",
        "",
        "- Detector boxes: archived production responses `reports/field-labelled-20261007/raw/batch-*.json`",
        "  (Roboflow projec-mutta/2), regrouped into columns with `count_layers_by_span` (same code as",
        "  the Worker port). The rim count uses only each column's x-extent, y-extent and detector pitch",
        "  as a prior; it never counts boxes.",
        "- Reference: `per_stack_counts.csv` column `assistant_count` (per-stack values inferred from the",
        "  user's scene totals plus visual inspection on 2026-10-08, not physical recounts). Columns of",
        "  images 4, 9 and 50 have no reference (multi-depth scenes, close-up perspective) and are",
        "  listed in results.csv but excluded from the scores.",
        "",
        "## Method (as implemented)",
        "",
        "- Strip = column widened by 10 %; signal = Sobel-Y of the "
        f"{params.channel} channel, polarity `{params.polarity}`",
        "  (bright-to-dark going down = rim underside / egg-to-tray edge), reduced across the central",
        f"  {params.core_fraction:.0%} of the strip by `{params.aggregate}`, Gaussian-smoothed with sigma =",
        f"  {params.smooth_fraction} x pitch, robustly normalised (median/MAD).",
        f"- Search window: y_first - {params.window_fraction} x pitch to y_last + "
        f"{params.window_fraction} x pitch.",
        f"- Candidate peaks need prominence >= {params.prominence_fraction} x a reference prominence: the",
        "  median of the six strongest peaks within +/-3 pitches of the candidate (local_prominence =",
        f"  {params.local_prominence}), floored at a quarter of the strip-wide strong-peak median. A",
        "  strip-wide threshold loses the perspective-compressed layers at the far end of a column.",
        f"- Peaks are accepted top to bottom with a minimum distance of {params.min_distance_fraction} x the",
        "  local pitch; the local pitch starts at the detector pitch and follows the running median of",
        "  the last three accepted gaps, each gap first divided by its rounded multiple of the current",
        "  local pitch so one missed rim cannot drag the tracker onto double pitch (clamped to",
        f"  {params.pitch_clamp[0]}-{params.pitch_clamp[1]} x detector pitch).",
        f"- A gap of about two local pitches counts as one inferred (missed) rim: infer_missing = "
        f"{params.infer_missing}.",
        "- End rule: stacked trays alternate orientation, so consecutive gaps alternate long/short while",
        "  each pair of gaps still spans two pitches; when the pair of gaps at a stack end is shorter",
        f"  than {params.end_pair_ratio} x the next pair, the weaker of the two end peaks is dropped (an",
        "  extra half-pitch edge from the floor, a pallet or the row of eggs behind).",
        "- confidence = 0.6 x regularity of gap-pair sums + 0.4 x relative prominence - 0.15 per",
        "  inferred rim. It is a diagnostic score, not a probability.",
        "- perspective_gradient = median of the top-third gaps / median of the bottom-third gaps.",
        "",
        "Parameters (`RimParams` defaults):",
        "",
        "```json",
        json.dumps(asdict(params), indent=2),
        "```",
        "",
        "## Results (measured on this set; same set as the tuning)",
        "",
        f"Columns: {stats['columns']} in 13 photos; {stats['scored']} with a reference; "
        f"{stats['unresolved']} without; rim_count None on {stats['rim_none']}.",
        "",
        "| Per column vs reference | exact | within +/-1 |",
        "|---|---:|---:|",
        f"| rim_count | {pct(stats['rim_count_exact'], stats['scored'])} | "
        f"{pct(stats['rim_count_within1'], stats['scored'])} |",
        f"| span_count | {pct(stats['span_count_exact'], stats['scored'])} | "
        f"{pct(stats['span_count_within1'], stats['scored'])} |",
        "",
        "Key numbers (disagreement = rim_count != span_count):",
        "",
        f"- span WRONG vs reference: {stats['span_wrong']} columns; rim disagrees with span (caught) on "
        f"**{pct(stats['caught'], stats['span_wrong'])}**, and gives the reference value on "
        f"{stats['caught_and_exact']} of them.",
        f"- span RIGHT vs reference: {stats['span_right']} columns; rim wrongly disagrees (false alarm) on "
        f"**{pct(stats['false_alarms'], stats['span_right'])}**.",
        f"- Restricted to confidence >= 0.6 ({stats['high_confidence']} columns): rim exact "
        f"{pct(stats['high_confidence_exact'], stats['high_confidence'])}, caught "
        f"{stats['high_confidence_caught']}/{stats['high_confidence_span_wrong']}, false alarms "
        f"{stats['high_confidence_false_alarms']}/"
        f"{stats['high_confidence'] - stats['high_confidence_span_wrong']}.",
        "",
        "Per column (reference blank = unresolved stack):",
        "",
        "| image | col | reference | span | rim | agrees | confidence | gradient | inferred | note |",
        "|---:|---:|---:|---:|---:|:---:|---:|---:|---:|---|",
    ]
    for r in rows:
        lines.append(
            f"| {r['image']} | {r['col']} | {r['reference']} | {r['span_count']} | {r['rim_count']} | "
            f"{'yes' if r['agrees'] == 1 else 'no' if r['agrees'] == 0 else ''} | {r['confidence']} | "
            f"{r['perspective_gradient']} | {r['inferred_rims']} | {r['note']} |"
        )
    lines += [
        "",
        "## Reading the result",
        "",
        "- A disagreement is a flag to rescan or count by hand, not a corrected count. Neither number",
        "  is verified; `verified` stays false everywhere.",
        "- Where span is wrong because the layer is physically outside the photo (crop cuts the base or",
        "  the top), the rim count cannot see it either; those columns stay agreeing and wrong.",
        "- Columns whose strip overlaps a neighbouring stack at a different depth carry mixed rims; the",
        "  overlays (`overlays/img-NN.png`: orange = strip and search window, red = accepted rims,",
        "  label green = agrees, red = disagrees) show where this happens.",
        "- Images 21 and 24 are 582 px tall with a 19 px pitch; the bottom layers lose their edge in the",
        "  WhatsApp copy and are filled by inferred rims with low confidence.",
        "",
        "## What was tried and rejected (same set)",
        "",
        "- Green channel instead of gray: consistently worse (WhatsApp chroma subsampling halves the",
        "  vertical chroma resolution). Bright-to-dark-below polarity beats the opposite polarity and the",
        "  absolute edge signal (two edges per layer, the half-pitch trap).",
        "- Per-row median or edge-support fraction across the strip instead of the mean: no gain.",
        "- A strip-wide prominence threshold: loses the compressed far end of perspective columns.",
        "- Peak height above the baseline, or height over the deeper adjacent trough, instead of",
        "  prominence: both much worse (baseline drift along the strip; distant bases inflate weak",
        "  peaks). Prominence keeps a known bias against the last rim when the floor below is flat.",
        "- Running median of raw gaps for the local pitch: one missed rim drags the tracker to double",
        "  pitch and every second rim is then skipped; dividing each gap by its rounded multiple fixed it.",
        "- Before the local threshold and the end rule the best setting reached 30/53 exact with 16/40",
        "  false alarms; after them 38/53 with 9/40 (measured, same set).",
        "",
        "## Expectations (not measured)",
        "",
        "- Field originals (full resolution, no chroma subsampling, no re-encode) should give sharper rim",
        "  edges and fewer inferred rims; the min-distance and prominence thresholds are relative to the",
        "  pitch and the strip's own signal, so they should transfer, but this has to be measured on the",
        "  first field set before any threshold is trusted.",
        "- Held-out validation is required before using the disagreement flag to withhold totals.",
        "",
        "Files: `results.csv` (one row per column), `overlays/` (one PNG per photo).",
    ]
    (out_dir / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--out", default=str(ROOT / "reports" / "rim-count-20261009"))
    parser.add_argument("--params", default="", help="JSON object overriding RimParams fields")
    args = parser.parse_args()
    params = RimParams(**{**asdict(DEFAULT_PARAMS), **(json.loads(args.params) if args.params else {})})
    out_dir = Path(args.out)
    rows = evaluate(out_dir, params)
    stats = summarise(rows)
    write_readme(out_dir, rows, stats, params)
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
