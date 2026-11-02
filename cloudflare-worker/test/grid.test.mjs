import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { assembleGrid, blockResult, buildBlock, cornerReading, gridInventory, readDeclaration, readTopViewTaps,
  spanColumns } from '../dist/index.js';

// ---- 0.5.0 physical grid, declaration and extra views (docs/GRID_CONTRACT_0.5.0.md).
const tray = (layers, {x = 100, pitch = 40, height = 36} = {}) =>
  Array.from({length: layers}, (_, k) => ({class: 'egg_tray', confidence: .9, x, y: 100 + k * pitch, width: 80, height}));
const faceOf = (...stacks) => spanColumns(stacks.flatMap((layers, i) => tray(layers, {x: 100 + i * 100})));
const cell = (x, y, status, layers, verified = status === 'observed') => ({x, y, status, layers, source: 'faces', verified,
  readings: status === 'observed' ? [{view: 'straight', capture_id: 'a', evidence: {gap_filled: 0, doubts: []}}] : []});
// A 3 x 2 block whose visible stacks are all verified and whose one hidden stack is computed (the case F and N resolve).
const verified3x2 = () => blockResult(3, 2, ['straight', 'left', 'right'], 20,
  [cell(0, 0, 'observed', 20), cell(1, 0, 'observed', 20), cell(2, 0, 'observed', 20),
   cell(0, 1, 'observed', 20), cell(1, 1, 'computed', 20, false), cell(2, 1, 'observed', 20)], []);
const declaration = (over = {}) => ({x: 3, y: 2, interior: 'full', missing_cells: [], partial_stacks: [], cover_trays: 'no',
  occupancy: 'unknown', reference_height: null, operator: 'op1', declared_at: '2026-11-01T10:00:00Z', ...over});

test('every reading names its capture, reader and evidence; one capture never verifies a stack twice', () => {
  const block = buildBlock(faceOf(20, 20), faceOf(20), faceOf(20), {}, null, {},
    {captureIds: {straight: 'c1', left: 'c2', right: 'c1'}, quality: {straight: 'accepted', left: 'accepted', right: 'accepted'}});
  const corner = block.cells.find(c => c.x === 0 && c.y === 0);
  assert.deepEqual(Object.keys(corner.readings[0]).sort(), ['capture_id', 'count', 'doubts', 'evidence', 'face', 'gap_filled', 'layers',
    'physical_stack_id', 'pipeline_version', 'quality', 'reader', 'trusted', 'view'].sort());
  assert.deepEqual([corner.readings[0].reader, corner.readings[0].physical_stack_id, corner.readings[0].pipeline_version], ['rf-walk', 'S0-0', 'worker-0.5.1']);
  assert.equal(corner.verified, true);                       // STRAIGHT (c1) and LEFT (c2)
  assert.equal(block.cells.find(c => c.x === 1).verified, false);  // STRAIGHT and RIGHT are the same capture (c1)
});

test('the grid holds one physical stack per cell: a corner seen by two faces is one stack, and sources stay apart', () => {
  const block = buildBlock(faceOf(20, 20, 20), faceOf(20, 20), faceOf(20, 20));
  const {grid, status, total} = assembleGrid(block, {declaration: null, topView: null, corner: null});
  assert.equal(grid.length, 2); assert.equal(grid[0].length, 3);
  assert.deepEqual(grid[0][0].observed_views, ['straight', 'left']);
  assert.deepEqual([grid[1][1].status, grid[1][1].measurement_sources, grid[1][1].stack_present], ['computed', ['computed'], null]);
  assert.ok(grid[1][1].uncertainties.some(u => u.includes('hidden')));
  assert.equal(total, 120); assert.equal(status, 'estimated');
  const inventory = gridInventory(grid, null, total);
  assert.deepEqual([inventory.physical_layers_observed, inventory.physical_layers_computed], [100, 20]);
  // Occupancy is not measured: eligible egg trays stay unknown until declared.
  assert.deepEqual(inventory.eligible_egg_trays.value, null); assert.equal(inventory.unknown_occupancy_layers, 120);
});

test('a declaration that agrees with every face and declares the interior full confirms, and says so', () => {
  const result = assembleGrid(verified3x2(), {declaration: declaration(), topView: null, corner: null});
  assert.equal(result.status, 'confirmed'); assert.deepEqual(result.confirmed_basis, ['declaration']);
  assert.equal(result.declaration_agrees, true);
  assert.deepEqual(result.grid[1][1].measurement_sources, ['declared', 'computed']);
  const inventory = gridInventory(result.grid, declaration({occupancy: 'egg_filled'}), result.total);
  assert.deepEqual(inventory.eligible_egg_trays, {value: 120, basis: 'declared',
    note: 'the operator declared that every counted tray holds eggs; occupancy is not measured'});
});

