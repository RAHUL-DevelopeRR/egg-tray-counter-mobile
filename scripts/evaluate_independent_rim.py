"""Score the independent rim reader (plan Phase E) on the registry faces, as the app sent them.

Inputs, no network and no inference:
- benchmarks/registry-20261101/manifest.json: faces, saved detections (only the column x-ranges are given to the reader;
  the detector's vertical positions are passed for the comparison fields only), photo preparation (MUTAA sets:
  EXIF-upright and resized to the sent size; 7 Oct batches: raw pixels);
- truth, never pooled: benchmarks/annotations-20261101/columns.json (tier V, hand review),
  reports/field-labelled-20261007/per_stack_counts.csv (tier A, label-implied assistant reference), and the MUTAA
  STRAIGHT per-stack consensus (tier V, only where its stack count equals the detector's column count).

Pass bars (plan step 2): 0 readable readings that agree with the detector on a known wrong count; the L-109 stack 4
disagreement exposed (a readable reading other than the detector's 18); half/double-pitch readings on at most 10% of
reviewed faces.

  python scripts/evaluate_independent_rim.py --mutaa C:/Users/rahul/MUTAA --out reports/rim-independent-20261101
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "backend"))

from app.vision.layer_span import _columns, count_layers_by_span  # noqa: E402
from app.vision.rim_count import DEFAULT_PARAMS, rim_count  # noqa: E402

LABELLED = REPO / "datasets" / "field-2026-10" / "labelled-20261007" / "originals"
# Detector readings known to be wrong (miss taxonomy, annotations): face, column, truth (None = unknown, not walk).
KNOWN_WRONG = [("img-30", 2, 20), ("img-30", 4, 20), ("mutaa:L-80:straight", 4, 20), ("mutaa:L-109-ORANGE:straight", 4, None)]


def photo(face: dict, mutaa: Path) -> Path:
    name = face["photo"]
    for candidate in (REPO / name, mutaa / name, LABELLED / Path(name).name):
        if candidate.exists():
            return candidate
    raise FileNotFoundError(name)


def prepared_bgr(face: dict, saved: dict, mutaa: Path) -> np.ndarray:
    image = Image.open(photo(face, mutaa))
    sent = (saved.get("_sent") or {}).get(face["detections"]["view"])
    if sent:
        image = ImageOps.exif_transpose(image)
        if list(image.size) != list(sent["sent"]):
            image = image.resize(tuple(sent["sent"]), Image.Resampling.LANCZOS)
    return cv2.cvtColor(np.asarray(image.convert("RGB")), cv2.COLOR_RGB2BGR)


def truths(manifest: dict) -> dict[tuple[str, int], tuple[int | None, str]]:
    out: dict[tuple[str, int], tuple[int | None, str]] = {}
    for row in csv.DictReader((REPO / "reports/field-labelled-20261007/per_stack_counts.csv").open(encoding="utf-8")):
        if row["assistant_count"].strip():
            out[(f"img-{int(row['image']):02d}", int(row["col"]))] = (int(row["assistant_count"]), "A")
    for face in manifest["faces"]:
        stacks = face["truth"].get("per_stack") if face.get("truth") else None
        if stacks:
            out.setdefault((face["id"], -len(stacks)), (None, "V-shape"))  # remembered for alignment below
    for c in json.loads((REPO / "benchmarks/annotations-20261101/columns.json").read_text(encoding="utf-8"))["columns"]:
        out[(c["face"], c["column"])] = (c["filled_layers"], "V-annotation")
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mutaa", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    mutaa = Path(args.mutaa)
    manifest = json.loads((REPO / "benchmarks/registry-20261101/manifest.json").read_text(encoding="utf-8"))
    truth = truths(manifest)
    rows = []
    for face in manifest["faces"]:
        saved = json.loads((REPO / face["detections"]["file"]).read_text(encoding="utf-8"))
        view = (saved.get("views") or saved["response"]["views"])[face["detections"]["view"]]
        try:
            image = prepared_bgr(face, saved, mutaa)
        except FileNotFoundError:
            continue
        spans = count_layers_by_span(view["detections"])
        groups = _columns(view["detections"])
        columns = []
        for span, group in zip(spans, groups, strict=False):
            widths = sorted(d["width"] for d in group)
            columns.append({**span, "x_centre": float(np.median([d["x"] for d in group])),
                            "box_width_px": float(widths[len(widths) // 2])})
        order = sorted(range(len(columns)), key=lambda i: columns[i]["x_min"])
        readings = rim_count(image, [columns[i] for i in order], DEFAULT_PARAMS)
        stacks = face["truth"].get("per_stack") if face.get("truth") else None
        for k, (i, r) in enumerate(zip(order, readings, strict=False), 1):
            t, tier = truth.get((face["id"], k), (None, None))
            if t is None and stacks and len(stacks) == len(columns):
                t, tier = stacks[k - 1], "V-consensus"
            rows.append({"face": face["id"], "column": k, "role": face["role"], "walk": columns[i]["walk_count"],
                         "rim": r["rim_count"], "rim_raw": r["rim_count_raw"], "readable": r["readable"],
                         "reason": r["unreadable_reason"], "confidence": r["confidence"], "pitch": r["pitch_px"],
                         "alternatives": r["pitch_alternatives"], "extra": r["run_extra_layers"],
                         "missing": r["run_missing_layers"], "truth": t, "tier": tier})
    known = []
    for face, col, t in KNOWN_WRONG:
        row = next((r for r in rows if r["face"] == face and r["column"] == col), None)
        if row:
            known.append({**row, "agrees_with_wrong_walk": bool(row["readable"] and row["rim"] == row["walk"]),
                          "known_truth": t})
    scored = [r for r in rows if r["truth"] is not None]
    readable = [r for r in scored if r["readable"]]
    harmonic = lambda r: r["readable"] and r["truth"] and (abs(r["rim"] - r["truth"] / 2) <= 1 or abs(r["rim"] - 2 * r["truth"]) <= 1)  # noqa: E731
    faces_reviewed = sorted({r["face"] for r in scored})
    harmonic_faces = sorted({r["face"] for r in scored if harmonic(r)})
    l109 = next((k for k in known if k["face"] == "mutaa:L-109-ORANGE:straight"), None)
    summary = {
        "params": {k: getattr(DEFAULT_PARAMS, k) for k in DEFAULT_PARAMS.__dataclass_fields__},
        "columns": len(rows), "columns_with_truth": len(scored),
        "readable_with_truth": len(readable), "coverage": round(len(readable) / len(scored), 3) if scored else None,
        "readable_exact": sum(r["rim"] == r["truth"] for r in readable),
        "readable_off_by_one": sum(abs(r["rim"] - r["truth"]) == 1 for r in readable),
        "readable_wrong": sorted(f"{r['face']}#{r['column']} rim {r['rim']} truth {r['truth']} ({r['tier']})"
                                 for r in readable if r["rim"] != r["truth"]),
        "wrong_agree": sorted(f"{r['face']}#{r['column']} {r['rim']} vs {r['truth']}" for r in readable
                              if r["rim"] == r["walk"] and r["rim"] != r["truth"]),
        "detector_wrong_caught": sorted(f"{r['face']}#{r['column']} walk {r['walk']} rim {r['rim']} truth {r['truth']}"
                                        for r in readable if r["walk"] != r["truth"] and r["rim"] != r["walk"]),
        "detector_right_contradicted": sorted(f"{r['face']}#{r['column']} walk {r['walk']} rim {r['rim']}"
                                              for r in readable if r["walk"] == r["truth"] and r["rim"] != r["walk"]),
        "known_wrong": [{k: v for k, v in r.items() if k in ("face", "column", "walk", "rim", "rim_raw", "readable", "reason",
                                                            "agrees_with_wrong_walk", "known_truth")} for r in known],
        "faces_reviewed": len(faces_reviewed), "harmonic_faces": harmonic_faces,
        "pass": {
            "no_agreement_with_known_wrong": not any(k["agrees_with_wrong_walk"] for k in known),
            "exposes_l109_stack4": bool(l109 and l109["readable"] and l109["rim"] != l109["walk"]),
            "harmonic_faces_at_most_10pct": len(harmonic_faces) <= 0.10 * max(1, len(faces_reviewed)),
        },
    }
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "results.json").write_text(json.dumps({"summary": summary, "rows": rows}, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in summary.items() if k != "params"}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
