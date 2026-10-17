"""Replay trained heatmaps and archived V2 evidence without upstream calls or tuning."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
from app.vision.heatmap_sequence import solve_layer_sequence
from app.vision.stack_measurement import analyze_rims


def counts_metric(predicted, truth):
    errors = np.asarray(predicted) - np.asarray(truth)
    return {"counts": predicted, "references": truth, "stack_exact": int(sum(errors == 0)),
            "stacks": len(truth), "scene_exact": bool(np.all(errors == 0)),
            "mae": float(np.mean(np.abs(errors))), "signed_error": float(np.mean(errors)),
            "missed_layers": None, "duplicate_layers": None, "false_accepted_count": 0,
            "rejection_rate": 1.0, "accepted_scan_accuracy": None,
            "latency_ms": None, "verified": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run = json.loads(args.run.read_text())
    if hashlib.sha256(args.manifest.read_bytes()).hexdigest() != run["config"]["manifest_sha256"]:
        raise ValueError("Evaluation must use the exact frozen manifest recorded by the training run")
    faces = {r["id"]: r for r in json.loads(args.manifest.read_text())}
    archive = ROOT / "reports/two-view-20260924/crop-experiment"
    old = json.loads((archive / "results.json").read_text())
    replay, boards = [], []
    for row in run["metrics"]["rows"]:
        face = faces[row["id"]]
        image = cv2.imread(str(ROOT / face["image_path"]))
        start = time.perf_counter()
        bands = analyze_rims(image)
        scale = (len(row["probabilities"]) - 1) / (image.shape[0] - 1)
        hypotheses = [{**h, "pitch_px": h["pitch_px"] * scale,
                       "centres": [y * scale for y in h["centres"]]}
                      for h in bands["hypotheses"] if 1 <= h["pitch_px"] * scale < len(row["probabilities"])]
        rf = []
        # Archived batch ordering is defined by evaluate_stack_crops.py: five crops,
        # five rectifications, side, wide; LEFT/RIGHT/STRAIGHT for each batch of three.
        if row["id"].startswith("focused-"):
            i = int(row["id"].split("-")[1])
            item_index = 4 + i
            payload = json.loads((archive / f"batch-{item_index // 3 + 1}.json").read_text())
            view = ("left", "right", "straight")[item_index % 3]
            rf = [{"y": d["y"] * scale} for d in payload["views"][view]["detections"]]
        outputs = {
            "heatmap_only": solve_layer_sequence(row["probabilities"]),
            "heatmap_bands": solve_layer_sequence(row["probabilities"], band_hypotheses=hypotheses),
            "heatmap_bands_rf": solve_layer_sequence(row["probabilities"], band_hypotheses=hypotheses,
                                                   rf_detections=rf),
        }
        replay.append({"id": row["id"], "reference": row["reference"], "raw_heatmap_count": row["candidate_count"],
                       "band_best": bands["best"], "outputs": outputs,
                       "bands_solver_latency_ms": (time.perf_counter() - start) * 1000})
        panel = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB)).resize((180, 640))
        board = Image.new("RGB", (440, 680), "white"); board.paste(panel, (0, 35)); draw = ImageDraw.Draw(board)
        draw.text((5, 5), f'{row["id"]}: ref {row["reference"]}, ML {row["candidate_count"]}', fill="black")
        # Label positions appear only on QA/evaluation; never feed endpoints to the solver.
        for y in face["centres_y"]:
            draw.line((0, 35 + y * 639, 180, 35 + y * 639), fill="red")
        curve = [(200 + float(p) * 210, 35 + y) for y, p in enumerate(row["probabilities"])]
        draw.line(curve, fill="blue", width=2)
        draw.line((305, 35, 305, 674), fill="gray")
        for peak in row["peaks"]:
            draw.line((180, 35 + peak, 200, 35 + peak), fill="blue", width=2)
        boards.append(board)
    selected = [r for r in run["metrics"]["rows"] if r["id"].startswith("focused-")]
    truth = [r["reference"] for r in selected]
    matrix = {
        "V2_full_frame_archived": {"visible_total": 76, "reference_total": 99, "signed_error": -23,
                                    "per_stack_metrics": None, "scope": "archived diagnostic", "verified": False},
        "V5_clean_full_frame": {"status": "not_trained", "reason": "No eligible reviewed grouped validation/control snapshot"},
        "V2_manual_rectified_archived": counts_metric([r["face_count"] for r in old["results"] if r["mode"] == "rectified"], [20,20,20,20,19]),
        "bands_archived": counts_metric([r["best"]["count"] for r in old["bands"]], [20,20,20,20,19]),
        "heatmap_raw_peaks": counts_metric([r["candidate_count"] for r in selected], truth) if selected else None,
    }
    if selected:
        matrix["heatmap_raw_peaks"].update(missed_layers=sum(r["missed_layers"] for r in selected),
            duplicate_layers=sum(r["duplicate_or_spurious_layers"] for r in selected),
            latency_ms=run["metrics"]["latency_ms_per_stack"], scope=run["evaluation_scope"])
    for name in ("heatmap_only", "heatmap_bands", "heatmap_bands_rf"):
        values = [r["outputs"][name]["selected_count"] for r in replay]
        matrix[name] = {"selected_counts": values, "resolved": sum(v is not None for v in values),
                       "stacks": len(values), "false_accepted_count": 0, "rejection_rate": 1.,
                       "accepted_scan_accuracy": None, "mae": None,
                       "reason": "No independently assessed quality/top/base/occupancy/grid", "verified": False}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "comparison.json").write_text(json.dumps({"scope": run["evaluation_scope"],
        "model_sha256": run["checkpoint_sha256"], "matrix": matrix, "replay": replay}, indent=2))
    sheet = Image.new("RGB", (440 * len(boards), 680), "white")
    for i, board in enumerate(boards): sheet.paste(board, (440 * i, 0))
    sheet.save(args.output / "prediction-qa.jpg")
    (args.output / "run.json").write_text(json.dumps(run, indent=2))
    print(json.dumps({"scope": run["evaluation_scope"], "matrix": matrix}, indent=2))


if __name__ == "__main__": main()
