"""Known-image diagnostic, not 3D reconstruction or held-out accuracy testing.

Run from repo root; --run performs 12 model calls through four diagnostic scans.
Without --run, reuses saved responses. Production settings are never modified.
"""
import argparse
import json
import uuid
from pathlib import Path

import cv2
import httpx
import numpy as np

from prepare_manual_corrections import FACES, ROOT
from app.vision.stack_measurement import localize_stacks, analyze_rims

OUT = ROOT / 'crop-experiment'
URL = 'https://egg-tray-counter-api.rahultech72216.workers.dev/v1/scans/count'
VIEWS = ('left', 'right', 'straight')


def prepare(image):
    items = []
    for mode in ('crop', 'rectified'):
        for i, (points, rows) in enumerate(FACES, 1):
            q = np.float32(points)
            if mode == 'crop':
                x, y = np.floor(q.min(axis=0)).astype(int)
                r, b = np.ceil(q.max(axis=0)).astype(int)
                result = image[y:b+1, x:r+1].copy()
                transform = np.array([[1, 0, -x], [0, 1, -y], [0, 0, 1]], float)
            else:
                w = round((np.linalg.norm(q[1]-q[0])+np.linalg.norm(q[2]-q[3]))/2)
                h = round((np.linalg.norm(q[3]-q[0])+np.linalg.norm(q[2]-q[1]))/2)
                transform = cv2.getPerspectiveTransform(q, np.float32([[0,0],[w-1,0],[w-1,h-1],[0,h-1]]))
                mapped = cv2.perspectiveTransform(q[None], transform)[0]
                assert np.allclose(mapped, [[0,0],[w-1,0],[w-1,h-1],[0,h-1]], atol=.01)
                result = cv2.warpPerspective(image, transform, (w, h))
            name = f'{mode}-{i}'
            assert result.size and cv2.imwrite(str(OUT / f'{name}.jpg'), result)
            items.append({'name': name, 'stack': i, 'mode': mode, 'reference': len(rows),
                          'original_to_input': transform.tolist()})
    for i, name in ((1, 'wide-control'), (2, 'side-control')):
        (OUT / f'{name}.jpg').write_bytes((ROOT / f'input-{i}.jpg').read_bytes())
        items.append({'name': name, 'reference': 99 if i == 1 else 19, 'mode': 'control'})
    return items


def summarize(item, predictions):
    image = cv2.imread(str(OUT / f"{item['name']}.jpg"))
    h, w = image.shape[:2]
    # Axis-aligned crops can include adjacent faces: select centres in reviewed face.
    eligible = predictions
    if item.get('stack'):
        inverse = np.linalg.inv(np.array(item['original_to_input']))
        quad = np.float32(FACES[item['stack']-1][0])
        eligible = []
        for p in predictions:
            xy = cv2.perspectiveTransform(np.float32([[[p['x'], p['y']]]]), inverse)[0,0]
            if cv2.pointPolygonTest(quad, tuple(map(float, xy)), False) >= 0:
                eligible.append(p)
    for p in predictions:
        a = (round(p['x']-p['width']/2), round(p['y']-p['height']/2))
        b = (round(p['x']+p['width']/2), round(p['y']+p['height']/2))
        cv2.rectangle(image, a, b, (0,220,0) if p in eligible else (0,0,255), 1)
    cv2.imwrite(str(OUT / f"{item['name']}-detections.jpg"), image)
    counts = {str(t): sum(p['confidence'] >= t for p in eligible) for t in (.35,.45,.55,.65)}
    result = {**item, 'raw_count': len(predictions), 'face_count': len(eligible),
              'error': len(eligible)-item['reference'], 'threshold_counts': counts}
    if item.get('mode') == 'rectified':
        rows = np.asarray(FACES[item['stack']-1][1]) * (h-1)/1199
        tolerance = float(np.median(np.diff(rows)) * .45)
        hits = [[] for _ in rows]
        unmatched = []
        for n, p in enumerate(eligible):
            index = int(np.argmin(abs(rows-p['y'])))
            if abs(rows[index]-p['y']) <= tolerance:
                hits[index].append(n)
            else:
                unmatched.append(n)
        result['row_centre_audit'] = {
            'meaning':'Approximate manual row-centre matching, not box precision/recall',
            'tolerance_px':tolerance,
            'rows_without_match':[i+1 for i, found in enumerate(hits) if not found],
            'rows_with_multiple_boxes':[i+1 for i, found in enumerate(hits) if len(found)>1],
            'unmatched_box_indices':unmatched}
    return result


def main():
    cv2.setNumThreads(1)
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    original = cv2.imread(str(ROOT / 'input-1.jpg'))
    items = prepare(original)
    results = []
    for batch in range(4):
        group = items[batch*3:batch*3+3]
        path = OUT / f'batch-{batch+1}.json'
        if args.run and not path.exists():
            files = {view: (item['name']+'.jpg', (OUT/(item['name']+'.jpg')).read_bytes(), 'image/jpeg')
                     for view, item in zip(VIEWS, group)}
            response = httpx.post(URL, files=files, data={'scan_id':str(uuid.uuid4()),
                                  'scan_contract':'model_spatial_v1'}, timeout=150)
            response.raise_for_status()
            payload = response.json()
            assert payload['model']['model_id'] == 'projec-mutta/2'
            path.write_text(json.dumps(payload, indent=2))
        payload = json.loads(path.read_text())
        for view, item in zip(VIEWS, group):
            predictions = payload['views'][view]['detections']
            row = summarize(item, predictions)
            results.append(row)
            print(item['name'], row['raw_count'], row['face_count'], flush=True)
    predictions = json.loads((OUT/'batch-4.json').read_text())['views']['right']['detections']
    boxes = [{'bbox':[max(0,p['x']-p['width']/2),max(0,p['y']-p['height']/2),
                      min(original.shape[1],p['x']+p['width']/2),min(original.shape[0],p['y']+p['height']/2)],
              'confidence':p['confidence']} for p in predictions]
    automatic = localize_stacks(boxes, original.shape)
    for s in automatic:
        cv2.polylines(original,[np.int32(s['polygon'])],True,(0,0,255),2)
    cv2.imwrite(str(OUT/'automatic-localization.jpg'), original)
    summary = {'model':'projec-mutta/2','manual_roi_assisted':True,'held_out':False,
               'physical_total':None,'results':results,'automatic_regions':automatic,
               'lower_threshold_sweep':'Unavailable through current Worker; only >=35% post-filtered.',
               'bands':[]}
    for i in range(1,6):
        measured = analyze_rims(cv2.imread(str(OUT/f'rectified-{i}.jpg')))
        summary['bands'].append({'stack':i,'best':measured['best']})
    assert len(results)==12 and sum(r['reference'] for r in results[:5])==99
    (OUT/'results.json').write_text(json.dumps(summary,indent=2))


if __name__ == '__main__':
    main()
