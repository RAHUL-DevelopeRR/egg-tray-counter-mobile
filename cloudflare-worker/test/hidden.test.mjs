import assert from 'node:assert/strict';
import test from 'node:test';
import { assembleGrid, blockResult, buildBlock, gridInventory, mode, spanColumns } from '../dist/index.js';

// ---- 0.6.0 hidden-tray calculation (docs/GRID_CONTRACT_0.6.0.md): a stack no face photo counts gets an assumed
// height from its line-of-sight neighbours, kept apart from the counted trays; a top-view tap changes presence and steps
// only. These tests run buildBlock + assembleGrid with no depth proof applied (the side check is side_check.test.mjs).
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
  return {...result, inventory: gridInventory(result.grid, inputs.declaration ?? null, result.total, {status: result.status})};
};
const cellAt = (result, x, y) => result.grid[y][x];

test('H1: a 4x3 block of 15s keeps 120 counted on faces and 60 assumed in the (4-2)(3-1) = 4 hidden stacks', () => {
  const block = buildBlock(front(15, 15, 15, 15), left(15, 15, 15), right(15, 15, 15));
  assert.deepEqual([block.observed_trays, block.computed_trays, block.total_trays], [120, 60, 180]);
  const r = grid(block);
  assert.deepEqual([r.status, r.total, r.confirmed_basis], ['estimated', 180, []]);
  const hidden = r.grid.flat().filter(g => g.hidden);
  assert.deepEqual(hidden.map(g => [g.x, g.y]), [[1, 1], [2, 1], [1, 2], [2, 2]]);
  for (const g of hidden) {
    assert.deepEqual([g.evidence_class, g.z_layers, g.assumed_layers, g.assumed_range, g.assumed_from, g.neighbours.length, g.status],
      ['assumed', 15, 15, [15, 15], 'neighbours', 3, 'computed'], `${g.x},${g.y}`);
    assert.deepEqual(g.measurement_sources, ['computed']);
  }
  const inv = r.inventory;
  assert.deepEqual([inv.counted_trays, inv.counted_stacks, inv.assumed_trays, inv.assumed_stacks, inv.estimated_total],
    [120, 8, 60, 4, 180]);
  assert.deepEqual([inv.assumed_range, inv.estimated_range], [[60, 60], [180, 180]]);
  assert.deepEqual([inv.hidden_stacks, inv.hidden_stacks_top_checked, inv.unchecked_hidden_stacks], [4, 0, 4]);
  assert.deepEqual([inv.unit, inv.released, inv.withheld_reason], ['tray_layers', true, null]);
  assert.equal(inv.note, '120 counted on faces; 60 assumed in 4 hidden stacks, none checked from the top');
  assert.equal(r.computed_trays, 60);
});

test('H2: each hidden stack takes the median of its front stack and side end stacks; the range is their spread', () => {
  const block = buildBlock(front(20, 19, 20, 20), left(20, 20, 18), right(20, 20, 20));
  const r = grid(block);
  const seen = [[1, 1], [2, 1], [1, 2], [2, 2]].map(([x, y]) => [cellAt(r, x, y).z_layers, cellAt(r, x, y).assumed_range]);
  assert.deepEqual(seen, [[20, [19, 20]], [20, [20, 20]], [19, [18, 20]], [20, [18, 20]]]);
  assert.deepEqual(cellAt(r, 1, 2).neighbours, [{x: 1, y: 0, layers: 19}, {x: 0, y: 2, layers: 18}, {x: 3, y: 2, layers: 20}]);
  const inv = r.inventory;
  assert.deepEqual([inv.counted_trays, inv.assumed_trays, inv.assumed_range], [157, 79, [75, 80]]);
  // 0.5.0 gave 237 (every hidden stack at the median face height, 20).
  assert.deepEqual([r.total, inv.estimated_total, inv.estimated_range], [236, 236, [232, 237]]);
  assert.equal(inv.note, '157 counted on faces; 79 assumed in 4 hidden stacks, none checked from the top');
});

test('H3: a set-back side stack is a seen gap; the trays seen through it are a hint on the stack behind, never counted', () => {
  const block = buildBlock(front(20, 20, 20, 20), left(20, 17), right(20, {layers: 16, pitch: 30}));
  const r = grid(block);
  assert.deepEqual([cellAt(r, 3, 1).evidence_class, cellAt(r, 3, 1).z_layers, cellAt(r, 3, 1).status], ['seen_empty', 0, 'missing']);
  assert.deepEqual([cellAt(r, 1, 1).z_layers, cellAt(r, 1, 1).assumed_range], [18, [17, 20]]);
  const behind = cellAt(r, 2, 1);
  assert.deepEqual([behind.z_layers, behind.assumed_range, behind.past_gap_layers, behind.past_gap_scale, behind.hidden],
    [18, [0, 20], 16, 0.75, true]);
  assert.ok(behind.flags.includes('line_of_sight_past_gap'));
  assert.ok(behind.uncertainties.some(u => u.startsWith('16 trays seen through the gap')));
  assert.deepEqual([r.inventory.counted_trays, r.total, r.inventory.estimated_range], [97, 133, [114, 137]]);
  assert.deepEqual(r.inventory.missing_stacks, {seen_empty: 1, top_missing: 0, declared_missing: 0});
});

