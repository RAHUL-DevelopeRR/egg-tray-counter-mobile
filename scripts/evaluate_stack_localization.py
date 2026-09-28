"""Offline localization audit of saved V2 detections; no count truth is used by CV.

Reports spatial matches, fragments and merges against five reviewed quads. These
known-scene polygons are visual references, not new independent warehouse truth.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from scipy.optimize import linear_sum_assignment

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from app.vision.stack_measurement import localize_stacks
from prepare_manual_corrections import FACES


def evaluate(reviewed, predicted, *, iou_threshold=.5, association_threshold=.5):
    """Match polygons one-to-one; separately retain many-to-many fragment evidence.

    Association requires overlap >= half the smaller polygon. It is distinct from
    an accepted IoU match, so a contained narrow fragment cannot look like a face.
    """
    if not 0 < iou_threshold <= 1 or not 0 < association_threshold <= 1:
        raise ValueError('Overlap thresholds must be in (0, 1]')
    polygons = []
    for polygon in reviewed + predicted:
        q = np.asarray(polygon, dtype=np.float32)
        if q.ndim != 2 or q.shape[1] != 2 or len(q) < 3 or not np.isfinite(q).all():
            raise ValueError('Finite polygon coordinates required')
        if not cv2.isContourConvex(q) or cv2.contourArea(q) <= 0:
            raise ValueError('Evaluation requires nondegenerate convex polygons')
        polygons.append(q)
    n, m = len(reviewed), len(predicted)
    iou, overlap = np.zeros((n, m)), np.zeros((n, m))
    for i, ref in enumerate(polygons[:n]):
        for j, pred in enumerate(polygons[n:]):
            intersection = max(0, cv2.intersectConvexConvex(ref, pred)[0])
            a, b = cv2.contourArea(ref), cv2.contourArea(pred)
            iou[i, j] = intersection / (a+b-intersection)
            overlap[i, j] = intersection / min(a, b)
    matches = []
    if n and m:
        # Maximize valid match cardinality before IoU; invalid edges carry no weight.
        benefit = (iou >= iou_threshold) * (1 + iou)
        ri, pi = linear_sum_assignment(-benefit)
        matches = [{'reviewed_stack': int(i+1), 'predicted_stack': int(j+1), 'iou': float(iou[i,j])}
                   for i,j in zip(ri,pi) if iou[i,j] >= iou_threshold]
    associates = overlap >= association_threshold
    return {'reviewed_stack_faces': n, 'predicted_stack_faces': m,
            'iou_threshold': iou_threshold, 'association_threshold': association_threshold,
            'association_rule': 'intersection / smaller_polygon_area',
            'iou_matrix': iou.tolist(), 'association_overlap_matrix': overlap.tolist(), 'matches': matches,
            'splits': [{'reviewed_stack': i+1, 'predicted_stacks': (np.flatnonzero(row)+1).tolist()}
                       for i,row in enumerate(associates) if sum(row) > 1],
            'merges': [{'predicted_stack': j+1, 'reviewed_stacks': (np.flatnonzero(col)+1).tolist()}
                       for j,col in enumerate(associates.T) if sum(col) > 1],
            'misses_without_association': [i+1 for i,row in enumerate(associates) if not row.any()],
            'unmatched_reviewed_at_iou_threshold': [i+1 for i in range(n) if not any(a['reviewed_stack']==i+1 for a in matches)],
            'unmatched_predicted_at_iou_threshold': [j+1 for j in range(m) if not any(a['predicted_stack']==j+1 for a in matches)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'reports/stack-heatmap-20260928/localization')
    parser.add_argument('--self-check', action='store_true')
    args = parser.parse_args()
    cv2.setNumThreads(1)
    if args.self_check:
        face = [[0,0],[10,0],[10,20],[0,20]]
        fragments = [[[0,0],[10,0],[10,10],[0,10]], [[0,10],[10,10],[10,20],[0,20]]]
        split = evaluate([face], fragments)
        assert len(split['splits']) == 1 and not split['misses_without_association']
        merged = evaluate(fragments, [face])
        assert len(merged['merges']) == 1 and len(merged['matches']) == 1
        assert evaluate([face], [])['misses_without_association'] == [1]
        assert evaluate([], [])['matches'] == []
        assert evaluate([face], [face])['matches'][0]['iou'] == 1
        print('Spatial matching/split/merge/empty self-check passed')
    source = ROOT/'reports/two-view-20260924/input-1.jpg'
    previous = ROOT/'reports/two-view-20260924/crop-experiment'
    image = cv2.imread(str(source))
    if image is None:
        raise ValueError('Saved source image not readable')
    payload = json.loads((previous/'batch-4.json').read_text())
    detections = payload['views']['right']['detections']
    h,w = image.shape[:2]
    boxes = [{'bbox': [max(0,d['x']-d['width']/2), max(0,d['y']-d['height']/2),
                      min(w,d['x']+d['width']/2), min(h,d['y']+d['height']/2)],
              'confidence': d['confidence']} for d in detections]
    proposed = localize_stacks(boxes, image.shape)
    reviewed = [q for q,_ in FACES]
    result = evaluate(reviewed, [r['polygon'] for r in proposed])
    earlier = json.loads((previous/'results.json').read_text())
    result.update({'source_path': str(source.relative_to(ROOT)),
                   'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                   'scene_id': 'warehouse-20260923-pair', 'model': payload['model'],
                   'reference_provenance': 'assistant reviewed visible face polygons; known TRAIN scene',
                   'held_out': False, 'verified_inventory': False,
                   'automatic_algorithm': 'app.vision.stack_measurement.localize_stacks',
                   'reviewed_faces': [{'stack_id': i+1, 'polygon': q,
                                      'rectification': next(r['original_to_input'] for r in earlier['results']
                                                            if r['name']==f'rectified-{i+1}')}
                                     for i,q in enumerate(reviewed)],
                   'predicted_faces': proposed})
    assert len(proposed) == len(earlier['automatic_regions'])  # Saved algorithm replay invariant.
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/'result.json').write_text(json.dumps(result, indent=2, allow_nan=False))
    for color, quads, prefix in [((0,220,0), reviewed, 'R'), ((0,0,255), [r['polygon'] for r in proposed], 'P')]:
        for i,q in enumerate(quads, 1):
            poly = np.int32(q)
            cv2.polylines(image, [poly], True, color, 2)
            xy = tuple(poly[0] + [0, -5 if prefix=='R' else 18])
            cv2.putText(image, f'{prefix}{i}', xy, cv2.FONT_HERSHEY_SIMPLEX, .6, color, 2)
    assert cv2.imwrite(str(args.output/'spatial-mapping.jpg'), image)
    print(json.dumps({k: result[k] for k in ('reviewed_stack_faces','predicted_stack_faces','matches','splits','merges',
                                           'misses_without_association','unmatched_reviewed_at_iou_threshold')}, indent=2))


if __name__ == '__main__':
    main()
