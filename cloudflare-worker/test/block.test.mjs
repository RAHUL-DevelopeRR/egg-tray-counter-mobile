import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { buildBlock, spanColumns, walkLayers } from '../dist/index.js';

const column = (x, layers, {pitch = 40, duplicateAt = null, width = 80, height = 36} = {}) => {
  const boxes = Array.from({length: layers}, (_, k) => ({class: 'egg_tray', confidence: .9, x, y: 100 + k * pitch, width, height}));
  if (duplicateAt !== null) boxes.push({class: 'egg_tray', confidence: .8, x: x + 2, y: 100 + duplicateAt * pitch + 3, width: width - 2, height: 36});
  return boxes;
};

// Real tray boxes are about six times wider than tall (the capture gate refuses square ones as sideways) and about as
// tall as the layer spacing (the block model refuses boxes much shorter than it).
const trayShaped = boxes => boxes.map(b => ({...b, width: b.height * 6}));

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

test('recessed front column becomes missing; the trays seen behind it are a hint, never a reading (0.6.0)', () => {
  const straight = spanColumns([...column(100, 20), ...column(200, 18, {pitch: 30, width: 60}), ...column(300, 20)]);
  const side = spanColumns([...column(100, 20), ...column(200, 20)]);
  const block = buildBlock(straight, side, []);
  const by = Object.fromEntries(block.cells.map(c => [`${c.x},${c.y}`, c]));
  assert.equal(by['1,0'].status, 'missing');
  // The stack behind the gap stays hidden: assumed from its one measured neighbour (LEFT's 20), its range open to 0.
  assert.deepEqual([by['1,1'].status, by['1,1'].layers, by['1,1'].past_gap_layers, by['1,1'].past_gap_scale], ['computed', 20, 18, 0.75]);
  assert.deepEqual([by['1,1'].assumed_range, by['1,1'].flags], [[0, 20], ['line_of_sight_past_gap', 'single_neighbour']]);
  assert.equal(block.total_trays, 5 * 20);
});

test('left/right depth disagreement and corner conflict withhold the total', () => {
  const face = (n, layers = 20) => spanColumns(Array.from({length: n}, (_, i) => column(100 + i * 100, layers)).flat());
  assert.equal(buildBlock(face(5), face(4), face(3)).total_trays, null);
  const conflict = buildBlock(face(2), spanColumns([...column(100, 20), ...column(200, 17)]), []);
  assert.ok(conflict.conflicts.some(c => String(c.reason).includes('corner')));
  assert.equal(conflict.total_trays, null);
});

