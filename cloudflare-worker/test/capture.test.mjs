import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { captureQuality, spanColumns } from '../dist/index.js';

// Synthetic faces: `layers` boxes per column, adjacent columns 100 px apart and 100 px wide, so four
// columns cover 400 px of an 800 px frame (coverage 0.5), five cover 0.625, and 20 layers at pitch 40
// span 800 px of a 1000 px frame (height 0.8).
const column = (x, layers, {pitch = 40, width = 100, y0 = 100} = {}) =>
  Array.from({length: layers}, (_, k) => ({class: 'egg_tray', confidence: .9, x, y: y0 + k * pitch, width, height: Math.round(pitch * .9)}));
const face = (pitches, opts = {}) => spanColumns(pitches.map((pitch, i) => column(100 + i * 100, 20, {...opts, pitch})).flat());
const FRAME = {width: 800, height: 1000};
const env = {MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only'};

test('frontal fill-frame face is accepted with its metrics', () => {
  const quality = captureQuality(face([40, 40, 40, 40, 40]), FRAME.width, FRAME.height);
  assert.equal(quality.accepted, true);
  assert.deepEqual(quality.reasons, []);
  assert.equal(quality.metrics.columns, 5);
  assert.equal(quality.metrics.model_boxes, 100);
  assert.equal(quality.metrics.pitch_gradient, 1);
  assert.equal(quality.metrics.coverage_x, .625);
  assert.equal(quality.metrics.height_frac, .8);
  assert.equal(quality.metrics.pitch_frac, .04);
  assert.equal(quality.metrics.recessed_columns, 0);
  assert.deepEqual(quality.metrics.image, FRAME);
});

test('distant face with a tiny pitch is rejected; the same columns pass when the image size is unknown', () => {
  // 20 layers at 8 px pitch span 160 px of a 1000 px frame; 5 narrow columns cover 100 px of 900.
  const tiny = spanColumns([0, 1, 2, 3, 4].map(i => column(100 + i * 25, 20, {pitch: 8, width: 20})).flat());
  assert.equal(tiny.length, 5);
  const quality = captureQuality(tiny, FRAME.width, FRAME.height);
  assert.equal(quality.accepted, false);
  assert.ok(quality.reasons.includes('stacks are too small in the frame (too far away)'));
  assert.ok(quality.reasons.includes('stacks cover too little of the frame width'));
  assert.ok(quality.metrics.pitch_frac < .01);
  assert.ok(quality.metrics.height_frac < .4);
  // Without the image size the pitch gradient is the only usable signal, and it is flat here.
  const unsized = captureQuality(tiny, null, null);
  assert.equal(unsized.accepted, true);
  assert.equal(unsized.metrics.coverage_x, null);
  assert.equal(unsized.metrics.height_frac, null);
  assert.equal(unsized.metrics.image, null);
});

test('angled face with a pitch gradient across the columns is rejected for that reason only', () => {
  const quality = captureQuality(face([50, 44, 38, 32, 26]), FRAME.width, 1200);
  assert.equal(quality.accepted, false);
  assert.deepEqual(quality.reasons, ['layer pitch changes across the face (angled or corner view)']);
  assert.ok(quality.metrics.pitch_gradient > 1.2);
  assert.equal(quality.metrics.recessed_columns, 2);
});

test('one column set back one position is allowed; a lone column far below the front pitch is not', () => {
  const recessedEnd = captureQuality(face([40, 40, 40, 40, 32]), FRAME.width, FRAME.height);   // scale 0.8 >= floor 0.6
  assert.equal(recessedEnd.accepted, true);
  assert.equal(recessedEnd.metrics.recessed_columns, 1);
  assert.equal(recessedEnd.metrics.pitch_gradient, 1);
  const steep = captureQuality(face([40, 18]), FRAME.width, FRAME.height);                      // scale 0.45 < floor
  assert.equal(steep.accepted, false);
  assert.ok(steep.reasons[0].includes('angled'));
});

test('zero detections never throw and are rejected as no stacks detected', () => {
  for (const [w, h] of [[null, null], [FRAME.width, FRAME.height], [0, -1]]) {
    const quality = captureQuality(spanColumns([]), w, h);
    assert.equal(quality.accepted, false);
    assert.deepEqual(quality.reasons, ['no stacks detected']);
    assert.equal(quality.metrics.columns, 0);
    assert.equal(quality.metrics.pitch_gradient, null);
  }
  assert.deepEqual(captureQuality([], null, null).reasons, ['no stacks detected']);
});

async function scan(t, perView) {
  t.mock.method(console, 'log', () => {});
  const calls = [];
  t.mock.method(globalThis, 'fetch', async () => {
    const view = ['left', 'right', 'straight'][calls.length];   // Worker infers views in this order
    calls.push(view);
    return Response.json(perView[view]);
  });
  const form = new FormData();
  form.set('scan_contract', 'model_spatial_v1');
  ['left', 'right', 'straight'].forEach((view, i) => form.set(view,
    new File([new Uint8Array([255, 216, 255, i])], `${view}.jpg`, {type: 'image/jpeg'})));
  const response = await worker.fetch(new Request('https://local/v1/scans/count', {method: 'POST', body: form}), env);
  assert.equal(response.status, 200);
  assert.deepEqual(calls, ['left', 'right', 'straight']);
  return response.json();
}

test('a view that fails the capture gate withholds the block total and names that view for rescan', async t => {
  const good = n => ({image: FRAME, predictions: Array.from({length: n}, (_, i) => column(100 + i * 100, 20)).flat()});
  const result = await scan(t, {left: good(4), right: {image: FRAME, predictions: []}, straight: good(5)});
  assert.equal(result.block.contract, 'block_model_v1');
  assert.equal(result.block.total_trays, null);
  assert.equal(result.block.total_eggs, null);
  assert.equal(result.block.faces_consistent, false);
  assert.equal(result.block.fully_observed, false);
  assert.equal(result.block.observed_trays, 160);           // 5 front + 3 LEFT-side cells x 20: geometry is still reported, only the total is withheld
  assert.equal(result.block.capture.right.accepted, false);
  assert.deepEqual(result.block.capture.right.reasons, ['no stacks detected']);
  assert.equal(result.block.capture.left.accepted, true);
  assert.equal(result.block.capture.straight.accepted, true);
  assert.ok(result.block.capture.straight.metrics.coverage_x >= .45);
  assert.deepEqual(result.block.capture.straight.metrics.image, FRAME);
  assert.deepEqual(result.views.straight.image, FRAME);
  assert.equal(result.rescan.recommended_view, 'right');
  assert.match(result.rescan.reason, /^Step closer and face the block squarely; the whole face must fill the frame \(RIGHT: no stacks detected\)$/);
  assert.equal(result.total_trays, null);                   // legacy top-level field unchanged for the installed APK
  assert.equal(result.accepted, false);
});

test('when every view passes the gate the block total and the generic rescan advice are unchanged', async t => {
  const good = n => ({image: FRAME, predictions: Array.from({length: n}, (_, i) => column(100 + i * 100, 20)).flat()});
  const result = await scan(t, {left: good(4), right: good(4), straight: good(5)});
  assert.equal(result.block.total_trays, 400);
  assert.equal(result.block.faces_consistent, true);
  assert.ok(['left', 'right', 'straight'].every(v => result.block.capture[v].accepted));
  assert.equal(result.rescan.recommended_view, 'straight');
  assert.ok(!result.rescan.reason.startsWith('Step closer'));
  assert.equal(result.total_trays, null);
});

test('a single stack filling the frame height is accepted although it cannot fill the width', () => {
  // one 20-layer column, 240 px wide in a 960x1280 portrait frame: coverage 0.25, height 0.66
  const boxes = Array.from({length: 20}, (_, k) => ({class: 'egg_tray', confidence: .9, x: 480, y: 200 + k * 40, width: 240, height: 36}));
  const quality = captureQuality(spanColumns(boxes), 960, 1280);
  assert.equal(quality.accepted, true, JSON.stringify(quality));
  // the same stack far away (12% of the height) is still rejected
  const far = boxes.map(b => ({...b, y: 600 + (b.y - 200) * 0.18, width: 50, height: 7}));
  assert.equal(captureQuality(spanColumns(far), 960, 1280).accepted, false);
});

test('a narrow face that fills the frame height passes in a wide landscape frame', () => {
  // Two 20-layer stacks, 240 px wide, in a 1920x864 landscape still: coverage 0.25, height 0.9.
  const two = spanColumns([0, 1].map(i => column(840 + i * 240, 20, {pitch: 38, width: 230, y0: 60})).flat());
  const wide = captureQuality(two, 1920, 864, 6);
  assert.equal(wide.accepted, true, JSON.stringify(wide));
  assert.ok(wide.metrics.coverage_x < .45);
  assert.ok(wide.metrics.height_frac >= .8);
  assert.equal(wide.metrics.box_aspect, 6);
  // The same stacks small in the frame are still refused for coverage and distance.
  const small = spanColumns([0, 1].map(i => column(900 + i * 120, 20, {pitch: 15, width: 115, y0: 200})).flat());
  const far = captureQuality(small, 1920, 864, 6);
  assert.equal(far.accepted, false);
  assert.ok(far.reasons.includes('stacks cover too little of the frame width'));
});

test('square boxes from a sideways photo refuse the face before anything is counted', () => {
  const quality = captureQuality(face([40, 40, 40, 40, 40]), FRAME.width, FRAME.height, 1.6);
  assert.equal(quality.accepted, false);
  assert.match(quality.reasons[0], /sideways/);
  assert.equal(quality.metrics.box_aspect, 1.6);
  const none = captureQuality([], FRAME.width, FRAME.height, 1.2);
  assert.deepEqual(none.reasons.length, 2);
  assert.match(none.reasons[0], /sideways/);
  // Tray-shaped boxes, or no size information, leave the verdict unchanged.
  assert.equal(captureQuality(face([40, 40, 40, 40, 40]), FRAME.width, FRAME.height, 5.8).accepted, true);
  assert.equal(captureQuality(face([40, 40, 40, 40, 40]), FRAME.width, FRAME.height).accepted, true);
});
