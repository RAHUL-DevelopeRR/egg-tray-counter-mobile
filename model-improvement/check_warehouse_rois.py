"""Measure existing layer counting on manually specified development ROIs."""
import csv
import json
import sys
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from app.config import Settings
from app.vision.rectification import rectify_face
from app.vision.layer_signal import count_layers
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks

folder = ROOT / 'model-improvement/09-data-expansion/warehouse-2026-09-07'
manifest = {r['id']: r for r in csv.DictReader((folder / 'intake.csv').open(encoding='utf-8'))}
rows = []
for item in json.loads((folder / 'counting-rois.json').read_text())['items']:
    with Image.open(manifest[item['id']]['source']) as im:
        source = cv2.cvtColor(np.array(ImageOps.exif_transpose(im).convert('RGB')), cv2.COLOR_RGB2BGR)
    settings = Settings()
    face = rectify_face(source, np.array(item['polygon'], dtype=np.float32), (settings.rectified_width, settings.rectified_height))
    result = count_layers(face.image, settings)
    hsv = cv2.cvtColor(face.image, cv2.COLOR_BGR2HSV)
    # Experimental only: colored plastic rails occupy more of a row than eggs.
    occupancy = np.mean(((hsv[:, 52:-52, 1] > 80) & (hsv[:, 52:-52, 2] > 35)).astype(float), axis=1)
    occupancy = gaussian_filter1d(occupancy, 1.2)
    candidates, _ = find_peaks(occupancy, height=0.72, prominence=0.12, distance=8)
    rows.append(dict(id=item['id'], truth=item['visible_foreground_trays'], prediction=result.tray_count,
                     detected_layers=result.detected_layers, inferred_layers=result.inferred_internal_layers,
                     quality=result.quality, reason=result.reason, saturation_experiment_count=len(candidates),
                     saturation_experiment_peaks=candidates.tolist(), scope='manual_ROI_development_not_end_to_end'))
    cv2.imwrite(str(ROOT / 'work/warehouse-2026-09-07' / (item['id']+'-rectified.jpg')), face.image)
(folder / 'layer-diagnostic.json').write_text(json.dumps(rows, indent=2)+'\n')
print(json.dumps(rows, indent=2))
