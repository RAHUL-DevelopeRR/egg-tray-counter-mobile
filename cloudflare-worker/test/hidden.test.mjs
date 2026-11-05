import assert from 'node:assert/strict';
import test from 'node:test';
import { assembleGrid, blockResult, buildBlock, gridInventory, mode, readDeclaration, spanColumns } from '../dist/index.js';

// ---- hidden-tray calculation: 0.6.0 (docs/GRID_CONTRACT_0.6.0.md) kept a hidden stack apart from the counted trays; 0.7.0
// (docs/GRID_CONTRACT_0.7.0.md) sets it to the block's full height by the stacking rule. A top-view tap changes presence and
// steps only. These tests run buildBlock + assembleGrid with no depth proof applied (the side check is side_check.test.mjs).
// Positions are grid (x, y): x from 0 left to right on the front, y from 0 front to back.

// Stacks stand on one floor (bottoms level), 100 px apart; a set-back stack is drawn at a smaller pitch.
const stack = (x, layers, {pitch = 40, width = 80, height = 36} = {}) =>
  Array.from({length: layers}, (_, k) => ({class: 'egg_tray', confidence: .9, x, y: 100 + (22 - layers + k) * pitch, width, height}));
// One photo's stacks, left to right in the frame: a number is a front stack, {layers, pitch} a set-back one.
const face = (...stacks) => spanColumns(stacks.flatMap((s, i) => typeof s === 'number' ? stack(100 + i * 100, s)
  : stack(100 + i * 100, s.layers, {pitch: s.pitch, width: 60})));
const front = (...heights) => face(...heights);
// Side faces by depth (y = 0 first). The LEFT photo has the front corner right-most (buildBlock reverses it), RIGHT left-most.
const left = (...byDepth) => face(...[...byDepth].reverse());
const right = (...byDepth) => face(...byDepth);
const none = {declaration: null, topView: null, corner: null};
const grid = (block, inputs = {}) => {
  const result = assembleGrid(block, {...none, ...inputs});
  return {...result, inventory: gridInventory(result.grid, inputs.declaration ?? null, result.total, {status: result.status, rule: result.rule})};
};
const cellAt = (result, x, y) => result.grid[y][x];

// 0.7.0 (Plan 5 Decision 1): hidden stacks are the block's full height H by the stacking rule, not the 0.6.0 median of
// their neighbours. H1-H5 were the 0.6.0 neighbour cases; each is kept with its new expectation and the reason.
test('H1: a 4x3 block of 15s: 120 counted on faces, and the (4-2)(3-1) = 4 hidden stacks full by the stacking rule at 15', () => {
  const block = buildBlock(front(15, 15, 15, 15), left(15, 15, 15), right(15, 15, 15));
  assert.deepEqual([block.observed_trays, block.computed_trays, block.total_trays, block.typical_layers], [120, 60, 180, 15]);
  // H rests on two back corners read on two faces; the faces show only 15, so a cover tray may make it 14 or 16.
  assert.deepEqual([block.rule.height, block.rule.partner, block.rule.range_heights, block.rule.basis.map(b => [b.x, b.y, b.face])],
    [15, null, [14, 16], [[0, 2, 'left'], [3, 2, 'right']]]);
  const r = grid(block);
  assert.deepEqual([r.status, r.total, r.confirmed_basis], ['estimated', 180, []]);
  const hidden = r.grid.flat().filter(g => g.hidden);
  assert.deepEqual(hidden.map(g => [g.x, g.y]), [[1, 1], [2, 1], [1, 2], [2, 2]]);
  for (const g of hidden) {
    assert.deepEqual([g.evidence_class, g.z_layers, g.assumed_layers, g.assumed_range, g.assumed_from, g.neighbours.length, g.status],
      ['assumed', 15, 15, [15, 15], 'stacking_rule', 0, 'computed'], `${g.x},${g.y}`);
    assert.deepEqual(g.measurement_sources, ['computed']);
    assert.match(g.uncertainties[0], /^hidden: full by the stacking rule, not seen/);
  }
  const inv = r.inventory;
  assert.deepEqual([inv.counted_trays, inv.counted_stacks, inv.assumed_trays, inv.assumed_stacks, inv.estimated_total],
    [120, 8, 60, 4, 180]);
  // The 0.6.0 neighbour ranges are null for a rule block; the cover-tray range is rule_trays_range.
  assert.deepEqual([inv.assumed_range, inv.estimated_range], [null, null]);
  assert.deepEqual([inv.rule_stacks, inv.rule_height, inv.rule_trays, inv.rule_trays_range, inv.rule_full_heights, inv.sensitivity_per_layer],
    [4, 15, 60, [56, 64], [15], 4]);
  assert.deepEqual([inv.rule_exceptions, inv.doubted_low_up_to, inv.two_photo_stacks], [0, null, 2]);
  assert.deepEqual([inv.hidden_stacks, inv.hidden_stacks_top_checked, inv.unchecked_hidden_stacks], [4, 0, 4]);
  assert.deepEqual([inv.unit, inv.released, inv.withheld_reason], ['tray_layers', true, null]);
  assert.equal(inv.note, '120 counted on faces; 4 hidden stacks x 15 = 60 full by the stacking rule (not seen); ' +
    'cover trays are sometimes used: the hidden stacks hold 56 to 64 tray layers');
  assert.equal(r.computed_trays, 60);
});

