// Offline replay benchmark: the Worker's own counting functions (dist build) on saved detections, scored against
// the truth tiers in benchmarks/registry-20261101/manifest.json, plus a synthetic adversarial library (tier S).
// No network, no inference: every input is a file already in the repo, so a rule change can be scored before it
// ships (a done scan job replays its stored answer forever, so a wrong rule cannot be fixed after the fact).
//
// Used by test/replay_benchmark.test.mjs and scripts/replay_benchmark.mjs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const VIEWS = ['left', 'right', 'straight'];
export const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const REGISTRY = 'benchmarks/registry-20261101/manifest.json';
const ENV = { MODEL_ID: 'replay', EGGS_PER_TRAY: '30' };

export const loadJson = rel => JSON.parse(fs.readFileSync(path.join(REPO, rel), 'utf8'));
// Saved files are either a Worker response ({views}) or a batch record wrapping one ({response: {views}}).
export const responseViews = saved => saved.views ?? saved.response?.views;

/** One photo on its own, the way scripts/evaluate_labelled.py scores it: capture gate, then per-column retake reasons. */
export function faceVerdict(w, detections, image) {
  const columns = w.spanColumns(detections);
  const capture = w.captureQuality(columns, image?.width ?? null, image?.height ?? null, w.medianBoxAspect(detections));
  const face = w.faceColumns(columns, 'face');
  const flagged = face.filter(c => c.reason);
  const outcome = !capture.accepted ? 'withheld_gate' : flagged.length ? 'withheld_flagged' : 'accepted';
  return {
    outcome, accepted: outcome === 'accepted', total: face.reduce((s, c) => s + c.layers, 0),
    walk_by_column: face.map(c => c.layers), filled_layers: face.reduce((s, c) => s + c.filled, 0),
    gate_reasons: capture.reasons, flag_reasons: flagged.map(c => c.reason),
  };
}

/** Three views through modelDiagnostics, exactly as the live Worker does after inference. */
export function replayViews(w, views, headings = {}) {
  const results = Object.fromEntries(VIEWS.map(v => [v, {
    count: views[v].detections.length, confidence: 0, detections: views[v].detections, image: views[v].image ?? null,
  }]));
  return w.modelDiagnostics('replay', results, {}, ENV, 0, undefined, undefined, headings);
}

export function blockSummary(result) {
  const b = result.block;
  return {
    status: b.status, total: b.total_trays, width: b.width, depth: b.depth, observed: b.observed_trays,
    computed: b.computed_trays, filled: b.filled_trays, conflicts: b.conflicts.length,
    side: Object.fromEntries(['left', 'right'].map(s => [s, b.side_check[s].status])),
    refused: VIEWS.filter(v => !b.capture[v].accepted), rescan_view: result.rescan.recommended_view,
  };
}

// ---- Synthetic faces (tier S). Columns 100 px wide and 100 px apart, layers at pitch 40 with 36 px boxes, in a frame
// sized so every intact face passes the capture gate; only the counting rules decide.
const PITCH = 40;
export function syntheticFace(heights, { drop = [], short = [], merge = null } = {}) {
  const detections = [];
  heights.forEach((layers, i) => {
    const x = merge !== null && i === merge + 1 ? 100 + merge * 100 + 30 : 100 + i * 100;
    for (let k = 0; k < layers; k++) {
      if (drop.some(([col, layer]) => col === i && layer === k)) continue;
      detections.push({ class: 'egg_tray', confidence: 0.9, x, y: 100 + (20 - layers + k) * PITCH, width: 100, height: 36 });
    }
  });
  // Short stacks (fewer than 3 trays) to the right of the face, standing on the same floor.
  short.forEach((layers, j) => {
    for (let k = 0; k < layers; k++) detections.push({ class: 'egg_tray', confidence: 0.9,
      x: 100 + (heights.length + j) * 100, y: 100 + (20 - layers + k) * PITCH, width: 100, height: 36 });
  });
  return { detections, image: { width: 100 * (heights.length + short.length) + 100, height: 1000 } };
}

