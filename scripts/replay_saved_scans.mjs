// Offline replays of saved scan responses through the current Worker build (cloudflare-worker/dist), using the
// detections the server returned at the time. No network, no detector calls.
//   as-sent           the upload as it was: no capture provenance, no declaration (what this Worker answers for it)
//   camera            COUNTERFACTUAL: the same photos as guided-camera stills with a 90-degree turn to each side
//   camera-declared   camera + the honest block size (from the scan's report), interior unknown
//   camera-corner-declared  camera-declared + a SYNTHETIC guided-camera CORNER photo (front-left) that reads the declared
//                     size (test/replay_benchmark.mjs syntheticCorner); a side that repeats the front needs one
// The camera rows assume sensor data these photos never had; they show what the counting logic would release, not what
// the app shows for these photos. Keys starting with "_" and local paths are removed from every output.
//   node scripts/replay_saved_scans.mjs reports/evidence-grid-0.6.0-20261103/saved-scans reports/evidence-grid-0.6.0-20261103/summary.json
// The optional second argument adds the short rows to the report's summary.json as saved_scans.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { REPO, replayViews, capturesFor, declared, CAMERA, responseViews, syntheticCorner } from '../cloudflare-worker/test/replay_benchmark.mjs';

const w = await import(pathToFileURL(path.join(REPO, 'cloudflare-worker', 'dist', 'index.js')).href);
const out = path.resolve(REPO, process.argv[2] ?? 'reports/saved-scans-replay');
const SCANS = [
  { name: '99-block-6fe33b1d', file: 'reports/eval-20261015/staging47-replay/6fe33b1d-4605-4b53-84f4-86bff313c1f3.json', size: [5, 1],
    truth: 'one-deep 5 x 1 row, 99 trays (eval-20261015)' },
  { name: 'field-4x3-9b4c783e', file: 'reports/field-scans-20261013/replay/9b4c783e-7edb-43ed-b7d2-2f8eed889f60.json', size: [4, 3],
    truth: '4 x 3 block; visual reading (tier V) 104 seen + 4 hidden x 15 = 164 filled (field-scans-20261013); no physical count' },
  { name: 'mutaa-L-100', file: 'reports/mutaa-validation-0.5.0-20261101/raw/set-L-100.json', size: [5, 1],
    truth: '5 x 1 row of 100 filled (manual consensus, tier V); its LEFT and RIGHT photos are re-shots of the front' },
];
const LOCAL_PATH = /^[A-Za-z]:[\\/]|[\\/]Users[\\/]|^\/(home|mnt|c)\//;
const scrub = v => Array.isArray(v) ? v.map(scrub)
  : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).filter(([k]) => !k.startsWith('_')).map(([k, x]) => [k, scrub(x)]))
  : typeof v === 'string' && LOCAL_PATH.test(v) ? '[local path removed]' : v;

fs.mkdirSync(out, { recursive: true });
const index = [];
for (const scan of SCANS) {
  const views = responseViews(JSON.parse(fs.readFileSync(path.join(REPO, scan.file), 'utf8')));
  const modes = {
    'as-sent': () => replayViews(w, views),
    'camera': () => replayViews(w, views, CAMERA, capturesFor('captured_still', CAMERA)),
    'camera-declared': () => replayViews(w, views, CAMERA, capturesFor('captured_still', CAMERA),
      declared(scan.size[0], scan.size[1], { interior: 'unknown', operator: 'replay' })),
    'camera-corner-declared': () => replayViews(w, views, CAMERA, capturesFor('captured_still', CAMERA),
      { ...syntheticCorner(scan.size[0], scan.size[1]), ...declared(scan.size[0], scan.size[1], { interior: 'unknown', operator: 'replay' }) }),
  };
  for (const [mode, run] of Object.entries(modes)) {
    const result = scrub(run());
    const file = `${scan.name}.${mode}.json`;
    fs.writeFileSync(path.join(out, file), JSON.stringify({ replay_of: scan.file, replay_mode: mode, truth: scan.truth, ...result }, null, 1) + '\n');
    const b = result.block, inv = b.inventory;
    const row = { scan: scan.name, mode, file, status: b.status, total_trays: b.total_trays, width: b.width, depth: b.depth,
      depth_basis: b.depth_basis, side_check: { left: b.side_check.left.status, right: b.side_check.right.status },
      counted_trays: inv.counted_trays, assumed_trays: inv.assumed_trays, assumed_stacks: inv.assumed_stacks,
      estimated_range: inv.estimated_range, withheld_reason: inv.withheld_reason, provisional: inv.provisional,
      suggested_views: b.suggested_views, suggested_inputs: b.suggested_inputs };
    index.push(row);
    console.log(scan.name.padEnd(20), mode.padEnd(16), `${b.status} ${b.total_trays}`.padEnd(18),
      inv.counted_trays === null ? '' : `counted ${inv.counted_trays} + assumed ${inv.assumed_trays}`, inv.withheld_reason ?? '');
  }
}
fs.writeFileSync(path.join(out, 'index.json'), JSON.stringify(index, null, 1) + '\n');
if (process.argv[3]) {
  const file = path.resolve(REPO, process.argv[3]);
  const summary = JSON.parse(fs.readFileSync(file, 'utf8'));
  summary.saved_scans = index.map(r => ({ scan: r.scan, mode: r.mode, status: r.status, total_trays: r.total_trays,
    counted_trays: r.counted_trays, assumed_trays: r.assumed_trays, estimated_range: r.estimated_range, withheld_reason: r.withheld_reason }));
  fs.writeFileSync(file, JSON.stringify(summary, null, 1) + '\n');
}
