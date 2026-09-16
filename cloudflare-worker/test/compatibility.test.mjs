import assert from 'node:assert/strict';
import test from 'node:test';
import worker from '../dist/index.js';

test('installed APK preflight and both no-ID client generations remain compatible', async t => {
  const env = {MODEL_ID:'projec-mutta/2', CONFIDENCE:'35', OVERLAP:'50',
    MAX_VIEW_COUNT_RATIO:'1.25', EGGS_PER_TRAY:'30', ROBOFLOW_API_KEY:'test-only'};
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    calls++;
    return Response.json({predictions: [{class:'egg_tray', confidence:.9, x:10, y:10, width:5, height:5}]});
  });
  const health = await (await worker.fetch(new Request('https://local/health'), env)).json();
  assert.equal(health.status, 'ok');
  assert.ok(health.scan_contracts.includes('model_spatial_v1'));
  const scan = async contract => {
    const form = new FormData();
    if (contract) form.set('scan_contract', contract);
    ['left','right','straight'].forEach((view,i) => form.set(view,
      new File([new Uint8Array([255,216,255,i])], `${view}.jpg`, {type:'image/jpeg'})));
    return worker.fetch(new Request('https://local/v1/scans/count', {method:'POST',body:form}),env);
  };
  const legacyResponse = await scan();
  assert.equal(legacyResponse.status, 200);
  const legacy = await legacyResponse.json();
  assert.equal(legacy.processing.mode, 'cloudflare_roboflow_egg_tray_baseline');
  assert.equal(legacy.total_trays, 1);
  const modernResponse = await scan('model_spatial_v1');
  assert.equal(modernResponse.status, 200);
  const modern = await modernResponse.json();
  assert.equal(modern.processing.mode, 'model_spatial_v1');
  assert.deepEqual(modern.cell_ids, {});
  assert.equal(modern.views.left.detections.length, 1);
  assert.equal(modern.accepted, false);
  assert.equal(modern.total_trays, null);
  const unsupported = await scan('unknown');
  assert.equal(unsupported.status, 422);
  assert.equal(calls, 6);
});
