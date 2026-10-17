"""Stack-face experiment (2026-10-15): is localization, layer counting or cross-view association the bottleneck?

Three arms on the same saved detections (no inference, no network, deterministic):
  A  deployed grouping and counting: layer_span.count_layers_by_span (x-columns of 3+ boxes, walk counter)
     with the block model's column reasons and the capture gate, total = sum of walk counts over the
     photo's columns, exactly as scripts/evaluate_labelled.py (predict_face) does;
  B  counting inside the reviewed target polygons: each box goes to the polygon containing its centre,
     one walk per polygon (column_record), target polygons only; < 3 boxes count as their box count
     with a flag (the walk count of those boxes is reported alongside);
  C  automatic stack separation without polygons: backend/app/vision/stack_separation.py.

Inputs:
  reports/experiment-stack-faces-20261015/annotations.json   reviewed polygons (geometry only)
  the detection file named in each image's detections_path   (saved Roboflow projec-mutta/2 boxes)
  reports/eval-20261015/eval_manifest.json                   labels: read only in score_* functions
  reports/field-labelled-20261007/raw/batch-*.json           detections for the 24 labelled photos (A vs C)
  datasets/field-2026-10/labelled-20261007/labels.csv        values for 3 polygon photos the audit marks
                                                             not usable (secondary table only)

Count labels are evaluation targets only: every prediction is made by predict_* functions that never
see a label; labels are joined afterwards in score_*. scripts/tests/test_label_perturbation.py changes
every label and per-stack truth value and checks that every prediction stays byte-identical.

Run from the repository root (PYTHONPATH must provide numpy):
  python scripts/experiment_stack_faces.py --out <scratch dir>
Writes results.json to --out (default reports/experiment-stack-faces-20261015) and prints a summary.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import statistics
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "backend"))
sys.path.insert(0, str(REPO / "scripts"))

from app.vision.block_model import _face, build_block  # noqa: E402
from app.vision.layer_span import _columns, count_layers_by_span  # noqa: E402
from app.vision.stack_separation import PARAMS as C_PARAMS  # noqa: E402
from app.vision.stack_separation import column_record, separate_stacks  # noqa: E402

import evaluate_labelled as ev  # noqa: E402

OUT_DIR = REPO / "reports" / "experiment-stack-faces-20261015"
ANNOTATIONS = OUT_DIR / "annotations.json"
LABELS_CSV = REPO / "datasets" / "field-2026-10" / "labelled-20261007" / "labels.csv"
BOX_PITCH_MIN = 0.75  # block_model.MIN_BOX_PITCH_RATIO

# Multi-view sets with polygons in every view. Truth status from the 2026-10-15 dataset audit.
VIEW_SETS = [
    {"set": "9b4c783e (13 Oct)", "genuine": "plausible genuine three-face set of one block (visual, audit); no count",
     "views": {"straight": "scan-9b4c783e-straight", "left": "scan-9b4c783e-left", "right": "scan-9b4c783e-right"}},
    {"set": "ef823816 (13 Oct)", "genuine": "not genuine: LEFT and RIGHT show the same right-side face; no count",
     "views": {"straight": "scan-ef823816-straight", "left": "scan-ef823816-left", "right": "scan-ef823816-right"}},
    {"set": "99-block trio", "genuine": "substituted: LEFT (warehouse image-4) and RIGHT (img-32) are the same free end",
     "views": {"straight": "labelled-img-01", "left": "warehouse-image-4", "right": "labelled-img-32"}},
]
# Polygon images whose label the audit marks usable (label_id in the eval manifest) or per-stack usable.
LABELLED_IMAGES = {"labelled-img-01": 1, "labelled-img-32": 32, "labelled-img-04": 4, "labelled-img-09": 9,
                   "labelled-img-35": 35, "labelled-img-39": 39, "labelled-img-47": 47, "labelled-img-46": 46}
PER_STACK_IMAGES = {"warehouse-image-4": "warehouse image-4 (same 19 stack)"}
NOT_USABLE_IMAGES = {"labelled-img-06": 6, "labelled-img-41": 41, "labelled-img-43": 43}
# Physical block of each polygon photo (2026-10-15 dataset audit, group_id; geometry and SIFT, no count).
PHOTO_GROUPS = {
    "scan-9b4c783e-straight": "G44", "scan-9b4c783e-left": "G44", "scan-9b4c783e-right": "G44",
    "scan-30aca6a1-straight": "G44",  # the same STRAIGHT face as 9b4c783e, from further back
    "scan-ef823816-straight": "G43", "scan-ef823816-left": "G43", "scan-ef823816-right": "G43",
    "labelled-img-01": "G01", "labelled-img-32": "G01", "warehouse-image-4": "G01",
    "labelled-img-04": "G05", "labelled-img-09": "G08", "labelled-img-06": "G07", "labelled-img-35": "G22",
    "labelled-img-39": "G24", "labelled-img-41": "G18", "labelled-img-47": "G30", "mutaa-image-07": "G36",
    "labelled-img-46": "G29", "labelled-img-43": "G26",
}
# warehouse image-4 is not in the eval manifest's photo list; its detector-leak status, measured here:
WAREHOUSE4_LEAK = "leaked (byte-identical to datasets/canonical_clean/train/images/fb5bd22bfe8d1b3da171.jpeg)"
SMALL_SCALE_PITCH_FRAC = 0.03  # median layer pitch below 3% of the frame height = the small-scale bucket


# ---------------------------------------------------------------- inputs (no labels)

def _load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def load_detections(spec):
    """Centre-format boxes from a detections_path ('file#views.<v>', '#stacks[0]...' or '#detections')."""
    path, _, frag = spec.split(" ")[0].partition("#")
    doc = _load(REPO / path)
    if frag.startswith("views."):
        root = doc["response"] if "response" in doc else doc
        raw = root["views"][frag.split(".")[1]]["detections"]
        boxes = [{"x": float(b["x"]), "y": float(b["y"]), "width": float(b["width"]), "height": float(b["height"])}
                 for b in raw]
    else:
        raw = [b for s in doc["stacks"] for b in s["visible_detections"]] if frag.startswith("stacks") else doc["detections"]
        boxes = []
        for b in raw:
            x0, y0, x1, y1 = b["bbox"]
            boxes.append({"x": (x0 + x1) / 2, "y": (y0 + y1) / 2, "width": x1 - x0, "height": y1 - y0})
    return ev._boxes(boxes)


def inside(point, polygon):
    """Even-odd ray casting; the polygons are simple."""
    x, y = point
    hit = False
    for i in range(len(polygon)):
        x1, y1 = polygon[i]
        x2, y2 = polygon[(i + 1) % len(polygon)]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def assign(boxes, polygons):
    """Polygon id per box (centre inside), first match in annotation order; also boxes inside 2+ polygons."""
    owner, multi = [], 0
    for b in boxes:
        hits = [p["id"] for p in polygons if inside((b["x"], b["y"]), p["polygon"])]
        multi += len(hits) > 1
        owner.append(hits[0] if hits else None)
    return owner, multi


def cell_key(physical):
    m = re.search(r"\((\d+),(\d+)\)", physical or "")
    return (int(m.group(1)), int(m.group(2))) if m else None


# ---------------------------------------------------------------- arms (no labels)

def arm_a(boxes, width, height):
    pred = ev.predict_face(boxes, width, height)
    members = _columns(boxes)  # the same grouping count_layers_by_span uses, in the same order
    records = count_layers_by_span(boxes)
    by_id = {id(b): i for i, b in enumerate(boxes)}
    stacks = []
    for rec, col in zip(records, members):
        assert column_record(col, rec["column"]) == rec  # column_record reproduces layer_span exactly
        stacks.append({**rec, "box_indices": sorted(by_id[id(b)] for b in col)})
    return {"outcome": pred["outcome"], "gate_reasons": pred["gate_reasons"], "flag_reasons": pred["flag_reasons"],
            "total": pred["predicted_total"], "total_without_recessed": pred["predicted_total_without_recessed"],
            "stacks": stacks, "columns": pred["columns"]}


def arm_b(boxes, owner, image):
    polys = {p["id"]: p for p in image["polygons"]}
    per = []
    for p in image["polygons"]:
        idx = [i for i, o in enumerate(owner) if o == p["id"]]
        rec = column_record([boxes[i] for i in idx], 0) if idx else None
        short = 0 < len(idx) < 3
        entry = {"polygon": p["id"], "role": p["role"], "depth_row": p["depth_row"], "face_view": p["face_view"],
                 "physical_stack": p.get("physical_stack_inferred"), "top_visible": p["top_visible"],
                 "base_visible": p["base_visible"], "clipped": p["clipped"], "blurred": p["blurred"],
                 "contents_note": p["contents_note"], "membership_uncertain": p["membership_uncertain"],
                 "boxes": len(idx), "box_indices": idx, "short": short,
                 "count": (len(idx) if short else rec["walk_count"]) if rec else 0,
                 "count_short_as_walk": rec["walk_count"] if rec else 0}
        if rec:
            entry.update({k: rec[k] for k in ("walk_count", "span_count", "walk_filled", "walk_unresolved_gaps",
                                              "duplicate_boxes", "pitch_px", "box_height_px", "perspective_gradient",
                                              "x_min", "x_max", "y_first", "y_last")})
            entry["box_pitch_ratio"] = round(rec["box_height_px"] / rec["pitch_px"], 3) if rec["pitch_px"] else None
            # boxes the walk skipped as duplicates (accepted boxes = walk count - filled layers)
            entry["walk_duplicates"] = len(idx) - (rec["walk_count"] - rec["walk_filled"])
            entry["_record"] = rec
        per.append(entry)
    # block-model column reasons on the target polygons with 3+ boxes (relative pitch needs the whole face)
    full = [e for e in per if e["role"] == "target" and e["boxes"] >= 3]
    if full:
        ordered = sorted(full, key=lambda e: e["_record"]["x_min"])
        for e, f in zip(ordered, _face([e["_record"] for e in ordered], "straight")):
            e["reason"], e["recessed"] = f["reason"], f["recessed"]
    # one count per physical stack: two polygons of one stack in one photo (two faces) count once
    chosen, groups = [], {}
    for e in per:
        if e["role"] != "target":
            continue
        key = e["physical_stack"] or ("poly:" + e["polygon"])
        groups.setdefault(key, []).append(e)
    for key, es in groups.items():
        best = max(es, key=lambda e: (e["boxes"], e["face_view"] == "front"))
        chosen.append(best["polygon"])
        for e in es:
            e["counted"] = e is best
    for e in per:
        e.setdefault("counted", False)
        e.pop("_record", None)
    counted = [e for e in per if e["counted"]]
    return {
        "polygons": per,
        "total": sum(e["count"] for e in counted),
        "total_short_as_walk": sum(e["count_short_as_walk"] for e in counted),
        "short_stacks_counted": sum(e["short"] for e in counted),
        "boxes_in_no_polygon": sum(o is None for o in owner),
        "boxes_in_neighbour_polygons": sum(1 for o in owner if o and polys[o]["role"] == "neighbour"),
        "boxes_in_target_polygons": sum(1 for o in owner if o and polys[o]["role"] == "target"),
    }


def arm_c(boxes):
    return separate_stacks(boxes)


# ---------------------------------------------------------------- localization against polygons (no labels)

def localization(stacks, owner, image, boxes):
    """Compare found stacks (A columns or C stacks: lists of box indices) with the polygons."""
    n_boxes = len(boxes)
    polys = {p["id"]: p for p in image["polygons"]}
    found = []
    for s in stacks:
        comp = Counter(owner[i] or "-" for i in s["box_indices"])
        kinds = {("unassigned" if k == "-" else polys[k]["role"]) for k in comp}
        entry = {"index": s["column"], "boxes": len(s["box_indices"]), "composition": dict(comp),
                 "walk_count": s["walk_count"], "kinds": sorted(kinds)}
        if len(comp) > 1:  # what the merge does to the count: walk of the mixed stack vs walk of each part
            parts = {k: column_record([boxes[i] for i in s["box_indices"] if (owner[i] or "-") == k])["walk_count"]
                     for k in comp}
            entry["merge_parts_walk"] = parts
            entry["merge_effect"] = s["walk_count"] - sum(parts.values())
        if "depth" in s:
            main = comp.most_common(1)[0][0]
            if main != "-" and polys[main]["role"] == "target":
                entry["depth_vs_polygon"] = {"c_depth": s["depth"], "polygon_depth_row": polys[main]["depth_row"],
                                             "agree": (s["depth"] == "front") == (polys[main]["depth_row"] == 0)}
        found.append(entry)
    placed = {i: f["index"] for s, f in zip(stacks, found) for i in s["box_indices"]}
    per_target = []
    for p in image["polygons"]:
        idx = [i for i in range(n_boxes) if owner[i] == p["id"]]
        if p["role"] != "target":
            continue
        if not idx:
            per_target.append({"polygon": p["id"], "status": "no_boxes", "boxes": 0})
            continue
        homes = Counter(placed.get(i) for i in idx)
        dropped = homes.pop(None, 0)
        if not homes:
            status = "missed"
        else:
            main = homes.most_common(1)[0][0]
            f = next(f for f in found if f["index"] == main)
            others = {k for k in f["composition"] if k != p["id"]}
            if len(homes) > 1:
                status = "split"
            elif others:
                kinds = {"unassigned" if k == "-" else polys[k]["role"] for k in others}
                status = "merged_with_" + "+".join(sorted(kinds))
            else:
                status = "correct"
        per_target.append({"polygon": p["id"], "status": status, "boxes": len(idx), "dropped_boxes": dropped,
                           "found_stacks": sorted(k for k in homes)})
    counts = Counter(t["status"] for t in per_target)
    return {
        "found_stacks": len(stacks),
        "target_polygons": sum(p["role"] == "target" for p in image["polygons"]),
        "target_polygons_with_boxes": sum(t["status"] != "no_boxes" for t in per_target),
        "status_counts": dict(sorted(counts.items())),
        "found_with_neighbour_boxes": sum("neighbour" in f["kinds"] for f in found),
        "found_neighbour_only": sum(f["kinds"] == ["neighbour"] for f in found),
        "found_with_unassigned_boxes": sum("unassigned" in f["kinds"] for f in found),
        "per_target": per_target,
        "found": found,
    }


# ---------------------------------------------------------------- layer-counting consistency (no labels)

def equal_extent_pairs(image, b):
    """Target polygons of one photo with the same depth row and face, fully in frame, whose first and last
    boxes sit within 0.6 pitch of each other: same tray type assumed, so they should read the same layers."""
    eligible = [e for e in b["polygons"] if e["role"] == "target" and e["boxes"] >= 3 and e["top_visible"]
                and e["base_visible"] and e["clipped"] == "none"]
    out = []
    for i, p in enumerate(eligible):
        for q in eligible[i + 1:]:
            if p["depth_row"] != q["depth_row"] or p["face_view"] != q["face_view"]:
                continue
            tol = 0.6 * max(p["pitch_px"], q["pitch_px"])
            if abs(p["y_first"] - q["y_first"]) <= tol and abs(p["y_last"] - q["y_last"]) <= tol:
                out.append({"image": image["id"], "pair": [p["polygon"], q["polygon"]],
                            "walk": [p["walk_count"], q["walk_count"]], "span": [p["span_count"], q["span_count"]],
                            "walk_diff": abs(p["walk_count"] - q["walk_count"]),
                            "span_diff": abs(p["span_count"] - q["span_count"])})
    return out


# ---------------------------------------------------------------- cross-view association (no labels)

def block_cells(columns, view, width):
    """Which block cell each column of a view feeds in build_block (same rules as block_model.build_block)."""
    ordered = sorted(columns, key=lambda c: c["x_min"])
    face = _face(ordered, view) if ordered else []
    pairs = list(zip(ordered, face))
    if view == "left":
        pairs = list(reversed(pairs))
    out = []
    for k, (col, f) in enumerate(pairs):
        if view == "straight":
            cell, behind = (k, 0), (k, 1)
        elif view == "left":
            cell, behind = (0, k), (1, k)
        else:
            cell, behind = (width - 1, k), (width - 2, k)
        if f["recessed"]:
            used = behind if (view == "straight" or k > 0) else None  # side faces never promote past the corner
        else:
            used = cell
        out.append({"column": col["column"], "box_indices": col.get("box_indices"), "layers": f["layers"],
                    "recessed": f["recessed"], "face_cell": list(cell), "counted_as_cell": list(used) if used else None})
    return out


def association(view_set, images, per_image):
    out = {"set": view_set["set"], "genuine": view_set["genuine"], "arms": {}}
    for arm in ("A", "B", "C"):
        cols = {}
        for view, iid in view_set["views"].items():
            r = per_image[iid]
            if arm == "A":
                cols[view] = r["A"]["stacks"]
            elif arm == "C":
                cols[view] = [s for s in r["C"]["stacks"] if s["model_boxes"] >= 3 and not s["partial"]]
            else:  # oracle localization: target polygons with 3+ boxes that stand on their own base in this view
                boxes = r["_boxes"]
                cols[view] = []
                for k, e in enumerate(r["B"]["polygons"]):
                    if e["role"] == "target" and e["boxes"] >= 3 and (e["base_visible"] or e["depth_row"] == 0):
                        rec = column_record([boxes[i] for i in e["box_indices"]], k + 1)
                        rec["box_indices"] = e["box_indices"]
                        cols[view].append(rec)
        block = build_block(cols["straight"], cols["left"] or None, cols["right"] or None)
        width = block["width"]
        checks = []
        for view, iid in view_set["views"].items():
            owner = per_image[iid]["_owner"]
            polys = {p["id"]: p for p in images[iid]["polygons"]}
            for c in block_cells(cols[view], view, width):
                comp = Counter(owner[i] for i in c["box_indices"] if owner[i])
                main = comp.most_common(1)[0][0] if comp else None
                phys = polys[main].get("physical_stack_inferred") if main else None
                truth = cell_key(phys)
                used = tuple(c["counted_as_cell"]) if c["counted_as_cell"] else None
                if used is None:
                    verdict = "not counted (recessed corner on a side face)"
                elif truth is None:
                    verdict = "no cell key on polygon"
                else:
                    verdict = "correct" if used == truth else "wrong"
                checks.append({"view": view, "column": c["column"], "layers": c["layers"], "recessed": c["recessed"],
                               "counted_as_cell": c["counted_as_cell"], "polygon": main, "physical_stack": phys,
                               "verdict": verdict})
        out["arms"][arm] = {
            "status": block["status"], "total_trays": block["total_trays"], "width": block["width"],
            "depth": block["depth"], "observed_trays": block["observed_trays"],
            "computed_trays": block["computed_trays"],
            "conflicts": [c.get("reason") for c in block["conflicts"]],
            "ambiguities": [{k: v for k, v in a.items() if k != "reason"} for a in block["ambiguities"]],
            "association": checks,
            "association_counts": dict(Counter(c["verdict"] for c in checks)),
        }
    return out


def physical_stack_table(images, per_image):
    """Every physical stack key that appears in 2+ photos: count per view under each arm."""
    seen = {}
    for iid, r in per_image.items():
        polys = images[iid]["polygons"]
        for p, e in zip(polys, r["B"]["polygons"]):
            key = p.get("physical_stack_inferred")
            if not key or p["role"] != "target":
                continue
            entry = {"image": iid, "polygon": p["id"], "face_view": p["face_view"], "depth_row": p["depth_row"],
                     "base_visible": p["base_visible"], "boxes": e["boxes"], "B": e["count"] if e["boxes"] else None}
            for arm in ("A", "C"):
                loc = r["loc_" + arm]
                t = next((t for t in loc["per_target"] if t["polygon"] == p["id"]), None)
                if t and t.get("found_stacks"):
                    main = t["found_stacks"][0] if len(t["found_stacks"]) == 1 else None
                    f = next((f for f in loc["found"] if f["index"] == main), None) if main else None
                    entry[arm] = f["walk_count"] if f else None
                    entry[arm + "_status"] = t["status"]
                else:
                    entry[arm] = None
                    entry[arm + "_status"] = t["status"] if t else "no_boxes"
            seen.setdefault(key.split(" ")[0], []).append(entry)
    table = []
    for key, entries in sorted(seen.items()):
        if len({e["image"] for e in entries}) < 2:
            continue
        b_vals = [e["B"] for e in entries if e["B"] is not None and e["base_visible"]]
        table.append({"physical_stack": key, "views": entries,
                      "B_spread_full_views": (max(b_vals) - min(b_vals)) if len(b_vals) >= 2 else None})
    return table


# ---------------------------------------------------------------- the 24 labelled photos: A vs C (no labels)

def predict_labelled_set(manifest):
    labelled, _ = ev.load_labelled_detections()
    rows = []
    for p in manifest["photos"]:
        dets, src = labelled[p["label_id"]]
        boxes = ev._boxes(dets)
        a = ev.predict_face(boxes, p["width"], p["height"])
        c = separate_stacks(boxes)
        rows.append({"label_id": p["label_id"], "cluster": p["near_duplicate_cluster"], "detections": src,
                     "A_outcome": a["outcome"], "A_total": a["predicted_total"],
                     "A_walk": [col["walk_count"] for col in a["columns"]],
                     "C_total": c["total"], "C_walk": [s["walk_count"] for s in c["stacks"]],
                     "C_depth": [s["depth"] for s in c["stacks"]],
                     "C_dropped": [d["reason"].split(" (")[0].split(" at ")[0] for d in c["dropped"]],
                     "C_splits": sum(s["partial"] for s in c["stacks"]),
                     "C_short": sum(s["short"] for s in c["stacks"])})
    return rows


def per_stack_recall(manifest):
    """Boxes per layer for the eval manifest's per-stack cases (columns chosen by geometry only)."""
    out = []
    wh_dets, wh_image, _ = ev.warehouse4_detections()
    for case in manifest["per_stack"]:
        src = case["detections"]
        if "batch" in src:
            dets = _load(REPO / src["batch"])["response"]["views"][src["view"]]["detections"]
        else:
            dets = wh_dets
        cols = sorted(count_layers_by_span(ev._boxes(dets)), key=lambda c: c["x_min"])
        if case.get("x_range"):
            lo, hi = case["x_range"]
            cols = [c for c in cols if lo <= (c["x_min"] + c["x_max"]) / 2 <= hi]
        out.append({"case": case["case"], "physical_stack": case["physical_stack"],
                    "columns": [{k: c[k] for k in ("model_boxes", "walk_count", "span_count", "walk_filled",
                                                   "duplicate_boxes", "pitch_px", "box_height_px")}
                                | {"boxed_layers": c["walk_count"] - c["walk_filled"],
                                   "box_pitch_ratio": round(c["box_height_px"] / c["pitch_px"], 3)}
                                for c in cols]})
    return out


