import pytest
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
