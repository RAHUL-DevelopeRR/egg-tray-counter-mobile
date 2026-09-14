"""Reproduce a count comparison without altering the frozen benchmark.

Reference counts are used only for scoring after image processing. The face
polygons are manually localized, so this is not an automatic end-to-end test.
Roboflow data is an explicitly labelled historical replay, not fresh inference.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import replace
from pathlib import Path

import cv2
import numpy as np

from app.config import Settings
from app.vision.layer_signal import count_layers
from app.vision.rectification import rectify_face

ROOT = Path(__file__).resolve().parents[1]
IMAGE = ROOT / "accuracy-evaluation/test-images/img04.jpg"
RAW = ROOT / "accuracy-evaluation/raw-json/img04-direct-c35-o50.json"
OUTPUT = ROOT / "reports/manual-reference-20260913"


def metrics(predicted: int | None, truth: int) -> dict:
    if predicted is None:
        return {"predicted_trays": None, "absolute_error": None, "relative_error_pct": None,
                "exact_match": None, "count_closeness_pct": None}
    error = abs(predicted - truth)
    return {"predicted_trays": predicted, "signed_error": predicted - truth,
            "absolute_error": error, "relative_error_pct": error / truth * 100,
            "exact_match": predicted == truth,
            "count_closeness_pct": max(0, 1 - error / truth) * 100}


def main() -> None:
    content = IMAGE.read_bytes()
    image = cv2.imdecode(np.frombuffer(content, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Reference image could not be decoded")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Manually selected face boundaries, not floor calibration or tray annotations.
    polygons = (
        ((82, 166), (390, 157), (345, 522), (200, 547)),
        ((398, 156), (638, 151), (509, 488), (345, 522)),
    )
    settings = Settings()
    raw = json.loads(RAW.read_text(encoding="utf-8"))
    predictions = [p for p in raw["predictions"] if p.get("class") == "egg_tray"]
    layer_results = []
    guided_results = []
    for index, polygon in enumerate(polygons):
        face = rectify_face(image, polygon, (settings.rectified_width, settings.rectified_height))
        result = count_layers(face.image, settings)
        cv2.imwrite(str(OUTPUT / f"face-{index + 1}.jpg"), face.image)
        layer_results.append({"face": index + 1, "polygon": polygon,
                              "candidate_trays": result.tray_count,
                              "detected_layers": result.detected_layers,
                              "inferred_layers": result.inferred_internal_layers,
                              "pitch_px": result.pitch_px,
                              "quality": result.quality, "reason": result.reason})
        # Exploratory RF + image hybrid: model positions constrain image pitch.
        # No ground-truth count is used. Manual faces make this an assisted test.
        contour = np.asarray(polygon, dtype=np.float32)
        centers = [(p["x"], p["y"]) for p in predictions
                   if cv2.pointPolygonTest(contour, (p["x"], p["y"]), False) >= 0]
        guided_count = None
        anchor_pitch = None
        if len(centers) >= 4:
            projected = cv2.perspectiveTransform(
                np.asarray([centers], dtype=np.float32), face.homography
            )[0]
            gaps = np.diff(np.sort(projected[:, 1]))
            gaps = gaps[gaps >= settings.min_pitch_px]
            if len(gaps) >= 3:
                anchor_pitch = float(np.median(gaps))
                # Fixed development interval around model-derived spacing.
                low = max(2, round(anchor_pitch * 0.75))
                high = max(low + 1, round(anchor_pitch * 1.25))
                guided = count_layers(face.image, replace(settings, min_pitch_px=low, max_pitch_px=high))
                guided_count = guided.tray_count
        guided_results.append({"face": index + 1, "model_anchors": len(centers),
                               "anchor_pitch_px": anchor_pitch, "candidate_trays": guided_count})
    # Scoring happens only after the fixed existing layer algorithm runs.
    truth = 32
    reference = {"image": str(IMAGE.relative_to(ROOT)), "sha256": hashlib.sha256(content).hexdigest(),
                 "visible_trays": truth, "per_column_visible_trays": [16, 16],
                 "method": "assistant visual recount of existing benchmark photo",
                 "blind": False, "physically_recounted": False,
                 "hidden_inventory_verified": False,
                 "note": "Reference is visible trays; full egg occupancy and out-of-frame stock are not certified."}
    layer_counts = [r["candidate_trays"] for r in layer_results]
    layer_total = sum(layer_counts) if all(n is not None for n in layer_counts) else None
    guided_counts = [r["candidate_trays"] for r in guided_results]
    guided_total = sum(guided_counts) if all(n is not None for n in guided_counts) else None
    report = {
        "reference": reference,
        "model": "projec-mutta/2",
        "rf_only": {"source": "historical saved predictions replay", **metrics(len(predictions), truth)},
        "layer_only": {"source": "fresh local run, manually localized faces; not automatic localization",
                       **metrics(layer_total, truth), "faces": layer_results},
        "calibrated_height": {"status": "unavailable", "reason": "No measured height/camera profile"},
        "hybrid": {"status": "not_evaluated", **metrics(None, truth),
                   "reason": "No operational image-to-hybrid adapter, measured height or occupancy evidence"},
        "assisted_hybrid_candidate": {
            "source": "Exploratory saved RF positions + fresh image layers; manually localized faces",
            "accepted_inventory": False, **metrics(guided_total, truth), "faces": guided_results,
            "note": "Development experiment on a seen image. No measured height, occupancy or multiview matching."},
        "detection_precision": None,
        "detection_recall": None,
        "precision_reason": "Requires independently labelled tray instances and one-to-one IoU matching",
        "limitations": "One previously seen photo is not a held-out three-view benchmark. Count closeness is not detection precision or a general accuracy claim.",
    }
    (OUTPUT / "reference.json").write_text(json.dumps(reference, indent=2) + "\n", encoding="utf-8")
    (OUTPUT / "comparison.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"rf": report["rf_only"], "layers": report["layer_only"],
                      "assisted_hybrid": report["assisted_hybrid_candidate"],
                      "hybrid": report["hybrid"], "output": str(OUTPUT)}, indent=2))


if __name__ == "__main__":
    main()
