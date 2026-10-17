"""Walk-overfill experiment (2026-10-15): does the walk counter's gap filling, not the detector, make the
inconsistent layer counts?

The 2026-10-15 verifier found that on the 62 reviewed target polygons with 3+ boxes (arm B of
scripts/experiment_stack_faces.py), 12 polygons have walk > span + 1 and hold 74 of the 92 filled layers.
This script re-counts the same saved boxes with five walk variants and scores them in two separate stages:

  1. LABEL-FREE (decides the variant): equal-extent pairs in one photo, walk-span agreement, the same
     physical stack across views, and the 53 reference columns' internal consistency (their reference
     values are NOT read). A pre-declared rule (choose_variant) picks the variant from these numbers only.
  2. LABEL-BASED (secondary check, computed after the choice is fixed): the 22 labelled clusters, the
     9 polygon photos with a usable label and the user-reported per-stack values, with leak-free / leaked
     and physical n.

Variants (all keep the deployed column grouping, duplicate rule and MAX_FILLED_PER_GAP):
  V0  deployed walk: backend/app/vision/layer_span.walk_layers, unchanged
  V1  cap: V0's count clipped to [span - 1, span + 1]
  V2  fallback: span when |V0 - span| > 1, else V0
  V3  strict fill: a gap is filled only when |gap/pitch - steps| <= 0.25 and the local pitch is within 15%
      of the global pitch; otherwise it counts as one step
  V4  observed pitch: the local pitch follows only gaps the walk read as one layer; filled sub-gaps no
      longer feed it (the deployed walk feeds gap/steps back, which ratchets the pitch down to its 0.6 floor
      and then splits every normal gap in two)

Each variant is applied by swapping the walk function that layer_span.count_layers_by_span and
stack_separation.column_record call (use_walk); everything else (grouping, gate, block-model flags) is the
deployed code. Nothing in backend/ is modified.

Run from the repository root (PYTHONPATH must provide numpy):
  python scripts/experiment_walk_fill.py [--out DIR]
Default DIR: reports/experiment-walk-fill-20261015 (writes results.json there).
"""

from __future__ import annotations

import argparse
import csv
import json
import statistics
import sys
from collections import Counter
from contextlib import contextmanager
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "backend"))
sys.path.insert(0, str(REPO / "scripts"))

import evaluate_labelled as ev  # noqa: E402
import experiment_stack_faces as sf  # noqa: E402
from app.vision import layer_span, stack_separation  # noqa: E402
from app.vision.layer_span import MAX_FILLED_PER_GAP, count_layers_by_span  # noqa: E402

DEFAULT_OUT = REPO / "reports" / "experiment-walk-fill-20261015"
REFERENCE_CSV = REPO / "reports" / "field-labelled-20261007" / "per_stack_counts.csv"
DATASET_MANIFEST = REPO / "datasets" / "field-2026-10" / "labelled-20261007" / "manifest.json"
FIELD_REPLAYS = REPO / "reports" / "field-scans-20261013" / "replay"
WAREHOUSE4 = REPO / "reports" / "staging-block-20261008" / "scan-99block-walk2.json"

DEPLOYED_WALK = layer_span.walk_layers  # captured before any swap
STRICT_RESIDUAL = 0.25  # V3: |gap/pitch - steps| must be at most this to fill
STRICT_PITCH_TOL = 0.15  # V3: local pitch within this fraction of the global pitch to fill
VARIANTS = ("V0", "V1", "V2", "V3", "V4")
VARIANT_TEXT = {
    "V0": "deployed walk (layer_span.walk_layers)",
    "V1": "V0 clipped to [span - 1, span + 1]",
    "V2": "span when |V0 - span| > 1, else V0",
    "V3": f"fill only when |gap/pitch - steps| <= {STRICT_RESIDUAL} and local pitch within "
    f"{round(STRICT_PITCH_TOL * 100)}% of global; else one step",
    "V4": "local pitch from one-layer gaps only (filled sub-gaps do not feed the pitch)",
}
USES_SPAN = {"V0": False, "V1": True, "V2": True, "V3": False, "V4": False}

# (c) cross-view stability: the views named in the task. ef823816 LEFT repeats the RIGHT face (audit), so it
# is left out of the criterion; it and the 99-block free end (walk-development photos) are shown separately.
CROSS_VIEW_IMAGES = (
    "scan-9b4c783e-straight",
    "scan-9b4c783e-left",
    "scan-9b4c783e-right",
    "scan-30aca6a1-straight",
    "scan-ef823816-straight",
    "scan-ef823816-right",
)
CROSS_VIEW_SUPPLEMENT = {
    "ef823816 LEFT vs RIGHT (same face photographed twice)": ("scan-ef823816-right", "scan-ef823816-left"),
    "G01 (4,0) free end: img-01, img-32, warehouse-4 (walk-development photos)": (
        "labelled-img-01",
        "labelled-img-32",
        "warehouse-image-4",
    ),
}
# Photos that show the same physical face: used only to state physical n for the equal-extent pairs.
SAME_FACE = {"scan-30aca6a1-straight": "scan-9b4c783e-straight", "scan-ef823816-left": "scan-ef823816-right"}
# Latest saved replay of each multi-view set (paths only; no label is read for the block results).
BLOCK_REPLAYS = {
    "99-block substituted trio": "reports/staging-block-20261008/scan-99block-walk2.json",
    "mechanics trio": "reports/staging-block-20261008/scan-mech-walk.json",
    "30aca6a1 (13 Oct)": "reports/eval-20261015/staging47-replay/30aca6a1-56da-4564-ac09-93de66c4404d.json",
    "ef823816 (13 Oct)": "reports/eval-20261015/staging47-replay/ef823816-899d-4e97-9614-10f1ec47c25a.json",
    "9b4c783e (13 Oct)": "reports/eval-20261015/staging47-replay/9b4c783e-7edb-43ed-b7d2-2f8eed889f60.json",
    "f81c04d7 (13 Oct)": "reports/eval-20261015/staging47-replay/f81c04d7-5fec-4d64-aa8c-54098abf2415.json",
}