# ---------------------------------------------------------------- scoring (labels enter here)

def score_polygon_images(per_image, manifest):
    by_id = {p["label_id"]: p for p in manifest["photos"]}
    wh = next(c for c in manifest["per_stack"] if c["case"] == PER_STACK_IMAGES["warehouse-image-4"])
    rows = []
    for iid, r in per_image.items():
        if iid in LABELLED_IMAGES:
            p = by_id[LABELLED_IMAGES[iid]]
            label, tier, source = p["label_value"], p["tier"], f"eval manifest label_id {p['label_id']}"
            leak = p["detector_leak"]
        elif iid in PER_STACK_IMAGES:
            label, tier, source = wh["stacks"][0]["filled"], "per-stack (user-confirmed)", wh["truth_source"]
            leak = WAREHOUSE4_LEAK
        else:
            continue
        rows.append({"image": iid, "label": label, "tier": tier, "label_source": source,
                     "detector_leak": leak, "group": PHOTO_GROUPS[iid],
                     "A": r["A"]["total"], "A_outcome": r["A"]["outcome"], "B": r["B"]["total"],
                     "B_short_as_walk": r["B"]["total_short_as_walk"], "C": r["C"]["total"],
                     "err_A": r["A"]["total"] - label, "err_B": r["B"]["total"] - label,
                     "err_B_short_as_walk": r["B"]["total_short_as_walk"] - label, "err_C": r["C"]["total"] - label,
                     "A_minus_B": r["A"]["total"] - r["B"]["total"]})
    return rows


