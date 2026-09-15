"""Local research candidate. No truth files, fixed stack count, or inventory certification."""

from __future__ import annotations

import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks

from app.vision.hybrid import HeightCalibration, HeightSample
from app.vision.layer_signal import horizontal_structure_signal
from app.vision.rectification import rectify_face


def calibrated_height_evidence(calibration: dict, measurement: dict) -> dict:
    """Reuse the measured interval model; version and geometry provenance required."""
    if (
        not calibration.get("version")
        or measurement.get("calibration_id") != calibration.get("profile_id")
        or measurement.get("calibration_version") != calibration["version"]
        or measurement.get("geometry_verified") is not True
        or not measurement.get("camera_calibration_id")
        or not measurement.get("survey_reference_id")
    ):
        raise ValueError("Matching versioned calibration and verified pose/depth measurement required")
    model = HeightCalibration(
        calibration["profile_id"], tuple(HeightSample(**s) for s in calibration["samples"])
    )
    candidates = model.candidates(measurement["height_cm"], measurement["uncertainty_cm"])
    return {
        "profile_id": model.profile_id,
        "version": calibration["version"],
        "count_candidates": list(candidates),
        "height_count": candidates[0] if len(candidates) == 1 else None,
        "height_cm": measurement["height_cm"],
        "uncertainty_cm": measurement["uncertainty_cm"],
        "occupancy": "unknown",
    }


def localize_stacks(detections: list[dict], image_shape: tuple) -> list[dict]:
    """Cluster original-coordinate xyxy tray boxes into provisional vertical faces.

    Complete-link X/width compatibility avoids transitive bridges across stacks.
    Bounds enclose observations, not a claim of complete top/bottom visibility.
    """
    h, w = image_shape[:2]
    groups: list[list[dict]] = []
    for detection in detections:
        box = np.asarray(detection["bbox"], dtype=float)
        confidence = detection.get("confidence", 0.0)
        if (
            box.shape != (4,)
            or not np.isfinite(box).all()
            or not np.isfinite(confidence)
            or not 0 <= confidence <= 1
            or not (0 <= box[0] < box[2] <= w and 0 <= box[1] < box[3] <= h)
        ):
            raise ValueError("Detection requires finite in-frame xyxy box and confidence")
    for detection in sorted(detections, key=lambda d: (d["bbox"][0] + d["bbox"][2]) / 2):
        box = np.asarray(detection["bbox"], dtype=float)
        x1, _, x2, _ = box
        width = x2 - x1
        matches = []
        for group in groups:
            compatible = []
            for other in group:
                a, _, b, _ = other["bbox"]
                compatible.append(
                    min(width, b - a) / max(width, b - a) >= 0.6
                    and abs((x1 + x2 - a - b) / 2) <= 0.3 * min(width, b - a)
                )
            if all(compatible):
                matches.append(group)
        if len(matches) == 1:
            matches[0].append(detection)
        else:
            groups.append([detection])
    result = []
    for group in groups:
        if len(group) < 3:
            continue
        boxes = np.asarray([d["bbox"] for d in group], dtype=float)
        ys = boxes[:, [1, 3]].mean(axis=1)
        if np.ptp(ys) < np.median(boxes[:, 3] - boxes[:, 1]) * 2:
            continue
        top, bottom = float(boxes[:, 1].min()), float(boxes[:, 3].max())
        # Sloped face sides use robust residual envelopes, not one tray rectangle.
        boundaries = []
        for edge in (0, 2):
            slope, intercept = np.polyfit(ys, boxes[:, edge], 1)
            residual = boxes[:, edge] - (slope * ys + intercept)
            offset = np.percentile(residual, 10 if edge == 0 else 90)
            boundaries.append(np.clip(slope * np.array([top, bottom]) + intercept + offset, 0, w - 1))
        left, right = boundaries
        quad = [
            [float(left[0]), top],
            [float(right[0]), top],
            [float(right[1]), bottom],
            [float(left[1]), bottom],
        ]
        if min(right - left) <= 2:
            continue
        result.append(
            {
                "stack_id": f"candidate_{len(result) + 1}",
                "polygon": quad,
                "centreline": [
                    [float((left[0] + right[0]) / 2), top],
                    [float((left[1] + right[1]) / 2), bottom],
                ],
                "visible_detections": group,
                "rf_count": len(group),
                "stack_confidence": float(np.median([d["confidence"] for d in group])),
                "confidence_meaning": "detector support, not calibrated localization accuracy",
                "top_visible": None,
                "bottom_visible": None,
                "clipped": bool(top <= 1 or bottom >= h - 1 or min(left) <= 1 or max(right) >= w - 2),
            }
        )
    return result


def rectify_native(image: np.ndarray, polygon: list) -> tuple:
    points = np.asarray(polygon, dtype=float)
    if points.shape != (4, 2) or not np.isfinite(points).all():
        raise ValueError("A finite complete stack quadrilateral is required")
    h, w = image.shape[:2]
    if (points < 0).any() or (points[:, 0] >= w).any() or (points[:, 1] >= h).any():
        raise ValueError("Stack quadrilateral extends outside the image")
    widths = [np.linalg.norm(points[1] - points[0]), np.linalg.norm(points[2] - points[3])]
    heights = [np.linalg.norm(points[3] - points[0]), np.linalg.norm(points[2] - points[1])]
    size = (max(8, int(np.ceil(max(widths)))), max(8, int(np.ceil(max(heights)))))
    face = rectify_face(image, polygon, size)
    return face, {
        "native_size": list(size),
        "side_height_ratio": max(heights) / min(heights),
        "top_bottom_width_ratio": max(widths) / min(widths),
        "metric_scale_available": False,
        "completeness_verified": False,
    }


