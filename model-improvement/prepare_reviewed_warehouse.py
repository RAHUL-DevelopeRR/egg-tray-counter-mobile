"""Export explicitly reviewed warehouse boxes and render them for a second pass."""
import csv
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'model-improvement/09-data-expansion/warehouse-2026-09-07'
data = json.loads((folder / 'reviewed-boxes.json').read_text())
manifest = {r['id']: r for r in csv.DictReader((folder / 'intake.csv').open(encoding='utf-8'))}
output = ROOT / 'work/warehouse-reviewed'
output.mkdir(parents=True, exist_ok=True)
for item in data['images']:
    row = manifest[item['id']]
    with Image.open(row['source']) as source:
        im = ImageOps.exif_transpose(source).convert('RGB')
    assert list(im.size) == item['size']
    w, h = im.size
    text = []
    draw = ImageDraw.Draw(im)
    for i, (x1, y1, x2, y2) in enumerate(item['boxes'], 1):
        assert 0 <= x1 < x2 <= w and 0 <= y1 < y2 <= h
        text.append(f'0 {(x1+x2)/2/w:.8f} {(y1+y2)/2/h:.8f} {(x2-x1)/w:.8f} {(y2-y1)/h:.8f}')
        draw.rectangle((x1,y1,x2,y2), outline='red', width=3)
        draw.text((x1+3,y1+4), str(i), fill='red', stroke_width=1)
    (output / (item['id']+'.txt')).write_text('\n'.join(text)+'\n')
    im.save(output / (item['id']+'-review.jpg'), quality=94)
print('Reviewed export:', len(data['images']), 'images;', sum(len(i['boxes']) for i in data['images']), 'boxes')
