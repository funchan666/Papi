// Runs the deployed cleanup handler with local fakes; never reaches Supabase
// or LiveKit Cloud. Node 22+: node --experimental-strip-types this-file.
import assert from 'node:assert/strict';
import { mkdtemp,readFile,rm,writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const dir=await mkdtemp(join(tmpdir(),'papi-cleanup-handler-'));
let source=await readFile(resolve('backend/functions/livekit-call-cleanup/index.ts'),'utf8');
for (const [before,after] of [
  ['import { createClient } from "npm:@supabase/supabase-js@2.118.0";','const createClient = globalThis.__papiCleanupClient;'],
  ['import { RoomServiceClient } from "npm:livekit-server-sdk@2.19.2";','const RoomServiceClient = globalThis.__papiCleanupRooms;'],
]) {if(!source.includes(before)) throw new Error('Unexpected handler import');source=source.replace(before,after);}
await writeFile(join(dir,'handler.ts'),source);
const a='00000000-0000-4000-8000-000000000041',b='00000000-0000-4000-8000-000000000042';
const call='60000000-0000-4000-8000-000000000041',session='90000000-0000-4000-8000-000000000041';
let handler,state;
globalThis.Deno={env:{get:key=>({SUPABASE_URL:'https://isolated.invalid',SUPABASE_SERVICE_ROLE_KEY:'test',LIVEKIT_URL:'wss://isolated.invalid',LIVEKIT_API_KEY:'test',LIVEKIT_API_SECRET:'test'})[key]},serve:fn=>{handler=fn;}};
globalThis.__papiCleanupClient=(url,key)=>{
  assert.equal(url,'https://isolated.invalid');assert.equal(key,'test');
  return {rpc:async(name,args)=>{
    state.calls.push(name);
    if(name==='consume_coffee_cleanup_ticket') return {data:state.authorized,error:null};
    if(name==='pending_call_revocations') return {data:state.callJobs,error:null};
    if(name==='pending_voice_revocations') return {data:state.voiceJobs,error:null};
    if(name==='complete_call_revocation' || name==='complete_voice_revocation') {state.completed.push({name,args});return {data:true,error:null};}
    throw new Error(`Unexpected RPC ${name}`);
  }};
};
globalThis.__papiCleanupRooms=class {
  constructor(host,key,secret){assert.equal(host,'https://isolated.invalid/');assert.equal(key,'test');assert.equal(secret,'test');}
  async removeParticipant(room,identity,options){
    assert.equal(typeof options.revokeTokenTs,'bigint');
    assert.ok(options.revokeTokenTs>=BigInt(Math.floor(Date.now()/1000)));
    state.removals.push({room,identity});
    if(identity===state.failIdentity) throw new Error('temporary failure');
  }
};
const request=(ticket='a'.repeat(64))=>new Request('https://isolated.invalid/cleanup',{method:'POST',headers:{'x-papi-cleanup-ticket':ticket}});
const initial=()=>({authorized:true,calls:[],completed:[],removals:[],callJobs:[{call_id:call,caller_id:a,recipient_id:b}],voiceJobs:[{topic_id:'room-chat',session_id:session,owner_id:a}]});
try {
  await import(pathToFileURL(join(dir,'handler.ts')).href);
  state=initial();let response=await handler(request());
  assert.equal(response.status,200);assert.deepEqual(await response.json(),{completed:1,voice_completed:1,failed:0,more:false});
  assert.deepEqual(state.removals,[{room:`papi-call-${call}`,identity:a},{room:`papi-call-${call}`,identity:b},{room:'papi-room-chat',identity:`${a}:${session}`}]);
  assert.equal(state.completed.length,2);
  state=initial();state.failIdentity=b;response=await handler(request());
  assert.equal(response.status,503);assert.equal(state.completed.length,1);assert.equal(state.completed[0].name,'complete_voice_revocation');
  state=initial();state.failIdentity=a;response=await handler(request());
  assert.equal(response.status,503);assert.ok(state.removals.some(x=>x.identity===b));
  assert.equal(state.completed.some(x=>x.name==='complete_call_revocation'),false);
  state=initial();state.authorized=false;response=await handler(request());
  assert.equal(response.status,401);assert.deepEqual(state.calls,['consume_coffee_cleanup_ticket']);assert.equal(state.removals.length,0);
  state=initial();state.callJobs[0].call_id='invalid';response=await handler(request());
  assert.equal(response.status,503);assert.equal(state.removals.length,1);assert.equal(state.completed.length,1);
  state=initial();response=await handler(request('invalid'));
  assert.equal(response.status,401);assert.equal(state.calls.length,0);
  console.log('PASS: isolated cleanup ticket, removal, cutoff, partial failure and invalid job behavior');
} finally {
  delete globalThis.Deno;delete globalThis.__papiCleanupClient;delete globalThis.__papiCleanupRooms;
  await rm(dir,{recursive:true,force:true});
}
