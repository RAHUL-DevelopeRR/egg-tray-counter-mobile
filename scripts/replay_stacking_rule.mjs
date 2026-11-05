// Offline replay for Worker 0.7.0's stacking rule (docs/PLAN_5_MULTI_PHOTO.md §7 Phase 1): the stacking-rule cases
// (cloudflare-worker/test/rule_cases.mjs) under an older build and the current one, and the four Decision 3 options
// (how strict the full height H is) on the rule cases, the adversarial library and the three saved real scans.
// No network, no detector call. The older build is a dist/index.js copy of that build, for example worker 0.6.0.
//   node scripts/replay_stacking_rule.mjs <older dist index.mjs> worker-0.6.0 reports/stacking-rule-0.7.0-20261105
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { REPO, replayViews, capturesFor, declared, CAMERA, responseViews, syntheticCorner, adversarialCases, blockSummary, judge, loadJson, REGISTRY }
  from '../cloudflare-worker/test/replay_benchmark.mjs';
import { ruleCases, runRuleCase, ruleSummary, judgeRule } from '../cloudflare-worker/test/rule_cases.mjs';

const [oldDist, oldName, outDir] = process.argv.slice(2);
const older = await import(pathToFileURL(path.resolve(oldDist)).href);
const current = await import(pathToFileURL(path.join(REPO, 'cloudflare-worker', 'dist', 'index.js')).href);
const pipeline = /const PIPELINE_VERSION = "([^"]+)"/.exec(fs.readFileSync(path.join(REPO, 'cloudflare-worker', 'src', 'index.ts'), 'utf8'))?.[1];
const out = path.resolve(REPO, outDir);
fs.mkdirSync(out, { recursive: true });
const OPTIONS = { a_two_faces: { basis: 'two_faces' }, a_prime_strict_sides: { basis: 'strict_sides' }, b_any_photo: { basis: 'any_photo' },
  c_doubted_allowed: { basis: 'doubted_allowed' } };
const short = s => ({ status: s.status, total: s.total, withheld_reason: s.withheld_reason ?? null });
// Wrong = a released total that is not the truth (for in_range cases: the truth outside the printed range).
const wrong = (c, s) => s.total !== null && c.truth !== null && (c.check === 'in_range' ? !judgeRule('in_range', s, c.truth) : s.total !== c.truth);

// 1. Rule cases: older build vs current, and the current build under each Decision 3 option.
const cases = ruleCases().map(c => {
  const o = ruleSummary(runRuleCase(older, c)), n = ruleSummary(runRuleCase(current, c));
  const options = Object.fromEntries(Object.entries(OPTIONS).map(([k, rule]) => {
    const s = ruleSummary(runRuleCase(current, c, rule));
    return [k, { ...short(s), rule_height: s.rule_height, pass: judgeRule(c.check, s, c.truth), wrong_release: wrong(c, s) }];
  }));
  return { id: c.id, truth: c.truth, check: c.check, expect: c.expect, residual: !!c.residual, sweep: c.sweep ?? null,
    [oldName]: { ...short(o), wrong_release: wrong(c, o) },
    [pipeline]: { ...short(n), rule_height: n.rule_height, rule_partner: n.rule_partner, counted: n.counted, assumed: n.assumed,
      rule_trays_range: n.rule_trays_range, estimated_range_by_rule: n.estimated_range_by_rule, doubted_low_up_to: n.doubted_low_up_to,
      rescan_view: n.rescan_view, provisional: n.provisional, pass: judgeRule(c.check, n, c.truth), wrong_release: wrong(c, n) },
    options };
});

// 2. The adversarial library under each Decision 3 option (the older build's answers are in compare-0.6.0.json).
const registry = loadJson(REGISTRY);
const library = adversarialCases(registry).map(c => {
  const run = rule => blockSummary(replayViews(current, c.views, c.headings, capturesFor(c.source ?? 'captured_still', c.headings),
    { ...(c.extras ?? {}), ...(rule ? { rule } : {}) }));
  return { id: c.id, truth: c.truth, check: c.check, options: Object.fromEntries(Object.entries(OPTIONS).map(([k, rule]) => {
    const s = run(rule);
    return [k, { ...short(s), pass: judge(c.check, s, c.truth), wrong_release: s.total !== null && c.truth !== null && s.total !== c.truth }];
  })) };
});

