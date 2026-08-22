"""Compute product-level verification metrics from a JSON file.

Input is a JSON array of scenes. Each scene has ``accepted``,
``total_trays_gt``, ``total_trays_pred`` and a ``stacks`` array with
``tray_count_gt`` and ``tray_count_pred``.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def safe_ratio(numerator: int, denominator: int) -> float | None:
    return numerator / denominator if denominator else None


def calculate_metrics(scenes: list[dict[str, Any]]) -> dict[str, float | int | None]:
    stack_errors: list[int] = []
    exact_stacks = 0
    exact_scenes = 0
    accepted = 0
    accepted_correct = 0
    false_accepts = 0

    for scene in scenes:
        scene_correct = scene.get("total_trays_pred") == scene.get("total_trays_gt")
        if scene_correct:
            exact_scenes += 1
        if scene.get("accepted"):
            accepted += 1
            if scene_correct:
                accepted_correct += 1
            else:
                false_accepts += 1
        for stack in scene.get("stacks", []):
            prediction = stack.get("tray_count_pred")
            ground_truth = stack.get("tray_count_gt")
            if prediction is None or ground_truth is None:
                continue
            error = abs(int(prediction) - int(ground_truth))
            stack_errors.append(error)
            if error == 0:
                exact_stacks += 1

    return {
        "scene_count": len(scenes),
        "evaluated_stack_count": len(stack_errors),
        "exact_stack_accuracy": safe_ratio(exact_stacks, len(stack_errors)),
        "stack_mae": sum(stack_errors) / len(stack_errors) if stack_errors else None,
        "exact_scene_accuracy": safe_ratio(exact_scenes, len(scenes)),
        "coverage": safe_ratio(accepted, len(scenes)),
        "accepted_accuracy": safe_ratio(accepted_correct, accepted),
        "false_accept_rate": safe_ratio(false_accepts, accepted),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    scenes = json.loads(args.input.read_text(encoding="utf-8"))
    if not isinstance(scenes, list):
        raise SystemExit("Input must be a JSON array of scenes")
    metrics = calculate_metrics(scenes)
    rendered = json.dumps(metrics, indent=2)
    print(rendered)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
