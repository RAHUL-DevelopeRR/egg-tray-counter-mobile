import assert from 'node:assert/strict';
import test from 'node:test';
import * as w from '../dist/index.js';
import { ruleCases, runRuleCase, ruleSummary, judgeRule } from './rule_cases.mjs';
import { syntheticFace as S, syntheticCorner, declared, CAMERA, capturesFor, replayViews } from './replay_benchmark.mjs';

// ---- 0.7.0 stacking rule (docs/PLAN_5_MULTI_PHOTO.md §4, §7 Phase 1; docs/GRID_CONTRACT_0.7.0.md). Cases FR01-FR21 are
// in test/rule_cases.mjs. A case Plan 5 expects to fail today is a TODO with its reason: FR04 and FR14 document risks the
// rule cannot see (two faces agreeing on an under-read; a hidden hole with no tap); the FR13 family needs Phase 1b
// (a column mixing a face partial and the stack behind it); FR13-outside needs Decision 18; FR18 shows that the printed
// range covers the hidden stacks only, not over-read face stacks.
const KNOWN = {
  'FR04': 'residual risk: two faces agreeing on an under-read (Plan 5 FR04)',
  'FR14': 'residual risk: a hidden hole with no tap (S29 twin, Plan 5 FR14)',
  'FR13': 'Plan 5 Phase 1b: a mixed column reads as one full stack from about scale 0.87',
  'FR13-side': 'Plan 5 Phase 1b',
  'FR13-corner': 'Plan 5 Phase 1b',
  'FR13-outside': 'Plan 5 Decision 18: a partial standing outside the X x Y rectangle',
  'FR18': 'the printed range covers the hidden stacks (120-126, truth 120), not the two over-read face stacks (+2)',
};
const runs = ruleCases().map(c => ({ c, r: runRuleCase(w, c) })).map(({ c, r }) => ({ c, r, s: ruleSummary(r) }));
const get = prefix => runs.find(x => x.c.id.startsWith(prefix + ' '));

for (const { c, s } of runs) {
  const key = c.sweep ?? c.id.split(' ')[0];
  test(`rule ${c.id}`, KNOWN[key] ? { todo: KNOWN[key] } : {}, () => {
    assert.ok(judgeRule(c.check, s, c.truth), `${c.check}: got ${s.status} ${s.total} (${s.withheld_reason}), truth ${c.truth}; expected ${c.expect}`);
  });
}

test('no rule case returns exact or confirmed, and no released rule block is exact', () => {
  for (const { c, s } of runs) {
    assert.notEqual(s.status, 'confirmed', c.id);
    if (s.rule_height !== null) assert.notEqual(s.status, 'exact', c.id);
  }
});

test('FR01: 171 counted on faces + 6 hidden stacks x 20 by the stacking rule = 291; the front 19 is the cover partner', () => {
  const { r, s } = get('FR01');
  const inv = r.block.inventory, rule = r.block.rule;
  assert.deepEqual([s.status, s.total, inv.counted_trays, inv.assumed_trays, inv.estimated_total], ['estimated', 291, 171, 120, 291]);
  assert.deepEqual([rule.height, rule.partner, rule.full_heights, rule.range_heights], [20, 19, [19, 20], [19, 20]]);
  assert.deepEqual(rule.basis.map(b => [b.x, b.y, b.face]), [[0, 2, 'left'], [4, 2, 'right']]);
  assert.deepEqual([inv.rule_stacks, inv.rule_trays, inv.rule_trays_range, inv.sensitivity_per_layer], [6, 120, [114, 120], 6]);
  // The 0.6.0 neighbour ranges are null for a rule block: app 0.6.x then prints "(range not given)" and hides its range row.
  assert.deepEqual([inv.assumed_range, inv.estimated_range, inv.provisional], [null, null, null]);
  assert.equal(inv.note, '171 counted on faces; 6 hidden stacks x 20 = 120 full by the stacking rule (not seen); ' +
    'cover trays are sometimes used: the hidden stacks hold 114 to 120 tray layers');
  assert.deepEqual([r.block.grid_contract, r.block.suggested_views, r.block.depth_basis], ['0.7.0', [], 'declaration']);
  for (const g of r.block.grid.flat().filter(g => g.hidden)) assert.deepEqual([g.z_layers, g.assumed_from, g.assumed_range], [20, 'stacking_rule', [20, 20]]);
  // Two front corners are read the same by two separate captures (M, in stacks).
  assert.equal(inv.two_photo_stacks, 2);
});

