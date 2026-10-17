"""Unchanged V2 audit through existing gateway. Triplets are transport batches, not scenes.

Saves the complete gateway response; upstream RF JSON is not exposed by this gateway.
No secrets, threshold tuning, scene truth or production changes are needed.
"""

import argparse
import json
import ssl
import time
import uuid
from pathlib import Path

import httpx

URL = "https://egg-tray-counter-api.rahultech72216.workers.dev"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument(
        "--batch",
        type=int,
        help="Retry one transport batch; preserve prior error record",
    )
    parser.add_argument("--skip-batch", type=int)
    parser.add_argument(
        "--single",
        help="One image with two small companion images for gateway transport",
    )
    args = parser.parse_args()
    records = json.loads((args.report / "manifest.json").read_text())["images"]
    usable = [r for r in records if r["decodable"] and not r["duplicate_of"]]
    output = args.report / "raw"
    output.mkdir(exist_ok=True)
    with httpx.Client(verify=ssl.create_default_context(), timeout=240) as client:
        for name in ("health", "ready"):
            response = client.get(URL + "/" + name)
            response.raise_for_status()
            (output / (name + ".json")).write_text(response.text, encoding="utf-8")
        for start in range(0, len(usable), 3):
            if args.single and start > 0:
                break
            if args.skip_batch == start // 3 + 1:
                continue
            if args.batch is not None and start // 3 + 1 != args.batch:
                continue
            batch = usable[start : start + 3]
            if args.single:
                batch = [next(r for r in usable if r["id"] == args.single)]
            if len(batch) < 3:
                batch += sorted(
                    [r for r in usable if r not in batch], key=lambda r: r["bytes"]
                )[: 3 - len(batch)]
            destination = output / (
                f"single-{args.single}.json"
                if args.single
                else f"batch-{start // 3 + 1:02d}.json"
            )
            if destination.exists():
                continue
            scan_id = str(uuid.uuid4())
            views = dict(zip(("left", "right", "straight"), batch, strict=True))
            request = {
                "scan_id": scan_id,
                "scan_contract": "model_spatial_v1",
                "transport_views": {k: v["id"] for k, v in views.items()},
                "model": "projec-mutta/2",
                "confidence": 35,
                "overlap": 50,
                "classes": "egg_tray",
                "settings_source": "checked-in gateway configuration",
                "upstream_raw_available": False,
                "warning": "Transport grouping does not assert common scene or camera view",
            }
            (output / (destination.stem + "-request.json")).write_text(
                json.dumps(request, indent=2)
            )
            files = {
                view: (
                    r["filename"],
                    (args.report / r["original"]).read_bytes(),
                    "image/jpeg",
                )
                for view, r in views.items()
            }
            started = time.monotonic()
            try:
                response = client.post(
                    URL + "/v1/scans/count",
                    data={"scan_id": scan_id, "scan_contract": "model_spatial_v1"},
                    files=files,
                )
                if response.status_code != 200:
                    (output / (destination.stem + "-error.json")).write_text(
                        json.dumps(
                            {"status": response.status_code, "body": response.text}
                        )
                    )
                    print(destination.stem, "HTTP", response.status_code, flush=True)
                    continue
                payload = response.json()
                if payload.get("model", {}).get("model_id") != "projec-mutta/2":
                    raise ValueError("Unexpected model version")
                destination.write_text(response.text, encoding="utf-8")
                print(
                    destination.stem,
                    payload["stacks"][0]["counts"],
                    round(time.monotonic() - started, 1),
                    "seconds",
                    flush=True,
                )
            except (httpx.HTTPError, ValueError) as exc:
                # HTTP exception text can contain URLs; record only its type.
                (output / (destination.stem + "-error.json")).write_text(
                    json.dumps({"error_type": type(exc).__name__})
                )
                print(destination.stem, type(exc).__name__, flush=True)


if __name__ == "__main__":
    main()
