"""Stage only reviewed manifest dependencies, preserving repo-relative lineage paths."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[3]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path); parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest = args.manifest.resolve()
    manifest.relative_to(ROOT)  # The bundle cannot absorb arbitrary unrelated host files.
    records = json.loads(manifest.read_text())
    paths = {manifest}
    for record in records:
        for key in ("image_path", "source_path", "target_path"):
            path = (ROOT / record[key]).resolve(); path.relative_to(ROOT); paths.add(path)
    args.output.mkdir(parents=True, exist_ok=True)
    files = []
    for source in sorted(paths):
        relative = source.relative_to(ROOT)
        target = args.output / relative; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        files.append({"path": relative.as_posix(), "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
    (args.output / "bundle-manifest.json").write_text(json.dumps({
        "dataset_manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(), "files": files}, indent=2))
    print(f"Staged {len(files)} files locally; no S3 write")
