// Runs an older Worker build and the current one (cloudflare-worker/dist) on the current replay library
// (cloudflare-worker/test/replay_benchmark.mjs) and writes the per-case answers side by side. Offline: no network.
// The older build is a transpiled copy of its src/index.ts, for example worker 0.5.1 at 10f2c3d:
//   git show 10f2c3d:cloudflare-worker/src/index.ts > <scratch>/index.ts
//   node -e "<ts.transpileModule to ES2022 ESM>"  (cloudflare-worker/node_modules/typescript)  -> <scratch>/index.mjs
//   node scripts/compare_replay_versions.mjs <scratch>/index.mjs worker-0.5.1 reports/<report>/compare-0.5.1.json \
//     reports/<report>/summary.json 10f2c3d
// The optional last two arguments add the tallies to the report's summary.json (written by scripts/replay_benchmark.mjs,
// so run that first) as comparison_with_<older build>, naming the commit the older build came from.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { REPO, runBenchmark, replayViews, capturesFor, syntheticFace, syntheticCorner, CAMERA } from '../cloudflare-worker/test/replay_benchmark.mjs';

const [oldDist, oldName, outFile, summaryFile, fromCommit] = process.argv.slice(2);
const older = await import(pathToFileURL(path.resolve(oldDist)).href);
const current = await import(pathToFileURL(path.join(REPO, 'cloudflare-worker', 'dist', 'index.js')).href);
const pipeline = /const PIPELINE_VERSION = "([^"]+)"/.exec(fs.readFileSync(path.join(REPO, 'cloudflare-worker', 'src', 'index.ts'), 'utf8'))?.[1];
const a = runBenchmark(older), b = runBenchmark(current);
const short = r => ({ status: r.status, total: r.total });
const cases = b.adversarial.map(x => {
  const o = a.adversarial.find(y => y.id === x.id);
  return { id: x.id, check: x.check, truth: x.truth, [oldName]: { ...short(o), pass: o.pass }, [pipeline]: { ...short(x), pass: x.pass },
    stretch: x.stretch ? { check: x.stretch.check, [oldName]: o.stretch.pass, [pipeline]: x.stretch.pass } : null };
});
const tally = (run, rows) => {
  const released = rows.filter(r => r.total !== null);
  const wrong = released.filter(r => r.truth !== null && r.total !== r.truth);
  return { cases: rows.length, pass: rows.filter(r => r.pass).length, released: released.length,
    wrong_releases: wrong.map(r => `${r.id.split(' ')[0]}: ${r.status} ${r.total} for ${r.truth}`),
    wrong_exact_or_confirmed: wrong.filter(r => ['exact', 'confirmed'].includes(r.status)).map(r => r.id.split(' ')[0]),
    confirmed: rows.filter(r => r.status === 'confirmed').length, exact: rows.filter(r => r.status === 'exact').length,
    trios_released: run.summary.trios.released.length, trios_wrong_releases: run.summary.trios.wrong_releases.length,
    trios_wrong_exact: run.summary.trios.wrong_exact.length, trios: run.summary.trios.records,
    labelled_clusters_accepted: `${run.summary.labelled_clusters.accepted}/${run.summary.labelled_clusters.n}` };
};
// The cost of the declared-size rule: S21 as the 0.5.1 library had it (CORNER photo, no declaration).
const S = syntheticFace;
const s21 = w => replayViews(w, { straight: S([20, 20, 20]), left: S([20, 20, 20]), right: S([20, 20, 20]) }, CAMERA,
  capturesFor('captured_still', CAMERA), syntheticCorner(3, 3)).block;
const cost = { id: 'S21 without a declaration (the 0.5.1 library case)', truth: 180,
  [oldName]: (b => ({ status: b.status, total: b.total_trays }))(s21(older)), [pipeline]: (b => ({ status: b.status, total: b.total_trays }))(s21(current)) };
const result = { library: 'cloudflare-worker/test/replay_benchmark.mjs (current)', registry: b.registry,
  summary: { [oldName]: tally(a, a.adversarial), [pipeline]: tally(b, b.adversarial) },
  face_verdicts_changed: b.faces.filter(f => { const o = a.faces.find(x => x.id === f.id); return o.outcome !== f.outcome || o.total !== f.total; }).length,
  trios_changed: b.trios.filter(t => { const o = a.trios.find(x => x.id === t.id); return o.status !== t.status || o.total !== t.total; }).map(t => t.id),
  declared_size_cost: cost, cases };
fs.writeFileSync(path.resolve(outFile), JSON.stringify(result, null, 1) + '\n');
if (summaryFile) {
  const summary = JSON.parse(fs.readFileSync(path.resolve(summaryFile), 'utf8'));
  summary[`comparison_with_${oldName.replace(/[^A-Za-z0-9]/g, '_')}`] = {
    source: `${path.basename(outFile)} (${oldName} transpiled from ${fromCommit ?? 'an older commit'}, run on this library)`,
    ...result.summary, face_verdicts_changed: result.face_verdicts_changed, trios_changed: result.trios_changed.length,
    declared_size_cost: cost };
  fs.writeFileSync(path.resolve(summaryFile), JSON.stringify(summary, null, 1) + '\n');
}
console.log(JSON.stringify(result.summary, null, 1));
console.log('face verdicts changed', result.face_verdicts_changed, '; trios changed', result.trios_changed.length);
console.log(JSON.stringify(cost));
for (const c of cases) if (c[oldName].status !== c[pipeline].status || c[oldName].total !== c[pipeline].total)
  console.log(`${c.id.split(' ')[0]}: ${c[oldName].status} ${c[oldName].total} -> ${c[pipeline].status} ${c[pipeline].total} (truth ${c.truth})`);
