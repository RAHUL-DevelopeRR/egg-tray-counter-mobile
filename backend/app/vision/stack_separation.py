"""Stack-face separation from tray boxes, without polygons (arm C of the 2026-10-15 stack-face experiment).

``layer_span.count_layers_by_span`` groups boxes into columns by x only and drops groups of fewer
than 3 boxes. The reviewed stack-face polygons (reports/experiment-stack-faces-20261015/) show
three ways that loses or mixes stacks:

1. A short front stack and the taller stack behind it share one x-column. The rear stack's top
   shows above the short one, its boxes are narrower (farther away) and there is a gap of one or
   more missing layers where the short stack's top tray is seen from above. Measured on the
   polygons: every column pair that crossed from a set-back polygon into the front polygon below
   it with a vertical gap had a gap of 1.54-4.3 layer pitches and an upper/lower box-width ratio
   of 0.63-0.81; inside one polygon no pair had both a gap of at least 1.4 pitches and a width
   ratio of at most 0.85 once the split is taken at the largest such gap (one pair inside ef823816
   LEFT ``l_setback``, gap 2.13, ratio 0.791, meets both before that split and is kept whole only by
   the largest-gap rule; 5 positives from 3 blocks). Columns are split there
   (``SPLIT_MIN_GAP_PITCHES``, ``SPLIT_MAX_WIDTH_RATIO``); the upper part is a set-back stack whose
   base is hidden, so its count is the visible layers only (``partial``).
2. Loose trays and 1-2 tray stacks have fewer than 3 boxes and disappear. They are kept here as
   ``short`` stacks (count = the walk count of their boxes, which removes a duplicate box), unless
   their boxes are much smaller than the main stacks' (``SHORT_MIN_SCALE``), which on the polygons
   only happened for a background stack.
3. Tall thin boxes along the frame edge (width/height 0.09-0.13; every box on a tray in the 20
   reviewed photos has at least 1.19) formed a 3-box "column" of fragments. Boxes narrower than
   ``SLIVER_ASPECT`` x their height are not tray faces and are dropped before grouping.

Each stack also gets a depth label from its box width against the front stacks' width: ``front``,
``set_back`` (narrower than ``FRONT_MIN_SCALE``) or ``set_back_partial`` (split off above a stack).
The thresholds come from polygon geometry only; no count label was used. Like ``layer_span`` the
result is diagnostic evidence, never a verified count.

Not handled (seen in the polygons, left for later): x-overlapping stacks at two depths with no
vertical gap between them (count-neutral for a face total), boxes that span two stacks at an
oblique close view, and neighbour stacks at the same scale as the target.
"""

from __future__ import annotations

import statistics

import numpy as np

from app.vision.layer_span import walk_layers

SLIVER_ASPECT = 0.5  # width / height below this is a frame-edge fragment, not a tray face
JOIN_GAP_FRAC = 0.6  # same x-grouping rule as layer_span._columns
SPLIT_MIN_GAP_PITCHES = 1.4  # vertical gap (in column pitches) needed for a depth split
SPLIT_MAX_WIDTH_RATIO = 0.85  # upper/lower box width at the gap must be at most this
SHORT_MAX_BOXES = 2  # groups this small are short stacks / loose trays
SHORT_MIN_SCALE = 0.65  # short groups narrower than this x the front stacks are background
FRONT_MIN_SCALE = 0.85  # same value as block_model.RECESS_SCALE, applied to box width

PARAMS = {
    "sliver_aspect": SLIVER_ASPECT,
    "join_gap_frac": JOIN_GAP_FRAC,
    "split_min_gap_pitches": SPLIT_MIN_GAP_PITCHES,
    "split_max_width_ratio": SPLIT_MAX_WIDTH_RATIO,
    "short_max_boxes": SHORT_MAX_BOXES,
    "short_min_scale": SHORT_MIN_SCALE,
    "front_min_scale": FRONT_MIN_SCALE,
}


def _check(detections: list[dict]) -> None:
    for det in detections:
        values = [det.get(k) for k in ("x", "y", "width", "height")]
        if any(v is None or not np.isfinite(v) for v in values) or det["width"] <= 0 or det["height"] <= 0:
            raise ValueError("Detection requires finite centre-format box with positive size")


def column_record(column: list[dict], index: int = 1) -> dict:
    """The per-column record of ``count_layers_by_span`` for an already grouped set of boxes.

    Same arithmetic, field for field, so the block model's ``_face`` can read it; it also works for
    one or two boxes, which ``count_layers_by_span`` never returns.
    """
    ys = np.sort([d["y"] for d in column])
    height = float(np.median([d["height"] for d in column]))
    gaps = np.diff(ys)
    real = gaps[gaps > 0.5 * height]
    pitch = float(np.median(real)) if len(real) else height
    span = int(round((ys[-1] - ys[0]) / pitch)) + 1
    walk = walk_layers(ys, height)
    return {
        "column": index,
        "model_boxes": len(column),
        "span_count": span,
        "walk_count": walk["count"],
        "walk_filled": walk["filled"],
        "walk_unresolved_gaps": walk["unresolved_gaps"],
        "perspective_gradient": walk["perspective_gradient"],
        "pitch_px": round(pitch, 2),
        "box_height_px": round(height, 2),
        "duplicate_boxes": int(len(column) - len(real) - 1),
        "x_min": round(float(min(d["x"] - d["width"] / 2 for d in column)), 1),
        "x_max": round(float(max(d["x"] + d["width"] / 2 for d in column)), 1),
        "y_first": round(float(ys[0]), 1),
        "y_last": round(float(ys[-1]), 1),
        "verified": False,
        "note": "span count assumes uniform layer pitch and a visible top and base; diagnostic only",
    }


