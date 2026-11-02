// Offline what-if replays of the MUTAA set scans through the Worker's own functions (cloudflare-worker/dist), using the
// detections staging returned. No network, no detector calls.
//   as_sent        gallery provenance, no declaration (must equal the staging answer)
//   declared       gallery provenance + an honest blind declaration (the 31 Oct manual footprint)
//   camera         COUNTERFACTUAL: the same photos as guided-camera stills with a valid 90-degree side turn
//   camera_decl    camera + the honest declaration
// The camera rows assume sensor data these photos never had; they test whether the counting logic would release a
// wrong total if provenance were present (or spoofed), not what the app shows for these photos.
//   node scripts/replay_mutaa_validation.mjs reports/mutaa-validation-0.5.0-20261101
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { REPO, replayViews, capturesFor, declared, CAMERA, blockSummary } from '../cloudflare-worker/test/replay_benchmark.mjs';

const w = await import(pathToFileURL(path.join(REPO, 'cloudflare-worker', 'dist', 'index.js')).href);
const report = path.resolve(process.argv[2]);
const consensus = Object.fromEntries(JSON.parse(fs.readFileSync(path.join(REPO,
  'reports/mutaa-manual-vs-backend-20261031/manual-consensus.json'), 'utf8')).map(c => [c.set_id, c.consensus]));

const rows = [];
for (const file of fs.readdirSync(path.join(report, 'raw')).filter(f => f.startsWith('set-')).sort()) {
  const saved = JSON.parse(fs.readFileSync(path.join(report, 'raw', file), 'utf8'));
  const c = consensus[saved._set_id];
  const decl = declared(c.x_stacks, c.y_stacks, { operator: 'mutaa-validation' });
  const run = (headings, captures, extras) => {
    const s = blockSummary(replayViews(w, saved.views, headings, captures, extras));
    return { status: s.status, total: s.total, width: s.width, depth: s.depth, conflicts: s.conflicts, refused: s.refused,
      side: s.side };
  };
  const gallery = capturesFor('uploaded_photo');
  const camera = capturesFor('captured_still', CAMERA);
  const row = {
    set_id: saved._set_id, filler: saved._filler ?? null,
    manual: { x: c.x_stacks, y: c.y_stacks, total_filled: c.total_filled },
    staging: { status: saved.result_status, total: saved.block?.total_trays ?? null },
    as_sent: run({}, {}, {}),
    declared: run({}, gallery, decl),
    camera: run(CAMERA, camera, {}),
    camera_decl: run(CAMERA, camera, decl),
  };
  row.as_sent_matches_staging = row.as_sent.status === row.staging.status && row.as_sent.total === row.staging.total;
  rows.push(row);
  console.log(row.set_id.padEnd(17), `manual ${c.x_stacks}x${c.y_stacks}=${c.total_filled}`.padEnd(18),
    ['as_sent', 'declared', 'camera', 'camera_decl'].map(k => `${k}:${row[k].status}/${row[k].total}`).join('  '),
    row.as_sent_matches_staging ? '' : 'STAGING MISMATCH');
}
fs.writeFileSync(path.join(report, 'replay-what-if.json'), JSON.stringify(rows, null, 1) + '\n');
