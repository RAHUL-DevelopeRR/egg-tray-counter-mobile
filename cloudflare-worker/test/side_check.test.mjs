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
  // A CORNER photo reading 3 wide and 3 deep settles the side it sees, and the other side when it repeats the front too.
  const seen = sideCheck({straight: square, left: square, right: square}, walk, {x: 3, y: 3, side: 'left', problem: null});
  for (const s of ['left', 'right'])
    assert.deepEqual([seen[s].status, seen[s].repeats_front, seen[s].depth_witness, seen[s].reason], ['turned', true, 'corner', undefined], s);
  // Sides that differ from the front are side faces on the heading alone.
  const side = cols([12, 12]);
  const deep = sideCheck({straight: square, left: side, right: side}, walk);
  assert.deepEqual([deep.left.status, deep.left.reason, deep.left.repeats_front], ['turned', undefined, undefined]);
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
  assert.deepEqual([scoped.left.status, scoped.right.status], ['turned', 'turned_repeats_front']);
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
function walkAround(extras) {
  const face = boxes([20, 20, 20, 20, 20]);
  const walk = {straight: heading(0, 'k3x9'), left: heading(-90, 'k3x9'), right: heading(90, 'k3x9')};
  const results = Object.fromEntries(['left', 'right', 'straight'].map(v => [v, {count: 0, confidence: 0, detections: face, image: FRAME}]));
  const stills = Object.fromEntries(['left', 'right', 'straight'].map(v => [v, {source: 'captured_still', blocked: false, heading: walk[v]}]));
  return modelDiagnostics('t', results, {}, env, 0, undefined, undefined, walk, stills, extras);
}
const still = {source: 'captured_still', blocked: false, heading: null};

test('a CORNER photo that sees a 5 x 5 block settles the depth of sides that repeat the front; they still verify nothing', () => {
  const result = walkAround({corner: cornerPhoto(9, 5), cornerCapture: still, cornerSide: 'front_left'});
  assert.deepEqual([result.block.side_check.left.status, result.block.side_check.left.depth_witness], ['turned', 'corner']);
  assert.deepEqual([result.block.corner.x, result.block.corner.y, result.block.corner.agrees], [5, 5, true]);
  assert.deepEqual([result.block.status, result.block.total_trays], ['estimated', 500]);
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
  assert.deepEqual([genuine.left.status, genuine.left.direction_ok, genuine.right.direction_ok], ['turned', true, true]);
  const swapped = sideCheck({straight: square, left: side, right: side}, {straight: heading(0), left: heading(92), right: heading(-87)});
  assert.deepEqual([swapped.left.status, swapped.left.direction_ok, swapped.right.direction_ok], ['turned', false, false]);
  assert.equal(sideCheck({straight: square, left: side, right: side}, {straight: heading(0), left: heading(-135), right: heading(90)}).left.status, 'turned');
});
