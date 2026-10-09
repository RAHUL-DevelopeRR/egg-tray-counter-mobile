import json
import pytest
import numpy as np
from io import BytesIO
from PIL import Image
from fastapi.testclient import TestClient
from app.vision_service import create_vision_app


def test_diagnostic_host_requires_auth_and_never_advertises_verified_inventory():
    with pytest.raises(ValueError):
        create_vision_app('short')
    client = TestClient(create_vision_app('x' * 32))
    assert client.get('/health').json()['inventory_verification_ready'] is False
    assert client.post('/candidate/count-3d').status_code == 401
    assert client.post('/candidate/count-3d', headers={'Authorization': 'Bearer ' + 'x' * 32}).status_code == 422
    assert client.post('/v1/scans/count', headers={'Authorization': 'Bearer ' + 'x' * 32}).status_code == 404


def test_reconstruction_contract_validates_photos_and_keeps_count_unverified():
    client = TestClient(create_vision_app('x' * 32))
    headers = {'Authorization': 'Bearer ' + 'x' * 32}
    assert client.post('/candidate/reconstruct').status_code == 401
    photos = []
    for color in ('white', 'black'):
        buffer = BytesIO()
        Image.new('RGB', (64, 64), color).save(buffer, format='PNG')
        photos.append(buffer.getvalue())
    def files(second):
        return {'first': ('first.png', photos[0], 'image/png'),
                'second': ('second.png', second, 'image/png')}
    assert client.post('/candidate/reconstruct', headers=headers, files=files(photos[0])).status_code == 422
    assert client.post('/candidate/reconstruct', headers=headers, files=files(b'\x89PNG\r\n\x1a\ncorrupt')).status_code == 415
    response = client.post('/candidate/reconstruct', headers=headers, files=files(photos[1]))
    assert response.status_code == 200
    result = response.json()
    assert result['physical_trays'] is None and result['verified'] is False
    assert result['status'] == 'insufficient_matches' and result['focal_hypotheses'] == []


def test_rim_count_route_counts_painted_rims_and_requires_auth():
    client = TestClient(create_vision_app('x' * 32))
    headers = {'Authorization': 'Bearer ' + 'x' * 32}
    # 20 bright 4 px rims on a dark strip, pitch shrinking from 26 px to 18 px top to bottom.
    pixels = np.full((640, 200, 3), 30, np.uint8)
    centres, y = [], 40.0
    for k in range(20):
        pixels[int(y):int(y) + 4, 40:160] = 230
        centres.append(y + 2)
        y += 26 - 8 * k / 19
    buffer = BytesIO()
    Image.fromarray(pixels).save(buffer, format='PNG')
    pitch = float(np.median(np.diff(centres)))
    columns = [{'column': 1, 'x_min': 40, 'x_max': 160, 'y_first': centres[0], 'y_last': centres[-1],
                'pitch_px': pitch, 'span_count': 20, 'model_boxes': 20}]

    def request(body, **kwargs):
        files = {'image': ('rims.png', buffer.getvalue(), 'image/png')}
        return client.post('/candidate/rim-count', files=files, data={'columns': body}, **kwargs)

    assert request(json.dumps(columns)).status_code == 401
    assert request('not json', headers=headers).status_code == 422
    assert request(json.dumps(columns * 51), headers=headers).status_code == 422
    response = request(json.dumps(columns), headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body['image'] == {'width': 200, 'height': 640}
    result = body['columns'][0]
    assert result['rim_count'] == 20 and result['agrees_with_span'] is True
    assert len(result['peaks_y']) == 20 and result['perspective_gradient'] > 1.2
    assert 'verified' not in result or result['verified'] is False
