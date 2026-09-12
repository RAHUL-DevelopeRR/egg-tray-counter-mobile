"""Fixed, offline-only SAHI-style V2 experiment; never edits deployment or benchmark."""
import argparse
import base64
import csv
import hashlib
import io
import json
import math
import os
import time
from pathlib import Path

import cv2
import httpx
from PIL import Image
from evaluate_count_model import summarize

MODEL = 'rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1'
MANIFEST = Path('accuracy-evaluation/manual-ground-truth.csv')
IMAGES = Path('accuracy-evaluation/test-images')
BASELINE = Path('model-improvement/07-validation/v2-cell-logic-regression-20260908')
CONFIG = dict(model=MODEL, confidence=35, overlap=50, grid='2x2', tile_overlap_ratio=.2,
              full_image_pass=True, merge='OpenCV IoU NMS', merge_iou=.5,
              tile_encoding='lossless PNG', purpose='fixed development experiment, not deployment')


def slices(width, height):
    # Two tiles per axis, each covering dimension/(2-overlap); no image-specific tuning.
    tw, th = math.ceil(width / 1.8), math.ceil(height / 1.8)
    return list(dict.fromkeys((x, y, x+tw, y+th)
                             for y in [0, height-th] for x in [0, width-tw]))


def predictions(payload, x=0, y=0):
    if not isinstance(payload.get('predictions'), list):
        raise ValueError('Missing predictions: cannot score a failed request as zero')
    boxes = []
    for p in payload['predictions']:
        if p.get('class') != 'egg_tray':
            continue
        values = [p[k] for k in ('x', 'y', 'width', 'height', 'confidence')]
        if not all(isinstance(v, (int, float)) and math.isfinite(v) for v in values):
            raise ValueError('Invalid prediction geometry/confidence')
        if p['width'] <= 0 or p['height'] <= 0 or not .35 <= p['confidence'] <= 1:
            raise ValueError('Prediction outside fixed contract')
        boxes.append(dict(p, x=p['x']+x, y=p['y']+y))
    return boxes


def merge(boxes):
    if not boxes:
        return []
    xywh = [[p['x']-p['width']/2, p['y']-p['height']/2, p['width'], p['height']] for p in boxes]
    kept = cv2.dnn.NMSBoxes(xywh, [p['confidence'] for p in boxes], 0.0, .5)
    return [boxes[int(i)] for i in kept]


