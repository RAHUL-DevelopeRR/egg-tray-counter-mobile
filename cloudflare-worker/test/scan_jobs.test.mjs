import assert from 'node:assert/strict';
import test from 'node:test';
import worker from '../dist/index.js';
import { FakeR2, enforceEnv, call, adminHeaders, deviceHeaders, activeDevice, postScan, scanForm, mockInference, jobIdentity,
  legacyJobIdentity, jobKey, deferred, until, captureLogs } from './enforce_support.mjs';

// Gated requests wait on each other: a regression must fail the test, not hang the run.
const LIMIT = {timeout: 10_000};
const resultOf = (env, scanId, headers) => call(env, `/v1/scans/${scanId}/result`, {headers});
const withoutJob = ({job, ...rest}) => rest;

async function setup(t, inference = {}) {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const device = await activeDevice(env, 1);
  return {bucket, env, device, headers: deviceHeaders(device), inference: mockInference(t, inference)};
}

// A job record as the Worker writes it, for states a test cannot reach by waiting (an expired lease).
const seedJob = (bucket, scanId, owner, fields) => {
  const now = new Date().toISOString();
  return bucket.seed(jobKey(scanId), {v: 1, scan_id: scanId, owner, ...jobIdentity(0), pipeline_version: 'worker-older', status: 'running',
    attempt: 1, lease_until: now, created_at: now, updated_at: now, ...fields}, {status: fields.status ?? 'running', owner});
};

test('first count processes and stores the full response; an identical retry replays it with no inference or archive write', LIMIT, async t => {
  const {bucket, env, headers, inference, device} = await setup(t);
  const scanId = crypto.randomUUID();
  const first = await postScan(env, scanId, headers);
  assert.equal(first.status, 200);
  const body = await first.json();
  assert.equal(body.scan_id, scanId);
  assert.equal(body.block.total_trays, 20);
  assert.equal(typeof body.job.pipeline_version, 'string');
  assert.deepEqual(body.job, {scan_id: scanId, status: 'done', attempt: 1, replayed: false, pipeline_version: body.job.pipeline_version});
  assert.equal(inference.calls, 3);
  assert.equal(bucket.stored(`scans/${scanId}/`), 3);
  const job = bucket.readJson(jobKey(scanId));
  assert.equal(job.status, 'done');
  assert.equal(job.owner, device.id);
  assert.deepEqual(job.image_hashes, jobIdentity(0).image_hashes);
  assert.equal(job.fingerprint, jobIdentity(0).fingerprint);
  assert.equal(job.fingerprint_version, 2);
  assert.equal(job.scan_contract, 'model_spatial_v1');
  assert.deepEqual(job.cell_ids, {});
  assert.deepEqual(job.result, body);
  assert.deepEqual(bucket.objects.get(jobKey(scanId)).customMetadata, {status: 'done', owner: device.id});
  const retry = await postScan(env, scanId, headers);
  assert.equal(retry.status, 200);
  const replayed = await retry.json();
  assert.equal(replayed.job.replayed, true);
  assert.deepEqual(withoutJob(replayed), withoutJob(body));
  assert.equal(inference.calls, 3);
  assert.equal(bucket.stored(`scans/${scanId}/`), 3);
  const result = await resultOf(env, scanId, headers);
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), replayed);
});

test('the same scan id with other photos is a conflict; another device is forbidden; the admin may replay', LIMIT, async t => {
  const {bucket, env, headers, inference} = await setup(t);
  const scanId = crypto.randomUUID();
  await postScan(env, scanId, headers);
  const retake = await postScan(env, scanId, headers, 1);
  assert.equal(retake.status, 409);
  assert.equal((await retake.json()).detail.code, 'scan_id_conflict');
  const other = await activeDevice(env, 2);
  const foreign = await postScan(env, scanId, deviceHeaders(other));
  assert.equal(foreign.status, 403);
  assert.equal((await foreign.json()).detail.code, 'scan_forbidden');
  const foreignResult = await resultOf(env, scanId, deviceHeaders(other));
  assert.equal(foreignResult.status, 403);
  assert.equal((await foreignResult.json()).detail.code, 'scan_forbidden');
  const admin = await postScan(env, scanId, adminHeaders());
  assert.equal(admin.status, 200);
  assert.equal((await admin.json()).job.replayed, true);
  assert.equal((await resultOf(env, scanId, adminHeaders())).status, 200);
  assert.equal(inference.calls, 3);
  assert.equal(bucket.stored(`scans/${scanId}/`), 3);
});

