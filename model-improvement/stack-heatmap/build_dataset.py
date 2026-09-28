"""Content inventory and reviewed layer targets. Run from any directory.

Raw capture-day groups are conservative leakage barriers, not asserted physical
scene identities. No archived detector predictions are promoted to labels.
"""
import argparse
import csv
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'work/vision-deps'))
sys.path.insert(0, str(ROOT / 'scripts'))
import cv2
import numpy as np
from PIL import Image, ImageOps
from prepare_manual_corrections import FACES

OUT = ROOT / 'reports/stack-heatmap-20260928/dataset'
EXT = {'.jpg', '.jpeg', '.png', '.webp'}
OUT_OF_SCOPE_FOLDER = 'WhatsApp Unknown 2026-09-22 at 6.27.37 AM'
# Root visual review of enlarged literal source crop; not RF/band-derived.
SCENE2_QUAD = [[454,578],[560,586],[552,705],[447,693]]
SCENE2_CENTRES = [[505,y] for y in (591,607,625,640,655,671,688)]


def dump(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')


def rel(path):
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dhash(path):
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert('L').resize((9, 8))
        a = np.asarray(im)
        return f'{int.from_bytes(np.packbits(a[:, 1:] > a[:, :-1]).tobytes(), "big"):016x}'


def csv_rows(path):
    with path.open(encoding='utf-8-sig', newline='') as file:
        return list(csv.DictReader(file))


def inventory():
    roots = [ROOT / 'datasets', ROOT / 'accuracy-evaluation/test-images',
             ROOT / 'reports/mutaa-20260916/originals',
             ROOT / 'reports/individual-trays-20260915',
             ROOT / 'reports/two-view-20260924/manual-corrections',
             ROOT / 'reports/two-view-20260924/focused-training']
    downloads = Path.home() / 'Downloads'
    roots += [p for p in downloads.iterdir() if p.is_dir() and
              (p.name.startswith('WhatsApp Unknown ') or p.name == 'MUTAA')
              and p.name != OUT_OF_SCOPE_FOLDER]
    excluded = downloads / OUT_OF_SCOPE_FOLDER
    dump(OUT / 'out-of-scope.json', [{'source_path': str(p), 'sha256': sha(p),
        'status': 'out_of_scope', 'reason': 'Visually reviewed unrelated voter UI / BookMyShow persona design.'}
        for p in sorted(excluded.glob('*.jpeg'))])
    paths = set()
    for folder in roots:
        if folder.exists():
            for path in folder.rglob('*'):
                if path.is_file() and path.suffix.lower() in EXT:
                    # Do not mistake a numbered overlay/QA render for original media.
                    if any(s in path.name for s in ('review', 'numbered', 'overlay', 'board')):
                        continue
                    paths.add(path)
    paths.update(ROOT / f'reports/two-view-20260924/input-{i}.jpg' for i in (1, 2))
    canonical = {r['sha256']: r for r in csv_rows(ROOT / 'datasets/canonical_clean/manifest.csv')}
    records, unreadable = [], []
    for path in sorted(paths):
        try:
            digest, perceptual = sha(path), dhash(path)
        except Exception as exc:
            unreadable.append({'source_path': rel(path), 'error': type(exc).__name__})
            continue
        record = canonical.get(digest, {})
        date = re.search(r'20\d\d[-_]\d\d[-_]\d\d', path.name)
        if record:
            date = re.search(r'20\d\d[-_]\d\d[-_]\d\d', record['source_path'])
        session = date.group().replace('_', '-') if date else 'unknown-historical-session'
        if 'two-view-20260924' in str(path):
            session = '2026-09-23'
        elif 'individual-trays-20260915' in str(path):
            session = '2026-09-15'
        elif 'mutaa-20260916' in str(path):
            session = '2026-09-16'
        derivative = 'focused-face-' in path.name
        records.append({'source_id': digest, 'source_path': rel(path), 'sha256': digest,
            'perceptual_hash': perceptual, 'scene_id': 'session-' + session,
            'capture_session_id': session, 'view': 'unknown', 'parent_source_id': None,
            'derived_from': [], 'annotation_status': 'historical_unreviewed' if
            (path.parent.parent / 'labels' / (path.stem + '.txt')).exists() else 'unannotated',
            'split': 'quarantine', 'historical_split': record.get('split'),
            'ground_truth_status': 'physical_count_unverified', 'is_derivative': derivative})
    # Session identity plus near-duplicate graph: conservative union, no random image split.
    parent = {r['scene_id']: r['scene_id'] for r in records}
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    def union(a, b):
        a, b = find(a), find(b)
        parent[max(a, b)] = min(a, b)
    unique = {}
    for r in records:
        if not r['is_derivative']:
            if r['sha256'] in unique:
                union(r['scene_id'], unique[r['sha256']]['scene_id'])
            else:
                unique[r['sha256']] = r
    originals = list(unique.values())
    edges = []
    for i, a in enumerate(originals):
        for b in originals[:i]:
            distance = (int(a['perceptual_hash'], 16) ^ int(b['perceptual_hash'], 16)).bit_count()
            if distance <= 8:
                union(a['scene_id'], b['scene_id'])
                edges.append({'a': a['sha256'], 'b': b['sha256'], 'dhash_distance': distance,
                              'status': 'conservative_candidate_same_split_not_confirmed_identity'})
    for r in records:
        r['scene_id'] = find(r['scene_id'])
    return records, edges, unreadable, roots


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='Regenerate and check lineage/targets.')
    parser.add_argument('--check-only', action='store_true', help='Verify saved source bytes, lineage and target peaks.')
    parser.add_argument('--reuse-inventory', action='store_true', help='Rebuild targets from the saved inventory checkpoint.')
    args = parser.parse_args()
    cv2.setNumThreads(1)
    if args.check_only:
        records = json.loads((OUT / 'inventory.json').read_text())
        faces = json.loads((OUT / 'faces.json').read_text())
        check(records, faces)
        source_availability({r['sha256']: r for r in records})
        freeze_snapshot()
        print(f'Checked {len(records)} inventory records, {len(faces)} reviewed faces, {sum(f["count"] for f in faces)} target peaks.')
        return
    OUT.mkdir(parents=True, exist_ok=True)
    if args.reuse_inventory:
        prior = json.loads((OUT / 'summary.json').read_text())
        records = [r for r in json.loads((OUT / 'inventory.json').read_text())
                   if not r['source_path'].startswith(rel(OUT / 'faces'))]
        edges = json.loads((OUT / 'duplicate-lineage.json').read_text())['edges']
        unreadable, roots = prior['unreadable_images'], [Path(p) for p in prior['searched_roots']]
    else:
        records, edges, unreadable, roots = inventory()
    by_sha = {}
    for r in records:
        by_sha.setdefault(r['sha256'], r)
    wide = ROOT / 'reports/two-view-20260924/input-1.jpg'
    scene = by_sha[sha(wide)]['scene_id']
    source_hash = sha(wide)
    labels = json.loads((ROOT / 'reports/two-view-20260924/focused-training/_annotations.coco.json').read_text())
    transforms = json.loads((ROOT / 'reports/two-view-20260924/crop-experiment/results.json').read_text())['results']
    faces, panels, snapshot_images, snapshot_annotations = [], [], [], []

    def add_face(id_, image_path, source_path, quad, transform, boxes, top_supported=True,
                 group=None, split='train', centres_override=None, include_control=True):
        im = cv2.imread(str(image_path)); h, w = im.shape[:2]
        group = group or scene
        centres = centres_override if centres_override is not None else sorted((b[1] + b[3] / 2) / h for b in boxes)
        assert all(0 < y < 1 for y in centres) and all(a < b for a, b in zip(centres, centres[1:]))
        target_h = 256
        positions = np.arange(target_h) / (target_h - 1)
        pitch = float(np.median(np.diff(centres)))
        sigma = max(1 / target_h, pitch * .16)
        target = np.max(np.exp(-.5 * ((positions[:, None] - np.array(centres)[None, :]) / sigma) ** 2), axis=1).astype('float32')
        target_path = OUT / 'targets' / f'{id_}.npy'
        target_path.parent.mkdir(exist_ok=True)
        np.save(target_path, target)
        face = {'id': id_, 'scene_id': group, 'leakage_group_id': group, 'split': split, 'image_path': rel(image_path),
            'source_sha256': sha(source_path), 'quad': quad, 'homography': transform,
            'source_path': rel(source_path),
            'centres_y': centres, 'count': len(centres), 'annotation_status': 'assistant_visual_reviewed',
            'ground_truth_status': 'visible_layer_reference_not_physical_inventory',
            'target_path': rel(target_path), 'target_sigma_normalized': sigma,
            'top_supported': top_supported, 'base_supported': include_control, 'occupancy': 'unknown'}
        if not include_control:
            face.update(provenance='root_visual_enlarged_crop_review_7_rims_approximate_centres',
                        label_purpose='development_only', source_quality='moderate_blur',
                        endpoints_calibrated=False, manual_centres_original=SCENE2_CENTRES)
        faces.append(face)
        digest = sha(image_path)
        for r in records:
            if r['sha256'] in (digest, sha(source_path)):
                r.update(scene_id=group, split=split)
                if r['sha256'] == digest:
                    r.update(parent_source_id=sha(source_path), derived_from=[sha(source_path)],
                             annotation_status='assistant_visual_reviewed',
                             ground_truth_status='visible_layer_reference_not_physical_inventory')
        # Snapshot copies original label extents; no model/band labels generated.
        if include_control:
            import shutil
            copied = OUT / 'v5-clean-control/train' / (id_ + '.jpg')
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(image_path, copied)
            image_id = len(snapshot_images) + 1
            snapshot_images.append({'id': image_id, 'file_name': copied.name, 'width': w, 'height': h,
                                    'scene_id': group, 'source_sha256': sha(source_path)})
            for box in boxes:
                snapshot_annotations.append({'id': len(snapshot_annotations) + 1, 'image_id': image_id,
                    'category_id': 1, 'bbox': box, 'area': box[2] * box[3], 'iscrowd': 0})
        panel = cv2.resize(im, (180, 700))
        for y in centres:
            cv2.line(panel, (0, round(y * 699)), (179, round(y * 699)), (0, 210, 255), 1)
        graph = np.full((700, 75, 3), 245, np.uint8)
        resized = cv2.resize(target[:, None], (1, 700))[:, 0]
        cv2.polylines(graph, [np.column_stack((resized * 65, np.arange(700))).astype('int32')], False, (170, 0, 0), 2)
        panel = np.concatenate((panel, graph), axis=1)
        panel = cv2.copyMakeBorder(panel, 50, 0, 0, 8, cv2.BORDER_CONSTANT, value=(255, 255, 255))
        cv2.putText(panel, f'{id_}: {len(boxes)}', (3, 21), 0, .45, (0, 0, 0), 1)
        cv2.putText(panel, 'Visual reference', (3, 42), 0, .4, (0, 0, 0), 1)
        panels.append(panel)

    for item in labels['images']:
        i = item['id']
        boxes = [a['bbox'] for a in labels['annotations'] if a['image_id'] == i]
        transform = next(r['original_to_input'] for r in transforms if r['name'] == f'rectified-{i}')
        add_face(f'focused-{i}', ROOT / 'reports/two-view-20260924/focused-training' / item['file_name'],
                 wide, FACES[i - 1][0], transform, boxes)
    # Side top is clipped: preserve visual19 for research, flag endpoint unresolved.
    corrections = json.loads((ROOT / 'reports/two-view-20260924/manual-corrections/_annotations.coco.json').read_text())
    side = ROOT / 'reports/two-view-20260924/input-2.jpg'
    side_im = cv2.imread(str(side))
    x0, y0, x1, y1 = 335, 0, 830, 1451
    side_crop = OUT / 'faces/side-19.jpg'; side_crop.parent.mkdir(exist_ok=True)
    cv2.imwrite(str(side_crop), side_im[y0:y1, x0:x1])
    boxes = [[a['bbox'][0] - x0, a['bbox'][1], a['bbox'][2], a['bbox'][3]]
             for a in corrections['annotations'] if a['image_id'] == 2]
    add_face('side-19', side_crop, side, [[x0,y0],[x1-1,y0],[x1-1,y1-1],[x0,y1-1]],
             [[1,0,-x0],[0,1,0],[0,0,1]], boxes, False)
    records.append({'source_id': sha(side_crop), 'source_path': rel(side_crop), 'sha256': sha(side_crop),
        'perceptual_hash': dhash(side_crop), 'scene_id': scene, 'capture_session_id': '2026-09-23',
        'view': 'unverified_side', 'parent_source_id': sha(side), 'derived_from': [sha(side)],
        'annotation_status': 'assistant_visual_reviewed', 'split': 'train',
        'ground_truth_status': 'visible_layer_reference_not_physical_inventory', 'is_derivative': True})
    source2 = ROOT / 'reports/individual-trays-20260915/image-06.jpg'
    scene2 = by_sha[sha(source2)]['scene_id']
    assert scene2 != scene, 'Development scene2 overlaps training leakage group'
    quad = np.float32(SCENE2_QUAD)
    w = round((np.linalg.norm(quad[1]-quad[0])+np.linalg.norm(quad[2]-quad[3]))/2)
    h = round((np.linalg.norm(quad[3]-quad[0])+np.linalg.norm(quad[2]-quad[1]))/2)
    transform = cv2.getPerspectiveTransform(quad, np.float32([[0,0],[w-1,0],[w-1,h-1],[0,h-1]]))
    mapped = cv2.perspectiveTransform(np.float32([SCENE2_CENTRES]), transform)[0]
    centres2 = sorted(float(p[1] / h) for p in mapped)
    edges2 = [max(0, centres2[0]-(centres2[1]-centres2[0])/2)]
    edges2 += [(a+b)/2 for a,b in zip(centres2, centres2[1:])]
    edges2 += [min(1, centres2[-1]+(centres2[-1]-centres2[-2])/2)]
    boxes2 = [[0, a*h, w, (b-a)*h] for a,b in zip(edges2, edges2[1:])]
    scene2_crop = OUT / 'faces/scene2-centre-7.jpg'
    im2 = cv2.imread(str(source2))
    cv2.imwrite(str(scene2_crop), cv2.warpPerspective(im2, transform, (w,h)))
    add_face('scene2-centre-7', scene2_crop, source2, SCENE2_QUAD, transform.tolist(), boxes2,
             False, scene2, 'valid', centres2, False)
    records.append({'source_id': sha(scene2_crop), 'source_path': rel(scene2_crop), 'sha256': sha(scene2_crop),
        'perceptual_hash': dhash(scene2_crop), 'scene_id': scene2, 'capture_session_id': '2026-09-15',
        'view': 'unverified_front', 'parent_source_id': sha(source2), 'derived_from': [sha(source2)],
        'annotation_status': 'assistant_visual_reviewed', 'split': 'valid',
        'ground_truth_status': 'visible_layer_reference_not_physical_inventory', 'is_derivative': True})
    overlay2 = im2.copy()
    cv2.polylines(overlay2, [quad.astype('int32')], True, (0,210,255), 2)
    for i, p in enumerate(SCENE2_CENTRES, 1):
        cv2.circle(overlay2, tuple(p), 2, (0,0,255), -1)
        cv2.putText(overlay2, str(i), (p[0]+4,p[1]), 0, .4, (0,0,255), 1)
    cv2.imwrite(str(OUT / 'scene2-source-review.jpg'), cv2.resize(overlay2[535:715,435:575], (560,720)))
    old = ROOT / 'model-improvement/09-data-expansion/warehouse-2026-09-07'
    provenance = json.loads((old / 'tray-layer-pilot-provenance.json').read_text())
    missing_reviewed = [{'id': r['id'], 'source_sha256': r['source_sha256'],
                        'reason': 'Source bytes unavailable; historical coordinates cannot label substitute image.'}
                       for r in provenance if r['source_sha256'] not in by_sha]
    # Historical72 are overview candidates awaiting full-resolution QA, never auto-approved.
    rejected = csv_rows(ROOT / 'model-improvement/01-dataset-audit/v2-label-policy-review.csv')
    dump(OUT / 'inventory.json', records)
    dump(OUT / 'duplicate-lineage.json', {'dhash_threshold': 8, 'edges': edges,
        'policy': 'Conservative session/date union plus exact/near duplicate graph; physical identity unconfirmed.'})
    dump(OUT / 'faces.json', faces)
    dump(OUT / 'development-splits.json', {'scene_splits': {scene: 'train', scene2: 'valid'},
        'cv_folds': [{'fold':i, 'train_scene_ids':[other], 'validation_scene_ids':[held]}
                     for i,(other,held) in enumerate(((scene,scene2),(scene2,scene)),1)],
        'cv_status': 'two_group_development_only_small_blurred_second_face',
        'final_acceptance_status': 'new_physically_counted_scene_required',
        'quarantined_inventory_groups': sorted({r['scene_id'] for r in records if r['split'] == 'quarantine'})})
    for split in ('train', 'valid', 'test'):
        dump(OUT / f'v5-clean-control/{split}/_annotations.coco.json', {
            'images': snapshot_images if split == 'train' else [],
            'annotations': snapshot_annotations if split == 'train' else [],
            'categories': [{'id': 1, 'name': 'egg_tray'}]})
    cv2.imwrite(str(OUT / 'heatmap-qa.jpg'), np.concatenate(panels, axis=1))
    summary = {'inventory_records': len(records), 'unique_contents': len({r['sha256'] for r in records}),
        'excluded_out_of_scope': len(json.loads((OUT / 'out-of-scope.json').read_text())),
        'near_duplicate_edges': len(edges), 'conservative_inventory_groups': len({r['scene_id'] for r in records}),
        'reviewed_faces': len(faces), 'reviewed_layer_targets': sum(f['count'] for f in faces),
        'reviewed_scene_groups': len({f['scene_id'] for f in faces}), 'physical_ground_truth_certified': False,
        'unreadable_images': unreadable, 'missing_reviewed_sources': missing_reviewed,
        'v2_overview_candidates_excluded_pending_full_resolution_QA': sum(r['review_status'] == 'overview_policy_consistent' for r in rejected),
        'searched_roots': [rel(p) for p in roots], 'snapshot_status': 'frozen_reviewed_subset_incomplete_valid_test_empty',
        'snapshot_manifest_sha256': sha(OUT / 'faces.json'), 'python': sys.executable}
    dump(OUT / 'summary.json', summary)
    source_availability(by_sha)
    freeze_snapshot()
    check(records, faces)
    print(json.dumps(summary, indent=2))


