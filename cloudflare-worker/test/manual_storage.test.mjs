// Manual counts under STATE_PREFIX, the merged admin listing, the per-scan manual-count route and the archive's job
// photos. Staging and production bind one bucket and production runs open: its open manual-count route writes
// scans/<id>/manual-count/latest.json for any scan id, so the enforced route never stores there.
import assert from 'node:assert/strict';
import test from 'node:test';
import { FakeR2, enforceEnv, observeEnv, call, sendJson, adminHeaders, deviceHeaders, activeDevice, postScan, mockInference,
  jobIdentity, manualKey, manualPrefix, legacyManualKey, captureLogs } from './enforce_support.mjs';

const cells = [{x: 0, y: 0, app_layers: 20, app_status: 'observed', filled: 20, empty: 0}];
const at = (offsetMs) => new Date(Date.now() + offsetMs).toISOString();
const manual = (fields = {}) => ({block_id: 'B01', notes: '', cells, app_version: '0.4.12+23', app_total: 20,
  count_id: crypto.randomUUID(), created_at: at(-60_000), ...fields});
const saveManual = (env, scanId, body, headers = {}) => sendJson(env, `/v1/scans/${scanId}/manual-count`, body, headers);
const readManual = (env, scanId, headers = {}) => call(env, `/v1/scans/${scanId}/manual-count`, {headers});
const code = async (response) => (await response.json()).detail.code;
// The production Worker on the same bucket: the same env without AUTH_MODE.
const openTwin = ({AUTH_MODE: _mode, ...env}) => env;
const encodeCursor = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');

async function setup(t, makeEnv = enforceEnv, bucket = new FakeR2()) {
  captureLogs(t);
  const inference = mockInference(t);
  const env = makeEnv(bucket);
  const device = await activeDevice(env, 1);
  return {bucket, env, device, headers: deviceHeaders(device), inference};
}

for (const [mode, makeEnv] of [['enforce', enforceEnv], ['observe', observeEnv]]) {
  test(`${mode}: manual counts are stored only under the state prefix; the open route writing scans/ cannot change them`, async t => {
    const {bucket, env, headers} = await setup(t, makeEnv);
    const scanId = crypto.randomUUID();
    assert.equal((await postScan(env, scanId, headers)).status, 200);
    const first = manual({created_at: at(-120_000)});
    const correction = manual({created_at: at(-60_000), app_total: 19});
    for (const body of [first, correction]) assert.equal((await saveManual(env, scanId, body, headers)).status, 200);
    assert.deepEqual(bucket.keys(`scans/${scanId}/manual-count/`), []);
    assert.deepEqual(bucket.keys(manualPrefix(scanId)), [first.count_id, correction.count_id, 'latest'].sort().map(name => manualKey(scanId, name)));
    assert.equal(bucket.objects.get(manualKey(scanId, 'latest')).customMetadata.count_id, correction.count_id);
    // Production's open route on the shared bucket writes the legacy key only.
    const forged = await saveManual(openTwin(env), scanId, {block_id: 'FORGED', cells: [{...cells[0], filled: 1}]});
    assert.equal(forged.status, 200);
    assert.equal(bucket.readJson(legacyManualKey(scanId, 'latest')).block_id, 'FORGED');
    assert.equal(bucket.readJson(manualKey(scanId, 'latest')).count_id, correction.count_id);
    const read = await readManual(env, scanId, headers);
    assert.equal(read.status, 200);
    const body = await read.json();
    assert.equal(body.scan_id, scanId);
    assert.equal(body.storage, 'state');
    assert.equal(body.latest.count_id, correction.count_id);
    assert.equal(body.latest.app_total, 19);
    assert.equal(body.latest.tamper_proof, true);
    assert.deepEqual(body.count_ids, [first.count_id, correction.count_id].sort());
    assert.deepEqual(body.legacy_count_ids, []);   // the open route names its file by time, not by count id
  });
}

