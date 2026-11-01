"""Score the five/six parity checker (plan Phase P) on the registry faces, as the app sent them.

Same inputs and photo preparation as scripts/evaluate_independent_rim.py. Truth: the hand annotations
(benchmarks/annotations-20261101/columns.json) for the end-layer row types and the known miss columns; the tier A/V
per-stack truths for false flags on correctly counted columns.

Pass bars (plan step 3): automatic row type matches the annotations on at least 95% of the end layers it types; the
known false counts it can see are flagged; at most one correctly counted face gets a false flag; far faces are
unreadable rather than typed.

  python scripts/evaluate_cross_stack.py --mutaa C:/Users/rahul/MUTAA --out reports/cross-stack-20261101
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "backend"))
sys.path.insert(0, str(REPO / "scripts"))

from app.vision.cross_stack import DEFAULT_PARAMS, cross_stack  # noqa: E402
from app.vision.layer_span import _columns, count_layers_by_span  # noqa: E402
from evaluate_independent_rim import KNOWN_WRONG, prepared_bgr, truths  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mutaa", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    mutaa = Path(args.mutaa)
    manifest = json.loads((REPO / "benchmarks/registry-20261101/manifest.json").read_text(encoding="utf-8"))
    annotations = {(c["face"], c["column"]): c for c in
                   json.loads((REPO / "benchmarks/annotations-20261101/columns.json").read_text(encoding="utf-8"))["columns"]}
    truth = truths(manifest)
    rows = []
    for face in manifest["faces"]:
        saved = json.loads((REPO / face["detections"]["file"]).read_text(encoding="utf-8"))
        view = (saved.get("views") or saved["response"]["views"])[face["detections"]["view"]]
        try:
            image = prepared_bgr(face, saved, mutaa)
        except FileNotFoundError:
            continue
        spans, groups = count_layers_by_span(view["detections"]), _columns(view["detections"])
        columns = []
        for span, group in zip(spans, groups, strict=False):
            widths = sorted(d["width"] for d in group)
            columns.append({**span, "x_centre": float(np.median([d["x"] for d in group])), "box_width_px": float(widths[len(widths) // 2])})
        columns.sort(key=lambda c: c["x_min"])
        stacks = face["truth"].get("per_stack") if face.get("truth") else None
        for k, (column, r) in enumerate(zip(columns, cross_stack(image, columns, DEFAULT_PARAMS), strict=False), 1):
            t, tier = truth.get((face["id"], k), (None, None))
            if t is None and stacks and len(stacks) == len(columns):
                t, tier = stacks[k - 1], "V-consensus"
            a = annotations.get((face["id"], k))
            rows.append({"face": face["id"], "column": k, "walk": column["walk_count"], "truth": t, "tier": tier,
                         "readable": r["readable"], "reason": r["reason"], "top_type": (r["top"] or {}).get("type"),
                         "top_eggs": (r["top"] or {}).get("eggs"), "bottom_type": (r["bottom"] or {}).get("type"),
                         "bottom_eggs": (r["bottom"] or {}).get("eggs"), "unboxed_above": r["unboxed_above"],
                         "unboxed_below": r["unboxed_below"], "empty_trays_above": r["empty_trays_above"],
                         "parity": r["parity"], "doubts": r["doubts"],
                         "annotated": None if a is None else {"top": a["top"]["type"], "bottom": a["bottom"]["type"],
                                                               "parity": a["parity"]}})
    typed = [(r, end) for r in rows if r["annotated"] for end in ("top", "bottom") if r[f"{end}_type"] is not None]
    type_ok = sum(r[f"{end}_type"] == r["annotated"][end] for r, end in typed)
    known = []
    for face, col, _ in KNOWN_WRONG:
        row = next((r for r in rows if r["face"] == face and r["column"] == col), None)
        if row:
            known.append({"face": face, "column": col, "walk": row["walk"], "doubts": row["doubts"], "readable": row["readable"],
                          "reason": row["reason"], "top": row["top_type"], "bottom": row["bottom_type"],
                          "unboxed": [row["unboxed_above"], row["unboxed_below"]]})
    correct = [r for r in rows if r["truth"] is not None and r["walk"] == r["truth"]]
    false_flags = [r for r in correct if r["doubts"]]
    far = [r for r in rows if r["face"] == "mutaa:W05-ORANGE:straight"]
    summary = {
        "params": {k: getattr(DEFAULT_PARAMS, k) for k in DEFAULT_PARAMS.__dataclass_fields__},
        "columns": len(rows), "readable": sum(r["readable"] for r in rows),
        "annotated_end_layers_typed": len(typed), "type_matches": type_ok,
        "type_accuracy": round(type_ok / len(typed), 3) if typed else None,
        "type_mismatches": [f"{r['face']}#{r['column']} {end}: {r[end + '_type']} vs {r['annotated'][end]}"
                            for r, end in typed if r[end + "_type"] != r["annotated"][end]],
        "known_wrong": known,
        "correct_columns": len(correct), "false_flags": [f"{r['face']}#{r['column']} {r['doubts']}" for r in false_flags],
        "faces_with_false_flags": sorted({r["face"] for r in false_flags}),
        "far_face_columns_readable": sum(r["readable"] for r in far), "far_face_columns": len(far),
    }
    summary["pass"] = {
        "type_accuracy_at_least_95pct": bool(typed) and type_ok >= 0.95 * len(typed),
        "known_visible_misses_flagged": all(k["doubts"] for k in known if k["readable"] or k["unboxed"] != [0, 0]),
        "at_most_one_correct_face_flagged": len(summary["faces_with_false_flags"]) <= 1,
        "far_faces_unreadable": summary["far_face_columns_readable"] == 0,
    }
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "results.json").write_text(json.dumps({"summary": summary, "rows": rows}, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in summary.items() if k != "params"}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
