"""Runnable small checks; avoids downloading weights or running a training job."""
import json
import tempfile
from pathlib import Path
import torch
from model import StackHeatmap, gaussian_target
from train_control import validate_snapshot
from aws.prepare_job import validate


def main():
    torch.set_num_threads(2)
    model = StackHeatmap(pretrained=False).train()
    assert not model.backbone.training
    assert model(torch.zeros(2, 3, 128, 64)).shape == (2, 128)
    target = gaussian_target([.25, .75], height=101, sigma=2)
    assert target[25] == 1 and target[75] == 1 and target[50] < .01
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        for split in ("train", "valid", "test"):
            (root / split).mkdir()
            (root / split / "_annotations.coco.json").write_text(json.dumps({"images": [], "annotations": []}))
        try:
            validate_snapshot(root)
            raise AssertionError("Empty validation passed")
        except ValueError:
            pass
    example = Path(__file__).parent / "aws/training-config.example.json"
    try:
        validate(json.loads(example.read_text()))
        raise AssertionError("Placeholder job passed")
    except ValueError:
        pass
    print("Training shape, targets, frozen backbone, control gate and AWS dry-run gates passed")


if __name__ == "__main__":
    main()
