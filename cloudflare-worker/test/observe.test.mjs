// AUTH_MODE=observe: the rollout step between open and enforce. A request that carries a credential is handled
// exactly as in enforce; an upload without one (the installed 0.4.11 app) gets the open 0.4.11 answer.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { PREFIX, FakeR2, observeEnv, enforceEnv, call, sendJson, adminHeaders, deviceHeaders, activeDevice, newDevice, register,
  postScan, mockInference, jobKey, manualKey, legacyManualKey, captureLogs } from './enforce_support.mjs';

const cells = [{x: 0, y: 0, app_layers: 20, app_status: 'observed', filled: 20, empty: 0}];
const code = async (response) => (await response.json()).detail.code;
// What the 0.4.11 app sends: no count_id, no created_at, no credential.
const oldManual = {block_id: 'B01', cells, notes: '', app_total: 20, app_version: '0.4.11+22'};
const manual = (fields = {}) => ({...oldManual, app_version: '0.4.12+23', count_id: crypto.randomUUID(),
  created_at: new Date(Date.now() - 60_000).toISOString(), ...fields});
const saveManual = (env, scanId, body, headers = {}) => sendJson(env, `/v1/scans/${scanId}/manual-count`, body, headers);

async function setup(t, extra = {}) {
  const logs = captureLogs(t);
  const inference = mockInference(t);
  const bucket = new FakeR2();
  return {logs, inference, bucket, env: observeEnv(bucket, extra)};
}

test('observe: a 0.4.11 count without credentials is answered as the open Worker does, with no job and no state', async t => {
  const {logs, inference, bucket, env} = await setup(t);
  const scanId = crypto.randomUUID();
  const first = await postScan(env, scanId, {});
  assert.equal(first.status, 200);
  const body = await first.json();
  assert.equal('job' in body, false);
  assert.equal(body.scan_id, scanId);
  assert.equal(body.block.total_trays, 20);
  // No idempotency on the open path: a repeat counts again, as 0.4.11 does.
  assert.equal((await postScan(env, scanId, {})).status, 200);
  assert.equal(inference.calls, 6);
  assert.equal(bucket.stored(`scans/${scanId}/`), 6);
  assert.equal(bucket.readJson(jobKey(scanId)), null);
  assert.deepEqual(bucket.keys(PREFIX), []);
  assert.equal(logs.filter(line => line.includes('"observe_open_request"') && line.includes('scans/count')).length, 2);
  // The baseline (no contract) and cell-identity generations stay open too.
  assert.equal((await postScan(env, crypto.randomUUID(), {}, 0, {contract: null})).status, 200);
  assert.equal((await postScan(env, crypto.randomUUID(), {}, 0, {contract: 'cell_identity_v1', cells: {left: 'A', right: 'A', straight: 'A'}})).status, 200);
});

test('observe: a 0.4.11 manual count without credentials is stored as the open Worker stores it', async t => {
  const {bucket, env} = await setup(t);
  const scanId = crypto.randomUUID();
  const saved = await saveManual(env, scanId, oldManual);
  assert.equal(saved.status, 200);
  const body = await saved.json();
  assert.deepEqual(Object.keys(body), ['stored', 'key', 'latest_key', 'totals']);
  assert.equal(body.latest_key, legacyManualKey(scanId, 'latest'));
  assert.equal(bucket.readJson(legacyManualKey(scanId, 'latest')).block_id, 'B01');
  assert.deepEqual(bucket.keys(PREFIX), []);
  // Open validation still applies.
  assert.equal((await saveManual(env, scanId, {...oldManual, cells: []})).status, 422);
});