test('a duplicate upload while the first is still counting gets 202 processing, then the stored result', LIMIT, async t => {
  const gate = deferred();
  const {bucket, env, headers, inference} = await setup(t, {gate: gate.promise});
  const scanId = crypto.randomUUID();
  const first = postScan(env, scanId, headers);
  await until(() => inference.calls === 1);
  assert.equal(bucket.readJson(jobKey(scanId)).status, 'running');
  const duplicate = await postScan(env, scanId, headers);
  assert.equal(duplicate.status, 202);
  const busy = await duplicate.json();
  assert.equal(busy.detail.code, 'processing');
  assert.equal(busy.job.status, 'running');
  assert.ok(busy.job.retry_after_s >= 1 && busy.job.retry_after_s <= 5);
  assert.equal(duplicate.headers.get('retry-after'), String(busy.job.retry_after_s));
  const polled = await resultOf(env, scanId, headers);
  assert.equal(polled.status, 202);
  assert.equal((await polled.json()).detail.code, 'processing');
  gate.resolve();
  const done = await first;
  assert.equal(done.status, 200);
  assert.equal((await done.json()).job.replayed, false);
  const again = await postScan(env, scanId, headers);
  assert.equal(again.status, 200);
  assert.equal((await again.json()).job.replayed, true);
  assert.equal(inference.calls, 3);
  assert.equal(bucket.stored(`scans/${scanId}/`), 3);
});

test('five identical uploads at once: exactly one claims and counts, the rest are told to wait', LIMIT, async t => {
  const gate = deferred();
  const {bucket, env, headers, inference} = await setup(t, {gate: gate.promise});
  const scanId = crypto.randomUUID();
  const racing = Array.from({length: 5}, () => postScan(env, scanId, headers));
  await until(() => inference.calls === 1 && bucket.ops.filter(o => o.op === 'put' && o.key === jobKey(scanId) && !o.stored).length === 4);
  gate.resolve();
  const statuses = (await Promise.all(racing)).map(r => r.status).sort();
  assert.deepEqual(statuses, [200, 202, 202, 202, 202]);
  assert.equal(inference.calls, 3);
  assert.equal(bucket.stored(`scans/${scanId}/`), 3);
});

test('an expired lease is reported as interrupted and taken over as attempt 2', LIMIT, async t => {
  const {bucket, env, headers, inference, device} = await setup(t);
  const scanId = crypto.randomUUID();
  await seedJob(bucket, scanId, device.id, {lease_until: new Date(Date.now() - 1000).toISOString()});
  const interrupted = await resultOf(env, scanId, headers);
  assert.equal(interrupted.status, 409);
  const body = await interrupted.json();
  assert.equal(body.detail.code, 'processing_interrupted');
  assert.equal(body.job.status, 'running');
  const takeover = await postScan(env, scanId, headers);
  assert.equal(takeover.status, 200);
  const counted = await takeover.json();
  assert.equal(counted.job.attempt, 2);
  assert.equal(counted.job.replayed, false);
  assert.notEqual(counted.job.pipeline_version, 'worker-older');
  assert.equal(inference.calls, 3);
  assert.equal(bucket.readJson(jobKey(scanId)).status, 'done');
  // A valid lease is left alone: 202, no inference.
  const busyId = crypto.randomUUID();
  await seedJob(bucket, busyId, device.id, {lease_until: new Date(Date.now() + 60_000).toISOString()});
  assert.equal((await postScan(env, busyId, headers)).status, 202);
  assert.equal((await resultOf(env, busyId, headers)).status, 202);
  assert.equal(inference.calls, 3);
});

test('a failed count is stored as failed, answered 409 scan_failed, and retried by the next upload', LIMIT, async t => {
  const {bucket, env, headers, inference} = await setup(t, {status: 500});
  const scanId = crypto.randomUUID();
  const failed = await postScan(env, scanId, headers);
  assert.equal(failed.status, 502);
  const error = await failed.json();
  assert.equal(error.detail.code, 'inference_failed');
  assert.deepEqual(error.job, {scan_id: scanId, status: 'failed', attempt: 1, replayed: false, pipeline_version: error.job.pipeline_version});
  const job = bucket.readJson(jobKey(scanId));
  assert.equal(job.status, 'failed');
  assert.deepEqual(job.error, {status: 502, code: 'inference_failed', message: 'Roboflow inference is unavailable'});
  const result = await resultOf(env, scanId, headers);
  assert.equal(result.status, 409);
  const report = await result.json();
  assert.equal(report.detail.code, 'scan_failed');
  assert.equal(report.job.error.code, 'inference_failed');
  inference.status = 200;
  const retried = await postScan(env, scanId, headers);
  assert.equal(retried.status, 200);
  const counted = await retried.json();
  assert.equal(counted.job.attempt, 2);
  assert.equal(bucket.readJson(jobKey(scanId)).status, 'done');
  assert.equal(bucket.readJson(jobKey(scanId)).error, undefined);
  assert.equal((await resultOf(env, scanId, headers)).status, 200);
});

