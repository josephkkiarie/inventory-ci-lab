import pytest
from app.main import app

@pytest.fixture
def client():
    app.config.update(TESTING=True)
    with app.test_client() as client:
        yield client

def test_health(client):
    response = client.get('/health')
    assert response.status_code == 200
    assert response.get_json()['status'] == 'ok'

def test_items(client):
    response = client.get('/api/items')
    assert response.status_code == 200
    assert len(response.get_json()['items']) == 2

def test_item_not_found(client):
    response = client.get('/api/items/999')
    assert response.status_code == 404
    assert response.get_json()['error'] == 'item not found'


@pytest.mark.parametrize(
    ('threshold', 'names'),
    [(0, []), (3, []), (4, ['switch']), (8, ['switch']),
     (9, ['router', 'switch']), (100, ['router', 'switch'])],
)
def test_low_stock_filters_strictly_below_threshold(client, threshold, names):
    response = client.get(f'/api/items/low-stock?threshold={threshold}')
    assert response.status_code == 200
    assert [item['name'] for item in response.get_json()['items']] == names


@pytest.mark.parametrize(
    'query',
    ['', '?threshold=-1', '?threshold=101', '?threshold=abc',
     '?threshold=3.5', '?threshold=+3', '?threshold=4&threshold=8'],
)
def test_low_stock_rejects_invalid_threshold(client, query):
    response = client.get(f'/api/items/low-stock{query}')
    assert response.status_code == 400
    assert 'threshold' in response.get_json()['error']
