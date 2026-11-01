import assert from 'node:assert/strict';
import test from 'node:test';
import * as w from '../dist/index.js';
import { REGISTRY, VIEWS, adversarialCases, loadJson, responseViews, runBenchmark } from './replay_benchmark.mjs';

// Offline replay of every saved detection set in benchmarks/registry-20261101 (scripts/replay_benchmark.mjs writes
// the full report). All figures are development figures: only img-47 and img-49 are untouched by tuning.
const run = runBenchmark(w);
const registry = loadJson(REGISTRY);

test('every registry input exists and every face and trio is replayed', () => {
  assert.equal(run.faces.length, registry.faces.length);
  assert.equal(run.trios.length, registry.trios.length);
  for (const t of registry.trios) assert.ok(VIEWS.every(v => responseViews(loadJson(t.response))[v]?.detections), t.id);
});

test('per-face verdicts equal the Python evaluation of the 0.4.11 logic on all 52 labelled photos', () => {
  const labelled = run.faces.filter(f => f.python_0411);
  assert.equal(labelled.length, 52);
  const mismatches = labelled.filter(f => f.python_0411.outcome !== f.outcome || f.python_0411.predicted_total !== f.total);
  assert.deepEqual(mismatches.map(f => f.id), []);
});

test('replaying the saved MUTAA responses reproduces their 0.4.12 stack columns and capture verdicts', () => {
  for (const t of registry.trios.filter(t => t.id.startsWith('mutaa:'))) {
    const saved = loadJson(t.response);
    const replay = w.modelDiagnostics('replay', Object.fromEntries(VIEWS.map(v => [v, {count: 0, confidence: 0,
      detections: saved.views[v].detections, image: saved.views[v].image}])), {}, {EGGS_PER_TRAY: '30'}, 0);
    for (const v of VIEWS) {
      // 0.4.14 adds doubts per column; every 0.4.12 field must be unchanged.
      assert.deepEqual(replay.views[v].stack_columns.map(({doubts, ...c}) => c), saved.views[v].stack_columns, `${t.id} ${v}`);
      assert.deepEqual(replay.block.capture[v], saved.block.capture[v], `${t.id} ${v}`);
    }
  }
});

test('accepted labelled faces: no wrong count beyond the known img-30 (78 for 80)', () => {
  assert.deepEqual(run.summary.labelled_clusters.accepted_wrong, ['img-30 78/80']);
});

test('no saved three-view scan releases a wrong total, and none releases a wrong exact', () => {
  assert.deepEqual(run.summary.trios.wrong_releases, []);
  assert.deepEqual(run.summary.trios.wrong_exact, []);
});

// Cases with fixed_by set fail today by design; they report as TODO until the named plan phase lands.
for (const c of adversarialCases(registry)) {
  const result = run.adversarial.find(a => a.id === c.id);
  test(`adversarial ${c.id}`, c.fixed_by ? {todo: `plan phase ${c.fixed_by}`} : {}, () => {
    assert.ok(result.pass, `${c.check}: got ${result.status} ${result.total}, truth ${c.truth}`);
  });
  if (c.stretch) test(`adversarial ${c.id}, stretch: ${c.stretch.check}`, {todo: `plan phase ${c.stretch.fixed_by}`}, () => {
    assert.ok(result.stretch.pass, `got ${result.status} ${result.total}, truth ${c.truth}`);
  });
}
