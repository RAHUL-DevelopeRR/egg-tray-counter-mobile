"""Staged, journaled Roboflow pilot. No deployment edits; no automatic training retry."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
from pathlib import Path
import zipfile
import httpx
from roboflow_rpc import rpc
from prepare_tray_layer_pilot import DATA, OUT, ROOT, prepare

TAG = 'tray-layer-pilot-20260907'
PROJECT = 'projec-mutta'
JOURNAL = DATA / 'tray-layer-pilot-run.json'
WORK = ROOT / 'work/tray-layer-pilot'


def unpack(result):
    if result.get('isError'):
        raise RuntimeError(str(result).replace(os.environ.get('ROBOFLOW_API_KEY', '\0'), '[REDACTED]'))
    return result.get('structuredContent') or json.loads(result['content'][0]['text'])


def call(name, **arguments):
    return unpack(rpc('tools/call', {'name': name, 'arguments': arguments}))


def save(journal):
    JOURNAL.write_text(json.dumps(journal, indent=2)+'\n')


def search(tag):
    records, offset = [], 0
    while True:
        page = call('images_search', project_id=PROJECT, query='', tag=tag,
                    limit=100, offset=offset, in_dataset=True,
                    fields=['id', 'name', 'split', 'tags'])
        rows = page.get('results', page.get('images', []))
        records.extend(rows)
        offset += len(rows)
        if offset >= page.get('total', offset) or not rows:
            return records


def main(stage, allow_public_upload=False):
    WORK.mkdir(parents=True, exist_ok=True)
    j = json.loads(JOURNAL.read_text()) if JOURNAL.exists() else {'status':'preparing', 'deploy':False}
    review = json.loads((DATA/'tray-layer-pilot.json').read_text())
    assert review['status'] == 'agent_visual_overlay_review_passed'
    expected_names = {f'warehouse-layer-pilot-20260907-{r["id"]}.jpg':r for r in review['images']}
    if stage == 'upload':
        prepare()
        project = call('projects_get', project_id=PROJECT)
        if project['project'].get('public') is not False and not allow_public_upload:
            raise PermissionError('Public/unknown project visibility: explicit user approval is required before uploading warehouse photos.')
        if j.get('upload_task_id'):
            raise RuntimeError('Upload already requested; inspect status, do not duplicate.')
        session = call('image_upload', project_id=PROJECT, split='train',
                       batch_name=TAG, tag_names=[TAG, 'warehouse-layer-reviewed-20260907'])
        # Signed URL is ephemeral; keep only in ignored work, never in committed evidence.
        (WORK/'upload-session.json').write_text(json.dumps(session))
        j['upload_task_id'] = session['taskId']
        save(j)
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_STORED) as z:
            for name in expected_names:
                z.write(OUT/name, 'train/'+name)
        with httpx.Client(timeout=120) as client:
            response = client.put(session['signedUrl'], content=archive.getvalue(), headers={'Content-Type':'application/zip'})
        if response.is_error:
            raise RuntimeError(f'Upload HTTP {response.status_code}; inspect task before retrying')
        j['status'] = 'upload_transferred'
    elif stage == 'upload-status':
        j['upload_status'] = call('image_upload_status', task_id=j['upload_task_id'])
    elif stage == 'annotate':
        # Uploaded batch assets are not Dataset members until annotations_save succeeds.
        found = call('images_search', project_id=PROJECT, query='', tag=TAG,
                     limit=100, fields=['id','name','split','tags'])
        rows = found.get('results', found.get('images', []))
        candidates = [r for r in rows if r['name'] in expected_names]
        assert len(candidates) == 3 and {r['name'] for r in candidates} == set(expected_names)
        for row in candidates:
            assert row['split'] == 'train'
            done = j.setdefault('annotations', {})
            if row['id'] in done:
                continue
            item = expected_names[row['name']]
            result = call('annotations_save', project_id=PROJECT, image_id=row['id'],
                          annotation_content=(OUT/Path(row['name']).with_suffix('.txt')).read_text(),
                          annotation_name=Path(row['name']).with_suffix('.txt').name,
                          labelmap={'0':'egg_tray'}, add_to_dataset=True)
            done[row['id']] = {'name':row['name'], 'visible_trays':item['expected_visible_layers'], 'response':result}
            save(j)
            print('Annotated', row['name'], item['expected_visible_layers'], flush=True)
        j['status'] = 'new_labels_saved'
    elif stage == 'tag-base':
        base = search('v3-policy-consistent-72')
        assert len(base) == 72 and len({r['id'] for r in base}) == 72
        assert Counter(r['split'] for r in base) == {'train':51,'valid':16,'test':5}
        assert all('stack-face-only-20260907' not in r['tags'] for r in base)
        j['base_images'] = base
        save(j)
        def tag(row):
            result = call('images_update_metadata', image_id=row['id'], add_tags=[TAG])
            assert result.get('success'), row['id']
            return row['id']
        with ThreadPoolExecutor(max_workers=4) as pool:
            for image_id in pool.map(tag, base):
                if image_id not in j.setdefault('base_tagged_ids', []):
                    j['base_tagged_ids'].append(image_id)
                save(j)
        j['status'] = 'base_tagged'
    elif stage == 'generate':
        if 'generation_requested' in j:
            raise RuntimeError('Generation was already requested; inspect version before any retry.')
        members = search(TAG)
        assert len(members) == 75 and len({r['id'] for r in members}) == 75
        assert Counter(r['split'] for r in members) == {'train':54,'valid':16,'test':5}
        assert {r['id'] for r in members} == set(j['base_tagged_ids']) | set(j['annotations'])
        assert all('stack-face-only-20260907' not in r['tags'] for r in members)
        j['members'] = members
        j['generation_requested'] = True
        save(j)
        j['generation'] = call('versions_generate', project_id=PROJECT,
            preprocessing={'auto-orient':True, 'resize':{'width':640,'height':640,'format':'Fit within'},
                           'filter-tags':{TAG:True}}, augmentation={},
            business_context='Controlled individual-tray-layer pilot: exact existing 72-image V3 subset plus three visually reviewed full-height foreground crops (47 new tray boxes). Not whole-folder training; no whole-stack labels; do not deploy without unchanged count benchmark.')
        j['status'] = 'version_requested'
    elif stage == 'version-status':
        version = j['version_number']
        j['version_status'] = call('versions_get', project_id=PROJECT, version_number=version)
    elif stage == 'train':
        if j.get('training_requested'):
            raise RuntimeError('Training was already requested; inspect existing run instead of duplicating credits.')
        version = j['version_number']
        info = call('versions_get', project_id=PROJECT, version_number=version)
        assert info.get('ready') and not info.get('generating')
        assert info['images'] == 75 and info['splits'] == {'train':54,'valid':16,'test':5}
        assert not info.get('trainings'), 'Version already has training; inspect it first'
        j['training_requested'] = True
        save(j)
        j['training'] = call('trainings_create', project_id=PROJECT, version_number=version,
            model_type='rfdetr-medium', checkpoint='rahuls-workspace-l9ylz/projec-mutta-2-rfdetr-medium-t1', epochs=100,
            business_context='User-requested Medium-only tray-layer pilot. Keep deployed V2 unchanged until exact >2/10 AND MAE <22.9 on the unchanged ten-file benchmark at confidence 35 / overlap 50. Three new crop images do not establish real-world accuracy.')
        j['status'] = 'training_requested'
    elif stage == 'training-status':
        j['trainings'] = call('trainings_list', project_id=PROJECT, version_number=j['version_number'])
    else:
        raise ValueError(stage)
    save(j)
    print(json.dumps({k:v for k,v in j.items() if k in ('status','generation','version_status','training','trainings','upload_status')}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['upload','upload-status','annotate','tag-base','generate','version-status','train','training-status'])
    parser.add_argument('--allow-public-upload', action='store_true', help='Use only AFTER the user explicitly approves public exposure of these warehouse crops.')
    args = parser.parse_args()
    main(args.stage, args.allow_public_upload)
