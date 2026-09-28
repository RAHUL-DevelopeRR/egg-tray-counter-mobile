"""Authenticated hosting entrypoint for diagnostic bands/correspondence only."""
import hmac
import os

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.api.candidate import router
from app.api.heatmap_candidate import configure_heatmap
from app.config import Settings


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
        return {'status': 'ok', 'mode': 'diagnostic_only', 'inventory_verification_ready': False}

    app.include_router(router)
    configure_heatmap(app)
    return app
