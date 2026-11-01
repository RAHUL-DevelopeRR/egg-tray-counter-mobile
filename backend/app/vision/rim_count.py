"""Rim count per stack column from the image alone: a second reading that does not count detector boxes.

The walk counter (``layer_span.walk_layers``) counts detector boxes, so it inherits every detector miss: a box over
two stacks, a tall box over two trays, an end tray with no box at all (2026-11-01 miss taxonomy). This module counts
the stack's periodic horizontal edges instead, so that its per-stack count can act as a second reading of the same
stack (plan Phase E).

What it takes from the detector, and nothing more: the column's x-range (``x_centre`` and ``box_width_px``, the median
box, when the caller sends them, otherwise ``x_min``/``x_max``). That picks the image strip and gives the scale (tray
boxes are 3-6 times wider than tall, so the layer pitch is searched as a fraction of the strip width). The detector's
vertical positions (``y_first``, ``y_last``) and its pitch are never used for counting; when sent they only feed the
comparison fields (``run_extra_layers``, ``run_missing_layers``, ``agrees_with_walk``). Limitation: it still depends on
the detector for WHERE each stack is (the x-range), so it is not independent of stack localisation.

Method per column, over the whole height of the strip:
- edge signal: Sobel-Y of the grey image, one polarity (bright above, dark below), averaged across the strip core;
- anchor: the band with the strongest local periodicity (autocorrelation at the strip's pitch times edge energy);
- pitch: the band's own autocorrelation. Cross-stacked trays alternate orientation, so the signal repeats every two
  layers and the strongest peak can be the pair (2p); while the autocorrelation at half the lag is also a period the
  pitch is halved. The p/2, p and 2p alternatives are scored, and a reading whose half-pitch alternative is nearly as
  strong as the chosen pitch is reported unreadable rather than guessed;
- rims: from the anchor, step up and down one local pitch at a time, taking the strongest edge near the expected
  position; the local pitch follows the last two gaps, so perspective and the long/short gap alternation are tracked;
- stack top and floor: where the periodic energy ends. Each period is compared with the median period of its own
  parity near the anchor; walking out, the run stops at the first period that does not look like the stack or carries
  too little edge energy (floor, wall, an empty cover tray, another stack); one or two weak periods inside are bridged
  when the two after them are good again;
- count = rims in the run.

A reading is ``readable`` only when its confidence is at least ``min_confidence``, the pitch is not ambiguous and the run
does not reach the frame edge (the stack may continue outside the photo). Unreadable readings carry ``rim_count`` None
and the raw run in ``rim_count_raw``. Nothing here verifies a count; the Worker decides what a reading is worth.

Parameters frozen on 2026-11-01 on development photos (reports/rim-independent-20261101/README.md), before any blind
count existed and before scoring against the hand annotations.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d

from app.vision.layer_signal import estimate_pitch

_TEMPLATE_SAMPLES = 32


@dataclass(frozen=True)
class RimParams:
    """Thresholds, frozen 2026-11-01 on development photos (not validated on held-out data)."""

    core_fraction: float = 0.60  # central fraction of the strip width that is averaged
    pitch_width_bounds: tuple[float, float] = (0.10, 0.45)  # layer pitch search range, as a fraction of strip width
    half_pitch_acf: float = 0.15  # halve the pitch while the autocorrelation at half the lag is at least this
    ambiguity: float = 0.80  # unreadable when the half-pitch alternative scores at least this share of the pitch
    anchor_layers: float = 4.0  # band, in pitches, whose local periodicity places the anchor
    local_layers: float = 6.0  # half-window, in pitches, around the anchor for the local pitch
    smooth_fraction: float = 0.12  # gaussian sigma of the edge signal as a fraction of the pitch (at least 1 px)
    step_window: tuple[float, float] = (0.65, 1.35)  # next rim searched this far from the last, in local pitches
    step_sigma: float = 0.20  # closeness weight of a candidate rim around one local pitch (gaussian sigma, pitches)
    pitch_clamp: tuple[float, float] = (0.75, 1.33)  # local pitch bounds relative to the band pitch
    template_rims: int = 3  # rims on each side of the anchor that define the stack's template periods
    end_similarity: float = 0.50  # a period correlating below this with the stack template is not the stack
    end_energy: float = 0.60  # ... nor is a rim whose edge is below this fraction of the stack's median rim edge
    max_bridge: int = 2  # weak rims inside the stack bridged when the two rims after them are good
    min_rims: int = 3  # fewer rims in the run is no reading
    min_confidence: float = 0.50  # below this the reading is reported unreadable


DEFAULT_PARAMS = RimParams()


def _empty(column: dict, index: int, note: str) -> dict:
    return {
        "column": column.get("column", index) if isinstance(column, dict) else index,
        "rim_count": None,
        "rim_count_raw": None,
        "readable": False,
        "unreadable_reason": note,
        "confidence": 0.0,
        "pitch_px": None,
        "pitch_alternatives": None,
        "top_y": None,
        "base_y": None,
        "run_longer_than_boxes": False,
        "run_extra_layers": 0,
        "run_extends": None,
        "run_shorter_than_boxes": False,
        "run_missing_layers": 0,
        "peaks_y": [],
        "local_pitches": [],
        "agrees_with_span": None,
        "agrees_with_walk": None,
        "perspective_gradient": None,
        "bridged_periods": 0,
        "acf_strength": 0.0,
        "coherence": 0.0,
        "regularity": 0.0,
        "touches_frame": False,
        "note": note,
    }


def _finite(value) -> bool:
    try:
        return bool(np.isfinite(float(value)))
    except (TypeError, ValueError):
        return False


def _x_range(column: dict) -> tuple[float, float]:
    """The median box when the caller sends it (a box over two stacks then cannot widen the strip), else the union."""
    if _finite(column.get("x_centre")) and _finite(column.get("box_width_px")) and float(column["box_width_px"]) > 0:
        half = float(column["box_width_px"]) / 2.0
        return float(column["x_centre"]) - half, float(column["x_centre"]) + half
    return float(column["x_min"]), float(column["x_max"])


def edge_signal(strip_bgr: np.ndarray, params: RimParams, absolute: bool = False) -> np.ndarray | None:
    """One raw value per image row: bright-above / dark-below edge strength (or |edge|) across the strip core."""
    plane = cv2.cvtColor(strip_bgr, cv2.COLOR_BGR2GRAY) if strip_bgr.ndim == 3 else strip_bgr
    height, width = plane.shape[:2]
    if height < 3 or width < 3:
        return None
    blurred = cv2.GaussianBlur(plane.astype(np.float32), (3, 3), 0)
    sobel = cv2.Sobel(blurred, cv2.CV_32F, dx=0, dy=1, ksize=3)
    margin = int(round(width * (1.0 - params.core_fraction) / 2.0))
    core = (sobel[:, margin : width - margin] if width - 2 * margin >= 3 else sobel).astype(np.float64)
    return np.abs(core).mean(axis=1) if absolute else -core.mean(axis=1)


def _autocorrelation(signal: np.ndarray) -> np.ndarray:
    centred = signal - np.mean(signal)
    correlation = np.correlate(centred, centred, mode="full")[len(centred) - 1 :]
    return correlation / correlation[0] if correlation.size and correlation[0] > 1e-9 else np.zeros_like(correlation)


def _acf_at(correlation: np.ndarray, lag: float) -> float:
    """The autocorrelation's best value within 8% of a lag (0 outside the computed range)."""
    a, b = int(np.floor(lag * 0.92)), int(np.ceil(lag * 1.08))
    a, b = max(1, a), min(len(correlation) - 1, b)
    return float(correlation[a : b + 1].max()) if b >= a else 0.0