test('H2: a back corner below the full height breaks the rule: withheld, provisional 237 (0.6.0 released 236 from neighbour medians)', () => {
  const block = buildBlock(front(20, 19, 20, 20), left(20, 20, 18), right(20, 20, 20));
  // H = 20 from the back-right corner and LEFT's middle stack; the front 19 is its cover-tray partner.
  assert.deepEqual([block.rule.height, block.rule.partner, block.rule.full_heights], [20, 19, [19, 20]]);
  assert.deepEqual([block.status, block.total_trays, block.rule.withheld_reason], ['conflict', null, 'back_corner_below_rule_height']);
  assert.match(block.conflicts[0].reason, /^LEFT: the back corner stack at \(0, 2\) reads 18, below the block's full height \(19 or 20/);
  assert.deepEqual(block.rescan_cells, [[0, 2]]);
  const r = grid(block);
  assert.deepEqual([r.status, r.total, r.rule.withheld_reason], ['conflict', null, 'back_corner_below_rule_height']);
  assert.deepEqual([r.rule.provisional.counted_on_faces, r.rule.provisional.at_rule_height, r.rule.provisional.at_rule_range], [157, 237, [233, 237]]);
  // The provisional figures never reach the inventory (app 0.6.x would title them "depth not proven").
  assert.deepEqual([r.inventory.released, r.inventory.provisional, r.inventory.estimated_total], [false, null, null]);
});

test('H3: a set-back side stack is a seen gap; the trays seen through it are a hint, never counted; a back row with a gap gives no H', () => {
  const block = buildBlock(front(20, 20, 20, 20), left(20, 17), right(20, {layers: 16, pitch: 30}));
  const r = grid(block);
  assert.deepEqual([cellAt(r, 3, 1).evidence_class, cellAt(r, 3, 1).z_layers, cellAt(r, 3, 1).status], ['seen_empty', 0, 'missing']);
  const behind = cellAt(r, 2, 1);
  assert.deepEqual([behind.past_gap_layers, behind.past_gap_scale, behind.hidden], [16, 0.75, true]);
  assert.ok(behind.flags.includes('line_of_sight_past_gap'));
  assert.ok(behind.uncertainties.some(u => u.startsWith('16 trays seen through the gap')));
  // The back row reads 17 and a gap: no back corner at a height two faces agree on, so no full height and no total.
  assert.deepEqual([block.rule.height, block.rule.withheld_reason, r.total], [null, 'no_rule_height', null]);
  assert.deepEqual(r.rule.provisional.at_typical_face_height, {height: 20, estimated_total: 137});
});

test('H3b: trays glimpsed through a gap below the full height withhold the total (a short hidden stack, or another block)', () => {
  const block = buildBlock(front(20, 20, 20, 20), left(20, 20, 20), right(20, {layers: 16, pitch: 30}, 20));
  assert.deepEqual([block.rule.height, block.rule.withheld_reason, block.total_trays], [20, 'inside_hint_below_rule', null]);
  assert.match(block.conflicts.find(c => c.check).reason, /^RIGHT: trays seen through a gap in front of the hidden stack at \(2, 1\) read 16/);
  assert.deepEqual(block.rule.hints_below, [{x: 2, y: 1, face: 'right', layers: 16}]);
});

test('H4: with one side photographed, (X-1)(Y-1) stacks are hidden and the block is withheld (Decision 7: partials may stand there)', () => {
  const block = buildBlock(front(20, {layers: 16, pitch: 30}, 20), left(20, 19), []);
  const r = grid(block);
  assert.deepEqual(r.grid.flat().filter(g => g.hidden).map(g => [g.x, g.y]), [[1, 1], [2, 1]]);
  assert.deepEqual([block.rule.one_side, block.rule.withheld_reason, r.total], ['right', 'one_side_only', null]);
  assert.match(block.conflicts[0].reason, /^RIGHT: only one side face was photographed/);
});

test('H5: typical_layers is H when the rule applies and the mode of the face stacks (ties to the lower) when nothing is hidden', () => {
  assert.equal(mode([19, 19, 20, 20, 21]), 19);
  assert.equal(mode([18, 20, 20]), 20);
  assert.equal(mode([]), null);
  const row = buildBlock(front(19, 19, 20, 20, 21), left(19), right(21));
  assert.deepEqual([row.rule.applied, row.typical_layers, row.total_trays], [false, 19, 99]);
  // Decision 7's other answer (a wall side never holds partials) fills the unseen side column by the rule.
  const oneSide = (opts) => buildBlock(front(20, 20, 20), left(20, 20, 20), [], {}, null, {}, {rule: opts});
  assert.deepEqual([oneSide({}).total_trays, oneSide({}).rule.withheld_reason], [null, 'one_side_only']);
  const wall = oneSide({oneSide: 'wall_full'});
  assert.deepEqual([wall.typical_layers, wall.computed_trays, wall.total_trays, wall.rule.withheld_reason], [20, 80, 180, null]);
});

// A 3 x 2 block whose visible stacks are all verified and whose one hidden stack (1,1) has neighbours 20, 20 and 20.
const cell = (x, y, status, layers, verified = status === 'observed') => ({x, y, status, layers, source: 'faces', verified,
  readings: status === 'observed' ? [{view: 'straight', capture_id: 'a', evidence: {gap_filled: 0, doubts: []}}] : []});
const verified3x2 = (front1 = ['observed', 20]) => blockResult(3, 2, ['straight', 'left', 'right'], 20,
  [cell(0, 0, 'observed', 20), cell(1, 0, ...front1), cell(2, 0, 'observed', 20),
   cell(0, 1, 'observed', 20), cell(1, 1, 'computed', 20, false), cell(2, 1, 'observed', 20)], []);
const tap = (state, x = 1, y = 1) => ({x: 3, y: 2, cells: [{x, y, state}]});
const declaration = (over = {}) => ({x: 3, y: 2, interior: 'unknown', missing_cells: [], partial_stacks: [], cover_trays: 'unknown',
  occupancy: 'unknown', reference_height: null, operator: 'op1', declared_at: null, ...over});

test('H6: a top-view tap changes presence and steps only; it never counts and never raises the status', () => {
  const plain = grid(verified3x2());
  // 0.7.0: an ELEVATED photo is never suggested (farm rule 5: photos from above are impractical).
  assert.deepEqual([plain.status, plain.total, plain.suggested_views], ['estimated', 120, []]);
  const present = grid(verified3x2(), {topView: tap('present')});
  assert.deepEqual([present.status, present.total, cellAt(present, 1, 1).evidence_class, cellAt(present, 1, 1).assumed_range],
    ['estimated', 120, 'top_present', [20, 20]]);
  assert.deepEqual([present.inventory.hidden_stacks_top_checked, present.inventory.unchecked_hidden_stacks, present.suggested_views], [1, 0, []]);
  assert.deepEqual([cellAt(present, 1, 1).status, cellAt(present, 1, 1).measurement_sources, cellAt(present, 1, 1).top_tap],
    ['top_view', ['top_view', 'computed'], 'present']);
  assert.match(cellAt(present, 1, 1).uncertainties[0], /^seen from above: presence only; height full by the stacking rule/);
  // A hole seen from above is an operator-reported exception to the rule: honoured, and named.
  const missing = grid(verified3x2(), {topView: tap('missing')});
  assert.deepEqual([missing.total, cellAt(missing, 1, 1).evidence_class, missing.inventory.missing_stacks.top_missing,
    missing.inventory.assumed_stacks, missing.computed_trays], [100, 'top_missing', 1, 0, 0]);
  assert.ok(cellAt(missing, 1, 1).flags.includes('rule_exception'));
  assert.deepEqual([missing.rule.exceptions, missing.inventory.rule_exceptions], [[{x: 1, y: 1, kind: 'top_missing', layers: 0}], 1]);
  // 0.7.0: a hidden stack taller than its neighbours means the full height may be too low: withheld (0.6.0 released 121).
  const up = grid(verified3x2(), {topView: tap('step_up')});
  assert.deepEqual([up.status, up.total, cellAt(up, 1, 1).z_layers, up.rule.withheld_reason], ['conflict', null, 21, 'inside_step_up']);
  assert.ok(cellAt(up, 1, 1).flags.includes('step_up_count_unknown'));
  assert.equal(up.rule.provisional.at_rule_height, 120);
  const down = grid(verified3x2(), {topView: tap('step_down')});
  assert.deepEqual([down.status, down.total, cellAt(down, 1, 1).z_layers, down.inventory.estimated_range], ['estimated', null, null, null]);
  assert.deepEqual([down.inventory.released, down.inventory.withheld_reason, down.inventory.provisional, down.computed_trays],
    [false, 'height_unknown', null, 0]);
  assert.deepEqual([down.inventory.assumed_trays, down.inventory.estimated_total, down.inventory.counted_trays], [null, null, 100]);
  const unsure = grid(verified3x2(), {topView: tap('unsure')});
  assert.deepEqual([unsure.total, unsure.inventory.hidden_stacks_top_checked, unsure.inventory.unchecked_hidden_stacks], [120, 0, 1]);
  assert.deepEqual(cellAt(unsure, 1, 1).flags, ['top_unsure']);
  const twice = (a, b) => grid(verified3x2(), {topView: {x: 3, y: 2, cells: [{x: 1, y: 1, state: a}, {x: 1, y: 1, state: b}]}});
  const disagree = twice('missing', 'present');
  assert.deepEqual([disagree.status, disagree.total], ['conflict', null]);
  assert.match(disagree.conflicts[0].reason, /tapped both missing and present/);
  const repeated = twice('present', 'present');
  assert.deepEqual([repeated.status, repeated.total, repeated.top_view.cells_present], ['estimated', 120, 1]);
});

test('H7: taps never change a face count: a contradiction is a conflict, a step a note', () => {
  const gap = verified3x2(['missing', 0]);
  assert.equal(grid(gap, {topView: tap('present', 1, 0)}).status, 'conflict');
  assert.equal(grid(gap, {topView: tap('missing', 1, 0)}).status, 'estimated');
  assert.equal(grid(verified3x2(), {topView: tap('missing', 0, 0)}).status, 'conflict');
  assert.equal(grid(verified3x2(), {topView: {x: 4, y: 2, cells: []}}).status, 'conflict');
  const step = grid(verified3x2(), {topView: tap('step_up', 0, 0)});
  assert.deepEqual([step.status, cellAt(step, 0, 0).z_layers, cellAt(step, 0, 0).evidence_class, step.total], ['estimated', 20, 'measured', 120]);
  assert.ok(cellAt(step, 0, 0).uncertainties.some(u => u.startsWith('ELEVATED: higher than its neighbours')));
});

test('H8: the declaration removes, sizes or flags hidden stacks, never counts them, and never overrides a tap', () => {
  const full = grid(verified3x2(), {declaration: declaration({interior: 'full'})});
  assert.deepEqual([full.status, cellAt(full, 1, 1).measurement_sources, cellAt(full, 1, 1).status], ['estimated', ['computed', 'declared'], 'computed']);
  assert.equal(full.rule.affirmed_by_operator, true);
  assert.ok(cellAt(full, 1, 1).flags.includes('declared_present'));
  const egg = gridInventory(full.grid, declaration({interior: 'full', occupancy: 'egg_filled'}), full.total, {status: full.status});
  assert.equal(egg.eligible_egg_trays.value, null); assert.match(egg.eligible_egg_trays.note, /assumed/);
  const gone = grid(verified3x2(), {declaration: declaration({missing_cells: [[1, 1]]})});
  assert.deepEqual([gone.status, gone.total, cellAt(gone, 1, 1).evidence_class, cellAt(gone, 1, 1).status], ['estimated', 100, 'declared_missing', 'declared']);
  assert.ok(cellAt(gone, 1, 1).flags.includes('rule_exception'));
  // Exceptions to the rule with a height are honoured (Decision 8 (a)); 0.7.0 gives no neighbour range for them.
  const partial = grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 12}]})});
  assert.deepEqual([partial.total, partial.inventory.estimated_range, cellAt(partial, 1, 1).status, cellAt(partial, 1, 1).assumed_from],
    [112, null, 'declared', 'declared_partial']);
  assert.deepEqual([partial.inventory.rule_exceptions, partial.inventory.rule_stacks, partial.inventory.note],
    [1, 0, '100 counted on faces; 1 hidden stack at the declared height']);
  const unsized = grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: null}]})});
  assert.deepEqual([unsized.total, unsized.inventory.estimated_range, cellAt(unsized, 1, 1).status], [null, null, 'unknown']);
  assert.equal(grid(verified3x2(), {declaration: declaration({missing_cells: [[1, 1]]}), topView: tap('present')}).status, 'conflict');
  assert.equal(grid(verified3x2(), {declaration: declaration({interior: 'full'}), topView: tap('missing')}).status, 'conflict');
  assert.equal(grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 12}]}), topView: tap('missing')}).status, 'conflict');
  assert.equal(grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 12}]}), topView: tap('step_up')}).status, 'conflict');
  assert.equal(grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 22}]}), topView: tap('step_down')}).status, 'conflict');
  // Declared missing where the top view also shows a hole: one removed stack, both sources named.
  const both = grid(verified3x2(), {declaration: declaration({missing_cells: [[1, 1]]}), topView: tap('missing')});
  assert.deepEqual([both.total, cellAt(both, 1, 1).evidence_class, cellAt(both, 1, 1).measurement_sources], [100, 'top_missing', ['top_view', 'declared']]);
  // 0.7.0: "partly empty" without naming the stacks leaves the rule nothing to set: withheld (0.6.0 released 120, range 100-120).
  const partly = grid(verified3x2(), {declaration: declaration({interior: 'partial'})});
  assert.deepEqual([partly.status, partly.total, partly.rule.withheld_reason], ['conflict', null, 'inside_declared_partial']);
  const partlySeen = grid(verified3x2(), {declaration: declaration({interior: 'partial'}), topView: tap('present')});
  assert.deepEqual([partlySeen.total, partlySeen.rule.withheld_reason], [null, 'inside_declared_partial']);
  // A one-stack block read by two captures, occupancy and covers declared: the only case with eligible egg trays.
  const one = blockResult(1, 1, ['straight', 'left', 'right'], 20, [cell(0, 0, 'observed', 20)], []);
  const decl = declaration({x: 1, y: 1, occupancy: 'egg_filled', cover_trays: 'no'});
  const single = assembleGrid(one, {declaration: decl, topView: null, corner: null});
  const inv = gridInventory(single.grid, decl, single.total, {status: single.status});
  assert.deepEqual([single.status, inv.eligible_egg_trays.value, inv.eligible_egg_trays.basis, inv.cover_trays], ['exact', 20, 'declared', {value: 0, basis: 'declared'}]);
});

