"""V5 clean control; refuse an empty grouped validation set or unapproved snapshot."""
import argparse
import hashlib
import json
from pathlib import Path


def validate_snapshot(path):
    frozen = path / "frozen-manifest.json"
    if frozen.exists() and json.loads(frozen.read_text()).get("training_release_eligible") is not True:
        raise ValueError("Frozen V5 subset is incomplete and explicitly ineligible for training release")
    partitions = {}
    for split in ("train", "valid", "test"):
        file = path / split / "_annotations.coco.json"
        data = json.loads(file.read_text(encoding="utf-8"))
        partitions[split] = data
    if not partitions["train"]["annotations"] or not partitions["valid"]["annotations"]:
        raise ValueError("V5-CLEAN-CONTROL needs reviewed training and separate leakage-group validation labels")
    seen = {}
    seen_hashes = {}
    for split, data in partitions.items():
        for image in data["images"]:
            group = image.get("scene_group") or image.get("scene_id")
            if not group:
                raise ValueError("Scene grouping required for every control image")
            if group in seen and seen[group] != split:
                raise ValueError("Scene leakage between control partitions")
            seen[group] = split
            digest = image.get("source_sha256")
            if not digest:
                raise ValueError("Original content hash required for control lineage")
            if digest in seen_hashes and seen_hashes[digest] != split:
                raise ValueError("Source/derivative leakage between control partitions")
            seen_hashes[digest] = split
    return partitions


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    run = {"candidate": "V5-CLEAN-CONTROL", "architecture": "RF-DETR Medium", "resolution": 640,
           "preprocessing": "640 fit-within, frozen snapshot", "threshold": .35, "seed": 20260928,
           "epochs": args.epochs, "status": "prepared_not_trained",
           "occupancy_supervision": "unknown; visible-layer boxes do not prove eggs in concealed layers"}
    try:
        partitions = validate_snapshot(args.dataset)
        run["annotation_sha256"] = {s: hashlib.sha256((args.dataset / s / "_annotations.coco.json").read_bytes()).hexdigest()
                                      for s in partitions}
    except ValueError as exc:
        run.update(status="blocked", reason=str(exc))
        (args.output / "control-run.json").write_text(json.dumps(run, indent=2), encoding="utf-8")
        print(run["reason"])
        return
    (args.output / "control-run.json").write_text(json.dumps(run, indent=2), encoding="utf-8")
    if args.prepare_only:
        return
    from rfdetr import RFDETRMedium
    options = {"pretrain_weights": str(args.checkpoint)} if args.checkpoint else {}
    model = RFDETRMedium(**options)
    model.train(dataset_dir=str(args.dataset), resolution=640, epochs=args.epochs,
                output_dir=str(args.output), seed=run["seed"], batch_size=2, grad_accum_steps=8)
    run["status"] = "training_completed_evaluation_pending"
    (args.output / "control-run.json").write_text(json.dumps(run, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
