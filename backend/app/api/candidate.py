"""Local candidate route consuming images and saved, hash-bound RF boxes.

No new upstream call or production route is enabled. Evidence is client-supplied
research input, so this route never asserts trusted inventory certification.
"""

import hashlib
import io
from typing import Annotated

import numpy as np
from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from PIL import Image, ImageOps
from starlette.concurrency import run_in_threadpool

from app.api.routes import _read_upload
from app.schemas.candidate import CandidateEvidence, CandidateResponse
from app.vision.spatial_3d import candidate_scene

router = APIRouter()


@router.post("/candidate/count-3d", response_model=CandidateResponse)
async def count_3d(
    request: Request,
    left: Annotated[UploadFile, File()],
    right: Annotated[UploadFile, File()],
    straight: Annotated[UploadFile, File()],
    evidence: Annotated[str, Form(max_length=2_000_000)],
):
    if request.app.state.settings.app_env == "production":
        raise HTTPException(404, "Local research route only")
    try:
        data = CandidateEvidence.model_validate_json(evidence).model_dump(by_alias=True)
        images, detections, hashes = {}, {}, set()
        for view, upload in (("left", left), ("right", right), ("straight", straight)):
            content = await _read_upload(upload, request.app.state.settings.max_upload_bytes, view)
            digest = hashlib.sha256(content).hexdigest()
            record = data["views"][view]
            if digest != record["image_sha256"] or digest in hashes:
                raise ValueError("Image hash mismatch or duplicate view")
            hashes.add(digest)
            with Image.open(io.BytesIO(content)) as image:
                if image.width * image.height > 60_000_000:
                    raise ValueError("Image exceeds candidate pixel budget")
                images[view] = np.asarray(ImageOps.exif_transpose(image).convert("RGB"))[:, :, ::-1].copy()
            if record.get("coordinate_frame") != "exif_transposed_pixels":
                raise ValueError("EXIF-transposed pixel coordinates required")
            detections[view] = record["detections"]
            if not isinstance(detections[view], list) or len(detections[view]) > 2000:
                raise ValueError("Detection list exceeds candidate budget")
        visibility = {v: r["visibility"] for v, r in data["views"].items()}
        result = await run_in_threadpool(candidate_scene, images, detections, data["sop"], visibility)
        result["evidence_source"] = "client_supplied_hash_bound_predictions_not_independently_authenticated"
        return result
    except (ValueError, KeyError, TypeError, OSError) as exc:
        raise HTTPException(422, "Invalid candidate image/evidence input") from exc