test('H9: a block with hidden stacks is never confirmed or exact, whatever the declaration, taps or CORNER photo say', () => {
  const block = buildBlock(front(15, 15, 15, 15), left(15, 15, 15), right(15, 15, 15));
  const allPresent = {x: 4, y: 3, cells: Array.from({length: 12}, (_, i) => ({x: i % 4, y: Math.floor(i / 4), state: 'present'}))};
  const decl = {...declaration({x: 4, y: 3, interior: 'full'})};
  for (let mask = 0; mask < 16; mask++) for (const depthBasis of [undefined, 'declaration', 'corner_and_declaration']) {
    const r = grid(block, {declaration: mask & 1 ? decl : null, topView: mask & 2 ? allPresent : null,
      corner: mask & 4 ? {side: 'front_left', x: 4, y: 3} : null, ...(mask & 8 && depthBasis ? {depthBasis} : {})});
    assert.ok(!['confirmed', 'exact'].includes(r.status), `${mask} ${depthBasis}: ${r.status}`);
    assert.deepEqual(r.confirmed_basis, []);
  }
  // exact is for one-deep blocks: a 1 x 2 block read the same by two photos everywhere is exact at the block level only.
  const deep = buildBlock(front(20), left(20, 18), right(20, 18));
  assert.equal(deep.status, 'exact');
  assert.equal(grid(deep).status, 'estimated');
  // Even when a caller says one_deep: a block more than one stack deep is never exact.
  assert.equal(grid(deep, {depthBasis: 'one_deep'}).status, 'estimated');
});