def _x_groups(boxes: list[dict]) -> list[list[dict]]:
    """layer_span._columns without the 3-box minimum."""
    if not boxes:
        return []
    gap = JOIN_GAP_FRAC * float(np.median([d["width"] for d in boxes]))
    groups: list[list[dict]] = []
    for det in sorted(boxes, key=lambda d: d["x"]):
        if groups and det["x"] - np.mean([d["x"] for d in groups[-1]]) < gap:
            groups[-1].append(det)
        else:
            groups.append([det])
    return groups


def _depth_split(group: list[dict]) -> list[list[dict]]:
    """Split a y-sorted group at the widest gap where the boxes above are clearly narrower; recurse."""
    if len(group) < 2:
        return [group]
    height = float(np.median([d["height"] for d in group]))
    gaps = np.diff([d["y"] for d in group])
    real = gaps[gaps > 0.5 * height]
    pitch = float(np.median(real)) if len(real) else height
    best = None
    for i, gap in enumerate(gaps):
        if gap < SPLIT_MIN_GAP_PITCHES * pitch:
            continue
        upper = statistics.median(d["width"] for d in group[max(0, i - 2): i + 1])
        lower = statistics.median(d["width"] for d in group[i + 1: i + 4])
        if upper / lower > SPLIT_MAX_WIDTH_RATIO:
            continue
        if best is None or gap > best[0]:
            best = (float(gap), i)
    if best is None:
        return [group]
    i = best[1]
    return _depth_split(group[: i + 1]) + _depth_split(group[i + 1:])


def separate_stacks(detections: list[dict]) -> dict:
    """Group centre-format boxes (x, y, width, height) into stack faces and count each.

    Returns ``stacks`` (ordered by x, then top to bottom; each a ``column_record`` plus
    ``box_indices`` into ``detections``, ``depth``, ``scale``, ``short``, ``partial``, ``flags``),
    ``dropped`` (box indices with a reason), ``total`` (sum of the stacks' walk counts) and the
    parameters used. Every input box is either in exactly one stack or in ``dropped``.
    """
    _check(detections)
    indexed = [dict(d, _i=i) for i, d in enumerate(detections)]
    sliver_reason = f"sliver (width/height below {SLIVER_ASPECT:.2f}): not a tray face"
    dropped = [{"index": d["_i"], "reason": sliver_reason}
               for d in indexed if d["width"] / d["height"] < SLIVER_ASPECT]
    boxes = [d for d in indexed if d["width"] / d["height"] >= SLIVER_ASPECT]

    segments = []  # (boxes, partial)
    for group in _x_groups(boxes):
        parts = _depth_split(sorted(group, key=lambda d: d["y"]))
        for k, part in enumerate(parts):
            segments.append((part, k < len(parts) - 1))  # every part above the lowest has its base hidden

    widths = [statistics.median(d["width"] for d in seg) for seg, partial in segments
              if len(seg) > SHORT_MAX_BOXES and not partial]
    if not widths:
        widths = [statistics.median(d["width"] for d in seg) for seg, _ in segments]
    reference = None
    if widths:
        middle = statistics.median(widths)
        reference = statistics.median([w for w in widths if w >= middle])

    stacks = []
    for seg, partial in segments:
        width = statistics.median(d["width"] for d in seg)
        scale = width / reference if reference else 1.0
        short = len(seg) <= SHORT_MAX_BOXES
        if short and scale < SHORT_MIN_SCALE:
            reason = f"short group at {scale:.2f} x the front box width: background"
            dropped += [{"index": d["_i"], "reason": reason} for d in seg]
            continue
        flags = []
        if partial:
            depth = "set_back_partial"
            flags.append("set back above a front stack; base hidden, visible layers only")
        elif scale < FRONT_MIN_SCALE:
            depth = "set_back"
            flags.append("narrower boxes than the front stacks: set back")
        else:
            depth = "front"
        if short:
            flags.append(f"short stack ({len(seg)} box{'' if len(seg) == 1 else 'es'})")
        stacks.append({"seg": seg, "depth": depth, "scale": round(scale, 3), "short": short,
                       "partial": partial, "flags": flags})

    stacks.sort(key=lambda s: (min(d["x"] - d["width"] / 2 for d in s["seg"]), min(d["y"] for d in s["seg"])))
    out = []
    for n, s in enumerate(stacks, 1):
        record = column_record(s["seg"], n)
        record.update(box_indices=sorted(d["_i"] for d in s["seg"]), depth=s["depth"], scale=s["scale"],
                      short=s["short"], partial=s["partial"], flags=s["flags"])
        out.append(record)
    return {
        "stacks": out,
        "dropped": sorted(dropped, key=lambda r: r["index"]),
        "total": sum(s["walk_count"] for s in out),
        "reference_box_width": None if reference is None else round(float(reference), 2),
        "params": dict(PARAMS),
    }
