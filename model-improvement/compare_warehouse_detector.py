"""Cache production-threshold predictions against reviewed stack boxes, not tray totals."""
import base64
import csv
import json
import os
import sys
from pathlib import Path
import httpx
ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'model-improvement/09-data-expansion/warehouse-2026-09-07'
review = json.loads((folder / 'reviewed-boxes.json').read_text())
manifest = {r['id']:r for r in csv.DictReader((folder / 'intake.csv').open(encoding='utf-8'))}
model = sys.argv[1]
output = folder / ('detector-'+model.replace('/','-'))
output.mkdir(exist_ok=True)
rows = []
with httpx.Client(timeout=120) as client:
    for item in review['images']:
        path = output / (item['id']+'.json')
        if path.exists():
            payload = json.loads(path.read_text())
        else:
            response = client.post('https://serverless.roboflow.com/'+model,
                params={'api_key':os.environ['ROBOFLOW_API_KEY'],'confidence':35,'overlap':50,'classes':'egg_tray','format':'json'},
                headers={'Content-Type':'application/x-www-form-urlencoded'},
                content=base64.b64encode(Path(manifest[item['id']]['source']).read_bytes()))
            if response.is_error:
                raise RuntimeError(f'Inference HTTP {response.status_code}')
            payload = response.json()
            path.write_text(json.dumps(payload,indent=2)+'\n')
        predictions = [p for p in payload.get('predictions',[]) if p.get('class')=='egg_tray']
        rows.append(dict(id=item['id'],model=model,truth_stack_boxes=len(item['boxes']),raw_detection_count=len(predictions),
            comparable_units=False, reason='Legacy egg_tray layer detections are not stack-face detections',
            ground_truth_trays=None,scope='detector_development_only_not_tray_count_accuracy',confidence=35,overlap=50))
        print(rows[-1],flush=True)
(output/'comparison.json').write_text(json.dumps(rows,indent=2)+'\n')
