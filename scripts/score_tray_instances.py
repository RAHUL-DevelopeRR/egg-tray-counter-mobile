"""Offline instance evaluation. Never imported by the image inference pipeline.

Usage: python scripts/score_tray_instances.py annotations.json predictions.json
Boxes are xyxy in original pixels. Polygons may be stored; bbox IoU is the
explicit matching metric (no silent claim of segmentation IoU).
"""

import argparse
import json
import math
from collections import Counter

import numpy as np
from scipy.optimize import linear_sum_assignment


def validate_instance(item: dict, *, truth: bool) -> None:
    if not isinstance(item.get("stack_id"), str) or not item["stack_id"].strip():
        raise ValueError("stack_id is required")
    if type(item.get("tray_index")) is not int or item["tray_index"] < 1:
        raise ValueError("tray_index must be a positive integer")
    if item.get("physical_state") not in {"filled", "empty", "unknown"}:
        raise ValueError("Invalid physical_state")
    if item.get("visibility") not in {"visible", "partial", "occluded", None}:
        raise ValueError("Invalid visibility")
    box = item.get("bbox")
    if box is not None and (
        len(box) != 4
        or not all(math.isfinite(v) for v in box)
        or not 0 <= box[0] < box[2]
        or not 0 <= box[1] < box[3]
    ):
        raise ValueError("bbox must be finite nonnegative xyxy with positive area")
    polygon = item.get("polygon")
    if polygon is not None and (
        len(polygon) < 3
        or any(
            len(p) != 2 or not all(math.isfinite(v) and v >= 0 for v in p)
            for p in polygon
        )
    ):
        raise ValueError("polygon must contain finite nonnegative xy points")
    if not truth and box is None:
        raise ValueError("Prediction bbox is required for bbox IoU matching")


def iou(a: list, b: list) -> float:
    intersection = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(
        0, min(a[3], b[3]) - max(a[1], b[1])
    )
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - intersection
    return intersection / union


def score(truth: dict, predictions: dict, threshold: float = 0.5) -> dict:
    if not 0 < threshold <= 1:
        raise ValueError("IoU threshold must be in (0,1]")
    if truth.get("image_sha256") != predictions.get("image_sha256") or not truth.get(
        "image_sha256"
    ):
        raise ValueError("Image hashes must match")
    labels, outputs = truth["instances"], predictions["instances"]
    for items, is_truth in ((labels, True), (outputs, False)):
        keys = []
        for item in items:
            validate_instance(item, truth=is_truth)
            keys.append((item["stack_id"], item["tray_index"]))
        if len(set(keys)) != len(keys):
            raise ValueError("Duplicate instance identity")
    errors = {}
    for stack in sorted({i["stack_id"] for i in labels + outputs}):
        expected = [i for i in labels if i["stack_id"] == stack]
        observed = [i for i in outputs if i["stack_id"] == stack]
        e, o = (
            Counter(i["physical_state"] for i in expected),
            Counter(i["physical_state"] for i in observed),
        )
        errors[stack] = {
            "physical_error": len(observed) - len(expected),
            "filled_error": o["filled"] - e["filled"]
            if not e["unknown"] + o["unknown"]
            else None,
            "empty_error": o["empty"] - e["empty"]
            if not e["unknown"] + o["unknown"]
            else None,
            "unknown_predictions": o["unknown"],
        }
    result = {
        "matching_metric": "bbox IoU",
        "iou_threshold": threshold,
        "per_stack": errors,
        "tp": None,
        "fp": None,
        "fn": None,
        "precision": None,
        "recall": None,
        "f1": None,
    }
    if not truth.get("annotation_complete") or any(
        i["visibility"] is None
        or (i["visibility"] != "occluded" and i.get("bbox") is None)
        for i in labels
    ):
        return {
            **result,
            "reason": "Instance geometry/visibility annotations are incomplete",
        }
    # Hidden inventory is reported above, excluded from visible-instance recall.
    visible = [i for i in labels if i["visibility"] != "occluded"]
    matrix = np.zeros((len(visible), len(outputs)))
    for row, label in enumerate(visible):
        for col, output in enumerate(outputs):
            if label["stack_id"] == output["stack_id"]:
                matrix[row, col] = iou(label["bbox"], output["bbox"])
    # Maximize valid-match cardinality first, IoU second; one-to-one, class agnostic.
    valid = matrix >= threshold
    rows, cols = linear_sum_assignment(
        -(valid * (min(matrix.shape, default=0) + 1) + matrix)
    )
    matches = [(int(a), int(b)) for a, b in zip(rows, cols, strict=True) if valid[a, b]]
    tp, fp, fn = len(matches), len(outputs) - len(matches), len(visible) - len(matches)
    precision = tp / (tp + fp) if tp + fp else None
    recall = tp / (tp + fn) if tp + fn else None
    confusion = Counter(
        (visible[a]["physical_state"], outputs[b]["physical_state"]) for a, b in matches
    )
    return {
        **result,
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "precision": precision,
        "recall": recall,
        "f1": 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else None,
        "matched_indices": matches,
        "unmatched_truth": [
            i
            for i in range(len(visible))
            if i not in rows.tolist() or not any(a == i for a, _ in matches)
        ],
        "unmatched_predictions": [
            i for i in range(len(outputs)) if not any(b == i for _, b in matches)
        ],
        "occupancy_confusion": {f"{a}->{b}": n for (a, b), n in confusion.items()},
        "excluded_occluded_truth": len(labels) - len(visible),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("truth")
    parser.add_argument("predictions")
    parser.add_argument("--iou", type=float, default=0.5)
    args = parser.parse_args()
    with open(args.truth, encoding="utf-8") as f:
        truth = json.load(f)
    with open(args.predictions, encoding="utf-8") as f:
        predictions = json.load(f)
    print(json.dumps(score(truth, predictions, args.iou), indent=2))
