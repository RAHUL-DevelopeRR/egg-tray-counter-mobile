"""Replay preserved baseline responses into automatic stack and beam evidence."""

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

from app.vision.spatial_3d import analyze_view, propose_correspondence


def save(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False), encoding="utf-8")


def load(path):
    with Image.open(path) as source:
        return np.asarray(ImageOps.exif_transpose(source).convert("RGB"))[
            :, :, ::-1
        ].copy()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    cv2.setNumThreads(1)
    root = args.report
    records = json.loads((root / "manifest.json").read_text())["images"]
    raw = {}
    for path in sorted(
        list((root / "raw").glob("batch-??.json"))
        + list((root / "raw").glob("single-image-??.json"))
    ):
        request = json.loads(path.with_name(path.stem + "-request.json").read_text())
        response = json.loads(path.read_text())
        for view, image_id in request["transport_views"].items():
            raw.setdefault(image_id, (response["views"][view]["detections"], path.name))
    output = root / "analysis"
    output.mkdir(exist_ok=True)
    summary, measured = [], {}
    for record in records:
        image_id = record["id"]
        image = load(root / record["original"])
        h, w = image.shape[:2]
        detections = []
        raw_boxes, source = raw.get(image_id, ([], None))
        clipped = 0
        for d in raw_boxes:
            x1, y1 = d["x"] - d["width"] / 2, d["y"] - d["height"] / 2
            x2, y2 = d["x"] + d["width"] / 2, d["y"] + d["height"] / 2
            box = [max(0, x1), max(0, y1), min(w - 1, x2), min(h - 1, y2)]
            if box != [x1, y1, x2, y2]:
                clipped += 1
            if box[0] < box[2] and box[1] < box[3]:
                detections.append(
                    {"bbox": box, "confidence": d["confidence"], "class": d["class"]}
                )
        result = analyze_view(image, detections, image_id)
        result.update(
            image_sha256=record["sha256"],
            baseline_response=source,
            raw_rf_count=len(raw_boxes) if source else None,
            coordinate_frame="exif_transposed_pixels",
            boxes_clipped_to_frame=clipped,
            physical_ground_truth=None,
            eligible_egg_trays=None,
            baseline_status="completed"
            if source
            else "unavailable_gateway_resource_failure",
        )
        save(output / (image_id + ".json"), result)
        save(
            output / (image_id + "-detections.json"),
            {
                "image_sha256": record["sha256"],
                "coordinate_frame": "exif_transposed_pixels",
                "detections": detections,
            },
        )
        overlay = image.copy()
        thickness = max(2, round(w / 800))
        for d in detections:
            x1, y1, x2, y2 = map(round, d["bbox"])
            cv2.rectangle(overlay, (x1, y1), (x2, y2), (255, 130, 0), thickness)
        for stack in result["stacks"]:
            polygon = np.asarray(stack["polygon"], np.float32)
            cv2.polylines(
                overlay, [polygon.astype(np.int32)], True, (0, 0, 255), thickness * 2
            )
            beam = stack["beam"]
            if "geometry" in beam:
                width, height = beam["geometry"]["native_size"]
                matrix = cv2.getPerspectiveTransform(
                    np.float32(
                        [
                            [0, 0],
                            [width - 1, 0],
                            [width - 1, height - 1],
                            [0, height - 1],
                        ]
                    ),
                    polygon,
                )
                for y in beam["band_centers"]:
                    line = cv2.perspectiveTransform(
                        np.float32([[[0, y], [width - 1, y]]]), matrix
                    )[0].astype(int)
                    cv2.line(
                        overlay,
                        tuple(line[0]),
                        tuple(line[1]),
                        (0, 255, 255),
                        thickness,
                    )
            label = f"{stack['stack_id'].split(':')[-1]} RF={stack['rf_count']} band={beam.get('exploratory_band_count')}"
            cv2.putText(
                overlay,
                label,
                tuple(polygon[0].astype(int)),
                cv2.FONT_HERSHEY_SIMPLEX,
                max(0.5, w / 1700),
                (0, 0, 255),
                thickness,
            )
        scale = min(1, 1600 / max(overlay.shape[:2]))
        preview = cv2.resize(overlay, None, fx=scale, fy=scale)
        cv2.imwrite(str(output / (image_id + "-overlay.jpg")), preview)
        summary.append(
            {
                "image_id": image_id,
                "rf_count": result["raw_rf_count"],
                "quality_accepted": result["quality"]["accepted"],
                "proposed_stacks": len(result["stacks"]),
                "rf_per_stack": [s["rf_count"] for s in result["stacks"]],
                "band_counts": [
                    s["beam"].get("exploratory_band_count") for s in result["stacks"]
                ],
                "unlocalized_detections": result["unlocalized_detections"],
                "physical_trays": None,
                "eligible_egg_trays": None,
                "ground_truth": None,
            }
        )
        measured[image_id] = result
        print(image_id, summary[-1]["rf_count"], summary[-1]["band_counts"], flush=True)
    save(root / "per-image-results.json", summary)
    # Human tentative view assignment, not pose estimation or ground truth.
    mapping = {"straight": "image-07", "left": "image-10", "right": "image-11"}
    images = {
        v: load(root / next(r["original"] for r in records if r["id"] == ident))
        for v, ident in mapping.items()
    }
    views = {v: measured[ident] for v, ident in mapping.items()}
    matches = propose_correspondence(images, views)
    save(
        root / "cross-view-prototype.json",
        {
            "view_assignment": mapping,
            "assignment_status": "tentative_manual_oblique_views",
            "view_correspondence": matches,
            "accepted_correspondence": [],
            "x_columns": None,
            "y_rows": None,
            "physical_trays": None,
            "eligible_egg_trays": None,
            "scene_grid": [],
            "verified": False,
            "reason": "No calibrated pose/shared-base verification; repeated texture cannot establish hidden inventory",
        },
    )


if __name__ == "__main__":
    main()
