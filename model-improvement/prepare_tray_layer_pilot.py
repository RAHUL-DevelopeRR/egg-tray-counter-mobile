"""Export explicitly drawn tray-layer boxes, with provenance and numbered QA overlays."""
import csv
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'model-improvement/09-data-expansion/warehouse-2026-09-07'
OUT = ROOT / 'work/tray-layer-pilot'


def prepare():
    review = json.loads((DATA / 'tray-layer-pilot.json').read_text())
    rows = {r['id']: r for r in csv.DictReader((DATA / 'intake.csv').open(encoding='utf-8'))}
    OUT.mkdir(parents=True, exist_ok=True)
    provenance = []
    assert review['annotation_unit'] == 'individual_visible_tray_layer'
    assert review['split'] == 'train'  # all views of this warehouse-day stay together
    for item in review['images']:
        row = rows[item['id']]
        source = Path(row['source'])
        assert hashlib.sha256(source.read_bytes()).hexdigest() == row['sha256']
        assert not any(row[k] for k in ('duplicate_of', 'benchmark_matches', 'training_matches'))
        original = ImageOps.exif_transpose(Image.open(source)).convert('RGB')
        x0, y0, x1, y1 = item['crop']
        assert 0 <= x0 < x1 <= original.width and 0 <= y0 < y1 <= original.height
        crop = original.crop(item['crop'])
        overlay = crop.copy()
        draw = ImageDraw.Draw(overlay)
        lines = []
        assert len(item['boxes']) == item['expected_visible_layers']
        assert len({tuple(b) for b in item['boxes']}) == len(item['boxes'])
        for number, (left, top, right, bottom) in enumerate(item['boxes'], 1):
            assert x0 <= left < right <= x1 and y0 <= top < bottom <= y1
            box = (left-x0, top-y0, right-x0, bottom-y0)
            color = 'red' if number % 2 else 'cyan'
            draw.rectangle(box, outline=color, width=2)
            draw.text((box[0]+5, (box[1]+box[3])/2-8), str(number), fill='white', stroke_width=2, stroke_fill='black', font_size=22)
            lines.append(f'0 {((left+right)/2-x0)/crop.width:.8f} {((top+bottom)/2-y0)/crop.height:.8f} {(right-left)/crop.width:.8f} {(bottom-top)/crop.height:.8f}')
        name = f'warehouse-layer-pilot-20260907-{item["id"]}'
        crop.save(OUT / (name+'.jpg'), quality=95)
        overlay.save(OUT / (item['id']+'-review.jpg'), quality=95)
        (OUT / (name+'.txt')).write_text('\n'.join(lines)+'\n')
        provenance.append({'id':item['id'], 'source_sha256':row['sha256'], 'crop':item['crop'],
            'derived_filename':name+'.jpg', 'derived_sha256':hashlib.sha256((OUT/(name+'.jpg')).read_bytes()).hexdigest(),
            'visible_layers':len(lines), 'split':review['split'], 'scene_group':review['scene_group']})
    (DATA / 'tray-layer-pilot-provenance.json').write_text(json.dumps(provenance, indent=2)+'\n')
    print(f'Validated {len(provenance)} crops, {sum(p["visible_layers"] for p in provenance)} individual tray boxes; originals unchanged.')


if __name__ == '__main__':
    prepare()
