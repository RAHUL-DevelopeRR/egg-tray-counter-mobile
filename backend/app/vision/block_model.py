"""Block model: STRAIGHT (X face), LEFT and RIGHT (Y faces) -> grid x height.

A rectangular block is X stacks wide and Y stacks deep. The STRAIGHT photo
observes the front row; the LEFT and RIGHT photos observe the two side
columns, so the depth Y is measured twice and must agree. The two front
corner stacks each appear in two photos and must agree. Every other stack is
interior: its height is COMPUTED from the observed faces (the X x Y x H
calculation the warehouse uses), and the output keeps observed and computed
trays separate so the app can show which is which.

A recessed face column (layer pitch clearly smaller than the face's typical
pitch) means the front stack is missing and the stack behind shows through:
the front cell is marked missing and the cell behind becomes observed. When
the grid has no cell behind (the faces say depth 1) that is a contradiction
and the block is sent for rescan instead of silently losing the stack.

Inputs are per-column records from ``layer_span.count_layers_by_span``.
Never raises on empty faces: a face with no stacks is a conflict in the
result, matching the Worker port.
"""

from __future__ import annotations

import statistics

RECESS_SCALE = 0.85  # pitch ratio below which a face column is treated as set back
MIN_RIM_CONFIDENCE = 0.5  # rim-edge verification only vetoes when its own confidence is at least this
MAX_PERSPECTIVE_GRADIENT = 1.5  # top-third / bottom-third layer spacing; measured frontal photos stay <= 1.42


def _round_half_even(value: float) -> int:
    return int(round(value))  # Python round() is half-to-even, same as the TS port


def _face(columns: list[dict], name: str) -> list[dict]:
    ordered = sorted(columns, key=lambda c: c["x_min"])
    # Reference pitch is the median of the front group (pitches at or above
    # the face median), not the single largest column: one spurious wide
    # column must not mark every other stack as recessed, and one recessed
    # column must not drag the reference down on a two-column face.
    pitches = [c["pitch_px"] for c in ordered]
    face_median = statistics.median(pitches)
    reference = statistics.median([v for v in pitches if v >= face_median])
    face = []
    for column in ordered:
        span = int(column["span_count"])
        layers = int(column.get("walk_count", span))
        scale = column["pitch_px"] / reference if reference else 1.0
        gradient = column.get("perspective_gradient")
        # Two box-based counts must agree; a steep top/base spacing ratio means the
        # camera looked down on the stack and the base layers may be compressed away.
        reason = None
        rim, rim_conf = column.get("rim_count"), column.get("rim_confidence") or 0.0
        if abs(span - layers) > 1:
            reason = f"layer counts disagree (span {span}, walk {layers}); retake this face"
        elif rim is not None and rim_conf >= MIN_RIM_CONFIDENCE and int(rim) != layers:
            reason = f"rim edges count {int(rim)} layers but boxes count {layers}; retake this face"
        elif gradient is not None and gradient > MAX_PERSPECTIVE_GRADIENT:
            reason = (
                f"camera looked down on the stack (spacing ratio {gradient}); "
                "hold the phone level at mid-height"
            )
        face.append(
            {
                "layers": layers,
                "scale": round(scale, 3),
                "recessed": scale < RECESS_SCALE,
                "count_agreement": reason is None,
                "reason": reason,
                "source": name,
            }
        )
    return face


def _result(width, depth, faces_used, typical, cells, conflicts, note):
    observed = sum(c["layers"] or 0 for c in cells if c["status"] == "observed")
    computed = sum(c["layers"] or 0 for c in cells if c["status"] == "computed")
    rescan = [[c["x"], c["y"]] for c in cells if c["status"] in {"rescan", "conflict"}]
    consistent = not conflicts and not rescan and typical is not None
    return {
        "width": width,
        "depth": depth,
        "faces_used": faces_used,
        "typical_layers": typical,
        "cells": cells,
        "observed_trays": observed,
        "computed_trays": computed,
        "total_trays": observed + computed if consistent else None,
        "fully_observed": consistent and computed == 0,
        "faces_consistent": consistent,
        "conflicts": conflicts,
        "rescan_cells": rescan,
        "note": note,
    }


NOTE = (
    "Interior stacks are computed from the observed faces (X x Y x height); "
    "missing or shorter interior stacks are not visible from the faces."
)


