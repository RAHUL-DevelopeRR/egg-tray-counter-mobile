"""Evaluate a Roboflow detector as an exact tray counter."""

from __future__ import annotations

import argparse
import base64
import csv
import json
import os
import statistics
from pathlib import Path

import httpx


def summarize(rows: list[dict[str, object]]) -> dict[str, float | int]:
    errors = [int(row["absolute_error"]) for row in rows]
    relatives = [float(row["relative_error_pct"]) for row in rows]
    return {
        "images": len(rows),
        "exact_matches": sum(bool(row["exact_match"]) for row in rows),
        "exact_count_accuracy_pct": 100 * sum(bool(row["exact_match"]) for row in rows) / len(rows),
        "mae": statistics.mean(errors),
        "median_absolute_error": statistics.median(errors),
        "maximum_absolute_error": max(errors),
        "mean_relative_error_pct": statistics.mean(relatives),
        "mean_count_accuracy_pct": statistics.mean(float(row["count_accuracy_pct"]) for row in rows),
        "undercounts": sum(int(row["prediction"]) < int(row["truth"]) for row in rows),
        "overcounts": sum(int(row["prediction"]) > int(row["truth"]) for row in rows),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True)
    parser.add_argument("--manifest", type=Path, default=Path("accuracy-evaluation/manual-ground-truth.csv"))
    parser.add_argument("--images", type=Path, default=Path("accuracy-evaluation/test-images"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--confidence", type=int, default=35)
    parser.add_argument("--overlap", type=int, default=50)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()

    if args.self_check:
        sample = [{"truth": 10, "prediction": 8, "absolute_error": 2, "relative_error_pct": 20.0,
                   "count_accuracy_pct": 80.0, "exact_match": False}]
        assert summarize(sample)["mae"] == 2
        return 0

    key = os.environ.get("ROBOFLOW_API_KEY")
    if not key:
        raise SystemExit("ROBOFLOW_API_KEY is required")

    args.output.mkdir(parents=True, exist_ok=True)
    raw_dir = args.output / "raw-json"
    raw_dir.mkdir(exist_ok=True)
    with args.manifest.open(newline="", encoding="utf-8") as handle:
        manifest = list(csv.DictReader(handle))

    rows: list[dict[str, object]] = []
    with httpx.Client(timeout=120) as client:
        for item in manifest:
            image = args.images / f"{item['image']}{Path(item['source']).suffix.lower()}"
            response = client.post(
                f"https://serverless.roboflow.com/{args.model}",
                params={"api_key": key, "confidence": args.confidence, "overlap": args.overlap,
                        "classes": "egg_tray", "format": "json"},
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                content=base64.b64encode(image.read_bytes()),
            )
            if response.is_error:
                raise RuntimeError(f"Roboflow inference failed: HTTP {response.status_code}")
            payload = response.json()
            (raw_dir / f"{item['image']}.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
            prediction = sum(p.get("class") == "egg_tray" for p in payload.get("predictions", []))
            truth = int(item["ground_truth_trays"])
            error = abs(prediction - truth)
            rows.append({
                "image": item["image"], "truth": truth, "prediction": prediction,
                "absolute_error": error, "relative_error_pct": round(100 * error / truth, 2),
                "count_accuracy_pct": round(max(0, 100 * (1 - error / truth)), 2),
                "exact_match": prediction == truth, "confidence": args.confidence,
                "overlap": args.overlap, "model": args.model,
            })

    with (args.output / "count-results.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    (args.output / "summary.json").write_text(json.dumps(summarize(rows), indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summarize(rows), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
