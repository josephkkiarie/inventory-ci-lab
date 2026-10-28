import os
import re
from flask import Flask, jsonify, request

app = Flask(__name__)
ITEMS = (
    {'id': 1, 'name': 'router', 'stock': 8},
    {'id': 2, 'name': 'switch', 'stock': 3},
)

@app.get('/')
def index():
    return jsonify(service='inventory-api', version=os.getenv('APP_VERSION', 'dev'), status='running')

@app.get('/health')
def health():
    return jsonify(status='ok'), 200

@app.get('/api/items')
def items():
    # Lab dataset: in a real system this would be backed by a database.
    return jsonify(items=ITEMS)


@app.get('/api/items/low-stock')
def low_stock():
    values = request.args.getlist('threshold')
    if len(values) != 1 or re.fullmatch(r'[0-9]+', values[0]) is None:
        return jsonify(error='threshold must be an integer from 0 to 100'), 400

    threshold = int(values[0])
    if threshold > 100:
        return jsonify(error='threshold must be an integer from 0 to 100'), 400
    return jsonify(items=[item for item in ITEMS if item['stock'] < threshold]), 200

@app.get('/api/items/<int:item_id>')
def item_detail(item_id):
    item = next((item for item in ITEMS if item['id'] == item_id), None)
    if item is None:
        return jsonify(error='item not found'), 404
    return jsonify(item), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
