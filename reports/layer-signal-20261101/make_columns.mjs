// Writes mobile/test/fixtures/layer_signal_columns.json: the detector's stack columns for every face in
// benchmarks/registry-20261101/manifest.json, which the LayerSignal parity test compares against.
//
// - MUTAA faces keep their saved stack_columns (staging 0.4.12). The Worker rebuilds them from the same boxes only
//   to say which columns it accepts; the saved and rebuilt pitches are both written.
// - The 7 Oct batches saved boxes only, so their columns are rebuilt with the Worker's own spanColumns.
// - A column is "accepted" when the face passes the capture gate and the column has no retake reason
//   (faceColumns), the same split the replay benchmark uses.
//
// No network, no inference. Run from the repository root with a dist build of cloudflare-worker/src/index.ts:
//   node reports/layer-signal-20261101/make_columns.mjs --dist <dir>/index.js
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const arg = name => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : null; };
const dist = path.resolve(arg('--dist') ?? path.join(REPO, 'cloudflare-worker', 'dist', 'index.js'));
const out = path.join(REPO, 'mobile', 'test', 'fixtures', 'layer_signal_columns.json');
const w = await import(pathToFileURL(dist).href);

const load = rel => JSON.parse(fs.readFileSync(path.join(REPO, rel), 'utf8'));
const views = saved => saved.views ?? saved.response?.views;
// _sent paths were written from the main checkout; files inside the repository are referenced relative to it.
const MAIN_ROOT = 'C:\\Users\\rahul\\egg-tray-counter-mobile\\';
const photoPath = src => src.startsWith(MAIN_ROOT) ? src.slice(MAIN_ROOT.length).replaceAll('\\', '/') : src;
const pick = c => ({ pitch_px: c.pitch_px, y_first: c.y_first, y_last: c.y_last, x_min: c.x_min, x_max: c.x_max,
  box_height_px: c.box_height_px, span_count: c.span_count, walk_count: c.walk_count });

const registry = load('benchmarks/registry-20261101/manifest.json');
const faces = registry.faces.map(f => {
  const saved = load(f.detections.file);
  const view = views(saved)[f.detections.view];
  const image = f.image;
  const rebuilt = [...w.spanColumns(view.detections, image)].sort((a, b) => a.x_min - b.x_min);
  const verdict = w.faceColumns(rebuilt, 'face');
  const capture = w.captureQuality(rebuilt, image.width, image.height, w.medianBoxAspect(view.detections));
  const sent = saved._sent?.[f.detections.view] ?? null;
  const savedColumns = view.stack_columns ? [...view.stack_columns].sort((a, b) => a.x_min - b.x_min) : null;
  const columns = rebuilt.map((c, i) => {
    // Saved and rebuilt columns are matched by the largest x-range overlap (over half the rebuilt width); the saved
    // one wins where it exists.
    const overlap = s => Math.min(s.x_max, c.x_max) - Math.max(s.x_min, c.x_min);
    const best = savedColumns?.reduce((a, s) => (a === null || overlap(s) > overlap(a) ? s : a), null) ?? null;
    const match = best && overlap(best) > 0.5 * (c.x_max - c.x_min) ? best : null;
    return { ...pick(match ?? c), source: match ? 'saved' : 'rebuilt', rebuilt_pitch_px: c.pitch_px,
      doubts: c.doubts, reason: verdict[i].reason, accepted: capture.accepted && verdict[i].reason === null };
  });
  return {
    id: f.id, source: f.source, block_id: f.block_id, same_photo_as: f.same_photo_as ?? null,
    photo: sent ? photoPath(sent.src) : f.photo,
    prepare: sent ? { mode: 'sent', width: sent.sent[0], height: sent.sent[1] } : { mode: 'raw' },
    image, truth: f.truth.trays ?? null, usable: f.truth.usable !== false,
    capture_accepted: capture.accepted, capture_reasons: capture.reasons,
    total: verdict.reduce((s, c) => s + c.layers, 0), columns,
  };
});

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify({
  made_by: 'reports/layer-signal-20261101/make_columns.mjs',
  worker: /const PIPELINE_VERSION = "([^"]+)"/.exec(fs.readFileSync(path.join(REPO, 'cloudflare-worker', 'src', 'index.ts'), 'utf8'))?.[1],
  registry: registry.registry, faces,
}, null, 1) + '\n');
const cols = faces.flatMap(f => f.columns);
console.log(`${faces.length} faces, ${cols.length} columns (${cols.filter(c => c.accepted).length} accepted, ` +
  `${cols.filter(c => c.source === 'saved').length} saved), written to ${path.relative(REPO, out)}`);
const drift = cols.filter(c => c.source === 'saved' && Math.abs(c.pitch_px - c.rebuilt_pitch_px) > 0.5);
console.log(`saved vs rebuilt pitch differs by > 0.5 px on ${drift.length} columns`);
