"""Optional warmed research model. Client polygons are hypotheses, never certified stock."""
import hashlib
import io
import os
from pathlib import Path
import threading
from dataclasses import asdict
from typing import Annotated

import numpy as np
import cv2
from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from PIL import Image, ImageOps
from pydantic import BaseModel, ConfigDict, Field
from starlette.concurrency import run_in_threadpool

from app.api.routes import _read_upload
from app.vision.heatmap_sequence import solve_layer_sequence
from app.vision.stack_measurement import analyze_rims, rectify_native
from app.vision.quality import evaluate_quality
from app.config import Settings

router = APIRouter()


class StackInput(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)
    stack_id: str = Field(min_length=1, max_length=80)
    polygon: list[tuple[float, float]] = Field(min_length=4, max_length=4)
    rf_centres: list[tuple[float, float]] = Field(default_factory=list, max_length=2000)


class HeatmapInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    image_sha256: str = Field(pattern="^[a-f0-9]{64}$")
    source_view: str = Field(pattern="^(left|right|straight)$")
    coordinate_frame: str = Field(pattern="^exif_transposed_pixels$")
    stacks: list[StackInput] = Field(min_length=1, max_length=30)


class HeatmapRunner:
    def __init__(self, checkpoint):
        import torch
        from app.vision.heatmap_model import load_model
        torch.set_num_threads(min(4, os.cpu_count() or 1))
        self.model, self.config = load_model(checkpoint)
        self.device = os.environ.get("STACK_HEATMAP_DEVICE", "cpu")
        if self.device not in ("cpu", "cuda"):
            raise ValueError("STACK_HEATMAP_DEVICE must be cpu or cuda")
        self.model.to(self.device)
        self.model_sha256 = hashlib.sha256(Path(checkpoint).read_bytes()).hexdigest()
        # ponytail: one CPU inference at a time; separate GPU worker pool if measured load requires it.
        self.lock = threading.Lock()

    def infer(self, rgb, record):
        import torch
        from app.vision.heatmap_model import image_tensor
        points = np.asarray(record["polygon"], dtype=np.float32)
        if not cv2.isContourConvex(points) or abs(cv2.contourArea(points)) < 16:
            raise ValueError("Nondegenerate convex stack polygon required")
        if np.prod(np.ptp(points, axis=0)) > 4_000_000:
            raise ValueError("Candidate face exceeds pixel budget")
        face, geometry = rectify_native(rgb[:, :, ::-1].copy(), record["polygon"])
        height = self.config["height"]
        with self.lock, torch.inference_mode():
            probabilities = self.model(image_tensor(face.image[:, :, ::-1].copy(), height,
                                             self.config["width"]).unsqueeze(0).to(self.device)).sigmoid()[0].cpu().numpy()
        bands = analyze_rims(face.image)
        scale = (height - 1) / (face.image.shape[0] - 1)
        hypotheses = [{**h, "pitch_px": h["pitch_px"] * scale,
                       "centres": [y * scale for y in h["centres"]]}
                      for h in bands.get("hypotheses", []) if 1 <= h["pitch_px"] * scale < height]
        rf = []
        for point in record.get("rf_centres", []):
            if not 0 <= point[0] < rgb.shape[1] or not 0 <= point[1] < rgb.shape[0]:
                raise ValueError("RF centre outside original image")
            transformed = cv2.perspectiveTransform(np.array([[point]], dtype=np.float32), face.homography)[0, 0]
            if 0 <= transformed[0] < face.image.shape[1] and 0 <= transformed[1] < face.image.shape[0]:
                rf.append({"y": min(height - 1., float(transformed[1] * scale))})
        sequence = solve_layer_sequence(probabilities, band_hypotheses=hypotheses, rf_detections=rf,
                         peak_threshold=self.config["threshold"], quality=None, endpoints=None)
        quality = asdict(evaluate_quality(face.image, Settings()))
        return {"stack_id": record["stack_id"], "stack_polygon": record["polygon"],
                "rectification": {**geometry, "homography": face.homography.tolist(),
                                  "heatmap_height": height, "native_to_heatmap_y_scale": scale},
                "heatmap_probabilities": probabilities.tolist(), "heatmap_peaks": sequence["heatmap_peaks"],
                "rf_evidence": {"centres": rf, "source": "client_supplied_untrusted_diagnostic"}, "band_candidates": hypotheses,
                "selected_physical_z": sequence["selected_count"], "sequence": sequence,
                "occupancy": "unknown", "quality": {"image_diagnostics": quality,
                    "threshold_profile": "existing_image_defaults_not_calibrated_for_stack_roi",
                    "completeness": "unknown", "inventory_suitable": None}, "verified": False}


def configure_heatmap(app):
    checkpoint = os.environ.get("STACK_HEATMAP_CHECKPOINT")
    app.state.heatmap_runner = HeatmapRunner(checkpoint) if checkpoint else None
    app.include_router(router)


@router.post("/candidate/stack-heatmap")
async def stack_heatmap(request: Request, image: Annotated[UploadFile, File()],
                        evidence: Annotated[str, Form(max_length=100_000)]):
    if request.app.state.settings.app_env == "production":
        raise HTTPException(404, "Research route only")
    runner = request.app.state.heatmap_runner
    if runner is None:
        raise HTTPException(503, "No research heatmap checkpoint configured")
    try:
        record = HeatmapInput.model_validate_json(evidence).model_dump()
        if len(set(s["stack_id"] for s in record["stacks"])) != len(record["stacks"]):
            raise ValueError("Duplicate stack IDs")
        content = await _read_upload(image, request.app.state.settings.max_upload_bytes, record["source_view"])
        if hashlib.sha256(content).hexdigest() != record["image_sha256"]:
            raise ValueError("Hash mismatch")
        with Image.open(io.BytesIO(content)) as source:
            if source.width * source.height > 60_000_000:
                raise ValueError("Image exceeds pixel budget")
            rgb = np.asarray(ImageOps.exif_transpose(source).convert("RGB")).copy()
        stacks = [await run_in_threadpool(runner.infer, rgb, stack) for stack in record["stacks"]]
        for stack in stacks:
            stack["source_views"] = [record["source_view"]]
            stack["source_sha256"] = record["image_sha256"]
        return {"candidate": "STACK-HEATMAP-HYBRID-V1", "model_sha256": runner.model_sha256,
                "stacks": stacks, "physical_grid": None, "inventory_total": None, "verified": False,
                "evidence_source": "client_supplied_polygons_not_independent_localization",
                "reason": "Endpoints, quality, occupancy and cross-view identity remain unverified"}
    except (ValueError, KeyError, TypeError, OSError) as exc:
        raise HTTPException(422, "Invalid candidate image or polygon evidence") from exc
