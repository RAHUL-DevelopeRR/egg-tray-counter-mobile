"""Send the MUTAA photo collection through the deployed staging Worker exactly as the app prepares photos.

What is sent (the app's own preparation, mobile/lib/services/captured_still.dart): EXIF-upright, long side at most
1600 px, JPEG quality 92. No capture fields are sent, so every reading counts as unknown provenance (as a gallery
upload): no block from these photos can be `exact`, which is the 0.5.0 contract for photos not taken with the guided
camera.

Scans:
- the 8 verified MUTAA block sets (reports/mutaa-manual-vs-backend-20261031/sets-verified.json, kept sets); a set with
  only two photos of its block takes the 31 Oct filler photo as RIGHT (sets-sent.json), so only its real faces count;
- every other MUTAA field photo, three per scan (per-photo readings only; such a scan's block is meaningless);
- the 52 count-labelled photos (datasets/field-2026-10/labelled-20261007/originals, the same files as MUTAA's
  FileOfEggLabels) not already in a set, three per scan.

Needs EGG_ADMIN_TOKEN (never printed). Spends 3 detector calls per new scan; resumes from saved answers.

  python scripts/validate_build_staging.py --mutaa C:/Users/rahul/MUTAA --out reports/mutaa-validation-0.5.0-20261101
"""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import field_tools as ft  # noqa: E402
import replay_field_scans as rfs  # noqa: E402
from PIL import Image, ImageOps  # noqa: E402

LONG_SIDE, QUALITY = 1600, 92
VIEWS = ("straight", "left", "right")
LABELLED = REPO / "datasets" / "field-2026-10" / "labelled-20261007" / "originals"


def prep(src: Path, dst: Path) -> dict:
    image = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
    w, h = image.size
    scale = LONG_SIDE / max(w, h)
    if scale < 1:
        image = image.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    image.save(dst, "JPEG", quality=QUALITY)
    return {"src": str(src), "upright_src": [w, h], "sent": list(image.size)}


def plan(mutaa: Path) -> list[dict]:
    verified = json.loads((REPO / "reports/mutaa-manual-vs-backend-20261031/sets-verified.json").read_text(encoding="utf-8"))
    sent = {s["set_id"]: s for s in json.loads((REPO / "reports/mutaa-manual-vs-backend-20261031/sets-sent.json").read_text(encoding="utf-8"))}
    scans, used = [], set()
    for s in verified["sets"]:
        if not s.get("keep"):
            continue
        # Sets with only two photos of their block take the 31 Oct filler (an unrelated photo) as RIGHT, as then.
        source = sent.get(s["set_id"], s)
        photos = {v: Path(source[v]) for v in VIEWS}
        if len({p.resolve() for p in photos.values()}) < 3:
            continue
        filler = source.get("filler")
        scans.append({"id": f"set-{s['set_id']}", "kind": "set", "set_id": s["set_id"], "photos": photos, "filler": filler})
        used.update(p.resolve() for v, p in photos.items() if v != filler)
    field = [p for p in sorted(mutaa.glob("*.jpeg")) if p.resolve() not in used]
    labelled = [p for p in sorted(LABELLED.glob("img-*.*")) if p.resolve() not in used]
    for kind, photos in (("mutaa-batch", field), ("labelled-batch", labelled)):
        groups = [photos[i : i + 3] for i in range(0, len(photos), 3)]
        for n, group in enumerate(groups, 1):
            # A short last group borrows earlier photos of its own kind: three distinct photographs are required.
            pad = [p for p in photos if p not in group][: 3 - len(group)]
            members = group + pad
            scans.append({"id": f"{kind}-{n:02d}", "kind": kind, "photos": dict(zip(VIEWS, members, strict=True)),
                          "padding": [str(p) for p in pad]})
    return scans


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mutaa", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    out = Path(args.out)
    raw = out / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    scans = plan(Path(args.mutaa))
    print(f"{len(scans)} scans planned ({sum(s['kind'] == 'set' for s in scans)} sets)")
    if args.dry_run:
        for s in scans:
            print(s["id"], {v: Path(p).name for v, p in s["photos"].items()})
        return 0
    work = out / "_sent"
    for s in scans:
        target = raw / f"{s['id']}.json"
        if target.exists():
            print(f"{s['id']}: saved answer reused")
            continue
        folder = work / s["id"]
        folder.mkdir(parents=True, exist_ok=True)
        sent = {v: prep(p, folder / f"{v}.jpg") for v, p in s["photos"].items()}
        scan_id = str(uuid.uuid4())
        try:
            answer = rfs.count_replay(ft.STAGING, scan_id, {v: folder / f"{v}.jpg" for v in VIEWS})
        except ft.WorkerHTTPError as error:
            answer = {"refused": {"status": error.status, "code": error.code, "message": str(error)}}
        answer.update({"_sent": sent, "_kind": s["kind"], "_set_id": s.get("set_id"), "_padding": s.get("padding", []),
                       "_filler": s.get("filler")})
        target.write_text(json.dumps(answer) + "\n", encoding="utf-8")
        job = answer.get("job") or {}
        print(f"{s['id']}: {job.get('pipeline_version')} {answer.get('result_status')} total {(answer.get('block') or {}).get('total_trays')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