test('a declaration never makes a result exact, and cannot confirm stacks read by one photo only', () => {
  const block = buildBlock(faceOf(20, 20, 20), faceOf(20, 20), faceOf(20, 20));   // front-middle seen once
  const result = assembleGrid(block, {declaration: declaration(), topView: null, corner: null});
  assert.equal(result.status, 'estimated'); assert.deepEqual(result.confirmed_basis, []);
  // A one-deep block seen twice everywhere is exact from the photos alone; the declaration changes nothing.
  const oneDeep = buildBlock(faceOf(20), faceOf(20), faceOf(20));
  assert.equal(assembleGrid(oneDeep, {declaration: declaration({x: 1, y: 1}), topView: null, corner: null}).status, 'exact');
});

test('declared size, missing cells and partial stacks that contradict the photos are conflicts, with no total', () => {
  const wide = assembleGrid(verified3x2(), {declaration: declaration({x: 4}), topView: null, corner: null});
  assert.equal(wide.status, 'conflict'); assert.equal(wide.total, null); assert.equal(wide.declaration_agrees, false);
  assert.match(wide.conflicts[0].reason, /declared 4 stacks wide, STRAIGHT shows 3/);
  const seen = assembleGrid(verified3x2(), {declaration: declaration({missing_cells: [[0, 0]]}), topView: null, corner: null});
  assert.equal(seen.status, 'conflict');
  // A declared missing hidden stack removes it; a declared partial hidden stack takes the declared height.
  const missing = assembleGrid(verified3x2(), {declaration: declaration({missing_cells: [[1, 1]]}), topView: null, corner: null});
  assert.deepEqual([missing.total, missing.grid[1][1].z_layers, missing.grid[1][1].stack_present], [100, 0, false]);
  const partial = assembleGrid(verified3x2(), {declaration: declaration({partial_stacks: [{x: 1, y: 1, layers: 12}]}), topView: null, corner: null});
  assert.deepEqual([partial.total, partial.grid[1][1].status], [112, 'declared']);
});

test('a measured reference height only demotes: a visible stack below it blocks confirmed and adds nothing', () => {
  const block = blockResult(3, 2, ['straight', 'left', 'right'], 20,
    [cell(0, 0, 'observed', 20), cell(1, 0, 'observed', 18), cell(2, 0, 'observed', 20),
     cell(0, 1, 'observed', 20), cell(1, 1, 'computed', 20, false), cell(2, 1, 'observed', 20)], []);
  const result = assembleGrid(block, {declaration: declaration({reference_height: 20}), topView: null, corner: null});
  assert.equal(result.status, 'estimated'); assert.equal(result.total, 118);
  assert.ok(result.grid[0][1].uncertainties.some(u => u.includes('reference height')));
});

test('elevated taps: a flush hidden stack confirms on the top view; a step makes it unknown; a wrong grid is a conflict', () => {
  const present = assembleGrid(verified3x2(), {declaration: null, topView: {x: 3, y: 2, cells: [{x: 1, y: 1, state: 'present'}]}, corner: null});
  assert.equal(present.status, 'confirmed'); assert.deepEqual(present.confirmed_basis, ['top_view']);
  assert.ok(present.grid[1][1].uncertainties[0].includes('conditional'));
  const step = assembleGrid(verified3x2(), {declaration: null, topView: {x: 3, y: 2, cells: [{x: 1, y: 1, state: 'step_down'}]}, corner: null});
  assert.deepEqual([step.status, step.total, step.grid[1][1].z_layers], ['estimated', null, null]);
  const missing = assembleGrid(verified3x2(), {declaration: null, topView: {x: 3, y: 2, cells: [{x: 1, y: 1, state: 'missing'}]}, corner: null});
  assert.deepEqual([missing.total, missing.top_view.cells_missing], [100, 1]);
  const wrong = assembleGrid(verified3x2(), {declaration: null, topView: {x: 4, y: 2, cells: []}, corner: null});
  assert.equal(wrong.status, 'conflict');
  const seen = assembleGrid(verified3x2(), {declaration: null, topView: {x: 3, y: 2, cells: [{x: 0, y: 0, state: 'missing'}]}, corner: null});
  assert.equal(seen.status, 'conflict');
});

test('a CORNER photo gives width and depth around its nearest (largest-pitch) stack; a mismatch is a conflict', () => {
  // Front-left corner: LEFT face (2 deep) on the left, the corner stack largest, the front (3 wide) on the right.
  const cols = spanColumns([...tray(10, {x: 100, pitch: 30, height: 27}), ...tray(10, {x: 200, pitch: 45}),
    ...tray(10, {x: 300, pitch: 38, height: 34}), ...tray(10, {x: 400, pitch: 32, height: 29})]);
  assert.deepEqual((({x, y, corner_column}) => [x, y, corner_column])(cornerReading(cols, 'front_left')), [3, 2, 2]);
  assert.deepEqual((({x, y}) => [x, y])(cornerReading(cols, 'front_right')), [2, 3]);
  assert.equal(cornerReading(cols, null).x, null);
  const block = buildBlock(faceOf(20, 20, 20), faceOf(20, 20), faceOf(20, 20));
  assert.equal(assembleGrid(block, {declaration: null, topView: null, corner: cornerReading(cols, 'front_left')}).corner_agrees, true);
  const off = assembleGrid(block, {declaration: null, topView: null, corner: {...cornerReading(cols, 'front_left'), x: 4}});
  assert.equal(off.status, 'conflict'); assert.match(off.conflicts[0].reason, /^CORNER shows 4 stacks wide/);
});

