"""Span-based layer count per stack column from tray detections.

Measured on the 2026-10-07 labelled field photos: raw per-column box counts
carry duplicate and missed boxes that cancel in scene totals but not per
stack. Counting the vertical span between the first and last box centre in
units of the median layer spacing removes duplicates. It still misses layers
the detector never saw at the top or bottom, so the result is diagnostic
evidence, never a verified count.

Known failure modes recorded with the evidence:
- stacks at different depths that overlap in x are merged into one column;
- close-up views from above compress the lower layers, so a single median
  pitch undercounts; rectify first;
- a column whose last box is not the physical base undercounts.
"""

from __future__ import annotations

import numpy as np


def _columns(detections: list[dict]) -> list[list[dict]]:
    if not detections:
        return []
    widths = np.array([d["width"] for d in detections], dtype=float)
    gap = 0.6 * float(np.median(widths))
    columns: list[list[dict]] = []
    for det in sorted(detections, key=lambda d: d["x"]):
        if columns and det["x"] - np.mean([d["x"] for d in columns[-1]]) < gap:
            columns[-1].append(det)
        else:
            columns.append([det])
    return [c for c in columns if len(c) >= 3]


def walk_layers(ys: list[float], height: float) -> dict:
    """Count layers by walking down a column with a slowly varying local pitch.

    Perspective makes the layer spacing shrink from the top of a stack to its
    base, so a single global pitch rounds the wrong way on tall stacks. The walk
    treats a box closer than 0.65 x the local pitch to the previous accepted box
    as a duplicate (this includes stray boxes sitting between two layers),
    fills missed layers when a gap is close to a multiple of the pitch, and
    lets the local pitch drift between 0.6 and 1.4 of the global pitch so it
    follows perspective without collapsing after a stray box. Returns the
    count, the accepted gaps and the top/base gap ratio (perspective
    gradient; > 1.5 means the camera looked down on the stack).
    """
    ys = sorted(float(y) for y in ys)
    if not ys:
        return {"count": 0, "gaps": [], "duplicates": 0, "filled": 0, "perspective_gradient": None}
    raw_gaps = np.diff(ys)
    real = raw_gaps[raw_gaps > 0.5 * height]
    global_pitch = float(np.median(real)) if len(real) else float(height)
    pitch = global_pitch
    count, duplicates, filled, gaps = 1, 0, 0, []
    last = ys[0]
    for y in ys[1:]:
        gap = y - last
        if gap < 0.65 * pitch:
            duplicates += 1
            continue
        steps = max(1, int(round(gap / pitch)))
        if steps > 1:
            filled += steps - 1
        count += steps
        gaps.extend([gap / steps] * steps)
        pitch = float(min(max(np.median(gaps[-3:]), 0.6 * global_pitch), 1.4 * global_pitch))
        last = y
    gradient = None
    if len(gaps) >= 6:
        third = max(2, len(gaps) // 3)
        gradient = round(float(np.median(gaps[:third]) / np.median(gaps[-third:])), 3)
    return {"count": count, "gaps": [round(g, 2) for g in gaps], "duplicates": duplicates,
            "filled": filled, "perspective_gradient": gradient}


def count_layers_by_span(detections: list[dict]) -> list[dict]:
    """Group centre-format boxes (x, y, width, height) into columns and count.

    Returns one record per column with the raw box count, the span count,
    the pitch in pixels, the number of duplicate boxes removed and the
    column x-extent. ``verified`` is always False.
    """
    for det in detections:
        values = [det.get(k) for k in ("x", "y", "width", "height")]
        if any(v is None or not np.isfinite(v) for v in values) or det["width"] <= 0 or det["height"] <= 0:
            raise ValueError("Detection requires finite centre-format box with positive size")
    records = []
    for index, column in enumerate(_columns(detections), 1):
        ys = np.sort([d["y"] for d in column])
        height = float(np.median([d["height"] for d in column]))
        gaps = np.diff(ys)
        real = gaps[gaps > 0.5 * height]
        pitch = float(np.median(real)) if len(real) else height
        span = int(round((ys[-1] - ys[0]) / pitch)) + 1
        walk = walk_layers(ys, height)
        records.append(
            {
                "column": index,
                "model_boxes": len(column),
                "span_count": span,
                "walk_count": walk["count"],
                "walk_filled": walk["filled"],
                "perspective_gradient": walk["perspective_gradient"],
                "pitch_px": round(pitch, 2),
                "duplicate_boxes": int(len(column) - len(real) - 1),
                "x_min": round(float(min(d["x"] - d["width"] / 2 for d in column)), 1),
                "x_max": round(float(max(d["x"] + d["width"] / 2 for d in column)), 1),
                "y_first": round(float(ys[0]), 1),
                "y_last": round(float(ys[-1]), 1),
                "verified": False,
                "note": "span count assumes uniform layer pitch and a visible top and base; diagnostic only",
            }
        )
    return records
