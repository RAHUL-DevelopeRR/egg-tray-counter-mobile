import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location(
    "instance_score", Path(__file__).parents[2] / "scripts/score_tray_instances.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def instance(index, box, state="filled"):
    return {
        "stack_id": "a",
        "tray_index": index,
        "bbox": box,
        "physical_state": state,
        "visibility": "visible",
    }


def test_same_total_with_duplicate_and_miss_is_not_perfect_detection():
    truth = {
        "image_sha256": "a" * 64,
        "annotation_complete": True,
        "instances": [instance(1, [0, 0, 20, 10]), instance(2, [0, 20, 20, 30], "empty")],
    }
    predicted = {
        "image_sha256": "a" * 64,
        "instances": [instance(1, [0, 0, 20, 10]), instance(2, [0, 0, 20, 10])],
    }
    result = module.score(truth, predicted)
    assert (result["tp"], result["fp"], result["fn"]) == (1, 1, 1)
    assert result["precision"] == result["recall"] == result["f1"] == 0.5
    assert result["per_stack"]["a"] == {
        "physical_error": 0,
        "filled_error": 1,
        "empty_error": -1,
        "unknown_predictions": 0,
    }


def test_missing_annotation_geometry_cannot_report_precision():
    truth = {"image_sha256": "a" * 64, "annotation_complete": False, "instances": [instance(1, None)]}
    assert module.score(truth, {"image_sha256": "a" * 64, "instances": []})["precision"] is None
    with pytest.raises(ValueError):
        module.score(truth, {"image_sha256": "b" * 64, "instances": []})


def test_occupancy_errors_preserved_despite_perfect_localization():
    truth = {
        "image_sha256": "a" * 64,
        "annotation_complete": True,
        "instances": [instance(1, [0, 0, 20, 10], "empty")],
    }
    outputs = {"image_sha256": "a" * 64, "instances": [instance(1, [0, 0, 20, 10])]}
    result = module.score(truth, outputs)
    assert result["precision"] == 1
    assert result["occupancy_confusion"] == {"empty->filled": 1}
