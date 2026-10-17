// Shared helpers for the AUTH_MODE=enforce tests. Every credential here is an obvious fake.
import { createHash } from 'node:crypto';
import worker from '../dist/index.js';
import { FakeR2 } from './fake_r2.mjs';

export { FakeR2 };
export const ADMIN = 'fake-admin-token-for-tests-only';
export const PREFIX = 'state/test/';

export const enforceEnv = (bucket, extra = {}) => ({MODEL_ID: 'projec-mutta/2', CONFIDENCE: '35', OVERLAP: '50', MAX_VIEW_COUNT_RATIO: '1.25',
  EGGS_PER_TRAY: '30', ROBOFLOW_API_KEY: 'test-only', SCAN_ARCHIVE: bucket, AUTH_MODE: 'enforce', STATE_PREFIX: PREFIX, ADMIN_TOKEN: ADMIN, ...extra});
export const observeEnv = (bucket, extra = {}) => enforceEnv(bucket, {AUTH_MODE: 'observe', ...extra});

export const call = (env, path, {method = 'GET', headers = {}, body} = {}) =>
  worker.fetch(new Request(`https://local${path}`, {method, headers, body}), env);
export const sendJson = (env, path, value, headers = {}) =>
  call(env, path, {method: 'POST', headers: {'content-type': 'application/json', ...headers}, body: JSON.stringify(value)});

// 32 fake bytes, base64url without padding (43 characters), like the app's secret.
export const fakeSecret = (n) => Buffer.from(`fake-device-secret-${n}`.padEnd(32, '.')).toString('base64url');
export const newDevice = (n) => ({id: crypto.randomUUID(), secret: fakeSecret(n)});
export const deviceHeaders = (device) => ({'x-device-id': device.id, authorization: `Device ${device.secret}`});
export const adminHeaders = (token = ADMIN) => ({authorization: `Bearer ${token}`});

export const register = (env, device, extra = {}) =>
  sendJson(env, '/v1/devices', {device_id: device.id, secret: device.secret, label: 'test phone', app_version: '0.4.12+23', ...extra});
export const approve = (env, device) => call(env, `/v1/admin/devices/${device.id}/approve`, {method: 'POST', headers: adminHeaders()});
export const revoke = (env, device) => call(env, `/v1/admin/devices/${device.id}/revoke`, {method: 'POST', headers: adminHeaders()});

export async function activeDevice(env, n) {
  const device = newDevice(n);
  if ((await register(env, device)).status !== 200) throw new Error('register failed');
  if ((await approve(env, device)).status !== 200) throw new Error('approve failed');
  return device;
}

// Three distinct JPEG-signed photos; `seed` changes their bytes (a retake).
export const photoBytes = (seed) => ['left', 'right', 'straight'].map((_, i) => new Uint8Array([255, 216, 255, i, seed]));
// contract: the scan_contract field (null leaves it out); cells: {view: cell id} sent as <view>_cell_id.
export function scanForm(scanId, seed = 0, {contract = 'model_spatial_v1', cells = {}} = {}) {
  const form = new FormData();
  if (contract !== null) form.set('scan_contract', contract);
  if (scanId) form.set('scan_id', scanId);
  for (const [view, id] of Object.entries(cells)) form.set(`${view}_cell_id`, id);
  photoBytes(seed).forEach((bytes, i) => form.set(['left', 'right', 'straight'][i], new File([bytes], `${i}.jpg`, {type: 'image/jpeg'})));
  return form;
}
export const postScan = (env, scanId, headers, seed = 0, options = {}) =>
  call(env, '/v1/scans/count', {method: 'POST', headers, body: scanForm(scanId, seed, options)});

const sha = (data) => createHash('sha256').update(data).digest('hex');
// The job identity the Worker writes (fingerprint version 2): SHA-256 of the JSON array
// [2, left, right, straight, scan_contract, [[view, cell id], ...] sorted by view].
export function jobIdentity(seed = 0, {contract = 'model_spatial_v1', cells = {}} = {}) {
  const [left, right, straight] = photoBytes(seed).map(sha);
  const cellIds = Object.fromEntries(Object.entries(cells).map(([view, id]) => [view, id.trim().toUpperCase()]).sort(([a], [b]) => (a < b ? -1 : 1)));
  return {image_hashes: {left, right, straight}, fingerprint: sha(JSON.stringify([2, left, right, straight, contract, Object.entries(cellIds)])),
    fingerprint_version: 2, scan_contract: contract, cell_ids: cellIds};
}
// A job written before fingerprint version 2: SHA-256 of the ordered view hashes joined with '|', no other fields.
export function legacyJobIdentity(seed = 0) {
  const [left, right, straight] = photoBytes(seed).map(sha);
  return {image_hashes: {left, right, straight}, fingerprint: sha(`${left}|${right}|${straight}`)};
}
export const jobKey = (scanId) => `${PREFIX}jobs/${scanId}.json`;
// Manual counts written by the enforced route; the legacy scans/ keys are what the open route writes.
export const manualPrefix = (scanId) => `${PREFIX}manual-counts/${scanId}/`;
export const manualKey = (scanId, name) => `${manualPrefix(scanId)}${name}.json`;
export const legacyManualKey = (scanId, name) => `scans/${scanId}/manual-count/${name}.json`;

// One 20-layer stack column per photo, so the block model has something to count.
const column = Array.from({length: 20}, (_, k) => ({class: 'egg_tray', confidence: .9, x: 400, y: 100 + k * 40, width: 500, height: 36}));
// Mocks Roboflow. status: HTTP status to answer with; gate: a promise inference waits on (first `gated` calls only).
// Per call n (1-based): gates[n] is a promise that call waits on; failing.has(n) answers that call with HTTP 500.
export function mockInference(t, {status = 200, gate = null, gated = Infinity, gates = {}, failing = new Set()} = {}) {
  const state = {calls: 0, status, failing};
  t.mock.method(globalThis, 'fetch', async () => {
    const n = ++state.calls;
    if (gate && n <= gated) await gate;
    if (gates[n]) await gates[n];
    const failed = state.status !== 200 ? state.status : state.failing.has(n) ? 500 : 0;
    if (failed) return new Response('upstream failure', {status: failed});
    return Response.json({predictions: column, image: {width: 800, height: 1000}});
  });
  return state;
}

export function deferred() {
  let resolve;
  const promise = new Promise((r) => { resolve = r; });
  return {promise, resolve};
}

// Lets pending requests run until `done()` is true (or gives up).
export async function until(done, rounds = 500) {
  for (let i = 0; i < rounds && !done(); i++) await new Promise((r) => setImmediate(r));
  if (!done()) throw new Error('condition not reached');
}

export function captureLogs(t) {
  const lines = [];
  t.mock.method(console, 'log', (line) => lines.push(String(line)));
  t.mock.method(console, 'error', (line) => lines.push(String(line)));
  return lines;
}
