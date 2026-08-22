from __future__ import annotations

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app import __version__
from app.api.routes import router
from app.config import Settings
from app.errors import EggCounterError, InferenceProviderError
from app.logging_config import configure_logging
from app.providers.base import InferenceProvider
from app.providers.mock import MockInferenceProvider
from app.providers.roboflow import RoboflowInferenceProvider
from app.repository import InMemoryScanRepository
from app.services.counting import CountingService


def build_provider(settings: Settings) -> InferenceProvider:
    if settings.inference_provider == "mock":
        return MockInferenceProvider(settings.mock_stack_count)
    if settings.inference_provider == "roboflow":
        return RoboflowInferenceProvider(settings)
    raise ValueError(f"Unsupported INFERENCE_PROVIDER: {settings.inference_provider}")


def create_app(settings: Settings | None = None, provider: InferenceProvider | None = None) -> FastAPI:
    resolved_settings = settings or Settings.from_env()
    resolved_settings.validate_runtime()
    configure_logging(resolved_settings.log_level)
    app = FastAPI(
        title="Egg Tray Counter API",
        version=resolved_settings.app_version or __version__,
        description="Conservative three-view tray-layer verification API.",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(resolved_settings.allowed_origins),
        allow_credentials=True,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type", "Authorization"],
    )
    app.state.settings = resolved_settings
    app.state.provider = provider or build_provider(resolved_settings)
    app.state.counting_service = CountingService(resolved_settings, app.state.provider)
    app.state.repository = InMemoryScanRepository()
    app.include_router(router)

    @app.exception_handler(InferenceProviderError)
    async def inference_error_handler(_request: Request, exc: InferenceProviderError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"detail": {"code": exc.code, "message": exc.message}},
        )

    @app.exception_handler(EggCounterError)
    async def domain_error_handler(_request: Request, exc: EggCounterError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={
                "detail": {"code": exc.code, "message": exc.message, "recommended_view": exc.recommended_view}
            },
        )

    return app


app = create_app()
