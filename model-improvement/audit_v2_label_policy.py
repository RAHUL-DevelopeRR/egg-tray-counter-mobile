"""Prioritize frozen-V2 images that may use a whole-stack egg_tray box."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def read_boxes(path: Path) -> list[tuple[float, float, float, float]]:
    boxes = []
    for line in path.read_text(encoding="utf-8").splitlines():
        values = line.split()
        if len(values) >= 5:
            boxes.append(tuple(map(float, values[1:5])))
    return boxes


def audit(manifest: Path, dataset: Path) -> list[dict[str, object]]:
    rows = list(csv.DictReader(manifest.open(encoding="utf-8-sig")))
    result = []
    for row in rows:
        image_path = dataset / Path(row["path"])
        label_path = (dataset / Path(row["path"].replace("/images/", "/labels/"))).with_suffix(".txt")
        if not image_path.is_file() or not label_path.is_file():
            raise RuntimeError(f"Cannot resolve V2 member {row['path']} in {dataset}")
        boxes = read_boxes(label_path)
        areas = [width * height for _, _, width, height in boxes]
        max_area = max(areas, default=0.0)
        max_width = max((width for _, _, width, _ in boxes), default=0.0)
        max_height = max((height for _, _, _, height in boxes), default=0.0)
        reasons = []
        if len(boxes) <= 5:
            reasons.append("low_annotation_count")
        if max_area >= 0.12:
            reasons.append("large_box_area")
        if max_width >= 0.60 or max_height >= 0.45:
            reasons.append("stack_scale_box")
        priority = 0 if "stack_scale_box" in reasons else 1 if reasons else 2
        result.append(
            {
                "priority": priority,
                "split": row["split"],
                "v2_path": row["path"],
                "image": image_path.as_posix(),
                "label": label_path.as_posix(),
                "annotations": len(boxes),
                "max_box_area": f"{max_area:.6f}",
                "max_box_width": f"{max_width:.6f}",
                "max_box_height": f"{max_height:.6f}",
                "review_reason": "|".join(reasons) or "routine_policy_review",
                "review_status": "pending",
                "review_note": "",
            }
        )
    return sorted(result, key=lambda item: (item["priority"], item["annotations"], item["image"]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path("model-improvement/01-dataset-audit/v2-image-manifest.csv"))
    parser.add_argument("--dataset", type=Path, default=Path("work/v2-frozen-export-20260902"))
    parser.add_argument("--output", type=Path, default=Path("model-improvement/01-dataset-audit/v2-label-policy-review.csv"))
    args = parser.parse_args()
    rows = audit(args.manifest, args.dataset)
    if args.output.is_file():
        previous = {
            row["v2_path"]: row
            for row in csv.DictReader(args.output.open(encoding="utf-8-sig"))
        }
        for row in rows:
            old = previous.get(str(row["v2_path"]), {})
            row["review_status"] = old.get("review_status", "pending")
            row["review_note"] = old.get("review_note", "")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    flagged = sum(row["priority"] < 2 for row in rows)
    print(f"audited={len(rows)} flagged={flagged} output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
