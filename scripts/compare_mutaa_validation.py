"""Compare blind manual tray counts with the app's (staging Worker) per-stack readings and block results.

Inputs (all in --report):
- raw/*.json: staging answers from scripts/validate_build_staging.py;
- manual-blind.json: the blind manual counts ({"photos": [{photo_id, path, final, counter_a, counter_b, ...}]}).
Block truth comes from the 31 Oct reconciled manual counts (reports/mutaa-manual-vs-backend-20261031) and the user's
handwritten totals where those apply to the whole block.

Per stack, the app's reading is the column's walk_count; it is matched to a manual stack by horizontal position. A
stack is scored only when the manual counters marked it fully countable with confidence other than low.

  python scripts/compare_mutaa_validation.py --report reports/mutaa-validation-0.5.0-20261101
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OCT31 = REPO / "reports" / "mutaa-manual-vs-backend-20261031"
REGISTRY = REPO / "benchmarks" / "registry-20261101" / "manifest.json"


def norm(path: str) -> str:
    return str(Path(path).resolve()).lower()


def app_readings(raw_dir: Path) -> dict[str, dict]:
    """One reading per source photo. A photo used as a real face in a set scan keeps that reading."""
    readings: dict[str, dict] = {}
    for file in sorted(raw_dir.glob("*.json"), key=lambda f: (not f.name.startswith("set-"), f.name)):
        answer = json.loads(file.read_text(encoding="utf-8"))
        if "refused" in answer:
            continue
        for view, sent in answer["_sent"].items():
            if view == answer.get("_filler"):
                continue
            key = norm(sent["src"])
            if key in readings:
                continue
            v = answer["views"][view]
            w = v["image"]["width"]
            cap = (answer["block"].get("capture") or {}).get(view) or {}
            readings[key] = {
                "scan": file.stem,
                "view": view,
                "capture_accepted": cap.get("accepted"),
                "capture_reasons": cap.get("reasons", []),
                "columns": [
                    {
                        "x_left": c["x_min"] / w,
                        "x_right": c["x_max"] / w,
                        "x_center": (c["x_min"] + c["x_max"]) / 2 / w,
                        "walk_count": c["walk_count"],
                        "model_boxes": c["model_boxes"],
                        "walk_filled": c["walk_filled"],
                        "doubts": c.get("doubts", []),
                    }
                    for c in v.get("stack_columns", [])
                ],
                "stray_groups": len(v.get("stray_groups", [])),
            }
    return readings


def match(app: list[dict], manual: list[dict]) -> tuple[list, list, list]:
    used, pairs, app_only = set(), [], []
    for c in sorted(app, key=lambda c: c["x_center"]):
        best, best_d = None, 1.0
        for j, s in enumerate(manual):
            if j in used:
                continue
            width = min(c["x_right"] - c["x_left"], s["x_right"] - s["x_left"])
            d = abs(c["x_center"] - s["x_center"])
            if d <= max(0.03, 0.5 * width) and d < best_d:
                best, best_d = j, d
        if best is None:
            app_only.append(c)
        else:
            used.add(best)
            pairs.append((c, manual[best]))
    return pairs, app_only, [s for j, s in enumerate(manual) if j not in used]


def grade(app_count: int, manual: int) -> str:
    d = app_count - manual
    return "exact" if d == 0 else "off_by_1" if abs(d) == 1 else "off_by_2_plus"


def scored(s: dict) -> bool:
    return bool(s["fully_countable"]) and s["confidence"] != "low"


def user_labels() -> dict[str, dict]:
    """The user's handwritten totals (tier U) whose scope the 15 Oct audit judged usable for the whole photo."""
    faces = json.loads(REGISTRY.read_text(encoding="utf-8"))["faces"]
    return {
        norm(str(REPO / f["photo"])): f["truth"]
        for f in faces
        if f["source"] == "labelled" and f["truth"].get("tier") == "U" and f["truth"].get("usable")
    }


