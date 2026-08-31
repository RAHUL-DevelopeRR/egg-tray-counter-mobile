"""Generate reproducible dataset-distribution and leakage review files."""

from __future__ import annotations

import csv
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = Path(__file__).resolve().parent
MANIFEST = ROOT / "datasets" / "canonical_clean" / "manifest.csv"
CONFIRMED_CROSS_SPLIT_SCENES = {
    frozenset(("fbe0d59572aabedc2e11", "36dccd6307a7fbd801d3")),
    frozenset(("d7c9bd5da8895bca07a0", "2b588d2747ad49e43c76")),
    frozenset(("e0dc76ed696457a17808", "01297a74fd3883320f92")),
}


def range_name(count: int) -> str:
    for maximum, name in ((10, "1-10"), (30, "11-30"), (60, "31-60"), (90, "61-90"), (120, "91-120")):
        if count <= maximum:
            return name
    return "120+"


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    with MANIFEST.open(encoding="utf-8-sig") as handle:
        records = list(csv.DictReader(handle))

    distributions: Counter[tuple[str, str, str]] = Counter()
    annotations: Counter[tuple[str, str, str]] = Counter()
    for record in records:
        count = int(record["annotation_count"])
        key = (record["split"], record["selected_source"], range_name(count))
        distributions[key] += 1
        annotations[key] += count

    stats_rows: list[dict[str, object]] = []
    for (split, source, count_range), images in sorted(distributions.items()):
        stats_rows.append({
            "dataset": "canonical_clean",
            "split": split,
            "source": source,
            "view": "UNKNOWN",
            "count_range": count_range,
            "images": images,
            "annotations": annotations[(split, source, count_range)],
            "count_semantics": "annotation_count_proxy_not_scene_ground_truth",
        })
    write_csv(
        OUT / "01-dataset-audit" / "dataset-stats.csv",
        ["dataset", "split", "source", "view", "count_range", "images", "annotations", "count_semantics"],
        stats_rows,
    )

    duplicate_rows: list[dict[str, object]] = []
    for index, first in enumerate(records):
        for second in records[index + 1 :]:
            distance = (int(first["dhash"], 16) ^ int(second["dhash"], 16)).bit_count()
            if distance > 6:
                continue
            confirmed = frozenset((first["canonical_image_id"], second["canonical_image_id"])) in CONFIRMED_CROSS_SPLIT_SCENES
            duplicate_rows.append({
                "image_a": first["canonical_image_id"],
                "image_b": second["canonical_image_id"],
                "split_a": first["split"],
                "split_b": second["split"],
                "sha256_equal": first["sha256"] == second["sha256"],
                "dhash_distance": distance,
                "cross_split": first["split"] != second["split"],
                "status": "confirmed_same_scene_cross_split" if confirmed else "human_scene_review_required",
                "reason": (
                    "visually confirmed same scene; remove duplicate or group into one split before training"
                    if confirmed else
                    "perceptual-near-duplicate candidate; dHash is screening evidence, not proof"
                ),
            })
    write_csv(
        OUT / "01-dataset-audit" / "duplicate-report.csv",
        ["image_a", "image_b", "split_a", "split_b", "sha256_equal", "dhash_distance", "cross_split", "status", "reason"],
        duplicate_rows,
    )

    scene_rows = [{
        "scene_id": "",
        "image_id": record["canonical_image_id"],
        "current_split": record["split"],
        "view": "UNKNOWN",
        "true_total_trays": "",
        "true_total_eggs": "",
        "number_of_stacks": "",
        "stack_counts_if_known": "",
        "lighting": "",
        "distance": "",
        "camera_angle": "",
        "occlusion_level": "",
        "tray_type": "",
        "source_path": record["source_path"],
        "review_status": "needs_human_scene_and_ground_truth_review",
        "notes": "Do not train or resplit from this row until scene_id and view are verified.",
    } for record in records]
    write_csv(
        OUT / "03-clean-dataset" / "scene-metadata.csv",
        list(scene_rows[0]),
        scene_rows,
    )
    print({"images": len(records), "near_duplicate_pairs": len(duplicate_rows), "cross_split_candidates": sum(row["cross_split"] for row in duplicate_rows)})


if __name__ == "__main__":
    main()
