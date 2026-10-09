import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { buildBlock, spanColumns } from '../dist/index.js';

const column = (x, layers, {pitch = 40, duplicateAt = null, width = 80} = {}) => {
  const boxes = Array.from({length: layers}, (_, k) => ({class: 'egg_tray', confidence: .9, x, y: 100 + k * pitch, width, height: 36}));
  if (duplicateAt !== null) boxes.push({class: 'egg_tray', confidence: .8, x: x + 2, y: 100 + duplicateAt * pitch + 3, width: width - 2, height: 36});
  return boxes;
};

test('span count removes duplicate boxes and splits columns by x', () => {
  const cols = spanColumns([...column(100, 20, {duplicateAt: 7}), ...column(300, 18), ...column(500, 2)]);
  assert.deepEqual(cols.map(c => [c.model_boxes, c.span_count, c.duplicate_boxes]), [[21, 20, 1], [18, 18, 0]]);
});

test('block from three faces keeps observed and computed trays separate', () => {
  const face = n => spanColumns(Array.from({length: n}, (_, i) => column(100 + i * 100, 20)).flat());
  const block = buildBlock(face(5), face(4), face(4));
  assert.equal(block.width, 5); assert.equal(block.depth, 4);
  assert.equal(block.cells.filter(c => c.status === 'observed').length, 11);
  assert.equal(block.observed_trays, 220); assert.equal(block.computed_trays, 180);
  assert.equal(block.total_trays, 400); assert.equal(block.faces_consistent, true); assert.equal(block.fully_observed, false);
});

test('recessed front column becomes missing and the stack behind is observed', () => {
  const straight = spanColumns([...column(100, 20), ...column(200, 18, {pitch: 30, width: 60}), ...column(300, 20)]);
  const side = spanColumns([...column(100, 20), ...column(200, 20)]);
  const block = buildBlock(straight, side, []);
  const by = Object.fromEntries(block.cells.map(c => [`${c.x},${c.y}`, c]));
  assert.equal(by['1,0'].status, 'missing'); assert.equal(by['1,1'].status, 'observed'); assert.equal(by['1,1'].layers, 18);
  assert.equal(block.total_trays, 4 * 20 + 18);
});

test('left/right depth disagreement and corner conflict withhold the total', () => {
  const face = (n, layers = 20) => spanColumns(Array.from({length: n}, (_, i) => column(100 + i * 100, layers)).flat());
  assert.equal(buildBlock(face(5), face(4), face(3)).total_trays, null);
  const conflict = buildBlock(face(2), spanColumns([...column(100, 20), ...column(200, 17)]), []);
  assert.ok(conflict.conflicts.some(c => String(c.reason).includes('corner')));
  assert.equal(conflict.total_trays, null);
});

