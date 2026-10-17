"""Authenticated hosting entrypoint for diagnostic bands/correspondence only."""
import hmac
import json
import os
import cv2
import numpy as np
from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Lock
from typing import Annotated

from fastapi import FastAPI, Request, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool
from PIL import Image, ImageOps, UnidentifiedImageError

from app.api.candidate import router
from app.api.heatmap_candidate import configure_heatmap
from app.config import Settings
from app.api.routes import _read_upload
from app.vision.reconstruction import run as reconstruct
from app.vision.rim_count import rim_count

# ponytail: one reconstruction at a time per process; use a job queue for sustained throughput.
reconstruction_lock = Lock()


def create_vision_app(token: str | None = None) -> FastAPI:
    secret = token if token is not None else os.environ.get('VISION_SERVICE_TOKEN', '')
    if len(secret) < 32:
        raise ValueError('VISION_SERVICE_TOKEN must contain at least 32 characters')
    app = FastAPI(title='Egg tray diagnostic vision service', docs_url=None, redoc_url=None, openapi_url=None)
    app.state.settings = Settings(app_env='diagnostic_host')

    @app.middleware('http')
    async def authenticate(request: Request, call_next):
        if request.url.path != '/health' and not hmac.compare_digest(
            request.headers.get('authorization', '').encode(), f'Bearer {secret}'.encode()
        ):
            return JSONResponse({'detail': 'Unauthorized'}, status_code=401)
        return await call_next(request)

    @app.get('/health')
    def health():
        return {'status': 'ok', 'mode': 'diagnostic_only', 'inventory_verification_ready': False,
                'reconstruction_contract': 'two_view_sfm_diagnostic_v1'}

    @app.post('/candidate/reconstruct')
    async def reconstruct_pair(first: UploadFile = File(...), second: UploadFile = File(...)):
        # Keep the multipart body below Lambda's synchronous request envelope limit.
        photos = [await _read_upload(upload, 2_000_000, view)
                  for upload, view in ((first, 'first'), (second, 'second'))]
        dimensions = []
        for raw in photos:
            try:
                with Image.open(BytesIO(raw)) as image:
                    if image.width * image.height > 12_000_000:
                        raise HTTPException(413, 'Each image must be at most 12 megapixels')
                    dimensions.append(image.size)
                    image.verify()
            except (UnidentifiedImageError, OSError, SyntaxError, ValueError, Image.DecompressionBombError):
                raise HTTPException(415, 'Invalid image') from None
        if photos[0] == photos[1] or dimensions[0] != dimensions[1]:
            raise HTTPException(422, 'Use two distinct overlapping photos with equal dimensions')
        if not reconstruction_lock.acquire(blocking=False):
            raise HTTPException(429, 'Reconstruction busy; retry shortly')
        try:
            with TemporaryDirectory(prefix='tray-reconstruction-') as directory:
                root = Path(directory)
                paths = [root / 'first.jpg', root / 'second.jpg']
                for path, raw in zip(paths, photos):
                    path.write_bytes(raw)
                return await run_in_threadpool(reconstruct, paths, root / 'result')
        except cv2.error:
            return {'status': 'pose_failed', 'reason': 'Geometry estimation failed. Capture more overlapping views.',
                    'physical_trays': None, 'verified': False, 'scale': 'arbitrary_unit_baseline',
                    'focal_hypotheses': [], 'mutual_matches': 0}
        except ValueError:
            raise HTTPException(422, 'Images could not be reconstructed') from None
        finally:
            reconstruction_lock.release()

    @app.post('/candidate/rim-count')
    async def rim_count_columns(image: Annotated[UploadFile, File()], columns: Annotated[str, Form()]):
        """Independent edge-peak layer count per column; diagnostic evidence, never a verified count.

        ``columns`` is the JSON list produced by ``layer_span.count_layers_by_span`` (x_min, x_max,
        y_first, y_last, pitch_px, span_count) in pixels of the EXIF-transposed image, which is the
        frame the detector boxes are reported in. The image is decoded in memory; no temp files.
        """
        raw = await _read_upload(image, 8_000_000, 'image')
        try:
            with Image.open(BytesIO(raw)) as picture:
                if picture.width * picture.height > 12_000_000:
                    raise HTTPException(413, 'Image must be at most 12 megapixels')
                picture.verify()
        except (UnidentifiedImageError, OSError, SyntaxError, ValueError, Image.DecompressionBombError):
            raise HTTPException(415, 'Invalid image') from None
        try:
            parsed = json.loads(columns)
        except ValueError:
            raise HTTPException(422, 'columns must be a JSON list') from None
        if not isinstance(parsed, list) or len(parsed) > 50 or not all(isinstance(c, dict) for c in parsed):
            raise HTTPException(422, 'columns must be a JSON list of at most 50 column objects')

        def work():
            with Image.open(BytesIO(raw)) as picture:
                rgb = np.asarray(ImageOps.exif_transpose(picture).convert('RGB'))
            bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
            return {'columns': rim_count(bgr, parsed),
                    'image': {'width': int(bgr.shape[1]), 'height': int(bgr.shape[0])}}

        return await run_in_threadpool(work)

    app.include_router(router)
    configure_heatmap(app)
    return app