def band_pitch(signed: np.ndarray, absolute: np.ndarray, lo: int, hi: int,
               params: RimParams) -> tuple[float | None, float, dict]:
    """Layer pitch of one band and its alternatives: (pitch, strength, {half, layer, pair}).

    The signed signal is tried first and the absolute one when it has no periodicity. While the autocorrelation at half
    the lag is also a period the pitch is halved: cross-stacked layers alternate, so the pair (2p) can be the strongest
    peak, and a detector that boxed alternate layers must not be imitated here."""
    smoothed = gaussian_filter1d(signed, 1.0)
    pitch, strength = estimate_pitch(smoothed, lo, hi)
    source = smoothed
    if pitch is None:
        source = gaussian_filter1d(absolute, 1.0)
        pitch, strength = estimate_pitch(source, lo, hi)
    if pitch is None:
        return None, strength, {}
    correlation = _autocorrelation(source)
    while pitch / 2.0 >= max(3.0, lo * 0.5):
        half = _acf_at(correlation, pitch / 2.0)
        if half < params.half_pitch_acf:
            break
        lag = pitch / 2.0
        a, b = max(1, int(np.floor(lag * 0.92))), min(len(correlation) - 1, int(np.ceil(lag * 1.08)))
        pitch = float(a + int(np.argmax(correlation[a : b + 1])))
        strength = half
    alternatives = {"half": round(_acf_at(correlation, pitch / 2.0), 3), "layer": round(_acf_at(correlation, pitch), 3),
                    "pair": round(_acf_at(correlation, 2.0 * pitch), 3)}
    return float(pitch), float(strength), alternatives