// Three different camera captures of one stack, each with its own framing (copies of one photo would be one capture).
const oneStackScan = async (t, capture) => {
  t.mock.method(console, 'log', () => {});
  let call = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    const shift = 120 * call++;
    return Response.json({predictions: trayShaped(column(250 + shift, 20, {pitch: 40})).map(b => ({...b, y: b.y + shift / 6})),
      image: {width: 800, height: 1000}});
  });
  const form = new FormData();
  form.set('scan_contract', 'model_spatial_v1');
  ['left', 'right', 'straight'].forEach((view, i) => form.set(view,
    new File([new Uint8Array([255, 216, 255, i])], `${view}.jpg`, {type: 'image/jpeg'})));
  const yaw = {straight: 0, left: -90, right: 90};
  if (capture) for (const view of ['left', 'right', 'straight']) form.set(`${view}_capture`,
    JSON.stringify({source: capture, blocked: false, yaw_deg: yaw[view], yaw_session: 'walk1'}));
  const response = await worker.fetch(new Request('https://local/v1/scans/count', {method: 'POST', body: form}),
    {MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only'});
  assert.equal(response.status, 200);
  return response.json();
};

test('model path returns a block contract with a computed total for a one-stack scene', async t => {
  const result = await oneStackScan(t, 'captured_still');
  assert.equal(result.block.contract, 'block_model_v1');
  assert.deepEqual([result.block.width, result.block.depth, result.block.total_trays, result.block.total_eggs], [1, 1, 20, 600]);
  assert.equal(result.block.fully_observed, true);
  assert.equal(result.block.status, 'exact'); assert.equal(result.result_status, 'exact');
  assert.equal(result.block.eggs_basis, 'capacity_if_every_tray_full');
  assert.equal(result.total_trays, null);   // legacy top-level field unchanged for the installed APK
  assert.equal(result.accepted, false);
  assert.equal(result.views.straight.stack_columns[0].span_count, 20);
  assert.deepEqual(['straight', 'left', 'right'].map(v => [result.views[v].capture_source, result.views[v].trusted]),
    [['captured_still', true], ['captured_still', true], ['captured_still', true]]);
});

test('only guided camera captures verify a stack: gallery photos or no provenance give an estimate, never exact', async t => {
  for (const capture of ['uploaded_photo', null]) {
    const result = await oneStackScan(t, capture);
    assert.equal(result.block.total_trays, 20, String(capture));
    assert.equal(result.block.status, 'estimated', String(capture));
    assert.equal(result.views.straight.trusted, false);
  }
});

test('one inflated-pitch column does not recess the rest; front-group median is the reference', () => {
  const straight = spanColumns([...column(100, 20), ...column(200, 20), ...column(300, 20), ...column(400, 20, {pitch: 60, width: 120, height: 54})]);
  const block = buildBlock(straight, spanColumns(column(100, 20)), []);
  assert.deepEqual(block.cells.slice(0, 3).map(c => c.status), ['observed', 'observed', 'observed']);
  assert.equal(block.total_trays, 80);
});

test('trays seen behind a gap with no room for a stack are noted, never counted: an estimate (0.6.0)', () => {
  const straight = spanColumns([...column(100, 20), ...column(200, 18, {pitch: 30, width: 60}), ...column(300, 20)]);
  const block = buildBlock(straight, spanColumns(column(100, 20)), []);   // faces say depth 1
  assert.deepEqual([block.total_trays, block.status], [40, 'estimated']);
  assert.ok(block.ambiguities.some(c => String(c.reason).includes('no room')));
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
  // The shared corner already contradicts itself (set back on STRAIGHT only), which is reported first.
  assert.ok(block.conflicts.some(c => /disagree|set back on one face only/.test(String(c.reason))));
});

test('two faces seeing the same trays through gaps agree on the hint; different heights conflict', () => {
  const straight = spanColumns([...column(100, 20), ...column(200, 18, {pitch: 30, width: 60}), ...column(300, 20)]);
  const agree = buildBlock(straight, spanColumns([...column(100, 18, {pitch: 30, width: 60}), ...column(200, 20)]), []);
  const byA = Object.fromEntries(agree.cells.map(c => [`${c.x},${c.y}`, c]));
  // No measured neighbour in line of sight (both are gaps): the typical face height, 20.
  assert.deepEqual([byA['1,1'].status, byA['1,1'].layers, byA['1,1'].past_gap_layers], ['computed', 20, 18]);
  assert.deepEqual([byA['1,1'].assumed_from, byA['1,1'].flags], ['face_typical', ['line_of_sight_past_gap', 'no_neighbour']]);
  assert.equal(agree.total_trays, 40 + 20 + 20);
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
  assert.equal(typical, 20);   // mode of 19, 20, 20
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

// ---- 2026-10-14 counting fixes: merged face readings, one-layer ambiguity, bounded gap filling, result status.
const tray = (layers, {x = 100, pitch = 40, height = 36, skip = []} = {}) =>
  Array.from({length: layers}, (_, k) => k).filter(k => !skip.includes(k))
    .map(k => ({class: 'egg_tray', confidence: .9, x, y: 100 + k * pitch, width: 80, height}));
const faceOf = (...stacks) => spanColumns(stacks.flatMap((layers, i) => tray(layers, {x: 100 + i * 100})));

test('opposite side faces of a one-wide block are merged, not overwritten', () => {
  const block = buildBlock(faceOf(20), faceOf(18, 20), faceOf(20, 22));   // LEFT front corner is right-most
  assert.equal(block.total_trays, null); assert.equal(block.status, 'conflict'); assert.equal(block.fully_observed, false);
  const rear = block.cells.find(c => c.x === 0 && c.y === 1);
  assert.equal(rear.status, 'conflict'); assert.equal(rear.source, 'left+right');
  const conflict = block.conflicts.find(c => c.cell && c.cell[0] === 0 && c.cell[1] === 1);
  assert.deepEqual([conflict.left_layers, conflict.right_layers], [18, 22]);
  // Stacks stand on one floor: a shorter stack's bottom is level with its neighbours' (its top is lower).
  const onFloor = (...stacks) => spanColumns(stacks.flatMap((layers, i) =>
    tray(20, {x: 100 + i * 100, skip: Array.from({length: 20 - layers}, (_, k) => k)})));
  const agree = buildBlock(faceOf(20), onFloor(18, 20), onFloor(20, 18));
  assert.equal(agree.total_trays, 38); assert.equal(agree.status, 'exact');
});

test('a one-layer corner difference keeps a total but only as an estimate', () => {
  const block = buildBlock(faceOf(20), faceOf(19), []);
  assert.equal(block.total_trays, 20); assert.equal(block.status, 'estimated');
  assert.deepEqual([block.ambiguities[0].straight_layers, block.ambiguities[0].left_layers], [20, 19]);
});

test('gap filling stops at two missed layers; longer runs are reported, not invented', () => {
  assert.deepEqual((({count, filled, unresolved_gaps}) => [count, filled, unresolved_gaps])(walkLayers([0, 40, 80, 4000], 36)), [4, 0, 1]);
  const two = walkLayers(tray(20, {skip: [9, 10]}).map(b => b.y), 36);
  assert.deepEqual([two.count, two.filled, two.unresolved_gaps], [20, 2, 0]);
  const block = buildBlock(spanColumns([...tray(20), ...tray(20, {x: 200, skip: [6, 7, 8, 9, 10]})]), faceOf(20), []);
  assert.equal(block.total_trays, null);
  assert.ok(block.conflicts.some(c => String(c.reason).includes('missing over several layers')));
});

test('filled layers stay in the count and are reported, but a gap-filled stack is never verified', () => {
  const block = buildBlock(spanColumns([...tray(20), ...tray(20, {x: 200, skip: [9]})]), faceOf(20), faceOf(20));
  // The right-hand stack is read 20 by both STRAIGHT and RIGHT, but STRAIGHT filled one of its layers: the cell keeps
  // RIGHT's unfilled reading, and one clean reading does not verify it.
  assert.equal(block.total_trays, 40); assert.equal(block.filled_trays, 0);
  const cell = block.cells.find(c => c.x === 1 && c.y === 0);
  assert.deepEqual(cell.readings.map(r => [r.face, r.layers, r.gap_filled]), [['straight', 20, 1], ['right', 20, 0]]);
  assert.equal(block.status, 'estimated'); assert.deepEqual(block.single_reading_cells, [[1, 0]]);
  assert.deepEqual([block.visible_verified_trays, block.visible_single_reading_trays], [20, 20]);
});

test('boxes on alternate layers only send the face for a retake', () => {
  const sparse = tray(10, {x: 200, pitch: 43, height: 28});
  const block = buildBlock(spanColumns([...tray(20), ...sparse]), faceOf(20), []);
  assert.equal(block.total_trays, null); assert.deepEqual(block.rescan_cells, [[1, 0]]);
  assert.ok(block.conflicts.some(c => String(c.reason).includes('step closer')));
});

test('status separates exact, estimated, conflict and a missing face', () => {
  assert.equal(buildBlock(faceOf(20, 20), faceOf(20), faceOf(20)).status, 'exact');
  // The right-hand stack is seen by STRAIGHT only: one photo's reading is an estimate.
  assert.equal(buildBlock(faceOf(20, 20), faceOf(20), []).status, 'estimated');
  assert.equal(buildBlock(faceOf(20, 20, 20), faceOf(20, 20, 20), faceOf(20, 20, 20)).status, 'estimated');
  assert.equal(buildBlock(faceOf(20, 20), faceOf(20, 20), faceOf(20)).status, 'conflict');
  assert.equal(buildBlock(faceOf(20, 20), [], []).status, 'needs_view');
});
// ---- 2026-11-01 release contract (plan Phase C): exact needs two photos reading every stack the same.
test('a stack read by one photo only keeps the total but is never exact; corners seen twice are verified', () => {
  const block = buildBlock(faceOf(20, 20, 20, 20), faceOf(20), faceOf(20));
  assert.equal(block.total_trays, 80); assert.equal(block.status, 'estimated');
  assert.deepEqual(block.single_reading_cells, [[1, 0], [2, 0]]);
  assert.deepEqual([block.visible_verified_trays, block.visible_single_reading_trays], [40, 40]);
  const corner = block.cells.find(c => c.x === 0 && c.y === 0);
  assert.equal(corner.verified, true);
  assert.deepEqual(corner.readings.map(r => [r.face, r.layers]), [['straight', 20], ['left', 20]]);
  assert.equal(buildBlock(faceOf(20), faceOf(20), faceOf(20)).status, 'exact');   // one stack, three photos
});

test('a box over two trays marks every stack it spans, and that reading cannot verify a corner (img-30)', () => {
  // Stack 1's top box is as wide as two stacks: it covers stack 2's top tray, so stack 2 reads one short.
  const wideTop = {class: 'egg_tray', confidence: .9, x: 125, y: 100, width: 180, height: 36};
  const straight = spanColumns([wideTop, ...tray(20, {skip: [0]}), ...tray(20, {x: 200, skip: [0]})]);
  assert.deepEqual(straight.map(c => [c.walk_count, c.doubts]), [[20, ['box_over_two_stacks']], [19, ['box_over_two_stacks']]]);
  const block = buildBlock(straight, faceOf(20), faceOf(19));
  assert.equal(block.status, 'estimated'); assert.deepEqual(block.single_reading_cells, [[0, 0], [1, 0]]);
});

test('a bottom tray cut by the frame edge gets a short box that is merged as a duplicate: a doubt (img-30 stack 4)', () => {
  const boxes = tray(19);
  boxes.push({class: 'egg_tray', confidence: .9, x: 100, y: 100 + 18 * 40 + 14, width: 80, height: 16});
  const [column] = spanColumns(boxes);
  assert.equal(column.walk_count, 19); assert.deepEqual(column.doubts, ['end_box_cut_short']);
  const tall = tray(20, {skip: [18, 19]});
  tall.push({class: 'egg_tray', confidence: .9, x: 100, y: 100 + 18.5 * 40, width: 80, height: 70});
  assert.deepEqual(spanColumns(tall)[0].doubts, ['box_over_two_trays']);
});

test('a stack whose bottom box sits over half a pitch above its neighbours lost its bottom tray (L-109 stack 4)', () => {
  const cols = spanColumns([...tray(20), ...tray(20, {x: 200, skip: [19]}), ...tray(20, {x: 300})]);
  assert.deepEqual(cols.map(c => c.doubts), [[], ['bottom_above_floor'], []]);
  // A shorter stack standing on the floor (its top lower, its bottom level) raises no doubt.
  const short = spanColumns([...tray(20), ...tray(20, {x: 200, skip: [0, 1]}), ...tray(20, {x: 300})]);
  assert.deepEqual(short.map(c => c.doubts), [[], [], []]);
});

test('groups of one or two boxes are reported, not counted, and keep a block from being exact', async () => {
  const { strayGroups } = await import('../dist/index.js');
  const loose = [...tray(20), ...tray(20, {x: 200}), ...tray(2, {x: 400})];
  assert.deepEqual(strayGroups(loose).map(g => g.boxes), [2]);
  const block = buildBlock(spanColumns(loose), faceOf(20), faceOf(20), {straight: 1});
  assert.equal(block.total_trays, 40); assert.equal(block.status, 'estimated');
  assert.ok(block.ambiguities[0].reason.startsWith('STRAIGHT: 1 group(s) of one or two boxes'), block.ambiguities[0].reason);
});

// ---- 2026-11-01 plan Phase K1: doubts that need the frame size.
test('a stack ending within one box height of the frame edge, or touching its side, is not verified', () => {
  const frame = {width: 500, height: 1000};
  // Boxes 36 px tall from y 82 to 878: over a full box height of room at both ends.
  const roomy = spanColumns([...tray(20, {x: 150}), ...tray(20, {x: 300})], frame);
  assert.deepEqual(roomy.map(c => c.doubts), [[], []]);
  // The same stacks in a frame that ends 12 px below the bottom box (img-30: 0.0 box heights).
  const cut = spanColumns([...tray(20, {x: 150}), ...tray(20, {x: 300})], {width: 500, height: 890});
  assert.deepEqual(cut.map(c => c.doubts), [['end_at_frame_edge'], ['end_at_frame_edge']]);
  // A stack whose boxes reach the left edge may be part of a stack.
  const side = spanColumns([...tray(20, {x: 40}), ...tray(20, {x: 300})], frame);
  assert.deepEqual(side.map(c => c.doubts), [['cut_at_frame_side'], []]);
  // Without a frame size (older callers) none of these is raised.
  assert.deepEqual(spanColumns([...tray(20, {x: 150}), ...tray(20, {x: 300})]).map(c => c.doubts), [[], []]);
});

test('a column with a much larger layer pitch than the face is a nearer stack or another block (M16-FAR)', () => {
  const cols = spanColumns([...tray(20), ...tray(20, {x: 200}), ...tray(14, {x: 300, pitch: 56, height: 50})]);
  assert.deepEqual(cols.map(c => c.doubts), [[], [], ['pitch_differs']]);
});

test('the short capture field wins over oversized evidence, so a heading is never lost to the evidence limit', async t => {
  t.mock.method(console, 'log', () => {});
  let call = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    const shift = 120 * call++;
    return Response.json({predictions: trayShaped(column(250 + shift, 20, {pitch: 40})).map(b => ({...b, y: b.y + shift / 6})),
      image: {width: 800, height: 1000}});
  });
  const form = new FormData();
  form.set('scan_contract', 'model_spatial_v1');
  const yaw = {straight: 0, left: -90, right: 90};
  ['left', 'right', 'straight'].forEach((view, i) => {
    form.set(view, new File([new Uint8Array([255, 216, 255, i])], `${view}.jpg`, {type: 'image/jpeg'}));
    const evidence = {source: 'captured_still', blocked: false, yaw_deg: yaw[view], yaw_session: 'w', checks: 'x'.repeat(20000)};
    form.set(`${view}_constraint_evidence`, JSON.stringify(evidence));
    if (view !== 'right') form.set(`${view}_capture`, JSON.stringify({source: 'captured_still', blocked: false, yaw_deg: yaw[view], yaw_session: 'w'}));
  });
  const response = await worker.fetch(new Request('https://local/v1/scans/count', {method: 'POST', body: form}),
    {MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only'});
  const result = await response.json();
  // LEFT has the short field; RIGHT has only the 20 kB evidence, which is past the limit, so it reads as unknown.
  assert.equal(result.block.side_check.left.status, 'turned');
  assert.deepEqual([result.views.left.trusted, result.views.right.trusted, result.views.right.capture_source], [true, false, null]);
});
