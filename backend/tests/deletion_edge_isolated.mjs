// Executes the real Edge handler with fake clients and no network or secrets.
// Run with Node 22+: node --experimental-strip-types backend/tests/deletion_edge_isolated.mjs
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const dir=await mkdtemp(join(tmpdir(),'papi-deletion-handler-'));
const source=await readFile(resolve('backend/functions/delete-coffee-account/index.ts'),'utf8');
const importLine='import { createClient } from "npm:@supabase/supabase-js@2.118.0";';
if (!source.includes(importLine)) throw new Error('Unexpected handler import');
await writeFile(join(dir,'handler.ts'),source.replace(importLine,'const createClient = globalThis.__papiTestCreateClient;'));

const owner='00000000-0000-4000-8000-000000000001';
const other='00000000-0000-4000-8000-000000000002';
const receipt='a'.repeat(64);
let handler, scenario;
globalThis.Deno={
  env:{get:key=>({SUPABASE_URL:'https://isolated.invalid',SUPABASE_ANON_KEY:'test-anon',SUPABASE_SERVICE_ROLE_KEY:'test-service',PAPI_DELETION_IMPLEMENTATION_READY:'true'})[key]},
  serve:fn=>{handler=fn;},
};
globalThis.__papiTestCreateClient=(url,key)=>{
  assert.equal(url,'https://isolated.invalid');
  if (key==='test-anon') return {
    auth:{getUser:async()=>({data:{user:{id:owner}},error:null})},
    rpc:async name=>{assert.equal(name,'begin_coffee_deletion');return scenario.start;},
  };
  assert.equal(key,'test-service');
  return {
    storage:{from:bucket=>{
      assert.equal(bucket,'coffee-media');
      return {remove:async names=>{
        scenario.events.push('remove');
        if (scenario.removeError) return {error:{message:'storage unavailable'}};
        scenario.files=scenario.files.filter(file=>!names.includes(file));
        return {error:null};
      }};
    }},
    auth:{admin:{deleteUser:async id=>{
      scenario.events.push('deleteUser');assert.equal(id,owner);
      if (scenario.deleteError) return {error:{message:'auth unavailable'}};
      scenario.exists=false;return {error:null};
    }}},
    rpc:async name=>{
      if (name==='coffee_deletion_available') return {data:true,error:null};
      if (name==='coffee_deletion_work') return {data:scenario.lookups.length ? scenario.lookups.shift() : (scenario.work ? [scenario.work] : []),error:null};
      if (name==='coffee_deletion_sessions_cleared') return {data:scenario.sessionsCleared ?? false,error:null};
      if (name==='coffee_deletion_files') return {data:scenario.files.map(name=>({name})),error:null};
      if (name==='coffee_deletion_storage_clear') return {data:scenario.storageClear ?? scenario.files.length===0,error:null};
      if (name==='coffee_deletion_user_exists') return {data:scenario.exists,error:null};
      if (name==='complete_coffee_deletion') {
        scenario.events.push('complete');
        if (scenario.finishError) return {data:null,error:{message:'database unavailable'}};
        scenario.work={owner_id:null,state:'complete'};return {data:true,error:null};
      }
      throw new Error(`Unexpected operation ${name}`);
    },
  };
};
const request=()=>new Request('https://isolated.invalid/delete',{method:'POST',headers:{authorization:'Bearer test-token'},body:JSON.stringify({receipt})});
const run=async (lookups,start)=>{
  scenario={lookups,start};
  const response=await handler(request());
  return {status:response.status,body:await response.json()};
};
try {
  await import(pathToFileURL(join(dir,'handler.ts')).href);
  assert.equal(typeof handler,'function');
  assert.deepEqual(await run([[],[{owner_id:owner,state:'requested'}]],{data:null,error:{message:'concurrent start'}}),{status:202,body:{status:'pending'}});
  assert.deepEqual(await run([[],[{owner_id:null,state:'complete'}]],{data:null,error:{message:'concurrent start'}}),{status:200,body:{status:'complete'}});
  assert.equal((await run([[],[{owner_id:other,state:'requested'}]],{data:null,error:{message:'start failed'}})).status,409);
  assert.equal((await run([[],[]],{data:null,error:{message:'purchase pending'}})).status,409);
  assert.equal((await run([[],[{owner_id:other,state:'requested'}]],{data:true,error:null})).status,503);
  assert.deepEqual(await run([[{owner_id:null,state:'complete'}]],null),{status:200,body:{status:'complete'}});
  assert.equal((await handler(new Request('https://isolated.invalid/delete',{method:'POST',body:'{}'}))).status,400);
  // The mocked failure must preserve the account; retry completes in order.
  scenario={lookups:[],work:{owner_id:owner,state:'requested'},sessionsCleared:true,files:[`${owner}/owned.jpg`],exists:true,events:[],removeError:true};
  assert.equal((await handler(request())).status,503);assert.deepEqual(scenario.events,['remove']);assert.equal(scenario.exists,true);
  scenario.removeError=false;
  assert.equal((await handler(request())).status,200);assert.deepEqual(scenario.events,['remove','remove','deleteUser','complete']);assert.equal(scenario.exists,false);
  scenario={lookups:[],work:{owner_id:owner,state:'requested'},sessionsCleared:true,files:[`${other}/foreign.jpg`],exists:true,events:[]};
  assert.equal((await handler(request())).status,503);assert.deepEqual(scenario.events,[]);assert.equal(scenario.exists,true);
  // If the last database acknowledgement fails, retry must not delete twice.
  scenario={lookups:[],work:{owner_id:owner,state:'requested'},sessionsCleared:true,files:[],exists:true,events:[],finishError:true};
  assert.equal((await handler(request())).status,202);assert.deepEqual(scenario.events,['deleteUser','complete']);
  scenario.finishError=false;
  assert.equal((await handler(request())).status,200);assert.deepEqual(scenario.events,['deleteUser','complete','complete']);
  console.log('PASS: isolated deletion retry, owner checks, storage failures and interrupted completion');
} finally {
  delete globalThis.Deno;delete globalThis.__papiTestCreateClient;
  await rm(dir,{recursive:true,force:true});
}