def build_block(
    straight: list[dict],
    left: list[dict] | None = None,
    right: list[dict] | None = None,
) -> dict:
    """Assemble a block from the STRAIGHT face and one or both side faces.

    LEFT is photographed standing at the block's left side, so its front
    corner is the right-most column in the image; RIGHT is photographed from
    the right side, so its front corner is the left-most column. Both side
    faces are re-ordered front -> back here.
    """
    faces_used = ["straight"] + [n for n, f in (("left", left), ("right", right)) if f]
    if not straight or (not left and not right):
        return _result(
            None, None, faces_used, None, [],
            [{"reason": "STRAIGHT and at least one side face must show stacks"}], NOTE,
        )
    xf = _face(straight, "straight")
    lf = list(reversed(_face(left, "left"))) if left else None
    rf = _face(right, "right") if right else None
    width = len(xf)
    conflicts: list[dict] = []
    depths = {name: len(f) for name, f in (("left", lf), ("right", rf)) if f}
    if len(set(depths.values())) > 1:
        conflicts.append({"reason": "depth differs between LEFT and RIGHT faces", **depths})
    depth = max(depths.values())

    # Corner agreement: same height and same recessed state on both faces.
    for name, f, xi in (("left", lf, 0), ("right", rf, width - 1)):
        if not f:
            continue
        a, b = xf[xi], f[0]
        if not b["count_agreement"]:
            conflicts.append({"cell": [xi, 0], "reason": f"{name.upper()}: {b['reason']}"})
        if a["recessed"] != b["recessed"]:
            conflicts.append(
                {"cell": [xi, 0],
                 "reason": f"corner stack is set back on one face only (STRAIGHT vs {name.upper()})"}
            )
        elif abs(a["layers"] - b["layers"]) > 1:
            conflicts.append(
                {"cell": [xi, 0], "reason": f"corner height differs between STRAIGHT and {name.upper()}",
                 "straight_layers": a["layers"], f"{name}_layers": b["layers"]}
            )

    heights = [c["layers"] for c in xf + (lf or []) + (rf or []) if not c["recessed"]]
    typical = _round_half_even(statistics.median(heights)) if heights else None

    cells = {(x, y): {"x": x, "y": y, "status": "computed", "layers": typical, "source": "faces"}
             for y in range(depth) for x in range(width)}

    def place(key, col, source, behind_key):
        cell = cells[key]
        if col["recessed"]:
            cell.update(status="missing", layers=0, source=source)
            if behind_key in cells:
                promotions.setdefault(behind_key, []).append(
                    {"status": "observed", "layers": col["layers"], "source": f"{source}-recessed"}
                )
            else:
                conflicts.append(
                    {"cell": list(key),
                     "reason": f"{source.upper()} shows a stack behind a missing one, "
                               "but the faces give no room for it; rescan"}
                )
        else:
            cell.update(status="observed", layers=col["layers"], source=source)
        if not col["count_agreement"]:
            cell["status"] = "rescan"
            conflicts.append({"cell": list(key), "reason": f"{source.upper()}: {col['reason']}"})

    promotions: dict[tuple[int, int], list[dict]] = {}
    for x, col in enumerate(xf):
        place((x, 0), col, "straight", (x, 1))
    for name, f, xi, dx in (("left", lf, 0, 1), ("right", rf, width - 1, -1)):
        if not f:
            continue
        for y, col in enumerate(f):
            if y == 0 or y >= depth:
                continue  # corner handled from STRAIGHT; extra rows already a depth conflict
            place((xi, y), col, name, (xi + dx, y))
    for key, candidates in promotions.items():
        cell = cells[key]
        layers = {c["layers"] for c in candidates}
        if cell["status"] == "computed" and len(layers) == 1:
            cell.update(candidates[0])
        elif cell["status"] == "observed" and layers == {cell["layers"]}:
            cell["source"] += "+" + "+".join(c["source"] for c in candidates)
        else:
            cell.update(status="conflict", layers=None, source="+".join(c["source"] for c in candidates))
            conflicts.append(
                {"cell": list(key), "reason": "faces disagree about the stack behind a missing one"}
            )

    cell_list = [cells[(x, y)] for y in range(depth) for x in range(width)]
    return _result(width, depth, faces_used, typical, cell_list, conflicts, NOTE)


def render_boxes(block: dict, tray_w: float = 1.0, tray_d: float = 1.0, layer_h: float = 0.25) -> list[dict]:
    """Axis-aligned boxes for the app's 3D view, one per stack, colour by status."""
    return [
        {
            "x": c["x"] * tray_w, "y": c["y"] * tray_d, "z": 0.0,
            "w": tray_w, "d": tray_d, "h": c["layers"] * layer_h,
            "layers": c["layers"], "status": c["status"],
        }
        for c in block["cells"]
        if c["layers"]
    ]