def source_availability(by_sha):
    references = []
    for manifest_name, path_key in (
        ('datasets/canonical_clean/manifest.csv', 'source_path'),
        ('model-improvement/09-data-expansion/warehouse-2026-09-07/intake.csv', 'source'),
        ('model-improvement/01-dataset-audit/v2-label-policy-review.csv', 'image')):
        for r in csv_rows(ROOT / manifest_name):
            path = Path(r[path_key])
            if not path.is_absolute():
                path = ROOT / path
            references.append({'manifest': manifest_name, 'recorded_source': r[path_key],
                'recorded_path_available': path.exists(),
                'content_hash_available_elsewhere': r.get('sha256') in by_sha if r.get('sha256') else None,
                'eligible_without_review': False})
    dump(OUT / 'source-availability.json', references)


def freeze_snapshot():
    files = sorted(p for p in (OUT / 'v5-clean-control').rglob('*')
                   if p.is_file() and p.name != 'frozen-manifest.json')
    manifest = {'status': 'incomplete_reviewed_layer_presence_subset',
        'training_release_eligible': False, 'occupancy_supervision_available': False,
        'files': [{'path': rel(p), 'sha256': sha(p)} for p in files]}
    frozen = OUT / 'v5-clean-control/frozen-manifest.json'
    if frozen.exists():
        assert json.loads(frozen.read_text()) == manifest, 'Frozen control content changed; create a new snapshot explicitly'
    else:
        dump(frozen, manifest)