test('H14: a declared partial stack of 0 trays is a missing stack; declared heights that disagree are a conflict', () => {
  const read = (d) => { const f = new FormData(); f.set('block_declaration', JSON.stringify({x: 3, y: 2, ...d})); return readDeclaration(f); };
  const zero = read({partial_stacks: [{x: 1, y: 1, layers: 0}], missing_cells: [[1, 1]]});
  assert.deepEqual([zero.missing_cells, zero.partial_stacks], [[[1, 1]], []]);
  const gone = grid(verified3x2(), {declaration: read({partial_stacks: [{x: 1, y: 1, layers: 0}]})});
  assert.deepEqual([gone.status, gone.total, cellAt(gone, 1, 1).evidence_class, gone.inventory.assumed_stacks, gone.inventory.missing_stacks.declared_missing],
    ['estimated', 100, 'declared_missing', 0, 1]);
  // Declared missing where the top view shows a hole, listed twice: the source is named once.
  const twiceMissing = grid(verified3x2(), {declaration: read({missing_cells: [[1, 1], [1, 1]]}), topView: tap('missing')});
  assert.deepEqual(cellAt(twiceMissing, 1, 1).measurement_sources, ['top_view', 'declared']);
  // Two different heights for one stack disagree; the same height twice is one entry.
  const differ = grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 12}, {x: 1, y: 1, layers: 5}]})});
  assert.deepEqual([differ.status, differ.total, cellAt(differ, 1, 1).evidence_class], ['conflict', null, 'conflict']);
  assert.match(differ.conflicts[0].reason, /^declared two partial heights for one stack \(12 and 5\)/);
  const same = grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 12}, {x: 1, y: 1, layers: 12}]})});
  assert.deepEqual([same.status, same.total], ['estimated', 112]);
  // A face that shows a gap disagrees with any declared stack there, with or without a height.
  const gap = verified3x2(['missing', 0]);
  for (const layers of [null, 12]) {
    const r = grid(gap, {declaration: declaration({partial_stacks: [{x: 1, y: 0, layers}]})});
    assert.deepEqual([r.status, r.declaration_agrees], ['conflict', false], String(layers));
    assert.match(r.conflicts[0].reason, /^declared a partial stack, but a face shows a gap there/);
  }
  // On a face that shows a stack, a partial with no height is presence only and agrees.
  assert.equal(grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 0, y: 0, layers: null}]})}).status, 'estimated');
});