test('an unexpected error inside processing marks the job failed: never left running, never a count', LIMIT, async t => {
  const {bucket, env, headers, inference} = await setup(t);
  const scanId = crypto.randomUUID();
  bucket.failPut = key => key.startsWith('scans/');
  const crashed = await postScan(env, scanId, headers);
  assert.equal(crashed.status, 500);
  const body = await crashed.json();
  assert.equal(body.detail.code, 'internal_error');
  assert.equal(body.job.status, 'failed');
  assert.equal(body.total_trays, undefined);
  assert.equal(inference.calls, 0);
  assert.equal(bucket.readJson(jobKey(scanId)).status, 'failed');
  assert.equal((await (await resultOf(env, scanId, headers)).json()).detail.code, 'scan_failed');
  // When even the failure cannot be written, the lease is what recovers the job.
  const stuckId = crypto.randomUUID();
  bucket.failPut = key => key.startsWith('scans/') || (key === jobKey(stuckId) && bucket.readJson(key) !== null);
  assert.equal((await postScan(env, stuckId, headers)).status, 500);
  assert.equal(bucket.readJson(jobKey(stuckId)).status, 'running');
  assert.equal((await resultOf(env, stuckId, headers)).status, 202);
  const stuck = bucket.readJson(jobKey(stuckId));
  bucket.failPut = null;
  await bucket.seed(jobKey(stuckId), {...stuck, lease_until: new Date(Date.now() - 1).toISOString()}, {status: 'running', owner: stuck.owner});
  assert.equal((await (await resultOf(env, stuckId, headers)).json()).detail.code, 'processing_interrupted');
  const recovered = await postScan(env, stuckId, headers);
  assert.equal(recovered.status, 200);
  assert.equal((await recovered.json()).job.attempt, 2);
});

test('when a lease is lost mid-count, the attempt that stored a result first is the answer for both', LIMIT, async t => {
  const gate = deferred();
  // Only the first inference call (the slow Worker's) waits on the gate.
  const {bucket, env, headers, inference} = await setup(t, {gate: gate.promise, gated: 1});
  const scanId = crypto.randomUUID();
  const slow = postScan(env, scanId, headers);
  await until(() => inference.calls === 1);
  // The slow Worker's lease runs out while it is still waiting for inference.
  const running = bucket.readJson(jobKey(scanId));
  await bucket.seed(jobKey(scanId), {...running, lease_until: new Date(Date.now() - 1).toISOString()}, {status: 'running', owner: running.owner});
  const fast = await postScan(env, scanId, headers);
  assert.equal(fast.status, 200);
  const fastBody = await fast.json();
  assert.equal(fastBody.job.attempt, 2);
  gate.resolve();
  const late = await slow;
  assert.equal(late.status, 200);
  const lateBody = await late.json();
  assert.equal(lateBody.job.attempt, 2);
  assert.equal(lateBody.job.replayed, true);
  assert.deepEqual(withoutJob(lateBody), withoutJob(fastBody));
  assert.equal(bucket.readJson(jobKey(scanId)).attempt, 2);
  assert.equal(inference.calls, 6);
});

test('validation errors come before the claim: no job, and the corrected upload can use the same id', LIMIT, async t => {
  const {bucket, env, headers} = await setup(t);
  const scanId = crypto.randomUUID();
  const form = new FormData();
  form.set('scan_id', scanId);
  form.set('scan_contract', 'model_spatial_v1');
  for (const view of ['left', 'right', 'straight']) form.set(view, new File([new Uint8Array([255, 216, 255, 9])], 'same.jpg', {type: 'image/jpeg'}));
  const duplicate = await call(env, '/v1/scans/count', {method: 'POST', headers, body: form});
  assert.equal(duplicate.status, 422);
  assert.equal((await duplicate.json()).detail.code, 'duplicate_view');
  assert.equal(bucket.readJson(jobKey(scanId)), null);
  assert.equal((await postScan(env, scanId, headers)).status, 200);
});

