"""Create a non-destructive annotation/migration manifest from audit output.

No scene, view, stack ID, or count is guessed. Those fields require human review.
Exact duplicate source paths are grouped under one canonical image row.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


FIELDS = (
    "canonical_path",
    "sha256",
    "duplicate_source_paths",
    "scene_id",
    "view",
    "physical_stack_ids",
    "tray_counts_gt",
    "annotation_status",
    "split",
)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", type=Path, default=root / "ml" / "audit-report.json")
    parser.add_argument(
        "--output", type=Path, default=root / "ml" / "migration-manifest.csv"
    )
    args = parser.parse_args()

    audit = json.loads(args.audit.read_text(encoding="utf-8"))
    by_hash: dict[str, list[str]] = defaultdict(list)
    for record in audit["images"]:
        if record["error"] is None and record["sha256"]:
            by_hash[record["sha256"]].append(record["relative_path"])

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        for digest, paths in sorted(
            by_hash.items(), key=lambda item: sorted(item[1])[0]
        ):
            ordered = sorted(paths)
            writer.writerow(
                {
                    "canonical_path": ordered[0],
                    "sha256": digest,
                    "duplicate_source_paths": "|".join(ordered[1:]),
                    "scene_id": "",
                    "view": "",
                    "physical_stack_ids": "",
                    "tray_counts_gt": "",
                    "annotation_status": "needs_stack_face_polygons",
                    "split": "",
                }
            )
    print(f"Wrote {len(by_hash)} unique-image rows to {args.output}")
    print(
        "Human review is required for scene_id, view, stack IDs, counts, polygons, and scene-level split."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
