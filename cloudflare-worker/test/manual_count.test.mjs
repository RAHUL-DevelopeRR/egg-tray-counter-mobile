import assert from 'node:assert/strict';
import test from 'node:test';
import worker from '../dist/index.js';

const SCAN = '8a1b2c3d-1111-4222-8333-444455556666';
const env = (archive) => ({MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only', SCAN_ARCHIVE: archive});
const post = (body, e, id = SCAN) => worker.fetch(new Request(`https://local/v1/scans/${id}/manual-count`, {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify(body)}), e);
const valid = {block_id: 'B01', notes: 'front row counted twice', tray: {width_cm: 30, bad: 'x'}, app_version: '0.4.0+11',
  cells: [{x: 0, y: 0, app_layers: 20, app_status: 'observed', filled: 20, empty: 0}, {x: 1, y: 0, app_layers: 20, app_status: 'observed', filled: 19, empty: 1, unreachable: false}, {x: 0, y: 1, app_layers: 20, app_status: 'computed', filled: 0, empty: 0, unreachable: true}]};

test('manual count is validated and archived next to the scan with totals', async t => {
  t.mock.method(console, 'log', () => {});
  const stored = [];
  const response = await post(valid, env({put: async (key, body, options) => stored.push({key, body: JSON.parse(body), options})}));
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.stored, true);
  assert.ok(result.key.startsWith(`scans/${SCAN}/manual-count/`));
  assert.deepEqual(result.totals, {filled: 39, empty: 1, unreachable: 1});
  assert.equal(stored.length, 2);
  assert.equal(stored[1].key, `scans/${SCAN}/manual-count/latest.json`);
  assert.equal(result.latest_key, stored[1].key);
  assert.equal(stored[0].body.kind, 'manual_count_v1');
  assert.deepEqual(stored[0].body.tray, {width_cm: 30});
  assert.equal(stored[0].options.customMetadata.block_id, 'B01');
});

test('invalid cells, duplicate cells, bad ids and missing archive are refused', async t => {
  t.mock.method(console, 'log', () => {});
  const archive = {put: async () => { throw new Error('must not store'); }};
  assert.equal((await post({...valid, cells: [{x: 0, y: 0, filled: -1, empty: 0}]}, env(archive))).status, 422);
  assert.equal((await post({...valid, cells: [valid.cells[0], valid.cells[0]]}, env(archive))).status, 422);
  assert.equal((await post({...valid, block_id: ''}, env(archive))).status, 422);
  assert.equal((await post(valid, env(archive), 'not-a-uuid')).status, 422);
  assert.equal((await post(valid, env(undefined))).status, 503);
});

test('archive listing returns key names for one scan only', async t => {
  t.mock.method(console, 'log', () => {});
  const archive = {put: async () => {}, list: async ({prefix}) => ({objects: [
    {key: `${prefix}straight/abc`, size: 10, uploaded: new Date(0)}, {key: `${prefix}manual-count/latest.json`, size: 5, uploaded: new Date(0)}]})};
  const response = await worker.fetch(new Request(`https://local/v1/scans/${SCAN}/archive`), env(archive));
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(body.keys.map(k => k.key), [`scans/${SCAN}/straight/abc`, `scans/${SCAN}/manual-count/latest.json`]);
  assert.equal((await worker.fetch(new Request('https://local/v1/scans/not-a-uuid/archive'), env(archive))).status, 422);
});
