import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import worker from '../dist/index.js';
import { ADMIN, PREFIX, FakeR2, enforceEnv, call, sendJson, newDevice, fakeSecret, deviceHeaders, adminHeaders, register, approve, revoke,
  activeDevice, postScan, mockInference, captureLogs } from './enforce_support.mjs';

const detail = async (response) => (await response.json()).detail;
const deviceKey = (device) => `${PREFIX}devices/${device.id}.json`;
// Characters a registrant must not get into the admin's device table (written as code points to keep this file ASCII).
const UNSAFE = [[0x00, 0x1f], [0x7f, 0x9f], [0x61c, 0x61c], [0x200b, 0x200f], [0x2028, 0x202e], [0x2060, 0x2069], [0xfeff, 0xfeff]];
const safeText = (text) => [...(text ?? '')].every(c => !UNSAFE.some(([low, high]) => c.codePointAt(0) >= low && c.codePointAt(0) <= high));
const ch = (code) => String.fromCodePoint(code);

test('device registration is create-only: new, idempotent retry, other secret refused', async t => {
  const logs = captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const device = newDevice(1);
  const first = await register(env, device);
  assert.equal(first.status, 200);
  const body = await first.json();
  assert.deepEqual(body, {device_id: device.id, status: 'pending',
    display_code: `${device.id.slice(0, 4)}-${device.id.slice(4, 8)}`.toUpperCase()});
  const key = `${PREFIX}devices/${device.id}.json`;
  const record = bucket.readJson(key);
  assert.equal(record.secret_sha256, createHash('sha256').update(device.secret).digest('hex'));
  assert.equal(record.status, 'pending');
  assert.equal(record.label, 'test phone');
  assert.equal(record.app_version, '0.4.12+23');
  assert.equal(bucket.objects.get(key).customMetadata.status, 'pending');
  const etag = bucket.objects.get(key).etag;
  // A transport retry with the same secret answers the same and never rewrites the record.
  const retry = await register(env, device, {label: 'other label'});
  assert.equal(retry.status, 200);
  assert.deepEqual(await retry.json(), body);
  assert.equal(bucket.objects.get(key).etag, etag);
  assert.equal(bucket.readJson(key).label, 'test phone');
  const conflict = await register(env, {id: device.id, secret: fakeSecret(2)});
  assert.equal(conflict.status, 409);
  assert.equal((await detail(conflict)).code, 'device_exists');
  assert.equal(bucket.objects.get(key).etag, etag);
  assert.equal((await detail(await register(env, {id: 'not-a-uuid', secret: device.secret}))).code, 'invalid_device_id');
  assert.equal((await detail(await register(env, {id: crypto.randomUUID(), secret: 'short'}))).code, 'invalid_device_secret');
  assert.equal((await sendJson(env, '/v1/devices', 'not an object')).status, 422);
  assert.equal(bucket.keys(`${PREFIX}devices/`).length, 1);
  // Only the hash is stored; the secret never reaches R2 or the logs.
  assert.ok(!bucket.allText().includes(device.secret));
  assert.ok(!logs.join('\n').includes(device.secret));
});

test('concurrent registrations of one id: one secret wins, its retries agree, the others conflict', async t => {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const id = crypto.randomUUID();
  const statuses = (await Promise.all([1, 1, 2, 3].map(n => register(env, {id, secret: fakeSecret(n)})))).map(r => r.status);
  const winner = bucket.readJson(`${PREFIX}devices/${id}.json`).secret_sha256;
  const expected = [1, 1, 2, 3].map(n => createHash('sha256').update(fakeSecret(n)).digest('hex') === winner ? 200 : 409);
  assert.deepEqual(statuses, expected);
  assert.ok(statuses.filter(s => s === 200).length >= 1);
  assert.equal(bucket.stored(`${PREFIX}devices/`), 1);
});

test('missing, unknown, wrong, pending and revoked credentials get their exact codes', async t => {
  const logs = captureLogs(t);
  const inference = mockInference(t);
  const env = enforceEnv(new FakeR2());
  const device = newDevice(3);
  await register(env, device);
  const scanId = crypto.randomUUID();
  const expect = async (headers, status, code) => {
    const response = await postScan(env, scanId, headers);
    assert.equal(response.status, status, code);
    const body = await detail(response);
    assert.equal(body.code, code);
    return body;
  };
  await expect({}, 401, 'device_credentials_required');
  await expect({'x-device-id': device.id}, 401, 'device_credentials_required');
  await expect({authorization: `Device ${device.secret}`}, 401, 'device_credentials_required');
  await expect({'x-device-id': crypto.randomUUID(), authorization: `Device ${device.secret}`}, 401, 'device_auth_failed');
  await expect({'x-device-id': 'not-a-uuid', authorization: `Device ${device.secret}`}, 401, 'device_auth_failed');
  await expect({...deviceHeaders(device), authorization: `Device ${fakeSecret(4)}`}, 401, 'device_auth_failed');
  const pending = await expect(deviceHeaders(device), 403, 'device_pending');
  assert.ok(pending.message.includes(device.id.slice(0, 4).toUpperCase()));
  // The device can always ask for its own status, but only with its own secret.
  const me = await call(env, '/v1/devices/me', {headers: deviceHeaders(device)});
  assert.equal(me.status, 200);
  assert.equal((await me.json()).status, 'pending');
  assert.equal((await detail(await call(env, '/v1/devices/me', {headers: {...deviceHeaders(device), authorization: `Device ${fakeSecret(5)}`}}))).code,
    'device_auth_failed');
  assert.equal((await detail(await call(env, '/v1/devices/me'))).code, 'device_credentials_required');
  await revoke(env, device);
  await expect(deviceHeaders(device), 403, 'device_revoked');
  assert.equal((await (await call(env, '/v1/devices/me', {headers: deviceHeaders(device)})).json()).status, 'revoked');
  assert.equal(inference.calls, 0);
  assert.ok(!logs.join('\n').includes(device.secret));
});

