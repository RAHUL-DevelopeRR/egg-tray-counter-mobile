"""Candidate image evidence and explicit physical-grid accounting; never scene-total voting.

Image correspondence is provisional without camera geometry. Generic egg_tray
labels and brightness bands never certify physical layers or egg occupancy.
"""

from __future__ import annotations

import cv2
import numpy as np

from app.config import Settings
from app.vision.quality import evaluate_quality
from app.vision.stack_measurement import analyze_rims, localize_stacks, rectify_native


def beam_evidence(image: np.ndarray, stack: dict) -> dict:
    face, geometry = rectify_native(image, stack["polygon"])
    result = analyze_rims(face.image, max_pitch=max(90, face.image.shape[0] // 3))
    best = result["best"]
    return {
        "stack_id": stack["stack_id"],
        "tray_count_candidates": sorted({h["count"] for h in result["hypotheses"]}),
        "selected_count": None,
        "exploratory_band_count": best["count"] if best else None,
        "pitch_px": best["pitch_px"] if best else None,
        "band_centers": best["centres"] if best else [],
        "coverage": best["coverage"] if best else 0,
        "top_visible": stack.get("top_visible"),
        "bottom_visible": stack.get("bottom_visible"),
        "harmonic_ambiguity": len({h["count"] for h in result["hypotheses"]}) > 1,
        "quality": best["support"] if best else 0,
        "quality_meaning": "uncalibrated signal support",
        "reason": result["reason"],
        "geometry": geometry,
        "hypotheses": result["hypotheses"],
        "profile": result["profile"],
        "signed_sobel": result["signed_sobel"],
        "autocorrelation": result["autocorrelation"],
    }


def fuse_stack(rf_count: int, beam: dict, height: dict | None = None) -> dict:
    """Retain channel disagreement. Calibrated height can propose Z, not occupancy."""
    height_count = height.get("height_count") if height else None
    band = beam.get("exploratory_band_count")
    return {
        "rf_count": rf_count,
        "beam_count": band,
        "rim_count": None,
        "height_count": height_count,
        "candidate_z": height_count if height_count is not None else band,
        "physical_layer_count": None,
        "status": "unresolved",
        "reason": "Physical rim semantics, endpoints and occupancy need validation",
        "channel_disagreement": band is not None and rf_count != band,
        "recommended_action": "Capture full top/base and a close-up of ambiguous layers",
    }


def analyze_view(image: np.ndarray, detections: list[dict], view: str) -> dict:
    quality = evaluate_quality(image, Settings())
    stacks = localize_stacks(detections, image.shape)
    for stack in stacks:
        stack["stack_id"] = f"{view}:{stack['stack_id']}"
        try:
            stack["beam"] = beam_evidence(image, stack)
            stack["fusion"] = fuse_stack(stack["rf_count"], stack["beam"])
        except ValueError as exc:
            stack["beam"] = {"selected_count": None, "reason": str(exc)}
            stack["fusion"] = {"physical_layer_count": None, "status": "unresolved"}
        stack["occupancy"] = "unknown"
    return {
        "view": view,
        "rf_count": len(detections),
        "quality": vars(quality),
        "stacks": stacks,
        "coordinate_frame": "decoded image pixels",
        "axis_role": "X boundary candidates" if view == "straight" else "Y boundary candidates",
        "boundary_count_candidate": len(stacks),
        "unlocalized_detections": len(detections) - sum(s["rf_count"] for s in stacks),
    }


def _features(image: np.ndarray, stack: dict):
    # Limit feature cost on 50 MP inputs; count/band processing retains native pixels.
    scale = min(1.0, 1600 / max(image.shape[:2]))
    small = cv2.resize(image, None, fx=scale, fy=scale) if scale < 1 else image
    mask = np.zeros(small.shape[:2], np.uint8)
    cv2.fillConvexPoly(mask, np.round(np.asarray(stack["polygon"]) * scale).astype(np.int32), 255)
    keypoints, descriptors = cv2.SIFT_create(nfeatures=1500).detectAndCompute(
        cv2.cvtColor(small, cv2.COLOR_BGR2GRAY), mask
    )
    points = np.asarray([k.pt for k in keypoints], np.float32).reshape(-1, 2)
    return points, descriptors


def propose_correspondence(images: dict, views: dict) -> list[dict]:
    """Local feature + planar consistency candidates, NOT physical identity certification.

    Repetitive tray texture or two different faces of a corner may fail; do not
    manufacture an anchor from matching horizontal indices or equal counts.
    """
    features = {s["stack_id"]: _features(images[v], s) for v, data in views.items() for s in data["stacks"]}
    candidates = []
    for side in ("left", "right"):
        for front in views.get("straight", {}).get("stacks", []):
            pa, da = features[front["stack_id"]]
            if da is None or len(da) < 12:
                continue
            for back in views.get(side, {}).get("stacks", []):
                pb, db = features[back["stack_id"]]
                if db is None or len(db) < 12:
                    continue
                pairs = cv2.BFMatcher().knnMatch(da, db, k=2)
                good = [
                    a for pair in pairs if len(pair) == 2 for a, b in [pair] if a.distance < 0.65 * b.distance
                ]
                # One train feature cannot be counted as many independent matches.
                good = list({m.trainIdx: m for m in sorted(good, key=lambda m: -m.distance)}.values())
                if len(good) < 12:
                    continue
                a = np.asarray([pa[m.queryIdx] for m in good])
                b = np.asarray([pb[m.trainIdx] for m in good])
                cv2.setRNGSeed(0)
                matrix, mask = cv2.findHomography(a, b, cv2.RANSAC, 3.0)
                if matrix is None or mask is None or int(mask.sum()) < 12:
                    continue
                inliers = mask.ravel().astype(bool)
                ratio = float(inliers.mean())
                if ratio < 0.6:
                    continue
                candidates.append(
                    {
                        "source": front["stack_id"],
                        "target": back["stack_id"],
                        "method": "SIFT ratio + planar RANSAC",
                        "inliers": int(mask.sum()),
                        "inlier_fraction": ratio,
                        "status": "provisional",
                        "accepted_identity": False,
                        "reason": "Repeated texture and different corner faces need pose/base verification",
                    }
                )
    return candidates


def candidate_scene(images: dict, detections: dict, sop: dict | None = None) -> dict:
    if set(images) != {"left", "right", "straight"} or set(detections) != set(images):
        raise ValueError("LEFT, RIGHT and STRAIGHT evidence required")
    sop = sop or {}
    required = ("vertical_stacks", "orthogonal_layout", "all_positions_observed", "top_base_visible")
    violations = [k for k in required if sop.get(k) is False]
    unknown = [k for k in required if sop.get(k) is not True]
    views = {v: analyze_view(images[v], detections[v], v) for v in images}
    violations += [v + ":image_quality" for v, data in views.items() if not data["quality"]["accepted"]]
    matches = propose_correspondence(images, views)
    stacks = [s for data in views.values() for s in data["stacks"]]
    return {
        "scan_contract": "spatial_3d_beam_v1",
        "status": "OUT_OF_OPERATING_ENVELOPE" if violations else "unresolved",
        "verified": False,
        "x_columns": None,
        "y_rows": None,
        "physical_trays": None,
        "eligible_egg_trays": None,
        "empty_trays": None,
        "unknown_trays": None,
        "views": views,
        "stacks": stacks,
        "view_correspondence": matches,
        "beam_evidence": [s["beam"] for s in stacks],
        "rf_evidence": detections,
        "scene_grid": [],
        "assumptions_used": [],
        "sop_violations": violations,
        "sop_unverified": unknown,
        "rescan": {
            "reason": "Resolve shared stack identity, unseen depth, tray endpoints and egg occupancy",
            "action": "Capture overlapping corner faces, all rows and stack tops/bases",
        },
    }


def assemble_grid(
    observations: list[dict],
    *,
    x_columns: int,
    y_rows: int,
    absent_cells: tuple = (),
    complete_coverage: bool = False,
) -> dict:
    """Accounting core for externally resolved geometry and layer evidence.

    Not used to convert image candidates into verified totals. Test fixtures use
    explicit synthetic correspondences. Coordinates are supplied by a reviewed
    geometry stage, never horizontal sorting. Conflicting repeats stay unresolved.
    """
    if (
        type(x_columns) is not int
        or type(y_rows) is not int
        or not (1 <= x_columns <= 100 and 1 <= y_rows <= 100)
    ):
        raise ValueError("Bounded positive grid dimensions required")
    cells, correspondence, unresolved = {}, [], []
    for observation in observations:
        x, y = observation["x"], observation["y"]
        if type(x) is not int or type(y) is not int or not (0 <= x < x_columns and 0 <= y < y_rows):
            raise ValueError("Observation outside grid")
        if not observation.get("geometry_evidence"):
            raise ValueError("Physical correspondence evidence required")
        layers = observation["layers"]
        if any(s not in {"filled", "empty", "unknown"} for s in layers):
            raise ValueError("Invalid occupancy")
        key = (x, y)
        correspondence.append(
            {
                "observation_id": observation["id"],
                "cell": [x, y],
                "evidence": observation["geometry_evidence"],
            }
        )
        if key not in cells:
            cells[key] = list(layers)
        elif cells[key] != layers:
            unresolved.append({"cell": [x, y], "reason": "Conflicting repeated layer evidence"})
    absent = set(map(tuple, absent_cells))
    if any(len(p) != 2 or not (0 <= p[0] < x_columns and 0 <= p[1] < y_rows) for p in absent):
        raise ValueError("Absent cell outside grid")
    if absent.intersection(cells):
        raise ValueError("Cell cannot be both absent and present")
    missing = [
        (x, y)
        for y in range(y_rows)
        for x in range(x_columns)
        if (x, y) not in cells and (x, y) not in absent
    ]
    physical = sum(len(layers) for layers in cells.values())
    filled = sum(layers.count("filled") for layers in cells.values())
    empty = sum(layers.count("empty") for layers in cells.values())
    unknown = sum(layers.count("unknown") for layers in cells.values())
    complete = complete_coverage and not missing and not unresolved
    return {
        "x_columns": x_columns,
        "y_rows": y_rows,
        "physical_trays": physical if complete else None,
        "eligible_egg_trays": filled if complete and not unknown else None,
        "empty_trays": empty if complete and not unknown else None,
        "unknown_trays": unknown if complete else None,
        "observed_filled_layers": filled,
        "verified": False,
        "scene_grid": [
            {
                "x": x,
                "y": y,
                "stack_present": True,
                "physical_layer_count": len(layers),
                "layers": [{"z": z, "occupancy": state} for z, state in enumerate(layers)],
            }
            for (x, y), layers in sorted(cells.items())
        ],
        "absent_cells": [list(p) for p in sorted(absent)],
        "view_correspondence": correspondence,
        "unresolved": unresolved,
        "rescan": bool(missing or unresolved or unknown or not complete_coverage),
        "unobserved_cells": [list(p) for p in missing],
        "assumptions_used": [],
    }
