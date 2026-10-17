"""Fresh model and local band audit. View slots are diagnostic, not calibrated poses."""
import hashlib
import json
import uuid
from pathlib import Path

import cv2
import httpx
from app.vision.spatial_3d import analyze_view, propose_correspondence

root = Path('reports/warehouse-20260923')
cv2.setNumThreads(1)
results, images = {}, {}
for batch, ids in enumerate(((1, 2, 3), (1, 2, 4)), 1):
    output = root / f'upstream-{batch}.json'
    if output.exists():
        payload = json.loads(output.read_text())
    else:
        scan_id = str(uuid.uuid4())
        files = {v: (f'image-{i}.jpg', (root / f'input/image-{i}.jpg').read_bytes(), 'image/jpeg')
                 for v, i in zip(('left', 'straight', 'right'), ids)}
        response = httpx.post('https://egg-tray-counter-api.rahultech72216.workers.dev/v1/scans/count',
            files=files, data={'scan_id': scan_id, 'scan_contract': 'model_spatial_v1'}, timeout=120)
        response.raise_for_status()
        payload = response.json()
        output.write_text(json.dumps(payload, indent=2))
    for view, i in zip(('left', 'straight', 'right'), ids):
        if i in results:
            continue
        path = root / f'input/image-{i}.jpg'
        image = cv2.imread(str(path))
        h, w = image.shape[:2]
        boxes = []
        for p in payload['views'][view]['detections']:
            box = [max(0, p['x']-p['width']/2), max(0, p['y']-p['height']/2),
                   min(w, p['x']+p['width']/2), min(h, p['y']+p['height']/2)]
            if box[2] > box[0] and box[3] > box[1]:
                boxes.append({'bbox': box, 'confidence': p['confidence'], 'class': 'egg_tray'})
        record = analyze_view(image, boxes, view)
        record.update(image_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
            view_assignment_confirmed=False, ground_truth=None)
        (root / f'image-{i}-analysis.json').write_text(json.dumps(record, indent=2))
        results[i], images[i] = record, image
        overlay = image.copy()
        for stack in record['stacks']:
            import numpy as np
            poly = np.array(stack['polygon'], dtype=np.int32)
            cv2.polylines(overlay, [poly], True, (0, 180, 255), 2)
            cv2.putText(overlay, f"bands {stack['beam'].get('exploratory_band_count')}",
                tuple(poly[0]), cv2.FONT_HERSHEY_SIMPLEX, .55, (0, 0, 255), 2)
        cv2.imwrite(str(root / f'image-{i}-overlay.jpg'), overlay)
        print(i, 'model', record['rf_count'], 'bands',
              [s['beam'].get('exploratory_band_count') for s in record['stacks']], flush=True)
mapping = {'left': 1, 'straight': 2, 'right': 3}
matches = propose_correspondence({v: images[i] for v, i in mapping.items()},
                               {v: results[i] for v, i in mapping.items()})
summary = {'physical_total': None, 'ground_truth': None, 'calibration': None,
           'stable_scene_confirmed': False, 'view_slots_are_diagnostic_only': True,
           'image_4_top_cropped': 'human_visual_observation', 'correspondence': matches,
           'images': {i: {'model_count': r['rf_count'], 'bands':
               [s['beam'].get('exploratory_band_count') for s in r['stacks']]} for i, r in results.items()}}
(root / 'summary.json').write_text(json.dumps(summary, indent=2))
