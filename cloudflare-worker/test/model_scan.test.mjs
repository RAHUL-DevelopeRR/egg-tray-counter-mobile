import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { readOptionalCellIds } from '../dist/index.js';

test('optional markers do not invent physical identity', () => {
  const form = new FormData();
  assert.deepEqual(readOptionalCellIds(form), {});
  form.set('left_cell_id', ' a1 ');
  assert.deepEqual(readOptionalCellIds(form), {left: 'A1'});
  form.set('right_cell_id', '<invalid>');
  assert.throws(() => readOptionalCellIds(form));
});

test('model path accepts no markers, retains boxes and never certifies photo agreement', async t => {
  const box = {class: 'egg_tray', confidence: .9, x: 100, y: 120, width: 40, height: 20};
  t.mock.method(globalThis, 'fetch', async () => Response.json({predictions: [box]}));
  const form = new FormData();
  form.set('scan_contract', 'model_spatial_v1');
  ['left', 'right', 'straight'].forEach((view, i) => form.set(view,
    new File([new Uint8Array([255, 216, 255, i])], `${view}.jpg`, {type:'image/jpeg'})));
  const response = await worker.fetch(new Request('https://local/v1/scans/count', {method:'POST', body:form}),
    {MODEL_ID:'projec-mutta/2', CONFIDENCE:'35', OVERLAP:'50', EGGS_PER_TRAY:'30', ROBOFLOW_API_KEY:'test-only'});
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.processing.mode, 'model_spatial_v1');
  assert.deepEqual(result.cell_ids, {});
  assert.deepEqual(result.views.left.detections, [box]);
  assert.equal(result.accepted, false);
  assert.equal(result.total_trays, null);
  assert.equal(result.total_eggs, null);
  assert.deepEqual(result.stacks[0].counts, {left:1, right:1, straight:1});
});
