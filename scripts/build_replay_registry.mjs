// Builds benchmarks/registry-20261101/manifest.json: every saved detection set the replay harness scores, with its
// truth tier and provenance. Deterministic, no network, no inference; reads only files already in the repo.
//
// Sources:
//   reports/eval-20261015/eval_manifest.json, results.json   labelled faces: labels, clusters, blocks, tuning flags
//   benchmarks/registry-20261101/near_duplicates.json         detector data-pool matches (scripts/registry_near_duplicates.py)
//   reports/mutaa-manual-vs-backend-20261031/                 MUTAA sets: raw staging responses, consensus counts, user totals
//
// Run from the repository root:  node scripts/build_replay_registry.mjs
import fs from 'node:fs';
import path from 'node:path';

const REPO = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const OUT_DIR = path.join(REPO, 'benchmarks', 'registry-20261101');
const read = rel => JSON.parse(fs.readFileSync(path.join(REPO, rel), 'utf8'));
const posix = p => p.split(path.sep).join('/');
const base = p => p.split(/[\\/]/).pop();

const manifest = read('reports/eval-20261015/eval_manifest.json');
const results = read('reports/eval-20261015/results.json');
const nearDup = read('benchmarks/registry-20261101/near_duplicates.json');
const MUTAA_DIR = 'reports/mutaa-manual-vs-backend-20261031';
const consensus = read(`${MUTAA_DIR}/manual-consensus.json`);
const comparison = read(`${MUTAA_DIR}/comparison.json`);
const verified = read(`${MUTAA_DIR}/sets-verified.json`).sets;

// Only these two clusters were touched by neither detector training nor logic tuning (eval-20261015 README).
const UNTOUCHED = new Set([47, 49]);
// Photos whose results shaped a counting rule after 2026-10-15: L-100 (img-19, 21, 24) drove the 0.4.13 side check.
const SIDECHECK_DESIGN = new Set(['img-19.jpeg', 'img-21.jpeg', 'img-24.jpeg']);

const poolMatches = Object.fromEntries(nearDup.photos.map(p => [base(p.file), p.pool_matches]));
const resultRow = Object.fromEntries(results.photos.map(r => [r.label_id, r]));
const secondaryRow = Object.fromEntries(results.not_usable_secondary.rows.map(r => [r.label_id, r]));
const labelByFile = Object.fromEntries([...manifest.photos, ...manifest.not_usable].map(p => [base(p.file), p]));

function provenance(fileName, row = {}) {
  const pool = poolMatches[fileName] ?? null;
  return {
    detector_pool_match: pool === null ? null : pool.length > 0,
    detector_leak: row.detector_leak ?? null,
    in_gate_tuning_set: row.in_gate_tuning_set ?? false,
    in_walk_reference_photos: row.in_walk_reference_photos ?? false,
    in_walk_development_photos: row.in_walk_development_photos ?? false,
    in_orientation_development_photos: row.in_orientation_development_photos ?? false,
    in_sidecheck_design: SIDECHECK_DESIGN.has(fileName),
  };
}

const faces = [];
for (const p of manifest.photos) {
  const r = resultRow[p.label_id];
  const name = base(p.file);
  faces.push({
    id: `img-${String(p.label_id).padStart(2, '0')}`, source: 'labelled', photo: p.file, sha256: p.sha256,
    cluster: p.near_duplicate_cluster, block_id: p.group_id, role: 'face',
    detections: { file: r.detections.file, view: r.detections.view }, image: { width: p.width, height: p.height },
    truth: { tier: 'U', trays: p.label_value, scope_tier: p.tier, scope: p.label_scope, usable: true },
    provenance: provenance(name, r), split: UNTOUCHED.has(p.label_id) ? 'untouched' : 'development',
    python_0411: { outcome: r.outcome, predicted_total: r.predicted_total },
  });
}
for (const p of manifest.not_usable) {
  const r = secondaryRow[p.label_id];
  faces.push({
    id: `img-${String(p.label_id).padStart(2, '0')}`, source: 'labelled', photo: p.file, sha256: p.sha256,
    cluster: p.near_duplicate_cluster, block_id: p.group_id, role: 'face_not_usable',
    detections: { file: r.detections.file, view: r.detections.view }, image: { width: p.width, height: p.height },
    truth: { tier: 'U', trays: p.label_value, usable: false, scope: p.audit_scope, why_not_usable: p.audit_reason_not_usable },
    provenance: provenance(base(p.file)), split: 'development',
    python_0411: { outcome: r.outcome, predicted_total: r.predicted_total },
  });
}