// 3. The saved real scans (scripts/replay_saved_scans.mjs modes; the camera rows are counterfactual) under each option.
const SCANS = [
  { name: '99-block-6fe33b1d', file: 'reports/eval-20261015/staging47-replay/6fe33b1d-4605-4b53-84f4-86bff313c1f3.json', size: [5, 1], truth: 99 },
  { name: 'field-4x3-9b4c783e', file: 'reports/field-scans-20261013/replay/9b4c783e-7edb-43ed-b7d2-2f8eed889f60.json', size: [4, 3], truth: null,
    note: 'tier V reading 164 filled (+ covers); no physical count' },
  { name: 'mutaa-L-100', file: 'reports/mutaa-validation-0.5.0-20261101/raw/set-L-100.json', size: [5, 1], truth: 100 },
];
const saved = SCANS.flatMap(scan => {
  const views = responseViews(loadJson(scan.file));
  const decl = declared(scan.size[0], scan.size[1], { interior: 'unknown', operator: 'replay' });
  const modes = { 'as-sent': [{}, {}, {}], camera: [CAMERA, capturesFor('captured_still', CAMERA), {}],
    'camera-declared': [CAMERA, capturesFor('captured_still', CAMERA), decl],
    'camera-corner-declared': [CAMERA, capturesFor('captured_still', CAMERA), { ...syntheticCorner(scan.size[0], scan.size[1]), ...decl }] };
  return Object.entries(modes).map(([mode, [headings, captures, extras]]) => {
    const one = (w, rule) => {
      const r = replayViews(w, views, headings, captures, { ...extras, ...(rule ? { rule } : {}) });
      const inv = r.block.inventory;
      return { status: r.block.status, total: r.block.total_trays, withheld_reason: inv.withheld_reason, counted: inv.counted_trays,
        assumed: inv.assumed_trays, rule_height: r.block.rule?.height ?? null, rule_trays_range: inv.rule_trays_range ?? null,
        provisional: r.block.rule?.provisional ?? inv.provisional ?? null, rescan_view: r.rescan.recommended_view };
    };
    return { scan: scan.name, mode, truth: scan.truth, note: scan.note ?? null, [oldName]: short(one(older)), [pipeline]: one(current),
      options: Object.fromEntries(Object.entries(OPTIONS).map(([k, rule]) => [k, (s => ({ ...short(s), rule_height: s.rule_height }))(one(current, rule))])) };
  });
});

const tallyOptions = rows => Object.fromEntries(Object.keys(OPTIONS).map(k => [k, {
  pass: rows.filter(r => r.options[k].pass).length, of: rows.length,
  released: rows.filter(r => r.options[k].total !== null).length,
  wrong_releases: rows.filter(r => r.options[k].wrong_release).map(r => r.id.split(' ')[0] + (r.id.includes('scale') ? ` ${r.id.split('scale ')[1]}` : '')),
}]));
const result = { pipeline, older: oldName, options: OPTIONS,
  rule_cases: { n: cases.length,
    [oldName]: { released: cases.filter(c => c[oldName].total !== null).length,
      wrong_releases: cases.filter(c => c[oldName].wrong_release).map(c => `${c.id.split(' ')[0]}${c.sweep ? ' ' + c.id.split('scale ')[1] : ''}: ${c[oldName].total} for ${c.truth}`) },
    [pipeline]: { pass: cases.filter(c => c[pipeline].pass).length, released: cases.filter(c => c[pipeline].total !== null).length,
      wrong_releases: cases.filter(c => c[pipeline].wrong_release).map(c => `${c.id.split(' ')[0]}${c.sweep ? ' ' + c.id.split('scale ')[1] : ''}: ${c[pipeline].total} for ${c.truth}`) },
    by_option: tallyOptions(cases) },
  library: { n: library.length, by_option: tallyOptions(library) },
  saved_scans: saved, cases, library_cases: library };
fs.writeFileSync(path.join(out, 'stacking-rule.json'), JSON.stringify(result, null, 1) + '\n');
console.log(JSON.stringify({ rule_cases: result.rule_cases, library: result.library }, null, 1));
for (const s of saved) console.log(s.scan.padEnd(20), s.mode.padEnd(24), `${oldName} ${s[oldName].status} ${s[oldName].total}`.padEnd(32),
  `${pipeline} ${s[pipeline].status} ${s[pipeline].total} ${s[pipeline].withheld_reason ?? ''}`.padEnd(54),
  Object.entries(s.options).map(([k, v]) => `${k.split('_')[0]}:${v.total ?? v.withheld_reason}`).join(' '));
