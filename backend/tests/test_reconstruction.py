from io import BytesIO
from pathlib import Path
import numpy as np
from PIL import Image
from app.vision import reconstruction as geometry

ROOT = Path(__file__).resolve().parents[2]


def test_render_points_are_capped_deterministic_and_have_camera_centres():
    xyz = np.arange(9000, dtype=float).reshape(-1, 3)
    pixels = np.zeros((3000, 2))
    image = np.full((2, 2, 3), [1, 2, 3], dtype=np.uint8)
    args = (xyz, pixels, image, np.eye(3), np.array([[1.], [0], [0]]), .5, 3000)
    result = geometry.render_evidence(*args)
    assert result == geometry.render_evidence(*args)
    assert len(result['points']) == 2000
    assert result['points'][0] == [0., 1., 2., 3., 2., 1.]
    assert result['cameras'][1]['centre'] == [-1., 0., 0.]
    assert result['bounds']['max'] == xyz[-1].tolist()


def test_exif_focal_is_an_estimate_only_when_metadata_exists():
    image = Image.new('RGB', (120, 160))
    raw = BytesIO(); image.save(raw, 'JPEG')
    assert geometry.exif_focal_pixels(raw.getvalue(), 120, 160) is None
    exif = Image.Exif(); exif[34665] = {37386: 4.5, 41989: 26}
    raw = BytesIO(); image.save(raw, 'JPEG', exif=exif)
    assert np.isclose(geometry.exif_focal_pixels(raw.getvalue(), 120, 160), 26 * 200 / np.hypot(36, 24))


def test_negative_pair_has_no_pose_or_count(tmp_path):
    paths = [ROOT / 'reports/two-view-20260924' / f'input-{i}.jpg' for i in (1, 2)]
    result = geometry.run(paths, tmp_path)
    assert result['status'] in ('insufficient_matches', 'pose_failed')
    assert result['focal_hypotheses'] == []
    assert result['physical_trays'] is None and result['verified'] is False
    assert result['reason'] and result['scale'] == 'arbitrary_unit_baseline'


def test_positive_pair_shape_and_exif_hypothesis(tmp_path, monkeypatch):
    paths = [ROOT / 'reports/warehouse-20260923/input' / f'image-{i}.jpg' for i in (1, 2)]
    result = geometry.run(paths, tmp_path / 'no-exif')
    assert result['status'] == 'reconstructed'
    assert result['physical_trays'] is None and result['verified'] is False
    assert all(h['label'] != 'exif_focal' for h in result['focal_hypotheses'])
    for h in result['focal_hypotheses']:
        r = h['render']
        assert 8 <= len(r['points']) <= 2000
        assert len(r['cameras']) == 2 and all(len(p) == 6 for p in r['points'])
        assert np.isfinite(np.array(r['points'])).all()
    monkeypatch.setattr(geometry, 'exif_focal_pixels', lambda *args: 1200.)
    with_exif = geometry.run(paths, tmp_path / 'exif')
    assert any(h['label'] == 'exif_focal' and h['intrinsics_source'] == 'exif_estimate'
               for h in with_exif['focal_hypotheses'])