test('per-scan manual count: the owner or the admin; a scan with a job reads only the state record, the legacy one is shown apart', async t => {
  const {bucket, env, headers} = await setup(t);
  const scanId = crypto.randomUUID();
  assert.equal((await postScan(env, scanId, headers)).status, 200);
  // A scan with a job and nothing saved yet.
  assert.deepEqual(await (await readManual(env, scanId, headers)).json(),
    {scan_id: scanId, latest: null, storage: null, count_ids: [], legacy_count_ids: [], legacy_latest: null});
  // A record under scans/ for a scan with a job never came from its owner (a 0.4.12 client always saves with its
  // credential, under the state prefix): it is not the latest count, only shown apart, tagged.
  const older = crypto.randomUUID();
  await bucket.seed(legacyManualKey(scanId, older), {kind: 'manual_count_v1', scan_id: scanId, count_id: older, block_id: 'B01'});
  await bucket.seed(legacyManualKey(scanId, 'latest'), {kind: 'manual_count_v1', scan_id: scanId, count_id: older, block_id: 'B01'});
  const shadowed = await (await readManual(env, scanId, headers)).json();
  assert.equal(shadowed.latest, null);
  assert.equal(shadowed.storage, null);
  assert.equal(shadowed.legacy_latest.count_id, older);
  assert.equal(shadowed.legacy_latest.storage, 'legacy_scans');
  assert.equal(shadowed.legacy_latest.tamper_proof, false);
  assert.match(shadowed.legacy_latest.storage_note, /not tamper-proof/);
  assert.deepEqual([shadowed.count_ids, shadowed.legacy_count_ids], [[], [older]]);
  // A count saved under the state prefix is the latest.
  const saved = manual();
  await saveManual(env, scanId, saved, headers);
  const current = await (await readManual(env, scanId, adminHeaders())).json();
  assert.deepEqual([current.storage, current.latest.count_id, current.count_ids, current.legacy_count_ids, current.legacy_latest.count_id],
    ['state', saved.count_id, [saved.count_id], [older], older]);
  // Another device, no credential, a bad id.
  const other = await activeDevice(env, 2);
  assert.equal(await code(await readManual(env, scanId, deviceHeaders(other))), 'scan_forbidden');
  assert.equal(await code(await readManual(env, scanId)), 'device_credentials_required');
  assert.equal((await readManual(env, 'not-a-uuid', adminHeaders())).status, 422);
  // A scan without a job (counted before 0.4.12): the admin only, and its legacy record is its latest count.
  const legacyScan = crypto.randomUUID();
  await bucket.seed(legacyManualKey(legacyScan, 'latest'), {kind: 'manual_count_v1', scan_id: legacyScan, block_id: 'B07', recorded_at: at(-1000)});
  assert.equal(await code(await readManual(env, legacyScan, headers)), 'scan_not_found');
  const legacy = await (await readManual(env, legacyScan, adminHeaders())).json();
  assert.equal(legacy.latest.block_id, 'B07');
  assert.equal(legacy.storage, 'legacy_scans');
  assert.equal(legacy.legacy_latest, null);
  // The admin may save a state count for it (archived photos): that one wins, the legacy record is shown apart.
  await bucket.put(`scans/${legacyScan}/left/${'d'.repeat(64)}`, 'photo');
  const admin = manual();
  assert.equal((await saveManual(env, legacyScan, admin, adminHeaders())).status, 200);
  const both = await (await readManual(env, legacyScan, adminHeaders())).json();
  assert.deepEqual([both.storage, both.latest.count_id, both.legacy_latest.block_id], ['state', admin.count_id, 'B07']);
  assert.deepEqual(await (await readManual(env, crypto.randomUUID(), adminHeaders())).json().then(b => [b.latest, b.storage, b.count_ids, b.legacy_latest]),
    [null, null, [], null]);
});

