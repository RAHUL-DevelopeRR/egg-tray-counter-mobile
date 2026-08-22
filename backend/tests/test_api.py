from __future__ import annotations

import uuid

import numpy as np
from fastapi.testclient import TestClient

from app.main import create_app
from app.providers.base import InferenceProvider, InferenceResult
from app.providers.mock import MockInferenceProvider
from tests.conftest import encoded_stack


def client(test_settings) -> TestClient:
    return TestClient(create_app(test_settings, MockInferenceProvider()))


def triplet() -> dict[str, tuple[str, bytes, str]]:
    return {
        "left": ("left.jpg", encoded_stack(18, 1), "image/jpeg"),
        "right": ("right.jpg", encoded_stack(18, 2), "image/jpeg"),
        "straight": ("straight.jpg", encoded_stack(18, 3), "image/jpeg"),
    }


class TrayBoxBaselineProvider(InferenceProvider):
    def __init__(self, counts: dict[str, int]) -> None:
        self.counts = counts

    async def infer(
        self,
        image_bytes: bytes,
        image: np.ndarray,
        metadata: dict[str, object],
    ) -> InferenceResult:
        view = str(metadata["view"])
        return InferenceResult(
            predictions=(),
            provider="roboflow_cloud",
            model_version="projec-mutta/2",
            latency_ms=1,
            detection_count=self.counts[view],
            output_class="egg_tray",
            average_detection_confidence=0.8,
        )


def test_health_ready_and_version(test_settings) -> None:
    with client(test_settings) as api:
        assert api.get("/health").json() == {"status": "ok"}
        assert api.get("/ready").status_code == 200
        assert api.get("/version").json()["version"] == "0.1.0"


def test_three_view_scan_is_verified_and_idempotent(test_settings) -> None:
    scan_id = str(uuid.uuid4())
    with client(test_settings) as api:
        first = api.post("/v1/scans/count", files=triplet(), data={"scan_id": scan_id})
        assert first.status_code == 200, first.text
        payload = first.json()
        assert payload["status"] == "verified"
        assert payload["accepted"] is True
        assert payload["total_trays"] == 18
        assert payload["total_eggs"] == 540
        assert payload["processing"]["model_version"] == "mock/full-face-v1"
        second = api.post("/v1/scans/count", files=triplet(), data={"scan_id": scan_id})
        assert second.json() == payload


def test_single_stack_tray_box_baseline_accepts_two_agreeing_views(test_settings) -> None:
    provider = TrayBoxBaselineProvider({"left": 18, "right": 18, "straight": 17})
    with TestClient(create_app(test_settings, provider)) as api:
        response = api.post("/v1/scans/count", files=triplet())
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "verified"
    assert payload["total_trays"] == 18
    assert payload["processing"]["mode"] == "roboflow_cloud_egg_tray_baseline"


def test_single_stack_tray_box_baseline_rejects_disagreement(test_settings) -> None:
    provider = TrayBoxBaselineProvider({"left": 18, "right": 17, "straight": 19})
    with TestClient(create_app(test_settings, provider)) as api:
        response = api.post("/v1/scans/count", files=triplet())
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "rescan_required"
    assert payload["total_trays"] is None


def test_invalid_mime_type(test_settings) -> None:
    files = triplet()
    files["straight"] = ("straight.txt", b"not-an-image", "text/plain")
    with client(test_settings) as api:
        response = api.post("/v1/scans/count", files=files)
    assert response.status_code == 415
    assert response.json()["detail"]["code"] == "invalid_mime_type"


def test_missing_view(test_settings) -> None:
    files = triplet()
    del files["left"]
    with client(test_settings) as api:
        response = api.post("/v1/scans/count", files=files)
    assert response.status_code == 422


def test_duplicate_view(test_settings) -> None:
    image = encoded_stack(18, 1)
    files = {view: (f"{view}.jpg", image, "image/jpeg") for view in ("left", "right", "straight")}
    with client(test_settings) as api:
        response = api.post("/v1/scans/count", files=files)
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "duplicate_view"


def test_oversized_image(test_settings) -> None:
    constrained = test_settings.__class__(**{**test_settings.__dict__, "max_upload_bytes": 100})
    with client(constrained) as api:
        response = api.post("/v1/scans/count", files=triplet())
    assert response.status_code == 413
