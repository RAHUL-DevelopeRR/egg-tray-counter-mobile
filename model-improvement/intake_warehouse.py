"""Inventory warehouse photos without changing originals or assigning ground truth."""
import csv
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from ml.audit_dataset import dhash, sha256_file


def distance(a, b):
    return (int(a, 16) ^ int(b, 16)).bit_count()


def main():
    source = Path(sys.argv[1])
    output = ROOT / 'model-improvement/09-data-expansion/warehouse-2026-09-07'
    output.mkdir(parents=True, exist_ok=True)
    sheets = ROOT / 'work/warehouse-2026-09-07'
    sheets.mkdir(parents=True, exist_ok=True)
    training = list(csv.DictReader((ROOT / 'model-improvement/01-dataset-audit/v2-image-manifest.csv').open()))
    golden = list(csv.DictReader((ROOT / 'accuracy-evaluation/manual-ground-truth.csv').open()))
    for row in golden:
        path = ROOT / row['source']
        row.update(dhash=dhash(path), sha256=sha256_file(path))
    records, seen = [], {}
    for i, path in enumerate(sorted(source.glob('*.jpeg')), 1):
        sha, dh = sha256_file(path), dhash(path)
        benchmark_matches = [r['image'] for r in golden if r['sha256'] == sha or distance(dh, r['dhash']) <= 8]
        training_matches = [r['path'] for r in training if r['sha256'] == sha or distance(dh, r['dhash']) <= 8]
        closest_golden = min(golden, key=lambda r: distance(dh, r['dhash']))
        closest_train = min(training, key=lambda r: distance(dh, r['dhash']))
        with Image.open(path) as im:
            width, height = ImageOps.exif_transpose(im).size
        record = dict(id=f'wh{i:03}', filename=path.name, source=str(path), width=width, height=height,
                      sha256=sha, dhash=dh, duplicate_of=seen.get(sha, ''),
                      benchmark_matches=';'.join(benchmark_matches), training_matches=';'.join(training_matches),
                      nearest_benchmark=closest_golden['image'], benchmark_distance=distance(dh, closest_golden['dhash']),
                      training_distance=distance(dh, closest_train['dhash']),
                      scene_id='', split='pending_scene_review', ground_truth_trays='',
                      ground_truth_status='not_verified', label_status='pending_visual_review')
        records.append(record)
        seen.setdefault(sha, record['id'])
    with (output / 'intake.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    unique = [r for r in records if not r['duplicate_of']]
    for page in range(0, len(unique), 12):
        sheet = Image.new('RGB', (1440, 1160), 'white')
        draw = ImageDraw.Draw(sheet)
        for j, row in enumerate(unique[page:page+12]):
            x, y = (j % 4)*360, (j // 4)*386
            with Image.open(row['source']) as im:
                thumb = ImageOps.contain(ImageOps.exif_transpose(im).convert('RGB'), (354, 346))
                sheet.paste(thumb, (x, y+30))
            draw.text((x+3, y+5), row['id'] + ' ' + row['filename'].split(' at ')[-1], fill='black')
        sheet.save(sheets / f'sheet-{page//12+1:02}.jpg', quality=93)
    summary = dict(files=len(records), unique=len(unique), duplicates=len(records)-len(unique),
                   benchmark_candidates=sum(bool(r['benchmark_matches']) for r in unique),
                   training_candidates=sum(bool(r['training_matches']) for r in unique),
                   method='SHA256 plus EXIF-normalized 64-bit dHash; Hamming <=8 flags review, not proof of identity. V2 manifest covers V3 subset. Scene review is still required.',
                   status='No uploads, splits or ground-truth claims made by intake.')
    (output / 'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps(summary, indent=2))
    assert len(seen) == len(unique)
    assert distance('0', 'ffffffffffffffff') == 64


if __name__ == '__main__':
    main()
