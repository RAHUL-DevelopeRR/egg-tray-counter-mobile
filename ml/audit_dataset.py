"""Read-only YOLO detection/segmentation dataset audit."""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps, UnidentifiedImageError

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}
SPLITS = ("train", "valid", "test")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def dhash(path: Path) -> str:
    with Image.open(path) as image:
        pixels = list(ImageOps.exif_transpose(image).convert("L").resize((9, 8)).getdata())
    bits = [pixels[row * 9 + col] > pixels[row * 9 + col + 1] for row in range(8) for col in range(8)]
    return f"{sum(int(bit) << index for index, bit in enumerate(bits)):016x}"


def polygon_area(values: list[float]) -> float:
    points = list(zip(values[0::2], values[1::2]))
    return abs(sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(points, points[1:] + points[:1]))) / 2


def annotation_box(values: list[float]) -> tuple[float, float, float, float]:
    if len(values) == 4:
        x, y, width, height = values
        return x - width / 2, y - height / 2, x + width / 2, y + height / 2
    xs, ys = values[0::2], values[1::2]
    return min(xs), min(ys), max(xs), max(ys)


def iou(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    x1, y1, x2, y2 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    intersection = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    union = max(0.0, a[2] - a[0]) * max(0.0, a[3] - a[1]) + max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1]) - intersection
    return intersection / union if union else 0.0


def read_classes(root: Path) -> list[str]:
    yaml = root / "data.yaml"
    if not yaml.exists():
        return []
    for line in yaml.read_text(encoding="utf-8-sig").splitlines():
        if line.strip().startswith("names:"):
            raw = line.split(":", 1)[1].strip().strip("[]")
            return [item.strip().strip("'\"") for item in raw.split(",") if item.strip()]
    return []


def parse_label(path: Path, duplicate_iou: float) -> dict[str, Any]:
    annotations: list[dict[str, Any]] = []
    issues: list[dict[str, Any]] = []
    seen: set[tuple[float | int, ...]] = set()
    for line_number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            fields = raw.split()
            class_id = int(fields[0])
            values = [float(value) for value in fields[1:]]
        except (ValueError, IndexError) as exc:
            issues.append({"line": line_number, "type": "malformed", "detail": str(exc)})
            continue
        kind = "bbox" if len(values) == 4 else "polygon" if len(values) >= 6 and len(values) % 2 == 0 else "malformed"
        key = (class_id, *[round(value, 8) for value in values])
        if kind == "malformed":
            issues.append({"line": line_number, "type": "malformed", "detail": f"{len(values)} coordinates"})
            continue
        if key in seen:
            issues.append({"line": line_number, "type": "exact_duplicate_annotation"})
        seen.add(key)
        if class_id < 0:
            issues.append({"line": line_number, "type": "negative_class_id"})
        if any(value < 0 or value > 1 for value in values):
            issues.append({"line": line_number, "type": "coordinate_out_of_bounds"})
        if kind == "bbox" and (values[2] <= 0 or values[3] <= 0):
            issues.append({"line": line_number, "type": "zero_area"})
        if kind == "polygon" and (len(set(zip(values[0::2], values[1::2]))) < 3 or polygon_area(values) <= 1e-8):
            issues.append({"line": line_number, "type": "zero_area"})
        box = annotation_box(values)
        if box[0] < 0 or box[1] < 0 or box[2] > 1 or box[3] > 1:
            issues.append({"line": line_number, "type": "geometry_outside_image"})
        annotations.append({"line": line_number, "class_id": class_id, "kind": kind, "values": values, "bbox": box})

    overlaps: list[dict[str, Any]] = []
    for index, first in enumerate(annotations):
        for second in annotations[index + 1 :]:
            if first["class_id"] != second["class_id"]:
                continue
            score = iou(tuple(first["bbox"]), tuple(second["bbox"]))
            if score >= duplicate_iou:
                overlaps.append({"lines": [first["line"], second["line"]], "iou": round(score, 6)})
    return {"annotations": annotations, "issues": issues, "high_overlap_pairs": overlaps}


