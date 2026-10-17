import assert from 'node:assert/strict';
import test from 'node:test';
import worker from '../dist/index.js';
import { ADMIN, FakeR2, enforceEnv, call, sendJson, adminHeaders, deviceHeaders, activeDevice, newDevice, register, postScan, mockInference,
  manualKey, manualPrefix, captureLogs } from './enforce_support.mjs';

const cells = [{x: 0, y: 0, app_layers: 20, app_status: 'observed', filled: 20, empty: 0}, {x: 1, y: 0, app_layers: 20, app_status: 'computed', filled: 18, empty: 1}];
const at = (offsetMs) => new Date(Date.now() + offsetMs).toISOString();
const manual = (fields = {}) => ({block_id: 'B01', notes: '', cells, app_version: '0.4.12+23', app_total: 40,
  count_id: crypto.randomUUID(), created_at: at(-60_000), ...fields});
const saveManual = (env, scanId, body, headers) => sendJson(env, `/v1/scans/${scanId}/manual-count`, body, headers);
// The enforced route stores manual counts under the state prefix only.
const latestOf = (bucket, scanId) => bucket.readJson(manualKey(scanId, 'latest'));
const code = async (response) => (await response.json()).detail.code;

async function scanned(t) {
  captureLogs(t);
  mockInference(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const device = await activeDevice(env, 1);
  const scanId = crypto.randomUUID();
  assert.equal((await postScan(env, scanId, deviceHeaders(device))).status, 200);
  return {bucket, env, device, headers: deviceHeaders(device), scanId};
}

test('manual count: only the job owner or the admin; a job is required, except admin counts for archived older scans', async t => {
  const {bucket, env, headers, scanId, device} = await scanned(t);
  const saved = await saveManual(env, scanId, manual(), headers);
  assert.equal(saved.status, 200);
  const body = await saved.json();
  assert.equal(body.stored, true);
  assert.equal(body.replayed, false);
  assert.equal(body.is_latest, true);
  assert.equal(body.key, manualKey(scanId, body.count_id));
  assert.equal(body.latest_key, manualKey(scanId, 'latest'));
  assert.deepEqual(bucket.keys(`scans/${scanId}/manual-count/`), []);
  assert.deepEqual(body.totals, {filled: 38, empty: 1, unreachable: 0});
  assert.equal(body.record.app_total, 40);
  assert.equal(body.record.recorded_by, device.id);
  assert.equal(latestOf(bucket, scanId).app_total, 40);
  const other = await activeDevice(env, 2);
  const foreign = await saveManual(env, scanId, manual(), deviceHeaders(other));
  assert.equal(foreign.status, 403);
  assert.equal(await code(foreign), 'scan_forbidden');
  assert.equal((await saveManual(env, scanId, manual(), adminHeaders())).status, 200);
  assert.equal((await saveManual(env, scanId, manual(), {})).status, 401);
  // No job: a device may not attach a count; the admin may, but only to a scan with archived photos.
  const older = crypto.randomUUID();
  const noJob = await saveManual(env, older, manual(), headers);
  assert.equal(noJob.status, 404);
  assert.equal(await code(noJob), 'scan_not_found');
  assert.equal(await code(await saveManual(env, older, manual(), adminHeaders())), 'scan_not_found');
  await bucket.put(`scans/${older}/left/${'a'.repeat(64)}`, 'photo');
  const legacy = await saveManual(env, older, manual(), adminHeaders());
  assert.equal(legacy.status, 200);
  assert.equal((await legacy.json()).record.recorded_by, 'admin');
  assert.equal((await saveManual(env, older, manual(), headers)).status, 404);
});

test('manual count is idempotent by count_id, and latest.json only moves to a newer created_at', async t => {
  const {bucket, env, headers, scanId} = await scanned(t);
  const countPrefix = manualPrefix(scanId);
  const first = manual({created_at: at(-60_000)});
  assert.equal((await (await saveManual(env, scanId, first, headers)).json()).is_latest, true);
  const objects = bucket.keys(countPrefix).length;
  // A transport retry: same count_id, same body -> the stored record, nothing new written.
  const retry = await saveManual(env, scanId, first, headers);
  assert.equal(retry.status, 200);
  const replay = await retry.json();
  assert.equal(replay.replayed, true);
  assert.equal(replay.is_latest, true);
  assert.equal(bucket.keys(countPrefix).length, objects);
  assert.equal(bucket.stored(`${countPrefix}${first.count_id}.json`), 1);
  const changed = await saveManual(env, scanId, {...first, cells: [{...cells[0], filled: 19, empty: 1}]}, headers);
  assert.equal(changed.status, 409);
  assert.equal(await code(changed), 'manual_count_conflict');
  // A late retry of an older count is stored but does not replace the newer latest.
  const older = manual({created_at: at(-120_000), app_total: 41});
  const late = await (await saveManual(env, scanId, older, headers)).json();
  assert.equal(late.is_latest, false);
  assert.equal(latestOf(bucket, scanId).count_id, first.count_id);
  assert.ok(bucket.readJson(`${countPrefix}${older.count_id}.json`));
  const correction = manual({created_at: at(-1000), app_total: 39});
  assert.equal((await (await saveManual(env, scanId, correction, headers)).json()).is_latest, true);
  assert.equal(latestOf(bucket, scanId).count_id, correction.count_id);
  assert.equal(latestOf(bucket, scanId).app_total, 39);
  // A replay of the first count after the correction leaves the correction in place.
  assert.equal((await (await saveManual(env, scanId, first, headers)).json()).is_latest, false);
  assert.equal(latestOf(bucket, scanId).count_id, correction.count_id);
  // A latest without created_at (a 0.4.11-shaped record; the enforced route always writes one) is ordered by its
  // server recorded_at.
  await bucket.seed(`${countPrefix}latest.json`, {kind: 'manual_count_v1', scan_id: scanId, recorded_at: at(-30_000)});
  assert.equal((await (await saveManual(env, scanId, manual({created_at: at(-40_000)}), headers)).json()).is_latest, false);
  assert.equal((await (await saveManual(env, scanId, manual({created_at: at(-20_000)}), headers)).json()).is_latest, true);
});

test('a phone clock running fast cannot pin latest.json: a count is ordered no later than the server stored it', async t => {
  const {bucket, env, headers, scanId} = await scanned(t);
  const fast = manual({created_at: at(50 * 60 * 1000), app_total: 40});
  const first = await (await saveManual(env, scanId, fast, headers)).json();
  assert.equal(first.is_latest, true);
  assert.equal(first.record.created_at, fast.created_at);        // stored as the phone sent it
  await new Promise(resolve => setTimeout(resolve, 5));
  const correction = manual({created_at: at(0), cells: [{...cells[0], filled: 19, empty: 1}, cells[1]], app_total: 39});
  const fixed = await (await saveManual(env, scanId, correction, adminHeaders())).json();
  assert.equal(fixed.is_latest, true);
  assert.equal(latestOf(bucket, scanId).count_id, correction.count_id);
  assert.equal(latestOf(bucket, scanId).cells[0].filled, 19);
  // A late retry of the fast count does not take latest back, and an older count is still older.
  assert.equal((await (await saveManual(env, scanId, fast, headers)).json()).is_latest, false);
  assert.equal((await (await saveManual(env, scanId, manual({created_at: at(-60_000)}), headers)).json()).is_latest, false);
  assert.equal(latestOf(bucket, scanId).count_id, correction.count_id);
});

test('concurrent saves of one scan: latest.json ends on the newest count whatever the arrival order', {timeout: 10_000}, async t => {
  const {bucket, env, headers, scanId} = await scanned(t);
  // Every save of a round reads latest.json before any of them writes it (the race the compare-and-swap settles);
  // they then go on in the order they read it.
  const latestKey = manualKey(scanId, 'latest');
  const get = bucket.get.bind(bucket);
  let barrier = null;
  bucket.get = async (key, options) => {
    const object = await get(key, options);
    if (key !== latestKey || !barrier) return object;
    const round = barrier;
    await new Promise(resolve => {
      round.waiting.push(resolve);
      if (round.waiting.length === round.size) {
        barrier = null;
        round.waiting.forEach(release => release());
      }
    });
    return object;
  };
  const orders = [[3, 7, 0, 5, 1, 6, 2, 4], [0, 1, 2, 3, 4, 5, 6, 7], [7, 6, 5, 4, 3, 2, 1, 0]];
  for (const [round, order] of orders.entries()) {
    // Each round is newer than the one before; within a round, rank 7 is the newest count.
    const bodies = order.map(rank => manual({created_at: at(-600_000 + round * 10_000 + rank * 100), app_total: rank}));
    const newest = order.indexOf(7);
    barrier = {size: bodies.length, waiting: []};
    const answers = await Promise.all(bodies.map(body => saveManual(env, scanId, body, headers)));
    assert.equal(barrier, null, `round ${round}`);
    assert.deepEqual(answers.map(r => r.status), Array(8).fill(200), `round ${round}`);
    const saved = await Promise.all(answers.map(r => r.json()));
    assert.equal(saved[newest].is_latest, true, `round ${round}`);
    assert.equal(latestOf(bucket, scanId).count_id, bodies[newest].count_id, `round ${round}`);
  }
});

test('manual count validation: count_id, created_at and app_total', async t => {
  const {env, headers, scanId} = await scanned(t);
  const refused = async (fields, expected) => {
    const response = await saveManual(env, scanId, manual(fields), headers);
    assert.equal(response.status, 422, expected);
    assert.equal(await code(response), expected);
  };
  await refused({count_id: undefined}, 'invalid_count_id');
  await refused({count_id: 'not-a-uuid'}, 'invalid_count_id');
  await refused({created_at: undefined}, 'invalid_created_at');
  await refused({created_at: '2026-10-15T07:19:00'}, 'invalid_created_at');          // no zone
  await refused({created_at: 'yesterday'}, 'invalid_created_at');
  await refused({created_at: at(2 * 60 * 60 * 1000)}, 'invalid_created_at');         // far in the future
  await refused({app_total: -1}, 'invalid_app_total');
  await refused({app_total: 1.5}, 'invalid_app_total');
  await refused({app_total: '40'}, 'invalid_app_total');
  await refused({cells: []}, 'invalid_cells');
  assert.equal((await saveManual(env, scanId, manual({app_total: null, created_at: '2026-10-01T12:49:00.123456+05:30'}), headers)).status, 200);
  assert.equal((await saveManual(env, scanId, manual({created_at: at(5 * 60 * 1000)}), headers)).status, 200);  // small clock skew
});

test('manual-count listing is admin-only and paginated by cursor; the archive listing is admin-only', async t => {
  captureLogs(t);
  const bucket = new FakeR2({pageCap: 2});
  const env = enforceEnv(bucket);
  const device = await activeDevice(env, 3);
  const scans = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
  for (const [i, scanId] of scans.entries()) {
    await bucket.put(`scans/${scanId}/left/${'b'.repeat(64)}`, 'photo');
    await bucket.seed(`scans/${scanId}/manual-count/latest.json`, {kind: 'manual_count_v1', scan_id: scanId, block_id: `B${i}`});
  }
  for (const headers of [{}, deviceHeaders(device), adminHeaders('fake-wrong-token')]) {
    const refused = await call(env, '/v1/manual-counts', {headers});
    assert.equal(refused.status, 401);
    assert.equal(await code(refused), 'admin_auth_failed');
  }
  const seen = [];
  let cursor = null, pages = 0;
  do {
    const response = await call(env, `/v1/manual-counts?limit=1${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`, {headers: adminHeaders()});
    assert.equal(response.status, 200);
    const page = await response.json();
    assert.equal(page.count, page.records.length);
    seen.push(...page.records.map(r => r.scan_id));
    cursor = page.cursor;
    pages++;
  } while (cursor && pages < 10);
  assert.equal(cursor, null);
  assert.ok(pages > 1);
  assert.deepEqual([...seen].sort(), [...scans].sort());
  const all = await (await call(env, '/v1/manual-counts', {headers: adminHeaders()})).json();
  assert.equal(all.records.length, 3);
  assert.equal(all.cursor, null);
  assert.equal(await code(await call(env, '/v1/manual-counts?cursor=garbage', {headers: adminHeaders()})), 'invalid_cursor');
  const archive = `/v1/scans/${scans[0]}/archive`;
  assert.equal((await call(env, archive, {headers: deviceHeaders(device)})).status, 401);
  assert.equal((await call(env, archive)).status, 401);
  const keys = await (await call(env, archive, {headers: adminHeaders()})).json();
  assert.equal(keys.keys.length, 2);
  // Device and job records live under STATE_PREFIX, never inside a scan listing.
  assert.ok(bucket.keys('state/test/devices/').length === 1);
  assert.ok(keys.keys.every(k => k.key.startsWith(`scans/${scans[0]}/`)));
});

test('diagnostics upload reads and discards the body, reports bytes and ms, refuses above 25 MB', async t => {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const device = await activeDevice(env, 4);
  const writes = bucket.stored();
  const upload = (body, headers = deviceHeaders(device)) => call(env, '/v1/diagnostics/upload',
    {method: 'POST', headers: {'content-type': 'application/octet-stream', ...headers}, body});
  const ok = await upload(new Uint8Array(1024 * 1024));
  assert.equal(ok.status, 200);
  const measured = await ok.json();
  assert.equal(measured.bytes, 1024 * 1024);
  assert.ok(Number.isInteger(measured.ms) && measured.ms >= 0);
  assert.equal((await (await upload(new Uint8Array(10), adminHeaders())).json()).bytes, 10);
  assert.equal((await (await upload(null)).json()).bytes, 0);
  assert.equal(bucket.stored(), writes);
  const big = await upload(new Uint8Array(25 * 1024 * 1024 + 1));
  assert.equal(big.status, 413);
  assert.equal(await code(big), 'upload_too_large');
  assert.equal((await upload(new Uint8Array(25 * 1024 * 1024))).status, 200);
  assert.equal(await code(await upload(new Uint8Array(10), {})), 'device_credentials_required');
  const pending = newDevice(5);
  await register(env, pending);
  assert.equal(await code(await upload(new Uint8Array(10), deviceHeaders(pending))), 'device_pending');
});

test('health reports device auth and scan jobs only when enforced or observed, and which mode is on', async () => {
  const health = async (env) => (await worker.fetch(new Request('https://local/health'), env)).json();
  const open = {status: 'ok', scan_contract: 'cell_identity_v1', scan_contracts: ['cell_identity_v1', 'model_spatial_v1'], hybrid_ready: false};
  assert.deepEqual(await health({}), open);
  assert.deepEqual(await health({AUTH_MODE: 'open'}), open);
  assert.deepEqual(await health({AUTH_MODE: ''}), open);
  const enforce = await health({AUTH_MODE: 'enforce'});
  assert.deepEqual(enforce, {...open, scan_contracts: ['cell_identity_v1', 'model_spatial_v1', 'scan_jobs_v1'], auth: 'device_v1', auth_mode: 'enforce'});
  const staging = await health({AUTH_MODE: 'enforce', RECONSTRUCTION_ENABLED: 'true'});
  assert.deepEqual(staging.scan_contracts, ['cell_identity_v1', 'model_spatial_v1', 'reconstruct_v1', 'scan_jobs_v1']);
  // Observe advertises exactly what enforce does, so a 0.4.12 app always sends its credential.
  assert.deepEqual(await health({AUTH_MODE: 'observe'}), {...enforce, auth_mode: 'observe'});
  assert.deepEqual(await health({AUTH_MODE: ' Observe ', RECONSTRUCTION_ENABLED: 'true'}), {...staging, auth_mode: 'observe'});
  // A mistyped mode fails closed.
  for (const mode of ['enforced', 'observed', 'opened', 'off']) assert.equal((await health({AUTH_MODE: mode})).auth_mode, 'enforce', mode);
  // /ready stays open in every mode.
  for (const mode of ['enforce', 'observe']) {
    assert.equal((await worker.fetch(new Request('https://local/ready'), {AUTH_MODE: mode, ROBOFLOW_API_KEY: 'test-only'})).status, 200);
  }
});

test('open mode keeps 0.4.11: new routes are 404, no job block, open manual counts and listings, no state written', async t => {
  captureLogs(t);
  mockInference(t);
  const bucket = new FakeR2();
  const {AUTH_MODE, ADMIN_TOKEN, ...env} = enforceEnv(bucket);
  assert.equal(AUTH_MODE, 'enforce');
  assert.equal(ADMIN_TOKEN, ADMIN);
  const device = newDevice(6);
  for (const [method, path] of [['POST', '/v1/devices'], ['GET', '/v1/devices/me'], ['GET', `/v1/scans/${crypto.randomUUID()}/result`],
    ['POST', '/v1/diagnostics/upload'], ['GET', '/v1/admin/devices'], ['POST', `/v1/admin/devices/${device.id}/approve`],
    ['GET', `/v1/scans/${crypto.randomUUID()}/manual-count`]]) {
    const response = await call(env, path, {method, headers: adminHeaders(), body: method === 'POST' ? '{}' : undefined});
    assert.equal(response.status, 404, path);
    assert.equal(await code(response), 'not_found');
  }
  const scanId = crypto.randomUUID();
  const counted = await postScan(env, scanId, {});
  assert.equal(counted.status, 200);
  assert.equal('job' in await counted.json(), false);
  assert.equal((await postScan(env, scanId, {})).status, 200);               // no idempotency: counted again
  assert.equal(bucket.stored(`scans/${scanId}/`), 6);
  const saved = await saveManual(env, scanId, {block_id: 'B01', cells}, {});
  assert.equal(saved.status, 200);
  assert.deepEqual(Object.keys(await saved.json()), ['stored', 'key', 'latest_key', 'totals']);
  const listing = await call(env, '/v1/manual-counts');
  assert.equal(listing.status, 200);
  const listed = await listing.json();
  assert.deepEqual(Object.keys(listed), ['count', 'records']);
  assert.equal('storage' in listed.records[0], false);
  const archive = await call(env, `/v1/scans/${scanId}/archive`);
  assert.equal(archive.status, 200);
  assert.deepEqual(Object.keys(await archive.json()), ['scan_id', 'keys']);
  assert.deepEqual(bucket.keys('state/'), []);
});

test('reconstruct needs an active device or the admin when enforced; still absent without RECONSTRUCTION_ENABLED', async t => {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket, {RECONSTRUCTION_ENABLED: 'true', VISION_SERVICE_URL: 'https://vision.example', VISION_SERVICE_TOKEN: 'fake-vision-token'});
  const device = await activeDevice(env, 7);
  t.mock.method(globalThis, 'fetch', async () => Response.json({status: 'insufficient_matches', physical_trays: null, verified: false,
    scale: 'arbitrary_unit_baseline'}));
  const pair = () => {
    const form = new FormData();
    form.set('first', new File([new Uint8Array([255, 216, 255, 1])], 'a.jpg', {type: 'image/jpeg'}));
    form.set('second', new File([new Uint8Array([255, 216, 255, 2])], 'b.jpg', {type: 'image/jpeg'}));
    return form;
  };
  const reconstruct = (headers, e = env) => call(e, '/v1/reconstruct', {method: 'POST', headers, body: pair()});
  assert.equal(await code(await reconstruct({})), 'device_credentials_required');
  assert.equal((await reconstruct(deviceHeaders(device))).status, 200);
  assert.equal((await reconstruct(adminHeaders())).status, 200);
  assert.equal((await reconstruct(adminHeaders(), enforceEnv(bucket))).status, 404);
});