def self_check():
    for w, h in [(640, 640), (1200, 1600), (3, 5)]:
        regions = slices(w, h)
        assert all(0 <= x0 < x1 <= w and 0 <= y0 < y1 <= h for x0, y0, x1, y1 in regions)
        for x, y in [(0, 0), (w-1, h-1), (w//2, h//2)]:
            assert any(x0 <= x < x1 and y0 <= y < y1 for x0, y0, x1, y1 in regions)
    p = dict(x=5, y=5, width=8, height=8, confidence=.9, **{'class': 'egg_tray'})
    shifted = predictions({'predictions': [p]}, 10, 20)[0]
    assert (shifted['x'], shifted['y']) == (15, 25)
    assert len(merge([p, dict(p), shifted])) == 2
    assert len(merge([])) == 0
    try:
        predictions({})
    except ValueError:
        pass
    else:
        raise AssertionError('Missing result was accepted')
    assert summarize([dict(truth=10, prediction=8, absolute_error=2, relative_error_pct=20,
                           count_accuracy_pct=80, exact_match=False)])['mae'] == 2
    print('PASS: tile coverage, coordinate offsets, duplicate merge, invalid responses, shared metric')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('model-improvement/07-validation/v2-tiled-2x2-c35-o50-20260908'))
    parser.add_argument('--self-check', action='store_true')
    args = parser.parse_args()
    if args.self_check:
        self_check()
        return
    key = os.environ['ROBOFLOW_API_KEY']
    manifest = list(csv.DictReader(MANIFEST.open(encoding='utf-8')))
    baseline = list(csv.DictReader((BASELINE/'count-results.csv').open()))
    assert len(manifest) == len(baseline) == 10
    assert [r['image'] for r in manifest] == [r['image'] for r in baseline]
    assert all(r['model'] == MODEL and r['confidence'] == '35' and r['overlap'] == '50' for r in baseline)
    inputs = [{**r, 'sha256': hashlib.sha256((IMAGES/(r['image']+Path(r['source']).suffix.lower())).read_bytes()).hexdigest()} for r in manifest]
    run_config = {**CONFIG, 'inputs': inputs, 'baseline': str(BASELINE), 'opencv_version': cv2.__version__}
    args.output.mkdir(parents=True, exist_ok=True)
    config_file = args.output/'config.json'
    if config_file.exists():
        assert json.loads(config_file.read_text()) == run_config, 'Refusing mismatched cached experiment'
    else:
        config_file.write_text(json.dumps(run_config, indent=2)+'\n')
    rows = []
    with httpx.Client(timeout=120) as client:
        for item, old in zip(inputs, baseline):
            start = time.monotonic()
            path = IMAGES/(item['image']+Path(item['source']).suffix.lower())
            with Image.open(path) as source:
                assert source.getexif().get(274, 1) == 1, 'Non-upright EXIF requires explicit coordinate handling'
                image = source.convert('RGB')
            raw = args.output/'raw-json'/item['image']
            raw.mkdir(parents=True, exist_ok=True)
            full = json.loads((BASELINE/'raw-json'/(item['image']+'.json')).read_text())
            assert (full['image']['width'], full['image']['height']) == image.size
            boxes = predictions(full)
            assert len(boxes) == int(old['prediction'])
            (raw/'full.json').write_text(json.dumps(full, indent=2)+'\n')
            for index, (x0, y0, x1, y1) in enumerate(slices(*image.size)):
                data = io.BytesIO()
                image.crop((x0, y0, x1, y1)).save(data, format='PNG')
                encoded = data.getvalue()
                tile_sha = hashlib.sha256(encoded).hexdigest()
                cache = raw/f'tile-{index}.json'
                if cache.exists():
                    stored = json.loads(cache.read_text())
                    assert stored['sha256'] == tile_sha
                    payload = stored['response']
                else:
                    try:
                        response = client.post(f'https://serverless.roboflow.com/{MODEL}',
                            params={'api_key': key, 'confidence': 35, 'overlap': 50, 'classes': 'egg_tray', 'format': 'json'},
                            headers={'Content-Type': 'application/x-www-form-urlencoded'}, content=base64.b64encode(encoded))
                    except httpx.HTTPError:
                        raise RuntimeError('Tile request failed; no partial benchmark score') from None
                    if response.is_error:
                        raise RuntimeError(f'Tile inference HTTP {response.status_code}; no partial score')
                    payload = response.json()
                    predictions(payload)  # Validate before caching; errors are never silent zero counts.
                    cache.write_text(json.dumps({'sha256': tile_sha, 'crop': [x0,y0,x1,y1], 'response': payload}, indent=2)+'\n')
                assert (payload['image']['width'], payload['image']['height']) == (x1-x0, y1-y0)
                boxes.extend(predictions(payload, x0, y0))
            kept = merge(boxes)
            (raw/'merged.json').write_text(json.dumps({'predictions': kept, 'before_merge': len(boxes)}, indent=2)+'\n')
            truth, count = int(item['ground_truth_trays']), len(kept)
            error = abs(count-truth)
            rows.append(dict(image=item['image'], truth=truth, prediction=count, absolute_error=error,
                relative_error_pct=round(100*error/truth, 2), count_accuracy_pct=round(max(0, 100*(1-error/truth)), 2),
                exact_match=count==truth, confidence=35, overlap=50, model=MODEL,
                baseline_prediction=int(old['prediction']), additional_tile_seconds=round(time.monotonic()-start, 3)))
            print(f"{item['image']}: truth={truth}, baseline={old['prediction']}, tiled={count}", flush=True)
    with (args.output/'count-results.csv').open('w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = summarize(rows)
    summary['gate_passed'] = summary['exact_matches'] > 2 and summary['mae'] < 22.9
    summary['decision'] = 'CANDIDATE ONLY: requires safety review' if summary['gate_passed'] else 'DO NOT DEPLOY'
    (args.output/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