test('observe: a request with a device credential is handled exactly as in enforce', async t => {
  const {inference, bucket, env} = await setup(t);
  const device = await activeDevice(env, 1);
  const scanId = crypto.randomUUID();
  const counted = await postScan(env, scanId, deviceHeaders(device));
  assert.equal(counted.status, 200);
  const body = await counted.json();
  assert.deepEqual(body.job, {scan_id: scanId, status: 'done', attempt: 1, replayed: false, pipeline_version: body.job.pipeline_version});
  assert.equal(bucket.readJson(jobKey(scanId)).owner, device.id);
  const retry = await postScan(env, scanId, deviceHeaders(device));
  assert.equal((await retry.json()).job.replayed, true);
  assert.equal(inference.calls, 3);
  assert.equal(await code(await postScan(env, scanId, deviceHeaders(device), 1)), 'scan_id_conflict');
  // Owner scoping: another device is refused.
  const other = await activeDevice(env, 2);
  assert.equal(await code(await postScan(env, scanId, deviceHeaders(other))), 'scan_forbidden');
  assert.equal(await code(await call(env, `/v1/scans/${scanId}/result`, {headers: deviceHeaders(other)})), 'scan_forbidden');
  // Every malformed, unknown, pending or revoked credential gets the enforce answer, never the open path.
  const pending = newDevice(3);
  await register(env, pending);
  const refusals = [
    [{'x-device-id': device.id}, 401, 'device_credentials_required'],
    [{authorization: `Device ${device.secret}`}, 401, 'device_credentials_required'],
    [{'x-device-id': ''}, 401, 'device_credentials_required'],
    [{authorization: 'Basic dXNlcjpwYXNz'}, 401, 'device_credentials_required'],
    [{'x-device-id': crypto.randomUUID(), authorization: `Device ${device.secret}`}, 401, 'device_auth_failed'],
    [deviceHeaders(pending), 403, 'device_pending'],
    [adminHeaders('fake-wrong-token'), 401, 'admin_auth_failed'],
  ];
  for (const [headers, status, expected] of refusals) {
    const refused = await postScan(env, crypto.randomUUID(), headers);
    assert.equal(refused.status, status, JSON.stringify(headers));
    assert.equal(await code(refused), expected);
    const manualRefused = await saveManual(env, scanId, manual(), headers);
    assert.equal(manualRefused.status, status, JSON.stringify(headers));
  }
  assert.equal(inference.calls, 3);
  // A credential-less upload on that scan id is an open count: answered without a job, the job left as it was.
  const etag = bucket.objects.get(jobKey(scanId)).etag;
  const open = await postScan(env, scanId, {});
  assert.equal(open.status, 200);
  assert.equal('job' in await open.json(), false);
  assert.equal(bucket.objects.get(jobKey(scanId)).etag, etag);
  assert.equal(inference.calls, 6);
  await call(env, `/v1/admin/devices/${device.id}/revoke`, {method: 'POST', headers: adminHeaders()});
  assert.equal(await code(await postScan(env, crypto.randomUUID(), deviceHeaders(device))), 'device_revoked');
  // The admin is treated as in enforce: a job owned by "admin".
  const adminScan = crypto.randomUUID();
  const asAdmin = await postScan(env, adminScan, adminHeaders());
  assert.equal(asAdmin.status, 200);
  assert.equal((await asAdmin.json()).job.status, 'done');
  assert.equal(bucket.readJson(jobKey(adminScan)).owner, 'admin');
});

test('observe: an authenticated manual count is the enforced one, stored under the state prefix only', async t => {
  const {bucket, env} = await setup(t);
  const device = await activeDevice(env, 4);
  const scanId = crypto.randomUUID();
  assert.equal((await postScan(env, scanId, deviceHeaders(device))).status, 200);
  const body = manual();
  const saved = await saveManual(env, scanId, body, deviceHeaders(device));
  assert.equal(saved.status, 200);
  const stored = await saved.json();
  assert.equal(stored.key, manualKey(scanId, body.count_id));
  assert.equal(stored.record.recorded_by, device.id);
  assert.equal(bucket.readJson(manualKey(scanId, 'latest')).count_id, body.count_id);
  assert.deepEqual(bucket.keys(`scans/${scanId}/manual-count/`), []);
  assert.equal((await (await saveManual(env, scanId, body, deviceHeaders(device))).json()).replayed, true);
  // An enforced save needs count_id; a device without a job for the scan id may not attach one.
  assert.equal(await code(await saveManual(env, scanId, oldManual, deviceHeaders(device))), 'invalid_count_id');
  assert.equal(await code(await saveManual(env, crypto.randomUUID(), manual(), deviceHeaders(device))), 'scan_not_found');
  // A credential-less (open) save on the same scan id lands under scans/ and leaves the state record alone.
  assert.equal((await saveManual(env, scanId, {...oldManual, block_id: 'OPEN'})).status, 200);
  assert.equal(bucket.readJson(legacyManualKey(scanId, 'latest')).block_id, 'OPEN');
  assert.equal(bucket.readJson(manualKey(scanId, 'latest')).count_id, body.count_id);
  const read = await (await call(env, `/v1/scans/${scanId}/manual-count`, {headers: deviceHeaders(device)})).json();
  assert.equal(read.latest.count_id, body.count_id);
  assert.equal(read.latest.storage, 'state');
});

test('observe: results, listings, archive and the per-scan manual count need a credential; device and admin routes as in enforce', async t => {
  const {bucket, env} = await setup(t);
  const scanId = crypto.randomUUID();
  assert.equal((await postScan(env, scanId, {})).status, 200);
  for (const path of ['/v1/manual-counts', `/v1/scans/${scanId}/archive`, '/v1/admin/devices']) {
    for (const headers of [{}, adminHeaders('fake-wrong-token')]) {
      const refused = await call(env, path, {headers});
      assert.equal(refused.status, 401, path);
      assert.equal(await code(refused), 'admin_auth_failed');
    }
    assert.equal((await call(env, path, {headers: adminHeaders()})).status, 200, path);
  }
  const device = await activeDevice(env, 5);
  for (const path of ['/v1/manual-counts', `/v1/scans/${scanId}/archive`]) {
    assert.equal(await code(await call(env, path, {headers: deviceHeaders(device)})), 'admin_auth_failed');
  }
  for (const path of [`/v1/scans/${scanId}/result`, `/v1/scans/${scanId}/manual-count`]) {
    assert.equal(await code(await call(env, path)), 'device_credentials_required', path);
  }
  // The open count made no job: the result route says so to the admin.
  assert.equal(await code(await call(env, `/v1/scans/${scanId}/result`, {headers: adminHeaders()})), 'scan_not_found');
  const upload = (headers) => call(env, '/v1/diagnostics/upload', {method: 'POST', headers: {'content-type': 'application/octet-stream', ...headers},
    body: new Uint8Array(10)});
  assert.equal(await code(await upload({})), 'device_credentials_required');
  assert.equal((await (await upload(deviceHeaders(device))).json()).bytes, 10);
  const pending = newDevice(6);
  assert.equal((await (await register(env, pending)).json()).status, 'pending');
  assert.equal((await (await call(env, '/v1/devices/me', {headers: deviceHeaders(pending)})).json()).status, 'pending');
  assert.equal(await code(await call(env, '/v1/devices/me')), 'device_credentials_required');
  assert.equal(bucket.readJson(`${PREFIX}devices/${pending.id}.json`).status, 'pending');
});