// MUTAA sets (2026-10-31): each real (non-filler) view is a face; STRAIGHT gets the consensus count as V truth, and the
// user's written label when the photo is a labelled one. Consensus counts are filled + empty trays (the detector counts
// trays), from three agent counters reconciled: tier V, never pooled with U.
const consensusBySet = Object.fromEntries(consensus.map(c => [c.set_id, c.consensus]));
const comparisonBySet = Object.fromEntries(comparison.map(c => [c.set_id, c]));
const verifiedBySet = Object.fromEntries(verified.map(v => [v.set_id, v]));
const trios = [];
for (const file of fs.readdirSync(path.join(REPO, MUTAA_DIR, 'raw')).sort()) {
  const setId = file.replace(/\.json$/, '');
  const rel = `${MUTAA_DIR}/raw/${file}`;
  const response = read(rel);
  const filler = response._filler ?? null;
  const c = consensusBySet[setId];
  const cmp = comparisonBySet[setId];
  for (const view of ['straight', 'left', 'right']) {
    if (view === filler) continue;
    const src = base(response._sent[view].src);
    const labelled = labelByFile[src];
    const front = view === 'straight' && c ? c.per_face.find(f => f.role.startsWith('STRAIGHT')) : null;
    const countable = front && front.stacks.every(s => s.agreement !== 'not_countable');
    const stacks = countable ? front.stacks.map(s => s.filled + (s.empty ?? 0)) : null;
    faces.push({
      id: `mutaa:${setId}:${view}`, source: labelled ? 'labelled_reencoded' : 'mutaa', photo: src,
      same_photo_as: labelled ? `img-${String(labelled.label_id).padStart(2, '0')}` : null,
      cluster: labelled?.near_duplicate_cluster ?? `MUTAA-${setId}-${view}`, block_id: `MUTAA-${setId}`, role: 'face',
      detections: { file: rel, view }, image: response.views[view].image,
      truth: view === 'straight'
        ? { tier: 'V', trays: stacks ? stacks.reduce((s, v) => s + v, 0) : null, per_stack: stacks,
            user_label: labelled?.label_value ?? null, user_label_scope: labelled?.label_scope ?? labelled?.audit_scope ?? null }
        : { tier: null, trays: null },
      provenance: provenance(src, resultRow[labelled?.label_id] ?? {}), split: 'development',
    });
  }
  trios.push({
    id: `mutaa:${setId}`, group: `MUTAA ${setId}`, response: rel, filler,
    photos: Object.fromEntries(['straight', 'left', 'right'].map(v => [v, base(response._sent[v].src)])),
    genuine: verifiedBySet[setId]?.genuine_trio ?? false,
    recorded: { pipeline_version: response.job?.pipeline_version ?? null, status: response.block.status, total_trays: response.block.total_trays },
    truth: { user_total: cmp?.user_label ?? null, manual_grid: cmp?.manual_grid ?? null,
      manual_trays_v: cmp ? cmp.manual_filled + (cmp.manual_empty ?? 0) : null, manual_reliability: cmp?.manual_reliability ?? null },
    expected: 'no released total (not a genuine STRAIGHT/LEFT/RIGHT trio)', split: 'development',
  });
}

// Older saved three-view responses (eval-20261015 multi_view). Each replay is one record; the trio is the scored unit.
for (const t of manifest.multi_view) {
  for (const replay of t.replays) {
    if (!fs.existsSync(path.join(REPO, replay.path))) continue;
    trios.push({
      id: `${t.trio} @ ${replay.path}`, group: t.trio, response: replay.path, filler: null, photos: t.faces,
      genuine: t.genuine, recorded: { note: replay.recorded },
      truth: { user_total: t.trio.startsWith('99-block') ? 99 : null, note: t.expected },
      expected: t.genuine ? 'no exact result (hidden interior computed; no physical count)' : 'no released total',
      split: 'development',
    });
  }
}

const out = {
  registry: 'registry-20261101',
  built_by: 'scripts/build_replay_registry.mjs',
  truth_tiers: {
    U: "the user's handwritten count on the photo (a stack-face or block total, scope from the 2026-10-15 audit)",
    'U-blind': "the user's blind per-stack count (Phase D2; none yet)",
    V: 'visual consensus of three agent counters, reconciled (2026-10-31); not physical, never pooled with U',
    S: 'synthetic, known by construction (adversarial library in cloudflare-worker/test/replay_benchmark.mjs)',
  },
  splits: {
    untouched: 'img-47 and img-49 only: untouched by detector training and by counting-logic tuning',
    development: 'everything else; figures from it are development figures, not proof',
  },
  counts: { faces: faces.length, trios: trios.length },
  faces,
  trios,
};
fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(path.join(OUT_DIR, 'manifest.json'), JSON.stringify(out, null, 1) + '\n');
console.log(`${posix(path.relative(REPO, path.join(OUT_DIR, 'manifest.json')))}: ${faces.length} faces, ${trios.length} trio replays`);
