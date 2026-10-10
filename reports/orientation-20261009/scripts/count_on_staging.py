"""Count the prepared uploads on the staging Worker next to the original photos and old-app controls."""
import json
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

STAGING = "https://egg-tray-counter-api-staging.rahultech72216.workers.dev"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ORIG = ROOT / "datasets/field-2026-10/labelled-20261007/originals"
REFERENCE = {"01": [20, 20, 20, 20, 19], "19": [20] * 5, "02": [20] * 4, "20": [20] * 3, "46": [20]}

REQUESTS = [
    {"straight": ("original 19", ORIG / "img-19.jpeg", "19"), "left": ("app r90 19", HERE / "upload-19-r90.jpg", "19"),
     "right": ("app r270 19", HERE / "upload-19-r270.jpg", "19")},
    {"straight": ("original 01", ORIG / "img-01.jpg", "01"), "left": ("app r90 01", HERE / "upload-01-r90.jpg", "01"),
     "right": ("app r270 01", HERE / "upload-01-r270.jpg", "01")},
    {"straight": ("original 02", ORIG / "img-02.jpeg", "02"), "left": ("app r90 02", HERE / "upload-02-r90.jpg", "02"),
     "right": ("app r270 02", HERE / "upload-02-r270.jpg", "02")},
    {"straight": ("original 20", ORIG / "img-20.jpeg", "20"), "left": ("app r0 20", HERE / "upload-20-r0.jpg", "20"),
     "right": ("OLD APP r90 19 (raw, tag 6)", HERE / "raw-19-r90.jpg", "19")},
    {"straight": ("app r90 46 narrow", HERE / "upload-46-r90.jpg", "46"), "left": ("original 46", ORIG / "img-46.jpeg", "46"),
     "right": ("OLD APP r270 01 (raw, tag 6)", HERE / "raw-01-r270.jpg", "01")},
]


def post(files: dict, attempts: int = 4) -> dict:
    for attempt in range(attempts):
        try:
            return _post(files)
        except (urllib.error.URLError, ConnectionError) as error:
            if attempt == attempts - 1:
                raise
            print(f"  retry after {error}")
            time.sleep(5 * (attempt + 1))


def _post(files: dict) -> dict:
    boundary = uuid.uuid4().hex
    body = b""
    for name, value in {"scan_id": str(uuid.uuid4()), "scan_contract": "model_spatial_v1"}.items():
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
    for view, (_, path, _) in files.items():
        body += (f'--{boundary}\r\nContent-Disposition: form-data; name="{view}"; filename="{view}.jpg"\r\n'
                 f"Content-Type: image/jpeg\r\n\r\n").encode() + path.read_bytes() + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    req = urllib.request.Request(f"{STAGING}/v1/scans/count", data=body, method="POST", headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}", "User-Agent": "egg-tray-tools/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)


def run(requests: list, tag: str) -> list:
    rows = []
    for i, files in enumerate(requests):
        result = post(files)
        (HERE / f"response-{tag}{i}.json").write_text(json.dumps(result, indent=1))
        for view, (label, _, ref_id) in files.items():
            cols = result["views"][view].get("stack_columns", [])
            walk = [c["walk_count"] for c in sorted(cols, key=lambda c: c["x_min"])]
            cap = result["block"]["capture"][view]
            ref = REFERENCE[ref_id]
            exact = sorted(walk) == sorted(ref)
            rows.append({"photo": label, "scan": result.get("scan_id"), "view": view, "boxes": cap["metrics"]["model_boxes"],
                         "box_aspect": cap["metrics"].get("box_aspect"), "walk": walk, "reference": ref,
                         "stacks_exact": exact, "accepted": cap["accepted"], "reasons": cap["reasons"]})
    (HERE / f"results{tag}.json").write_text(json.dumps(rows, indent=1))
    print(f"{'photo':32s} {'boxes':>5s} {'aspect':>6s}  {'accepted':8s} {'exact':5s} walk counts vs reference / reasons")
    for r in rows:
        print(f"{r['photo']:32s} {r['boxes']:5d} {str(r['box_aspect']):>6s}  {str(r['accepted']):8s} {str(r['stacks_exact']):5s} "
              f"{r['walk']} vs {r['reference']} {'; '.join(r['reasons'])}")
    return rows


CONTROL = [
    {"straight": ("scene 01 (upright, no app)", HERE / "scene-01-r90.jpg", "01"),
     "left": ("scene 02 (upright, no app)", HERE / "scene-02-r90.jpg", "02"),
     "right": ("scene 19 (upright, no app)", HERE / "scene-19-r90.jpg", "19")},
]

SPLIT = [
    {"straight": ("app, no trim 01 r90", HERE / "nocrop-01-r90.jpg", "01"),
     "left": ("app, no trim 02 r90", HERE / "nocrop-02-r90.jpg", "02"),
     "right": ("app, no trim 02 r270", HERE / "nocrop-02-r270.jpg", "02")},
    {"straight": ("trim only (no app) 01", HERE / "scenecrop-01.jpg", "01"),
     "left": ("trim only (no app) 02", HERE / "scenecrop-02.jpg", "02"),
     "right": ("app, no trim 19 r90", HERE / "nocrop-19-r90.jpg", "19")},
]

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "main"
    run({"control": CONTROL, "split": SPLIT}.get(which, REQUESTS), "" if which == "main" else which + "-")
