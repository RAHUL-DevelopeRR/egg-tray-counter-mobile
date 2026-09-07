"""Upload only the explicitly reviewed detector subset; never upload predictions as truth."""
import csv
import json
import os
import io
import zipfile
import sys
from pathlib import Path
import httpx
from roboflow_rpc import rpc

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'model-improvement/09-data-expansion/warehouse-2026-09-07'
manifest = {r['id']: r for r in csv.DictReader((folder / 'intake.csv').open(encoding='utf-8'))}
review = json.loads((folder / 'reviewed-boxes.json').read_text())
journal_path = folder / 'upload-journal.json'
journal = json.loads(journal_path.read_text()) if journal_path.exists() else {}
def unpack(result):
    if result.get('isError'):
        raise RuntimeError(str(result))
    return result.get('structuredContent') or json.loads(result['content'][0]['text'])

session = unpack(json.loads((ROOT / 'work/warehouse-upload-session.json').read_text()))
if '--put' in sys.argv:
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_STORED) as z:
        for item in review['images']:
            z.write(manifest[item['id']]['source'], 'train/warehouse-20260907-'+item['id']+'.jpeg')
    with httpx.Client(timeout=120) as client:
        response = client.put(session['signedUrl'], content=archive.getvalue(), headers={'Content-Type':'application/zip'})
        if response.is_error:
            raise RuntimeError(f'ZIP upload HTTP {response.status_code}')
    print('ZIP transferred', session['taskId'])
elif '--status' in sys.argv:
    result = rpc('tools/call', {'name':'image_upload_status','arguments':{'task_id':session['taskId']}})
    (folder / 'upload-status.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
elif '--isolate' in sys.argv:
    # V2/V3 egg_tray labels are individual layers; these labels are stack faces.
    # Never include both units in the old clean-tag version filter.
    for item in review['images']:
        entry = journal[item['id']]
        result = unpack(rpc('tools/call', {'name':'images_update_metadata', 'arguments':{
            'image_id':entry['image_id'],
            'remove_tags':['clean-manual-auto-reconciled-v2'],
            'add_tags':['stack-face-only-20260907'],
            'metadata':{'annotation_unit':'stack_face', 'scene_id':review['scene_id'],
                        'count_ground_truth':'not_physically_verified'}}}))
        if not result.get('success'):
            raise RuntimeError('Isolation not confirmed: '+item['id'])
        entry['isolated_from_layer_dataset'] = True
        journal_path.write_text(json.dumps(journal, indent=2)+'\n')
        print(item['id'], 'isolated', flush=True)
elif '--annotate' in sys.argv or '--verify' in sys.argv:
    found = unpack(rpc('tools/call', {'name':'images_search','arguments':{'project_id':'projec-mutta',
        'query':'','tag':'warehouse-reviewed-20260907','limit':20,'fields':['id','name','filename','split','tags']}}))
    (folder / 'uploaded-images.json').write_text(json.dumps(found,indent=2)+'\n')
    images = found.get('images', found.get('results', []))
    if '--verify' in sys.argv:
        expected = {entry['image_id'] for entry in journal.values()}
        assert {item['id'] for item in images} == expected
        assert all('clean-manual-auto-reconciled-v2' not in item['tags'] for item in images)
        assert all('stack-face-only-20260907' in item['tags'] for item in images)
        assert all(item['split'] == 'train' for item in images)
        print('Verified isolated train-only stack-face images:', len(images))
        sys.exit(0)
    for item in review['images']:
        row = manifest[item['id']]
        assert not row['duplicate_of'] and not row['benchmark_matches'] and not row['training_matches']
        entry = journal.setdefault(item['id'], {})
        if not entry.get('image_id'):
            matches = [r for r in images if item['id'] in str(r.get('name', r.get('filename',''))) ]
            if len(matches) != 1:
                raise RuntimeError('Uploaded image name did not resolve uniquely: '+item['id'])
            entry['image_id'] = matches[0]['id']
            journal_path.write_text(json.dumps(journal, indent=2)+'\n')
            if not entry['image_id']:
                raise RuntimeError('Upload did not return an image id; inspect journal before retrying')
        if not entry.get('annotation_saved'):
            result = rpc('tools/call', {'name':'annotations_save', 'arguments':{
                'project_id':'projec-mutta', 'image_id':entry['image_id'],
                'annotation_content':(ROOT/'work/warehouse-reviewed'/(item['id']+'.txt')).read_text(),
                'annotation_name':item['id']+'.txt', 'labelmap':{'0':'egg_tray'}, 'add_to_dataset':True}})
            entry['annotation_response'] = result
            entry['annotation_saved'] = not result.get('isError', False)
            journal_path.write_text(json.dumps(journal, indent=2)+'\n')
            if not entry['annotation_saved']:
                raise RuntimeError('Annotation save failed; inspect journal')
        print(item['id'], entry['image_id'], 'saved', flush=True)