# ---------------------------------------------------------------- walk variants (no labels)


def span_from_ys(ys, height: float) -> int:
    """count_layers_by_span's span count for one column (same arithmetic)."""
    ys = np.sort(np.asarray(ys, dtype=float))
    if not len(ys):
        return 0
    gaps = np.diff(ys)
    real = gaps[gaps > 0.5 * height]
    pitch = float(np.median(real)) if len(real) else float(height)
    return int(round((ys[-1] - ys[0]) / pitch)) + 1


def walk(
    ys, height: float, *, strict: tuple[float, float] | None = None, observed_pitch: bool = False
) -> dict:
    """layer_span.walk_layers with two optional changes; with the defaults it is the deployed walk, step for
    step.

    strict=(residual, pitch_tol): fill a gap only when |gap/pitch - steps| <= residual and
    |pitch/global - 1| <= pitch_tol, else count it as one step (V3).
    observed_pitch: the local pitch is the clamped median of the last 3 gaps read as one layer (V4); the
    deployed walk uses the last 3 entries of gap/steps, filled sub-gaps included.
    """
    ys = sorted(float(y) for y in ys)
    if not ys:
        return {
            "count": 0,
            "gaps": [],
            "duplicates": 0,
            "filled": 0,
            "unresolved_gaps": 0,
            "perspective_gradient": None,
            "declined_fills": 0,
        }
    raw_gaps = np.diff(ys)
    real = raw_gaps[raw_gaps > 0.5 * height]
    global_pitch = float(np.median(real)) if len(real) else float(height)
    pitch = global_pitch
    count, duplicates, filled, unresolved, declined = 1, 0, 0, 0, 0
    gaps, single = [], []
    last = ys[0]
    for y in ys[1:]:
        gap = y - last
        if gap < 0.65 * pitch:
            duplicates += 1
            continue
        steps = max(1, int(round(gap / pitch)))
        last = y
        if steps - 1 > MAX_FILLED_PER_GAP:
            unresolved += 1
            count += 1
            continue
        if steps > 1 and strict is not None:
            residual, tol = strict
            if abs(gap / pitch - steps) > residual or abs(pitch / global_pitch - 1.0) > tol:
                steps = 1
                declined += 1
        if steps > 1:
            filled += steps - 1
        else:
            single.append(gap)
        count += steps
        gaps.extend([gap / steps] * steps)
        track = single if observed_pitch else gaps
        if track:
            pitch = float(min(max(np.median(track[-3:]), 0.6 * global_pitch), 1.4 * global_pitch))
    gradient = None
    if len(gaps) >= 6:
        third = max(2, len(gaps) // 3)
        gradient = round(float(np.median(gaps[:third]) / np.median(gaps[-third:])), 3)
    return {
        "count": count,
        "gaps": [round(g, 2) for g in gaps],
        "duplicates": duplicates,
        "filled": filled,
        "unresolved_gaps": unresolved,
        "perspective_gradient": gradient,
        "declined_fills": declined,
    }


def _adjust(base: dict, count: int) -> dict:
    accepted = base["count"] - base["filled"]  # boxes the walk kept as layers
    return {**base, "count": count, "filled": max(0, count - accepted), "deployed_count": base["count"]}


def walk_cap(ys, height):
    """V1: the deployed walk clipped to [span - 1, span + 1]."""
    base = DEPLOYED_WALK(ys, height)
    if not len(ys):
        return _adjust(base, 0)
    span = span_from_ys(ys, height)
    return _adjust(base, min(max(base["count"], span - 1), span + 1))


def walk_fallback(ys, height):
    """V2: the span count when the deployed walk and span differ by more than one layer."""
    base = DEPLOYED_WALK(ys, height)
    if not len(ys):
        return _adjust(base, 0)
    span = span_from_ys(ys, height)
    return _adjust(base, span if abs(base["count"] - span) > 1 else base["count"])


def walk_strict(ys, height):
    """V3: stricter fill (residual and local-pitch conditions)."""
    return walk(ys, height, strict=(STRICT_RESIDUAL, STRICT_PITCH_TOL))


def walk_observed_pitch(ys, height):
    """V4: local pitch from observed one-layer gaps only."""
    return walk(ys, height, observed_pitch=True)


WALKS = {
    "V0": DEPLOYED_WALK,
    "V1": walk_cap,
    "V2": walk_fallback,
    "V3": walk_strict,
    "V4": walk_observed_pitch,
}


@contextmanager
def use_walk(variant: str):
    """Make layer_span.count_layers_by_span and stack_separation.column_record call this variant's walk."""
    fn = WALKS[variant]
    saved = (layer_span.walk_layers, stack_separation.walk_layers)
    layer_span.walk_layers = fn
    stack_separation.walk_layers = fn
    try:
        yield fn
    finally:
        layer_span.walk_layers, stack_separation.walk_layers = saved


# ---------------------------------------------------------------- inputs (no labels)


def _load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def polygon_photos():
    ann = _load(sf.ANNOTATIONS)
    out = []
    for im in ann["images"]:
        boxes = sf.load_detections(im["detections_path"])
        owner, _ = sf.assign(boxes, im["polygons"])
        out.append((im, boxes, owner))
    return out


def reference_columns():
    """(image id, column index) of the 53 resolved reference columns. Only the row's position is read; the
    reference value (assistant_count) and its basis are not."""
    with open(REFERENCE_CSV, encoding="utf-8") as fh:
        return [(int(r["image"]), int(r["col"])) for r in csv.DictReader(fh) if r["assistant_count"].strip()]


def all_photos():
    """Every photo with saved boxes and known size: 52 labelled photos, warehouse image-4, 12 field-scan views
    of 13 Oct, MUTAA image-07. Returns [(photo id, source, detections, width, height)]."""
    dims = {im["id"]: (im["width"], im["height"]) for im in _load(DATASET_MANIFEST)["images"]}
    labelled, _ = ev.load_labelled_detections()
    photos = [
        (f"labelled-img-{i:02d}", "labelled-20261007", dets, *dims[i])
        for i, (dets, _) in sorted(labelled.items())
    ]
    wh = _load(WAREHOUSE4)["views"]["left"]
    photos.append(
        (
            "warehouse-image-4",
            "warehouse-20260923",
            wh["detections"],
            wh["image"]["width"],
            wh["image"]["height"],
        )
    )
    for f in sorted(FIELD_REPLAYS.glob("*.json")):
        resp = _load(f)
        for view in ev.VIEWS:
            v = resp["views"][view]
            img = v.get("image") or {}
            photos.append(
                (
                    f"scan-{f.stem[:8]}-{view}",
                    "field-scans-20261013",
                    v.get("detections") or [],
                    img.get("width"),
                    img.get("height"),
                )
            )
    ann = {im["id"]: im for im in _load(sf.ANNOTATIONS)["images"]}
    m07 = ann["mutaa-image-07"]
    photos.append(
        (
            "mutaa-image-07",
            "mutaa-20260916",
            sf.load_detections(m07["detections_path"]),
            m07["width"],
            m07["height"],
        )
    )
    return photos


# ---------------------------------------------------------------- label-free criteria


def _phys(entry, image_id):
    key = entry.get("physical_stack")
    return key.split(" ")[0] if key else f"{image_id}:{entry['polygon']}"


def polygon_counts(photos, variant):
    """Arm B under one variant: per target polygon walk/span/filled, plus the equal-extent pairs."""
    rows, pairs = [], []
    with use_walk(variant):
        for im, boxes, owner in photos:
            b = sf.arm_b(boxes, owner, im)
            for e in b["polygons"]:
                if e["role"] != "target":
                    continue
                rows.append(
                    {
                        "image": im["id"],
                        "polygon": e["polygon"],
                        "physical": _phys(e, im["id"]),
                        "boxes": e["boxes"],
                        "count": e["count"],
                        "base_visible": e["base_visible"],
                        "depth_row": e["depth_row"],
                        "face_view": e["face_view"],
                        **(
                            {
                                k: e[k]
                                for k in (
                                    "walk_count",
                                    "span_count",
                                    "walk_filled",
                                    "box_pitch_ratio",
                                    "pitch_px",
                                    "y_first",
                                    "y_last",
                                )
                            }
                            if e["boxes"] >= 3
                            else {}
                        ),
                    }
                )
            pairs.extend(sf.equal_extent_pairs(im, b))
    return rows, pairs


def equal_extent_summary(pairs, rows, pitch_frac):
    phys = {(r["image"], r["polygon"]): r["physical"] for r in rows}

    def key(p):
        return frozenset((phys[(p["image"], p["pair"][0])], phys[(p["image"], p["pair"][1])]))

    def physical(sel):
        keys = {key(p) for p in sel}
        return {
            "physical_pairs": len(keys),
            "physical_pairs_diff_gt1_in_any_photo": len({key(p) for p in sel if p["walk_diff"] > 1}),
            "distinct_faces": len({SAME_FACE.get(p["image"], p["image"]) for p in sel}),
        }

    out = {
        "pairs": len(pairs),
        "photos": len({p["image"] for p in pairs}),
        "photos_distinct_faces": len({SAME_FACE.get(p["image"], p["image"]) for p in pairs}),
        "physical_pairs": len({key(p) for p in pairs}),
        "diff_gt1": sum(p["walk_diff"] > 1 for p in pairs),
        "diff_gt0": sum(p["walk_diff"] > 0 for p in pairs),
        "abs_diff_sum": sum(p["walk_diff"] for p in pairs),
        "diff_max": max((p["walk_diff"] for p in pairs), default=None),
    }
    out["physical"] = physical(pairs)
    for name, sel in (
        ("large_scale_pitch_ge_3pct", lambda p: pitch_frac[p["image"]] >= 0.03),
        ("small_scale_pitch_lt_3pct", lambda p: pitch_frac[p["image"]] < 0.03),
    ):
        s = [p for p in pairs if sel(p)]
        out[name] = {
            "pairs": len(s),
            "photos": len({p["image"] for p in s}),
            "diff_gt1": sum(p["walk_diff"] > 1 for p in s),
            "abs_diff_sum": sum(p["walk_diff"] for p in s),
            "diff_max": max((p["walk_diff"] for p in s), default=None),
            **physical(s),
        }
    return out


def walk_span_summary(rows, deployed_rows):
    full = [r for r in rows if r["boxes"] >= 3]
    v0 = {(r["image"], r["polygon"]): r for r in deployed_rows if r["boxes"] >= 3}
    over = [
        r
        for r in full
        if v0[(r["image"], r["polygon"])]["walk_count"] > v0[(r["image"], r["polygon"])]["span_count"] + 1
    ]
    return {
        "polygons": len(full),
        "physical_stacks": len({r["physical"] for r in full}),
        "count_gt_span_plus1": sum(r["walk_count"] > r["span_count"] + 1 for r in full),
        "count_lt_span_minus1": sum(r["walk_count"] < r["span_count"] - 1 for r in full),
        "abs_count_minus_span_sum": sum(abs(r["walk_count"] - r["span_count"]) for r in full),
        "filled_layers": sum(r["walk_filled"] for r in full),
        "polygons_with_fills": sum(r["walk_filled"] > 0 for r in full),
        "layers": sum(r["walk_count"] for r in full),
        "polygons_changed_vs_V0": sum(
            r["walk_count"] != v0[(r["image"], r["polygon"])]["walk_count"] for r in full
        ),
        "on_V0_overfill_polygons": {
            "polygons": len(over),
            "filled": sum(r["walk_filled"] for r in over),
            "count_minus_span": [r["walk_count"] - r["span_count"] for r in over],
        },
    }


def overfill_decomposition(deployed_rows):
    """The verifier's label-free split of V0's filled layers (reproduced, not new)."""
    full = [r for r in deployed_rows if r["boxes"] >= 3]
    over = [r for r in full if r["walk_count"] > r["span_count"] + 1]
    regular = [r for r in over if r["box_pitch_ratio"] >= sf.BOX_PITCH_MIN]
    under = [r for r in full if r["span_count"] > r["walk_count"] + 1]
    return {
        "polygons_3plus_boxes": len(full),
        "filled_total": sum(r["walk_filled"] for r in full),
        "walk_gt_span_plus1": {
            "polygons": len(over),
            "filled": sum(r["walk_filled"] for r in over),
            "photos": sorted({r["image"] for r in over}),
            "rows": [
                {
                    k: r[k]
                    for k in (
                        "image",
                        "polygon",
                        "boxes",
                        "span_count",
                        "walk_count",
                        "walk_filled",
                        "box_pitch_ratio",
                    )
                }
                for r in over
            ],
        },
        "of_which_regular_boxes": {
            "polygons": len(regular),
            "filled": sum(r["walk_filled"] for r in regular),
        },
        "span_gt_walk_plus1": {
            "polygons": len(under),
            "rows": [
                {k: r[k] for k in ("image", "polygon", "boxes", "span_count", "walk_count")} for r in under
            ],
        },
    }


def cross_view(rows, images):
    by_key = {}
    for r in rows:
        if r["image"] in images and r["boxes"] > 0 and r["base_visible"]:
            by_key.setdefault(r["physical"], []).append(r)
    stacks = []
    for key, es in sorted(by_key.items()):
        if len({e["image"] for e in es}) < 2:
            continue
        vals = [e["count"] for e in es]
        stacks.append(
            {
                "physical_stack": key,
                "views": {f"{e['image']}:{e['polygon']}": e["count"] for e in es},
                "spread": max(vals) - min(vals),
            }
        )
    return {
        "stacks": len(stacks),
        "spread_gt1": sum(s["spread"] > 1 for s in stacks),
        "spread_gt0": sum(s["spread"] > 0 for s in stacks),
        "spread_sum": sum(s["spread"] for s in stacks),
        "spread_max": max((s["spread"] for s in stacks), default=None),
        "per_stack": stacks,
    }


def reference_consistency(ref_cols, detections, variant, deployed=None):
    """The 53 reference columns without their reference values: span agreement, fills, change vs V0, and
    equal-extent agreement between reference columns of one photo (the 0.6-pitch rule of the polygon
    pairs)."""
    with use_walk(variant):
        cols = {i: count_layers_by_span(detections[i][0]) for i in sorted({i for i, _ in ref_cols})}
    recs = [
        {
            "image": i,
            "col": c,
            **{
                k: cols[i][c - 1][k]
                for k in ("walk_count", "span_count", "walk_filled", "pitch_px", "y_first", "y_last")
            },
        }
        for i, c in ref_cols
    ]
    pairs = []
    for i in sorted(cols):
        mine = [r for r in recs if r["image"] == i]
        for a_i, a in enumerate(mine):
            for b in mine[a_i + 1 :]:
                tol = 0.6 * max(a["pitch_px"], b["pitch_px"])
                if abs(a["y_first"] - b["y_first"]) <= tol and abs(a["y_last"] - b["y_last"]) <= tol:
                    pairs.append(
                        {
                            "image": i,
                            "cols": [a["col"], b["col"]],
                            "counts": [a["walk_count"], b["walk_count"]],
                            "diff": abs(a["walk_count"] - b["walk_count"]),
                        }
                    )
    out = {
        "columns": len(recs),
        "photos": len(cols),
        "count_ne_span": sum(r["walk_count"] != r["span_count"] for r in recs),
        "count_minus_span_gt1": sum(abs(r["walk_count"] - r["span_count"]) > 1 for r in recs),
        "filled_layers": sum(r["walk_filled"] for r in recs),
        "columns_with_fills": sum(r["walk_filled"] > 0 for r in recs),
        "equal_extent_pairs": len(pairs),
        "equal_extent_diff_gt0": sum(p["diff"] > 0 for p in pairs),
        "equal_extent_diff_gt1": sum(p["diff"] > 1 for p in pairs),
        "equal_extent_abs_diff_sum": sum(p["diff"] for p in pairs),
        "counts": [[r["image"], r["col"], r["walk_count"]] for r in recs],
    }
    if deployed is not None:
        before = {(i, c): n for i, c, n in deployed["counts"]}
        changed = [
            [r["image"], r["col"], before[(r["image"], r["col"])], r["walk_count"]]
            for r in recs
            if r["walk_count"] != before[(r["image"], r["col"])]
        ]
        out["changed_vs_V0"] = len(changed)
        out["changed_columns"] = changed
    return out


def outcomes(photos, variant):
    out = {}
    with use_walk(variant):
        for pid, source, dets, w, h in photos:
            pred = ev.predict_face(dets, w, h)
            out[pid] = {
                "source": source,
                "outcome": pred["outcome"],
                "total": pred["predicted_total"],
                "walk": [c["walk_count"] for c in pred["columns"]],
                "flags": sorted({r.split(" (")[0].split(";")[0] for r in pred["flag_reasons"]}),
            }
    return out


def outcome_changes(base, other):
    rows = []
    for pid in sorted(base):
        a, b = base[pid], other[pid]
        if a["outcome"] != b["outcome"] or a["total"] != b["total"]:
            rows.append(
                {
                    "photo": pid,
                    "source": a["source"],
                    "V0": [a["outcome"], a["total"]],
                    "variant": [b["outcome"], b["total"]],
                    "V0_walk": a["walk"],
                    "variant_walk": b["walk"],
                    "V0_flags": a["flags"],
                    "variant_flags": b["flags"],
                }
            )
    newly_acc = [r for r in rows if r["V0"][0] != "accepted" and r["variant"][0] == "accepted"]
    newly_with = [r for r in rows if r["V0"][0] == "accepted" and r["variant"][0] != "accepted"]
    acc_changed = [
        r for r in rows if r["V0"][0] == "accepted" == r["variant"][0] and r["V0"][1] != r["variant"][1]
    ]
    return {
        "photos": len(base),
        "accepted": sum(o["outcome"] == "accepted" for o in other.values()),
        "newly_accepted": len(newly_acc),
        "newly_withheld": len(newly_with),
        "accepted_both_total_changed": len(acc_changed),
        "withheld_both_total_changed": sum(
            r["V0"][0] != "accepted" and r["variant"][0] != "accepted" for r in rows
        ),
        "newly_accepted_photos": [r["photo"] for r in newly_acc],
        "newly_withheld_photos": [r["photo"] for r in newly_with],
        "changes": rows,
    }


def block_results(variant):
    out = {}
    with use_walk(variant):
        for name, path in BLOCK_REPLAYS.items():
            resp = _load(REPO / path)
            views = {
                v: {
                    "detections": resp["views"][v].get("detections") or [],
                    "image": resp["views"][v].get("image"),
                }
                for v in ev.VIEWS
            }
            blk = ev.predict_block(views)
            out[name] = {
                "status": blk["status"],
                "total_trays": blk["total_trays"],
                "walk_by_view": blk["walk_by_view"],
                "conflicts": len(blk["conflicts"]),
                "ambiguities": len(blk["ambiguities"]),
            }
    return out


def choose_variant(crit):
    """Pre-declared, label-free decision rule (fixed before any label-based number was computed).

    Eligible: (G1) keeps the span-walk check independent (the count does not use span: excludes V1, V2,
    which would make the deployed 'span/walk disagree' flag impossible); (G2) cross-view stacks with
    spread > 1 not more than V0; (G3) reference-column equal-extent pairs differing by > 1 not more than V0.
    Rank eligible variants by (a) equal-extent pairs differing by > 1, then (a) sum of |difference|, then
    reference columns changed vs V0. A walk change is recommended for a trial only if the winner is not V0.
    """
    v0 = crit["V0"]
    eligible, reasons = [], {}
    for v in VARIANTS:
        c = crit[v]
        why = []
        if USES_SPAN[v]:
            why.append("count uses span: the span/walk disagreement flag can no longer fire")
        if c["cross_view"]["spread_gt1"] > v0["cross_view"]["spread_gt1"]:
            why.append("more cross-view stacks with spread > 1 than V0")
        if c["reference"]["equal_extent_diff_gt1"] > v0["reference"]["equal_extent_diff_gt1"]:
            why.append("more reference equal-extent pairs differing by > 1 than V0")
        reasons[v] = why
        if not why:
            eligible.append(v)

    def key(v):
        return (
            crit[v]["equal_extent"]["diff_gt1"],
            crit[v]["equal_extent"]["abs_diff_sum"],
            crit[v]["reference"].get("changed_vs_V0", 0),
        )

    ranked = sorted(eligible, key=lambda v: (key(v), VARIANTS.index(v)))
    winner = ranked[0]
    return {
        "rule": choose_variant.__doc__.strip(),
        "ineligible_reasons": reasons,
        "eligible": eligible,
        "ranking": [{"variant": v, "key": list(key(v))} for v in ranked],
        "chosen": winner,
        "walk_change_for_trial": winner != "V0",
    }


def label_free():
    photos = polygon_photos()
    pitch_frac = {}
    rows_by, pairs_by = {}, {}
    for v in VARIANTS:
        rows_by[v], pairs_by[v] = polygon_counts(photos, v)
    for im, _, _ in photos:
        f = [r for r in rows_by["V0"] if r["image"] == im["id"] and r["boxes"] >= 3]
        if f:
            pitch_frac[im["id"]] = round(statistics.median(r["pitch_px"] for r in f) / im["height"], 4)
    pair_sets = {v: [(p["image"], tuple(p["pair"])) for p in pairs_by[v]] for v in VARIANTS}
    assert all(pair_sets[v] == pair_sets["V0"] for v in VARIANTS), (
        "pair definition must not depend on the walk"
    )
    photo_boxes, _ = ev.load_labelled_detections()  # boxes only; the loader reads no label
    ref_cols = reference_columns()
    ref_v0 = reference_consistency(ref_cols, photo_boxes, "V0")
    every = all_photos()
    out_v0 = outcomes(every, "V0")
    crit, pair_table = {}, []
    for v in VARIANTS:
        rows = rows_by[v]
        crit[v] = {
            "description": VARIANT_TEXT[v],
            "equal_extent": equal_extent_summary(pairs_by[v], rows, pitch_frac),
            "walk_span": walk_span_summary(rows, rows_by["V0"]),
            "walk_span_note": (
                "tautological: the count is forced within 1 of span" if USES_SPAN[v] else None
            ),
            "cross_view": cross_view(rows, CROSS_VIEW_IMAGES),
            "cross_view_supplement": {
                name: cross_view(rows, imgs) for name, imgs in CROSS_VIEW_SUPPLEMENT.items()
            },
            "reference": ref_v0 if v == "V0" else reference_consistency(ref_cols, photo_boxes, v, ref_v0),
        }
    for i, p in enumerate(pairs_by["V0"]):
        pair_table.append(
            {
                "image": p["image"],
                "pair": p["pair"],
                "pitch_frac": pitch_frac[p["image"]],
                "span": p["span"],
                **{v: pairs_by[v][i]["walk"] for v in VARIANTS},
            }
        )
    ref_v0["changed_vs_V0"] = 0
    choice = choose_variant(crit)
    outcome_by = {v: outcomes(every, v) if v != "V0" else out_v0 for v in VARIANTS}
    photo_sources = Counter(p[1] for p in every)
    flags_v0_kept = {}
    for v in ("V1", "V2"):
        # If the deployed flag stayed on the deployed walk, V1/V2 change no outcome: only totals of photos
        # that are withheld anyway (their flagged columns) would differ.
        ch = outcome_changes(out_v0, outcome_by[v])
        flags_v0_kept[v] = {
            "outcomes_changed": 0,
            "withheld_photo_totals_changed": sum(r["V0"][0] != "accepted" for r in ch["changes"]),
            "accepted_photo_totals_changed": sum(r["V0"][0] == "accepted" for r in ch["changes"]),
        }
    return {
        "variants": VARIANT_TEXT,
        "overfill_decomposition_V0": overfill_decomposition(rows_by["V0"]),
        "criteria": crit,
        "equal_extent_pairs": pair_table,
        "pitch_frac_per_photo": pitch_frac,
        "polygon_counts": [
            {
                "image": r["image"],
                "polygon": r["polygon"],
                "physical": r["physical"],
                "boxes": r["boxes"],
                "span": r.get("span_count"),
                "box_pitch_ratio": r.get("box_pitch_ratio"),
                **{
                    v: next(
                        x for x in rows_by[v] if (x["image"], x["polygon"]) == (r["image"], r["polygon"])
                    ).get("walk_count", r["count"])
                    for v in VARIANTS
                },
                **{
                    f"{v}_filled": next(
                        x for x in rows_by[v] if (x["image"], x["polygon"]) == (r["image"], r["polygon"])
                    ).get("walk_filled")
                    for v in VARIANTS
                },
            }
            for r in rows_by["V0"]
            if r["boxes"] >= 3
        ],
        "choice": choice,
        "outcomes": {
            "photos": len(every),
            "by_source": dict(sorted(photo_sources.items())),
            "accepted_V0": sum(o["outcome"] == "accepted" for o in out_v0.values()),
            "flag_on_variant": {v: outcome_changes(out_v0, outcome_by[v]) for v in VARIANTS if v != "V0"},
            "flag_kept_on_deployed_walk": flags_v0_kept,
        },
        "block_results": {v: block_results(v) for v in VARIANTS},
        "_outcomes_by_variant": outcome_by,
    }


# ------------------------------------------------------- stage 2: labels (secondary, after the choice)


def _summary(rows):
    n = len(rows)
    acc = [r for r in rows if r["outcome"] == "accepted"]
    return {
        "n": n,
        "exact_ungated": sum(r["error"] == 0 for r in rows),
        "accepted": len(acc),
        "accepted_correct": sum(r["error"] == 0 for r in acc),
        "accepted_wrong": sum(r["error"] != 0 for r in acc),
        "withheld": n - len(acc),
        "abs_error_sum": sum(abs(r["error"]) for r in rows),
        "mae": round(statistics.fmean(abs(r["error"]) for r in rows), 2) if rows else None,
    }


def score_clusters(manifest, outcome_by):
    """The 24 usable labelled photos: near-duplicate clusters (22, lowest id) and blocks (19, lowest id per
    group)."""
    out = {}
    for v in VARIANTS:
        rows = []
        for p in sorted(manifest["photos"], key=lambda p: p["label_id"]):
            o = outcome_by[v][f"labelled-img-{p['label_id']:02d}"]
            rows.append(
                {
                    "label_id": p["label_id"],
                    "label": p["label_value"],
                    "tier": p["tier"],
                    "cluster": p["near_duplicate_cluster"],
                    "group": p["group_id"],
                    "leak": p["detector_leak"],
                    # manifest tags only: gate tuning set, walk reference photos, 9 Oct walk development
                    # (img-01, img-32) and 0.4.8 capture-gate orientation development (img-46)
                    "used_in_tuning": ev.used_in_logic_tuning(p),
                    "outcome": o["outcome"],
                    "total": o["total"],
                    "error": o["total"] - p["label_value"],
                }
            )
        reps, blocks = {}, {}
        for r in rows:
            reps.setdefault(r["cluster"], r)
            blocks.setdefault(r["group"], r)
        reps, blocks = list(reps.values()), list(blocks.values())
        out[v] = {
            "clusters_all": _summary(reps),
            "clusters_leak_free": _summary([r for r in reps if r["leak"] == "leak_free"]),
            "clusters_leaked": _summary([r for r in reps if r["leak"] != "leak_free"]),
            "clusters_not_used_in_tuning": _summary([r for r in reps if not r["used_in_tuning"]]),
            "blocks_all": _summary(blocks),
            "blocks_leak_free": _summary([r for r in blocks if r["leak"] == "leak_free"]),
            "_rows": reps,
        }
    base = {r["label_id"]: r for r in out["V0"]["_rows"]}
    for v in VARIANTS:
        out[v]["changed_clusters_vs_V0"] = [
            {
                "label_id": r["label_id"],
                "label": r["label"],
                "leak": r["leak"],
                "V0": [
                    base[r["label_id"]]["outcome"],
                    base[r["label_id"]]["total"],
                    base[r["label_id"]]["error"],
                ],
                "variant": [r["outcome"], r["total"], r["error"]],
            }
            for r in out[v]["_rows"]
            if (r["outcome"], r["total"]) != (base[r["label_id"]]["outcome"], base[r["label_id"]]["total"])
        ]
    for v in VARIANTS:
        out[v].pop("_rows")
    return out


def score_polygon_photos(photos, manifest):
    """The 9 polygon photos with a usable label: A (deployed grouping) and B (polygons) totals per variant."""
    by_id = {p["label_id"]: p for p in manifest["photos"]}
    wh = next(c for c in manifest["per_stack"] if c["case"] == sf.PER_STACK_IMAGES["warehouse-image-4"])
    rows = []
    for im, boxes, owner in photos:
        iid = im["id"]
        if iid in sf.LABELLED_IMAGES:
            p = by_id[sf.LABELLED_IMAGES[iid]]
            label, tier, leak, group = p["label_value"], p["tier"], p["detector_leak"], p["group_id"]
        elif iid in sf.PER_STACK_IMAGES:
            label, tier, leak, group = (
                wh["stacks"][0]["filled"],
                "per-stack (user-confirmed)",
                "not in manifest",
                "G01",
            )
        else:
            continue
        row = {
            "image": iid,
            "label": label,
            "tier": tier,
            "leak": leak,
            "group": group,
            "walk_development": iid in ("labelled-img-32", "warehouse-image-4"),
        }
        for v in VARIANTS:
            with use_walk(v):
                a = ev.predict_face(boxes, im["width"], im["height"])
                b = sf.arm_b(boxes, owner, im)
            row[v] = {
                "A": a["predicted_total"],
                "A_outcome": a["outcome"],
                "B": b["total"],
                "err_A": a["predicted_total"] - label,
                "err_B": b["total"] - label,
            }
        rows.append(row)

    def summ(sel, v):
        return {
            "photos": len(sel),
            "physical_blocks": len({r["group"] for r in sel}),
            "A_exact": sum(r[v]["err_A"] == 0 for r in sel),
            "A_abs_error_sum": sum(abs(r[v]["err_A"]) for r in sel),
            "A_accepted": sum(r[v]["A_outcome"] == "accepted" for r in sel),
            "B_exact": sum(r[v]["err_B"] == 0 for r in sel),
            "B_abs_error_sum": sum(abs(r[v]["err_B"]) for r in sel),
        }

    return {
        "rows": rows,
        "summary": {
            v: {
                "all": summ(rows, v),
                "leak_free": summ([r for r in rows if r["leak"] == "leak_free"], v),
                "not_leak_free": summ([r for r in rows if r["leak"] != "leak_free"], v),
            }
            for v in VARIANTS
        },
        "note": "img-01, img-32 and warehouse image-4 are block G01; img-32 and warehouse-4 are one stack",
    }


def score_per_stack(manifest, labelled):
    out = {}
    for v in VARIANTS:
        with use_walk(v):
            entries = ev.evaluate_per_stack(manifest, labelled)
        obs = [(e, s) for e in entries for s in e["stacks"]]
        out[v] = {
            **ev.per_stack_summary(entries),
            "abs_error_sum": sum(abs(s["walk_minus_filled"]) for _, s in obs),
            "stacks": [
                [e["case"], s["position"], s["user_filled"], s["walk"], e["photo_outcome"]] for e, s in obs
            ],
        }
    return out


def score_reference(crit):
    """The 53 reference columns against their reference values (secondary; 7 of the 53 values were inferred
    from the image label: the basis mentions it)."""
    with open(REFERENCE_CSV, encoding="utf-8") as fh:
        refs = {
            (int(r["image"]), int(r["col"])): (int(r["assistant_count"]), "label" in r["basis"].lower())
            for r in csv.DictReader(fh)
            if r["assistant_count"].strip()
        }
    out = {}
    for v in VARIANTS:
        counts = {(i, c): n for i, c, n in crit[v]["reference"]["counts"]}

        def score(keys, counts=counts):
            return {
                "columns": len(keys),
                "exact": sum(counts[k] == refs[k][0] for k in keys),
                "within_1": sum(abs(counts[k] - refs[k][0]) <= 1 for k in keys),
                "abs_error_sum": sum(abs(counts[k] - refs[k][0]) for k in keys),
            }

        keys = sorted(refs)
        out[v] = {
            "all": score(keys),
            "without_label_derived": score([k for k in keys if not refs[k][1]]),
            "label_derived_rows": sum(refs[k][1] for k in keys),
        }
    return out


def score_not_usable_changes(outcome_by, manifest):
    """Labelled photos the audit marks not usable whose outcome or total changes under V3 or V4 (labels.csv
    value shown; never a headline number)."""
    usable = {p["label_id"] for p in manifest["photos"]}
    with open(sf.LABELS_CSV, encoding="utf-8") as fh:
        values = {int(r["id"]): r["label_total"] for r in csv.DictReader(fh)}
    rows = []
    for v in ("V3", "V4"):
        for pid, o in sorted(outcome_by[v].items()):
            if not pid.startswith("labelled-img-") or int(pid[-2:]) in usable:
                continue
            b = outcome_by["V0"][pid]
            if b["outcome"] != o["outcome"]:
                rows.append(
                    {
                        "variant": v,
                        "photo": pid,
                        "labels_csv_value": values[int(pid[-2:])],
                        "V0": [b["outcome"], b["total"]],
                        "variant_result": [o["outcome"], o["total"]],
                    }
                )
    return rows


def label_based(lf, outcome_by):
    manifest = _load(ev.MANIFEST)
    labelled, _ = ev.load_labelled_detections()
    return {
        "note": "computed after stage 1 fixed the choice; nothing here feeds back into choose_variant",
        "clusters_22": score_clusters(manifest, outcome_by),
        "polygon_photos_9": score_polygon_photos(polygon_photos(), manifest),
        "per_stack_user_reported": score_per_stack(manifest, labelled),
        "reference_columns_53": score_reference(lf["criteria"]),
        "not_usable_outcome_changes": score_not_usable_changes(outcome_by, manifest),
    }


# ---------------------------------------------------------------- main


def run():
    lf = label_free()
    outcome_by = lf.pop("_outcomes_by_variant")
    choice = json.loads(json.dumps(lf["choice"]))  # frozen copy: stage 2 must not change it
    lb = label_based(lf, outcome_by)
    assert lf["choice"] == choice
    return {
        "experiment": "walk-fill variants, 2026-10-15",
        "label_rule": "stage 1 reads no count label; stage 2 reads labels only to score, after the choice",
        "stage_1_label_free": lf,
        "stage_2_label_based": lb,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output directory for results.json")
    args = parser.parse_args(argv)
    results = run()
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "results.json").write_text(
        json.dumps(results, indent=1, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    lf = results["stage_1_label_free"]
    for v in VARIANTS:
        c = lf["criteria"][v]
        print(
            v,
            "pairs>1",
            c["equal_extent"]["diff_gt1"],
            "/",
            c["equal_extent"]["pairs"],
            "sum",
            c["equal_extent"]["abs_diff_sum"],
            "| span>1",
            c["walk_span"]["count_gt_span_plus1"],
            c["walk_span"]["count_lt_span_minus1"],
            "fills",
            c["walk_span"]["filled_layers"],
            "| xview>1",
            c["cross_view"]["spread_gt1"],
            "sum",
            c["cross_view"]["spread_sum"],
            "| ref pairs>1",
            c["reference"]["equal_extent_diff_gt1"],
            "changed",
            c["reference"].get("changed_vs_V0"),
        )
    print("choice:", lf["choice"]["chosen"], lf["choice"]["ranking"])
    lb = results["stage_2_label_based"]
    for v in VARIANTS:
        c = lb["clusters_22"][v]
        print(
            v,
            "clusters",
            c["clusters_all"],
            "| leak-free",
            c["clusters_leak_free"]["accepted_correct"],
            "/",
            c["clusters_leak_free"]["accepted"],
            "| per-stack equal",
            lb["per_stack_user_reported"][v]["walk_equals_user_filled"],
            "| ref exact",
            lb["reference_columns_53"][v]["all"]["exact"],
        )
    return results


if __name__ == "__main__":
    main()