test('production and observe Workers on one bucket: a scans/ count planted for a scan with a job is never served or listed as its count', async t => {
  const {env, headers} = await setup(t, observeEnv);
  const scanId = crypto.randomUUID();
  assert.equal((await postScan(env, scanId, headers)).status, 200);
  // Production's open route, then an anonymous observe request, write scans/<id>/manual-count/latest.json.
  assert.equal((await saveManual(openTwin(env), scanId, {block_id: 'PLANTED', cells: [{...cells[0], filled: 99}]})).status, 200);
  assert.equal((await saveManual(env, scanId, {block_id: 'PLANTED2', cells: [{...cells[0], filled: 98}]})).status, 200);
  for (const who of [adminHeaders(), headers]) {
    const body = await (await readManual(env, scanId, who)).json();
    assert.deepEqual([body.latest, body.storage, body.legacy_latest.block_id, body.legacy_latest.tamper_proof], [null, null, 'PLANTED2', false]);
  }
  const listing = async () => (await call(env, '/v1/manual-counts', {headers: adminHeaders()})).json();
  const before = await listing();
  assert.deepEqual([before.records, before.legacy_shadowed], [[], [{scan_id: scanId, by: 'scan_job'}]]);
  // The owner's count, sent later (after a lossy link), is the latest; the planted record stays out of the listing.
  const own = manual();
  assert.equal((await saveManual(env, scanId, own, headers)).status, 200);
  const read = await (await readManual(env, scanId, adminHeaders())).json();
  assert.deepEqual([read.storage, read.latest.count_id, read.legacy_latest.block_id], ['state', own.count_id, 'PLANTED2']);
  const after = await listing();
  assert.deepEqual(after.records.map(r => [r.storage, r.count_id]), [['state', own.count_id]]);
  assert.deepEqual(after.legacy_shadowed, [{scan_id: scanId, by: 'state'}]);
});

test('admin listing stops at `limit` inside an R2 page and within its R2 call budget; the cursor resumes after the last key read', async t => {
  captureLogs(t);
  const bucket = new FakeR2();
  const env = enforceEnv(bucket);
  const stateScans = Array.from({length: 450}, () => crypto.randomUUID());
  for (const id of stateScans) await bucket.seed(manualKey(id, 'latest'), {kind: 'manual_count_v1', scan_id: id, block_id: 'S'});
  const legacyScans = Array.from({length: 150}, () => crypto.randomUUID());
  for (const id of legacyScans) {
    await bucket.put(`scans/${id}/left/${'e'.repeat(64)}`, 'photo');
    await bucket.seed(legacyManualKey(id, 'latest'), {kind: 'manual_count_v1', scan_id: id, block_id: 'L'});
  }
  const page = async (limit, cursor) => {
    const before = bucket.ops.length;
    const response = await call(env, `/v1/manual-counts?limit=${limit}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`, {headers: adminHeaders()});
    assert.equal(response.status, 200);
    return {body: await response.json(), calls: bucket.ops.length - before};
  };
  const one = await page(1);
  assert.equal(one.body.records.length, 1);
  assert.ok(one.calls <= 2, `${one.calls} R2 calls for limit=1`);   // one list, one GET
  for (const limit of [500, 7]) {
    const seen = [];
    let cursor = null, pages = 0, most = 0;
    do {
      const {body, calls} = await page(limit, cursor);
      assert.ok(body.records.length <= limit);
      most = Math.max(most, calls);
      seen.push(...body.records.map(r => `${r.storage} ${r.scan_id}`));
      cursor = body.cursor;
      pages++;
    } while (cursor && pages < 200);
    assert.equal(cursor, null, `limit ${limit}`);
    assert.ok(most <= 400, `limit ${limit}: ${most} R2 calls in one request`);
    assert.ok(pages >= (limit === 500 ? 2 : 86), `limit ${limit}: ${pages} pages`);
    assert.deepEqual(seen.sort(), [...stateScans.map(id => `state ${id}`), ...legacyScans.map(id => `legacy_scans ${id}`)].sort());
  }
});