test('model path returns a block contract with a computed total for a one-stack scene', async t => {
  t.mock.method(console, 'log', () => {});
  t.mock.method(globalThis, 'fetch', async () => Response.json({predictions: column(100, 20)}));
  const form = new FormData();
  form.set('scan_contract', 'model_spatial_v1');
  ['left', 'right', 'straight'].forEach((view, i) => form.set(view,
    new File([new Uint8Array([255, 216, 255, i])], `${view}.jpg`, {type: 'image/jpeg'})));
  const response = await worker.fetch(new Request('https://local/v1/scans/count', {method: 'POST', body: form}),
    {MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only'});
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.block.contract, 'block_model_v1');
  assert.deepEqual([result.block.width, result.block.depth, result.block.total_trays, result.block.total_eggs], [1, 1, 20, 600]);
  assert.equal(result.block.fully_observed, true);
  assert.equal(result.total_trays, null);   // legacy top-level field unchanged for the installed APK
  assert.equal(result.views.straight.stack_columns[0].span_count, 20);
});

test('one inflated-pitch column does not recess the rest; front-group median is the reference', () => {
  const straight = spanColumns([...column(100, 20), ...column(200, 20), ...column(300, 20), ...column(400, 20, {pitch: 60, width: 120})]);
  const block = buildBlock(straight, spanColumns(column(100, 20)), []);
  assert.deepEqual(block.cells.slice(0, 3).map(c => c.status), ['observed', 'observed', 'observed']);
  assert.equal(block.total_trays, 80);
});

test('recessed stack with no room behind is a conflict, not a silent loss', () => {
  const straight = spanColumns([...column(100, 20), ...column(200, 18, {pitch: 30, width: 60}), ...column(300, 20)]);
  const block = buildBlock(straight, spanColumns(column(100, 20)), []);   // faces say depth 1
  assert.equal(block.total_trays, null);
  assert.ok(block.conflicts.some(c => String(c.reason).includes('no room')));
});

test('corner set back on one face only is a conflict', () => {
  const straight = spanColumns([...column(100, 18, {pitch: 25, width: 50}), ...column(200, 20), ...column(300, 20)]);
  const left = spanColumns([...column(100, 20), ...column(200, 20)]);
  const block = buildBlock(straight, left, []);
  assert.ok(block.conflicts.some(c => String(c.reason).includes('set back on one face only')));
  assert.equal(block.total_trays, null);
});

test('a stack one face sees but another calls missing is a conflict', () => {
  const straight = spanColumns([...column(100, 20), ...column(200, 18, {pitch: 30, width: 60})]);
  const right = spanColumns([...column(100, 20), ...column(200, 16, {pitch: 30, width: 60})]);
  const block = buildBlock(straight, [], right);
  assert.equal(block.total_trays, null);
  assert.ok(block.conflicts.some(c => String(c.reason).includes('disagree')));
});

test('two faces promoting the same height agree; different heights conflict', () => {
  const straight = spanColumns([...column(100, 20), ...column(200, 18, {pitch: 30, width: 60}), ...column(300, 20)]);
  const agree = buildBlock(straight, spanColumns([...column(100, 18, {pitch: 30, width: 60}), ...column(200, 20)]), []);
  const byA = Object.fromEntries(agree.cells.map(c => [`${c.x},${c.y}`, c]));
  assert.equal(byA['1,1'].status, 'observed'); assert.equal(byA['1,1'].layers, 18); assert.equal(agree.total_trays, 40 + 18 + 20);
  const differ = buildBlock(straight, spanColumns([...column(100, 16, {pitch: 30, width: 60}), ...column(200, 20)]), []);
  const byD = Object.fromEntries(differ.cells.map(c => [`${c.x},${c.y}`, c]));
  assert.equal(byD['1,1'].status, 'conflict'); assert.equal(differ.total_trays, null);
});

test('exact half spans round half-to-even like the Python reference', () => {
  // first box at y=100, last at y=100 + 18.5 pitches -> Python round(18.5)=18 -> 19 layers
  const boxes = Array.from({length: 19}, (_, k) => ({class: 'egg_tray', confidence: .9, x: 100, y: 100 + k * 40, width: 80, height: 36}));
  boxes[18].y = 100 + 18.5 * 40;
  assert.equal(spanColumns(boxes)[0].span_count, 19);
  const typical = buildBlock(spanColumns([...column(100, 19), ...column(200, 20)]), spanColumns([...column(100, 20), ...column(200, 19)]), []).typical_layers;
  assert.equal(typical, 20);   // median 19.5 -> 20
});

test('walk count fixes the perspective rounding and merges duplicates', () => {
  let y = 100, gap = 28; const boxes = [{class: 'egg_tray', confidence: .9, x: 100, y, width: 80, height: 24}];
  for (let k = 0; k < 19; k++) { y += gap; gap -= 12 / 19; boxes.push({class: 'egg_tray', confidence: .9, x: 100, y, width: 80, height: 24}); }
  boxes.push({class: 'egg_tray', confidence: .8, x: 102, y: boxes[7].y + 3, width: 78, height: 24});   // duplicate
  const col = spanColumns(boxes)[0];
  assert.equal(col.walk_count, 20);
  assert.ok(col.perspective_gradient > 1.4);
  assert.notEqual(col.span_count, 20);
});

test('steep perspective marks the stack for rescan even when the counts agree', () => {
  let y = 100, gap = 40; const boxes = [{class: 'egg_tray', confidence: .9, x: 100, y, width: 80, height: 30}];
  for (let k = 0; k < 19; k++) { y += gap; gap -= 24 / 19; boxes.push({class: 'egg_tray', confidence: .9, x: 100, y, width: 80, height: 30}); }
  const block = buildBlock(spanColumns(boxes), spanColumns(column(100, 20)), []);
  assert.ok(block.rescan_cells.length >= 1);
  assert.equal(block.total_trays, null);
  assert.ok(block.conflicts.some(c => String(c.reason).includes('hold the phone level')));
});

test('a side face corner shot from above reports its own reason', () => {
  let yy = 100, gap = 50; const boxes = [{class: 'egg_tray', confidence: .9, x: 100, y: yy, width: 80, height: 30}];
  for (let k = 0; k < 19; k++) { yy += gap; gap -= 30 / 19; boxes.push({class: 'egg_tray', confidence: .9, x: 100, y: yy, width: 80, height: 30}); }
  const block = buildBlock(spanColumns([...column(100, 20), ...column(200, 20)]), [], spanColumns(boxes));
  assert.ok(block.conflicts.some(c => String(c.reason).startsWith('RIGHT') && String(c.reason).includes('hold the phone level')));
  assert.equal(block.total_trays, null);
});