// Camera headings for a genuine walk-around in one session. Sign: positive yaw is a left (counter-clockwise) turn
// seen from above; to face the block's left side face the operator turns right (-90). Only the magnitude matters to
// the 0.4.13 side check; the direction is used by the Phase D1 rule.
export const CAMERA = { straight: { yaw_deg: 0, yaw_session: 'syn' }, left: { yaw_deg: -90, yaw_session: 'syn' },
  right: { yaw_deg: 90, yaw_session: 'syn' } };
const swap = { ...CAMERA, left: { yaw_deg: 90, yaw_session: 'syn' }, right: { yaw_deg: -90, yaw_session: 'syn' } };
const backAsLeft = { ...CAMERA, left: { yaw_deg: 180, yaw_session: 'syn' } };

/**
 * Adversarial library. check:
 *   no_wrong_exact  a released `exact` total must equal the truth
 *   no_wrong_total  any released total must equal the truth
 *   withheld        no total at all
 * fixed_by names the plan phase expected to make a case pass when it fails today (null = must pass now). stretch is a
 * stricter check the release contract does not require yet (an estimate may be wrong), with the phase meant to meet it.
 */
export function adversarialCases(registry) {
  const S = syntheticFace;
  const trioFromRaw = id => {
    const t = registry.trios.find(r => r.id === id);
    return responseViews(loadJson(t.response));
  };
  return [
    { id: 'S01 genuine 4x1 one-deep, all 20', views: { straight: S([20, 20, 20, 20]), left: S([20]), right: S([20]) },
      headings: CAMERA, truth: 80, check: 'no_wrong_total', fixed_by: null },
    { id: 'S02 genuine 3x2, all 20 (one hidden stack computed)', views: { straight: S([20, 20, 20]), left: S([20, 20]), right: S([20, 20]) },
      headings: CAMERA, truth: 120, check: 'no_wrong_exact', fixed_by: null },
    { id: 'S03 top tray of a middle front stack missed (silent -1)', views: { straight: S([20, 20, 20, 20], { drop: [[1, 0]] }),
      left: S([20]), right: S([20]) }, headings: CAMERA, truth: 80, check: 'no_wrong_exact', fixed_by: null,
      stretch: { check: 'no_wrong_total', fixed_by: 'E' } },
    { id: 'S04 bottom tray of a middle front stack missed (silent -1)', views: { straight: S([20, 20, 20, 20], { drop: [[2, 19]] }),
      left: S([20]), right: S([20]) }, headings: CAMERA, truth: 80, check: 'no_wrong_exact', fixed_by: null,
      stretch: { check: 'no_wrong_total', fixed_by: 'E' } },
    { id: 'S05 layer inside a middle stack missed and gap-filled', views: { straight: S([20, 20, 20, 20], { drop: [[1, 10]] }),
      left: S([20]), right: S([20]) }, headings: CAMERA, truth: 80, check: 'no_wrong_exact', fixed_by: null },
    { id: 'S06 short end stack of 2 trays dropped from the front', views: { straight: S([20, 20, 20], { short: [2] }),
      left: S([20]), right: S([], { short: [2] }) }, headings: CAMERA, truth: 62, check: 'no_wrong_exact', fixed_by: null },
    { id: 'S07 two front stacks merged into one column', views: { straight: S([20, 20, 20, 20], { merge: 1 }),
      left: S([20]), right: S([20]) }, headings: CAMERA, truth: 80, check: 'no_wrong_exact', fixed_by: null,
      stretch: { check: 'no_wrong_total', fixed_by: 'F' } },
    { id: 'S08 corner heights 1 apart', views: { straight: S([20, 20, 20]), left: S([19]), right: S([20]) },
      headings: CAMERA, truth: 60, check: 'no_wrong_exact', fixed_by: null },
    { id: 'S09 missing interior stack in a 3x3 block (photos identical to a full block)',
      views: { straight: S([20, 20, 20]), left: S([20, 20, 20]), right: S([20, 20, 20]) },
      headings: CAMERA, truth: 160, check: 'no_wrong_exact', fixed_by: null, stretch: { check: 'no_wrong_total', fixed_by: 'H' } },
    { id: 'S10 LEFT and RIGHT photos swapped (heights differ)', views: { straight: S([20, 20, 20]), left: S([20, 18]), right: S([20, 20]) },
      headings: swap, truth: 118, check: 'no_wrong_total', fixed_by: null },
    { id: 'S11 back face (180 degrees) sent as LEFT of a 4x2 block', views: { straight: S([20, 20, 20, 20]), left: S([20, 20, 20, 20]), right: S([20, 20]) },
      headings: backAsLeft, truth: 160, check: 'no_wrong_total', fixed_by: null },
    { id: 'S11b back face (180 degrees) sent as LEFT of a square 3x3 block (counts cannot tell it from a side)',
      views: { straight: S([20, 20, 20]), left: S([20, 20, 20]), right: S([20, 20, 20]) },
      headings: backAsLeft, truth: 180, check: 'withheld', fixed_by: null },
    { id: 'S12 front re-shot as LEFT, gallery (no heading), 4x2 block', views: { straight: S([20, 20, 20, 20]), left: S([20, 20, 20, 20]), right: S([20, 20]) },
      headings: {}, truth: 160, check: 'withheld', fixed_by: null },
    { id: 'S13 front re-shot as LEFT with the phone turned only 10 degrees', views: { straight: S([20, 20, 20]), left: S([20, 20, 20]), right: S([20, 20]) },
      headings: { ...CAMERA, left: { yaw_deg: -10, yaw_session: 'syn' } }, truth: 120, check: 'withheld', fixed_by: null },
    { id: 'S14 side photos of another block, phone really turned (4x1 block, 3-deep neighbour)',
      views: { straight: S([20, 20, 20, 20]), left: S([20, 20, 20]), right: S([20, 20, 20]) },
      headings: CAMERA, truth: 80, check: 'no_wrong_total', fixed_by: 'F' },
    { id: 'R01 MUTAA L-100: three front photos, gallery', views: trioFromRaw('mutaa:L-100'), headings: {},
      truth: 100, check: 'no_wrong_total', fixed_by: null },
    { id: 'R02 MUTAA L-100 sides sent with camera headings of a real walk-around', views: trioFromRaw('mutaa:L-100'), headings: CAMERA,
      truth: 100, check: 'no_wrong_total', fixed_by: 'F' },
    { id: 'R03 MUTAA M16-FAR: neighbouring block in the front photo', views: trioFromRaw('mutaa:M16-FAR'), headings: CAMERA,
      truth: null, check: 'withheld', fixed_by: null },
  ];
}

