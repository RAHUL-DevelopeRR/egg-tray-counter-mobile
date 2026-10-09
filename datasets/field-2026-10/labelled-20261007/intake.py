"""Copy the user's labelled WhatsApp photos byte-for-byte and find near-duplicates.

Source labels are handwritten totals burned into the pixels; they are
transcribed separately in labels.csv. Originals are never modified.
"""
import hashlib, json, shutil
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps

SRC = Path(r"C:/Users/DELL/Downloads/FileOfEggLabels")
HERE = Path(__file__).parent
files = sorted(SRC.iterdir(), key=lambda p: p.name)
rows, hashes = [], []
for i, p in enumerate(files, 1):
    raw = p.read_bytes()
    dest = HERE / "originals" / f"img-{i:02d}{p.suffix.lower()}"
    shutil.copyfile(p, dest)
    assert hashlib.sha256(dest.read_bytes()).hexdigest() == hashlib.sha256(raw).hexdigest()
    with Image.open(p) as im:
        im = ImageOps.exif_transpose(im)
        w, h = im.size
        g = np.asarray(im.convert("L").resize((17, 16)), dtype=np.int16)
    hashes.append((g[:, 1:] > g[:, :-1]).ravel())
    rows.append({"id": i, "file": dest.name, "source_name": p.name,
                 "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw),
                 "width": w, "height": h, "exif": False})
near = []
for a in range(len(rows)):
    for b in range(a + 1, len(rows)):
        d = int((hashes[a] != hashes[b]).sum())
        if d <= 40:
            near.append({"a": a + 1, "b": b + 1, "dhash_distance_of_256": d})
json.dump({"source_folder": str(SRC), "images": rows, "near_duplicate_pairs": near},
          open(HERE / "manifest.json", "w"), indent=1)
print(len(rows), "copied"); [print(n) for n in sorted(near, key=lambda n: n["dhash_distance_of_256"])]
