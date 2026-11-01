"""Draw a saved response's detector boxes on the photo, coloured by the stack column the counter put them in.

For the Phase B miss taxonomy (reports/miss-taxonomy-20261101): shows whether a short count is a missed end tray,
a layer lost inside the stack, a box placed in the wrong column, a dropped or merged column, or a neighbouring
block. Columns come from backend/app/vision/layer_span.py (the Worker's spanColumns has parity with it).

The image is prepared the way it was sent: for MUTAA set responses (with `_sent`), EXIF-upright and resized to the
sent size; for the 7 Oct labelled batches, the file's own pixels (no EXIF transpose, as eval-20261015 found).

  python scripts/overlay_columns.py --response <saved.json> --view straight --photo <file> --out <dir> --name <case> [--strips 2 4]
Writes <name>.jpg (whole face, boxes numbered top to bottom per column), <name>-c<k>.jpg for each column named in
--strips (the column strip at twice the size), <name>.json, and prints, per column, the box centres and the gaps in
layer pitches.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "backend"))

from app.vision.layer_span import _columns, count_layers_by_span  # noqa: E402

COLOURS = ["#e6194b", "#3cb44b", "#4363d8", "#f58231", "#911eb4", "#42d4f4", "#f032e6", "#bfef45", "#9a6324", "#000075"]


def load_view(path: Path, view: str):
    saved = json.loads(path.read_text(encoding="utf-8"))
    views = saved.get("views") or saved["response"]["views"]
    return saved, views[view]


def prepared_image(saved: dict, view: str, photo: Path) -> Image.Image:
    image = Image.open(photo)
    sent = (saved.get("_sent") or {}).get(view)
    if sent:
        image = ImageOps.exif_transpose(image)
        if list(image.size) != list(sent["sent"]):
            image = image.resize(tuple(sent["sent"]), Image.Resampling.LANCZOS)
    return image.convert("RGB")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--response", required=True)
    ap.add_argument("--view", required=True)
    ap.add_argument("--photo", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--strips", type=int, nargs="*", default=[], help="columns to save as zoomed strips")
    args = ap.parse_args(argv)
    saved, view = load_view(Path(args.response), args.view)
    detections = view["detections"]
    image = prepared_image(saved, args.view, Path(args.photo))
    columns = _columns(detections)
    counts = count_layers_by_span(detections)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    draw = ImageDraw.Draw(image)
    lw = max(2, image.width // 600)
    in_columns = {id(d) for column in columns for d in column}
    for d in detections:  # boxes in groups of fewer than 3: never counted
        if id(d) not in in_columns:
            x0, y0 = d["x"] - d["width"] / 2, d["y"] - d["height"] / 2
            draw.rectangle([x0, y0, x0 + d["width"], y0 + d["height"]], outline="#808080", width=lw)
    report = {"name": args.name, "response": args.response, "view": args.view, "image": list(image.size), "columns": []}
    for k, (column, count) in enumerate(zip(columns, counts), 1):
        colour = COLOURS[(k - 1) % len(COLOURS)]
        ordered = sorted(column, key=lambda d: d["y"])
        pitch = count["pitch_px"]
        for i, d in enumerate(ordered, 1):
            x0, y0 = d["x"] - d["width"] / 2, d["y"] - d["height"] / 2
            draw.rectangle([x0, y0, x0 + d["width"], y0 + d["height"]], outline=colour, width=lw)
            draw.text((x0 + 3, y0 + 1), str(i), fill=colour)
        top = min(d["y"] for d in column)
        draw.text((count["x_min"], max(0, top - 3 * pitch)), f"c{k} w{count['walk_count']} s{count['span_count']}", fill=colour)
        ys = [round(d["y"], 1) for d in ordered]
        gaps = [round((b - a) / pitch, 2) for a, b in zip(ys, ys[1:])]
        report["columns"].append({"column": k, "boxes": len(column), "walk": count["walk_count"], "span": count["span_count"],
                                  "filled": count["walk_filled"], "pitch_px": pitch, "x": [count["x_min"], count["x_max"]],
                                  "y_first": ys[0], "y_last": ys[-1], "gaps_in_pitches": gaps,
                                  "confidence_min": round(min(d.get("confidence", 1) for d in column), 3)})
    image.save(out / f"{args.name}.jpg", quality=85)
    for c in (c for c in report["columns"] if c["column"] in args.strips):
        pad = 0.15 * (c["x"][1] - c["x"][0])
        top = max(0, c["y_first"] - 2 * c["pitch_px"])
        bottom = min(image.height, c["y_last"] + 2 * c["pitch_px"])
        strip = image.crop((max(0, c["x"][0] - pad), top, min(image.width, c["x"][1] + pad), bottom))
        strip.resize((strip.width * 2, strip.height * 2), Image.Resampling.LANCZOS).save(out / f"{args.name}-c{c['column']}.jpg", quality=85)
    (out / f"{args.name}.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    for c in report["columns"]:
        print(f"c{c['column']}: boxes {c['boxes']} walk {c['walk']} span {c['span']} filled {c['filled']} pitch {c['pitch_px']} "
              f"x {c['x']} y {c['y_first']}..{c['y_last']} gaps {c['gaps_in_pitches']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