test('admin approves and revokes by compare-and-swap; a revoked device is refused on its next request', async t => {
  const logs = captureLogs(t);
  const inference = mockInference(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const device = newDevice(6);
  await register(env, device);
  await register(env, newDevice(7));
  const listed = await call(env, '/v1/admin/devices', {headers: adminHeaders()});
  assert.equal(listed.status, 200);
  const {devices, cursor} = await listed.json();
  assert.equal(devices.length, 2);
  assert.equal(cursor, null);
  assert.ok(devices.every(d => d.status === 'pending' && !('secret_sha256' in d) && /^[0-9A-F]{4}-[0-9A-F]{4}$/.test(d.display_code)));
  const approved = await approve(env, device);
  assert.equal(approved.status, 200);
  const record = await approved.json();
  assert.equal(record.status, 'active');
  assert.ok(record.approved_at);
  assert.ok(!('secret_sha256' in record));
  const key = `${PREFIX}devices/${device.id}.json`;
  assert.equal(bucket.objects.get(key).customMetadata.status, 'active');
  const writes = bucket.stored(key);
  assert.equal((await approve(env, device)).status, 200);           // repeating is a no-op
  assert.equal(bucket.stored(key), writes);
  const pendingOnly = await (await call(env, '/v1/admin/devices?status=pending', {headers: adminHeaders()})).json();
  assert.deepEqual(pendingOnly.devices.map(d => d.status), ['pending']);
  assert.equal((await postScan(env, crypto.randomUUID(), deviceHeaders(device))).status, 200);
  const revoked = await (await revoke(env, device)).json();
  assert.equal(revoked.status, 'revoked');
  assert.ok(revoked.revoked_at);
  const refused = await postScan(env, crypto.randomUUID(), deviceHeaders(device));
  assert.equal(refused.status, 403);
  assert.equal((await detail(refused)).code, 'device_revoked');
  assert.equal(inference.calls, 3);
  assert.equal((await detail(await call(env, `/v1/admin/devices/${crypto.randomUUID()}/approve`, {method: 'POST', headers: adminHeaders()}))).code,
    'device_not_found');
  assert.equal((await call(env, '/v1/admin/devices/not-a-uuid/approve', {method: 'POST', headers: adminHeaders()})).status, 422);
  const text = logs.join('\n');
  assert.ok(!text.includes(ADMIN) && !text.includes(device.secret));
  assert.ok(logs.some(line => line.includes('device_status_changed') && line.includes(device.id)));
});

test('admin routes refuse a wrong, missing or device credential, and everything when ADMIN_TOKEN is unset', async t => {
  captureLogs(t);
  const env = enforceEnv(new FakeR2());
  const device = await activeDevice(env, 8);
  const admin = async (headers, e = env) => {
    const response = await call(e, '/v1/admin/devices', {headers});
    assert.equal(response.status, 401);
    assert.equal((await detail(response)).code, 'admin_auth_failed');
  };
  await admin({});
  await admin(adminHeaders('fake-wrong-token'));
  await admin(adminHeaders(`${ADMIN}x`));
  await admin(deviceHeaders(device));
  await admin({authorization: ADMIN});
  const unset = enforceEnv(new FakeR2(), {ADMIN_TOKEN: undefined});
  await admin(adminHeaders(), unset);
  await admin(adminHeaders(''), unset);
  // A device route given a wrong admin token is an admin failure, not a silent device fallback.
  const scan = await postScan(env, crypto.randomUUID(), adminHeaders('fake-wrong-token'));
  assert.equal(scan.status, 401);
  assert.equal((await detail(scan)).code, 'admin_auth_failed');
});

test('registration reads at most 4 KiB before any credential: a larger declared or streamed body is refused unread', async t => {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const device = newDevice(20);
  // 16 MiB of blanks in 1 KiB chunks (finite, so a regression that reads it whole fails instead of hanging);
  // `pulled` counts how many chunks the Worker asked for.
  let pulled = 0;
  const huge = () => new ReadableStream({pull(controller) {
    if (++pulled > 16 * 1024) controller.close(); else controller.enqueue(new Uint8Array(1024).fill(32));
  }});
  const post = (body, headers = {}) => worker.fetch(new Request('https://local/v1/devices',
    {method: 'POST', duplex: 'half', headers: {'content-type': 'application/json', ...headers}, body}), env);
  const declared = await post(huge(), {'content-length': String(16 * 1024 * 1024)});
  assert.equal(declared.status, 413);
  assert.equal((await detail(declared)).code, 'request_too_large');
  assert.ok(pulled <= 2, `pulled ${pulled}`);
  pulled = 0;
  const streamed = await post(huge());
  assert.equal(streamed.status, 413);
  assert.equal((await detail(streamed)).code, 'request_too_large');
  assert.ok(pulled <= 8, `pulled ${pulled}`);
  const padded = JSON.stringify({device_id: device.id, secret: device.secret, label: 'x'.repeat(64 * 1024)});
  assert.equal((await post(padded)).status, 413);
  assert.deepEqual(bucket.keys(`${PREFIX}devices/`), []);
  // Just under the limit is a normal registration; the label is cut to 64 characters.
  const ok = await post(JSON.stringify({device_id: device.id, secret: device.secret, label: 'x'.repeat(3000)}));
  assert.equal(ok.status, 200);
  assert.equal(bucket.readJson(deviceKey(device)).label, 'x'.repeat(64));
  assert.equal((await post('')).status, 422);
});

test('registration turns control characters, bidi overrides and invisible marks in label and app_version into spaces', async t => {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const device = newDevice(21);
  const registered = await register(env, device, {label: `x\nABCD-1234  active\r${ch(0x1b)}[2K${ch(0x202e)}enohp${ch(0)}`, app_version: `${ch(0x200b)}0.4.12+23${ch(0x85)}${ch(0x2066)}`});
  assert.equal(registered.status, 200);
  const record = bucket.readJson(deviceKey(device));
  assert.equal(record.label, 'x ABCD-1234 active [2K enohp');
  assert.equal(record.app_version, '0.4.12+23');
  const blank = newDevice(22);
  await register(env, blank, {label: `${ch(0x07)}${ch(0x202e)}\r\n`, app_version: ch(0xfeff)});
  assert.equal(bucket.readJson(deviceKey(blank)).label, null);
  assert.equal(bucket.readJson(deviceKey(blank)).app_version, null);
  const {devices} = await (await call(env, '/v1/admin/devices', {headers: adminHeaders()})).json();
  assert.ok(devices.every(d => safeText(d.label) && safeText(d.app_version)));
});

test('revocation is final: approve refuses a revoked device, and its old secret stays refused', async t => {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const lost = await activeDevice(env, 23);
  assert.equal((await revoke(env, lost)).status, 200);
  const etag = bucket.objects.get(deviceKey(lost)).etag;
  const again = await approve(env, lost);
  assert.equal(again.status, 409);
  const refusal = await detail(again);
  assert.equal(refusal.code, 'device_revoked');
  assert.ok(refusal.message.includes(lost.id.slice(0, 4).toUpperCase()));
  assert.equal(bucket.objects.get(deviceKey(lost)).etag, etag);
  assert.equal(bucket.readJson(deviceKey(lost)).status, 'revoked');
  const upload = await call(env, '/v1/diagnostics/upload', {method: 'POST', headers: deviceHeaders(lost), body: 'x'});
  assert.equal(upload.status, 403);
  assert.equal((await detail(upload)).code, 'device_revoked');
  assert.equal((await revoke(env, lost)).status, 200);           // revoking again is a no-op
  assert.equal(bucket.objects.get(deviceKey(lost)).etag, etag);
});

test('approve and revoke are compare-and-swap: a change written between the read and the write is never overwritten', async t => {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const put = bucket.put.bind(bucket);
  // Runs `between` once, just before the first write of `status` to `device`'s record.
  const interleave = (device, status, between) => {
    let armed = true, answer = null;
    bucket.put = async (key, value, options) => {
      if (armed && key === deviceKey(device) && JSON.parse(value).status === status) {
        armed = false;
        answer = await between();
      }
      return put(key, value, options);
    };
    return () => answer;
  };
  // An approve that read "pending" while a revoke lands: the revoke stands and the approve is refused.
  const lost = newDevice(24);
  await register(env, lost);
  const revokedBetween = interleave(lost, 'active', () => revoke(env, lost));
  const approved = await approve(env, lost);
  assert.equal(revokedBetween().status, 200);
  assert.equal(approved.status, 409);
  assert.equal((await detail(approved)).code, 'device_revoked');
  assert.equal(bucket.readJson(deviceKey(lost)).status, 'revoked');
  assert.equal(bucket.objects.get(deviceKey(lost)).customMetadata.status, 'revoked');
  // A revoke that read "pending" while an approve lands: the revoke is written over the approval, as the last answer says.
  const other = newDevice(25);
  await register(env, other);
  const approvedBetween = interleave(other, 'revoked', () => approve(env, other));
  const revoked = await revoke(env, other);
  assert.equal(approvedBetween().status, 200);
  assert.equal(revoked.status, 200);
  assert.equal((await revoked.json()).status, 'revoked');
  const record = bucket.readJson(deviceKey(other));
  assert.equal(record.status, 'revoked');
  assert.ok(record.approved_at && record.revoked_at);
});
