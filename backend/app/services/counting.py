from __future__ import annotations

import asyncio
import logging
import time
from pathlib import Path

import cv2

from app.config import Settings
from app.errors import StackAssociationError
from app.providers.base import InferenceProvider, InferenceResult
from app.schemas.scan import (
    ModelSchema,
    ProcessingSchema,
    RescanSchema,
    ScanResponse,
    StackCountsSchema,
    StackResultSchema,
    ViewQualitySchema,
)
from app.vision.fusion import FusedStack, fuse_scene
from app.vision.layer_signal import count_layers
from app.vision.overlay import draw_rectified_layers, draw_source_predictions
from app.vision.quality import ImageQuality, decode_image, evaluate_quality
from app.vision.rectification import rectify_face
from app.vision.stack_matching import StackObservation, associate_by_spatial_order

LOGGER = logging.getLogger(__name__)
VIEW_NAMES = ("left", "right", "straight")


class CountingService:
    def __init__(self, settings: Settings, provider: InferenceProvider) -> None:
        self.settings = settings
        self.provider = provider

    async def count_triplet(self, scan_id: str, content: dict[str, bytes]) -> ScanResponse:
        total_started = time.perf_counter()
        timings: dict[str, int] = {}

        decode_started = time.perf_counter()
        images = {view: decode_image(content[view]) for view in VIEW_NAMES}
        timings["image_decoding"] = round((time.perf_counter() - decode_started) * 1000)

        quality_started = time.perf_counter()
        qualities = {view: evaluate_quality(images[view], self.settings) for view in VIEW_NAMES}
        timings["image_quality"] = round((time.perf_counter() - quality_started) * 1000)

        inference_started = time.perf_counter()
        results = await asyncio.gather(
            *(
                self.provider.infer(
                    content[view],
                    images[view],
                    {"scan_id": scan_id, "view": view},
                )
                for view in VIEW_NAMES
            )
        )
        inference_by_view = dict(zip(VIEW_NAMES, results, strict=True))
        timings["model_inference"] = round((time.perf_counter() - inference_started) * 1000)

        observations_started = time.perf_counter()
        observations = self._build_observations(scan_id, images, qualities, inference_by_view)
        timings["roi_and_layer_count"] = round((time.perf_counter() - observations_started) * 1000)

        model_version = self._model_version(results)
        processing_mode = results[0].provider if results else "unknown"
        recommended_view = self._recommended_view(qualities, observations)

        association_started = time.perf_counter()
        try:
            matched = associate_by_spatial_order(
                observations,
                minimum_confidence=self.settings.association_threshold,
            )
        except StackAssociationError as exc:
            timings["cross_view_matching"] = round((time.perf_counter() - association_started) * 1000)
            return self._rescan_response(
                scan_id=scan_id,
                reason=exc.message,
                recommended_view=recommended_view,
                qualities=qualities,
                stacks=[],
                mode=processing_mode,
                model_version=model_version,
                timings=timings,
                total_started=total_started,
            )
        timings["cross_view_matching"] = round((time.perf_counter() - association_started) * 1000)

        fusion_started = time.perf_counter()
        fused = fuse_scene(matched, self.settings)
        timings["fusion"] = round((time.perf_counter() - fusion_started) * 1000)
        if not fused or any(not stack.accepted for stack in fused):
            failed = next((stack for stack in fused if not stack.accepted), None)
            reason = failed.reason if failed else "No physical stack could be verified"
            return self._rescan_response(
                scan_id=scan_id,
                reason=reason,
                recommended_view=recommended_view,
                qualities=qualities,
                stacks=fused,
                mode=processing_mode,
                model_version=model_version,
                timings=timings,
                total_started=total_started,
            )

        total_trays = sum(stack.final_count or 0 for stack in fused)
        timings["total"] = round((time.perf_counter() - total_started) * 1000)
        response = ScanResponse(
            scan_id=scan_id,
            status="verified",
            accepted=True,
            physical_stack_count=len(fused),
            total_trays=total_trays,
            eggs_per_tray=self.settings.eggs_per_tray,
            total_eggs=total_trays * self.settings.eggs_per_tray,
            model=self._model_schema(processing_mode, model_version),
            processing=ProcessingSchema(
                mode=processing_mode,
                latency_ms=timings["total"],
                model_version=model_version,
                timings_ms=timings,
            ),
            views=self._view_schemas(qualities),
            stacks=self._stack_schemas(fused),
            rescan=None,
        )
        LOGGER.info(
            "scan completed",
            extra={
                "scan_id": scan_id,
                "processing_stage": "complete",
                "duration_ms": timings["total"],
                "provider": processing_mode,
                "model_version": model_version,
            },
        )
        return response

    def _build_observations(
        self,
        scan_id: str,
        images: dict[str, object],
        qualities: dict[str, ImageQuality],
        inference_by_view: dict[str, InferenceResult],
    ) -> dict[str, list[StackObservation]]:
        all_observations: dict[str, list[StackObservation]] = {view: [] for view in VIEW_NAMES}
        debug_root = Path(self.settings.debug_output_dir) / scan_id
        for view in VIEW_NAMES:
            image = images[view]
            height, width = image.shape[:2]
            predictions = [
                prediction
                for prediction in inference_by_view[view].predictions
                if prediction.confidence >= self.settings.min_segmentation_confidence
            ]
            if self.settings.debug_overlays:
                debug_root.mkdir(parents=True, exist_ok=True)
                cv2.imwrite(
                    str(debug_root / f"{view}-predictions.jpg"), draw_source_predictions(image, predictions)
                )
            for index, prediction in enumerate(sorted(predictions, key=lambda item: item.center_x), start=1):
                try:
                    face = rectify_face(
                        image,
                        prediction.polygon,
                        (self.settings.rectified_width, self.settings.rectified_height),
                    )
                    layer_result = count_layers(face.image, self.settings)
                except (ValueError, cv2.error):
                    continue
                if self.settings.debug_overlays:
                    cv2.imwrite(
                        str(debug_root / f"{view}-stack-{index:02d}-layers.jpg"),
                        draw_rectified_layers(face.image, layer_result),
                    )
                x1, y1, x2, y2 = prediction.bbox
                all_observations[view].append(
                    StackObservation(
                        view=view,
                        center_x_normalized=float(((x1 + x2) / 2) / width),
                        height_normalized=float((y2 - y1) / height),
                        tray_count=layer_result.tray_count,
                        image_quality=qualities[view].score if qualities[view].accepted else 0.0,
                        segmentation_quality=prediction.confidence,
                        periodicity_quality=layer_result.quality,
                        inferred_layers=layer_result.inferred_internal_layers,
                        top_visible=y1 <= height * 0.15,
                        bottom_visible=y2 >= height * 0.85,
                    )
                )
        return all_observations

    @staticmethod
    def _model_version(results: tuple[InferenceResult, ...] | list[InferenceResult]) -> str:
        versions = sorted({result.model_version for result in results})
        return ",".join(versions) if versions else "unavailable"

    @staticmethod
    def _recommended_view(
        qualities: dict[str, ImageQuality],
        observations: dict[str, list[StackObservation]],
    ) -> str:
        missing = [view for view in VIEW_NAMES if not observations[view]]
        if missing:
            return min(missing, key=lambda view: qualities[view].score)
        return min(VIEW_NAMES, key=lambda view: qualities[view].score)

    @staticmethod
    def _view_schemas(qualities: dict[str, ImageQuality]) -> dict[str, ViewQualitySchema]:
        return {
            view: ViewQualitySchema(
                quality=quality.score,
                accepted=quality.accepted,
                blur_score=quality.blur_score,
                exposure_mean=quality.exposure_mean,
                reason=quality.reason,
            )
            for view, quality in qualities.items()
        }

    def _model_schema(self, provider: str, model_version: str) -> ModelSchema:
        return ModelSchema(
            provider=provider,
            workspace=self.settings.roboflow_workspace,
            project=self.settings.roboflow_project,
            version=self.settings.roboflow_model_version,
            model_id=self.settings.roboflow_model_id or model_version,
        )

    @staticmethod
    def _stack_schemas(stacks: list[FusedStack]) -> list[StackResultSchema]:
        return [
            StackResultSchema(
                physical_stack_id=stack.physical_stack_id,
                counts=StackCountsSchema(**stack.counts),
                final_count=stack.final_count,
                confidence=stack.confidence,
                accepted=stack.accepted,
                reason=stack.reason,
                association_confidence=stack.association_confidence,
            )
            for stack in stacks
        ]

    def _rescan_response(
        self,
        *,
        scan_id: str,
        reason: str,
        recommended_view: str,
        qualities: dict[str, ImageQuality],
        stacks: list[FusedStack],
        mode: str,
        model_version: str,
        timings: dict[str, int],
        total_started: float,
    ) -> ScanResponse:
        timings["total"] = round((time.perf_counter() - total_started) * 1000)
        return ScanResponse(
            scan_id=scan_id,
            status="rescan_required",
            accepted=False,
            physical_stack_count=None,
            total_trays=None,
            eggs_per_tray=self.settings.eggs_per_tray,
            total_eggs=None,
            model=self._model_schema(mode, model_version),
            processing=ProcessingSchema(
                mode=mode,
                latency_ms=timings["total"],
                model_version=model_version,
                timings_ms=timings,
            ),
            views=self._view_schemas(qualities),
            stacks=self._stack_schemas(stacks),
            rescan=RescanSchema(recommended_view=recommended_view, reason=reason),
        )