test('admin archive listing: one listing per view and for the manual counts, so open writes cannot push photos out; truncated names the prefix', async t => {
  const {bucket, env} = await setup(t, observeEnv);
  const scanId = crypto.randomUUID();
  assert.equal((await postScan(env, scanId, {})).status, 200);   // an anonymous observe scan: photos, no job
  // Production's open manual-count route adds one object per call under manual-count/, which sorts between left/ and right/.
  for (let i = 0; i < 120; i++) await bucket.seed(`scans/${scanId}/manual-count/2026-10-15T11-16-${String(i).padStart(3, '0')}Z.json`, {block_id: 'X'});
  const archive = async () => (await call(env, `/v1/scans/${scanId}/archive`, {headers: adminHeaders()})).json();
  const perView = (listing) => Object.fromEntries(['left', 'right', 'straight'].map(v => [v,
    listing.keys.filter(k => k.key.startsWith(`scans/${scanId}/${v}/`)).length]));
  const flooded = await archive();
  assert.deepEqual(perView(flooded), {left: 1, right: 1, straight: 1});
  assert.equal(flooded.job, null);
  assert.equal(flooded.truncated, true);
  assert.deepEqual(flooded.truncated_prefixes, [`scans/${scanId}/manual-count/`]);
  // A view with more than 100 photos is named too.
  for (let i = 0; i < 100; i++) await bucket.put(`scans/${scanId}/right/${String(i).padStart(64, '0')}`, 'photo');
  assert.deepEqual((await archive()).truncated_prefixes, [`scans/${scanId}/manual-count/`, `scans/${scanId}/right/`]);
  // Nothing truncated.
  const small = crypto.randomUUID();
  assert.equal((await postScan(env, small, {})).status, 200);
  const whole = await (await call(env, `/v1/scans/${small}/archive`, {headers: adminHeaders()})).json();
  assert.deepEqual([whole.keys.length, whole.truncated, whole.truncated_prefixes], [3, false, []]);
  // The open route's listing is unchanged: one listing of the scan prefix, at most 100 keys.
  const open = await (await call(openTwin(env), `/v1/scans/${scanId}/archive`)).json();
  assert.deepEqual([Object.keys(open), open.keys.length], [['scan_id', 'keys'], 100]);
});