test('observe: reconstruct without credentials stays open for the installed app; with a credential it is enforced', async t => {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = observeEnv(bucket, {RECONSTRUCTION_ENABLED: 'true', VISION_SERVICE_URL: 'https://vision.example', VISION_SERVICE_TOKEN: 'fake-vision-token'});
  t.mock.method(globalThis, 'fetch', async () => Response.json({status: 'insufficient_matches', physical_trays: null, verified: false,
    scale: 'arbitrary_unit_baseline'}));
  const pair = () => {
    const form = new FormData();
    form.set('first', new File([new Uint8Array([255, 216, 255, 1])], 'a.jpg', {type: 'image/jpeg'}));
    form.set('second', new File([new Uint8Array([255, 216, 255, 2])], 'b.jpg', {type: 'image/jpeg'}));
    return form;
  };
  const reconstruct = (headers) => call(env, '/v1/reconstruct', {method: 'POST', headers, body: pair()});
  assert.equal((await reconstruct({})).status, 200);
  assert.equal(await code(await reconstruct({'x-device-id': crypto.randomUUID()})), 'device_credentials_required');
  const device = await activeDevice(env, 7);
  assert.equal((await reconstruct(deviceHeaders(device))).status, 200);
  assert.equal((await reconstruct(adminHeaders())).status, 200);
});

test('a mistyped AUTH_MODE fails closed to enforce: no open answer without a credential', async t => {
  captureLogs(t);
  const inference = mockInference(t);
  for (const mode of ['observed', 'obsrve', 'opened']) {
    const env = enforceEnv(new FakeR2(), {AUTH_MODE: mode});
    const refused = await postScan(env, crypto.randomUUID(), {});
    assert.equal(refused.status, 401, mode);
    assert.equal(await code(refused), 'device_credentials_required');
    assert.equal(await code(await saveManual(env, crypto.randomUUID(), oldManual)), 'device_credentials_required');
  }
  // Case and spacing are forgiven for the real names.
  assert.equal((await postScan(observeEnv(new FakeR2(), {AUTH_MODE: ' OBSERVE '}), crypto.randomUUID(), {})).status, 200);
  assert.equal(inference.calls, 3);
});

test('observe and enforce without STATE_PREFIX refuse every state route (no shared default); uploads without a credential stay open in observe', async t => {
  captureLogs(t);
  const inference = mockInference(t);
  for (const [mode, prefix] of [['observe', undefined], ['enforce', ''], ['observe', '  ']]) {
    const bucket = new FakeR2();
    const env = observeEnv(bucket, {AUTH_MODE: mode, STATE_PREFIX: prefix});
    const label = `${mode} ${JSON.stringify(prefix)}`;
    const device = newDevice(8);
    const refused = [await register(env, device), await postScan(env, crypto.randomUUID(), deviceHeaders(device)),
      await postScan(env, crypto.randomUUID(), adminHeaders()), await call(env, '/v1/manual-counts', {headers: adminHeaders()}),
      await call(env, `/v1/scans/${crypto.randomUUID()}/archive`, {headers: adminHeaders()}),
      await call(env, '/v1/admin/devices', {headers: adminHeaders()})];
    for (const response of refused) {
      assert.equal(response.status, 503, label);
      assert.equal(await code(response), 'state_prefix_missing', label);
    }
    if (mode === 'observe') assert.equal((await postScan(env, crypto.randomUUID(), {})).status, 200, label);
    assert.deepEqual(bucket.keys('state/'), [], label);
  }
  assert.equal(inference.calls, 6);
});

test('wrangler.jsonc: staging deploys AUTH_MODE observe under its own STATE_PREFIX; production has no AUTH_MODE (open)', () => {
  const text = readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8');
  const config = JSON.parse(text.split('\n').filter(line => !/^\s*\/\//.test(line)).join('\n'));
  assert.equal(config.vars.AUTH_MODE, undefined);
  // The installed 0.4.11 app counts against staging: a plain `wrangler deploy --env staging` must not lock it out.
  // Switching staging to enforce is a deliberate edit of the config and of this line, once the 0.4.12 phone is approved.
  assert.equal(config.env.staging.vars.AUTH_MODE, 'observe');
  assert.equal(config.env.staging.vars.STATE_PREFIX, 'state/staging/');
});
