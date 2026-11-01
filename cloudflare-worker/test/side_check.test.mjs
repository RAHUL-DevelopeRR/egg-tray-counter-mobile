import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { sideCheck, spanColumns } from '../dist/index.js';

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

test('a phone heading from one capture screen decides, whatever the counts say', () => {
  const square = cols([20, 20, 20]);
  const turned = sideCheck({straight: square, left: square, right: square},
    {straight: heading(0), left: heading(88), right: heading(-92)});
  assert.deepEqual([turned.left.status, turned.left.turn_deg, turned.right.status, turned.right.turn_deg], ['turned', 88, 'turned', -92]);
  assert.equal(turned.left.reason, undefined);
  // Heading wraps around: 350 -> 80 is a 90 degree turn, 10 -> -340 is no turn at all.
  assert.equal(sideCheck({straight: square, left: square, right: square},
    {straight: heading(350), left: heading(80), right: heading(260)}).left.turn_deg, 90);
  const same = sideCheck({straight: square, left: square, right: square},
    {straight: heading(10), left: heading(-340), right: heading(-80)});
  assert.equal(same.left.status, 'same_way_as_straight');
  assert.match(same.left.reason, /^LEFT: taken facing the same way as STRAIGHT \(phone turned only 10 degrees\)/);
  assert.equal(same.right.status, 'turned');
});

test('LEFT and RIGHT facing the same way are one side photographed twice (13 Oct corner block)', () => {
  const verdicts = sideCheck({straight: cols([20, 20, 20, 20]), left: cols([20, 20, 20]), right: cols([20, 20, 20])},
    {straight: heading(0), left: heading(90), right: heading(95)});
  assert.equal(verdicts.left.status, 'turned');
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

test('the same photos with camera headings turned around the block are a square block and keep their total', async t => {
  const face = boxes([20, 20, 20, 20, 20]);
  const evidence = Object.fromEntries([['straight', 0], ['left', 91], ['right', -87]].map(([view, yaw]) =>
    [view, JSON.stringify({source: 'captured_still', yaw_deg: yaw, yaw_session: 'k3x9'})]));
  const result = await scan(t, {left: face, right: face, straight: face}, evidence);
  assert.deepEqual([result.block.side_check.left.status, result.block.side_check.right.status], ['turned', 'turned']);
  assert.equal(result.block.width, 5); assert.equal(result.block.depth, 5);
  assert.equal(result.block.total_trays, 500);
  assert.equal(result.block.status, 'estimated');
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
  const square = cols([20, 20, 20]);
  const back = sideCheck({straight: square, left: square, right: square},
    {straight: heading(10), left: heading(-170), right: heading(100)});
  assert.equal(back.left.status, 'faces_back'); assert.equal(Math.abs(back.left.turn_deg), 180);
  assert.ok(back.left.reason.startsWith('LEFT: taken facing the back of the block (phone turned 180 degrees from STRAIGHT)'), back.left.reason);
  assert.equal(back.right.status, 'turned');
  // Facing the left side face is a right turn (negative yaw): recorded as direction_ok, not enforced yet.
  const genuine = sideCheck({straight: square, left: square, right: square}, {straight: heading(0), left: heading(-92), right: heading(87)});
  assert.deepEqual([genuine.left.status, genuine.left.direction_ok, genuine.right.direction_ok], ['turned', true, true]);
  const swapped = sideCheck({straight: square, left: square, right: square}, {straight: heading(0), left: heading(92), right: heading(-87)});
  assert.deepEqual([swapped.left.status, swapped.left.direction_ok, swapped.right.direction_ok], ['turned', false, false]);
  assert.equal(sideCheck({straight: square, left: square, right: square}, {straight: heading(0), left: heading(-135), right: heading(90)}).left.status, 'turned');
});
