import assert from 'node:assert/strict';
import test from 'node:test';
import worker from '../dist/index.js';
const env = {RECONSTRUCTION_ENABLED:'true', VISION_SERVICE_URL:'https://vision.example', VISION_SERVICE_TOKEN:'test-secret', SCAN_ARCHIVE:{put:async()=>{}}};
function request(second=2, mime='image/jpeg') {
 const form=new FormData();
 form.set('first',new File([new Uint8Array([255,216,255,1])],'a.jpg',{type:mime}));
 form.set('second',new File([new Uint8Array([255,216,255,second])],'b.jpg',{type:mime}));
 return new Request('https://local/v1/reconstruct',{method:'POST',body:form});
}
const result={status:'insufficient_matches',reason:'Need more overlap',physical_trays:null,verified:false,scale:'arbitrary_unit_baseline',focal_hypotheses:[]};
test('reconstruction is staging-only; production health and route unchanged',async()=>{
 const health=await (await worker.fetch(new Request('https://local/health'),{})).json();
 assert.deepEqual(health.scan_contracts,['cell_identity_v1','model_spatial_v1']);
 assert.equal((await worker.fetch(request(),{})).status,404);
 const staging=await (await worker.fetch(new Request('https://local/health'),env)).json();
 assert.ok(staging.scan_contracts.includes('reconstruct_v1'));
});
test('validates files before archiving or forwarding',async()=>{
 assert.equal((await worker.fetch(request(1),env)).status,422);
 assert.equal((await worker.fetch(request(2,'text/plain'),env)).status,415);
 assert.equal((await worker.fetch(new Request('https://local/v1/reconstruct',{method:'POST',body:'bad'}),env)).status,415);
});
test('archives exact hashes and forwards secret server-side',async t=>{
 const archive=[];
 t.mock.method(globalThis,'fetch',async(url,options)=>{
  assert.equal(String(url),'https://vision.example/candidate/reconstruct');
  assert.equal(options.headers.Authorization,'Bearer test-secret');
  assert.equal(options.body.get('first').size,4);
  return Response.json(result);
 });
 const response=await worker.fetch(request(),{...env,SCAN_ARCHIVE:{put:async(key)=>archive.push(key)}});
 assert.equal(response.status,200);
 const body=await response.json();
 assert.equal(archive.length,2); assert.ok(archive[0].endsWith(body.input_hashes.first));
 assert.match(archive[0],/^reconstruct\/[0-9a-f-]+\/first\/[0-9a-f]{64}$/);
 assert.equal(body.verified,false); assert.equal(body.physical_trays,null);
 assert.ok(!JSON.stringify(body).includes('test-secret'));
});
for(const [status,expected,code] of [[401,502,'vision_auth_failed'],[429,429,'vision_busy'],[503,502,'vision_unavailable']]) {
 test(`maps upstream ${status}`,async t=>{
  t.mock.method(globalThis,'fetch',async()=>new Response('private upstream error',{status}));
  const response=await worker.fetch(request(),env);
  assert.equal(response.status,expected); assert.equal((await response.json()).detail.code,code);
 });
}
test('rejects an upstream inventory claim',async t=>{
 t.mock.method(globalThis,'fetch',async()=>Response.json({...result,physical_trays:99,verified:true}));
 assert.equal((await worker.fetch(request(),env)).status,502);
});
