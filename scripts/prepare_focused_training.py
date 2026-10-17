"""Reviewed rectified-face labels and detection audit; no automatic training.

Bounds are manually read tray-base rows in the saved native-size crops.
This is a TRAIN-only supplement from one known scene, not a test dataset.
"""
import hashlib
import csv
import json
import shutil
import zipfile
from pathlib import Path

import cv2
import numpy as np

ROOT = Path('reports/two-view-20260924')
SOURCE = ROOT / 'crop-experiment'
OUT = ROOT / 'focused-training'
# Reviewed independently of model boxes; one visible tray from top to supporting rim.
BASES = [
    [99,130,161,191,220,250,281,310,339,369,397,425,452,480,507,534,559,585,609,634],
    [81,111,141,173,203,234,264,296,327,357,388,419,449,479,508,538,568,599,627,658],
    [81,115,147,182,215,250,283,317,348,382,414,447,480,510,542,573,605,637,667,698],
    [58,94,130,164,197,232,266,301,334,369,404,439,473,507,541,576,609,644,678,713],
    [44,80,114,150,186,222,258,296,334,372,410,446,482,520,559,598,636,672,702],
]


def main():
    cv2.setNumThreads(1)
    OUT.mkdir(parents=True, exist_ok=True)
    coco = {'images':[], 'annotations':[], 'categories':[{'id':1,'name':'egg_tray'}]}
    audit = []
    panels = []
    items = json.loads((SOURCE/'results.json').read_text())['results']
    for index, bases in enumerate(BASES, 1):
        src = SOURCE / f'rectified-{index}.jpg'
        name = f'focused-face-{index}.jpg'
        shutil.copyfile(src, OUT/name)
        image = cv2.imread(str(src)); h,w = image.shape[:2]
        assert len(bases) == (19 if index == 5 else 20)
        assert all(a < b for a,b in zip([0]+bases, bases)) and bases[-1] < h
        coco['images'].append({'id':index,'file_name':name,'width':w,'height':h,
            'scene_group':'warehouse-20260923-pair','split':'train',
            'sha256':hashlib.sha256(src.read_bytes()).hexdigest()})
        item_index = next(i for i,x in enumerate(items) if x['name']==f'rectified-{index}')
        payload = json.loads((SOURCE/f'batch-{item_index//3+1}.json').read_text())
        predictions = payload['views'][('left','right','straight')[item_index%3]]['detections']
        assignments = [[] for _ in bases]
        for pi,p in enumerate(predictions):
            row = int(np.searchsorted(bases, p['y'], side='left'))
            if row < len(bases):
                assignments[row].append(pi)
        for row,(top,bottom) in enumerate(zip([0]+bases[:-1], bases),1):
            coco['annotations'].append({'id':len(coco['annotations'])+1,'image_id':index,
                'category_id':1,'bbox':[0,top,w,bottom-top],'area':w*(bottom-top),
                'iscrowd':0,'segmentation':[], 'attributes':{'layer_top_down':row,
                'provenance':'assistant_visual_rim_review','extent':'rectified_visible_layer'}})
            color = (0,220,0) if len(assignments[row-1])==1 else (0,180,255)
            cv2.rectangle(image,(0,top),(w-1,bottom),color,1)
            cv2.putText(image,str(row),(3,(top+bottom)//2),0,.4,(0,0,0),3)
            cv2.putText(image,str(row),(3,(top+bottom)//2),0,.4,(255,255,255),1)
        cv2.imwrite(str(OUT/f'review-{index}.jpg'), image)
        audit.append({'stack':index,'reference':len(bases),'detections':len(predictions),
            'rows_without_detection_centre':[i+1 for i,p in enumerate(assignments) if not p],
            'rows_with_multiple_detection_centres':[i+1 for i,p in enumerate(assignments) if len(p)>1],
            'row_to_prediction_indices':assignments,
            'note':'Centre assignment flags candidates for review; spanning boxes may overlap other rows.'})
        panel = cv2.resize(image,(round(w*900/h),900))
        panels.append(cv2.copyMakeBorder(panel,35,0,0,8,cv2.BORDER_CONSTANT,value=(255,255,255)))
        cv2.putText(panels[-1],f'S{index}: {len(bases)}',(3,23),0,.55,(0,0,0),1)
    assert len(coco['annotations']) == 99
    # Every layer is contiguous and non-overlapping within its own face.
    for image in coco['images']:
        boxes=[a['bbox'] for a in coco['annotations'] if a['image_id']==image['id']]
        assert all(a[1]+a[3]==b[1] for a,b in zip(boxes,boxes[1:]))
    (OUT/'_annotations.coco.json').write_text(json.dumps(coco,indent=2))
    (OUT/'detection-audit.json').write_text(json.dumps(audit,indent=2))
    cv2.imwrite(str(OUT/'review-board.jpg'),np.concatenate(panels,axis=1))
    with zipfile.ZipFile(OUT/'train-supplement.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for path in [OUT/'_annotations.coco.json']+[OUT/i['file_name'] for i in coco['images']]:
            archive.write(path,path.name)
    with Path('datasets/canonical_clean/manifest.csv').open(encoding='utf-8-sig', newline='') as file:
        records = list(csv.DictReader(file))
    candidates = []
    for name in ('img04.jpg','img05.jpeg'):
        path = Path('accuracy-evaluation/test-images')/name
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        candidates.append({'path':path.as_posix(),'sha256':digest,
            'visual_reference':32 if name=='img04.jpg' else None,
            'physical_count':None,'source_scene_separation':'visually different arrangement',
            'canonical_exact_hash_matches':[{'id':r['canonical_image_id'],'split':r['split']}
                                            for r in records if r['sha256']==digest],
            'independent_test_verified':False,
            'reason':'Past training exposure and near-duplicates must be checked against frozen version.'})
    (OUT/'validation-candidates.json').write_text(json.dumps({'candidates':candidates,
        'excluded_same_scene':['img01.jpg','img02.jpg','img03.jpg','img06.jpeg'],
        'rule':'Do not move training examples to test; use candidate photos for diagnostic review only until provenance checked.'},indent=2))
    print(json.dumps(audit,indent=2))


if __name__=='__main__':
    main()
