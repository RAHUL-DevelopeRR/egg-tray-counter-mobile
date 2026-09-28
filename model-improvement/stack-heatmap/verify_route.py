"""Exercise authenticated real-checkpoint route; no upstream inference calls."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
from fastapi.testclient import TestClient
from app.vision_service import create_vision_app


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("checkpoint", type=Path); args = parser.parse_args()
    os.environ["STACK_HEATMAP_CHECKPOINT"] = str(args.checkpoint)
    app = create_vision_app("local-test-authorization-token-00000")
    client = TestClient(app)
    path = ROOT / "reports/two-view-20260924/input-1.jpg"
    content = path.read_bytes()
    faces = json.loads((ROOT / "reports/stack-heatmap-20260928/dataset/faces.json").read_text())
    evidence = {"image_sha256": hashlib.sha256(content).hexdigest(), "source_view": "straight",
                "coordinate_frame": "exif_transposed_pixels",
                "stacks": [{"stack_id": "diagnostic_1", "polygon": faces[0]["quad"]}]}
    files = {"image": ("input.jpg", content, "image/jpeg")}
    assert client.post("/candidate/stack-heatmap", files=files, data={"evidence": json.dumps(evidence)}).status_code == 401
    headers = {"Authorization": "Bearer local-test-authorization-token-00000"}
    response = client.post("/candidate/stack-heatmap", headers=headers, files=files, data={"evidence": json.dumps(evidence)})
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["verified"] is False and result["inventory_total"] is None
    stack = result["stacks"][0]
    assert stack["selected_physical_z"] is None and stack["band_candidates"]
    assert stack["occupancy"] == "unknown" and stack["rectification"]["homography"]
    evidence["image_sha256"] = "0" * 64
    assert client.post("/candidate/stack-heatmap", headers=headers, files=files, data={"evidence": json.dumps(evidence)}).status_code == 422
    print("Authenticated warmed-checkpoint route, hash mismatch, homography, bands and uncertified output passed")


if __name__ == "__main__": main()
