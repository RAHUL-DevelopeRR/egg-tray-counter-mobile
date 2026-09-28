"""Render assistant-reviewed photo references; these are not physical ground truth.

Layer positions below were manually read from enlarged photographs, independently
of the detector and band output. Recount/review overlays before changing them.
"""
import hashlib
import json
import shutil
from pathlib import Path

import cv2
import numpy as np

ROOT = Path('reports/two-view-20260924')
OUT = ROOT / 'manual-corrections'
# Face inspection coordinates; row centres manually selected in 250x1200 crops.
FACES = [
    ([[188,510],[310,541],[345,1202],[218,1148]],
     [140,205,265,325,380,441,498,552,604,657,709,760,809,858,904,953,999,1044,1090,1130]),
    ([[310,541],[477,583],[490,1282],[345,1202]],
     [100,160,214,270,326,382,437,489,543,596,650,702,755,809,861,912,965,1015,1069,1120]),
    ([[477,583],[656,628],[651,1369],[490,1282]],
     [100,157,215,273,328,385,442,497,553,607,663,718,770,823,875,929,978,1028,1078,1129]),
    ([[656,628],[881,683],[835,1448],[651,1369]],
     [60,120,176,230,282,337,391,446,501,555,609,665,719,771,825,880,935,990,1044,1095]),
    ([[859,730],[1140,777],[1010,1500],[810,1400]],
     [37,106,166,225,282,342,403,468,528,591,652,717,780,847,913,978,1043,1103,1168]),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    coco = {'images': [], 'annotations': [], 'categories': [{'id': 1, 'name': 'egg_tray'}]}
    reference = {'provenance': 'assistant manual visual recount, not physical inventory',
                 'scene_group': 'warehouse-20260923-pair', 'split': 'train',
                 'eligible_for_independent_accuracy_test': False, 'images': []}
    for image_id in (1, 2):
        path = ROOT / f'input-{image_id}.jpg'
        image = cv2.imread(str(path)); h, w = image.shape[:2]
        name = f'manual-20260924-{image_id}.jpg'
        shutil.copyfile(path, OUT / name)
        coco['images'].append({'id': image_id, 'file_name': name, 'width': w, 'height': h})
        boxes = []
        if image_id == 1:
            for stack_id, (quad, ys) in enumerate(FACES, 1):
                inverse = cv2.getPerspectiveTransform(np.float32([[0,0],[249,0],[249,1199],[0,1199]]), np.float32(quad))
                # Approximate front-face annotation extents; centres are the manual evidence.
                edges = [max(0, ys[0] - 65)] + [(a+b)/2 for a,b in zip(ys,ys[1:])] + [ys[-1]+25]
                for layer, y in enumerate(ys, 1):
                    row = np.float32([[[0,edges[layer-1]],[249,edges[layer-1]],
                                      [249,edges[layer]],[0,edges[layer]]]])
                    polygon = cv2.perspectiveTransform(row, inverse)[0]
                    centre = cv2.perspectiveTransform(np.float32([[[124,y]]]), inverse)[0,0]
                    boxes.append((stack_id,layer,polygon,centre))
        else:
            bottoms = [60,155,249,341,432,516,600,682,760,836,910,986,1056,1127,1194,1257,1322,1385,1450]
            for layer, (top,bottom) in enumerate(zip([0]+bottoms[:-1],bottoms), 1):
                left = 335 + 25 * bottom/1450
                right = 830 - 75 * bottom/1450
                polygon = np.float32([[left,top],[right,top],[right,bottom],[left,bottom]])
                boxes.append((1,layer,polygon,np.float32([(left+right)/2,(top+bottom)/2])))
        for stack_id,layer,polygon,centre in boxes:
            minimum = np.maximum(polygon.min(axis=0),[0,0])
            maximum = np.minimum(polygon.max(axis=0),[w,h])
            x,y = minimum; bw,bh = maximum-minimum
            assert bw > 0 and bh > 0
            coco['annotations'].append({'id':len(coco['annotations'])+1,'image_id':image_id,
                'category_id':1,'bbox':[float(x),float(y),float(bw),float(bh)],
                'area':float(bw*bh),'iscrowd':0,'segmentation':[],
                'attributes':{'stack':stack_id,'layer_top_down':layer,
                              'source':'assistant_manual','extent':'approximate_front_face',
                              'egg_evidence':'visible','truncated':image_id==2 and layer==1}})
            cv2.polylines(image,[polygon.astype(np.int32)],True,(0,210,255),1)
            label=f'{stack_id}:{layer}'
            point=tuple(centre.astype(int))
            cv2.putText(image,label,point,0,.42,(0,0,0),3)
            cv2.putText(image,label,point,0,.42,(255,255,255),1)
        cv2.imwrite(str(OUT/f'numbered-{image_id}.jpg'),image)
        reference['images'].append({'file_name':name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'visible_egg_trays':len(boxes),'per_stack':[20,20,20,20,19] if image_id==1 else [19],
            'physical_total':None,'hidden_occupancy':'unknown','boxes_are_approximate':True})
    assert len(coco['annotations']) == 118
    (OUT/'_annotations.coco.json').write_text(json.dumps(coco,indent=2),encoding='utf-8')
    (OUT/'manual-reference.json').write_text(json.dumps(reference,indent=2),encoding='utf-8')
    print('Manual visual references: 99 wide, 19 side; 118 draft front-face boxes; no 3D total.')


if __name__ == '__main__':
    main()
