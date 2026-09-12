import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { fuseCells, readCellIds } from '../dist/index.js';

const observations = (left, right, straight) => Object.fromEntries(
  Object.entries({ left, right, straight }).map(([view, count]) => [view, { count, confidence: .9 }]),
);

test('health advertises the cell contract without invoking inference', async () => {
  const health = await (await worker.fetch(new Request('https://local/health'), {})).json();
  assert.deepEqual(health, { status: 'ok', scan_contract: 'cell_identity_v1' });
});

test('40/40/100 belong to separate cells, never compare or sum them', () => {
  const cells = fuseCells(observations(40, 40, 100), { left: 'W1-A', right: 'W1-B', straight: 'W1-C' });
  assert.equal(cells.length, 3);
  assert.ok(cells.every(c => !c.accepted && c.final_count === null));
  assert.deepEqual(cells.map(c => c.counts), [{ left: 40 }, { right: 40 }, { straight: 100 }]);
});

test('same-cell agreement cannot certify another cell with one observation', () => {
  const [a, b] = fuseCells(observations(40, 40, 100), { left: 'A', right: 'A', straight: 'B' });
  assert.equal(a.final_count, 40);
  assert.equal(b.final_count, null);
  assert.match(b.reason, /at least two/);
});

test('same cell: mismatch, zero, low/missing confidence all require recount', () => {
  const ids = { left: 'A', right: 'A', straight: 'A' };
  assert.equal(fuseCells(observations(40, 40, 100), ids)[0].accepted, false);
  assert.equal(fuseCells(observations(40, 40, 0), ids)[0].accepted, false);
  for (const confidence of [.79, NaN, undefined, 1.1]) {
    const data = observations(40, 40, 40);
    data.left.confidence = confidence;
    assert.equal(fuseCells(data, ids)[0].accepted, false);
  }
  assert.equal(fuseCells(observations(40, 40, 40), ids)[0].final_count, 40);
});

test('cell identity is mandatory, normalized and bounded', () => {
  const form = new FormData();
  assert.throws(() => readCellIds(form), /painted cell/);
  for (const view of ['left', 'right', 'straight']) form.set(`${view}_cell_id`, ' w1-a2 ');
  assert.deepEqual(readCellIds(form), { left: 'W1-A2', right: 'W1-A2', straight: 'W1-A2' });
  for (const bad of ['A'.repeat(33), '<A>', '__proto__', 'A/B', '']) {
    form.set('left_cell_id', bad);
    assert.throws(() => readCellIds(form), /painted cell/);
  }
});

test('HTTP rejects legacy metadata and duplicate photos before inference; partial cells never get a total', async t => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    calls++;
    return Response.json({ predictions: Array.from({ length: 40 }, () => ({ class: 'egg_tray', confidence: .9 })) });
  });
  const env = { MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', MAX_VIEW_COUNT_RATIO: '1.25', EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only' };
  const request = (ids, duplicate = false) => {
    const form = new FormData();
    ['left', 'right', 'straight'].forEach((view, i) => {
      form.set(view, new File([new Uint8Array([255, 216, 255, duplicate ? 0 : i])], `${view}.jpg`, { type: 'image/jpeg' }));
      if (ids) form.set(`${view}_cell_id`, ids[i]);
    });
    return new Request('https://local/v1/scans/count', { method: 'POST', body: form });
  };
  assert.equal((await worker.fetch(request(null), env)).status, 422);
  assert.equal((await worker.fetch(request(['A','A','A'], true), env)).status, 422);
  assert.equal(calls, 0);
  const partial = await (await worker.fetch(request(['A','A','B']), env)).json();
  assert.equal(partial.status, 'manual_recount_required');
  assert.equal(partial.total_trays, null);
  assert.equal(partial.total_eggs, null);
  assert.equal(partial.processing.mode, 'cell_identity_v1');
  assert.deepEqual(partial.cell_ids, { left: 'A', right: 'A', straight: 'B' });
  assert.equal(partial.views.straight.accepted, false);
  const verified = await (await worker.fetch(request(['A','A','A']), env)).json();
  assert.equal(verified.total_trays, 40);
  assert.equal(verified.total_eggs, 1200);
  assert.equal(verified.physical_cell_count, 1);
});
