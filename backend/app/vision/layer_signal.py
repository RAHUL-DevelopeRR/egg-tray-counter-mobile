from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks

from app.config import Settings


@dataclass(frozen=True)
class LayerCountResult:
    tray_count: int | None
    detected_layers: int
    inferred_internal_layers: int
    pitch_px: float | None
    periodicity_error: float
    peak_prominence_mean: float
    quality: float
    peak_positions: tuple[int, ...]
    signal: np.ndarray
    reason: str | None = None


def horizontal_structure_signal(rectified: np.ndarray, side_margin_fraction: float) -> np.ndarray:
    gray = cv2.cvtColor(rectified, cv2.COLOR_BGR2GRAY) if rectified.ndim == 3 else rectified
    blurred = cv2.GaussianBlur(gray, (3, 3), 0)
    sobel_y = cv2.Sobel(blurred, cv2.CV_32F, dx=0, dy=1, ksize=3)
    edges = np.abs(sobel_y)
    width = edges.shape[1]
    margin = min(width // 3, max(0, round(width * side_margin_fraction)))
    core = edges[:, margin : width - margin] if width - 2 * margin >= 8 else edges
    signal = np.mean(core, axis=1).astype(np.float64)
    signal = gaussian_filter1d(signal, sigma=1.2)
    median = float(np.median(signal))
    mad = float(np.median(np.abs(signal - median)))
    scale = max(1.4826 * mad, 1e-6)
    return (signal - median) / scale


def estimate_pitch(signal: np.ndarray, min_pitch: int, max_pitch: int) -> tuple[float | None, float]:
    centered = signal - np.mean(signal)
    correlation = np.correlate(centered, centered, mode="full")[len(centered) - 1 :]
    if correlation.size == 0 or correlation[0] <= 1e-9:
        return None, 0.0
    correlation = correlation / correlation[0]
    upper = min(max_pitch, len(correlation) - 1)
    if upper <= min_pitch:
        return None, 0.0
    section = correlation[min_pitch : upper + 1]
    peaks, _ = find_peaks(section)
    if peaks.size:
        peak_strengths = section[peaks]
        strong_threshold = max(0.08, float(np.max(peak_strengths)) * 0.72)
        strong_peaks = peaks[peak_strengths >= strong_threshold]
        local_index = int(strong_peaks[0]) if strong_peaks.size else int(peaks[np.argmax(peak_strengths)])
    else:
        local_index = int(np.argmax(section))
    pitch = min_pitch + local_index
    strength = float(section[local_index])
    if strength < 0.08:
        return None, strength
    return float(pitch), strength


def count_layers(rectified: np.ndarray, settings: Settings) -> LayerCountResult:
    signal = horizontal_structure_signal(rectified, settings.side_margin_fraction)
    pitch, autocorrelation_strength = estimate_pitch(signal, settings.min_pitch_px, settings.max_pitch_px)
    if pitch is None:
        return LayerCountResult(
            tray_count=None,
            detected_layers=0,
            inferred_internal_layers=0,
            pitch_px=None,
            periodicity_error=1.0,
            peak_prominence_mean=0.0,
            quality=0.0,
            peak_positions=(),
            signal=signal,
            reason="No stable repeating tray pitch was found",
        )
    prominence = max(0.75, settings.peak_prominence_factor * float(np.percentile(signal, 80)))
    peaks, properties = find_peaks(
        signal,
        distance=max(2, round(pitch * 0.58)),
        prominence=prominence,
    )
    if len(peaks) < 2:
        return LayerCountResult(
            tray_count=None,
            detected_layers=len(peaks),
            inferred_internal_layers=0,
            pitch_px=pitch,
            periodicity_error=1.0,
            peak_prominence_mean=float(np.mean(properties.get("prominences", [0.0]))),
            quality=0.0,
            peak_positions=tuple(int(value) for value in peaks),
            signal=signal,
            reason="Too few tray rails were visible",
        )

    gaps = np.diff(peaks).astype(np.float64)
    ratios = gaps / pitch
    nearest = np.maximum(1, np.rint(ratios).astype(int))
    residuals = np.abs(ratios - nearest)
    supported = residuals <= 0.28
    inferred = int(
        sum(max(0, int(multiplier) - 1) for multiplier, ok in zip(nearest, supported, strict=True) if ok)
    )
    periodicity_error = float(np.mean(residuals))
    prominence_mean = float(np.mean(properties.get("prominences", [0.0])))
    inference_penalty = min(1.0, inferred / max(settings.max_inferred_layers + 1, 1))
    quality = float(
        np.clip(
            0.40 * max(0.0, autocorrelation_strength)
            + 0.35 * max(0.0, 1.0 - periodicity_error / 0.35)
            + 0.25 * min(1.0, prominence_mean / 5.0)
            - 0.25 * inference_penalty,
            0.0,
            1.0,
        )
    )
    count = len(peaks) + inferred
    reason = None
    if inferred > settings.max_inferred_layers:
        reason = f"Too many internal tray rails had to be inferred ({inferred})"
    return LayerCountResult(
        tray_count=count if reason is None else None,
        detected_layers=len(peaks),
        inferred_internal_layers=inferred,
        pitch_px=pitch,
        periodicity_error=periodicity_error,
        peak_prominence_mean=prominence_mean,
        quality=quality,
        peak_positions=tuple(int(value) for value in peaks),
        signal=signal,
        reason=reason,
    )
