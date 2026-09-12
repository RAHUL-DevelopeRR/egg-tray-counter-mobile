"""Export reviewed/draft full-frame boxes and a 74-image queue; never upload or train."""
import csv
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT/'model-improvement/09-data-expansion/warehouse-2026-09-07'
OUT = ROOT/'work/full-frame-layer-review'


def main():
    source = list(csv.DictReader((DATA/'intake.csv').open(encoding='utf-8')))
    unique = [r for r in source if not r['duplicate_of']]
    assert len(source) == 82 and len(unique) == 74
    review = json.loads((DATA/'full-frame-layer-review.json').read_text())
    assert review['annotation_unit'] == 'individual_egg_filled_tray_layer'
    reviewed = {r['id']: r for r in review['images']}
    assert len(reviewed) == len(review['images']) and set(reviewed) <= {r['id'] for r in unique}
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for r in unique:
        path = Path(r['source'])
        assert hashlib.sha256(path.read_bytes()).hexdigest() == r['sha256'], f"Changed source {r['id']}"
        record = reviewed.get(r['id'])
        row = dict(id=r['id'], source=r['source'], sha256=r['sha256'],
            target_class='egg_tray', annotation_unit='individual_egg_filled_tray_layer', empty_trays='non_target',
            overview_review='contact_sheet_triage_only',
            full_resolution_review='pending' if record is None else record['status'],
            labeled_visible_count='' if record is None else record['visible_annotation_count'],
            physical_inventory_gt='', physical_gt_status='not_verified',
            scene_group='green-room-20260907' if int(r['id'][2:]) < 68 or r['id']=='wh069' else 'other-warehouse-acquisition',
            split='unassigned_scene_group_must_stay_together', training_approved=False)
        rows.append(row)
        if record is None:
            continue
        with Image.open(path) as source_image:
            assert source_image.getexif().get(274, 1) == 1
            overlay = source_image.convert('RGB')
        draw = ImageDraw.Draw(overlay)
        boxes = record['boxes']
        assert len(boxes) == record['visible_annotation_count'] and len(set(map(tuple, boxes))) == len(boxes)
        labels = []
        for i, (x0,y0,x1,y1) in enumerate(boxes, 1):
            assert 0 <= x0 < x1 <= overlay.width and 0 <= y0 < y1 <= overlay.height
            draw.rectangle((x0,y0,x1,y1), outline='red' if i%2 else 'cyan', width=3)
            draw.text((x0+8, (y0+y1)/2), str(i), fill='white', stroke_width=2, stroke_fill='black', font_size=26)
            labels.append(f'0 {(x0+x1)/2/overlay.width:.8f} {(y0+y1)/2/overlay.height:.8f} {(x1-x0)/overlay.width:.8f} {(y1-y0)/overlay.height:.8f}')
        overlay.save(OUT/(r['id']+'-review.jpg'), quality=95)
        (OUT/(r['id']+'.txt')).write_text('\n'.join(labels)+'\n')
    with (DATA/'full-frame-review-queue.csv').open('w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f'{len(rows)} unique originals verified; {len(reviewed)} full-frame box drafts; 0 training approvals. No upload/training.')


if __name__ == '__main__':
    main()
