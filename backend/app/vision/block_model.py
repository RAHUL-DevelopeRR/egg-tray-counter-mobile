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

Every face that sees a cell contributes an observation; observations are
merged, never overwritten. Heights more than one layer apart are a
conflict. One layer apart is an ambiguity: the better-supported reading is
kept and the block is only an estimate.

``status`` is the one result state the app shows and stores:
``exact`` (every stack seen, faces agree), ``estimated`` (a total exists but
hidden stacks are computed or a reading is ambiguous), ``conflict`` (no
total; retake the named face) or ``needs_view`` (a face is missing).

Inputs are per-column records from ``layer_span.count_layers_by_span``.
Never raises on empty faces: a face with no stacks is a conflict in the
result, matching the Worker port.
"""

from __future__ import annotations

import statistics

RECESS_SCALE = 0.85  # pitch ratio below which a face column is treated as set back
MIN_RIM_CONFIDENCE = 0.5  # rim-edge verification only vetoes when its own confidence is at least this
MAX_PERSPECTIVE_GRADIENT = 1.5  # top-third / bottom-third layer spacing; measured frontal photos stay <= 1.42
# Tray boxes are about as tall as the layer spacing (0.79-1.16 on the 53 reference stacks). Far
# away, cross-stacked trays get boxes on alternate layers only, the spacing doubles and the count
# halves (2026-10-13 corner block: 0.64-0.67, about 10 of 20 layers).
MIN_BOX_PITCH_RATIO = 0.75


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
        box_height = column.get("box_height_px")
        box_ratio = box_height / column["pitch_px"] if box_height and column["pitch_px"] else None
        # Two box-based counts must agree; a steep top/base spacing ratio means the
        # camera looked down on the stack and the base layers may be compressed away.
        reason = None
        rim, rim_conf = column.get("rim_count"), column.get("rim_confidence") or 0.0
        if box_ratio is not None and box_ratio < MIN_BOX_PITCH_RATIO:
            reason = ("boxes found on only some layers (trays too small in the photo); "
                      "step closer and retake this face")
        elif column.get("walk_unresolved_gaps"):
            reason = "boxes are missing over several layers of this stack; retake this face"
        elif abs(span - layers) > 1:
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
                "filled": int(column.get("walk_filled") or 0),
                "scale": round(scale, 3),
                "recessed": scale < RECESS_SCALE,
                "count_agreement": reason is None,
                "reason": reason,
                "source": name,
            }
        )
    return face


def _result(width, depth, faces_used, typical, cells, conflicts, note, ambiguities=(), needs_view=False):
    observed = sum(c["layers"] or 0 for c in cells if c["status"] == "observed")
    computed = sum(c["layers"] or 0 for c in cells if c["status"] == "computed")
    filled = sum(c.get("filled_layers", 0) for c in cells if c["status"] == "observed")
    rescan = [[c["x"], c["y"]] for c in cells if c["status"] in {"rescan", "conflict"}]
    consistent = not conflicts and not rescan and typical is not None
    total = observed + computed if consistent else None
    if needs_view:
        status = "needs_view"
    elif total is None:
        status = "conflict"
    elif computed or ambiguities:
        status = "estimated"
    else:
        status = "exact"
    return {
        "status": status,
        "width": width,
        "depth": depth,
        "faces_used": faces_used,
        "typical_layers": typical,
        "cells": cells,
        "observed_trays": observed,
        "computed_trays": computed,
        "filled_trays": filled,
        "total_trays": total,
        "fully_observed": consistent and computed == 0,
        "faces_consistent": consistent,
        "conflicts": conflicts,
        "ambiguities": list(ambiguities),
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
            [{"reason": "STRAIGHT and at least one side face must show stacks"}], NOTE, needs_view=True,
        )
    xf = _face(straight, "straight")
    lf = list(reversed(_face(left, "left"))) if left else None
    rf = _face(right, "right") if right else None
    width = len(xf)
    conflicts: list[dict] = []
    ambiguities: list[dict] = []
    depths = {name: len(f) for name, f in (("left", lf), ("right", rf)) if f}
    if len(set(depths.values())) > 1:
        conflicts.append({"reason": "depth differs between LEFT and RIGHT faces", **depths})
    depth = max(depths.values())

    heights = [c["layers"] for c in xf + (lf or []) + (rf or []) if not c["recessed"]]
    typical = _round_half_even(statistics.median(heights)) if heights else None

    cells = {(x, y): {"x": x, "y": y, "status": "computed", "layers": typical, "source": "faces"}
             for y in range(depth) for x in range(width)}

    # Every face reading of a cell: (face column, face name, the cell seen when this one is missing).
    # STRAIGHT sees the front row; each side face sees its column, corner included. A one-wide
    # block puts LEFT and RIGHT on the same cells, so readings are merged, never overwritten.
    seen: dict[tuple[int, int], list[tuple[dict, str, tuple[int, int]]]] = {}
    for x, col in enumerate(xf):
        seen.setdefault((x, 0), []).append((col, "straight", (x, 1)))
    for name, f, xi, dx in (("left", lf, 0, 1), ("right", rf, width - 1, -1)):
        for y, col in enumerate(f or []):
            seen.setdefault((xi, y), []).append((col, name, (xi + dx, y)))

    promotions: dict[tuple[int, int], list[dict]] = {}
    for key, readings in seen.items():
        cell = cells[key]
        names = [name for _, name, _ in readings]
        source = "+".join(names)
        corner = key[1] == 0 and len(readings) > 1
        unsure = [(col, name) for col, name, _ in readings if not col["count_agreement"]]
        for col, name in unsure:
            conflicts.append({"cell": list(key), "reason": f"{name.upper()}: {col['reason']}"})
        if unsure:
            first = readings[0][0]
            cell.update(status="rescan", layers=0 if first["recessed"] else first["layers"], source=source)
            continue
        if len({col["recessed"] for col, _, _ in readings}) > 1:
            other = next(name for col, name, _ in readings if col["recessed"] != readings[0][0]["recessed"])
            where = "corner stack" if corner else "stack"
            faces = f"{names[0].upper()} vs {other.upper()}"
            conflicts.append({"cell": list(key), "reason": f"{where} is set back on one face only ({faces})"})
            cell.update(status="conflict", layers=None, source=source)
            continue
        if readings[0][0]["recessed"]:
            cell.update(status="missing", layers=0, source=source)
            for col, name, behind in readings:
                if key[1] == 0 and name != "straight":
                    continue  # a side face looks along the front row past a missing corner
                if behind in cells:
                    promotions.setdefault(behind, []).append(
                        {"status": "observed", "layers": col["layers"], "filled_layers": col["filled"],
                         "source": f"{name}-recessed"})
                else:
                    conflicts.append({"cell": list(key),
                                      "reason": f"{name.upper()} shows a stack behind a missing one, "
                                                "but the faces give no room for it; rescan"})
            continue
        values = {name: col["layers"] for col, name, _ in readings}
        layer_fields = {f"{name}_layers": v for name, v in values.items()}
        low, high = min(values, key=values.get), max(values, key=values.get)
        if values[high] - values[low] > 1:
            pair = sorted({low, high}, key=["straight", "left", "right"].index)
            where = "corner height" if corner and "straight" in values else "height"
            reason = f"{where} differs between {pair[0].upper()} and {pair[1].upper()}"
            conflicts.append({"cell": list(key), "reason": reason, **layer_fields})
            cell.update(status="conflict", layers=None, source=source)
            continue
        # Agreeing faces, or one layer apart: keep the reading with fewest gap-filled layers
        # (STRAIGHT on a tie) and record the ambiguity so the total is only an estimate.
        best = min(readings, key=lambda r: (r[0]["filled"], r[1] != "straight"))[0]
        cell.update(status="observed", layers=best["layers"], filled_layers=best["filled"], source=source)
        if values[high] != values[low]:
            ambiguities.append({"cell": list(key), "reason": "faces differ by one layer", **layer_fields,
                                "chosen": best["layers"]})

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
    return _result(width, depth, faces_used, typical, cell_list, conflicts, NOTE, ambiguities)


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
