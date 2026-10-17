"""Replay archived photo evidence against an authenticated diagnostic host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time

import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reconstruct', action='store_true')
    args = parser.parse_args()
    token = os.environ['VISION_SERVICE_TOKEN']
    root = Path(__file__).resolve().parents[1]
    archive = root / 'reports' / 'warehouse-20260923'
    upstream = json.loads((archive / 'upstream-1.json').read_text())
    slots = {'left': 1, 'straight': 2, 'right': 3}
    files, views = {}, {}
    for view, number in slots.items():
        content = (archive / 'input' / f'image-{number}.jpg').read_bytes()
        boxes = []
        for detection in upstream['views'][view]['detections']:
            x, y = detection['x'], detection['y']
            half_w, half_h = detection['width'] / 2, detection['height'] / 2
            boxes.append({
                'bbox': [x - half_w, y - half_h, x + half_w, y + half_h],
                'confidence': detection['confidence'], 'class': 'egg_tray',
            })
        files[view] = (f'image-{number}.jpg', content, 'image/jpeg')
        views[view] = {
            'image_sha256': hashlib.sha256(content).hexdigest(),
            'coordinate_frame': 'exif_transposed_pixels', 'detections': boxes,
        }
    with httpx.Client(base_url=args.url.rstrip('/'), timeout=150) as client:
        started = time.perf_counter()
        health = client.get('/health')
        health_ms = round((time.perf_counter() - started) * 1000)
        rejected = client.post('/candidate/count-3d')
        started = time.perf_counter()
        response = client.post(
            '/candidate/count-3d', headers={'Authorization': f'Bearer {token}'},
            files=files, data={'evidence': json.dumps({'views': views})},
        )
        candidate_ms = round((time.perf_counter() - started) * 1000)
    try:
        health_body = health.json()
    except ValueError:
        health_body = {'response_text': health.text[:500]}
    summary = {
        'url': args.url, 'health_status': health.status_code,
        'health': health_body, 'health_ms': health_ms,
        'unauthenticated_candidate_status': rejected.status_code,
        'candidate_status': response.status_code, 'candidate_ms': candidate_ms,
        'source_view_assignment': slots, 'source_views_are_calibrated': False,
        'stable_scene_physically_confirmed': False,
        'source_sha256': {v: e['image_sha256'] for v, e in views.items()},
        'model_evidence': 'archived Roboflow V2 detections; no fresh inference',
    }
    args.output.mkdir(parents=True, exist_ok=True)
    if response.status_code == 200:
        result = response.json()
        summary.update({
            'status': result['status'], 'verified': result['verified'],
            'physical_trays': result['physical_trays'],
            'eligible_egg_trays': result['eligible_egg_trays'],
            'stack_candidates': len(result['stacks']),
            'correspondences': len(result['view_correspondence']),
            'sop_unverified': result['sop_unverified'],
        })
        (args.output / 'candidate-response.json').write_text(
            json.dumps(result, indent=2), encoding='utf-8',
        )
    else:
        summary['error'] = response.text[:500]
    (args.output / 'api-summary.json').write_text(
        json.dumps(summary, indent=2), encoding='utf-8',
    )
    print(json.dumps(summary, indent=2))
    if args.reconstruct:
        pair = {view: (f'image-{number}.jpg', (archive / 'input' / f'image-{number}.jpg').read_bytes(), 'image/jpeg')
                for view, number in (('first', 1), ('second', 2))}
        with httpx.Client(base_url=args.url.rstrip('/'), timeout=150) as client:
            rejected_pair = client.post('/candidate/reconstruct', files=pair)
            started = time.perf_counter()
            geometry_response = client.post('/candidate/reconstruct', files=pair,
                                            headers={'Authorization': f'Bearer {token}'})
        assert rejected_pair.status_code == 401
        geometry_response.raise_for_status()
        geometry = geometry_response.json()
        assert geometry['physical_trays'] is None and geometry['verified'] is False
        assert [source['sha256'] for source in geometry['sources']] == [
            hashlib.sha256(part[1]).hexdigest() for part in pair.values()]
        (args.output / 'reconstruction-response.json').write_text(json.dumps(geometry, indent=2), encoding='utf-8')
        geometry_summary = {
            'response_status': geometry_response.status_code, 'unauthenticated_status': rejected_pair.status_code,
            'processing_ms': round((time.perf_counter() - started) * 1000),
            'status': geometry['status'], 'mutual_matches': geometry['mutual_matches'],
            'fundamental_inliers': geometry.get('fundamental_inliers'),
            'triangulated_points': [h['triangulated_points'] for h in geometry['focal_hypotheses']],
            'physical_trays': geometry['physical_trays'], 'verified': geometry['verified'],
        }
        (args.output / 'reconstruction-summary.json').write_text(json.dumps(geometry_summary, indent=2), encoding='utf-8')
        print(json.dumps(geometry_summary, indent=2))
    return 0 if health.status_code == 200 and rejected.status_code == 401 and response.status_code == 200 else 1


if __name__ == '__main__':
    raise SystemExit(main())
