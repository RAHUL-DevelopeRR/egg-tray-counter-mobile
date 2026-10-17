"""Assisted layer diagnostic; manual ROIs, user truth loaded only after counting."""
import json
from pathlib import Path

import cv2

from app.config import Settings
from app.vision.layer_signal import count_layers
from app.vision.overlay import draw_rectified_layers
from app.vision.quality import decode_image
from app.vision.rectification import rectify_face

ROOT = Path(__file__).resolve().parents[1]
CASE = ROOT / 'reports/user-100-tray-case-20260915'


def main():
    image = decode_image((CASE / 'scene-annotated.jpg').read_bytes())
    # Manually localized from the supplied 675x507 scene, not model output.
    if image.shape[:2] != (507, 675):
        raise ValueError('Manual ROIs apply only to the archived 675x507 image')
    polygons = [
        ((60, 77), (181, 78), (205, 476), (84, 479)),
        ((181, 78), (305, 78), (321, 475), (205, 476)),
        ((305, 61), (430, 64), (438, 475), (321, 475)),
        ((430, 76), (550, 77), (555, 475), (438, 475)),
        ((550, 77), (673, 69), (673, 477), (555, 475)),
    ]
    settings = Settings()
    results = []
    for index, polygon in enumerate(polygons, 1):
        face = rectify_face(image, polygon, (settings.rectified_width, settings.rectified_height))
        result = count_layers(face.image, settings)
        if not cv2.imwrite(str(CASE / f'layers-column-{index}.jpg'),
                           draw_rectified_layers(face.image, result)):
            raise OSError('Could not save diagnostic overlay')
        results.append({'column_from_left': index, 'manual_polygon': polygon,
                        'layer_candidate': result.tray_count, 'pitch_px': result.pitch_px,
                        'quality': result.quality, 'reason': result.reason})
    # Scoring is separate: neither the 100 total nor the 20/column enters inference.
    truth = json.loads((CASE / 'reference.json').read_text())
    for result, reference in zip(results, truth['per_stack_truth'], strict=True):
        expected = reference['egg_containing_trays'] + reference['empty_trays']
        result['user_reported_physical_trays'] = expected
        result['signed_physical_count_error'] = (
            None if result['layer_candidate'] is None else result['layer_candidate'] - expected)
    report = {'method': 'existing layer counter; manual faces on annotated compressed image',
              'automatic_localization': False, 'occupancy_evaluated': False,
              'eligible_tray_total': None, 'columns': results}
    (CASE / 'assisted-layer-evaluation.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