def compare_photos(readings: dict, manual: dict) -> list[dict]:
    labels = user_labels()
    rows = []
    for p in manual["photos"]:
        final = p.get("final") or {}
        r = readings.get(norm(p["path"]))
        stacks = final.get("stacks", []) if final else []
        row = {
            "photo_id": p["photo_id"],
            "manual_countable": final.get("countable") if final else None,
            "manual_view": final.get("view") if final else None,
            "manual_reconciled": p.get("reconciled"),
            "manual_truth_basis": p.get("truth_basis"),
            "app": None if r is None else {k: r[k] for k in ("scan", "view", "capture_accepted", "capture_reasons")},
            "stacks": [],
            "missed_by_app": [],
            "app_only_columns": [],
            "user_label": labels.get(norm(p["path"]), {}).get("trays"),
            "manual_total_main": sum(s["filled_trays"] for s in stacks if s["block"] == "main") if stacks else None,
            "manual_all_main_scored": bool(stacks) and all(scored(s) for s in stacks if s["block"] == "main"),
            "app_total": None,
        }
        if r is None:
            rows.append(row)
            continue
        row["app_total"] = sum(c["walk_count"] for c in r["columns"])
        pairs, app_only, manual_only = match(r["columns"], stacks)
        for c, s in pairs:
            row["stacks"].append({
                "x_center": round(s["x_center"], 3),
                "block": s["block"],
                "manual_filled": s["filled_trays"],
                "manual_cover": s["cover_trays"],
                "manual_scored": scored(s),
                "manual_confidence": s["confidence"],
                "app_walk": c["walk_count"],
                "app_boxes": c["model_boxes"],
                "app_gap_fill": c["walk_filled"],
                "app_doubts": c["doubts"],
                "grade_vs_filled": grade(c["walk_count"], s["filled_trays"]),
                "grade_vs_all_layers": grade(c["walk_count"], s["filled_trays"] + s["cover_trays"]),
            })
        row["missed_by_app"] = [
            {"x_center": round(s["x_center"], 3), "block": s["block"], "manual_filled": s["filled_trays"], "scored": scored(s)}
            for s in manual_only
        ]
        row["app_only_columns"] = [
            {"x_center": round(c["x_center"], 3), "app_walk": c["walk_count"], "doubts": c["doubts"]} for c in app_only
        ]
        rows.append(row)
    return rows


