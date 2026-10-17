"""Local candidate runner: image + geometry/detections only, never truth.

Example: python scripts/measure_stack_candidates.py --image scene.jpg
  --faces assisted-faces.json --output reports/candidate-run
Alternatively --detections accepts original-coordinate bbox/confidence records.
No production route or mobile build is changed.
"""

import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np

from app.config import Settings
from app.vision.layer_signal import count_layers
from app.vision.stack_measurement import analyze_rims, localize_stacks, rectify_native


def save_image(path, image):
    if not cv2.imwrite(str(path), image):
        raise OSError(f"Cannot write {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--faces", type=Path)
    inputs.add_argument("--detections", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Use a new output directory to preserve previous measurements")
    content = args.image.read_bytes()
    image = cv2.imdecode(np.frombuffer(content, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Cannot decode source image")
    cv2.setNumThreads(1)
    if args.faces:
        geometry = json.loads(args.faces.read_text(encoding="utf-8"))
        if set(geometry) != {"image_sha256", "method", "faces"}:
            raise ValueError(
                "Geometry-only file required; do not supply annotations/truth"
            )
        if geometry["image_sha256"] != hashlib.sha256(content).hexdigest():
            raise ValueError("Geometry image hash mismatch")
        faces = geometry["faces"]
        if any(set(f) != {"stack_id", "polygon"} for f in faces):
            raise ValueError("Faces may contain only stack_id and polygon")
        mode = "assisted_manual_faces"
    else:
        raw = json.loads(args.detections.read_text(encoding="utf-8"))
        if raw["image_sha256"] != hashlib.sha256(content).hexdigest():
            raise ValueError("Detection image hash mismatch")
        faces = localize_stacks(raw["detections"], image.shape)
        mode = "automatic_from_supplied_detections"
    args.output.mkdir(parents=True)
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    overlay = image.copy()
    reports = []
    for index, face in enumerate(faces, 1):
        rectified, geometry_info = rectify_native(image, face["polygon"])
        crop = rectified.image
        rf_centres = ()
        if face.get("visible_detections"):
            points = np.array(
                [
                    [
                        (d["bbox"][0] + d["bbox"][2]) / 2,
                        (d["bbox"][1] + d["bbox"][3]) / 2,
                    ]
                    for d in face["visible_detections"]
                ],
                np.float32,
            )
            transformed = cv2.perspectiveTransform(points[None], rectified.homography)[
                0
            ]
            rf_centres = tuple(
                float(p[1]) for p in transformed if 0 <= p[1] < crop.shape[0]
            )
        result = analyze_rims(crop, rf_centres=rf_centres)
        best = result["best"]
        # Legacy output at the original 512x768 diagnostic resolution for comparison.
        from app.vision.rectification import rectify_face

        legacy_crop = rectify_face(image, face["polygon"], (512, 768)).image
        legacy = count_layers(legacy_crop, Settings())
        result["legacy"] = {
            "count": legacy.tray_count,
            "pitch_px": legacy.pitch_px,
            "rectified_size": [512, 768],
            "quality": legacy.quality,
        }
        result["geometry"] = geometry_info
        result["rf_count"] = face.get("rf_count")
        result["stack_id"] = face["stack_id"]
        result["polygon"] = face["polygon"]
        result["layer_states"] = [
            {"candidate_index": i + 1, "centre_y": y, "physical_state": "unknown"}
            for i, y in enumerate(best["centres"] if best else [])
        ]
        save_image(args.output / f"column-{index}-crop.png", crop)
        annotated = crop.copy()
        if best:
            for layer, (a, b) in enumerate(best["intervals"], 1):
                y = best["centres"][layer - 1]
                cv2.line(annotated, (0, y), (crop.shape[1] - 1, y), (0, 255, 255), 1)
                cv2.putText(
                    annotated,
                    str(layer),
                    (2, y - 2),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.3,
                    (0, 0, 255),
                    1,
                )
            inverse = np.linalg.inv(rectified.homography)
            for y in best["centres"]:
                ends = np.array([[[0, y], [crop.shape[1] - 1, y]]], np.float32)
                projected = (
                    cv2.perspectiveTransform(ends, inverse)[0].round().astype(int)
                )
                cv2.line(
                    overlay, tuple(projected[0]), tuple(projected[1]), (0, 255, 255), 1
                )
        cv2.polylines(
            overlay, [np.array(face["polygon"], np.int32)], True, (0, 0, 255), 2
        )
        save_image(args.output / f"column-{index}-bands.png", annotated)
        fig, axes = plt.subplots(4, 1, figsize=(11, 10), constrained_layout=True)
        axes[0].plot(result["profile"], label="brightness profile")
        if best:
            for y in best["centres"]:
                axes[0].axvline(y, color="orange", alpha=0.4)
        axes[0].set_title(
            f"{face['stack_id']} - exploratory bands, not certified trays"
        )
        axes[1].plot(result["signed_sobel"], label="signed Sobel Y")
        axes[1].axhline(0, color="gray")
        axes[2].plot(result["autocorrelation"][:91], label="brightness AC")
        axes[2].plot(result["edge_autocorrelation"][:91], label="absolute-edge AC")
        for c in result["hypotheses"][:8]:
            axes[2].axvline(c["pitch_px"], alpha=0.25, color="red")
        top = result["hypotheses"][:10]
        axes[3].barh(
            [
                f"{i}: p={c['pitch_px']} {c['feature']} n={c['count']}"
                for i, c in enumerate(top)
            ],
            [c["support"] for c in top],
        )
        axes[3].set_xlabel(
            "Diagnostic support (not probability); alternatives retained"
        )
        for ax in axes[:3]:
            ax.legend()
        fig.savefig(args.output / f"column-{index}-signal.png", dpi=120)
        plt.close(fig)
        reports.append(result)
    save_image(args.output / "source-overlay.png", overlay)
    report = {
        "image_sha256": hashlib.sha256(content).hexdigest(),
        "mode": mode,
        "automatic_localization": not bool(args.faces),
        "stacks": reports,
        "physical_total": None,
        "eligible_total": None,
        "occupancy": "unknown",
        "calibration": None,
        "fresh_rf_inference": False,
    }
    (args.output / "measurements.json").write_text(json.dumps(report, indent=2) + "\n")
    print(
        json.dumps(
            {
                "mode": mode,
                "legacy": [r["legacy"]["count"] for r in reports],
                "candidate": [
                    r["best"]["count"] if r["best"] else None for r in reports
                ],
                "pitches": [
                    r["best"]["pitch_px"] if r["best"] else None for r in reports
                ],
                "physical_total": None,
                "eligible_total": None,
            }
        )
    )


if __name__ == "__main__":
    main()
