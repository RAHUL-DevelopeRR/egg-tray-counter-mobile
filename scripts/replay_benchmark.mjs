// Offline replay benchmark report: the current Worker build on every saved detection set in
// benchmarks/registry-20261101, plus the synthetic adversarial library. No network, no inference.
//
// Run from the repository root after building the Worker (cd cloudflare-worker && npm run build):
//   node scripts/replay_benchmark.mjs --out reports/replay-baseline-20261101
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const REPO = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const arg = name => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : null; };
const out = path.resolve(REPO, arg('--out') ?? 'reports/replay-latest');
const dist = path.join(REPO, 'cloudflare-worker', 'dist', 'index.js');
if (!fs.existsSync(dist)) throw new Error('cloudflare-worker/dist/index.js is missing; run npm run build in cloudflare-worker first');

const w = await import(pathToFileURL(dist).href);
const { runBenchmark } = await import(pathToFileURL(path.join(REPO, 'cloudflare-worker', 'test', 'replay_benchmark.mjs')).href);
const pipeline = /const PIPELINE_VERSION = "([^"]+)"/.exec(fs.readFileSync(path.join(REPO, 'cloudflare-worker', 'src', 'index.ts'), 'utf8'))?.[1];
const run = runBenchmark(w);
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'summary.json'), JSON.stringify({ pipeline_version: pipeline, ...run.summary }, null, 1) + '\n');
fs.writeFileSync(path.join(out, 'details.json'), JSON.stringify({ pipeline_version: pipeline, faces: run.faces, trios: run.trios,
  adversarial: run.adversarial, reencode: run.reencode }, null, 1) + '\n');

const s = run.summary;
console.log(`pipeline ${pipeline}; registry ${run.registry}`);
for (const [k, v] of Object.entries(s.faces)) console.log(`faces ${k}: ${v.accepted}/${v.n} accepted, ${v.accepted_correct} correct, wrong ${JSON.stringify(v.accepted_wrong)}`);
console.log(`labelled clusters: ${s.labelled_clusters.accepted}/${s.labelled_clusters.n} accepted, wrong ${JSON.stringify(s.labelled_clusters.accepted_wrong)}`);
console.log(`trios: ${s.trios.records} replays of ${s.trios.groups} sets; wrong releases ${s.trios.wrong_releases.length}, wrong exact ${s.trios.wrong_exact.length}`);
console.log(`adversarial: ${s.adversarial.pass}/${s.adversarial.n} pass`);
for (const f of s.adversarial.failing) console.log(`  FAIL ${f}`);
console.log(`re-encode flips: ${s.reencode.flipped.length}/${s.reencode.n}`);
console.log(`wrote ${path.relative(REPO, out)}/summary.json and details.json`);