test('FR02 / FR03: a face stack above the full heights withholds, names STRAIGHT, and gives provisional figures at both heights', () => {
  const two = get('FR02');
  assert.deepEqual([two.s.rescan_view, two.r.block.rule.taller.map(t => [t.x, t.y, t.layers, t.released])], ['straight', [[2, 0, 21, false]]]);
  assert.match(two.r.rescan.reason, /^STRAIGHT: the stack at \(2, 0\) reads 21 trays, above the block's full height \(19 or 20, with or without a cover tray\)/);
  const p = two.r.block.rule.provisional;
  assert.deepEqual([p.kind, p.counted_on_faces, p.at_rule_height, p.at_taller], ['stack_taller_than_rule_height', 172, 292, {height: 21, estimated_total: 298}]);
  // Never in the inventory: app 0.6.x would title any inventory provisional "DEPTH NOT PROVEN".
  assert.equal(two.r.block.inventory.provisional, null);
  const three = get('FR03');
  assert.deepEqual([three.s.rule_height, three.r.block.rule.taller.map(t => [t.x, t.y]), three.s.total], [20, [[0, 0], [1, 0]], null]);
});

test('FR05: a back corner below the full heights breaks "the back row is full": withheld, retake LEFT', () => {
  const { r, s } = get('FR05');
  assert.deepEqual([s.withheld_reason, s.rescan_view, s.total], ['back_corner_below_rule_height', 'left', null]);
  assert.deepEqual(r.block.rule.back_corners.map(b => [b.x, b.y, b.layers, b.check]), [[0, 2, 18, 'below'], [4, 2, 20, 'full']]);
  assert.equal(r.block.rule.provisional.at_rule_height, 289);
});

test('FR06: a one-deep row has no hidden stack: the rule is not used and the answer is 0.6.0\'s', () => {
  const { r, s } = get('FR06');
  assert.deepEqual([s.status, s.total, r.block.rule, r.block.typical_layers], ['estimated', 99, null, 20]);
  assert.equal(r.block.inventory.rule_stacks, null);
});

test('FR08-FR11, FR16: operator exceptions are honoured with a height and withhold without one; checks name their reason', () => {
  const missing = get('FR08');
  assert.deepEqual([missing.s.total, missing.r.block.inventory.rule_exceptions, missing.r.block.rule.exceptions],
    [271, 1, [{x: 2, y: 1, kind: 'declared_missing', layers: 0}]]);
  assert.deepEqual([get('FR09').s.withheld_reason, get('FR10').s.withheld_reason, get('FR11').s.withheld_reason, get('FR16').s.withheld_reason],
    ['inside_declared_partial', 'inside_step_up', 'inside_hint_below_rule', 'reference_height_differs']);
  assert.deepEqual(get('FR11').r.block.rule.hints_below, [{x: 2, y: 1, face: 'straight', layers: 14}]);
  // WITHHELD_NOTE explains each reason in the inventory note.
  for (const id of ['FR09', 'FR10', 'FR11', 'FR16']) assert.match(get(id).r.block.inventory.note, /^no inventory: /, id);
});

test('FR15: with every reading cut by the frame edge there is no clean basis: no_rule_height, provisional at the typical face height', () => {
  const { r, s } = get('FR15');
  assert.deepEqual([s.withheld_reason, s.rule_height, s.total], ['no_rule_height', null, null]);
  assert.match(r.rescan.reason, /^(LEFT|RIGHT): no full height for the hidden stacks/);
  assert.deepEqual(r.block.rule.provisional.at_typical_face_height, {height: 20, estimated_total: 291});
});

test('FR17: cover trays on some full stacks: the covered stacks are the partner height, never taller; the truth lies in the range', () => {
  const { r, s } = get('FR17');
  assert.deepEqual([s.status, s.total, s.rule_height, s.rule_partner, r.block.rule.taller], ['estimated', 301, 21, 20, []]);
  assert.deepEqual([s.rule_trays_range, s.estimated_range_by_rule], [[120, 126], [295, 301]]);
  assert.match(r.block.inventory.note, /cover trays are sometimes used: the hidden stacks hold 120 to 126 tray layers$/);
});

test('FR20: a doubted face reading below H stays at its reading; the result says how far it could rise (Decision 9)', () => {
  const { r, s } = get('FR20');
  assert.deepEqual([s.total, s.doubted_low_up_to, r.block.rule.doubted_low.map(d => [d.x, d.y, d.layers])], [291, 292, [[3, 0, 19]]]);
  // Without a clean 19 the faces show only H: nobody knows whether 20 includes a cover tray, so the range is 19-21 per stack.
  assert.deepEqual([s.rule_partner, s.rule_trays_range], [null, [114, 126]]);
});

test('FR21 and S21: a side that repeats the front counts for H once a CORNER photo and the declaration settle it; a copy never does', () => {
  assert.deepEqual([get('FR21').s.status, get('FR21').s.total], ['estimated', 180]);
  const copies = replayViews(w, {straight: S([20, 20, 20]), left: S([20, 20, 20]), right: S([20, 20, 20])}, CAMERA,
    capturesFor('captured_still', CAMERA), {...syntheticCorner(3, 3), ...declared(3, 3, {interior: 'unknown'})});
  assert.deepEqual([copies.views.left.duplicate_of, copies.block.total_trays, copies.block.inventory.withheld_reason], ['straight', null, 'no_rule_height']);
});

test('Decision 3 options change one switch: strict sides withhold a near-square block; any photo lets one photo set H', () => {
  const s26 = {views: {straight: S([15, 15, 15, 15]), left: S([15, 15, 15], {shift: 1}), right: S([15, 15, 15], {shift: 2})}, headings: CAMERA,
    extras: {...syntheticCorner(4, 3), ...declared(4, 3, {interior: 'unknown'})}};
  const run = rule => ruleSummary(runRuleCase(w, s26, rule));
  assert.deepEqual([run().total, run({basis: 'doubted_allowed'}).total, run({basis: 'any_photo'}).total], [180, 180, 180]);
  assert.deepEqual([run({basis: 'strict_sides'}).total, run({basis: 'strict_sides'}).withheld_reason], [null, 'no_rule_height']);
  // Any photo: the 10s of one photo set H with no second face and no back corner (Plan 5 §4.5, ef823816). Under (a) no
  // back corner reads a height another face reads, so there is no H at all.
  const one = {views: {straight: S([10, 10, 18, 10, 12]), left: S([16, 14, 10], {shift: 1}), right: S([12, 13, 15], {shift: 2})}, headings: CAMERA,
    extras: declared(5, 3, {interior: 'unknown'})};
  const any = ruleSummary(runRuleCase(w, one, {basis: 'any_photo'}));
  assert.deepEqual([any.rule_height, any.withheld_reason], [10, 'stack_taller_than_rule_height']);
  assert.deepEqual([ruleSummary(runRuleCase(w, one)).rule_height, ruleSummary(runRuleCase(w, one)).withheld_reason], [null, 'no_rule_height']);
  // The cover range off (covers never used, Decision 4 alternative): one height only, and the plurality guard can be on.
  const fr01 = get('FR01').c;
  const flat = ruleSummary(runRuleCase(w, fr01, {coverRange: false}));
  assert.deepEqual([flat.total, flat.rule_partner, flat.rule_trays_range], [291, null, [120, 120]]);
  const fr18 = get('FR18').c;
  // FR18 with covers never used: more face stacks read 20 than the 21 that H rests on (Plan 5 FR18, second answer).
  assert.equal(ruleSummary(runRuleCase(w, fr18, {coverRange: false, plurality: true})).withheld_reason, 'rule_height_ambiguous');
});

test('a released rule block keeps the 0.6.x app contract: three views, the legacy fields, the 0.6.0 inventory keys', () => {
  const { r } = get('FR01');
  assert.deepEqual(Object.keys(r.views).sort(), ['left', 'right', 'straight']);
  for (const v of ['left', 'right', 'straight']) assert.deepEqual([typeof r.views[v].quality, typeof r.views[v].accepted], ['number', 'boolean']);
  assert.deepEqual([r.processing.mode, r.status, r.total_trays, r.scan_id], ['model_spatial_v1', 'rescan_required', null, 'replay']);
  for (const k of ['counted_trays', 'counted_stacks', 'assumed_trays', 'assumed_range', 'assumed_stacks', 'estimated_total', 'estimated_range',
    'hidden_stacks', 'hidden_stacks_top_checked', 'unchecked_hidden_stacks', 'missing_stacks', 'withheld_reason', 'provisional', 'released'])
    assert.ok(k in r.block.inventory, k);
  // Tray layers only: no egg figure for a block with hidden stacks.
  assert.equal(r.block.total_eggs, null);
});
