from __future__ import annotations

import base64
import csv
import json
import os
import shutil
import time
import uuid
from pathlib import Path

import httpx
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUT = Path(__file__).resolve().parent
WORKER = "https://egg-tray-counter-api.rahultech72216.workers.dev"
MODEL = "projec-mutta/2"
EGGS_PER_TRAY = 30

SAMPLES = [
    ("img01", "datasets/roboflow_auto_original/test/images/WhatsApp-Image-2026-07-03-at-11-57-19-AM_jpeg.rf.feb2d66882a2a76010cf40c7331b9e23.jpg", 60, "same 60-tray scene, left/side view; three 20-tray stacks"),
    ("img02", "datasets/roboflow_auto_original/test/images/WhatsApp-Image-2026-07-03-at-11-57-20-AM_jpeg.rf.69f0522ac347a7b905f4b480e10e9c9d.jpg", 60, "same 60-tray scene, right/close view; three 20-tray stacks"),
    ("img03", "datasets/roboflow_auto_original/valid/images/WhatsApp-Image-2026-07-03-at-11-57-20-AM-2-_jpeg.rf.7048c50fa506961efb6e18caa5d15b3a.jpg", 60, "same 60-tray scene, straight view; three 20-tray stacks"),
    ("img04", "datasets/roboflow_auto_original/test/images/WhatsApp-Image-2026-07-03-at-11-57-17-AM_jpeg.rf.307d9fb9212e290d06232d7e7230224b.jpg", 32, "two brown stacks, 16 trays each"),
    ("img05", "datasets/canonical_clean/test/images/43409f4aee1d3653f129.jpeg", 120, "large straight green stack wall, six 20-tray stacks"),
    ("img06", "datasets/canonical_clean/test/images/a1843591fc331694b11f.jpeg", 21, "medium angled two-stack scene, 10+11 visible trays"),
    ("img07", "datasets/canonical_clean/test/images/bb2b695f926199caecaa.jpeg", 21, "medium straight dense scene, 21 visible tray layers"),
    ("img08", "datasets/roboflow_auto_original/test/images/WhatsApp-Image-2026-07-03-at-11-56-57-AM_jpeg.rf.89f4bc4ee2c7c1dd04d5a124ecec90b9.jpg", 46, "large warehouse stack, elevated angle"),
    ("img09", "datasets/roboflow_auto_original/test/images/WhatsApp-Image-2026-07-03-at-12-01-00-PM_jpeg.rf.f385e1d876734229d2317d18efa35d5c.jpg", 76, "large warehouse stack, straight/angled"),
    ("img10", "datasets/roboflow_auto_original/test/images/WhatsApp-Video-2026-07-03-at-12_04_04-PM_mp4-0002_jpg.rf.b2f6230e26cd45d499ba1295b93aaa4f.jpg", 1, "single tray, top-down video frame"),
]

FILLERS = [
    ROOT / "datasets/canonical_clean/test/images/35c45766a260ff49cc4a.jpg",
    ROOT / "datasets/canonical_clean/test/images/4ca5161426ab6a8dfa4a.jpg",
]


def request_with_retry(client: httpx.Client, method: str, url: str, **kwargs) -> httpx.Response:
    for attempt in range(3):
        response = client.request(method, url, **kwargs)
        if response.status_code not in {429, 502, 503, 504}:
            response.raise_for_status()
            return response
        if attempt < 2:
            time.sleep(0.5 * 2**attempt)
    response.raise_for_status()
    raise AssertionError("unreachable")


