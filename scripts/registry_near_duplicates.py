"""Near-duplicate matches between the field photos and every image in the detector data pools.

Provenance for the replay registry (benchmarks/registry-20261101): a field photo whose near-duplicate sits in a
detector training/review pool is not out of sample for the detector. Hash: 64-bit difference hash (dHash) of the
EXIF-upright image, compared in all four rotations. dHash resizes to 9x8 regardless of aspect, so resized and
stretched exports (Roboflow 640x640) still match; a crop does not. Threshold: Hamming distance <= 8 of 64. Checked
on the labelled photos against the audit's detector_leak flags (eval_manifest.json): the 18 leaked photos match at
0-7, the 6 leak-free ones at 10 or not at all.

Run from the repository root (needs Pillow):
  python scripts/registry_near_duplicates.py --mutaa C:/Users/rahul/MUTAA --out benchmarks/registry-20261101/near_duplicates.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageOps

REPO = Path(__file__).resolve().parents[1]
POOLS = {
    "canonical_clean": REPO / "datasets" / "canonical_clean",
    "review": REPO / "datasets" / "review",
    "roboflow_auto_original": REPO / "datasets" / "roboflow_auto_original",
}
LABELLED = REPO / "datasets" / "field-2026-10" / "labelled-20261007" / "originals"
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}
MAX_DISTANCE = 8


def images(root: Path):
    return sorted(p for p in root.rglob("*") if p.suffix.lower() in IMAGE_SUFFIXES and p.is_file())


def dhash(image: Image.Image) -> int:
    small = image.convert("L").resize((9, 8), Image.Resampling.LANCZOS)
    px = list(small.getdata())
    bits = 0
    for row in range(8):
        for col in range(8):
            bits = (bits << 1) | (px[row * 9 + col] > px[row * 9 + col + 1])
    return bits


def hashes(path: Path, rotations: bool) -> list[int]:
    with Image.open(path) as raw:
        raw.draft("RGB", (512, 512))
        image = ImageOps.exif_transpose(raw)
        turns = (0, 90, 180, 270) if rotations else (0,)
        return [dhash(image.rotate(angle, expand=True) if angle else image) for angle in turns]


def rel(path: Path) -> str:
    try:
        return path.relative_to(REPO).as_posix()
    except ValueError:
        return path.as_posix()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mutaa", required=True, help="MUTAA clone (field photos, outside this repo)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    mutaa = Path(args.mutaa)
    field = [("mutaa", p) for p in sorted(mutaa.glob("*.jpeg"))] + [("labelled", p) for p in images(LABELLED)]
    pool = [(name, p, hashes(p, False)[0]) for name, root in POOLS.items() for p in images(root)]
    out = {"method": "dHash 64-bit of the EXIF-upright image, four rotations of the field photo",
           "max_distance": MAX_DISTANCE, "pools": {k: rel(v) for k, v in POOLS.items()},
           "pool_images": {k: sum(1 for n, _, _ in pool if n == k) for k in POOLS}, "photos": []}
    for source, path in field:
        own = hashes(path, True)
        matches = []
        for name, other, h in pool:
            distance = min(bin(a ^ h).count("1") for a in own)
            if distance <= MAX_DISTANCE:
                matches.append({"pool": name, "file": rel(other), "distance": distance})
        matches.sort(key=lambda m: (m["distance"], m["file"]))
        out["photos"].append({"source": source, "file": path.name if source == "mutaa" else rel(path),
                              "dhash": f"{own[0]:016x}", "pool_matches": matches})
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
    hit = sum(1 for p in out["photos"] if p["pool_matches"])
    print(f"{len(out['photos'])} field photos, {len(pool)} pool images, {hit} field photos with a pool match")
    return 0


if __name__ == "__main__":
    sys.exit(main())
