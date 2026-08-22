from pathlib import Path

from ml.audit_dataset import iou, parse_label


def test_iou_detects_near_duplicate_boxes() -> None:
    assert iou((0.1, 0.1, 0.5, 0.5), (0.11, 0.11, 0.51, 0.51)) > 0.85


def test_duplicate_annotation_is_flagged(tmp_path: Path) -> None:
    label = tmp_path / "sample.txt"
    label.write_text("0 0.5 0.5 0.2 0.2\n0 0.5 0.5 0.2 0.2\n", encoding="utf-8")
    result = parse_label(label, 0.85)
    assert any(issue["type"] == "exact_duplicate_annotation" for issue in result["issues"])