test('declarations and taps are validated; malformed input is no evidence, never a refusal', () => {
  const form = (fields) => { const f = new FormData(); for (const [k, v] of Object.entries(fields)) f.set(k, v); return f; };
  assert.equal(readDeclaration(form({block_declaration: '{bad'})), null);
  assert.equal(readDeclaration(form({block_declaration: JSON.stringify({x: 0, y: 2})})), null);
  const d = readDeclaration(form({block_declaration: JSON.stringify({x: 3, y: 2, interior: 'weird', missing_cells: [[9, 9], [1, 1]],
    reference_height: 20, reference_height_measured: false, operator: 'a\u0000b'})}));
  assert.deepEqual([d.interior, d.missing_cells, d.reference_height, d.operator], ['unknown', [[1, 1]], null, 'a b']);
  assert.equal(readDeclaration(form({block_declaration: JSON.stringify({x: 3, y: 2, reference_height: 20, reference_height_measured: true})})).reference_height, 20);
  const t = readTopViewTaps(form({elevated_taps: JSON.stringify({x: 2, y: 2, cells: [{x: 1, y: 1, state: 'missing'}, {x: 5, y: 0, state: 'present'}, {x: 0, y: 0, state: 'odd'}]})}));
  assert.deepEqual(t.cells, [{x: 1, y: 1, state: 'missing'}]);
});

test('end to end: a camera scan with a declaration and a CORNER photo returns the grid, inventory and its evidence', async t => {
  t.mock.method(console, 'log', () => {});
  // Faces: STRAIGHT 3 wide, LEFT and RIGHT 2 deep (front corner stack largest), each framed differently.
  const faces = {
    left: [...tray(20, {x: 150}), ...tray(20, {x: 300})], right: [...tray(20, {x: 170}), ...tray(20, {x: 320})],
    straight: [...tray(20, {x: 110}), ...tray(20, {x: 260}), ...tray(20, {x: 410})],
    corner: [...tray(10, {x: 100, pitch: 30, height: 27}), ...tray(10, {x: 350, pitch: 45}), ...tray(10, {x: 600, pitch: 38, height: 34}),
      ...tray(10, {x: 850, pitch: 32, height: 29})],
  };
  const order = ['left', 'right', 'straight', 'corner'];
  let call = 0;
  t.mock.method(globalThis, 'fetch', async () => Response.json({predictions: faces[order[call++]].map(b => ({...b, width: b.height * 6})),
    image: {width: 900, height: 1000}}));
  const form = new FormData();
  form.set('scan_contract', 'model_spatial_v1');
  [...order].forEach((view, i) => form.set(view, new File([new Uint8Array([255, 216, 255, i])], `${view}.jpg`, {type: 'image/jpeg'})));
  const yaw = {straight: 0, left: -90, right: 90, corner: -45};
  for (const view of order) form.set(`${view}_capture`, JSON.stringify({source: 'captured_still', blocked: false, yaw_deg: yaw[view], yaw_session: 'w'}));
  form.set('corner_side', 'front_left');
  form.set('block_declaration', JSON.stringify({x: 3, y: 2, interior: 'full', cover_trays: 'no', occupancy: 'egg_filled', operator: 'op1'}));
  const response = await worker.fetch(new Request('https://local/v1/scans/count', {method: 'POST', body: form}),
    {MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only'});
  assert.equal(response.status, 200);
  const {block} = await response.json();
  assert.equal(block.grid.length, 2); assert.equal(block.grid[0].length, 3);
  assert.deepEqual([block.corner.x, block.corner.y, block.corner.agrees], [3, 2, true]);
  assert.equal(block.declaration.agrees_with_faces, true); assert.equal(block.declaration.operator, 'op1');
  // The front-middle stack is seen by STRAIGHT only, so the interior declaration cannot confirm: an estimate.
  assert.equal(block.status, 'estimated');
  assert.equal(block.inventory.eligible_egg_trays.basis, 'declared');
  assert.match(block.grid_note, /not a point cloud/);
});

test('a refused photo keeps needs_view: a declaration or top view is not compared with faces that are not measurements', () => {
  const refused = {...verified3x2(), status: 'needs_view', total_trays: null};
  const result = assembleGrid(refused, {declaration: declaration({x: 4}), topView: null, corner: null});
  assert.equal(result.status, 'needs_view'); assert.equal(result.total, null);
  assert.equal(result.declaration_agrees, false);   // still recorded for the operator
});
