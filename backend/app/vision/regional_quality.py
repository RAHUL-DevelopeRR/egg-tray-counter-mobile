"""Experimental, region-specific capture guidance; no inventory/occupancy inference."""

from dataclasses import asdict, dataclass

import cv2
import numpy as np

from app.vision.rectification import rectify_face


@dataclass(frozen=True)
class RegionalQualityProfile:
    version: str = "regional_quality_pilot_v1"
    dark_mean: float = 45.0
    dark_fraction: float = 0.55
    weak_rim_contrast: float = 12.0
    min_laplacian_variance: float = 20.0
    min_local_contrast: float = 18.0


PROFILE = RegionalQualityProfile()


def recommendation(code, view, stack, region, cause, action, source="measured_image"):
    return dict(
        code=code, view=view, stack=stack, region=region, cause=cause, action=action, evidence_source=source
    )


def regional_stack_quality(image, stack, view, profile=PROFILE):
    """Analyze thirds of a proposed face, not thirds of the whole camera frame.

    Thresholds are pilot heuristics. Weak sharpness cannot distinguish motion
    from defocus/texture; obstruction cannot be established by dark pixels alone.
    """
    polygon = np.asarray(stack["polygon"], np.float32)
    width = max(np.linalg.norm(polygon[1] - polygon[0]), np.linalg.norm(polygon[2] - polygon[3]))
    height = max(np.linalg.norm(polygon[3] - polygon[0]), np.linalg.norm(polygon[2] - polygon[1]))
    scale = min(1.0, 768 / max(height, 1), 384 / max(width, 1))
    face = rectify_face(image, polygon, (max(12, round(width * scale)), max(24, round(height * scale)))).image
    gray = cv2.cvtColor(face, cv2.COLOR_BGR2GRAY)
    # Avoid interpolated crop borders generating false sharpness evidence.
    gray = gray[:, 2:-2]
    diagnostics, instructions = {}, []
    stack_id = stack["stack_id"]
    for region, patch in zip(("top", "middle", "bottom"), np.array_split(gray, 3), strict=True):
        mean = float(patch.mean())
        dark = float(np.mean(patch <= 30))
        contrast = float(np.percentile(patch, 95) - np.percentile(patch, 5))
        sharpness = float(cv2.Laplacian(patch, cv2.CV_32F).var())
        rim = float(np.percentile(np.abs(cv2.Sobel(patch, cv2.CV_32F, 0, 1)), 90))
        low_light = mean < profile.dark_mean and (
            dark > profile.dark_fraction or rim < profile.weak_rim_contrast
        )
        weak_sharpness = not low_light and sharpness < profile.min_laplacian_variance
        diagnostics[region] = dict(
            exposure_mean=mean,
            dark_fraction=dark,
            highlight_clipping_fraction=float(np.mean(patch >= 245)),
            local_contrast=contrast,
            laplacian_variance=sharpness,
            rim_contrast=rim,
            low_light=low_light,
            weak_sharpness=weak_sharpness,
            occlusion=None,
        )
        if low_light:
            instructions.append(
                recommendation(
                    "BOTTOM_DARK" if region == "bottom" else "REGION_DARK",
                    view,
                    stack_id,
                    region,
                    "low_light",
                    f"Illuminate the {region} of {stack_id} and retake {view.upper()}.",
                )
            )
        elif weak_sharpness:
            instructions.append(
                recommendation(
                    "MOTION_BLUR",
                    view,
                    stack_id,
                    region,
                    "insufficient_sharpness_motion_not_confirmed",
                    f"Hold still, refocus on the {region} of {stack_id}, and retake {view.upper()}.",
                )
            )
        elif contrast < profile.min_local_contrast or rim < profile.weak_rim_contrast:
            instructions.append(
                recommendation(
                    "RIM_CONTRAST_LOW",
                    view,
                    stack_id,
                    region,
                    "weak_layer_structure",
                    f"Capture a clearer close-up of the {region} tray rims in {view.upper()}.",
                )
            )
    for region, code, contact in (
        ("top", "TOP_CROPPED", min(polygon[:2, 1]) <= 2),
        ("bottom", "BASE_CROPPED", max(polygon[2:, 1]) >= image.shape[0] - 3),
    ):
        if contact:
            instructions.append(
                recommendation(
                    code,
                    view,
                    stack_id,
                    region,
                    "possible_crop_at_image_boundary",
                    f"Move back to include the complete {region} of {stack_id} in {view.upper()}.",
                )
            )
    return dict(
        profile=asdict(profile),
        thresholds_validated=False,
        roi_completeness_verified=False,
        analysis_size=[face.shape[1], face.shape[0]],
        regions=diagnostics,
        recommendations=instructions,
    )