def _anchor(signal: np.ndarray, pitch: float, params: RimParams) -> int:
    """Centre of the band with the strongest local periodicity at the pitch (autocorrelation times edge energy)."""
    half = int(round(params.anchor_layers * pitch / 2.0))
    lag = max(1, int(round(pitch)))
    best, centre = -np.inf, len(signal) // 2
    for c in range(half, max(half + 1, len(signal) - half), max(1, lag // 2)):
        segment = signal[c - half : c + half]
        if len(segment) <= lag + 2:
            continue
        energy = float(np.std(segment))
        score = _acf_at(_autocorrelation(segment), pitch) * energy
        if score > best:
            best, centre = score, c
    return centre


def _track(signal: np.ndarray, anchor: int, pitch: float, params: RimParams) -> tuple[list[int], int]:
    """Rims from the anchor to both ends of the signal, one local pitch per step. Returns them top to bottom and the
    anchor's index."""
    low, high = params.pitch_clamp[0] * pitch, params.pitch_clamp[1] * pitch
    chains = []
    for direction in (1, -1):
        chain, gaps = [anchor], []
        while True:
            # Mean of the last two gaps: cross-stacked trays alternate long/short gaps, and a pair spans two pitches.
            local = float(np.clip(np.mean(gaps[-2:]), low, high)) if gaps else pitch
            near = chain[-1] + direction * params.step_window[0] * local
            far = chain[-1] + direction * params.step_window[1] * local
            a, b = int(round(min(near, far))), int(round(max(near, far)))
            if a < 0 or b >= len(signal) or b - a < 1:
                break
            # The strongest edge, weighted by closeness to one local pitch: a stronger sub-layer edge (egg row, rim
            # lip) a third of a pitch away must not pull the walk off the layer phase.
            offsets = (np.arange(a, b + 1) - chain[-1]) * direction / local - 1.0
            weight = np.exp(-0.5 * (offsets / params.step_sigma) ** 2)
            y = a + int(np.argmax(np.maximum(signal[a : b + 1], 0.0) * weight))
            gaps.append(abs(y - chain[-1]))
            chain.append(y)
        chains.append(chain)
    down, up = chains
    return up[::-1] + down[1:], len(up) - 1


def _period(signal: np.ndarray, a: int, b: int) -> tuple[np.ndarray | None, float]:
    """The signal between two rims resampled to a fixed length, centred and unit-norm; and its edge energy (std)."""
    if b - a < 3:
        return None, 0.0
    segment = signal[a : b + 1]
    resampled = np.interp(np.linspace(0, len(segment) - 1, _TEMPLATE_SAMPLES), np.arange(len(segment)), segment)
    resampled = resampled - resampled.mean()
    norm = float(np.linalg.norm(resampled))
    return (resampled / norm if norm > 1e-9 else None), float(np.std(segment))


def _run(chain: list[int], anchor: int, signal: np.ndarray, params: RimParams) -> tuple[int, int, list[float], int]:
    """The periodic run around the anchor: (first rim index, last rim index, period similarities, bridged rims).

    Walking out from the anchor, a rim joins the run when its edge is at least ``end_energy`` of the median rim edge of
    its parity near the anchor, the period to it looks like that parity's template (``end_similarity``) and its gap is
    about one local pitch. Cross-stacked trays alternate orientation, so odd and even layers are compared separately."""
    periods = [_period(signal, a, b) for a, b in zip(chain, chain[1:], strict=False)]
    near = range(max(0, anchor - params.template_rims), min(len(chain), anchor + params.template_rims + 1))
    templates, references = {}, {}
    for parity in (0, 1):
        inside = [periods[k][0] for k in near if k < len(periods) and k % 2 == parity and periods[k][0] is not None]
        if inside:
            template = np.median(np.stack(inside), axis=0)
            template = template - template.mean()
            templates[parity] = template / max(float(np.linalg.norm(template)), 1e-9)
        strengths = [signal[chain[k]] for k in near if k % 2 == parity]
        references[parity] = max(float(np.median(strengths)), 1e-9) if strengths else max(float(signal[chain[anchor]]), 1e-9)
    if not templates:
        return anchor, anchor, [], 0
    similarity = [float(p @ templates.get(k % 2, templates.get(1 - k % 2))) if p is not None else -1.0
                  for k, (p, _) in enumerate(periods)]
    gaps = np.diff(chain).astype(float)
    pair = float(np.median([gaps[k] + gaps[k + 1] for k in range(len(gaps) - 1)])) / 2.0 if len(gaps) > 1 else (
        float(gaps[0]) if gaps.size else 1.0)

    def good(rim: int, period: int) -> bool:
        return bool(signal[chain[rim]] >= params.end_energy * references[rim % 2]
                    and similarity[period] >= params.end_similarity
                    and 0.6 * pair <= gaps[period] <= 1.45 * pair)

    bridged = 0

    def walk(step: int) -> int:
        """Rims taken beyond the anchor in one direction (step +1 down, -1 up). Up to ``max_bridge`` weak rims are
        bridged when the two rims after them are good again (a dark or occluded layer inside the stack)."""
        nonlocal bridged
        taken, k = 0, 1
        rim = lambda j: anchor + step * j  # noqa: E731
        period = lambda j: anchor + step * j - (1 if step > 0 else 0)  # noqa: E731 - period between rim j-1 and j
        while 0 <= rim(k) < len(chain):
            if good(rim(k), period(k)):
                taken, k = k, k + 1
                continue
            for weak in range(1, params.max_bridge + 1):
                after = (k + weak, k + weak + 1)
                if 0 <= rim(after[1]) < len(chain) and all(good(rim(j), period(j)) for j in after):
                    bridged += weak
                    taken, k = after[1], after[1] + 1
                    break
            else:
                break
        return taken

    below, above = walk(1), walk(-1)
    first, last = anchor - above, anchor + below
    return first, last, similarity[first:last], bridged


def _count_column(image: np.ndarray, column: dict, index: int, params: RimParams) -> dict:
    if not isinstance(column, dict) or any(not _finite(column.get(k)) for k in ("x_min", "x_max")):
        return _empty(column, index, "column needs a finite x_min and x_max")
    height, width = image.shape[:2]
    x0, x1 = _x_range(column)
    if x1 <= x0:
        return _empty(column, index, "degenerate column x-range")
    xa, xb = int(np.floor(max(0.0, x0))), int(np.ceil(min(float(width), x1)))
    if xb - xa < 6:
        return _empty(column, index, "column strip is empty or narrower than 6 px")
    strip_width = float(x1 - x0)
    lo = max(3, int(np.floor(params.pitch_width_bounds[0] * strip_width)))
    hi = min(int(np.ceil(params.pitch_width_bounds[1] * strip_width)), height // 3)
    if hi <= lo:
        return _empty(column, index, "the strip is too short for three layers at the expected pitch")
    strip = image[:, xa:xb]
    raw = edge_signal(strip, params)
    absolute = edge_signal(strip, params, absolute=True)
    if raw is None or absolute is None:
        return _empty(column, index, "strip too small for an edge signal")
    pitch0, strength0, _ = band_pitch(raw, absolute, lo, hi, params)
    if pitch0 is None:
        result = _empty(column, index, "no periodic edge signal at a layer pitch")
        result["acf_strength"] = round(float(strength0), 3)
        return result
    # The band with the strongest local periodicity is the stack; its own autocorrelation gives the pitch.
    centre = _anchor(gaussian_filter1d(raw, 1.0), pitch0, params)
    reach = int(round(params.local_layers * pitch0))
    band = slice(max(0, centre - reach), min(len(raw), centre + reach))
    pitch, strength, alternatives = band_pitch(raw[band], absolute[band], lo, hi, params)
    if pitch is None:
        pitch, strength, alternatives = pitch0, strength0, {}
    signal = gaussian_filter1d(raw, sigma=max(1.0, params.smooth_fraction * pitch))
    a, b = int(max(0, round(centre - 0.5 * pitch))), int(min(len(signal) - 1, round(centre + 0.5 * pitch)))
    anchor = a + int(np.argmax(signal[a : b + 1]))
    chain, anchor_index = _track(signal, anchor, pitch, params)
    first, last, similarity, bridged = _run(chain, anchor_index, signal, params)
    rims = chain[first : last + 1]
    if len(rims) < params.min_rims:
        return _empty(column, index, "no periodic run of at least three rims")
    ys = np.asarray(rims, dtype=float)
    gaps = np.diff(ys)
    local = float(np.median(gaps))
    residuals = [abs((gaps[k] + gaps[k + 1]) / (2.0 * local) - 1.0) for k in range(len(gaps) - 1)]
    # Regularity on sums of neighbouring gaps: cross-stacked trays alternate, so single gaps alternate long/short
    # while each pair still spans two pitches.
    regularity = float(np.clip(1.0 - np.mean(residuals) / 0.25, 0.0, 1.0)) if residuals else 0.0
    coherence = float(np.clip(np.median(similarity), 0.0, 1.0)) if similarity else 0.0
    # A stack end is proven only with a full layer of room before the frame edge (the Worker's end_at_frame_edge rule);
    # rims are bright-to-dark edges, so the first one can sit almost a pitch below a cut top.
    touches_frame = bool(ys[0] < 1.5 * local or ys[-1] > height - 1 - 1.5 * local)
    ambiguous = bool(alternatives and alternatives["layer"] > 0
                     and alternatives["half"] >= params.ambiguity * alternatives["layer"] and pitch / 2.0 >= lo)
    confidence = 0.45 * coherence + 0.35 * regularity + 0.20 * min(1.0, strength / 0.3) - 0.15 * bridged
    confidence = float(np.clip(confidence, 0.0, 1.0))
    reasons = []
    if confidence < params.min_confidence:
        reasons.append(f"weak periodic evidence (confidence {confidence:.2f})")
    if ambiguous:
        reasons.append("half the pitch is nearly as periodic as the pitch (p/2 or p is ambiguous)")
    if touches_frame:
        reasons.append("the periodic run reaches the frame edge; the stack may continue outside the photo")
    readable = not reasons
    gradient = None
    if len(gaps) >= 6:
        third = max(2, len(gaps) // 3)
        bottom = float(np.median(gaps[-third:]))
        gradient = round(float(np.median(gaps[:third])) / bottom, 3) if bottom > 0 else None
    count = int(len(ys))
    # Comparison with the detector's box stack, when the caller sent it: reported, never used for the count.
    extra = missing = 0
    extends = None
    if _finite(column.get("y_first")) and _finite(column.get("y_last")):
        y_first, y_last = float(column["y_first"]), float(column["y_last"])
        above, below = (y_first - ys[0]) / local, (ys[-1] - y_last) / local
        extra = int(max(0, round(above)) + max(0, round(below)))
        missing = int(max(0, round(-above)) + max(0, round(-below)))
        if extra:
            extends = "both" if round(above) >= 1 and round(below) >= 1 else "top" if round(above) >= 1 else "bottom"
    notes = ["periodic-edge count from the image; the detector gave the strip only; not verified"]
    if bridged:
        notes.append(f"{bridged} weak period(s) inside the stack bridged")
    notes.extend(reasons)
    span_count, walk = column.get("span_count"), column.get("walk_count")
    return {
        "column": column.get("column", index),
        "rim_count": count if readable else None,
        "rim_count_raw": count,
        "readable": readable,
        "unreadable_reason": "; ".join(reasons) or None,
        "confidence": round(confidence if readable else 0.0, 3),
        "pitch_px": round(local, 2),
        "pitch_alternatives": alternatives or None,
        "top_y": round(float(ys[0]), 1),
        "base_y": round(float(ys[-1]), 1),
        "run_longer_than_boxes": bool(extra >= 1),
        "run_extra_layers": extra,
        "run_extends": extends,
        "run_shorter_than_boxes": bool(missing >= 1),
        "run_missing_layers": missing,
        "peaks_y": [round(float(y), 1) for y in ys],
        "local_pitches": [round(float(g), 2) for g in gaps],
        "agrees_with_span": bool(count == int(span_count)) if _finite(span_count) and readable else None,
        "agrees_with_walk": bool(count == int(walk)) if _finite(walk) and readable else None,
        "perspective_gradient": gradient,
        "bridged_periods": bridged,
        "acf_strength": round(float(strength), 3),
        "coherence": round(coherence, 3),
        "regularity": round(regularity, 3),
        "touches_frame": touches_frame,
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