test('result route: 404 for a scan never claimed, 422 for a bad id, credentials required', LIMIT, async t => {
  const {env, headers} = await setup(t);
  const missing = await resultOf(env, crypto.randomUUID(), headers);
  assert.equal(missing.status, 404);
  assert.equal((await missing.json()).detail.code, 'scan_not_found');
  assert.equal((await resultOf(env, 'not-a-uuid', headers)).status, 422);
  assert.equal((await resultOf(env, crypto.randomUUID(), {})).status, 401);
  assert.equal((await resultOf(env, crypto.randomUUID(), adminHeaders())).status, 404);
});

test('a job done by an older pipeline version is replayed as stored, never recounted after a deploy', LIMIT, async t => {
  const {bucket, env, headers, inference, device} = await setup(t);
  const scanId = crypto.randomUUID();
  const stored = {scan_id: scanId, total_trays: 7, block: {total_trays: 7},
    job: {scan_id: scanId, status: 'done', attempt: 1, replayed: false, pipeline_version: 'worker-older'}};
  await seedJob(bucket, scanId, device.id, {status: 'done', lease_until: new Date(Date.now() - 60_000).toISOString(), result: stored});
  const etag = bucket.objects.get(jobKey(scanId)).etag;
  const retry = await postScan(env, scanId, headers);
  assert.equal(retry.status, 200);
  const body = await retry.json();
  assert.deepEqual(body, {...stored, job: {...stored.job, replayed: true}});
  assert.equal(inference.calls, 0);
  assert.equal(bucket.stored(`scans/${scanId}/`), 0);
  assert.equal(bucket.objects.get(jobKey(scanId)).etag, etag);
  assert.deepEqual(await (await resultOf(env, scanId, headers)).json(), body);
});

test('a takeover that loses its compare-and-swap answers 202 processing and never counts', LIMIT, async t => {
  const {bucket, env, headers, inference, device} = await setup(t);
  const scanId = crypto.randomUUID();
  const key = jobKey(scanId);
  await seedJob(bucket, scanId, device.id, {lease_until: new Date(Date.now() - 1000).toISOString()});
  const put = bucket.put.bind(bucket);
  let armed = true;
  bucket.put = async (target, value, options = {}) => {
    if (armed && target === key && options.onlyIf && 'etagMatches' in options.onlyIf) {
      armed = false;
      // Another Worker takes the job over between this request's read and its compare-and-swap.
      const current = bucket.readJson(key);
      await put(key, JSON.stringify({...current, attempt: 2, lease_until: new Date(Date.now() + 60_000).toISOString()}),
        {customMetadata: {status: 'running', owner: current.owner}});
    }
    return put(target, value, options);
  };
  const lost = await postScan(env, scanId, headers);
  assert.equal(armed, false);
  assert.equal(lost.status, 202);
  const body = await lost.json();
  assert.equal(body.detail.code, 'processing');
  assert.equal(body.job.status, 'running');
  assert.equal(inference.calls, 0);
  assert.equal(bucket.stored(`scans/${scanId}/`), 0);
  assert.equal(bucket.readJson(key).attempt, 2);
});

test('the count runs under waitUntil, so it is stored even when the phone stops waiting for the answer', LIMIT, async t => {
  const gate = deferred();
  const {bucket, env, headers, inference} = await setup(t, {gate: gate.promise});
  const scanId = crypto.randomUUID();
  const waited = [];
  const ctx = {waitUntil: (promise) => waited.push(promise), passThroughOnException: () => {}};
  // Nobody awaits this response: the link dropped after the upload.
  const dropped = worker.fetch(new Request('https://local/v1/scans/count', {method: 'POST', headers, body: scanForm(scanId)}), env, ctx);
  await until(() => inference.calls === 1);
  assert.equal(waited.length, 1);
  gate.resolve();
  await waited[0];
  assert.equal(bucket.readJson(jobKey(scanId)).status, 'done');
  const result = await resultOf(env, scanId, headers);
  assert.equal(result.status, 200);
  assert.equal((await result.json()).job.replayed, true);
  assert.equal(inference.calls, 3);
  assert.equal((await dropped).status, 200);
});

