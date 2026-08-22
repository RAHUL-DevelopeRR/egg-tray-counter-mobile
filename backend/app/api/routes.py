from __future__ import annotations

import hashlib
import uuid
from typing import Annotated

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile, status

from app.repository import InMemoryScanRepository
from app.schemas.scan import ScanResponse
from app.services.counting import CountingService

router = APIRouter()
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png"}


def _is_allowed_signature(content: bytes) -> bool:
    return content.startswith(b"\xff\xd8\xff") or content.startswith(b"\x89PNG\r\n\x1a\n")


async def _read_upload(upload: UploadFile, max_bytes: int, view: str) -> bytes:
    if upload.content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail={"code": "invalid_mime_type", "message": f"{view.upper()} must be a JPEG or PNG image"},
        )
    content = await upload.read(max_bytes + 1)
    if len(content) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={
                "code": "image_too_large",
                "message": f"{view.upper()} exceeds the configured upload limit",
            },
        )
    if not content or not _is_allowed_signature(content):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail={
                "code": "invalid_image_signature",
                "message": f"{view.upper()} content is not a JPEG or PNG",
            },
        )
    return content


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
async def ready(request: Request) -> dict[str, object]:
    settings = request.app.state.settings
    return {
        "status": "ready",
        "provider": settings.inference_provider,
        "model_reference": settings.roboflow_model_reference or None,
        "experimental_tray_box_baseline": settings.allow_experimental_tray_box_baseline,
    }


@router.get("/version")
async def version(request: Request) -> dict[str, str | None]:
    settings = request.app.state.settings
    return {
        "version": settings.app_version,
        "provider": settings.inference_provider,
        "model_reference": settings.roboflow_model_reference or None,
    }


@router.post("/v1/scans/count", response_model=ScanResponse)
async def count_scan(
    request: Request,
    left: Annotated[UploadFile, File(description="Original-resolution LEFT image")],
    right: Annotated[UploadFile, File(description="Original-resolution RIGHT image")],
    straight: Annotated[UploadFile, File(description="Original-resolution STRAIGHT image")],
    scan_id: Annotated[str | None, Form()] = None,
    device_model: Annotated[str | None, Form(max_length=120)] = None,
    app_version: Annotated[str | None, Form(max_length=40)] = None,
    warehouse_id: Annotated[str | None, Form(max_length=120)] = None,
    lane_id: Annotated[str | None, Form(max_length=120)] = None,
) -> ScanResponse:
    del device_model, app_version, warehouse_id, lane_id
    settings = request.app.state.settings
    try:
        resolved_scan_id = str(uuid.UUID(scan_id)) if scan_id else str(uuid.uuid4())
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"code": "invalid_scan_id", "message": "scan_id must be a UUID"},
        ) from exc
    content = {
        "left": await _read_upload(left, settings.max_upload_bytes, "left"),
        "right": await _read_upload(right, settings.max_upload_bytes, "right"),
        "straight": await _read_upload(straight, settings.max_upload_bytes, "straight"),
    }
    hashes = {view: hashlib.sha256(value).hexdigest() for view, value in content.items()}
    if len(set(hashes.values())) != 3:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "code": "duplicate_view",
                "message": "LEFT, RIGHT, and STRAIGHT must be distinct photographs",
            },
        )
    fingerprint = hashlib.sha256(
        "|".join(hashes[view] for view in ("left", "right", "straight")).encode()
    ).hexdigest()
    repository: InMemoryScanRepository = request.app.state.repository
    scan_lock = await repository.lock_for(resolved_scan_id)
    async with scan_lock:
        existing = await repository.get(resolved_scan_id)
        if existing:
            if existing.fingerprint != fingerprint:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "code": "scan_id_conflict",
                        "message": "scan_id was already used for different photographs",
                    },
                )
            return existing.response
        service: CountingService = request.app.state.counting_service
        response = await service.count_triplet(resolved_scan_id, content)
        await repository.save(resolved_scan_id, fingerprint, response)
        return response
