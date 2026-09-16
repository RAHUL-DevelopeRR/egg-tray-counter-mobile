"""Synthetic accounting/abstention checks, not real-camera accuracy claims."""

import pytest

from app.vision.spatial_3d import assemble_grid, candidate_scene, fuse_stack


def observations():
    return [
        {
            "id": f"front-{x}-{y}",
            "x": x,
            "y": y,
            "geometry_evidence": "synthetic calibrated pose fixture",
            "layers": ["filled"] * 20,
        }
        for y in range(2)
        for x in range(5)
    ]


def grid(items, **kwargs):
    return assemble_grid(items, x_columns=5, y_rows=2, complete_coverage=True, **kwargs)


def test_rectangle_and_shared_anchor():
    items = observations()
    assert grid(items)["eligible_egg_trays"] == 200
    items.append({**items[4], "id": "right-shared-5"})
    items.append({**items[4], "id": "duplicate-side-5"})
    assert grid(items)["eligible_egg_trays"] == 200
    assert len(grid(items)["scene_grid"]) == 10


def test_missing_and_unequal_rear():
    items = observations()
    items.pop()
    assert grid(items, absent_cells=((4, 1),))["eligible_egg_trays"] == 180
    assert grid(items)["eligible_egg_trays"] is None
    assert grid(items)["rescan"]
    items = observations()
    items[-1]["layers"] = ["filled"] * 13
    assert grid(items)["eligible_egg_trays"] == 193


def test_unknown_and_empty():
    items = observations()
    items[0]["layers"].append("empty")
    result = grid(items)
    assert result["physical_trays"] == 201
    assert result["eligible_egg_trays"] == 200
    assert result["empty_trays"] == 1
    items[0]["layers"][0] = "unknown"
    result = grid(items)
    assert result["eligible_egg_trays"] is None
    assert result["observed_filled_layers"] == 199
    assert result["unknown_trays"] == 1


@pytest.mark.parametrize("count", [10, 20, 40])
def test_harmonics_never_certify(count):
    result = fuse_stack(19, {"exploratory_band_count": count}, {"height_count": 20})
    assert result["candidate_z"] == 20
    assert result["physical_layer_count"] is None
    assert result["status"] == "unresolved"


def test_conflicting_anchor_and_bad_geometry():
    items = observations()
    items.append({**items[4], "id": "side", "layers": ["filled"] * 19})
    assert grid(items)["physical_trays"] is None
    items[0]["geometry_evidence"] = ""
    with pytest.raises(ValueError):
        grid(items)


def test_out_of_sop():
    import numpy as np

    images = {v: np.full((480, 480, 3), 128, np.uint8) for v in ("left", "right", "straight")}
    result = candidate_scene(images, {v: [] for v in images}, {"orthogonal_layout": False})
    assert result["status"] == "OUT_OF_OPERATING_ENVELOPE"
    assert result["eligible_egg_trays"] is None
    assert not result["verified"]


def test_image_stack_beam_integration():
    from conftest import synthetic_stack

    from app.vision.spatial_3d import analyze_view

    image = synthetic_stack(18)
    detections = [{"bbox": [10, y - 5, 460, y + 5], "confidence": 0.9} for y in range(40, 681, 38)]
    result = analyze_view(image, detections, "straight")
    assert len(result["stacks"]) == 1
    beam = result["stacks"][0]["beam"]
    assert beam["band_centers"]
    assert beam["selected_count"] is None
    assert beam["hypotheses"]


def test_candidate_route_hashes_and_no_false_certification():
    import hashlib
    import json

    from conftest import encoded_stack
    from fastapi.testclient import TestClient

    from app.main import create_app

    files = {
        v: (v + ".jpg", encoded_stack(variant=i), "image/jpeg")
        for i, v in enumerate(("left", "right", "straight"))
    }
    evidence = {
        "views": {
            v: {
                "image_sha256": hashlib.sha256(f[1]).hexdigest(),
                "coordinate_frame": "exif_transposed_pixels",
                "detections": [],
            }
            for v, f in files.items()
        }
    }
    client = TestClient(create_app())
    response = client.post("/candidate/count-3d", files=files, data={"evidence": json.dumps(evidence)})
    assert response.status_code == 200
    assert response.json()["verified"] is False
    evidence["views"]["left"]["image_sha256"] = "wrong"
    assert (
        client.post("/candidate/count-3d", files=files, data={"evidence": json.dumps(evidence)}).status_code
        == 422
    )
