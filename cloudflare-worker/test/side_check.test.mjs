import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { modelDiagnostics, sideCheck, spanColumns } from '../dist/index.js';

// Same synthetic faces as capture.test.mjs: 100 px wide columns 100 px apart, 20 layers at pitch 40 in a
// 800 x 1000 frame, so every face passes the capture gate and only the side check can withhold a total.
const column = (x, layers, {pitch = 40, width = 100, y0 = 100} = {}) =>
  Array.from({length: layers}, (_, k) => ({class: 'egg_tray', confidence: .9, x, y: y0 + k * pitch, width, height: Math.round(pitch * .9)}));
const boxes = heights => heights.map((layers, i) => column(100 + i * 100, layers)).flat();
const cols = heights => spanColumns(boxes(heights));
const FRAME = {width: 800, height: 1000};
const env = {MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only'};
const heading = (yaw, session = 'cap-1') => ({yaw_deg: yaw, yaw_session: session});

test('a side photo repeating the front stacks and heights is taken as the front again (MUTAA L-100)', () => {
  const front = cols([20, 20, 20, 20, 20]);
  const verdicts = sideCheck({straight: front, left: cols([20, 20, 20, 20, 20]), right: cols([20, 21, 20, 19, 20])});
  assert.equal(verdicts.left.status, 'repeats_front');
  assert.equal(verdicts.right.status, 'repeats_front');
  assert.match(verdicts.left.reason, /^LEFT: shows the same 5 stacks with the same heights as STRAIGHT/);
});

test('without a heading only a one-deep block keeps its sides; deeper sides are unconfirmed, however they count', () => {
  const front = cols([20, 20, 20, 20, 19]);
  // One stack deep (the 99 block): the sides only confirm the corner heights.
  const shallow = sideCheck({straight: front, left: cols([20]), right: cols([19])});
  assert.deepEqual([shallow.left.status, shallow.right.status], ['unverified', 'unverified']);
  assert.equal(shallow.left.reason, undefined);
  // Deeper sides cannot be told from a re-shot front framed one stack tighter or with a stack misread: refused.
  for (const side of [[20, 20, 20, 20], [20, 20, 17, 20, 19], [20, 20, 18, 20, 20]]) {
    const verdicts = sideCheck({straight: front, left: cols(side), right: cols(side)});
    assert.equal(verdicts.left.status, 'unconfirmed', JSON.stringify(side));
    assert.match(verdicts.left.reason, new RegExp(`^LEFT: not confirmed as a side face .* this block is ${side.length} stacks deep`));
  }
  // A one-stack front (a lone stack) has nothing to compare and no depth: never refused.
  assert.equal(sideCheck({straight: cols([14]), left: cols([14]), right: cols([14])}).left.status, 'unverified');
});

test('a phone heading settles which way the camera faced, but not that a side repeating the front is a side (0.5.1)', () => {
  const square = cols([20, 20, 20]);
  const walk = {straight: heading(0), left: heading(88), right: heading(-92)};
  const turned = sideCheck({straight: square, left: square, right: square}, walk);
  assert.deepEqual([turned.left.status, turned.left.turn_deg, turned.right.status, turned.right.turn_deg],
    ['turned_repeats_front', 88, 'turned_repeats_front', -92]);
  assert.match(turned.left.reason, /^LEFT: this photo shows the same stacks with the same heights as STRAIGHT, so it may be the front face again/);
  assert.match(turned.right.reason, /add a CORNER photo from the front-right corner, with the corner stack and both faces in frame, to count the depth$/);
  // A CORNER photo reading 3 wide and 3 deep settles the side it sees, and the other side when it repeats the front too;
  // since 0.6.0 the depth still needs the declared size (rows standing against a block look the same in every photo).
  const corner = {x: 3, y: 3, side: 'left', problem: null};
  const seen = sideCheck({straight: square, left: square, right: square}, walk, corner);
  for (const s of ['left', 'right']) {
    assert.deepEqual([seen[s].status, seen[s].repeats_front, seen[s].corner_settles, seen[s].retake], ['depth_unproven', true, true, 'declaration'], s);
    assert.match(seen[s].reason, /: the CORNER photo shows this is a side face 3 deep, but rows standing against a block look the same in every photo; declare the block size/);
  }
  const both = sideCheck({straight: square, left: square, right: square}, walk, corner, {x: 3, y: 3});
  for (const s of ['left', 'right'])
    assert.deepEqual([both[s].status, both[s].repeats_front, both[s].depth_witness, both[s].reason], ['turned', true, 'corner_and_declaration', undefined], s);
  // Sides that differ from the front are side faces on the heading alone, but their depth rests on the declared size.
  const side = cols([12, 12]);
  const deep = sideCheck({straight: square, left: side, right: side}, walk);
  assert.deepEqual([deep.left.status, deep.left.retake, deep.left.repeats_front], ['depth_unproven', 'declaration', undefined]);
  assert.match(deep.left.reason, /^LEFT: the block reads 2 deep here, but rows standing against a block look the same in every photo; declare the block size \(X x Y\) before the scan to say where the block ends$/);
  const declaredDeep = sideCheck({straight: square, left: side, right: side}, walk, null, {x: 3, y: 2});
  assert.deepEqual([declaredDeep.left.status, declaredDeep.left.depth_witness, declaredDeep.left.reason], ['turned', 'declaration', undefined]);
  // Heading wraps around: 350 -> 80 is a 90 degree turn, 10 -> -340 is no turn at all.
  assert.equal(sideCheck({straight: square, left: side, right: side},
    {straight: heading(350), left: heading(80), right: heading(260)}).left.turn_deg, 90);
  const same = sideCheck({straight: square, left: square, right: side},
    {straight: heading(10), left: heading(-340), right: heading(-80)});
  assert.equal(same.left.status, 'same_way_as_straight');
  assert.match(same.left.reason, /^LEFT: taken facing the same way as STRAIGHT \(phone turned only 10 degrees\)/);
  assert.equal(same.right.status, 'turned');
});

test('a turned side repeats the front with one stack more or fewer, reversed, or one misread height from four stacks up', () => {
  const walk = {straight: heading(0), left: heading(-90), right: heading(90)};
  const verdict = (front, side) => sideCheck({straight: cols(front), left: cols(side), right: cols([9])}, walk).left.status;
  assert.equal(verdict([20, 20, 20, 20, 20], [20, 20, 20, 20]), 'turned_repeats_front');      // framed one stack tighter
  assert.equal(verdict([20, 20, 20], [20, 20, 20, 20]), 'turned_repeats_front');              // or one wider
  assert.equal(verdict([20, 18, 15], [15, 18, 20]), 'turned_repeats_front');                  // seen from the other end
  assert.equal(verdict([20, 20, 20, 20], [20, 20, 14, 20]), 'turned_repeats_front');          // one stack misread
  assert.equal(verdict([20, 20, 20, 20], [20, 14, 14, 20]), 'turned');                        // two differ: another face
  assert.equal(verdict([20, 20, 20], [20, 14, 20]), 'turned');                                // three stacks: no misread allowed
  assert.equal(verdict([20, 20, 20, 20], [20, 20]), 'turned');                                // two stacks fewer
  assert.equal(verdict([20, 20, 20], [20]), 'turned');                                        // a one-deep side has no depth to fake
  // Behind a one-stack front any deeper side could be the stack plus stacks standing behind it (0.5.0 gave exact 40 for 20).
  assert.equal(verdict([20], [20, 20]), 'turned_repeats_front');
  assert.equal(verdict([20], [20, 14, 9]), 'turned_repeats_front');
  assert.equal(verdict([20], [20]), 'turned');
  assert.match(sideCheck({straight: cols([20]), left: cols([20, 20]), right: cols([20])}, walk).left.reason,
    /^LEFT: STRAIGHT shows one stack, so this side cannot be told from stacks standing behind it; add a CORNER photo/);
});

test('a CORNER photo settles only the side it sees, at the depth it reads, and says what is wrong when it does not', () => {
  const walk = {straight: heading(0), left: heading(-90), right: heading(90)};
  const front = cols([20, 20, 20, 20]);
  const check = (left, right, corner) => sideCheck({straight: front, left: cols(left), right: cols(right)}, walk, corner);
  // LEFT is a real side (back rows lower), RIGHT the front again: a front-left CORNER photo cannot vouch for RIGHT.
  const scoped = check([15, 15, 20], [20, 20, 20], {x: 4, y: 3, side: 'left', problem: null});
  assert.deepEqual([scoped.left.status, scoped.right.status], ['depth_unproven', 'turned_repeats_front']);
  assert.match(scoped.right.reason, /and the CORNER photo sees the left side, not this one; add a CORNER photo from the front-right corner/);
  // The CORNER photo reads 1 deep: the 4-deep side is not the side face.
  const wrong = check([20, 20, 20, 20], [20, 20, 20, 20], {x: 4, y: 1, side: 'left', problem: null});
  assert.match(wrong.left.reason, /^LEFT: the CORNER photo shows 4 stacks wide and 1 deep, but this side shows 4 stacks and STRAIGHT 4: it is not the left side face/);
  // Width and depth the other way round: probably taken from the other corner.
  const swapped = check([20, 20, 20], [20, 20, 20], {x: 3, y: 4, side: 'left', problem: null});
  assert.match(swapped.left.reason, /reads 3 wide and 4 deep, the other way round; was it taken from the other front corner\?$/);
  // A CORNER photo that cannot be used says why.
  const blocked = check([20, 20, 20], [20, 20, 20], {x: 4, y: 3, side: 'left', problem: "the phone's live checks blocked the CORNER photo"});
  assert.match(blocked.left.reason, /and the phone's live checks blocked the CORNER photo; retake the CORNER photo$/);
});

test('LEFT and RIGHT facing the same way are one side photographed twice (13 Oct corner block)', () => {
  const verdicts = sideCheck({straight: cols([20, 20, 20, 20]), left: cols([20, 20, 20]), right: cols([20, 20, 20])},
    {straight: heading(0), left: heading(90), right: heading(95)});
  // 0.5.1: an even-height block's sides also repeat the front, so LEFT waits for a CORNER or ELEVATED view as well.
  assert.equal(verdicts.left.status, 'turned_repeats_front');
  assert.equal(verdicts.right.status, 'same_way_as_other_side');
  assert.match(verdicts.right.reason, /^RIGHT: taken facing the same way as LEFT \(5 degrees apart\)/);
});

test('headings from different sessions are not compared: the count rule and the depth rule apply instead', () => {
  const face = cols([20, 20, 20]);
  const verdicts = sideCheck({straight: face, left: face, right: cols([20, 20])},
    {straight: heading(0, 'cap-1'), left: heading(90, 'cap-2'), right: heading(-90, 'cap-2')});
  assert.equal(verdicts.left.status, 'repeats_front');
  assert.equal(verdicts.right.status, 'unconfirmed');
  // One-deep sides from one session are still compared with each other: one end photographed twice.
  const ends = sideCheck({straight: cols([20, 20, 20, 20]), left: cols([20]), right: cols([20])},
    {left: heading(90, 'cap-2'), right: heading(92, 'cap-2')});
  assert.equal(ends.left.status, 'unverified');
  assert.equal(ends.right.status, 'same_way_as_other_side');
});

async function scan(t, perView, evidence = {}) {
  t.mock.method(console, 'log', () => {});
  const calls = [];
  t.mock.method(globalThis, 'fetch', async () => {
    const view = ['left', 'right', 'straight'][calls.length];   // Worker infers views in this order
    calls.push(view);
    return Response.json({image: FRAME, predictions: perView[view]});
  });
  const form = new FormData();
  form.set('scan_contract', 'model_spatial_v1');
  ['left', 'right', 'straight'].forEach((view, i) => form.set(view,
    new File([new Uint8Array([255, 216, 255, i])], `${view}.jpg`, {type: 'image/jpeg'})));
  for (const [view, value] of Object.entries(evidence)) form.set(`${view}_constraint_evidence`, value);
  const response = await worker.fetch(new Request('https://local/v1/scans/count', {method: 'POST', body: form}), env);
  assert.equal(response.status, 200);
  return response.json();
}

test('three front photos withhold the block total and ask for the LEFT side face', async t => {
  const front = boxes([20, 20, 20, 20, 20]);
  const result = await scan(t, {left: front, right: front, straight: front});
  assert.equal(result.block.status, 'needs_view');
  assert.equal(result.result_status, 'needs_view');
  assert.equal(result.block.total_trays, null);
  assert.equal(result.block.total_eggs, null);
  assert.equal(result.block.side_check.left.status, 'repeats_front');
  assert.match(result.block.conflicts[0].reason, /^LEFT: shows the same 5 stacks/);
  assert.equal(result.rescan.recommended_view, 'left');
  assert.match(result.rescan.reason, /photograph the left side face with the camera after walking around the corner$/);
  // Every face passed the capture gate: the side check alone withheld the total.
  assert.ok(Object.values(result.block.capture).every(q => q.accepted));
  // The false 5 x 5 depth, its hidden stacks and the grid are not returned either (the app would draw them).
  assert.equal(result.block.depth, null);
  assert.deepEqual(result.block.cells, []);
  assert.equal(result.block.computed_trays, null);
  assert.equal(result.block.observed_trays, null);
  assert.equal(result.block.width, 5);
});

test('a real deep block uploaded without headings (gallery, older app) is withheld, not counted', async t => {
  const result = await scan(t, {left: boxes([20, 20, 20]), right: boxes([20, 20, 20]), straight: boxes([20, 20, 20, 20])});
  assert.equal(result.block.status, 'needs_view');
  assert.equal(result.block.total_trays, null);
  assert.deepEqual([result.block.side_check.left.status, result.block.side_check.right.status], ['unconfirmed', 'unconfirmed']);
  assert.match(result.rescan.reason, /scan it with the camera, walking around the block$/);
});

test('the same photos with camera headings turned around the block no longer give 500: they ask for a CORNER photo (0.5.1)', async t => {
  const face = boxes([20, 20, 20, 20, 20]);
  const evidence = Object.fromEntries([['straight', 0], ['left', 91], ['right', -87]].map(([view, yaw]) =>
    [view, JSON.stringify({source: 'captured_still', yaw_deg: yaw, yaw_session: 'k3x9'})]));
  const result = await scan(t, {left: face, right: face, straight: face}, evidence);
  assert.deepEqual([result.block.side_check.left.status, result.block.side_check.right.status], ['turned_repeats_front', 'turned_repeats_front']);
  assert.equal(result.block.status, 'needs_view');
  assert.equal(result.result_status, 'needs_view');
  assert.equal(result.block.total_trays, null);
  assert.equal(result.block.depth, null);
  assert.deepEqual(result.block.cells, []);
  assert.deepEqual(result.block.suggested_views, ['corner']);
  assert.equal(result.rescan.recommended_view, 'left');
  assert.match(result.rescan.reason, /^LEFT: this photo shows the same stacks with the same heights as STRAIGHT/);
  // Nothing from the false 5 x 5 build is left for a client to add up.
  assert.deepEqual([result.block.single_reading_cells, result.block.visible_single_reading_trays, result.block.grid], [[], null, []]);
});

// The same five-stack faces from a camera walk-around, with a CORNER photo or ELEVATED taps (modelDiagnostics, as the
// Worker runs it after inference). A CORNER photo of n stacks whose nearest stack (largest pitch) is the k-th from the
// left shows k stacks on the left face and n - k + 1 on the right (front_left: width = right face, depth = left face).
const cornerPhoto = (n, k) => ({detections: Array.from({length: n}, (_, i) => column(100 + i * 100, 20, {pitch: i === k - 1 ? 52 : 40})).flat(),
  image: {width: 100 * n + 200, height: 1200}});
// separate: each side framed a little differently (separate captures, not copies of the front photo). 0.7.0: a copy never
// sets the stacking rule's full height, so a released deep total needs the sides to be separate captures.
function walkAround(extras, {separate = false} = {}) {
  const face = boxes([20, 20, 20, 20, 20]);
  const walk = {straight: heading(0, 'k3x9'), left: heading(-90, 'k3x9'), right: heading(90, 'k3x9')};
  const shifted = dx => face.map(b => ({...b, x: b.x + dx, y: b.y + dx / 3}));
  const results = Object.fromEntries(['left', 'right', 'straight'].map(v => [v, {count: 0, confidence: 0,
    detections: separate && v !== 'straight' ? shifted(v === 'left' ? 30 : 60) : face, image: separate && v !== 'straight' ? {width: 700, height: 1000} : FRAME}]));
  const stills = Object.fromEntries(['left', 'right', 'straight'].map(v => [v, {source: 'captured_still', blocked: false, heading: walk[v]}]));
  return modelDiagnostics('t', results, {}, env, 0, undefined, undefined, walk, stills, extras);
}
const still = {source: 'captured_still', blocked: false, heading: null};

test('a CORNER photo that sees a 5 x 5 block settles sides that repeat the front; the depth also needs the declared size', () => {
  const alone = walkAround({corner: cornerPhoto(9, 5), cornerCapture: still, cornerSide: 'front_left'});
  assert.deepEqual([alone.block.side_check.left.status, alone.block.side_check.left.corner_settles], ['depth_unproven', true]);
  assert.deepEqual([alone.block.status, alone.block.total_trays], ['needs_view', null]);
  const decl = {x: 5, y: 5, interior: 'unknown', missing_cells: [], partial_stacks: [], cover_trays: 'unknown', occupancy: 'unknown',
    reference_height: null, operator: null, declared_at: null};
  const result = walkAround({corner: cornerPhoto(9, 5), cornerCapture: still, cornerSide: 'front_left', declaration: decl}, {separate: true});
  assert.deepEqual([result.block.side_check.left.status, result.block.side_check.left.depth_witness], ['turned', 'corner_and_declaration']);
  assert.deepEqual([result.block.corner.x, result.block.corner.y, result.block.corner.agrees], [5, 5, true]);
  assert.deepEqual([result.block.status, result.block.total_trays, result.block.depth_basis], ['estimated', 500, 'corner_and_declaration']);
  assert.deepEqual([result.views.left.trusted, result.views.right.trusted, result.views.straight.trusted], [false, false, true]);
});

test('a CORNER photo of the real 5 x 1 block (MUTAA L-100) withholds the false 5 x 5 and names the side to retake', () => {
  const result = walkAround({corner: cornerPhoto(5, 1), cornerCapture: still, cornerSide: 'front_left'});
  assert.deepEqual([result.block.corner.x, result.block.corner.y], [5, 1]);
  assert.deepEqual([result.block.status, result.block.total_trays, result.block.depth], ['needs_view', null, null]);
  assert.deepEqual([result.block.cells, result.block.grid], [[], []]);
  assert.equal(result.rescan.recommended_view, 'left');
  assert.match(result.rescan.reason, /^LEFT: the CORNER photo shows 5 stacks wide and 1 deep, but this side shows 5 stacks and STRAIGHT 5: it is not the left side face/);
  assert.deepEqual(result.block.suggested_views, []);
});

test('ELEVATED taps, a gallery or blocked CORNER photo, or one without its side do not settle the depth', () => {
  // The app sizes the tap grid from the declaration and an empty grid reads nothing (0.5.1 review): never a witness.
  for (const topView of [{x: 5, y: 5, cells: []}, {x: 5, y: 5, cells: [{x: 2, y: 4, state: 'present'}]}]) {
    const r = walkAround({topView, elevated: true});
    assert.deepEqual([r.block.status, r.block.total_trays, r.block.side_check.left.status], ['needs_view', null, 'turned_repeats_front']);
  }
  const gallery = walkAround({corner: cornerPhoto(9, 5), cornerCapture: {source: 'uploaded_photo', blocked: null, heading: null}, cornerSide: 'front_left'});
  assert.match(gallery.block.side_check.left.reason, /and the CORNER photo is not from the guided camera; retake the CORNER photo$/);
  const blocked = walkAround({corner: cornerPhoto(9, 5), cornerCapture: {...still, blocked: true}, cornerSide: 'front_left'});
  assert.deepEqual([blocked.block.status, blocked.block.total_trays], ['needs_view', null]);
  const sideless = walkAround({corner: cornerPhoto(9, 5), cornerCapture: still, cornerSide: null});
  assert.match(sideless.block.side_check.left.reason, /the CORNER photo could not be read \(corner side not given/);
  const unreadable = walkAround({corner: cornerPhoto(1, 1), cornerCapture: still, cornerSide: 'front_left'});
  assert.match(unreadable.block.side_check.left.reason, /the CORNER photo could not be read \(fewer than two stacks in the CORNER photo\)/);
});

test('a wrong-way side is retaken before a side that only needs a CORNER photo, and only then is a CORNER photo suggested', () => {
  const face = boxes([20, 20, 20, 20, 20]);
  const walk = {straight: heading(0, 'k'), left: heading(-90, 'k'), right: heading(-85, 'k')};
  const results = Object.fromEntries(['left', 'right', 'straight'].map(v => [v, {count: 0, confidence: 0, detections: face, image: FRAME}]));
  const r = modelDiagnostics('t', results, {}, env, 0, undefined, undefined, walk, {}, {});
  assert.deepEqual([r.block.side_check.left.status, r.block.side_check.right.status], ['turned_repeats_front', 'same_way_as_other_side']);
  assert.equal(r.rescan.recommended_view, 'right');
  assert.match(r.block.conflicts[0].reason, /^RIGHT: taken facing the same way as LEFT/);
  assert.deepEqual(r.block.suggested_views, []);
});

test('a camera side taken without turning is refused with the turn it measured', async t => {
  const front = boxes([20, 20, 20, 20]);
  const evidence = {straight: JSON.stringify({yaw_deg: 12.4, yaw_session: 's1'}), left: JSON.stringify({yaw_deg: 30.2, yaw_session: 's1'}),
    right: JSON.stringify({yaw_deg: -80, yaw_session: 's1'})};
  const result = await scan(t, {left: boxes([20, 20]), right: boxes([20, 20]), straight: front}, evidence);
  assert.equal(result.block.total_trays, null);
  assert.equal(result.block.side_check.left.turn_deg, 18);
  assert.equal(result.rescan.recommended_view, 'left');
  assert.match(result.rescan.reason, /phone turned only 18 degrees/);
});

test('missing or malformed evidence never refuses a scan and a real block keeps its total', async t => {
  const evidence = {straight: '{not json', left: JSON.stringify({yaw_deg: 'ninety', yaw_session: 's'}),
    right: JSON.stringify({yaw_deg: 90, yaw_session: 'has spaces'})};
  const result = await scan(t, {left: boxes([20]), right: boxes([20]), straight: boxes([20, 20, 20, 20, 19])}, evidence);
  assert.deepEqual([result.block.side_check.left.status, result.block.side_check.right.status], ['unverified', 'unverified']);
  assert.equal(result.block.total_trays, 99);
});

test('a side photo turned past 135 degrees faces the back of the block and is refused; the turn direction is recorded', () => {
  const square = cols([20, 20, 20]), side = cols([12, 12]);
  const back = sideCheck({straight: square, left: square, right: side},
    {straight: heading(10), left: heading(-170), right: heading(100)});
  assert.equal(back.left.status, 'faces_back'); assert.equal(Math.abs(back.left.turn_deg), 180);
  assert.ok(back.left.reason.startsWith('LEFT: taken facing the back of the block (phone turned 180 degrees from STRAIGHT)'), back.left.reason);
  assert.equal(back.right.status, 'turned');
  // Facing the left side face is a right turn (negative yaw): recorded as direction_ok, not enforced yet.
  const genuine = sideCheck({straight: square, left: side, right: side}, {straight: heading(0), left: heading(-92), right: heading(87)});
  assert.deepEqual([genuine.left.status, genuine.left.direction_ok, genuine.right.direction_ok], ['depth_unproven', true, true]);
  const swapped = sideCheck({straight: square, left: side, right: side}, {straight: heading(0), left: heading(92), right: heading(-87)});
  assert.deepEqual([swapped.left.status, swapped.left.direction_ok, swapped.right.direction_ok], ['depth_unproven', false, false]);
  assert.equal(sideCheck({straight: square, left: side, right: side}, {straight: heading(0), left: heading(-135), right: heading(90)}).left.status, 'depth_unproven');
});

// ---- 0.6.0 depth proof (docs/GRID_CONTRACT_0.6.0.md): rows standing against a block look the same in every photo, a
// CORNER photo included, so a depth over one stack rests on the declared block size. Camera walk-arounds through
// modelDiagnostics; each face's frame is sized to its stacks so every face passes the capture gate.
const faceView = (heights, {x0 = 100, y0 = 100} = {}) => ({count: 0, confidence: 0,
  detections: heights.map((layers, i) => column(x0 + i * 100, layers, {y0})).flat(), image: {width: 100 * heights.length + x0, height: 1000}});
const WALK = {straight: heading(0, 'k'), left: heading(-90, 'k'), right: heading(90, 'k')};
function walkScan(faces, extras = {}, walk = WALK) {
  // Each side framed a little differently: separate captures, not copies of one photo.
  const results = {straight: faceView(faces.straight), left: faceView(faces.left, {x0: 130, y0: 110}), right: faceView(faces.right, {x0: 160, y0: 120})};
  if (!faces.right.length) results.right = {count: 0, confidence: 0, detections: [], image: FRAME};
  const stills = Object.fromEntries(['left', 'right', 'straight'].map(v => [v, {source: 'captured_still', blocked: false, heading: walk[v]}]));
  return modelDiagnostics('t', results, {}, env, 0, undefined, undefined, walk, stills, extras);
}
const declare = (x, y) => ({declaration: {x, y, interior: 'unknown', missing_cells: [], partial_stacks: [], cover_trays: 'unknown',
  occupancy: 'unknown', reference_height: null, operator: null, declared_at: null}});
const cornerReads = (x, y) => ({corner: cornerPhoto(x + y - 1, y), cornerCapture: still, cornerSide: 'front_left'});
const NEW_NUMBERS = ['counted_trays', 'counted_stacks', 'assumed_trays', 'assumed_range', 'assumed_stacks', 'estimated_total', 'estimated_range',
  'hidden_stacks', 'hidden_stacks_top_checked', 'unchecked_hidden_stacks', 'missing_stacks'];
const S25 = {straight: [20, 20, 20, 20, 20], left: [20, 20, 20], right: [20, 20, 20]};

test('H10: S25, a 5x1 row with two rows standing behind it, is withheld until the operator declares the block size', () => {
  const r = walkScan(S25);
  assert.deepEqual([r.block.side_check.left.status, r.block.side_check.right.status], ['depth_unproven', 'depth_unproven']);
  assert.deepEqual([r.block.status, r.block.total_trays, r.block.grid, r.block.cells], ['needs_view', null, [], []]);
  assert.deepEqual([r.block.suggested_views, r.block.suggested_inputs, r.block.depth_basis], [[], ['declaration'], null]);
  assert.equal(r.rescan.recommended_view, 'left');
  assert.match(r.rescan.reason, /^LEFT: the block reads 3 deep here, but rows standing against a block look the same in every photo; declare the block size/);
  const inv = r.block.inventory;
  assert.deepEqual([inv.released, inv.withheld_reason], [false, 'depth_unproven']);
  for (const k of NEW_NUMBERS) assert.equal(inv[k], null, k);
  assert.deepEqual(inv.provisional, {kind: 'depth_unproven', reason: r.block.side_check.left.reason, front_row_counted: 100,
    if_depth: {y: 3, counted_trays: 180, assumed_trays: 120, assumed_stacks: 6, estimated_total: 300}});
  // The operator says where the block ends: 5 x 3 releases the estimate, 5 x 1 (the truth) keeps it withheld.
  const deep = walkScan(S25, declare(5, 3));
  assert.deepEqual([deep.block.status, deep.block.total_trays, deep.block.depth_basis], ['estimated', 300, 'declaration']);
  assert.deepEqual([deep.block.inventory.provisional, deep.block.suggested_inputs], [null, []]);
  // Tray capacity is never given for assumed trays (tray layers, never eggs).
  assert.equal(deep.block.total_eggs, null);
  const row = walkScan(S25, declare(5, 1));
  assert.deepEqual([row.block.status, row.block.total_trays], ['needs_view', null]);
  assert.match(row.block.side_check.left.reason, /; the declaration says 5 x 1$/);
  assert.deepEqual(row.block.suggested_inputs, ['declaration']);
  // A CORNER photo sees the same touching rows (5 x 3): alone it proves nothing; with the declaration it agrees.
  const corner = walkScan(S25, cornerReads(5, 3));
  assert.deepEqual([corner.block.status, corner.block.total_trays, corner.block.suggested_views], ['needs_view', null, []]);
  const both = walkScan(S25, {...cornerReads(5, 3), ...declare(5, 3)});
  assert.deepEqual([both.block.status, both.block.total_trays, both.block.corner.agrees], ['estimated', 300, true]);
  // A side shot twice is still caught and retaken first.
  const twice = walkScan(S25, {}, {...WALK, right: heading(-85, 'k')});
  assert.deepEqual([twice.block.side_check.right.status, twice.rescan.recommended_view], ['same_way_as_other_side', 'right']);
  // Sides of different depths need no proof of their own: the block model's depth conflict names the retake.
  const uneven = walkScan({straight: S25.straight, left: [20, 20, 20], right: [12, 12]});
  assert.deepEqual([uneven.block.side_check.left.status, uneven.block.side_check.right.status, uneven.block.status], ['turned', 'turned', 'conflict']);
});

test('H11: sides that repeat the front need the CORNER photo and the declared size; the what-if waits for the CORNER photo', () => {
  const H1 = {straight: [15, 15, 15, 15], left: [15, 15, 15], right: [15, 15, 15]};
  const r = walkScan(H1);
  assert.deepEqual([r.block.side_check.left.status, r.block.status, r.block.suggested_views, r.block.suggested_inputs],
    ['turned_repeats_front', 'needs_view', ['corner'], ['declaration']]);
  assert.deepEqual(r.block.inventory.provisional, {kind: 'side_repeats_front', reason: r.block.side_check.left.reason, front_row_counted: 60, if_depth: null});
  assert.equal(r.block.inventory.withheld_reason, 'side_repeats_front');
  const declared = walkScan(H1, declare(4, 3));
  assert.deepEqual([declared.block.status, declared.block.suggested_views, declared.block.suggested_inputs], ['needs_view', ['corner'], []]);
  const corner = walkScan(H1, cornerReads(4, 3));
  assert.deepEqual([corner.block.side_check.left.status, corner.block.side_check.left.corner_settles, corner.block.status],
    ['depth_unproven', true, 'needs_view']);
  assert.match(corner.block.side_check.left.reason, /^LEFT: the CORNER photo shows this is a side face 3 deep, but rows standing against a block/);
  assert.equal(corner.block.inventory.provisional.kind, 'depth_unproven');
  assert.equal(corner.block.inventory.provisional.if_depth.estimated_total, 180);
  assert.deepEqual([corner.block.suggested_views, corner.block.suggested_inputs], [[], ['declaration']]);
  const both = walkScan(H1, {...cornerReads(4, 3), ...declare(4, 3)});
  assert.deepEqual([both.block.status, both.block.total_trays, both.block.depth_basis], ['estimated', 180, 'corner_and_declaration']);
  assert.deepEqual([both.views.left.trusted, both.views.right.trusted], [false, false]);
  assert.deepEqual([both.block.inventory.counted_trays, both.block.inventory.assumed_trays, both.block.inventory.unchecked_hidden_stacks], [120, 60, 4]);
  // 0.7.0: the sides, settled by the CORNER photo and the declaration, set the full height 15 (Decision 3 (a)); an
  // ELEVATED photo is no longer suggested.
  assert.deepEqual([both.block.rule.height, both.block.suggested_views], [15, []]);
});

test('H12: earlier cases keep their answers; provisional figures appear only for a block withheld for its depth', () => {
  // MUTAA L-100 as a camera walk-around: withheld as in 0.5.1, with the front row counted and no what-if.
  const l100 = walkAround({});
  assert.deepEqual([l100.block.status, l100.block.inventory.provisional.front_row_counted, l100.block.inventory.provisional.if_depth],
    ['needs_view', 100, null]);
  // A gallery 3-deep block (no headings): unconfirmed sides, no provisional figures, no new numbers.
  const gallery = modelDiagnostics('t', Object.fromEntries(['left', 'right', 'straight'].map(v =>
    [v, faceView(v === 'straight' ? [20, 20, 20, 20] : [20, 20, 20])])), {}, env, 0);
  assert.deepEqual([gallery.block.side_check.left.status, gallery.block.inventory.provisional], ['unconfirmed', null]);
  for (const k of NEW_NUMBERS) assert.equal(gallery.block.inventory[k], null, k);
  // S18: a one-deep 2 x 1 block, every stack read by two captures: exact, resting on its one-stack depth.
  const s18 = walkScan({straight: [20, 20], left: [20], right: [20]});
  assert.deepEqual([s18.block.status, s18.block.total_trays, s18.block.depth_basis], ['exact', 40, 'one_deep']);
  assert.deepEqual([s18.block.inventory.counted_trays, s18.block.inventory.hidden_stacks, s18.block.inventory.released], [40, 0, true]);
  assert.equal(s18.block.total_eggs, 1200);
  // A refused photo is retaken first: no provisional figures while a face is not a measurement.
  const refused = walkScan({straight: S25.straight, left: [20, 20, 20], right: []});
  assert.deepEqual([refused.block.side_check.left.status, refused.block.status, refused.block.inventory.provisional, refused.rescan.recommended_view],
    ['depth_unproven', 'needs_view', null, 'right']);
});

test('H13: every 0.5.0 key stays, and the legacy cells, computed_trays and totals agree with the grid', () => {
  const CELL_KEYS = ['physical_stack_id', 'x', 'y', 'stack_present', 'z_layers', 'filled_layers', 'partial_layers', 'empty_cover_layers',
    'unknown_layers', 'observed_views', 'measurement_sources', 'status', 'uncertainties', 'readings', 'pair_type'];
  const BLOCK_KEYS = ['status', 'width', 'depth', 'faces_used', 'typical_layers', 'cells', 'observed_trays', 'computed_trays', 'filled_trays',
    'visible_verified_trays', 'visible_single_reading_trays', 'single_reading_cells', 'total_trays', 'fully_observed', 'faces_consistent',
    'conflicts', 'ambiguities', 'rescan_cells', 'note', 'contract', 'eggs_per_tray', 'verification', 'total_eggs', 'eggs_basis', 'capture',
    'side_check', 'grid', 'inventory', 'confirmed_basis', 'declaration', 'corner', 'top_view', 'suggested_views', 'grid_note'];
  const INVENTORY_KEYS = ['physical_layers_observed', 'physical_layers_computed', 'physical_layers_declared', 'physical_layers_top_view',
    'eligible_egg_trays', 'empty_cover_layers', 'unknown_occupancy_layers', 'unknown_cells'];
  const hole = {topView: {x: 5, y: 3, cells: [{x: 2, y: 1, state: 'missing'}, {x: 1, y: 2, state: 'step_up'}]}, elevated: true};
  for (const extras of [declare(5, 3), {...declare(5, 3), ...hole}]) {
    const {block} = walkScan(S25, extras);
    for (const k of BLOCK_KEYS) assert.ok(k in block, k);
    for (const k of INVENTORY_KEYS) assert.ok(k in block.inventory, k);
    for (const g of block.grid.flat()) for (const k of CELL_KEYS) assert.ok(k in g, k);
    assert.deepEqual([block.grid_contract, block.confirmed_basis], ['0.7.0', []]);
    const hidden = block.grid.flat().filter(g => g.hidden);
    assert.equal(block.computed_trays, hidden.filter(g => g.stack_present !== false).reduce((s, g) => s + (g.z_layers ?? 0), 0));
    // 0.7.0: the step-up tap withholds the second case (a hidden stack taller than its neighbours: H may be too low).
    const stepUp = 'topView' in extras;
    assert.deepEqual([block.inventory.released, block.inventory.withheld_reason], stepUp ? [false, 'inside_step_up'] : [true, null]);
    if (!stepUp) assert.deepEqual([block.observed_trays, block.total_trays], [block.inventory.counted_trays, block.inventory.estimated_total]);
    for (const g of hidden) {
      const legacy = block.cells.find(c => c.x === g.x && c.y === g.y);
      assert.equal(legacy.layers, g.z_layers, `${g.x},${g.y}`);
      if (g.stack_present === false) assert.equal(legacy.status, 'missing');
    }
  }
  const {block} = walkScan(S25, {...declare(5, 3), ...hole});
  // 0.6.0 released 281; 0.7.0 withholds it (inside_step_up). The legacy cells still follow the grid.
  assert.deepEqual([block.total_trays, block.computed_trays, block.inventory.estimated_range], [null, 101, null]);
  assert.deepEqual([block.cells.find(c => c.x === 2 && c.y === 1).status, block.top_view.steps_up], ['missing', 1]);
});
