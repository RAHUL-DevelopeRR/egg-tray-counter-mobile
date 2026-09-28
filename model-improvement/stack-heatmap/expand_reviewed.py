"""Freeze the next visually reviewed development subset without rewriting V1."""
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
PRIOR = ROOT / 'reports/stack-heatmap-20260928/dataset'
OUT = ROOT / 'reports/stack-heatmap-followup-20260928/dataset'
EXCLUDED = 'WhatsApp Unknown 2026-09-26 at 6.45.01 AM'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(value, indent=2) + '\n').encode())


def rel(path):
    return path.relative_to(ROOT).as_posix()


def check():
    frozen = json.loads((OUT / 'frozen-manifest.json').read_text())
    for item in frozen['files']:
        assert sha(ROOT / item['path']) == item['sha256'], item['path']
    faces = json.loads((OUT / 'faces.json').read_text())
    inventory = json.loads((OUT / 'inventory.json').read_text())
    groups = {}
    for row in inventory:
        groups.setdefault(row['sha256'], set()).add(row['scene_id'])
    assert all(len(value) == 1 for value in groups.values())
    edges = json.loads((OUT / 'duplicate-lineage.json').read_text())['edges']
    assert all(groups[e['a']] == groups[e['b']] for e in edges)
    for face in faces:
        assert sha(ROOT / face['source_path']) == face['source_sha256']
        assert sha(ROOT / face['image_path']) == face['image_sha256']
        assert groups[face['source_sha256']] == {face['leakage_group_id']}
        assert len(face['centres_y']) == face['count']
        assert all(0 < y < 1 for y in face['centres_y'])
        assert all(a < b for a, b in zip(face['centres_y'], face['centres_y'][1:]))
        target = np.load(ROOT / face['target_path'])
        peaks = np.flatnonzero((target[1:-1] > target[:-2]) & (target[1:-1] >= target[2:])) + 1
        assert len(peaks) == face['count'], face['id']
    assert len(faces) == 11 and sum(f['count'] for f in faces) == 152
    assert len({f['leakage_group_id'] for f in faces}) == 2
    print(f'Checked {len(faces)} reviewed faces, 152 visible-layer targets, two conservative groups.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    if args.check_only:
        check()
        return
    if (OUT / 'frozen-manifest.json').exists():
        raise ValueError('Release already frozen; check it or create a new release.')
    cv2.setNumThreads(1)
    old = json.loads((PRIOR / 'inventory.json').read_text())
    excluded = [r for r in old if EXCLUDED in r['source_path']]
    inventory = [r for r in old if EXCLUDED not in r['source_path']]
    by_sha = {r['sha256']: r for r in inventory}
    retained = set(by_sha)
    edges = [e for e in json.loads((PRIOR / 'duplicate-lineage.json').read_text())['edges']
             if e['a'] in retained and e['b'] in retained]
    # Removing unrelated screenshots does not relax any prior leakage barrier.
    faces = json.loads((PRIOR / 'faces.json').read_text())
    review = json.loads((OUT / 'reviewed-additions.json').read_text())
    for spec in review:
        source = ROOT / spec['source_path']
        original = cv2.imread(str(source))
        quad = np.float32(spec['quad'])
        width = round((np.linalg.norm(quad[1]-quad[0]) + np.linalg.norm(quad[2]-quad[3])) / 2)
        height = round((np.linalg.norm(quad[3]-quad[0]) + np.linalg.norm(quad[2]-quad[1])) / 2)
        transform = cv2.getPerspectiveTransform(quad, np.float32([[0,0],[width-1,0],
                                                [width-1,height-1],[0,height-1]]))
        image_path = OUT / 'faces' / (spec['id'] + '.jpg')
        image_path.parent.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(image_path), cv2.warpPerspective(original, transform, (width,height)))
        mapped = cv2.perspectiveTransform(np.float32([spec['manual_centres_original']]), transform)[0]
        group = by_sha[sha(source)]['scene_id']
        face = {**spec, 'source_sha256': sha(source), 'scene_id': group, 'leakage_group_id': group,
                'split': 'development', 'image_path': rel(image_path), 'homography': transform.tolist(),
                'centres_y': sorted(float(p[1]/(height-1)) for p in mapped),
                'count': len(mapped), 'annotation_status': 'assistant_visual_reviewed',
                'ground_truth_status': 'visible_layer_reference_not_physical_inventory',
                'top_supported': False, 'base_supported': False, 'endpoints_calibrated': False,
                'occupancy': 'unknown', 'label_purpose': 'development_only'}
        faces.append(face)
        inventory.append({'source_id': sha(image_path), 'source_path': rel(image_path),
            'sha256': sha(image_path), 'scene_id': group, 'parent_source_id': sha(source),
            'derived_from': [sha(source)], 'split': 'development', 'is_derivative': True,
            'annotation_status': 'assistant_visual_reviewed',
            'ground_truth_status': 'visible_layer_reference_not_physical_inventory'})
    panels = []
    for face in faces:
        face['image_sha256'] = sha(ROOT / face['image_path'])
        centres = np.asarray(face['centres_y'])
        sigma = max(1/640, float(np.median(np.diff(centres))) * .16)
        y = np.arange(640)/639
        target = np.max(np.exp(-.5*((y[:,None]-centres[None,:])/sigma)**2), axis=1).astype('float32')
        target_path = OUT / 'targets' / (face['id'] + '.npy')
        target_path.parent.mkdir(parents=True, exist_ok=True)
        np.save(target_path, target)
        face.update(target_path=rel(target_path), target_sigma_normalized=sigma)
        image = cv2.resize(cv2.imread(str(ROOT / face['image_path'])), (160,640))
        for i, pos in enumerate(centres, 1):
            at = round(pos*639)
            cv2.line(image,(0,at),(159,at),(0,0,255),1)
            cv2.putText(image,str(i),(3,at-2),0,.3,(255,0,0),1)
        image = cv2.copyMakeBorder(image,45,0,0,5,cv2.BORDER_CONSTANT,value=(255,255,255))
        cv2.putText(image,face['id'],(3,17),0,.35,(0,0,0),1)
        cv2.putText(image,f"visual {face['count']}",(3,35),0,.4,(0,0,0),1)
        panels.append(image)
    dump(OUT/'faces.json', faces)
    dump(OUT/'inventory.json', inventory)
    dump(OUT/'duplicate-lineage.json', {'edges':edges,'policy':'Prior barriers retained, unrelated resume contents removed; no group split adjudicated.'})
    dump(OUT/'out-of-scope-additions.json', [{'source_path':r['source_path'],'sha256':r['sha256'],
        'reason':'Visual triage confirms unrelated resume/editor screenshots; not warehouse images.'} for r in excluded])
    dump(OUT/'summary.json', {'inventory_records':len(inventory),'unique_contents':len({r['sha256'] for r in inventory}),
        'excluded_unrelated_resume_paths':len(excluded),'near_duplicate_edges':len(edges),
        'reviewed_faces':len(faces),'reviewed_layer_targets':sum(f['count'] for f in faces),
        'leakage_groups':sorted({f['leakage_group_id'] for f in faces}),
        'review_manifest_sha256':sha(OUT/'reviewed-additions.json'), 'prior_manifest_sha256':sha(PRIOR/'faces.json'),
        'physical_ground_truth_certified':False,'V5_control':'unchanged_ineligible_no_complete_fullframe_QA',
        'split_policy':'Leave one entire conservative group out. New crops inherit parent group. No acceptance images.'})
    cv2.imwrite(str(OUT/'review-qa.jpg'), np.concatenate(panels,axis=1))
    files = sorted(p for p in OUT.rglob('*') if p.is_file())
    dump(OUT/'frozen-manifest.json', {'files':[{'path':rel(p),'sha256':sha(p)} for p in files]})
    check()


if __name__ == '__main__':
    main()
