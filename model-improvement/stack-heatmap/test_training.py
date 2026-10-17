"""Runnable small checks; avoids downloading weights or running a training job."""
import json
import hashlib
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch
import torch
from model import StackHeatmap, gaussian_target, load_model
from train_control import validate_snapshot
from aws.prepare_job import validate
from train_heatmap import validation_score, main as train_main


def main():
    torch.set_num_threads(2)
    model = StackHeatmap(pretrained=False).train()
    assert not model.backbone.training
    assert model(torch.zeros(2, 3, 128, 64)).shape == (2, 128)
    assert not any(p.requires_grad for p in model.backbone.parameters())
    thawed = StackHeatmap(pretrained=False, backbone_mode="last-block").train()
    assert not any(p.requires_grad for p in thawed.backbone[:-1].parameters())
    assert all(p.requires_grad for p in thawed.backbone[-1].parameters())
    before = {name: value.clone() for name, value in thawed.backbone.state_dict().items()}
    optimizer = torch.optim.Adam((p for p in thawed.parameters() if p.requires_grad), lr=.003)
    thawed(torch.randn(2, 3, 128, 64)).square().mean().backward()
    assert all(p.grad is None for p in thawed.backbone[:-1].parameters())
    assert any(p.grad is not None and p.grad.abs().sum() > 0 for p in thawed.backbone[-1].parameters())
    optimizer.step()
    after = thawed.backbone.state_dict()
    assert any(not torch.equal(before[name], value) for name, value in after.items() if name.startswith("3."))
    assert all(torch.equal(before[name], value) for name, value in after.items()
               if not name.startswith("3.") or "running_" in name or "num_batches_tracked" in name)
    target = gaussian_target([.25, .75], height=101, sigma=2)
    assert target[25] == 1 and target[75] == 1 and target[50] < .01
    accurate = {"stack_exact": 2, "mae": 1., "missed_layers": 3,
                "duplicate_or_spurious_layers": 3, "loss": .7}
    suppressed = {"stack_exact": 0, "mae": 20., "missed_layers": 40,
                  "duplicate_or_spurious_layers": 0, "loss": .2}
    assert validation_score(suppressed, "bce") < validation_score(accurate, "bce")
    assert validation_score(accurate, "count") < validation_score(suppressed, "count")
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        source = root / "source.jpg"
        source.write_bytes(b"not decoded: validation must reject before training")
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        record = {"id": "a", "count": 2, "centres_y": [.25, .75], "scene_id": "a",
                  "leakage_group_id": "a", "split": "development",
                  "source_path": str(source), "source_sha256": digest,
                  "image_path": str(source), "image_sha256": digest,
                  "annotation_status": "assistant_visual_reviewed"}
        for records, message in [
            ([{**record, "image_sha256": "0" * 64}], "crop bytes"),
            ([record, {**record, "id": "b", "scene_id": "b", "leakage_group_id": "b"}], "cross leakage"),
            ([{**record, "centres_y": [.25, float("nan")]}], "finite normalized"),
            ([{**record, "split": "acceptance"}], "Acceptance/test"),
            ([{**record, "annotation_status": "unreviewed"}], "Unreviewed"),
        ]:
            manifest = root / "invalid.json"
            manifest.write_text(json.dumps(records))
            with patch.object(sys, "argv", ["train_heatmap.py", "--manifest", str(manifest),
                                           "--output", str(root / "forbidden-run")]):
                try:
                    train_main()
                    raise AssertionError("Invalid manifest reached training")
                except ValueError as error:
                    assert message in str(error), str(error)
        assert not (root / "forbidden-run").exists()
        # New training modes retain the old checkpoint architecture and config loading.
        torch.save({"model": model.state_dict(), "config": {"height": 640}}, root / "old.pt")
        loaded, config = load_model(root / "old.pt")
        assert config == {"height": 640} and not loaded.training
        torch.save({"model": thawed.state_dict(), "config": {"backbone_mode": "last-block"}}, root / "thawed.pt")
        loaded, config = load_model(root / "thawed.pt")
        assert config["backbone_mode"] == "last-block"
        assert all(torch.equal(loaded.state_dict()[name], value) for name, value in thawed.state_dict().items())
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
    print("Training shape, targets, controlled backbone gradients, frozen BN, checkpoint compatibility, control and AWS gates passed")


if __name__ == "__main__":
    main()
