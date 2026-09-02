from __future__ import annotations

import asyncio
import base64
import time
from collections.abc import Mapping
from typing import Any

import httpx
import numpy as np

from app.config import Settings
from app.errors import InferenceProviderError, UnsupportedModelOutputError
from app.providers.base import InferenceProvider, InferenceResult, StackFacePrediction

RETRYABLE_STATUS_CODES = {429, 502, 503, 504}


class RoboflowInferenceProvider(InferenceProvider):
    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self.settings = settings
        self._client = client

    async def infer(
        self,
        image_bytes: bytes,
        image: np.ndarray,
        metadata: dict[str, object],
    ) -> InferenceResult:
        model_reference = self.settings.roboflow_model_reference
        if not self.settings.roboflow_api_key or not model_reference:
            raise InferenceProviderError("Roboflow credentials and an explicit model version are required")
        url = f"{self.settings.roboflow_inference_url}/{model_reference}"
        params = {
            "api_key": self.settings.roboflow_api_key,
            "confidence": self.settings.roboflow_confidence,
            "format": "json",
        }
        body = base64.b64encode(image_bytes)
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
        started = time.perf_counter()
        owns_client = self._client is None
        client = self._client or httpx.AsyncClient(timeout=self.settings.roboflow_timeout_seconds)
        try:
            response = await self._post_with_retry(client, url, params=params, content=body, headers=headers)
            try:
                payload = response.json()
            except ValueError as exc:
                raise InferenceProviderError("Roboflow returned malformed JSON") from exc
            predictions, detection_count, output_class, average_confidence = self._normalize(
                payload, image.shape[1], image.shape[0]
            )
        finally:
            if owns_client:
                await client.aclose()
        return InferenceResult(
            predictions=tuple(predictions),
            provider="roboflow_cloud",
            model_version=model_reference,
            latency_ms=round((time.perf_counter() - started) * 1000),
            detection_count=detection_count,
            output_class=output_class,
            average_detection_confidence=average_confidence,
        )

    async def _post_with_retry(self, client: httpx.AsyncClient, url: str, **kwargs: Any) -> httpx.Response:
        last_error: Exception | None = None
        for attempt in range(self.settings.roboflow_max_retries + 1):
            try:
                response = await client.post(url, **kwargs)
                if response.status_code not in RETRYABLE_STATUS_CODES:
                    response.raise_for_status()
                    return response
                last_error = InferenceProviderError(
                    f"Roboflow temporarily unavailable (HTTP {response.status_code})"
                )
            except httpx.TimeoutException as exc:
                last_error = InferenceProviderError("Roboflow inference timed out")
                last_error.__cause__ = exc
            except httpx.HTTPStatusError as exc:
                status = exc.response.status_code
                if status == 403:
                    raise InferenceProviderError("Roboflow authentication was rejected") from exc
                if status == 404:
                    raise InferenceProviderError("Configured Roboflow model/version was not found") from exc
                if status == 413:
                    raise InferenceProviderError("Roboflow rejected an oversized image") from exc
                raise InferenceProviderError(f"Roboflow inference failed (HTTP {status})") from exc
            except httpx.HTTPError as exc:
                last_error = InferenceProviderError("Roboflow network request failed")
                last_error.__cause__ = exc
            if attempt < self.settings.roboflow_max_retries:
                await asyncio.sleep(min(0.25 * (2**attempt), 1.0))
        if last_error:
            raise last_error
        raise InferenceProviderError("Roboflow inference failed")

    def _normalize(
        self, payload: Any, original_width: int, original_height: int
    ) -> tuple[list[StackFacePrediction], int | None, str | None, float | None]:
        if not isinstance(payload, Mapping) or not isinstance(payload.get("predictions"), list):
            raise InferenceProviderError("Roboflow response is missing a predictions list")
        image_meta = payload.get("image") if isinstance(payload.get("image"), Mapping) else {}
        response_width = float(image_meta.get("width") or original_width)
        response_height = float(image_meta.get("height") or original_height)
        scale_x = original_width / response_width
        scale_y = original_height / response_height
        normalized: list[StackFacePrediction] = []
        unsupported_classes: set[str] = set()
        raw_predictions = payload["predictions"]
        for raw in raw_predictions:
            if not isinstance(raw, Mapping):
                raise InferenceProviderError("Roboflow prediction entry is malformed")
            class_name = str(raw.get("class") or raw.get("class_name") or "unknown")
            confidence = float(raw.get("confidence", 0.0))
            if confidence < self.settings.min_segmentation_confidence:
                continue
            accepted_alias = self.settings.allow_experimental_tray_box_baseline and class_name == "egg_tray"
            if class_name not in self.settings.accepted_stack_classes and not accepted_alias:
                unsupported_classes.add(class_name)
                continue
            polygon = self._polygon(raw, scale_x, scale_y)
            xs = [point[0] for point in polygon]
            ys = [point[1] for point in polygon]
            normalized.append(
                StackFacePrediction(
                    polygon=tuple(polygon),
                    bbox=(min(xs), min(ys), max(xs), max(ys)),
                    confidence=confidence,
                    class_name=class_name,
                    metadata={"detection_id": raw.get("detection_id")},
                )
            )
        if normalized:
            return normalized, None, None, None
        if raw_predictions and unsupported_classes:
            classes = ", ".join(sorted(unsupported_classes))
            raise UnsupportedModelOutputError(
                f"Configured model returned [{classes}], not a stack-face class. "
                "Annotate `stack_face` polygons; individual tray boxes are not summed."
            )
        return normalized, None, None, None

    @staticmethod
    def _polygon(raw: Mapping[str, Any], scale_x: float, scale_y: float) -> list[tuple[float, float]]:
        points = raw.get("points")
        if isinstance(points, list) and len(points) >= 3:
            polygon: list[tuple[float, float]] = []
            for point in points:
                if not isinstance(point, Mapping) or "x" not in point or "y" not in point:
                    raise InferenceProviderError("Roboflow segmentation polygon is malformed")
                polygon.append((float(point["x"]) * scale_x, float(point["y"]) * scale_y))
            return polygon
        required = ("x", "y", "width", "height")
        if not all(key in raw for key in required):
            raise InferenceProviderError("Roboflow prediction has neither a polygon nor a bounding box")
        center_x = float(raw["x"])
        center_y = float(raw["y"])
        width = float(raw["width"])
        height = float(raw["height"])
        return [
            ((center_x - width / 2) * scale_x, (center_y - height / 2) * scale_y),
            ((center_x + width / 2) * scale_x, (center_y - height / 2) * scale_y),
            ((center_x + width / 2) * scale_x, (center_y + height / 2) * scale_y),
            ((center_x - width / 2) * scale_x, (center_y + height / 2) * scale_y),
        ]