test('an attempt that fails after losing its lease answers with the stored result, not "failed"', LIMIT, async t => {
  const first = deferred(), second = deferred();
  // Call 1 is the slow attempt's first view; call 2 is the takeover's first view, which fails.
  const {bucket, env, headers, inference} = await setup(t, {gates: {1: first.promise, 2: second.promise}, failing: new Set([2])});
  const scanId = crypto.randomUUID();
  const slow = postScan(env, scanId, headers);
  await until(() => inference.calls === 1);
  const running = bucket.readJson(jobKey(scanId));
  await bucket.seed(jobKey(scanId), {...running, lease_until: new Date(Date.now() - 1).toISOString()}, {status: 'running', owner: running.owner});
  const takeover = postScan(env, scanId, headers);
  await until(() => inference.calls === 2);
  first.resolve();
  const slowAnswer = await slow;
  assert.equal(slowAnswer.status, 200);
  const counted = await slowAnswer.json();
  assert.equal(counted.job.attempt, 1);
  assert.equal(bucket.readJson(jobKey(scanId)).status, 'done');
  second.resolve();
  const lost = await takeover;
  assert.equal(lost.status, 200);
  const replayed = await lost.json();
  assert.equal(replayed.job.replayed, true);
  assert.equal(replayed.job.attempt, 1);
  assert.deepEqual(withoutJob(replayed), withoutJob(counted));
  const job = bucket.readJson(jobKey(scanId));
  assert.equal(job.status, 'done');
  assert.equal(job.error, undefined);
  assert.equal((await resultOf(env, scanId, headers)).status, 200);
  assert.equal(inference.calls, 4);
});

test('an attempt that fails after losing its lease to a running takeover answers 202, and the takeover still counts', LIMIT, async t => {
  const first = deferred(), second = deferred();
  // Call 1 (the slow attempt) fails once released; the takeover's calls succeed.
  const {bucket, env, headers, inference} = await setup(t, {gates: {1: first.promise, 2: second.promise}, failing: new Set([1])});
  const scanId = crypto.randomUUID();
  const slow = postScan(env, scanId, headers);
  await until(() => inference.calls === 1);
  const running = bucket.readJson(jobKey(scanId));
  await bucket.seed(jobKey(scanId), {...running, lease_until: new Date(Date.now() - 1).toISOString()}, {status: 'running', owner: running.owner});
  const takeover = postScan(env, scanId, headers);
  await until(() => inference.calls === 2);
  first.resolve();
  const slowAnswer = await slow;
  assert.equal(slowAnswer.status, 202);
  const busy = await slowAnswer.json();
  assert.equal(busy.detail.code, 'processing');
  assert.equal(busy.job.attempt, 2);
  const holder = bucket.readJson(jobKey(scanId));
  assert.equal(holder.status, 'running');
  assert.equal(holder.attempt, 2);
  second.resolve();
  const done = await takeover;
  assert.equal(done.status, 200);
  const counted = await done.json();
  assert.equal(counted.job.attempt, 2);
  assert.equal(counted.job.replayed, false);
  assert.equal(bucket.readJson(jobKey(scanId)).status, 'done');
  assert.equal(inference.calls, 4);
});

// The lease outlives the longest life of an attempt whose phone gave up (90 s receive timeout + 30 s of waitUntil after
// the disconnect) and ends well inside the app's 3-minute wait for the result, so an interrupted count is taken over
// (409 processing_interrupted, then an upload) before the app reports the result lost.
test('the job lease is 150 s for a claim and for a takeover; retry_after_s stays capped at 5 s', LIMIT, async t => {
  const gate = deferred();
  const {bucket, env, headers, inference, device} = await setup(t, {gate: gate.promise});
  const scanId = crypto.randomUUID();
  const first = postScan(env, scanId, headers);
  await until(() => inference.calls === 1);
  const running = bucket.readJson(jobKey(scanId));
  assert.equal(Date.parse(running.lease_until) - Date.parse(running.created_at), 150_000);
  const busy = await postScan(env, scanId, headers);
  assert.equal(busy.status, 202);
  assert.equal((await busy.json()).job.retry_after_s, 5);
  assert.equal(busy.headers.get('retry-after'), '5');
  gate.resolve();
  assert.equal((await first).status, 200);
  const expiredId = crypto.randomUUID();
  await seedJob(bucket, expiredId, device.id, {lease_until: new Date(Date.now() - 1000).toISOString()});
  const before = Date.now();
  assert.equal((await postScan(env, expiredId, headers)).status, 200);
  const lease = Date.parse(bucket.readJson(jobKey(expiredId)).lease_until);
  assert.ok(lease >= before + 150_000 && lease <= Date.now() + 150_000, `lease ${lease - before} ms`);
});