export function judge(check, summary, truth) {
  const released = summary.total !== null;
  if (check === 'withheld') return !released;
  if (check === 'no_wrong_total') return !released || summary.total === truth;
  return summary.status !== 'exact' || summary.total === truth;
}

/** Everything in one pass; deterministic for a given dist build and registry. */
export function runBenchmark(w) {
  const registry = loadJson(REGISTRY);
  const cache = new Map();
  const saved = rel => { if (!cache.has(rel)) cache.set(rel, loadJson(rel)); return cache.get(rel); };

  const faces = registry.faces.map(f => {
    const view = responseViews(saved(f.detections.file))[f.detections.view];
    const v = faceVerdict(w, view.detections, f.image);
    const truth = f.truth.trays;
    return { id: f.id, source: f.source, role: f.role, split: f.split, tier: f.truth.tier, usable: f.truth.usable !== false,
      cluster: f.cluster, same_photo_as: f.same_photo_as ?? null, truth, ...v,
      correct: truth === null || truth === undefined ? null : v.total === truth, python_0411: f.python_0411 ?? null };
  });

  const trios = registry.trios.map(t => {
    const s = blockSummary(replayViews(w, responseViews(saved(t.response))));
    const truth = t.truth.user_total ?? null;
    const released = s.total !== null;
    // A total from a set that is not one block's three faces is wrong unless the block's own total is known and equal
    // (the 99 block: its sides are substituted, but a one-deep block's sides only confirm the corner heights).
    const wrong = released && (truth !== null ? s.total !== truth : !t.genuine);
    return { id: t.id, group: t.group, genuine: t.genuine, truth, recorded: t.recorded, ...s, released, wrong_release: wrong,
      wrong_exact: wrong && s.status === 'exact' };
  });

  const adversarial = adversarialCases(registry).map(c => {
    const s = blockSummary(replayViews(w, c.views, c.headings));
    return { id: c.id, check: c.check, fixed_by: c.fixed_by, truth: c.truth, ...s, pass: judge(c.check, s, c.truth),
      stretch: c.stretch ? { ...c.stretch, pass: judge(c.stretch.check, s, c.truth) } : null };
  });

  // Re-encode stability: a labelled photo sent again through the app's 1600 px re-encode (MUTAA L-* sets).
  const byId = Object.fromEntries(faces.map(f => [f.id, f]));
  const reencode = faces.filter(f => f.same_photo_as).map(f => ({ id: f.id, original: f.same_photo_as,
    original_total: byId[f.same_photo_as].total, original_outcome: byId[f.same_photo_as].outcome,
    reencoded_total: f.total, reencoded_outcome: f.outcome, flipped: f.total !== byId[f.same_photo_as].total }));

  return { registry: registry.registry, faces, trios, adversarial, reencode, summary: summarize(faces, trios, adversarial, reencode) };
}