test('H4: with one side photographed, (X-1)(Y-1) stacks are hidden; one neighbour is flagged', () => {
  const block = buildBlock(front(20, {layers: 16, pitch: 30}, 20), left(20, 19), []);
  const r = grid(block);
  assert.deepEqual(r.grid.flat().filter(g => g.hidden).map(g => [g.x, g.y]), [[1, 1], [2, 1]]);
  const gapBehind = cellAt(r, 1, 1);
  assert.deepEqual([gapBehind.z_layers, gapBehind.assumed_range, gapBehind.past_gap_layers], [19, [0, 19], 16]);
  assert.ok(gapBehind.flags.includes('single_neighbour'));
  assert.deepEqual([cellAt(r, 2, 1).z_layers, cellAt(r, 2, 1).assumed_range], [19, [19, 20]]);
  assert.deepEqual([r.inventory.counted_trays, r.total, r.inventory.estimated_range], [59, 97, [78, 98]]);
});

test('H5: the fallback height is the mode of the measured stacks, ties to the lower', () => {
  assert.equal(mode([19, 19, 20, 20, 21]), 19);
  assert.equal(mode([18, 20, 20]), 20);
  assert.equal(mode([]), null);
  // Both line-of-sight neighbours of (1,1) are gaps: the block's typical face height (20).
  const straight = front(20, {layers: 18, pitch: 30}, 20);
  const block = buildBlock(straight, face({layers: 18, pitch: 30}, 20), []);
  const g = block.cells.find(c => c.x === 1 && c.y === 1);
  assert.deepEqual([g.assumed_from, g.layers, g.flags], ['face_typical', 20, ['line_of_sight_past_gap', 'no_neighbour']]);
  assert.equal(block.typical_layers, 20);
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
  assert.deepEqual([plain.status, plain.total, plain.suggested_views], ['estimated', 120, ['elevated']]);
  const present = grid(verified3x2(), {topView: tap('present')});
  assert.deepEqual([present.status, present.total, cellAt(present, 1, 1).evidence_class, cellAt(present, 1, 1).assumed_range],
    ['estimated', 120, 'top_present', [20, 20]]);
  assert.deepEqual([present.inventory.hidden_stacks_top_checked, present.inventory.unchecked_hidden_stacks, present.suggested_views], [1, 0, []]);
  assert.deepEqual([cellAt(present, 1, 1).status, cellAt(present, 1, 1).measurement_sources, cellAt(present, 1, 1).top_tap],
    ['top_view', ['top_view', 'computed'], 'present']);
  assert.match(cellAt(present, 1, 1).uncertainties[0], /^seen from above: presence only; height assumed from neighbours/);
  const missing = grid(verified3x2(), {topView: tap('missing')});
  assert.deepEqual([missing.total, cellAt(missing, 1, 1).evidence_class, missing.inventory.missing_stacks.top_missing,
    missing.inventory.assumed_stacks, missing.computed_trays], [100, 'top_missing', 1, 0, 0]);
  const up = grid(verified3x2(), {topView: tap('step_up')});
  assert.deepEqual([up.total, cellAt(up, 1, 1).z_layers, cellAt(up, 1, 1).assumed_range, up.inventory.estimated_range],
    [121, 21, [21, null], [121, null]]);
  assert.ok(cellAt(up, 1, 1).flags.includes('step_up_count_unknown'));
  const down = grid(verified3x2(), {topView: tap('step_down')});
  assert.deepEqual([down.status, down.total, cellAt(down, 1, 1).z_layers, down.inventory.estimated_range], ['estimated', null, null, [101, 120]]);
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
  assert.ok(cellAt(full, 1, 1).flags.includes('declared_present'));
  const egg = gridInventory(full.grid, declaration({interior: 'full', occupancy: 'egg_filled'}), full.total, {status: full.status});
  assert.equal(egg.eligible_egg_trays.value, null); assert.match(egg.eligible_egg_trays.note, /assumed/);
  const gone = grid(verified3x2(), {declaration: declaration({missing_cells: [[1, 1]]})});
  assert.deepEqual([gone.status, gone.total, cellAt(gone, 1, 1).evidence_class, cellAt(gone, 1, 1).status], ['estimated', 100, 'declared_missing', 'declared']);
  const partial = grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 12}]})});
  assert.deepEqual([partial.total, partial.inventory.estimated_range, cellAt(partial, 1, 1).status, cellAt(partial, 1, 1).assumed_from],
    [112, [112, 112], 'declared', 'declared_partial']);
  const unsized = grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: null}]})});
  assert.deepEqual([unsized.total, unsized.inventory.estimated_range, cellAt(unsized, 1, 1).status], [null, [101, 120], 'unknown']);
  assert.equal(grid(verified3x2(), {declaration: declaration({missing_cells: [[1, 1]]}), topView: tap('present')}).status, 'conflict');
  assert.equal(grid(verified3x2(), {declaration: declaration({interior: 'full'}), topView: tap('missing')}).status, 'conflict');
  assert.equal(grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 12}]}), topView: tap('missing')}).status, 'conflict');
  assert.equal(grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 12}]}), topView: tap('step_up')}).status, 'conflict');
  assert.equal(grid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 22}]}), topView: tap('step_down')}).status, 'conflict');
  // Declared missing where the top view also shows a hole: one removed stack, both sources named.
  const both = grid(verified3x2(), {declaration: declaration({missing_cells: [[1, 1]]}), topView: tap('missing')});
  assert.deepEqual([both.total, cellAt(both, 1, 1).evidence_class, cellAt(both, 1, 1).measurement_sources], [100, 'top_missing', ['top_view', 'declared']]);
  const partly = grid(verified3x2(), {declaration: declaration({interior: 'partial'})});
  assert.deepEqual([partly.total, partly.inventory.estimated_range], [120, [100, 120]]);
  const partlySeen = grid(verified3x2(), {declaration: declaration({interior: 'partial'}), topView: tap('present')});
  assert.deepEqual(partlySeen.inventory.estimated_range, [101, 120]);
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
});