def direct_infer(client: httpx.Client, image: Path, confidence: int, overlap: int) -> dict:
    key = os.environ.get("ROBOFLOW_API_KEY")
    if not key:
        raise RuntimeError("ROBOFLOW_API_KEY is required")
    response = request_with_retry(
        client,
        "POST",
        f"https://serverless.roboflow.com/{MODEL}",
        params={
            "api_key": key,
            "confidence": confidence,
            "overlap": overlap,
            "classes": "egg_tray",
            "format": "json",
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        content=base64.b64encode(image.read_bytes()),
    )
    return response.json()


def worker_infer(client: httpx.Client, paths: list[Path]) -> dict:
    files = {
        view: (path.name, path.read_bytes(), "image/jpeg")
        for view, path in zip(("left", "right", "straight"), paths, strict=True)
    }
    response = request_with_retry(
        client,
        "POST",
        f"{WORKER}/v1/scans/count",
        data={"scan_id": str(uuid.uuid4())},
        files=files,
    )
    return response.json()


def draw_predictions(image_path: Path, payload: dict, output_path: Path) -> None:
    with Image.open(image_path).convert("RGB") as image:
        draw = ImageDraw.Draw(image)
        for prediction in payload.get("predictions", []):
            if prediction.get("class") != "egg_tray":
                continue
            x = float(prediction["x"])
            y = float(prediction["y"])
            width = float(prediction["width"])
            height = float(prediction["height"])
            box = (x - width / 2, y - height / 2, x + width / 2, y + height / 2)
            draw.rectangle(box, outline=(255, 40, 40), width=3)
            draw.text((box[0] + 2, box[1] + 2), f"{prediction.get('confidence', 0):.2f}", fill=(255, 255, 0))
        image.save(output_path, quality=92)


def main() -> None:
    test_images = OUT / "test-images"
    raw_json = OUT / "raw-json"
    detections = OUT / "detections"
    for directory in (test_images, raw_json, detections):
        directory.mkdir(parents=True, exist_ok=True)

    records = []
    copied = {}
    for sample_id, relative, ground_truth, scene in SAMPLES:
        source = ROOT / relative
        destination = test_images / f"{sample_id}{source.suffix.lower()}"
        shutil.copy2(source, destination)
        copied[sample_id] = destination
        records.append({
            "image": sample_id,
            "source": relative,
            "ground_truth_trays": ground_truth,
            "ground_truth_eggs": ground_truth * EGGS_PER_TRAY,
            "ground_truth_status": "manual_visual_count",
            "scene": scene,
        })

    with httpx.Client(timeout=90) as client:
        for record in records:
            payload = direct_infer(client, copied[record["image"]], 35, 50)
            (raw_json / f"{record['image']}-direct-c35-o50.json").write_text(
                json.dumps(payload, indent=2), encoding="utf-8"
            )
            predictions = [p for p in payload.get("predictions", []) if p.get("class") == "egg_tray"]
            record["roboflow_raw"] = len(predictions)
            record["confidences"] = [round(float(p.get("confidence", 0)), 6) for p in predictions]
            draw_predictions(copied[record["image"]], payload, detections / f"{record['image']}.jpg")

        groups = [
            ["img01", "img02", "img03"],
            ["img04", "img05", "img06"],
            ["img07", "img08", "img09"],
        ]
        by_id = {record["image"]: record for record in records}
        for index, group in enumerate(groups, 1):
            payload = worker_infer(client, [copied[item] for item in group])
            (raw_json / f"worker-group-{index:02d}.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
            counts = payload["stacks"][0]["counts"]
            for view, sample_id in zip(("left", "right", "straight"), group, strict=True):
                by_id[sample_id]["backend_view_count"] = counts[view]
                by_id[sample_id]["app_scan_accepted"] = payload["accepted"]
                by_id[sample_id]["app_final_count"] = payload["total_trays"] if index == 1 else None

            if index == 1:
                (OUT / "multi-view-result.json").write_text(
                    json.dumps({"ground_truth": 60, "views": counts, "response": payload}, indent=2),
                    encoding="utf-8",
                )

        final_paths = [copied["img10"], *FILLERS]
        payload = worker_infer(client, final_paths)
        (raw_json / "worker-group-04.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
        by_id["img10"]["backend_view_count"] = payload["stacks"][0]["counts"]["left"]
        by_id["img10"]["app_scan_accepted"] = payload["accepted"]
        by_id["img10"]["app_final_count"] = None

        threshold_rows = []
        for sample_id in ("img04", "img05", "img08"):
            for confidence in (10, 20, 30, 35, 40, 50):
                payload = direct_infer(client, copied[sample_id], confidence, 50)
                predictions = [p for p in payload.get("predictions", []) if p.get("class") == "egg_tray"]
                threshold_rows.append({
                    "image": sample_id,
                    "confidence": confidence,
                    "overlap": 50,
                    "count": len(predictions),
                    "ground_truth": by_id[sample_id]["ground_truth_trays"],
                })
        for overlap in (20, 35, 50, 70, 90):
            payload = direct_infer(client, copied["img05"], 35, overlap)
            predictions = [p for p in payload.get("predictions", []) if p.get("class") == "egg_tray"]
            threshold_rows.append({
                "image": "img05",
                "confidence": 35,
                "overlap": overlap,
                "count": len(predictions),
                "ground_truth": by_id["img05"]["ground_truth_trays"],
            })

    for record in records:
        predicted = int(record["backend_view_count"])
        actual = int(record["ground_truth_trays"])
        error = abs(predicted - actual)
        record["absolute_error"] = error
        record["relative_error_pct"] = round(100 * error / actual, 2)
        record["count_accuracy_pct"] = round(max(0, 100 * (1 - error / actual)), 2)
        record["exact_match"] = predicted == actual
        record["predicted_eggs"] = predicted * EGGS_PER_TRAY

    with (OUT / "manual-ground-truth.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["image", "source", "ground_truth_trays", "ground_truth_eggs", "ground_truth_status", "scene"])
        writer.writeheader()
        writer.writerows({key: record[key] for key in writer.fieldnames} for record in records)

    result_fields = [
        "image", "ground_truth_trays", "roboflow_raw", "backend_view_count", "app_scan_accepted",
        "app_final_count", "absolute_error", "relative_error_pct", "count_accuracy_pct", "exact_match", "predicted_eggs",
    ]
    with (OUT / "results.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=result_fields)
        writer.writeheader()
        writer.writerows({key: record.get(key) for key in result_fields} for record in records)

    with (OUT / "threshold-experiment.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["image", "ground_truth", "confidence", "overlap", "count"])
        writer.writeheader()
        writer.writerows(threshold_rows)

    summary = {
        "model": MODEL,
        "worker": WORKER,
        "confidence": 35,
        "overlap": 50,
        "eggs_per_tray": EGGS_PER_TRAY,
        "records": records,
        "threshold_experiment": threshold_rows,
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
