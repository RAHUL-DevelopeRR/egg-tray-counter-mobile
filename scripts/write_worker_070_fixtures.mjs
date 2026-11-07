// Writes three Worker 0.7.0 answers (the current cloudflare-worker/dist build, offline, no detector call) as app test
// fixtures, so mobile/test/worker_070_compat_test.dart can check that the installed app (0.6.x parser and panel) reads
// them (docs/PLAN_5_MULTI_PHOTO.md Phase 1 gate 8):
//   fr01_released.json        FR01, 171 counted + 6 hidden stacks x 20 by the stacking rule = 291
//   fr02_taller.json          FR02, a face stack above the full height: withheld (stack_taller_than_rule_height)
//   fr15_no_rule_height.json  FR15, every reading cut by the frame edge: withheld (no_rule_height)
//   node scripts/write_worker_070_fixtures.mjs
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { REPO } from '../cloudflare-worker/test/replay_benchmark.mjs';
import { ruleCases, runRuleCase } from '../cloudflare-worker/test/rule_cases.mjs';

const w = await import(pathToFileURL(path.join(REPO, 'cloudflare-worker', 'dist', 'index.js')).href);
const out = path.join(REPO, 'mobile', 'test', 'fixtures', 'worker_0_7_0');
fs.mkdirSync(out, { recursive: true });
const cases = ruleCases();
for (const [file, id] of [['fr01_released.json', 'FR01'], ['fr02_taller.json', 'FR02'], ['fr15_no_rule_height.json', 'FR15']]) {
  const c = cases.find(x => x.id.startsWith(id + ' '));
  const answer = runRuleCase(w, c);
  fs.writeFileSync(path.join(out, file), JSON.stringify({ _fixture: `${c.id} (scripts/write_worker_070_fixtures.mjs, ${answer.block.cells[0]?.readings?.[0]?.pipeline_version})`, ...answer }) + '\n');
  console.log(file, answer.block.status, answer.block.total_trays, answer.block.inventory.withheld_reason);
}
