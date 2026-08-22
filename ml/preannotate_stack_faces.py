"""Build review-only stack-face suggestions from canonical egg-tray labels.

This is deliberately a weak heuristic, not a labeling or counting model. It
groups vertically adjacent, horizontally aligned tray boxes and wraps each
group in a rectangular polygon for human correction in Label Studio.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from statistics import median
from urllib.parse import quote


PROJECT_ROOT = Path(__file__).resolve().parents[1]
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


@dataclass(frozen=True)
class Box:
    left: float
    top: float
    right: float
    bottom: float

    @property
    def width(self) -> float:
        return self.right - self.left

    @property
    def height(self) -> float:
        return self.bottom - self.top

    @property
    def center_x(self) -> float:
        return (self.left + self.right) / 2


def clipped_box(values: list[float]) -> Box | None:
    if len(values) == 4:
        center_x, center_y, width, height = values
        left, right = center_x - width / 2, center_x + width / 2
        top, bottom = center_y - height / 2, center_y + height / 2
    elif len(values) >= 6 and len(values) % 2 == 0:
        xs, ys = values[0::2], values[1::2]
        left, right, top, bottom = min(xs), max(xs), min(ys), max(ys)
    else:
        return None
    box = Box(
        max(0.0, left),
        max(0.0, top),
        min(1.0, right),
        min(1.0, bottom),
    )
    return box if box.width > 0 and box.height > 0 else None


def read_boxes(label_path: Path) -> tuple[list[Box], int]:
    boxes: list[Box] = []
    skipped = 0
    if not label_path.exists():
        return boxes, skipped
    for raw in label_path.read_text(encoding="utf-8-sig").splitlines():
        parts = raw.split()
        try:
            box = clipped_box([float(value) for value in parts[1:]])
        except (ValueError, IndexError):
            box = None
        if box is None:
            skipped += 1
        else:
            boxes.append(box)
    return boxes, skipped


def horizontal_overlap(a: Box, b: Box) -> float:
    overlap = max(0.0, min(a.right, b.right) - max(a.left, b.left))
    return overlap / min(a.width, b.width)


def vertical_gap(a: Box, b: Box) -> float:
    if a.bottom < b.top:
        return b.top - a.bottom
    if b.bottom < a.top:
        return a.top - b.bottom
    return 0.0


def cluster_boxes(
    boxes: list[Box],
    *,
    min_x_overlap: float,
    max_x_center_distance: float,
    max_vertical_gap: float,
    height_gap_multiplier: float,
    padding: float,
) -> list[tuple[Box, int]]:
    if not boxes:
        return []
    parents = list(range(len(boxes)))

    def find(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(first: int, second: int) -> None:
        first_root, second_root = find(first), find(second)
        if first_root != second_root:
            parents[second_root] = first_root

    typical_height = median(box.height for box in boxes)
    allowed_gap = max(max_vertical_gap, typical_height * height_gap_multiplier)
    for first in range(len(boxes)):
        for second in range(first + 1, len(boxes)):
            a, b = boxes[first], boxes[second]
            x_aligned = horizontal_overlap(a, b) >= min_x_overlap
            x_aligned |= abs(a.center_x - b.center_x) <= (
                max_x_center_distance * max(a.width, b.width)
            )
            if x_aligned and vertical_gap(a, b) <= allowed_gap:
                union(first, second)

    groups: dict[int, list[Box]] = {}
    for index, box in enumerate(boxes):
        groups.setdefault(find(index), []).append(box)

    envelopes: list[tuple[Box, int]] = []
    for members in groups.values():
        envelope = Box(
            max(0.0, min(box.left for box in members) - padding),
            max(0.0, min(box.top for box in members) - padding),
            min(1.0, max(box.right for box in members) + padding),
            min(1.0, max(box.bottom for box in members) + padding),
        )
        envelopes.append((envelope, len(members)))
    return sorted(envelopes, key=lambda item: (item[0].left, item[0].top))


def polygon_result(index: int, envelope: Box, member_count: int) -> dict[str, object]:
    points = [
        [envelope.left * 100, envelope.top * 100],
        [envelope.right * 100, envelope.top * 100],
        [envelope.right * 100, envelope.bottom * 100],
        [envelope.left * 100, envelope.bottom * 100],
    ]
    return {
        "id": f"stack-{index}",
        "from_name": "label",
        "to_name": "image",
        "type": "polygonlabels",
        "score": min(0.49, 0.20 + 0.02 * member_count),
        "value": {"points": points, "polygonlabels": ["stack_face"]},
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dataset-root",
        type=Path,
        default=PROJECT_ROOT / "datasets" / "canonical_clean",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=PROJECT_ROOT / "datasets" / "stack_face_review" / "tasks.json",
    )
    parser.add_argument("--min-x-overlap", type=float, default=0.45)
    parser.add_argument("--max-x-center-distance", type=float, default=0.35)
    parser.add_argument("--max-vertical-gap", type=float, default=0.04)
    parser.add_argument("--height-gap-multiplier", type=float, default=2.5)
    parser.add_argument("--padding", type=float, default=0.01)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = args.dataset_root / "manifest.csv"
    if not manifest_path.exists():
        raise FileNotFoundError(f"Canonical manifest not found: {manifest_path}")

    tasks: list[dict[str, object]] = []
    totals = {"images": 0, "source_boxes": 0, "stack_suggestions": 0, "skipped_labels": 0}
    for split in ("train", "valid", "test"):
        image_dir = args.dataset_root / split / "images"
        label_dir = args.dataset_root / split / "labels"
        for image_path in sorted(path for path in image_dir.iterdir() if path.suffix.lower() in IMAGE_SUFFIXES):
            boxes, skipped = read_boxes(label_dir / f"{image_path.stem}.txt")
            envelopes = cluster_boxes(
                boxes,
                min_x_overlap=args.min_x_overlap,
                max_x_center_distance=args.max_x_center_distance,
                max_vertical_gap=args.max_vertical_gap,
                height_gap_multiplier=args.height_gap_multiplier,
                padding=args.padding,
            )
            results = [
                polygon_result(index, envelope, count)
                for index, (envelope, count) in enumerate(envelopes, start=1)
            ]
            relative_image = quote(f"canonical_clean/{split}/images/{image_path.name}", safe="/")
            tasks.append(
                {
                    "id": len(tasks) + 1,
                    "data": {
                        "image": f"/data/local-files/?d={relative_image}",
                        "canonical_image_id": image_path.stem,
                        "split": split,
                        "source_egg_tray_count": len(boxes),
                        "heuristic_stack_count": len(results),
                        "review_required": True,
                    },
                    "predictions": [
                        {
                            "model_version": "heuristic-vertical-clustering-v1",
                            "score": 0.25 if results else 0.0,
                            "result": results,
                        }
                    ],
                }
            )
            totals["images"] += 1
            totals["source_boxes"] += len(boxes)
            totals["stack_suggestions"] += len(results)
            totals["skipped_labels"] += skipped

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(tasks, indent=2), encoding="utf-8")
    print(json.dumps(totals, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
