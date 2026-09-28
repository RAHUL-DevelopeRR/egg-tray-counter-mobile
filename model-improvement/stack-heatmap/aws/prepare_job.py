"""Render validated SageMaker request locally. No AWS calls or resource creation."""
import argparse
import json
from pathlib import Path


def validate(config):
    text = json.dumps(config)
    if "REPLACE" in text:
        raise ValueError("Fill account, role, immutable image digest, S3 prefixes and git commit first")
    if "@sha256:" not in config["AlgorithmSpecification"]["TrainingImage"]:
        raise ValueError("Pin container by digest")
    if config["ResourceConfig"]["InstanceCount"] != 1:
        raise ValueError("This baseline is single-instance only")
    if config.get("EnableManagedSpotTraining"):
        if not config.get("CheckpointConfig") or config["StoppingCondition"]["MaxWaitTimeInSeconds"] < config["StoppingCondition"]["MaxRuntimeInSeconds"]:
            raise ValueError("Spot training requires checkpoints and sufficient wait time")
    return config


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(validate(json.loads(args.config.read_text())), indent=2), encoding="utf-8")