def score_not_usable(per_image):
    """Polygon photos the audit marks not usable at image level: shown, never in a headline number."""
    values = {}
    with open(LABELS_CSV, encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            values[int(row["id"])] = row["label_total"]
    rows = []
    for iid, lid in NOT_USABLE_IMAGES.items():
        r = per_image[iid]
        rows.append({"image": iid, "labels_csv_value": values[lid], "audit": "not usable (scope unclear)",
                     "A": r["A"]["total"], "B": r["B"]["total"], "C": r["C"]["total"]})
    return rows


def score_labelled_set(rows, manifest):
    by_id = {p["label_id"]: p for p in manifest["photos"]}
    for r in rows:
        p = by_id[r["label_id"]]
        r.update(label=p["label_value"], tier=p["tier"], detector_leak=p["detector_leak"],
                 err_A=r["A_total"] - p["label_value"], err_C=r["C_total"] - p["label_value"])
        r["A_accepted_exact"] = r["A_outcome"] == "accepted" and r["err_A"] == 0
    reps = {}
    for r in sorted(rows, key=lambda r: r["label_id"]):
        reps.setdefault(r["cluster"], r)
    reps = list(reps.values())

    def summ(sel):
        n = len(sel)
        return {"n": n, "A_exact_ungated": sum(r["err_A"] == 0 for r in sel),
                "C_exact_ungated": sum(r["err_C"] == 0 for r in sel),
                "A_accepted": sum(r["A_outcome"] == "accepted" for r in sel),
                "A_accepted_exact": sum(r["A_accepted_exact"] for r in sel),
                "A_abs_error_sum": sum(abs(r["err_A"]) for r in sel),
                "C_abs_error_sum": sum(abs(r["err_C"]) for r in sel),
                "A_abs_error_median": statistics.median(abs(r["err_A"]) for r in sel) if sel else None,
                "C_abs_error_median": statistics.median(abs(r["err_C"]) for r in sel) if sel else None,
                "C_differs_from_A": sum(r["C_total"] != r["A_total"] for r in sel)}

    return {"clusters_all": summ(reps),
            "clusters_tier_A": summ([r for r in reps if r["tier"] == "A"]),
            "clusters_tier_B": summ([r for r in reps if r["tier"] == "B"]),
            "clusters_leak_free": summ([r for r in reps if r["detector_leak"] == "leak_free"]),
            "representatives": [r["label_id"] for r in reps]}


def score_per_stack_recall(cases, manifest):
    truth = {c["case"]: c["stacks"] for c in manifest["per_stack"]}
    for case in cases:
        stacks = truth[case["case"]]
        if len(stacks) != len(case["columns"]):
            case["note"] = "column count differs from stack count: not scored"
            continue
        for col, st in zip(case["columns"], stacks):
            col["user_filled"] = st["filled"]
            col["missing_layers"] = st["filled"] - col["boxed_layers"]
            col["walk_error"] = col["walk_count"] - st["filled"]
            col["span_error"] = col["span_count"] - st["filled"]
    return cases


# ---------------------------------------------------------------- main

def run():
    ann = _load(ANNOTATIONS)
    images = {im["id"]: im for im in ann["images"]}
    per_image = {}
    for iid, im in images.items():
        boxes = load_detections(im["detections_path"])
        owner, multi = assign(boxes, im["polygons"])
        a = arm_a(boxes, im["width"], im["height"])
        b = arm_b(boxes, owner, im)
        c = arm_c(boxes)
        per_image[iid] = {"A": a, "B": b, "C": c, "boxes": len(boxes), "boxes_in_two_polygons": multi,
                          "loc_A": localization(a["stacks"], owner, im, boxes),
                          "loc_C": localization(c["stacks"], owner, im, boxes),
                          "equal_extent_pairs": equal_extent_pairs(im, b),
                          "_boxes": boxes, "_owner": owner}
    assoc = [association(vs, images, per_image) for vs in VIEW_SETS]
    phys = physical_stack_table(images, per_image)

    manifest = _load(ev.MANIFEST)
    labelled_rows = predict_labelled_set(manifest)
    recall_cases = per_stack_recall(manifest)

    # ---- labels from here on (scoring only)
    scored = score_polygon_images(per_image, manifest)
    not_usable = score_not_usable(per_image)
    labelled_summary = score_labelled_set(labelled_rows, manifest)
    recall_cases = score_per_stack_recall(recall_cases, manifest)

    # ---- aggregates
    def loc_totals(arm):
        tot = Counter()
        for r in per_image.values():
            tot.update(r["loc_" + arm]["status_counts"])
        merges = [f for r in per_image.values() for f in r["loc_" + arm]["found"] if "merge_effect" in f]
        depth = [f["depth_vs_polygon"] for r in per_image.values() for f in r["loc_" + arm]["found"]
                 if "depth_vs_polygon" in f]
        return {"mixed_stacks": len(merges), "mixed_stacks_count_neutral": sum(f["merge_effect"] == 0 for f in merges),
                "mixed_stacks_effect_sum": sum(f["merge_effect"] for f in merges),
                "mixed_stacks_abs_effect_sum": sum(abs(f["merge_effect"]) for f in merges),
                "depth_label_vs_polygon": ({"stacks": len(depth), "agree": sum(d["agree"] for d in depth),
                                            "front_called_set_back": sum(d["c_depth"] != "front" and d["polygon_depth_row"] == 0 for d in depth),
                                            "set_back_called_front": sum(d["c_depth"] == "front" and d["polygon_depth_row"] > 0 for d in depth)}
                                           if depth else None),
                "target_polygons": sum(r["loc_" + arm]["target_polygons"] for r in per_image.values()),
                "target_polygons_with_boxes": sum(r["loc_" + arm]["target_polygons_with_boxes"] for r in per_image.values()),
                "found_stacks": sum(r["loc_" + arm]["found_stacks"] for r in per_image.values()),
                "found_with_neighbour_boxes": sum(r["loc_" + arm]["found_with_neighbour_boxes"] for r in per_image.values()),
                "found_with_unassigned_boxes": sum(r["loc_" + arm]["found_with_unassigned_boxes"] for r in per_image.values()),
                "status_counts": dict(sorted(tot.items())),
                "images_all_correct": sum(set(r["loc_" + arm]["status_counts"]) <= {"correct", "no_boxes"}
                                          for r in per_image.values())}

    targets = [e for r in per_image.values() for e in r["B"]["polygons"] if e["role"] == "target"]
    full = [e for e in targets if e["boxes"] >= 3]
    layer = {
        "target_polygons": len(targets), "with_3plus_boxes": len(full),
        "with_1_2_boxes": sum(0 < e["boxes"] < 3 for e in targets), "with_0_boxes": sum(e["boxes"] == 0 for e in targets),
        "polygons_with_filled_layers": sum(e["walk_filled"] > 0 for e in full),
        "filled_layers_total": sum(e["walk_filled"] for e in full),
        "walk_layers_total": sum(e["walk_count"] for e in full),
        "polygons_with_walk_duplicates": sum(e["walk_duplicates"] > 0 for e in full),
        "walk_duplicate_boxes_total": sum(e["walk_duplicates"] for e in full),
        "boxes_total": sum(e["boxes"] for e in full),
        "polygons_box_pitch_below_0.75": sum(e["box_pitch_ratio"] < BOX_PITCH_MIN for e in full),
        "polygons_span_walk_differ_gt1": sum(abs(e["span_count"] - e["walk_count"]) > 1 for e in full),
        "polygons_with_unresolved_gaps": sum(e["walk_unresolved_gaps"] > 0 for e in full),
        "polygons_with_block_reason": sum(bool(e.get("reason")) for e in full),
    }
    pairs = [p for r in per_image.values() for p in r["equal_extent_pairs"]]
    consistency = {"pairs": len(pairs), "walk_diff_gt1": sum(p["walk_diff"] > 1 for p in pairs),
                   "span_diff_gt1": sum(p["span_diff"] > 1 for p in pairs),
                   "walk_diff_max": max((p["walk_diff"] for p in pairs), default=None),
                   "span_diff_max": max((p["span_diff"] for p in pairs), default=None)}
    per_image_layer = []
    for iid, r in per_image.items():
        f = [e for e in r["B"]["polygons"] if e["role"] == "target" and e["boxes"] >= 3]
        if not f:
            continue
        per_image_layer.append({
            "image": iid, "polygons_3plus": len(f),
            "median_pitch_frac": round(statistics.median(e["pitch_px"] for e in f) / images[iid]["height"], 4),
            "median_box_pitch_ratio": round(statistics.median(e["box_pitch_ratio"] for e in f), 3),
            "filled_layers": sum(e["walk_filled"] for e in f),
            "box_pitch_below_0.75": sum(e["box_pitch_ratio"] < BOX_PITCH_MIN for e in f),
            "span_walk_differ_gt1": sum(abs(e["span_count"] - e["walk_count"]) > 1 for e in f),
            "equal_extent_pairs": len(r["equal_extent_pairs"]),
            "equal_extent_walk_diff_gt1": sum(p["walk_diff"] > 1 for p in r["equal_extent_pairs"])})

    # ---- physical n behind the photo-level numbers (label-free)
    def stack_key(iid, e):
        return e["physical_stack"].split(" ")[0] if e["physical_stack"] else f"{iid}:{e['polygon']}"

    keys = {(iid, e["polygon"]): stack_key(iid, e) for iid, r in per_image.items() for e in r["B"]["polygons"]
            if e["role"] == "target"}
    frac = {x["image"]: x["median_pitch_frac"] for x in per_image_layer}
    buckets = {}
    for name, sel in (("pitch_frac_ge_0.03", lambda f: f >= SMALL_SCALE_PITCH_FRAC),
                      ("pitch_frac_lt_0.03", lambda f: f < SMALL_SCALE_PITCH_FRAC)):
        bp = [p for p in pairs if sel(frac[p["image"]])]
        physical = {frozenset(keys[(p["image"], q)] for q in p["pair"]) for p in bp}
        by_group = Counter(PHOTO_GROUPS[p["image"]] for p in bp)
        buckets[name] = {"images": sorted({p["image"] for p in bp}), "groups": sorted(by_group),
                         "pairs": len(bp), "physically_distinct_pairs": len(physical),
                         "pairs_per_group": dict(sorted(by_group.items())),
                         "walk_diff_gt1": sum(p["walk_diff"] > 1 for p in bp),
                         "span_diff_gt1": sum(p["span_diff"] > 1 for p in bp)}
    physical_n = {"photos": len(per_image), "physical_groups": len({PHOTO_GROUPS[i] for i in per_image}),
                  "target_polygons": len(keys), "physical_stack_keys": len(set(keys.values())),
                  "target_polygons_3plus_boxes": len(full),
                  "physical_stack_keys_3plus_boxes": len({keys[(iid, e["polygon"])] for iid, r in per_image.items()
                                                          for e in r["B"]["polygons"]
                                                          if e["role"] == "target" and e["boxes"] >= 3}),
                  "equal_extent_buckets": buckets,
                  "note": "keys = physical_stack_inferred (Claude's cross-view links); a target polygon without a "
                          "link is its own key. ef823816 LEFT and RIGHT show the same face; 30aca6a1 STRAIGHT and "
                          "9b4c783e STRAIGHT show the same face."}

    # ---- where the walk and the span disagree inside the polygons (label-free)
    def part(sel):
        return {"polygons": len(sel), "filled_layers": sum(e["walk_filled"] for e in sel),
                "walk_duplicates": sum(e["walk_duplicates"] for e in sel)}

    over = [e for e in full if e["walk_count"] > e["span_count"] + 1]
    walk_vs_span = {
        "polygons": len(full), "filled_layers": sum(e["walk_filled"] for e in full),
        "walk_gt_span_plus1": part(over),
        "walk_gt_span_plus1_regular_boxes": part([e for e in over if e["box_pitch_ratio"] >= BOX_PITCH_MIN]),
        "span_gt_walk_plus1": part([e for e in full if e["span_count"] > e["walk_count"] + 1]),
        "within_1": part([e for e in full if abs(e["span_count"] - e["walk_count"]) <= 1]),
        "walk_gt_span_plus1_list": [{"image": iid, "polygon": e["polygon"], "boxes": e["boxes"],
                                     "span": e["span_count"], "walk": e["walk_count"], "filled": e["walk_filled"],
                                     "box_pitch_ratio": e["box_pitch_ratio"]}
                                    for iid, r in per_image.items() for e in r["B"]["polygons"]
                                    if e["role"] == "target" and e["boxes"] >= 3
                                    and e["walk_count"] > e["span_count"] + 1],
        "note": "regular boxes = box height / pitch >= 0.75. Walk > span + 1 is a disagreement between the two "
                "counters, not proof that the walk over-counts.",
    }

    totals = [{"image": iid, "A": r["A"]["total"], "A_outcome": r["A"]["outcome"], "B": r["B"]["total"],
               "B_short_as_walk": r["B"]["total_short_as_walk"], "C": r["C"]["total"],
               "A_minus_B": r["A"]["total"] - r["B"]["total"], "C_minus_B": r["C"]["total"] - r["B"]["total"],
               "boxes": r["boxes"], "boxes_in_no_polygon": r["B"]["boxes_in_no_polygon"],
               "boxes_in_neighbour_polygons": r["B"]["boxes_in_neighbour_polygons"],
               "boxes_in_two_polygons": r["boxes_in_two_polygons"]}
              for iid, r in per_image.items()]

    box_totals = {"photos": len(totals), "boxes": sum(t["boxes"] for t in totals),
                  "in_target_polygons": sum(r["B"]["boxes_in_target_polygons"] for r in per_image.values()),
                  "in_neighbour_polygons": sum(t["boxes_in_neighbour_polygons"] for t in totals),
                  "in_no_polygon": sum(t["boxes_in_no_polygon"] for t in totals),
                  "in_two_polygons": sum(t["boxes_in_two_polygons"] for t in totals)}
    face_total_effect = {
        "photos": len(totals), "B_total_sum": sum(t["B"] for t in totals),
        "A_differs_from_B": sum(t["A_minus_B"] != 0 for t in totals),
        "abs_A_minus_B_sum": sum(abs(t["A_minus_B"]) for t in totals),
        "C_differs_from_B": sum(t["C_minus_B"] != 0 for t in totals),
        "abs_C_minus_B_sum": sum(abs(t["C_minus_B"]) for t in totals)}

    for r in per_image.values():
        r.pop("_boxes")
        r.pop("_owner")
    return {
        "box_totals": box_totals,
        "localization_effect_on_face_totals": face_total_effect,
        "experiment": "stack-face A/B/C, 2026-10-15",
        "inputs": {"annotations": ANNOTATIONS.relative_to(REPO).as_posix(),
                   "annotations_schema": ann["schema_version"], "labels": "reports/eval-20261015/eval_manifest.json",
                   "detections": "per image detections_path (saved projec-mutta/2 boxes)"},
        "arm_c_params": C_PARAMS,
        "label_rule": "labels are read only in score_* after every prediction; no threshold, polygon or count used one",
        "totals_per_image": totals,
        "scored_polygon_images": scored,
        "not_usable_polygon_images": not_usable,
        "localization_A": loc_totals("A"),
        "localization_C": loc_totals("C"),
        "layer_counting_B": layer,
        "walk_vs_span_B": walk_vs_span,
        "physical_n": physical_n,
        "layer_counting_per_image": per_image_layer,
        "equal_extent_consistency": consistency,
        "equal_extent_pairs": pairs,
        "per_stack_recall": recall_cases,
        "cross_view_association": assoc,
        "physical_stacks_in_several_photos": phys,
        "labelled_set_A_vs_C": {"summary": labelled_summary, "photos": labelled_rows},
        "per_image": per_image,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=str(OUT_DIR), help="output folder for results.json (default: the report folder)")
    args = ap.parse_args(argv)
    results = run()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "results.json").write_text(json.dumps(results, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    la, lc = results["localization_A"], results["localization_C"]
    print("localization A:", la["status_counts"], "found", la["found_stacks"], "neighbour-boxes", la["found_with_neighbour_boxes"])
    print("localization C:", lc["status_counts"], "found", lc["found_stacks"], "neighbour-boxes", lc["found_with_neighbour_boxes"])
    print("layer counting B:", results["layer_counting_B"])
    print("equal-extent:", results["equal_extent_consistency"])
    pn, ws = results["physical_n"], results["walk_vs_span_B"]
    print("physical n:", {k: pn[k] for k in ("photos", "physical_groups", "target_polygons", "physical_stack_keys")})
    print("walk > span + 1:", ws["walk_gt_span_plus1"], "regular boxes:", ws["walk_gt_span_plus1_regular_boxes"],
          "span > walk + 1:", ws["span_gt_walk_plus1"])
    for r in results["scored_polygon_images"]:
        print("  scored", r["image"], "label", r["label"], "A", r["A"], "B", r["B"], "C", r["C"])
    print("labelled set:", results["labelled_set_A_vs_C"]["summary"]["clusters_all"])
    for s in results["cross_view_association"]:
        print("  assoc", s["set"], {k: (v["status"], v["total_trays"], v["association_counts"]) for k, v in s["arms"].items()})
    return results


if __name__ == "__main__":
    main()