def check(records, faces):
    by_sha = {}
    for r in records:
        by_sha.setdefault(r['sha256'], set()).add(r['scene_id'])
    assert all(len(groups) == 1 for groups in by_sha.values()), 'Exact duplicate scene lineage disagrees'
    for r in records:
        if r['parent_source_id']:
            assert by_sha[r['parent_source_id']] == {r['scene_id']}, 'Derivative changed source scene'
    edges = json.loads((OUT / 'duplicate-lineage.json').read_text())['edges']
    assert all(by_sha[e['a']] == by_sha[e['b']] for e in edges), 'Near duplicates cross leakage groups'
    for key in ('scene_id', 'sha256', 'parent_source_id'):
        splits = {}
        for r in records:
            if r[key] and r['split'] != 'quarantine':
                splits.setdefault(r[key], set()).add(r['split'])
        assert all(len(s) == 1 for s in splits.values()), f'{key} crosses development splits'
    assert len(faces) == 7 and sum(f['count'] for f in faces) == 125
    for face in faces:
        assert len(face['centres_y']) == face['count']
        assert sha(ROOT / face['source_path']) == face['source_sha256']
        target = np.load(ROOT / face['target_path'])
        peaks = np.flatnonzero((target[1:-1] > target[:-2]) & (target[1:-1] >= target[2:])) + 1
        assert len(peaks) == face['count'], (face['id'], len(peaks))
    assert len({f['scene_id'] for f in faces}) == 2


if __name__ == '__main__':
    main()