def build_audit(root: Path, duplicate_iou: float = 0.85) -> dict[str, Any]:
    classes = read_classes(root)
    records: list[dict[str, Any]] = []
    label_records: list[dict[str, Any]] = []
    sha_groups: dict[str, list[str]] = defaultdict(list)
    class_counts: Counter[int] = Counter()
    kind_counts: Counter[str] = Counter()
    issue_counts: Counter[str] = Counter()
    widths: list[int] = []
    heights: list[int] = []
    box_areas: list[float] = []
    missing_labels: list[str] = []
    orphan_labels: list[str] = []
    split_counts: dict[str, dict[str, int]] = {}

    for split in SPLITS:
        image_dir, label_dir = root / split / "images", root / split / "labels"
        images = sorted(path for path in image_dir.glob("*") if path.suffix.lower() in IMAGE_EXTENSIONS) if image_dir.exists() else []
        labels = sorted(label_dir.glob("*.txt")) if label_dir.exists() else []
        image_by_stem = {path.stem: path for path in images}
        label_by_stem = {path.stem: path for path in labels}
        missing_labels.extend(f"{split}/images/{stem}{image_by_stem[stem].suffix}" for stem in sorted(image_by_stem.keys() - label_by_stem.keys()))
        orphan_labels.extend(f"{split}/labels/{stem}.txt" for stem in sorted(label_by_stem.keys() - image_by_stem.keys()))
        split_counts[split] = {"images": len(images), "labels": len(labels)}
        for image in images:
            relative = image.relative_to(root).as_posix()
            try:
                digest = sha256_file(image)
                with Image.open(image) as opened:
                    opened.verify()
                with Image.open(image) as opened:
                    width, height = ImageOps.exif_transpose(opened).size
                perceptual = dhash(image)
                error = None
                widths.append(width)
                heights.append(height)
                sha_groups[digest].append(relative)
            except (OSError, ValueError, UnidentifiedImageError) as exc:
                digest = perceptual = None
                width = height = None
                error = f"{type(exc).__name__}: {exc}"
            records.append({"path": relative, "split": split, "width": width, "height": height, "sha256": digest, "dhash": perceptual, "error": error})
        for label in labels:
            parsed = parse_label(label, duplicate_iou)
            for annotation in parsed["annotations"]:
                class_counts[annotation["class_id"]] += 1
                kind_counts[annotation["kind"]] += 1
                box = annotation["bbox"]
                box_areas.append(max(0.0, box[2] - box[0]) * max(0.0, box[3] - box[1]))
            issue_counts.update(issue["type"] for issue in parsed["issues"])
            issue_counts["high_overlap_pair"] += len(parsed["high_overlap_pairs"])
            label_records.append({"path": label.relative_to(root).as_posix(), "split": split, **parsed})

    duplicate_groups = [{"sha256": digest, "paths": paths} for digest, paths in sha_groups.items() if len(paths) > 1]
    split_leakage = [group for group in duplicate_groups if len({path.split("/", 1)[0] for path in group["paths"]}) > 1]
    corrupt = [record for record in records if record["error"]]
    return {
        "source": str(root.resolve()), "source_is_read_only_by_policy": True,
        "format": "YOLO detection/segmentation text", "classes": classes,
        "duplicate_iou_threshold": duplicate_iou,
        "summary": {
            "images": len(records), "labels": len(label_records), "annotations": sum(class_counts.values()),
            "corrupt_images": len(corrupt), "missing_labels": len(missing_labels), "orphan_labels": len(orphan_labels),
            "duplicate_image_groups": len(duplicate_groups), "split_leakage_groups": len(split_leakage),
        },
        "splits": split_counts, "class_distribution": {str(key): value for key, value in sorted(class_counts.items())},
        "annotation_types": dict(kind_counts), "issue_counts": dict(issue_counts), "missing_labels": missing_labels,
        "orphan_labels": orphan_labels, "corrupt_images": corrupt, "duplicate_images": duplicate_groups,
        "split_leakage": split_leakage,
        "image_resolution": {
            "unique": len(set(zip(widths, heights))),
            "width_min": min(widths) if widths else None, "width_median": statistics.median(widths) if widths else None, "width_max": max(widths) if widths else None,
            "height_min": min(heights) if heights else None, "height_median": statistics.median(heights) if heights else None, "height_max": max(heights) if heights else None,
        },
        "annotation_area": {
            "min": min(box_areas) if box_areas else None, "median": statistics.median(box_areas) if box_areas else None, "max": max(box_areas) if box_areas else None,
        },
        "images": records, "labels": label_records,
    }


def render_markdown(audit: dict[str, Any], title: str) -> str:
    summary = audit["summary"]
    lines = [
        f"# {title}", "", f"Source: `{audit['source']}`", "",
        "> Read-only audit: source images and labels were not changed.", "", "## Summary", "",
        f"- Format: {audit['format']}", f"- Classes: `{json.dumps(audit['classes'])}`",
        f"- Images / labels / annotations: {summary['images']} / {summary['labels']} / {summary['annotations']}",
        f"- Split counts: `{json.dumps(audit['splits'], sort_keys=True)}`",
        f"- Annotation types: `{json.dumps(audit['annotation_types'], sort_keys=True)}`",
        f"- Class distribution: `{json.dumps(audit['class_distribution'], sort_keys=True)}`",
        f"- Corrupt images: {summary['corrupt_images']}", f"- Missing / orphan labels: {summary['missing_labels']} / {summary['orphan_labels']}",
        f"- Exact duplicate image groups: {summary['duplicate_image_groups']}", f"- Cross-split duplicate leakage groups: {summary['split_leakage_groups']}",
        "", "## Annotation QA", "", f"Candidate duplicate IoU threshold: {audit['duplicate_iou_threshold']}", "",
    ]
    lines.extend(f"- {name}: {count}" for name, count in sorted(audit["issue_counts"].items()))
    if not audit["issue_counts"]:
        lines.append("No geometry, parsing, exact-duplicate, or high-overlap issues detected.")
    lines.extend(["", "## Distribution", "", f"- Image resolution: `{json.dumps(audit['image_resolution'], sort_keys=True)}`", f"- Normalized annotation area: `{json.dumps(audit['annotation_area'], sort_keys=True)}`", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--markdown-output", type=Path, required=True)
    parser.add_argument("--title", default="Dataset Audit")
    parser.add_argument("--duplicate-iou", type=float, default=0.85)
    args = parser.parse_args()
    if not args.source.is_dir():
        parser.error(f"dataset not found: {args.source}")
    audit = build_audit(args.source, args.duplicate_iou)
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.markdown_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(audit, indent=2), encoding="utf-8")
    args.markdown_output.write_text(render_markdown(audit, args.title), encoding="utf-8")
    print(json.dumps(audit["summary"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