test('admin listing: state records, then legacy records, tagged, with one cursor across both sources', async t => {
  const {bucket, env, headers} = await setup(t, enforceEnv, new FakeR2({pageCap: 2}));
  const stateScans = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
  for (const scanId of stateScans) {
    assert.equal((await postScan(env, scanId, headers)).status, 200);
    assert.equal((await saveManual(env, scanId, manual(), headers)).status, 200);
  }
  const legacyScans = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
  for (const [i, scanId] of legacyScans.entries()) {
    await bucket.put(`scans/${scanId}/left/${'b'.repeat(64)}`, 'photo');
    await bucket.seed(legacyManualKey(scanId, 'latest'), {kind: 'manual_count_v1', scan_id: scanId, block_id: `L${i}`});
  }
  // Production's open route also wrote legacy records for a state scan and for a scan with a job but no count yet:
  // neither is listed as a count (the state record wins; a scan with a job never has a legitimate scans/ record).
  assert.equal((await saveManual(openTwin(env), stateScans[0], {block_id: 'FORGED', cells})).status, 200);
  const uncounted = crypto.randomUUID();
  assert.equal((await postScan(env, uncounted, headers)).status, 200);
  assert.equal((await saveManual(openTwin(env), uncounted, {block_id: 'FORGED', cells})).status, 200);
  const expected = [...stateScans.map(id => `state ${id}`), ...legacyScans.map(id => `legacy_scans ${id}`)].sort();
  for (const limit of [1, 2, 100]) {
    const seen = [], shadowed = [];
    let cursor = null, pages = 0;
    do {
      const response = await call(env, `/v1/manual-counts?limit=${limit}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`, {headers: adminHeaders()});
      assert.equal(response.status, 200);
      const page = await response.json();
      assert.equal(page.count, page.records.length);
      assert.ok(page.records.length <= limit);
      for (const record of page.records) {
        assert.equal(record.tamper_proof, record.storage === 'state', record.scan_id);
        if (record.storage === 'legacy_scans') assert.match(record.storage_note, /not tamper-proof/);
        seen.push(`${record.storage} ${record.scan_id}`);
      }
      shadowed.push(...page.legacy_shadowed.map(s => `${s.by} ${s.scan_id}`));
      cursor = page.cursor;
      pages++;
    } while (cursor && pages < 30);
    assert.equal(cursor, null, `limit ${limit}`);
    assert.ok(pages > 1, `limit ${limit}: ${pages} pages`);    // 2 keys per R2 page: one call never reads both sources whole
    assert.deepEqual([...seen].sort(), expected, `limit ${limit}`);
    assert.deepEqual(shadowed.sort(), [`state ${stateScans[0]}`, `scan_job ${uncounted}`].sort(), `limit ${limit}`);
    // Every state record comes before every legacy one.
    assert.equal(seen.findIndex(s => s.startsWith('legacy')), stateScans.length, `limit ${limit}`);
  }
  // The cursor is {v, source, r2} in base64url: a cursor at the start of the legacy source lists legacy records only.
  const legacyOnly = (await (await call(env, `/v1/manual-counts?cursor=${encodeCursor({v: 1, source: 'legacy_scans', r2: null})}`,
    {headers: adminHeaders()})).json()).records;
  assert.ok(legacyOnly.length > 0 && legacyOnly.every(r => r.storage === 'legacy_scans'));
  for (const bad of ['garbage', encodeCursor({v: 1, source: 'other', r2: null}), encodeCursor({v: 2, source: 'state', r2: null}),
    encodeCursor({v: 1, source: 'state', r2: 'not-an-r2-cursor'}), encodeCursor({v: 1, source: 'state', r2: ''}),
    encodeCursor({v: 1, source: 'state', r2: null, after: `scans/${legacyScans[0]}/manual-count/latest.json`}),
    encodeCursor({v: 1, source: 'legacy_scans', r2: null, after: 7})]) {
    const refused = await call(env, `/v1/manual-counts?cursor=${encodeURIComponent(bad)}`, {headers: adminHeaders()});
    assert.equal(refused.status, 422, bad);
    assert.equal(await code(refused), 'invalid_cursor');
  }
});

test('the admin archive listing names the photos the scan job counted; the open route can add others under the prefix', async t => {
  const {bucket, env, headers, device} = await setup(t);
  const scanId = crypto.randomUUID();
  assert.equal((await postScan(env, scanId, headers)).status, 200);
  // Production (open) receives other photos under the same scan id.
  assert.equal((await postScan(openTwin(env), scanId, {}, 1)).status, 200);
  const listing = await (await call(env, `/v1/scans/${scanId}/archive`, {headers: adminHeaders()})).json();
  assert.equal(listing.keys.length, 6);
  assert.deepEqual(listing.job.image_hashes, jobIdentity(0).image_hashes);
  assert.deepEqual([listing.job.status, listing.job.owner, listing.job.attempt], ['done', device.id, 1]);
  for (const [view, hash] of Object.entries(listing.job.image_hashes)) {
    assert.ok(listing.keys.some(k => k.key === `scans/${scanId}/${view}/${hash}`), view);
  }
  const noJob = crypto.randomUUID();
  await bucket.put(`scans/${noJob}/left/${'c'.repeat(64)}`, 'photo');
  const old = await (await call(env, `/v1/scans/${noJob}/archive`, {headers: adminHeaders()})).json();
  assert.equal(old.job, null);
  assert.equal(old.keys.length, 1);
});
