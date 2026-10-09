"""Run the unchanged production V2 route on the labelled field photos.

Labels are NOT sent and NOT read during inference; scoring happens afterwards.
The Worker's three view slots are used as transport slots for three unrelated
images, so only per-image detection counts are meaningful.
"""
import json, subprocess, time, uuid
from pathlib import Path

ROOT = Path(__file__).parent
DATA = Path("datasets/field-2026-10/labelled-20261007")
GATEWAY = "https://egg-tray-counter-api.rahultech72216.workers.dev/v1/scans/count"
images = json.load(open(DATA / "manifest.json"))["images"]
ids = [r["id"] for r in images]
batches = [ids[i:i + 3] for i in range(0, len(ids), 3)]
if len(batches[-1]) < 3:  # pad with already-run images; padded results are ignored
    batches[-1] += [x for x in ids if x not in batches[-1]][: 3 - len(batches[-1])]
by_id = {r["id"]: r for r in images}
for n, batch in enumerate(batches, 1):
    out = ROOT / "raw" / f"batch-{n:02d}.json"
    if out.exists():
        continue
    scan_id = str(uuid.uuid4())
    args = ["curl", "-sS", "--max-time", "240", "-w", "\n%{http_code}", "-X", "POST", GATEWAY,
            "-F", f"scan_id={scan_id}", "-F", "scan_contract=model_spatial_v1"]
    for view, i in zip(("left", "right", "straight"), batch):
        args += ["-F", f"{view}=@{DATA / 'originals' / by_id[i]['file']};type=image/jpeg"]
    started = time.monotonic()
    proc = subprocess.run(args, capture_output=True, text=True)
    body, _, code = proc.stdout.rpartition("\n")
    record = {"batch": n, "scan_id": scan_id, "ids": dict(zip(("left", "right", "straight"), batch)),
              "http": code, "seconds": round(time.monotonic() - started, 2)}
    if code == "200":
        record["response"] = json.loads(body)
        out.write_text(json.dumps(record), encoding="utf-8")
        counts = {v: len(record["response"]["views"][v].get("detections") or []) for v in record["ids"]}
        print(n, code, record["seconds"], {record["ids"][v]: c for v, c in counts.items()})
    else:
        print(n, code, record["seconds"], proc.stderr.strip()[:200], body[:200])