test('the same photos with another scan_contract or other cell ids are a conflict, not a replay', LIMIT, async t => {
  const {bucket, env, headers, inference} = await setup(t);
  const scanId = crypto.randomUUID();
  const cells = {left: 'A1', right: 'A1', straight: 'A1'};
  assert.equal((await postScan(env, scanId, headers, 0, {cells})).status, 200);
  const job = bucket.readJson(jobKey(scanId));
  const identity = jobIdentity(0, {cells});
  assert.equal(job.fingerprint, identity.fingerprint);
  assert.notEqual(job.fingerprint, legacyJobIdentity(0).fingerprint);
  assert.deepEqual([job.fingerprint_version, job.scan_contract, job.cell_ids], [2, 'model_spatial_v1', cells]);
  // The same request (cell ids are trimmed and upper-cased as the Worker reads them) replays.
  const same = await postScan(env, scanId, headers, 0, {cells: {straight: 'a1', left: ' a1 ', right: 'A1'}});
  assert.equal(same.status, 200);
  assert.equal((await same.json()).job.replayed, true);
  for (const options of [{contract: 'cell_identity_v1', cells}, {contract: null, cells}, {cells: {...cells, straight: 'B1'}},
    {cells: {left: 'A1', right: 'A1'}}, {cells: {}}]) {
    const conflict = await postScan(env, scanId, headers, 0, options);
    assert.equal(conflict.status, 409, JSON.stringify(options));
    assert.equal((await conflict.json()).detail.code, 'scan_id_conflict');
  }
  assert.equal(inference.calls, 3);
  assert.equal(bucket.stored(`scans/${scanId}/`), 3);
  assert.equal(bucket.readJson(jobKey(scanId)).fingerprint, identity.fingerprint);
});

test('a job written before fingerprint version 2 replays for the same photos whatever the metadata; a takeover upgrades it', LIMIT, async t => {
  const {bucket, env, headers, inference, device} = await setup(t);
  const scanId = crypto.randomUUID();
  const now = new Date().toISOString();
  const stored = {scan_id: scanId, total_trays: 7, block: {total_trays: 7},
    job: {scan_id: scanId, status: 'done', attempt: 1, replayed: false, pipeline_version: 'worker-0.4.12'}};
  // Exactly the fields the previous build wrote: no fingerprint_version, scan_contract or cell_ids.
  const old = {v: 1, scan_id: scanId, owner: device.id, ...legacyJobIdentity(0), pipeline_version: 'worker-0.4.12', status: 'done',
    attempt: 1, lease_until: now, created_at: now, updated_at: now, result: stored};
  await bucket.seed(jobKey(scanId), old, {status: 'done', owner: device.id});
  const etag = bucket.objects.get(jobKey(scanId)).etag;
  for (const options of [{}, {cells: {left: 'A1'}}, {contract: null}]) {
    const retry = await postScan(env, scanId, headers, 0, options);
    assert.equal(retry.status, 200, JSON.stringify(options));
    assert.deepEqual(await retry.json(), {...stored, job: {...stored.job, replayed: true}});
  }
  assert.equal((await (await postScan(env, scanId, headers, 1)).json()).detail.code, 'scan_id_conflict');
  assert.equal(bucket.objects.get(jobKey(scanId)).etag, etag);
  assert.equal(inference.calls, 0);
  // An interrupted old-format job is taken over by the same photos and then carries this build's identity.
  const interruptedId = crypto.randomUUID();
  const {result: _result, ...running} = old;
  await bucket.seed(jobKey(interruptedId), {...running, scan_id: interruptedId, status: 'running',
    lease_until: new Date(Date.now() - 1000).toISOString()}, {status: 'running', owner: device.id});
  const takeover = await postScan(env, interruptedId, headers, 0, {cells: {left: 'A1'}});
  assert.equal(takeover.status, 200);
  assert.equal((await takeover.json()).job.attempt, 2);
  const upgraded = bucket.readJson(jobKey(interruptedId));
  const identity = jobIdentity(0, {cells: {left: 'A1'}});
  assert.deepEqual([upgraded.fingerprint, upgraded.fingerprint_version, upgraded.scan_contract, upgraded.cell_ids],
    [identity.fingerprint, 2, 'model_spatial_v1', {left: 'A1'}]);
  assert.equal(upgraded.status, 'done');
  assert.equal((await postScan(env, interruptedId, headers, 0, {cells: {left: 'A1'}})).status, 200);
  assert.equal((await postScan(env, interruptedId, headers, 0)).status, 409);
  assert.equal(inference.calls, 3);
});
