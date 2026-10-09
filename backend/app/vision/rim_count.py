"""Independent rim count per stack column from the image itself.

The production span count (``layer_span.count_layers_by_span``) divides the
distance between the first and last detector box by one median spacing. It
fails by +/-1 when the detector double-boxes or skips a layer, and when
perspective shrinks the spacing from top to bottom. This module gives a second
opinion that does not use the detector boxes for counting: it only uses the
column's x-extent, its vertical extent and the detector pitch as a prior.

Method per column:
- take the column strip widened by 10 %, build a horizontal-edge signal
  (Sobel-Y of one channel, one polarity, averaged across the central 60 % of
  the strip width, smoothed with a sigma proportional to the pitch, robustly
  normalised);
- search between ``y_first - w*pitch`` and ``y_last + w*pitch``;
- keep peaks whose prominence is at least a fraction of the strip's strong
  peaks, then accept them top to bottom with a minimum distance that starts at
  ``0.6 * pitch_px`` and follows the running median of the last three
  accepted gaps, so a slowly varying (perspective) pitch is tracked instead of
  assumed constant;
- a gap of about two local pitches with no peak is reported as an inferred rim.

Everything returned is diagnostic evidence: ``agrees_with_span`` flags columns
where the two independent counts differ, nothing here verifies a count.
Tuned on the 13 straight-on WhatsApp copies of 2026-10-07 (see
``reports/rim-count-20261009/README.md``); not validated on held-out data.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks

_REQUIRED = ("x_min", "x_max", "y_first", "y_last", "pitch_px")


@dataclass(frozen=True)
class RimParams:
    """Tunable thresholds; defaults are the 2026-10-09 tuning (same-set, not validated)."""

    widen_fraction: float = 0.10  # strip widened by this fraction of the column width in total
    core_fraction: float = 0.60  # central fraction of the strip width that is averaged
    window_fraction: float = 0.75  # search margin beyond the first/last box centre, in pitches
    smooth_fraction: float = 0.08  # gaussian sigma as a fraction of the pitch (at least 1 px)
    min_distance_fraction: float = 0.60  # minimum accepted peak distance, in local pitches
    prominence_fraction: float = 0.30  # minimum prominence relative to the strip's strong peaks
    channel: str = "green"  # "green" or "gray"
    polarity: str = "dark_below"  # "dark_below", "bright_below" or "absolute"
    aggregate: str = "mean"  # how the edge map is reduced across the core width: mean, median, support
    infer_missing: bool = True  # count a gap of ~2 local pitches as one missed rim
    pitch_clamp: tuple[float, float] = (0.5, 1.6)  # local pitch bounds relative to pitch_px


DEFAULT_PARAMS = RimParams()


def _empty(column: dict, index: int, note: str) -> dict:
    return {
        "column": column.get("column", index) if isinstance(column, dict) else index,
        "rim_count": None,
        "peaks_y": [],
        "local_pitches": [],
        "top_y": None,
        "base_y": None,
        "confidence": 0.0,
        "agrees_with_span": None,
        "perspective_gradient": None,
        "inferred_rims": 0,
        "note": note,
    }


def _finite(value) -> bool:
    try:
        return bool(np.isfinite(float(value)))
    except (TypeError, ValueError):
        return False


def edge_signal(strip_bgr: np.ndarray, params: RimParams, pitch: float) -> np.ndarray | None:
    """One value per image row: horizontal-edge strength of the chosen polarity, robustly scaled."""
    if strip_bgr.ndim != 3:
        plane = strip_bgr
    elif params.channel == "green":
        plane = strip_bgr[:, :, 1]
    else:
        plane = cv2.cvtColor(strip_bgr, cv2.COLOR_BGR2GRAY)
    height, width = plane.shape[:2]
    if height < 3 or width < 3:
        return None
    blurred = cv2.GaussianBlur(plane.astype(np.float32), (3, 3), 0)
    sobel = cv2.Sobel(blurred, cv2.CV_32F, dx=0, dy=1, ksize=3)
    margin = int(round(width * (1.0 - params.core_fraction) / 2.0))
    core = sobel[:, margin : width - margin] if width - 2 * margin >= 3 else sobel
    core = core.astype(np.float64)
    if params.polarity == "dark_below":
        core = -core
    elif params.polarity == "absolute":
        core = np.abs(core)
    if params.aggregate == "median":
        rows = np.median(core, axis=1)
    elif params.aggregate == "support":
        tau = float(np.percentile(np.abs(core), 75))
        rows = (core > tau).mean(axis=1) if tau > 0 else core.mean(axis=1)
    else:
        rows = core.mean(axis=1)
    sigma = max(1.0, params.smooth_fraction * pitch)
    rows = gaussian_filter1d(rows, sigma=sigma)
    median = float(np.median(rows))
    scale = max(1.4826 * float(np.median(np.abs(rows - median))), 1e-6)
    return (rows - median) / scale


def _accept_peaks(
    ys: np.ndarray, prominences: np.ndarray, pitch: float, params: RimParams
) -> tuple[list[tuple], list[int]]:
    """Greedy top-to-bottom acceptance with a minimum distance that follows the local pitch.

    Each accepted gap is divided by its rounded multiple of the current local pitch before it
    enters the running median, so one missed rim cannot drag the tracker onto double pitch.
    Returns the accepted (y, prominence) pairs and the multiple of each accepted gap.
    """
    low, high = params.pitch_clamp[0] * pitch, params.pitch_clamp[1] * pitch
    accepted: list[tuple[int, float]] = []
    units: list[float] = []
    multiples: list[int] = []

    def local_pitch() -> float:
        if not units:
            return pitch
        return float(np.clip(np.median(units[-3:]), low, high))

    def multiple_of(gap: float, local: float) -> int:
        return max(1, int(round(gap / local)))

    for y, prominence in zip(ys.tolist(), prominences.tolist(), strict=True):
        if not accepted:
            accepted.append((y, prominence))
            continue
        local = local_pitch()
        min_distance = params.min_distance_fraction * local
        gap = y - accepted[-1][0]
        if gap >= min_distance:
            accepted.append((y, prominence))
            m = multiple_of(gap, local)
            multiples.append(m)
            units.append(gap / m)
        elif prominence > accepted[-1][1] and (len(accepted) < 2 or y - accepted[-2][0] >= min_distance):
            accepted[-1] = (y, prominence)
            if units:
                units.pop()
                multiples.pop()
                previous = local_pitch()
                gap = y - accepted[-2][0]
                m = multiple_of(gap, previous)
                multiples.append(m)
                units.append(gap / m)
    return accepted, multiples


def _neighbour_pitch(unit_gaps: np.ndarray, index: int) -> float:
    """Median of the neighbouring single-pitch gaps (up to three on each side), excluding this one."""
    neighbours = [g for k, g in enumerate(unit_gaps) if k != index and abs(k - index) <= 3]
    return float(np.median(neighbours)) if neighbours else float(unit_gaps[index])


def _count_column(image: np.ndarray, column: dict, index: int, params: RimParams) -> dict:
    if not isinstance(column, dict) or any(not _finite(column.get(k)) for k in _REQUIRED):
        return _empty(column, index, "column needs finite x_min, x_max, y_first, y_last, pitch_px")
    height, width = image.shape[:2]
    pitch = float(column["pitch_px"])
    x_min, x_max = float(column["x_min"]), float(column["x_max"])
    y_first, y_last = float(column["y_first"]), float(column["y_last"])
    if pitch <= 1 or x_max <= x_min or y_last < y_first:
        return _empty(column, index, "degenerate column geometry")
    pad = (x_max - x_min) * params.widen_fraction / 2.0
    xa, xb = int(np.floor(max(0.0, x_min - pad))), int(np.ceil(min(float(width), x_max + pad)))
    if xb - xa < 3:
        return _empty(column, index, "column strip is empty or narrower than 3 px")
    margin = params.window_fraction * pitch
    ya, yb = int(np.floor(max(0.0, y_first - margin))), int(np.ceil(min(float(height), y_last + margin)))
    if yb - ya < 3:
        return _empty(column, index, "search window is empty")
    signal = edge_signal(image[:, xa:xb], params, pitch)
    if signal is None:
        return _empty(column, index, "strip too small for an edge signal")
    window = signal[ya:yb]
    peaks, props = find_peaks(window, distance=max(1, int(round(0.3 * pitch))), prominence=0.0)
    if peaks.size == 0:
        return _empty(column, index, "no edge peaks in the search window")
    prominences = np.asarray(props["prominences"], dtype=float)
    expected = max(3, int(round((yb - ya) / pitch)))
    strong = float(np.median(np.sort(prominences)[::-1][:expected]))
    threshold = params.prominence_fraction * strong
    keep = prominences >= threshold
    if not keep.any():
        return _empty(column, index, "all edge peaks fall below the prominence threshold")
    accepted, multiples = _accept_peaks(peaks[keep], prominences[keep], pitch, params)
    ys = np.array([ya + y for y, _ in accepted], dtype=float)
    proms = np.array([p for _, p in accepted], dtype=float)
    gaps = np.diff(ys)
    inferred = 0
    residuals = []
    for k, (gap, m) in enumerate(zip(gaps, multiples, strict=True)):
        local = _neighbour_pitch(gaps / np.asarray(multiples, dtype=float), k)
        ratio = gap / local if local > 0 else 1.0
        if params.infer_missing and m >= 2 and abs(ratio - m) <= 0.3 * m:
            inferred += m - 1
            residuals.append(abs(ratio - m) / m)
        else:
            residuals.append(abs(ratio - 1.0))
    rim_count = int(len(ys) + inferred)
    regularity = float(np.clip(1.0 - np.mean(residuals) / 0.35, 0.0, 1.0)) if residuals else 0.0
    prominence_term = float(np.clip(np.median(proms) / max(strong, 1e-6), 0.0, 1.0)) if strong > 0 else 0.0
    confidence = float(np.clip(0.6 * regularity + 0.4 * prominence_term - 0.15 * inferred, 0.0, 1.0))
    if len(ys) < 2:
        confidence = 0.0
    gradient = None
    if len(gaps) >= 3:
        third = max(1, len(gaps) // 3)
        bottom = float(np.median(gaps[-third:]))
        gradient = round(float(np.median(gaps[:third])) / bottom, 3) if bottom > 0 else None
    span = column.get("span_count")
    agrees = bool(rim_count == int(span)) if _finite(span) else None
    notes = ["edge-peak count; diagnostic only, not a verified layer count"]
    if inferred:
        notes.append(f"{inferred} rim(s) inferred from double-pitch gaps")
    if ya == 0 or yb == height:
        notes.append("search window touches the image border")
    return {
        "column": column.get("column", index),
        "rim_count": rim_count,
        "peaks_y": [round(float(y), 1) for y in ys],
        "local_pitches": [round(float(g), 2) for g in gaps],
        "top_y": round(float(ys[0]), 1),
        "base_y": round(float(ys[-1]), 1),
        "confidence": round(confidence, 3),
        "agrees_with_span": agrees,
        "perspective_gradient": gradient,
        "inferred_rims": inferred,
        "note": "; ".join(notes),
    }


def rim_count(image_bgr: np.ndarray, columns: list[dict], params: RimParams | None = None) -> list[dict]:
    """Count rim edges per column. Never raises on degenerate input: rim_count is None with a note."""
    params = params or DEFAULT_PARAMS
    columns = list(columns or [])
    image_ok = isinstance(image_bgr, np.ndarray) and image_bgr.ndim in (2, 3) and image_bgr.size > 0
    if not image_ok:
        return [_empty(column, index, "image is empty or not a 2-D/3-D array") for index, column in
                enumerate(columns, 1)]
    results = []
    for index, column in enumerate(columns, 1):
        try:
            results.append(_count_column(image_bgr, column, index, params))
        except Exception as error:  # noqa: BLE001 - diagnostic path must never raise
            results.append(_empty(column, index, f"rim count failed: {type(error).__name__}"))
    return results