function faceStats(rows) {
  const accepted = rows.filter(r => r.accepted);
  return { n: rows.length, accepted: accepted.length, accepted_correct: accepted.filter(r => r.correct).length,
    accepted_wrong: accepted.filter(r => r.correct === false).map(r => `${r.id} ${r.total}/${r.truth}`),
    withheld: rows.length - accepted.length, withheld_would_be_exact: rows.filter(r => !r.accepted && r.correct).length,
    coverage: rows.length ? Math.round(1000 * accepted.length / rows.length) / 1000 : null };
}

function summarize(faces, trios, adversarial, reencode) {
  const scored = faces.filter(f => f.role === 'face' && f.truth !== null && f.truth !== undefined && f.tier);
  // A re-encoded labelled photo is also scored against the user's label when that label is usable for the face.
  const byId = Object.fromEntries(faces.map(f => [f.id, f]));
  for (const f of faces.filter(f => f.same_photo_as && byId[f.same_photo_as].usable)) {
    const truth = byId[f.same_photo_as].truth;
    scored.push({ ...f, tier: 'U', truth, correct: f.total === truth });
  }
  const groups = {};
  for (const f of scored) (groups[`${f.split}/${f.tier}/${f.source}`] ??= []).push(f);
  // Primary unit for the labelled photos: one face per near-duplicate cluster (lowest id), as in eval-20261015.
  const firstPerCluster = Object.values(Object.fromEntries([...scored].filter(f => f.source === 'labelled').reverse()
    .map(f => [f.cluster, f])));
  return {
    faces: Object.fromEntries(Object.entries(groups).sort().map(([k, rows]) => [k, faceStats(rows)])),
    labelled_clusters: faceStats(firstPerCluster),
    trios: { records: trios.length, groups: new Set(trios.map(t => t.group)).size,
      released: trios.filter(t => t.released).map(t => `${t.id}: ${t.status} ${t.total}`),
      wrong_releases: trios.filter(t => t.wrong_release).map(t => t.id), wrong_exact: trios.filter(t => t.wrong_exact).map(t => t.id) },
    adversarial: { n: adversarial.length, pass: adversarial.filter(a => a.pass).length,
      failing: adversarial.filter(a => !a.pass).map(a => `${a.id} [${a.status} ${a.total}, truth ${a.truth}; fixed by ${a.fixed_by ?? 'NOTHING PLANNED'}]`),
      stretch_failing: adversarial.filter(a => a.stretch && !a.stretch.pass)
        .map(a => `${a.id} [${a.stretch.check}: ${a.status} ${a.total}, truth ${a.truth}; phase ${a.stretch.fixed_by}]`) },
    reencode: { n: reencode.length, flipped: reencode.filter(r => r.flipped).map(r => `${r.id} ${r.original_total}->${r.reencoded_total}`) },
  };
}
