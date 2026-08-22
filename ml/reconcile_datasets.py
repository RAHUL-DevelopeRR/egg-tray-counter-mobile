"""Reconcile manual and auto YOLO datasets without changing either source."""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
from collections import Counter
from pathlib import Path
from typing import Any

from audit_dataset import iou

FIELDS = (
    "canonical_image_id", "local_path", "roboflow_path", "sha256", "perceptual_hash",
    "duplicate_type", "local_annotation_count", "roboflow_annotation_count",
    "annotation_agreement", "review_status", "selected_source", "reason",
)


def source_name(path: str) -> str:
    stem = Path(path).stem.lower().split(".rf.", 1)[0]
    stem = re.sub(r"-(am|pm)", "", stem)
    stem = re.sub(r"_(jpeg|jpg|png)$", "", stem)
    return re.sub(r"[^a-z0-9]", "", stem)


def hamming(left: str, right: str) -> int:
    return (int(left, 16) ^ int(right, 16)).bit_count()


def labels_by_image(audit: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result = {}
    for label in audit["labels"]:
        result[label["path"].replace("/labels/", "/images/").rsplit(".", 1)[0]] = label
    return result


def label_for(image_path: str, labels: dict[str, dict[str, Any]]) -> dict[str, Any]:
    key = image_path.rsplit(".", 1)[0]
    return labels.get(key, {"annotations": [], "issues": [], "high_overlap_pairs": []})


def clean_boxes(label: dict[str, Any], manual: bool) -> tuple[list[tuple[float, float, float, float]], list[str], int]:
    boxes: list[tuple[float, float, float, float]] = []
    fixes: list[str] = []
    removed = 0
    for annotation in label["annotations"]:
        x1, y1, x2, y2 = annotation["bbox"]
        clipped = max(0.0, x1), max(0.0, y1), min(1.0, x2), min(1.0, y2)
        if clipped != (x1, y1, x2, y2):
            if not manual:
                return [], ["auto_geometry_requires_review"], removed
            fixes.append("clipped_manual_export_geometry")
        if clipped[2] <= clipped[0] or clipped[3] <= clipped[1]:
            return [], ["zero_area_requires_review"], removed
        if any(iou(clipped, existing) >= 0.98 for existing in boxes):
            removed += 1
            fixes.append("removed_near_identical_duplicate")
            continue
        boxes.append(clipped)
    ambiguous = any(0.85 <= iou(first, second) < 0.98 for index, first in enumerate(boxes) for second in boxes[index + 1 :])
    if ambiguous and not manual:
        return [], [*fixes, "high_overlap_requires_review"], removed
    return boxes, fixes, removed


def agreement(left: list[tuple[float, float, float, float]], right: list[tuple[float, float, float, float]]) -> float:
    if not left and not right:
        return 1.0
    if not left or not right:
        return 0.0
    available = set(range(len(right)))
    scores = []
    for box in left:
        if not available:
            scores.append(0.0)
            continue
        best = max(available, key=lambda index: iou(box, right[index]))
        scores.append(iou(box, right[best]))
        available.remove(best)
    return round(sum(scores) / max(len(left), len(right)), 4)


def write_yolo(path: Path, boxes: list[tuple[float, float, float, float]]) -> None:
    lines = []
    for x1, y1, x2, y2 in boxes:
        lines.append(f"0 {(x1 + x2) / 2:.8f} {(y1 + y2) / 2:.8f} {x2 - x1:.8f} {y2 - y1:.8f}")
    path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--local-root", type=Path, required=True)
    parser.add_argument("--cloud-root", type=Path, required=True)
    parser.add_argument("--local-audit", type=Path, required=True)
    parser.add_argument("--cloud-audit", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    local_audit = json.loads(args.local_audit.read_text(encoding="utf-8"))
    cloud_audit = json.loads(args.cloud_audit.read_text(encoding="utf-8"))
    local_labels, cloud_labels = labels_by_image(local_audit), labels_by_image(cloud_audit)
    local_images, cloud_images = local_audit["images"], cloud_audit["images"]

    candidates = []
    for local in local_images:
        for cloud in cloud_images:
            distance = hamming(local["dhash"], cloud["dhash"])
            if distance <= 6:
                candidates.append((distance, source_name(local["path"]) != source_name(cloud["path"]), local["path"], cloud["path"]))
    matched_local: dict[str, str] = {}
    matched_cloud: set[str] = set()
    for _, _, local_path, cloud_path in sorted(candidates):
        if local_path not in matched_local and cloud_path not in matched_cloud:
            matched_local[local_path] = cloud_path
            matched_cloud.add(cloud_path)

    canonical = args.output_root / "datasets" / "canonical_clean"
    review = args.output_root / "datasets" / "review"
    reports = args.output_root / "reports"
    for split in ("train", "valid", "test"):
        (canonical / split / "images").mkdir(parents=True, exist_ok=True)
        (canonical / split / "labels").mkdir(parents=True, exist_ok=True)
    (review / "images").mkdir(parents=True, exist_ok=True)
    reports.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, Any]] = []
    manifest: list[dict[str, Any]] = []
    review_tasks: list[dict[str, Any]] = []
    stats: Counter[str] = Counter()
    copied_cloud_hashes: set[str] = set()

    def queue_review(source: str, record: dict[str, Any], boxes: list[tuple[float, float, float, float]], reason: str) -> None:
        source_root = args.local_root if source == "manual_original" else args.cloud_root
        image = source_root / record["path"]
        target_name = f"{source}-{record['sha256'][:12]}{image.suffix.lower()}"
        target = review / "images" / target_name
        if not target.exists():
            shutil.copy2(image, target)
        results = [{
            "id": f"box-{index}", "from_name": "label", "to_name": "image", "type": "rectanglelabels",
            "value": {"x": x1 * 100, "y": y1 * 100, "width": (x2 - x1) * 100, "height": (y2 - y1) * 100, "rectanglelabels": ["egg_tray"]},
        } for index, (x1, y1, x2, y2) in enumerate(boxes, 1)]
        review_tasks.append({
            "data": {"image": f"/data/local-files/?d=images/{target_name}", "source": source, "reason": reason},
            "predictions": [{"model_version": source, "score": 0.5, "result": results}],
        })

    def add_canonical(source: str, root: Path, record: dict[str, Any], boxes: list[tuple[float, float, float, float]], fixes: list[str]) -> None:
        split = record["split"]
        source_image = root / record["path"]
        image_id = record["sha256"][:20]
        target_image = canonical / split / "images" / f"{image_id}{source_image.suffix.lower()}"
        target_label = canonical / split / "labels" / f"{image_id}.txt"
        shutil.copy2(source_image, target_image)
        write_yolo(target_label, boxes)
        manifest.append({
            "canonical_image_id": image_id, "split": split, "selected_source": source,
            "source_path": str(source_image), "sha256": record["sha256"], "dhash": record["dhash"],
            "annotation_count": len(boxes), "provenance": "manual_original" if source == "local" else "roboflow_auto",
            "automatic_corrections": "|".join(sorted(set(fixes))),
        })

    for local in local_images:
        local_label = label_for(local["path"], local_labels)
        local_boxes, local_fixes, local_removed = clean_boxes(local_label, manual=True)
        stats["duplicate_annotations_removed"] += local_removed
        cloud_path = matched_local.get(local["path"])
        cloud_label = label_for(cloud_path, cloud_labels) if cloud_path else {"annotations": [], "issues": [], "high_overlap_pairs": []}
        cloud_boxes, _, _ = clean_boxes(cloud_label, manual=False)
        score = agreement(local_boxes, cloud_boxes)
        needs_review = bool(cloud_path and (len(local_boxes) != len(cloud_boxes) or score < 0.5))
        reason = "manual annotation selected over overlapping auto annotation" if cloud_path else "unique manual image"
        rows.append({
            "canonical_image_id": local["sha256"][:20], "local_path": str(args.local_root / local["path"]),
            "roboflow_path": str(args.cloud_root / cloud_path) if cloud_path else "", "sha256": local["sha256"],
            "perceptual_hash": local["dhash"], "duplicate_type": "near_duplicate" if cloud_path else "unique_local",
            "local_annotation_count": len(local_boxes), "roboflow_annotation_count": len(cloud_boxes),
            "annotation_agreement": score if cloud_path else "", "review_status": "queued" if needs_review else "resolved",
            "selected_source": "manual_original", "reason": reason,
        })
        add_canonical("local", args.local_root, local, local_boxes, local_fixes)
        stats["manual_images"] += 1
        if cloud_path:
            stats["manual_replaced_auto"] += 1
        if needs_review:
            queue_review("manual_original", local, local_boxes, "manual_vs_auto_disagreement")
            stats["conflicts_queued"] += 1

    for cloud in cloud_images:
        if cloud["path"] in matched_cloud:
            continue
        if cloud["sha256"] in copied_cloud_hashes:
            stats["exact_duplicate_images_removed"] += 1
            continue
        copied_cloud_hashes.add(cloud["sha256"])
        label = label_for(cloud["path"], cloud_labels)
        boxes, fixes, removed = clean_boxes(label, manual=False)
        stats["duplicate_annotations_removed"] += removed
        review_reason = next((fix for fix in fixes if fix.endswith("requires_review")), None)
        if review_reason:
            raw_boxes = [tuple(annotation["bbox"]) for annotation in label["annotations"]]
            queue_review("roboflow_auto", cloud, raw_boxes, review_reason)
            stats["auto_images_queued"] += 1
            rows.append({
                "canonical_image_id": "", "local_path": "", "roboflow_path": str(args.cloud_root / cloud["path"]),
                "sha256": cloud["sha256"], "perceptual_hash": cloud["dhash"], "duplicate_type": "unique_roboflow",
                "local_annotation_count": "", "roboflow_annotation_count": len(label["annotations"]),
                "annotation_agreement": "", "review_status": "queued", "selected_source": "pending_review", "reason": review_reason,
            })
            continue
        add_canonical("cloud", args.cloud_root, cloud, boxes, fixes)
        stats["roboflow_images"] += 1
        rows.append({
            "canonical_image_id": cloud["sha256"][:20], "local_path": "", "roboflow_path": str(args.cloud_root / cloud["path"]),
            "sha256": cloud["sha256"], "perceptual_hash": cloud["dhash"], "duplicate_type": "unique_roboflow",
            "local_annotation_count": "", "roboflow_annotation_count": len(boxes), "annotation_agreement": "",
            "review_status": "resolved", "selected_source": "roboflow_auto", "reason": "unique auto image passed strict QA",
        })

    with (reports / "dataset_reconciliation.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    manifest_fields = list(manifest[0]) if manifest else []
    with (canonical / "manifest.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=manifest_fields)
        writer.writeheader()
        writer.writerows(manifest)
    (canonical / "data.yaml").write_text("path: .\ntrain: train/images\nval: valid/images\ntest: test/images\nnames:\n  0: egg_tray\n", encoding="utf-8")
    (review / "tasks.json").write_text(json.dumps(review_tasks, indent=2), encoding="utf-8")
    (review / "label_config.xml").write_text('<View>\n  <Image name="image" value="$image"/>\n  <RectangleLabels name="label" toName="image"><Label value="egg_tray"/></RectangleLabels>\n</View>\n', encoding="utf-8")
    report = [
        "# Canonical Dataset Report", "", "> Sources were preserved unchanged. Ambiguous auto labels were excluded and queued for human review.", "",
        f"- Total source images: {len(local_images) + len(cloud_images)}", f"- Manual images selected: {stats['manual_images']}",
        f"- Roboflow images selected: {stats['roboflow_images']}", f"- Manual annotations replaced auto labels: {stats['manual_replaced_auto']}",
        f"- Exact duplicate images removed: {stats['exact_duplicate_images_removed']}", f"- Duplicate annotations removed: {stats['duplicate_annotations_removed']}",
        f"- Manual/auto conflicts queued: {stats['conflicts_queued']}", f"- Auto-labelled images queued: {stats['auto_images_queued']}",
        f"- Final images: {len(manifest)}", f"- Review tasks: {len(review_tasks)}", "",
        "Scene/capture-session metadata is absent, so scene-level split leakage cannot be ruled out. Existing source splits were preserved and overlapping manual images replaced their cloud counterparts.", "",
    ]
    (reports / "canonical_dataset_report.md").write_text("\n".join(report), encoding="utf-8")
    print(json.dumps({**stats, "final_images": len(manifest), "review_tasks": len(review_tasks)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
