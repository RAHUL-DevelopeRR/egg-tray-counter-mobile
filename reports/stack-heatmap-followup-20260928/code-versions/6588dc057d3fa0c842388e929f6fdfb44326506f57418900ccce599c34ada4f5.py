"""CPU/GPU smoke fit or leakage-group leave-one-out development evaluation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import time

import numpy as np
from PIL import Image, ImageEnhance
import torch
from scipy.signal import find_peaks

from model import StackHeatmap, gaussian_target, image_tensor

REPO = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("STACK_DATA_ROOT", REPO))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def samples(records, config, augment=False):
    # ponytail: in-memory reviewed pilot only; use mini-batches for a larger curated release.
    rows = []
    for record in records:
        with Image.open(ROOT / record["image_path"]) as image:
            image = image.convert("RGB")
            if augment:
                image = ImageEnhance.Brightness(image).enhance(random.uniform(.9, 1.1))
                image = ImageEnhance.Contrast(image).enhance(random.uniform(.9, 1.1))
            rows.append((image_tensor(np.asarray(image), config["height"], config["width"]),
                         gaussian_target(record["centres_y"], config["height"], config["sigma"])))
    return torch.stack([r[0] for r in rows]), torch.stack([r[1] for r in rows])


def metrics(model, records, config, device):
    x, target = samples(records, config)
    started = time.perf_counter()
    with torch.no_grad():
        logits = model(x.to(device))
        loss = torch.nn.functional.binary_cross_entropy_with_logits(logits, target.to(device)).item()
        probabilities = logits.sigmoid().cpu().numpy()
    latency = (time.perf_counter() - started) * 1000 / len(records)
    rows = []
    for record, probability in zip(records, probabilities, strict=True):
        peaks, _ = find_peaks(probability, height=config["threshold"], distance=config["peak_distance"])
        truth = np.array(record["centres_y"]) * (config["height"] - 1)
        # One-to-one localization matching distinguishes missing and duplicate peaks.
        remaining = list(truth)
        matched = 0
        for peak in sorted(peaks, key=lambda p: -probability[p]):
            if remaining:
                index = int(np.argmin(np.abs(np.array(remaining) - peak)))
                if abs(remaining[index] - peak) <= config["match_tolerance"]:
                    remaining.pop(index)
                    matched += 1
        count = len(peaks)
        rows.append({"id": record["id"], "scene_id": record["scene_id"], "reference": record["count"],
                     "candidate_count": count, "signed_error": count - record["count"],
                     "missed_layers": len(truth) - matched, "duplicate_or_spurious_layers": count - matched,
                     "peaks": peaks.tolist(), "probabilities": probability.tolist(),
                     "latency_ms": latency, "verified": False, "occupancy": "unknown"})
    errors = [r["signed_error"] for r in rows]
    scenes = set(r["scene_id"] for r in rows)
    return {"loss": loss, "stack_exact": sum(e == 0 for e in errors), "stacks": len(rows),
            "scene_exact": sum(all(r["signed_error"] == 0 for r in rows if r["scene_id"] == s) for s in scenes),
            "scenes": len(scenes), "mae": float(np.mean(np.abs(errors))), "signed_error": float(np.mean(errors)),
            "missed_layers": sum(r["missed_layers"] for r in rows),
            "duplicate_or_spurious_layers": sum(r["duplicate_or_spurious_layers"] for r in rows),
            "rejection_rate": 1.0, "false_accepted_count": 0, "accepted_scan_accuracy": None,
            "latency_ms_per_stack": latency, "rows": rows}


def fit(train, valid, config, output, device):
    random.seed(config["seed"]); np.random.seed(config["seed"]); torch.manual_seed(config["seed"])
    model = StackHeatmap(backbone_mode=config.get("backbone_mode", "frozen")).to(device)
    optimizer = torch.optim.Adam((p for p in model.parameters() if p.requires_grad),
                                 lr=config["learning_rate"])
    history, best, stale = [], float("inf"), 0
    resume_path = Path(config["checkpoint_dir"]) / (output.name + "-resume.pt")
    best_resume_path = Path(config["checkpoint_dir"]) / (output.name + "-best.pt")
    resume_path.parent.mkdir(parents=True, exist_ok=True)
    start = 0
    if resume_path.exists():
        checkpoint = torch.load(resume_path, map_location=device, weights_only=True)
        if checkpoint["manifest_sha256"] != config["manifest_sha256"] or checkpoint["config"] != config:
            raise ValueError("Resume checkpoint configuration or dataset mismatch")
        model.load_state_dict(checkpoint["model"]); optimizer.load_state_dict(checkpoint["optimizer"])
        start = checkpoint["epoch"] + 1
        history, best, stale = checkpoint["history"], checkpoint["best"], checkpoint["stale"]
        random.setstate(checkpoint["random_state"]); torch.set_rng_state(checkpoint["torch_rng"].cpu())
    output.mkdir(parents=True, exist_ok=True)
    if start:
        if not best_resume_path.exists():
            raise ValueError("Resume requires its matching best checkpoint, not optimizer state alone")
        shutil.copyfile(best_resume_path, output / "best.pt")
    stop_epoch = start if valid and stale >= config["patience"] else config["epochs"]
    for epoch in range(start, stop_epoch):
        x, target = samples(train, config, augment=True)
        model.train(); optimizer.zero_grad()
        logits = model(x.to(device))
        loss = torch.nn.functional.binary_cross_entropy_with_logits(logits, target.to(device),
                                                pos_weight=torch.tensor(4., device=device))
        loss.backward(); optimizer.step(); model.eval()
        validation = metrics(model, valid, config, device) if valid else None
        history.append({"epoch": epoch + 1, "train_loss": loss.item(),
                        "validation_loss": validation["loss"] if validation else None,
                        "validation_stack_exact": validation["stack_exact"] if validation else None,
                        "validation_scene_exact": validation["scene_exact"] if validation else None})
        # Validation selects checkpoints; smoke fit selects its final epoch only.
        improved = validation is None or validation["loss"] < best
        if improved:
            best = validation["loss"] if validation else loss.item(); stale = 0
            torch.save({"model": model.cpu().state_dict(), "config": config, "epoch": epoch + 1}, output / "best.pt")
            shutil.copyfile(output / "best.pt", best_resume_path)
            model.to(device)
        else:
            stale += 1
        torch.save({"model": model.state_dict(), "optimizer": optimizer.state_dict(), "config": config,
                    "manifest_sha256": config["manifest_sha256"], "epoch": epoch, "history": history,
                    "best": best, "stale": stale, "random_state": random.getstate(),
                    "torch_rng": torch.get_rng_state()}, resume_path)
        print(json.dumps(history[-1]), flush=True)
        if valid and stale >= config["patience"]:
            break
    checkpoint = torch.load(output / "best.pt", weights_only=True, map_location=device)
    model.load_state_dict(checkpoint["model"]); model.eval()
    result = {"config": config, "train_scene_ids": sorted(set(r["scene_id"] for r in train)),
              "validation_scene_ids": sorted(set(r["scene_id"] for r in valid)), "history": history,
              "epoch": len(history), "best_epoch": checkpoint.get("epoch"),
              "best_checkpoint": str(output / "best.pt"),
              "checkpoint_sha256": sha(output / "best.pt"),
              "evaluation_scope": "development_validation" if valid else "training_fit_only_no_generalization",
              "metrics": metrics(model, valid or train, config, device)}
    (output / "run.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--mode", choices=["smoke", "loco"], default="smoke")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--backbone-mode", choices=["frozen", "last-block"], default="frozen",
                        help="Controlled last-block fine-tuning; BN running statistics stay frozen")
    args = parser.parse_args()
    if not 1 <= args.epochs <= 10000:
        parser.error("epochs must be between 1 and 10000")
    torch.set_num_threads(min(4, os.cpu_count() or 1))
    raw = json.loads(args.manifest.read_text(encoding="utf-8"))
    records = raw if isinstance(raw, list) else raw["faces"]
    if not records or any(r["count"] != len(r["centres_y"]) for r in records):
        raise ValueError("Nonempty reviewed one-centre-per-layer manifest required")
    source_groups = {}
    for record in records:
        if record.get("annotation_status") != "assistant_visual_reviewed":
            raise ValueError("Unreviewed records cannot become heatmap labels")
        if sha(ROOT / record["source_path"]) != record["source_sha256"]:
            raise ValueError("Original source bytes do not match the reviewed label provenance")
        if record.get("image_sha256") and sha(ROOT / record["image_path"]) != record["image_sha256"]:
            raise ValueError("Reviewed crop bytes changed after the dataset was frozen")
        source_groups.setdefault(record["source_sha256"], set()).add(
            record.get("leakage_group_id", record["scene_id"]))
        if len(set(record["centres_y"])) != record["count"]:
            raise ValueError("Repeated layer centres are not distinct physical targets")
        if not all(np.isfinite(y) and 0 < y < 1 for y in record["centres_y"]):
            raise ValueError("Layer centres must be finite normalized interior coordinates")
    if any(len(groups) != 1 for groups in source_groups.values()):
        raise ValueError("Crops of the same source cannot cross leakage groups")
    # Acceptance/test annotations are never available to this trainer.
    if any(r.get("split") in ("test", "acceptance") for r in records):
        raise ValueError("Acceptance/test records cannot enter development training")
    config = {"architecture": "mobilenet_v3_small_imagenet_stride8_frozen_1d_head",
              "backbone_mode": args.backbone_mode, "batch_norm_statistics": "frozen",
              "height": 640, "width": 192, "sigma": 3., "seed": 20260928,
              "learning_rate": .003, "epochs": args.epochs, "patience": 5,
              "threshold": .5, "peak_distance": 8, "match_tolerance": 6,
              "loss_weights": {"heatmap_bce": 1., "positive_weight": 4., "endpoint": 0., "count": 0.},
              "augmentation": "brightness_contrast_0.9_to_1.1_only",
              "manifest_sha256": sha(args.manifest),
              "training_code_sha256": sha(__file__),
              "model_code_sha256": sha(REPO / "backend/app/vision/heatmap_model.py"),
              "git_commit": os.environ.get("TRAINING_GIT_COMMIT") or subprocess.check_output(
                  ["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
              "torch_version": str(torch.__version__), "device": args.device,
              "checkpoint_dir": os.environ.get("SM_CHECKPOINT_DIR", str(args.output / "checkpoints"))}
    if args.backbone_mode == "last-block":
        config["architecture"] = "mobilenet_v3_small_imagenet_stride8_last_block_1d_head"
    groups = sorted(set(r.get("leakage_group_id", r["scene_id"]) for r in records))
    args.output.mkdir(parents=True, exist_ok=True)
    if args.mode == "loco" and len(groups) < 2:
        (args.output / "cv-blocked.json").write_text(json.dumps({"status": "blocked", "groups": groups,
            "reason": "At least two independently reviewed leakage groups required; no random image split"}, indent=2))
        print("Grouped development CV blocked: fewer than two independent reviewed groups.")
        return
    folds = groups if args.mode == "loco" else [None]
    for fold, group in enumerate(folds):
        train = [r for r in records if group is None or r.get("leakage_group_id", r["scene_id"]) != group]
        valid = [r for r in records if group is not None and r.get("leakage_group_id", r["scene_id"]) == group]
        fit(train, valid, config, args.output / f"fold-{fold}", args.device)


if __name__ == "__main__":
    main()
