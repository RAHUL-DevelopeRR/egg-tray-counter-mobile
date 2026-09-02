from __future__ import annotations

import httpx
import numpy as np
import pytest

from app.config import Settings
from app.errors import InferenceProviderError, UnsupportedModelOutputError
from app.logging_config import configure_logging
from app.providers.roboflow import RoboflowInferenceProvider


def settings() -> Settings:
    return Settings(
        inference_provider="roboflow",
        roboflow_api_key="test-secret",
        roboflow_model_id="egg-stack-face/7",
        roboflow_max_retries=0,
    )


def test_httpx_request_logging_cannot_expose_api_key() -> None:
    configure_logging("INFO")
    assert __import__("logging").getLogger("httpx").getEffectiveLevel() >= 30


@pytest.mark.asyncio
async def test_normalizes_segmentation_to_original_coordinates() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert "api_key=test-secret" in str(request.url)
        return httpx.Response(
            200,
            json={
                "image": {"width": 100, "height": 100},
                "predictions": [
                    {
                        "class": "stack_face",
                        "confidence": 0.92,
                        "points": [{"x": 10, "y": 20}, {"x": 90, "y": 20}, {"x": 90, "y": 80}],
                    }
                ],
            },
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = RoboflowInferenceProvider(settings(), client=client)
    result = await provider.infer(b"image", np.zeros((300, 200, 3), dtype=np.uint8), {})
    await client.aclose()
    prediction = result.predictions[0]
    assert prediction.polygon[0] == pytest.approx((20.0, 60.0))
    assert result.model_version == "egg-stack-face/7"


@pytest.mark.asyncio
async def test_rejects_individual_tray_box_model() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "predictions": [
                    {"class": "tray", "confidence": 0.99, "x": 5, "y": 5, "width": 4, "height": 4}
                ]
            },
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = RoboflowInferenceProvider(settings(), client=client)
    with pytest.raises(UnsupportedModelOutputError):
        await provider.infer(b"image", np.zeros((10, 10, 3), dtype=np.uint8), {})
    await client.aclose()


@pytest.mark.asyncio
async def test_egg_tray_alias_produces_stack_face_rois() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "predictions": [
                    {"class": "egg_tray", "confidence": 0.91, "x": 5, "y": 5, "width": 4, "height": 4},
                    {"class": "egg_tray", "confidence": 0.82, "x": 5, "y": 9, "width": 4, "height": 4},
                ]
            },
        )

    baseline_settings = Settings(
        inference_provider="roboflow",
        roboflow_api_key="test-secret",
        roboflow_model_id="projec-mutta/2",
        roboflow_max_retries=0,
        allow_experimental_tray_box_baseline=True,
    )
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = RoboflowInferenceProvider(baseline_settings, client=client)
    result = await provider.infer(b"image", np.zeros((10, 10, 3), dtype=np.uint8), {})
    await client.aclose()

    assert len(result.predictions) == 2
    assert all(prediction.class_name == "egg_tray" for prediction in result.predictions)
    assert result.output_class is None
    assert result.detection_count is None


@pytest.mark.asyncio
async def test_timeout_is_typed() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow", request=request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = RoboflowInferenceProvider(settings(), client=client)
    with pytest.raises(InferenceProviderError, match="timed out"):
        await provider.infer(b"image", np.zeros((10, 10, 3), dtype=np.uint8), {})
    await client.aclose()


@pytest.mark.asyncio
async def test_malformed_response_is_typed() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"not-json")

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = RoboflowInferenceProvider(settings(), client=client)
    with pytest.raises(InferenceProviderError, match="malformed JSON"):
        await provider.infer(b"image", np.zeros((10, 10, 3), dtype=np.uint8), {})
    await client.aclose()