def _correlation(signal: np.ndarray) -> np.ndarray:
    centered = signal - np.mean(signal)
    result = np.correlate(centered, centered, "full")[len(signal) - 1 :]
    return result / result[0] if result[0] > 1e-9 else np.zeros_like(result)


def analyze_rims(
    image: np.ndarray, *, min_pitch: int = 6, max_pitch: int = 90, rf_centres: tuple[float, ...] = ()
) -> dict:
    """Rank bands rather than count both edges; preserve harmonic alternatives.

    Scores are diagnostic signal support, NEVER probabilities or calibrated fusion.
    White/dark bands are competing physical-feature interpretations, not additive.
    """
    if image.ndim not in (2, 3) or min(image.shape[:2]) < 8:
        raise ValueError("A nonempty rectified stack face is required")
    if min_pitch < 3 or max_pitch <= min_pitch:
        raise ValueError("Invalid pitch bounds")
    if any(not np.isfinite(y) or not 0 <= y < image.shape[0] for y in rf_centres):
        raise ValueError("RF centres must be in rectified image coordinates")
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    margin = max(1, image.shape[1] // 10)
    profile = gaussian_filter1d(gray[:, margin:-margin].mean(axis=1), 1.0)
    signed = gaussian_filter1d(cv2.Sobel(gray, cv2.CV_64F, 0, 1)[:, margin:-margin].mean(1), 1.0)
    absolute = horizontal_structure_signal(image, 0.1)
    ac, edge_ac = _correlation(profile), _correlation(absolute)
    upper = min(max_pitch, len(profile) // 3)
    seeds = set()
    for correlation in (ac, edge_ac):
        indices, _ = find_peaks(correlation)
        seeds.update(int(p) for p in indices if min_pitch <= p <= upper and correlation[p] > 0.08)
    prominence = max(2.0, float(np.std(profile)) * 0.4)
    bands = {}
    for polarity, values in [("bright", profile), ("dark", -profile)]:
        centres, properties = find_peaks(values, distance=3, prominence=prominence)
        bands[polarity] = (centres, properties["prominences"])
        if len(centres) > 2:
            seeds.add(round(float(np.median(np.diff(centres)))))
    pitches = sorted(
        {
            round(p * factor)
            for p in seeds
            for factor in (0.5, 1, 2)
            if min_pitch <= round(p * factor) <= upper
        }
    )
    candidates = []
    for pitch in pitches:
        for polarity, values in [("bright", profile), ("dark", -profile)]:
            raw, _ = bands[polarity]
            centres, props = find_peaks(values, distance=max(3, round(pitch * 0.55)), prominence=prominence)
            if len(centres) < 3:
                continue
            intervals = []
            # Each extremum has one rise/fall pair; no summing opposite polarities.
            direction = 1 if polarity == "bright" else -1
            for centre in centres:
                a, b = (
                    max(0, centre - round(pitch * 0.45)),
                    min(len(profile) - 1, centre + round(pitch * 0.45)),
                )
                left = a + int(np.argmax(direction * signed[a : centre + 1]))
                right = centre + int(np.argmax(-direction * signed[centre : b + 1]))
                intervals.append([int(left), int(right)])
            gaps = np.diff(centres)
            regularity = max(0.0, 1.0 - float(np.mean(np.abs(gaps / pitch - 1))))
            coverage = min(1.0, len(centres) * pitch / len(profile))
            explained = len(centres) / max(1, len(raw))
            paired = float(np.mean([a < c < b for (a, b), c in zip(intervals, centres, strict=True)]))
            # Product rejects half-pitch missing bands and double-pitch discarded bands.
            support = coverage * explained * regularity * paired
            rf_alignment = None
            if rf_centres:
                distances = np.abs(np.asarray(rf_centres)[:, None] - centres[None, :]).min(axis=1)
                rf_alignment = float(np.mean(distances <= pitch * 0.25))
            candidates.append(
                {
                    "pitch_px": pitch,
                    "feature": polarity,
                    "count": len(centres),
                    "centres": centres.tolist(),
                    "intervals": intervals,
                    "support": support,
                    "coverage": coverage,
                    "explained_bands": explained,
                    "regularity": regularity,
                    "edge_pair_fraction": paired,
                    "autocorrelation": float(ac[pitch]),
                    "edge_autocorrelation": float(edge_ac[pitch]),
                    "rf_alignment": rf_alignment,
                    "prominence_mean": float(np.mean(props["prominences"])),
                }
            )
    candidates.sort(key=lambda c: (-c["support"], -c["autocorrelation"], c["pitch_px"]))
    best = candidates[0] if candidates else None
    for index, candidate in enumerate(candidates):
        candidate["selection"] = "exploratory_best" if index == 0 else "retained_alternative"
    return {
        "best": best,
        "hypotheses": candidates,
        "physical_count": None,
        "eligible_count": None,
        "reason": "Band semantics, endpoint completeness and occupancy are unverified",
        "profile": profile.tolist(),
        "signed_sobel": signed.tolist(),
        "absolute_signal": absolute.tolist(),
        "autocorrelation": ac.tolist(),
        "edge_autocorrelation": edge_ac.tolist(),
        "local_spacings": {k: np.diff(v[0]).tolist() for k, v in bands.items()},
        "occupancy": "unknown",
        "height_count": None,
    }