def summarise(rows: list[dict]) -> dict:
    out = {}
    for label, keep in (
        ("all photos", lambda r: True),
        ("photos the capture check accepts", lambda r: r["app"] and r["app"]["capture_accepted"]),
        ("photos the capture check refuses", lambda r: r["app"] and r["app"]["capture_accepted"] is False),
    ):
        sel = [r for r in rows if r["app"] and keep(r)]
        st = [s for r in sel for s in r["stacks"] if s["manual_scored"]]
        clean = [s for s in st if not s["app_doubts"] and not s["app_gap_fill"]]
        doubted = [s for s in st if s["app_doubts"] or s["app_gap_fill"]]
        out[label] = {
            "photos": len(sel),
            "scored_stacks": len(st),
            "vs_filled": dict(Counter(s["grade_vs_filled"] for s in st)),
            "vs_all_layers": dict(Counter(s["grade_vs_all_layers"] for s in st)),
            "clean_stacks (no doubt, no gap fill)": {"n": len(clean), **dict(Counter(s["grade_vs_filled"] for s in clean))},
            "doubted_or_gap_filled": {"n": len(doubted), **dict(Counter(s["grade_vs_filled"] for s in doubted))},
            "manual_stacks_missed_by_app": sum(1 for r in sel for s in r["missed_by_app"] if s["scored"]),
            "app_columns_with_no_manual_stack": sum(len(r["app_only_columns"]) for r in sel),
        }
    scored_all = [(r, s) for r in rows if r["app"] for s in r["stacks"] if s["manual_scored"]]
    by_basis: dict[str, Counter] = {}
    for r, s in scored_all:
        by_basis.setdefault(r["manual_truth_basis"] or "unknown", Counter())[s["grade_vs_filled"]] += 1
    out["scored stacks by manual truth basis (grade vs filled)"] = {k: dict(v) for k, v in sorted(by_basis.items())}
    # The dangerous case: a column the app would use with no doubt and no gap fill, on a photo it accepts, that
    # matches neither the manual filled count nor filled + cover.
    out["accepted photos: clean app columns that disagree with the manual count"] = [
        {"photo": r["photo_id"], "x": s["x_center"], "app": s["app_walk"], "manual_filled": s["manual_filled"],
         "manual_cover": s["manual_cover"], "manual_confidence": s["manual_confidence"], "basis": r["manual_truth_basis"]}
        for r, s in scored_all
        if r["app"]["capture_accepted"] and not s["app_doubts"] and not s["app_gap_fill"]
        and s["grade_vs_filled"] != "exact" and s["grade_vs_all_layers"] != "exact"
    ]
    labelled = [r for r in rows if r["user_label"] is not None]
    out["photo totals vs the user's handwritten labels (U)"] = {
        "photos": len(labelled),
        "manual_equals_label": sum(1 for r in labelled if r["manual_total_main"] == r["user_label"]),
        "app_equals_label": sum(1 for r in labelled if r["app_total"] == r["user_label"]),
        "app_equals_label_and_capture_accepted": sum(
            1 for r in labelled if r["app_total"] == r["user_label"] and r["app"] and r["app"]["capture_accepted"]
        ),
        "capture_accepted": sum(1 for r in labelled if r["app"] and r["app"]["capture_accepted"]),
        "rows": [
            {"photo": r["photo_id"], "label": r["user_label"], "manual": r["manual_total_main"], "app": r["app_total"],
             "accepted": r["app"]["capture_accepted"] if r["app"] else None}
            for r in labelled
        ],
    }
    return out


def blocks(raw_dir: Path) -> list[dict]:
    consensus = {c["set_id"]: c["consensus"] for c in json.loads((OCT31 / "manual-consensus.json").read_text(encoding="utf-8"))}
    verified = {s["set_id"]: s for s in json.loads((OCT31 / "sets-verified.json").read_text(encoding="utf-8"))["sets"]}
    rows = []
    for file in sorted(raw_dir.glob("set-*.json")):
        a = json.loads(file.read_text(encoding="utf-8"))
        sid = a["_set_id"]
        c = consensus.get(sid, {})
        b = a.get("block") or {}
        rows.append({
            "set_id": sid,
            "app_status": a.get("result_status"),
            "app_total": b.get("total_trays"),
            "app_footprint": [b.get("width"), b.get("depth")],
            "app_visible_verified": b.get("visible_verified_trays"),
            "app_visible_single_reading": b.get("visible_single_reading_trays"),
            "app_conflicts": [x.get("reason") for x in b.get("conflicts", [])],
            "capture": {v: (b.get("capture") or {}).get(v, {}).get("accepted") for v in ("straight", "left", "right")},
            "filler": a.get("_filler"),
            "manual_footprint": [c.get("x_stacks"), c.get("y_stacks")],
            "manual_total_filled": c.get("total_filled"),
            "manual_range": [c.get("total_low"), c.get("total_high")],
            "manual_reliability": c.get("reliability"),
            "user_label_total": verified.get(sid, {}).get("user_label_total"),
        })
    return rows


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--report", required=True)
    args = ap.parse_args(argv)
    report = Path(args.report)
    readings = app_readings(report / "raw")
    manual = json.loads((report / "manual-blind.json").read_text(encoding="utf-8"))
    rows = compare_photos(readings, manual)
    result = {"photos": rows, "summary": summarise(rows), "blocks": blocks(report / "raw")}
    (report / "comparison.json").write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(result["summary"], indent=1))
    for b in result["blocks"]:
        print(b["set_id"], b["app_status"], b["app_total"], b["app_footprint"], "| manual", b["manual_footprint"],
              b["manual_total_filled"], "| user", b["user_label_total"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
