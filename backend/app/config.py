from __future__ import annotations

import os
from dataclasses import dataclass, field


def _int(name: str, default: int) -> int:
    return int(os.getenv(name, default))


def _float(name: str, default: float) -> float:
    return float(os.getenv(name, default))


def _bool(name: str, default: bool = False) -> bool:
    return os.getenv(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


def _csv(name: str, default: str) -> tuple[str, ...]:
    return tuple(value.strip() for value in os.getenv(name, default).split(",") if value.strip())


@dataclass(frozen=True)
class Settings:
    app_env: str = "development"
    log_level: str = "INFO"
    app_version: str = "0.1.0"
    inference_provider: str = "mock"
    eggs_per_tray: int = 30
    max_upload_bytes: int = 20 * 1024 * 1024
    allowed_origins: tuple[str, ...] = ("http://localhost:3000", "http://localhost:8080")

    min_image_width: int = 480
    min_image_height: int = 480
    min_blur_score: float = 35.0
    max_dark_fraction: float = 0.88
    max_bright_fraction: float = 0.88
    min_view_quality: float = 0.58
    min_segmentation_confidence: float = 0.35
    min_pitch_px: int = 8
    max_pitch_px: int = 90
    peak_prominence_factor: float = 0.55
    max_inferred_layers: int = 2
    association_threshold: float = 0.62
    side_margin_fraction: float = 0.10
    rectified_width: int = 512
    rectified_height: int = 768

    roboflow_api_key: str = ""
    roboflow_workspace: str = ""
    roboflow_project: str = ""
    roboflow_model_id: str = ""
    roboflow_model_version: str = ""
    roboflow_inference_url: str = "https://serverless.roboflow.com"
    roboflow_timeout_seconds: float = 20.0
    roboflow_confidence: int = 35
    roboflow_max_retries: int = 2
    accepted_stack_classes: tuple[str, ...] = ("stack_face", "counting_face")
    allow_experimental_tray_box_baseline: bool = False

    mock_stack_count: int = 1
    debug_overlays: bool = False
    debug_output_dir: str = "debug-output"
    extra: dict[str, str] = field(default_factory=dict)

    @property
    def roboflow_model_reference(self) -> str:
        if self.roboflow_model_id and "/" in self.roboflow_model_id:
            return self.roboflow_model_id
        project = self.roboflow_model_id or self.roboflow_project
        if not project or not self.roboflow_model_version:
            return ""
        return f"{project}/{self.roboflow_model_version}"

    @classmethod
    def from_env(cls) -> Settings:
        return cls(
            app_env=os.getenv("APP_ENV", "development"),
            log_level=os.getenv("LOG_LEVEL", "INFO"),
            app_version=os.getenv("APP_VERSION", "0.1.0"),
            inference_provider=os.getenv("INFERENCE_PROVIDER", "mock").strip().lower(),
            eggs_per_tray=_int("EGGS_PER_TRAY", 30),
            max_upload_bytes=_int("MAX_UPLOAD_BYTES", 20 * 1024 * 1024),
            allowed_origins=_csv("ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:8080"),
            min_image_width=_int("MIN_IMAGE_WIDTH", 480),
            min_image_height=_int("MIN_IMAGE_HEIGHT", 480),
            min_blur_score=_float("MIN_BLUR_SCORE", 35.0),
            max_dark_fraction=_float("MAX_DARK_FRACTION", 0.88),
            max_bright_fraction=_float("MAX_BRIGHT_FRACTION", 0.88),
            min_view_quality=_float("MIN_VIEW_QUALITY", 0.58),
            min_segmentation_confidence=_float("MIN_SEGMENTATION_CONFIDENCE", 0.35),
            min_pitch_px=_int("MIN_PITCH_PX", 8),
            max_pitch_px=_int("MAX_PITCH_PX", 90),
            peak_prominence_factor=_float("PEAK_PROMINENCE_FACTOR", 0.55),
            max_inferred_layers=_int("MAX_INFERRED_LAYERS", 2),
            association_threshold=_float("ASSOCIATION_THRESHOLD", 0.62),
            side_margin_fraction=_float("SIDE_MARGIN_FRACTION", 0.10),
            rectified_width=_int("RECTIFIED_WIDTH", 512),
            rectified_height=_int("RECTIFIED_HEIGHT", 768),
            roboflow_api_key=os.getenv("ROBOFLOW_API_KEY", ""),
            roboflow_workspace=os.getenv("ROBOFLOW_WORKSPACE", ""),
            roboflow_project=os.getenv("ROBOFLOW_PROJECT", ""),
            roboflow_model_id=os.getenv("ROBOFLOW_MODEL_ID", ""),
            roboflow_model_version=os.getenv("ROBOFLOW_VERSION", os.getenv("ROBOFLOW_MODEL_VERSION", "")),
            roboflow_inference_url=os.getenv(
                "ROBOFLOW_INFERENCE_URL", "https://serverless.roboflow.com"
            ).rstrip("/"),
            roboflow_timeout_seconds=_float("ROBOFLOW_TIMEOUT_SECONDS", 20.0),
            roboflow_confidence=_int("ROBOFLOW_CONFIDENCE", 35),
            roboflow_max_retries=_int("ROBOFLOW_MAX_RETRIES", 2),
            accepted_stack_classes=_csv("ROBOFLOW_STACK_CLASSES", "stack_face,counting_face"),
            allow_experimental_tray_box_baseline=_bool("ALLOW_EXPERIMENTAL_TRAY_BOX_BASELINE"),
            mock_stack_count=_int("MOCK_STACK_COUNT", 1),
            debug_overlays=_bool("DEBUG_OVERLAYS"),
            debug_output_dir=os.getenv("DEBUG_OUTPUT_DIR", "debug-output"),
        )

    def validate_runtime(self) -> None:
        if self.app_env == "production" and "*" in self.allowed_origins:
            raise ValueError("Wildcard CORS is not allowed in production")
        if self.inference_provider == "roboflow" and (
            not self.roboflow_api_key or not self.roboflow_model_reference
        ):
            raise ValueError(
                "INFERENCE_PROVIDER=roboflow requires ROBOFLOW_API_KEY "
                "and a traceable project/version model reference"
            )
