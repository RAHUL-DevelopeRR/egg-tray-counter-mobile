from ml.evaluate import calculate_metrics


def test_product_metrics_keep_accuracy_and_coverage_separate() -> None:
    scenes = [
        {
            "accepted": True,
            "total_trays_gt": 18,
            "total_trays_pred": 18,
            "stacks": [{"tray_count_gt": 18, "tray_count_pred": 18}],
        },
        {
            "accepted": False,
            "total_trays_gt": 19,
            "total_trays_pred": None,
            "stacks": [{"tray_count_gt": 19, "tray_count_pred": None}],
        },
        {
            "accepted": True,
            "total_trays_gt": 20,
            "total_trays_pred": 19,
            "stacks": [{"tray_count_gt": 20, "tray_count_pred": 19}],
        },
    ]
    metrics = calculate_metrics(scenes)
    assert metrics["coverage"] == 2 / 3
    assert metrics["accepted_accuracy"] == 0.5
    assert metrics["false_accept_rate"] == 0.5
    assert metrics["exact_stack_accuracy"] == 0.5
    assert metrics["stack_mae"] == 0.5
