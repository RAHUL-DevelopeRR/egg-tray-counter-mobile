"""Five/six parity and occupancy of a stack's end layers, from cross-stacked trays (plan Phase P).

The trays are cross-stacked: alternate layers are turned 90 degrees, so a stack's front shows rows of 5 and
6 egg cells
in turn (reports/field-scans-20261013/README.md; benchmarks/annotations-20261101). Over the egg-containing
layers,
which alternate, the same row type at the top and bottom means an odd number of layers and different types
an even
number. This module reads the type and occupancy of a column's end layers from the image and gives that
parity.

It is a parity check only: it never corrects or promotes a count, it cannot see an error of two layers, and
a reading
whose end layers it cannot type is ``unreadable`` (far faces, where the 6-cell rows are dark, and ends cut
by the
frame). Empty trays (cover trays) are not egg layers: they are skipped and reported, never typed.

What it takes from the detector: the column's x-range and its end rows (``y_first``, ``y_last``,
``pitch_px``) to know
where to look; it then probes up to two layers beyond each end, so a tray the detector did not box (the
L-109 stack 4
floor tray, the img-30 stack 2 top tray) is found as ``unboxed_above``/``unboxed_below`` and typed itself.

Egg cells: eggs are bright and unsaturated against the coloured plastic (HSV: saturation at most
``egg_max_sat``,
value at least ``egg_min_val``); blobs of about one cell in the layer's band are counted. A band with
exactly 5 or 6
evenly spaced egg blobs has that type; 1-4 blobs is a partly filled tray (untyped); none with tray-coloured
plastic is
an empty tray.

Thresholds frozen 2026-11-01 before scoring against the hand annotations
(reports/cross-stack-20261101/README.md).
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(frozen=True)
class CrossStackParams:
    egg_max_sat: int = 80  # an egg pixel is unsaturated (HSV S, 0-255) ...
    egg_min_val: int = 135  # ... and bright (HSV V, 0-255)
    plastic_min_sat: int = 90  # a tray pixel is saturated plastic (green, orange)
    band_half: float = 0.40  # a layer's band reaches this many pitches above and below its row
    search: float = 0.30  # the best band is searched this many pitches around the expected row
    cell_fraction: tuple[float, float] = (0.35, 1.6)  # egg blob width bounds, in cells (box width / 6)
    min_blob_area: float = 0.10  # egg blob area at least this share of (one cell x one pitch)
    max_gap_spread: float = 0.35  # blob spacing: std/mean of neighbouring gaps at most this for a typed row
    empty_plastic: float = (
        0.25  # an egg-free band with at least this share of plastic pixels is an empty tray
    )
    probe_layers: int = 2  # layers probed beyond each detector end


DEFAULT_PARAMS = CrossStackParams()


def _finite(value) -> bool:
    try:
        return bool(np.isfinite(float(value)))
    except (TypeError, ValueError):
        return False


def _x_range(column: dict) -> tuple[float, float]:
    if (
        _finite(column.get("x_centre"))
        and _finite(column.get("box_width_px"))
        and float(column["box_width_px"]) > 0
    ):
        half = float(column["box_width_px"]) / 2.0
        return float(column["x_centre"]) - half, float(column["x_centre"]) + half
    return float(column["x_min"]), float(column["x_max"])


def read_layer(hsv: np.ndarray, y: float, pitch: float, x0: int, x1: int, params: CrossStackParams) -> dict:
    """The layer whose row is near ``y``: egg blobs counted in the best band within ``search`` pitches."""
    height = hsv.shape[0]
    width = x1 - x0
    cell = width / 6.0
    best = None
    for dy in np.linspace(-params.search, params.search, 7) * pitch:
        top, bottom = (
            int(round(y + dy - params.band_half * pitch)),
            int(round(y + dy + params.band_half * pitch)),
        )
        if top < 0 or bottom > height or bottom - top < 3:
            continue
        band = hsv[top:bottom, x0:x1]
        egg = ((band[..., 1] <= params.egg_max_sat) & (band[..., 2] >= params.egg_min_val)).astype(np.uint8)
        egg = cv2.morphologyEx(egg, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        count, _, stats, centroids = cv2.connectedComponentsWithStats(egg, connectivity=8)
        blobs = [
            centroids[k][0]
            for k in range(1, count)
            if params.cell_fraction[0] * cell <= stats[k, cv2.CC_STAT_WIDTH] <= params.cell_fraction[1] * cell
            and stats[k, cv2.CC_STAT_AREA] >= params.min_blob_area * cell * pitch
        ]
        plastic = float(np.mean(band[..., 1] >= params.plastic_min_sat))
        score = len(blobs)
        if best is None or score > best["eggs"]:
            best = {
                "y": round(y + dy, 1),
                "eggs": score,
                "xs": sorted(float(b) for b in blobs),
                "plastic": plastic,
            }
    if best is None:
        return {"y": round(y, 1), "eggs": 0, "type": None, "occupancy": "unknown", "in_frame": False}
    xs = best["xs"]
    gaps = np.diff(xs) if len(xs) > 1 else np.array([])
    even = bool(gaps.size and float(np.std(gaps)) <= params.max_gap_spread * float(np.mean(gaps)))
    kind = best["eggs"] if best["eggs"] in (5, 6) and even else None
    if best["eggs"] >= 5:
        occupancy = "filled"
    elif best["eggs"] >= 1:
        occupancy = "partial"
    else:
        occupancy = "empty" if best["plastic"] >= params.empty_plastic else "unknown"
    return {"y": best["y"], "eggs": best["eggs"], "type": kind, "occupancy": occupancy, "in_frame": True}


def cross_stack(
    image_bgr: np.ndarray, columns: list[dict], params: CrossStackParams | None = None
) -> list[dict]:
    """Per column: the end layers' type and occupancy, unboxed egg layers beyond the detector's ends, and
    the parity.
    Never raises; a column it cannot read has ``readable`` False with a reason."""
    params = params or DEFAULT_PARAMS
    if not isinstance(image_bgr, np.ndarray) or image_bgr.ndim != 3 or image_bgr.size == 0:
        return [
            _unreadable(c, i, "image is empty or not a colour image") for i, c in enumerate(columns or [], 1)
        ]
    hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    return [_column(hsv, c, i, params) for i, c in enumerate(columns or [], 1)]


def _unreadable(column, index: int, reason: str) -> dict:
    return {
        "column": column.get("column", index) if isinstance(column, dict) else index,
        "readable": False,
        "reason": reason,
        "top": None,
        "bottom": None,
        "unboxed_above": 0,
        "unboxed_below": 0,
        "empty_trays_above": 0,
        "parity": None,
        "walk_parity_ok": None,
        "doubts": [],
    }


def _column(hsv: np.ndarray, column: dict, index: int, params: CrossStackParams) -> dict:
    try:
        keys = ("x_min", "x_max", "y_first", "y_last", "pitch_px")
        if (
            not isinstance(column, dict)
            or any(not _finite(column.get(k)) for k in keys)
            or float(column["pitch_px"]) <= 2
        ):
            return _unreadable(
                column, index, "column needs x_min, x_max, y_first, y_last and a pitch above 2 px"
            )
        height, width = hsv.shape[:2]
        x0f, x1f = _x_range(column)
        x0, x1 = int(max(0, np.floor(x0f))), int(min(width, np.ceil(x1f)))
        if x1 - x0 < 12:
            return _unreadable(column, index, "column strip narrower than 12 px")
        pitch = float(column["pitch_px"])
        y_first, y_last = float(column["y_first"]), float(column["y_last"])

        def end(start: float, step: float) -> tuple[dict, int, int, bool]:
            """Walk out from a detector end: the outermost egg layer, unboxed egg layers, empty trays
            beyond it, and
            whether the frame stopped the walk."""
            layer = read_layer(hsv, start, pitch, x0, x1, params)
            outer, unboxed, empty, cut = layer, 0, 0, not layer["in_frame"]
            for k in range(1, params.probe_layers + 1):
                probe = read_layer(hsv, start + step * k * pitch, pitch, x0, x1, params)
                if not probe["in_frame"]:
                    cut = True
                    break
                if probe["occupancy"] in ("filled", "partial") and empty == 0:
                    outer, unboxed = probe, k
                elif probe["occupancy"] == "empty":
                    empty += 1
                else:
                    break
            return outer, unboxed, empty, cut

        top, unboxed_above, empty_above, cut_top = end(y_first, -1.0)
        bottom, unboxed_below, _, cut_bottom = end(y_last, 1.0)
        reasons = []
        if cut_top or cut_bottom:
            reasons.append("a stack end is at the frame edge")
        if top["type"] is None or bottom["type"] is None:
            reasons.append("an end layer's row type (5 or 6 cells) cannot be read")
        readable = not reasons
        parity = ("odd" if top["type"] == bottom["type"] else "even") if readable else None
        walk = column.get("walk_count")
        walk_ok = None
        doubts = []
        if unboxed_above or unboxed_below:
            doubts.append("unboxed_egg_layer")
        if readable and _finite(walk):
            walk_ok = (int(walk) % 2 == 1) == (parity == "odd")
            if not walk_ok:
                doubts.append("parity_mismatch")
        return {
            "column": column.get("column", index),
            "readable": readable,
            "reason": "; ".join(reasons) or None,
            "top": top,
            "bottom": bottom,
            "unboxed_above": unboxed_above,
            "unboxed_below": unboxed_below,
            "empty_trays_above": empty_above,
            "parity": parity,
            "walk_parity_ok": walk_ok,
            "doubts": doubts,
        }
    except Exception as error:  # noqa: BLE001 - diagnostic path must never raise
        return _unreadable(column, index, f"cross-stack read failed: {type(error).__name__}")
