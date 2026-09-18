"""Run assigned views through unchanged live RF and the local spatial candidate.

No manual reference, expected total, or physical truth is read by inference.
"""

import hashlib
import io
import json
import ssl
import time
import uuid
from pathlib import Path

import cv2
import httpx
from fastapi.testclient import TestClient
from PIL import Image, ImageOps

from app.main import create_app

ROOT = Path("reports/production-20260918")
GATEWAY = "https://egg-tray-counter-api.rahultech72216.workers.dev"


def save(name, value):
    (ROOT / name).write_text(
        json.dumps(value, indent=None if name == "backend_result.json" else 2, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def main():
    cv2.setNumThreads(1)
    records = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8-sig"))[
        "images"
    ]
    files, evidence, dimensions = {}, {"views": {}}, {}
    for r in records:
        content = (ROOT / r["file"]).read_bytes()
        assert hashlib.sha256(content).hexdigest() == r["sha256"]
        files[r["view"]] = (r["view"] + ".jpg", content, "image/jpeg")
        with Image.open(io.BytesIO(content)) as image:
            oriented = ImageOps.exif_transpose(image)
            dimensions[r["view"]] = oriented.size
        evidence["views"][r["view"]] = {
            "image_sha256": r["sha256"],
            "coordinate_frame": "exif_transposed_pixels",
            "detections": [],
        }
    raw_path = ROOT / "gateway_result.json"
    if not raw_path.exists():
        scan_id = str(uuid.uuid4())
        save(
            "gateway_request.json",
            {
                "scan_id": scan_id,
                "scan_contract": "model_spatial_v1",
                "view_assignment": {r["view"]: r["file"] for r in records},
                "input_bytes": sum(r["bytes"] for r in records),
                "purpose": "user-requested assigned-view demonstration; stable scene not asserted",
            },
        )
        started = time.monotonic()
        with httpx.Client(verify=ssl.create_default_context(), timeout=240) as client:
            response = client.post(
                GATEWAY + "/v1/scans/count",
                files=files,
                data={"scan_id": scan_id, "scan_contract": "model_spatial_v1"},
            )
        if response.status_code != 200:
            save("gateway_error.json", {"status_code": response.status_code})
            raise RuntimeError(
                "Gateway request failed; HTTP status saved without response body"
            )
        raw = response.json()
        assert raw["model"]["model_id"] == "projec-mutta/2"
        save("gateway_result.json", raw)
        save("timing.json", {"gateway_seconds": time.monotonic() - started})
    raw = json.loads(raw_path.read_text())
    for view in files:
        w, h = dimensions[view]
        for d in raw["views"][view]["detections"]:
            bbox = [
                max(0, d["x"] - d["width"] / 2),
                max(0, d["y"] - d["height"] / 2),
                min(w - 1, d["x"] + d["width"] / 2),
                min(h - 1, d["y"] + d["height"] / 2),
            ]
            if bbox[0] < bbox[2] and bbox[1] < bbox[3]:
                evidence["views"][view]["detections"].append(
                    {"bbox": bbox, "confidence": d["confidence"], "class": d["class"]}
                )
    save("candidate_request.json", evidence)
    started = time.monotonic()
    with TestClient(create_app()) as client:
        response = client.post(
            "/candidate/count-3d", files=files, data={"evidence": json.dumps(evidence)}
        )
        assert response.status_code == 200, response.text
        result = response.json()
    save("backend_result.json", result)
    summary = {
        "status": result["status"],
        "verified": result["verified"],
        "geometry": result["geometry"],
        "eligible_egg_trays": result["eligible_egg_trays"],
        "local_analysis_seconds": time.monotonic() - started,
        "view_correspondence": result["view_correspondence"],
        "views": {
            v: {
                "rf_count": data["rf_count"],
                "proposed_faces": len(data["stacks"]),
                "beam_candidates": [
                    s["beam"].get("exploratory_band_count") for s in data["stacks"]
                ],
                "per_stack_rf": [s["rf_count"] for s in data["stacks"]],
            }
            for v, data in result["views"].items()
        },
    }
    save("demo-summary.json", summary)
    assert result["verified"] is False and result["eligible_egg_trays"] is None
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
