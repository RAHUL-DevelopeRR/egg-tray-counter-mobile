import assert from 'node:assert/strict';
import test from 'node:test';
import worker from '../dist/index.js';

const column = (x, layers, pitch = 40) => Array.from({length: layers}, (_, k) => ({class: 'egg_tray', confidence: .9, x, y: 100 + k * pitch, width: 500, height: 36}));
const scan = async (t, env, rimReply) => {
  t.mock.method(console, 'log', () => {});
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url) => {
    calls.push(String(url));
    if (String(url).includes('rim-count')) return rimReply();
    return Response.json({predictions: column(400, 20), image: {width: 800, height: 1000}});
  });
  const form = new FormData();
  form.set('scan_contract', 'model_spatial_v1');
  ['left', 'right', 'straight'].forEach((view, i) => form.set(view, new File([new Uint8Array([255, 216, 255, i])], `${view}.jpg`, {type: 'image/jpeg'})));
  const response = await worker.fetch(new Request('https://local/v1/scans/count', {method: 'POST', body: form}), env);
  return {result: await response.json(), calls};
};
const base = {MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only',
  VISION_SERVICE_URL: 'https://lambda.example', VISION_SERVICE_TOKEN: 'x'.repeat(40)};

test('rim verification disabled: no service call, counts stand', async t => {
  const {result, calls} = await scan(t, base, () => { throw new Error('must not be called'); });
  assert.equal(result.block.total_trays, 20);
  assert.equal(result.block.verification.views.straight, 'disabled');
  assert.ok(calls.every(u => !u.includes('rim-count')));
});

test('agreeing rim count keeps the total; a confident disagreement forces a rescan with a reason', async t => {
  const agree = await scan(t, {...base, RIM_VERIFY: 'true'}, () => Response.json({columns: [{column: 1, rim_count: 20, confidence: .9}]}));
  assert.equal(agree.result.block.total_trays, 20);
  assert.equal(agree.result.block.verification.views.straight, 'ok');
  assert.equal(agree.result.views.straight.stack_columns[0].rim_count, 20);
  const differ = await scan(t, {...base, RIM_VERIFY: 'true'}, () => Response.json({columns: [{column: 1, rim_count: 19, confidence: .9}]}));
  assert.equal(differ.result.block.total_trays, null);
  assert.ok(differ.result.block.conflicts.some(c => String(c.reason).includes('rim edges count 19')));
  const unsure = await scan(t, {...base, RIM_VERIFY: 'true'}, () => Response.json({columns: [{column: 1, rim_count: 19, confidence: .2}]}));
  assert.equal(unsure.result.block.total_trays, 20);
});

test('rim service failure never blocks the scan', async t => {
  const {result} = await scan(t, {...base, RIM_VERIFY: 'true'}, () => new Response('boom', {status: 500}));
  assert.equal(result.block.total_trays, 20);
  assert.equal(result.block.verification.views.straight, 'unavailable_500');
});
