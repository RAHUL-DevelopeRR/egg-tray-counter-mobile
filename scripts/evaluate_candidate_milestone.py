"""Replay frozen MUTAA evidence locally; never call RF or modify frozen reports."""

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

from app.schemas.candidate import CandidateEvidence, CandidateResponse
from app.vision.regional_quality import regional_stack_quality
from app.vision.spatial_3d import assemble_grid, propose_correspondence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("reports/mutaa-20260916"))
    parser.add_argument(
        "--output", type=Path, default=Path("reports/candidate-20260917")
    )
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        raise ValueError("Preserve frozen source")
    args.output.mkdir(parents=True, exist_ok=True)
    cv2.setNumThreads(1)

    def save(name, data):
        (args.output / name).write_text(
            json.dumps(data, indent=2, allow_nan=False) + "\n", encoding="utf-8"
        )

    manifest = json.loads((args.source / "manifest.json").read_text())
    results, images, views, codes = [], {}, {}, Counter()
    # This is an explicitly unconfirmed grouping from the prior audit, not a scored same-scene test.
    tentative = {"image-07": "straight", "image-10": "left", "image-11": "right"}
    for entry in manifest["images"]:
        content = (args.source / entry["original"]).read_bytes()
        assert hashlib.sha256(content).hexdigest() == entry["sha256"]
        with Image.open(args.source / entry["original"]) as source:
            image = cv2.cvtColor(
                np.asarray(ImageOps.exif_transpose(source).convert("RGB")),
                cv2.COLOR_RGB2BGR,
            )
        old = json.loads(
            (args.source / "analysis" / (entry["id"] + ".json")).read_text()
        )
        stacks = [
            {
                "stack_id": s["stack_id"],
                "polygon": s["polygon"],
                "rf_count": s["rf_count"],
                "historical_beam": {
                    k: s["beam"].get(k)
                    for k in (
                        "exploratory_band_count",
                        "selected_count",
                        "tray_count_candidates",
                        "harmonic_ambiguity",
                        "reason",
                    )
                },
                "full_beam_source": f"../mutaa-20260916/analysis/{entry['id']}.json",
                "regional_quality": regional_stack_quality(
                    image, s, tentative.get(entry["id"], "straight")
                ),
            }
            for s in old["stacks"]
        ]
        for stack in stacks:
            codes.update(
                r["code"] for r in stack["regional_quality"]["recommendations"]
            )
        record = {
            "id": entry["id"],
            "sha256": entry["sha256"],
            "ground_truth_status": "GROUND_TRUTH_UNKNOWN",
            "view_assignment_confirmed": False,
            "rf_count": old["rf_count"],
            "stacks": stacks,
            "quality_scope": "proposed faces only; missed/partial faces remain unassessed",
            "rf_and_beam_source": "frozen 20260916 audit; no fresh model calls",
        }
        save(entry["id"] + "-quality.json", record)
        results.append(
            {
                "id": entry["id"],
                "rf_count": old["rf_count"],
                "proposed_faces": len(stacks),
            }
        )
        if entry["id"] in tentative:
            view = tentative[entry["id"]]
            images[view], views[view] = image, old
        print(entry["id"], len(stacks), "faces", flush=True)
    correspondence = propose_correspondence(images, views)
    save(
        "correspondence.json",
        {
            "group": tentative,
            "same_scene_confirmed": False,
            "ground_truth_status": "GROUND_TRUTH_UNKNOWN",
            "proposals": correspondence,
            "accepted_identities": 0,
            "accuracy": None,
        },
    )
    save(
        "quality-summary.json",
        {
            "images": results,
            "recommendation_counts": codes,
            "thresholds_validated": False,
            "accuracy": None,
            "new_model_calls": 0,
        },
    )
    for name, model in (
        ("request-schema.json", CandidateEvidence),
        ("response-schema.json", CandidateResponse),
    ):
        save(name, model.model_json_schema())
    synthetic = []
    for case in (
        "full",
        "rear_x3_absent",
        "rear_x3_short",
        "shared_front_right",
        "shared_left_right",
        "extra_empty",
        "unknown_occupancy",
        "hidden_rear",
    ):
        items = [
            {
                "id": f"fixture-{x}-{y}",
                "x": x,
                "y": y,
                "view": "straight",
                "geometry_evidence": "synthetic explicit geometry",
                "layers": ["filled"] * 20,
            }
            for y in range(2)
            for x in range(5)
        ]
        absent = ()
        expected = 200
        if case in ("rear_x3_absent", "hidden_rear"):
            items.pop(7)
            absent = ((2, 1),) if case == "rear_x3_absent" else ()
            expected = 180 if absent else None
        elif case == "rear_x3_short":
            items[7]["layers"] = ["filled"] * 15
            expected = 195
        elif case.startswith("shared"):
            idx = 4 if case == "shared_front_right" else 7
            items[idx]["view"] = "straight" if idx == 4 else "left"
            items.append({**items[idx], "id": "repeat-right", "view": "right"})
        elif case == "extra_empty":
            items[0]["layers"].append("empty")
        elif case == "unknown_occupancy":
            items[0]["layers"][0] = "unknown"
            expected = None
        result = assemble_grid(
            items, x_columns=5, y_rows=2, absent_cells=absent, complete_coverage=True
        )
        assert result["eligible_egg_trays"] == expected
        synthetic.append(
            {"case": case, "expected_eligible": expected, "result": result}
        )
    save("synthetic-grid.json", synthetic)


if __name__ == "__main__":
    main()
