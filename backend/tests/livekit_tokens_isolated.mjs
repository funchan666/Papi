// Real token handlers and LiveKit SDK with fake Auth/RPC clients and fake keys.
// No network calls: PAPI_LIVEKIT_ROOT=/tmp/... node --experimental-strip-types this-file
import assert from 'node:assert/strict';
import { mkdtemp,readFile,rm,writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { join,resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root=process.env.PAPI_LIVEKIT_ROOT;
if (!root || !resolve(root).startsWith('/tmp/')) throw new Error('Temporary SDK prefix required');
const require=createRequire(resolve(root,'package.json'));
const {AccessToken}=require('livekit-server-sdk');
const {TrackSource}=require('@livekit/protocol');
const dir=await mkdtemp(join(tmpdir(),'papi-token-handlers-'));
const ids={user:'00000000-0000-4000-8000-000000000061',call:'60000000-0000-4000-8000-000000000061',session:'90000000-0000-4000-8000-000000000061'};
let handler,state;
globalThis.Deno={env:{get:key=>({SUPABASE_URL:'https://isolated.invalid',SUPABASE_ANON_KEY:'fake',LIVEKIT_URL:'wss://isolated.invalid',LIVEKIT_API_KEY:'fake-key',LIVEKIT_API_SECRET:'fake-secret-long-enough-for-test'})[key]},serve:fn=>{handler=fn;}};
globalThis.__papiAccessToken=AccessToken;globalThis.__papiTrackSource=TrackSource;
globalThis.__papiTokenClient=(url,key)=>{
  assert.equal(url,'https://isolated.invalid');assert.equal(key,'fake');
  return {auth:{getUser:async()=>{
    if(state.authThrows) throw new Error('network unavailable');
    return {data:{user:state.user ? {id:ids.user} : null},error:state.authError ?? null};
  }},rpc:async(name,args)=>{
    state.calls.push(name);
    if(name.startsWith('can_join_')) return {data:state.allowed.shift(),error:null};
    if(name.startsWith('reserve_')) return {data:state.reserved,error:null};
    throw new Error(`Unexpected RPC ${name}`);
  }};
};
const replace=[
  ['import { createClient } from "npm:@supabase/supabase-js@2.118.0";','const createClient = globalThis.__papiTokenClient;'],
  ['import { AccessToken } from "npm:livekit-server-sdk@2.19.2";','const AccessToken = globalThis.__papiAccessToken;'],
  ['import { TrackSource } from "npm:@livekit/protocol@1.51.0";','const TrackSource = globalThis.__papiTrackSource;'],
];
const request=body=>new Request('https://isolated.invalid/token',{method:'POST',headers:{authorization:'Bearer fake'},body:JSON.stringify(body)});
try {
  for (const kind of ['call','voice']) {
    let source=await readFile(resolve(`backend/functions/livekit-${kind}-token/index.ts`),'utf8');
    for(const [before,after] of replace) {if(!source.includes(before)) throw new Error('Unexpected import');source=source.replace(before,after);}
    const path=join(dir,`${kind}.ts`);await writeFile(path,source);await import(pathToFileURL(path).href);
    const body=kind==='call' ? {call_id:ids.call} : {topic_id:'room-chat',session_id:ids.session};
    state={user:true,allowed:[true,true],reserved:true,calls:[]};
    let response=await handler(request(body));assert.equal(response.status,200);
    const result=await response.json();const payload=JSON.parse(Buffer.from(result.participant_token.split('.')[1],'base64url').toString());
    assert.equal(result.server_url,'wss://isolated.invalid');assert.equal(payload.exp-payload.nbf,120);
    assert.equal(payload.sub,kind==='call' ? ids.user : `${ids.user}:${ids.session}`);
    assert.equal(payload.video.room,kind==='call' ? `papi-call-${ids.call}` : 'papi-room-chat');
    assert.equal(payload.video.roomJoin,true);assert.equal(payload.video.canPublishData,false);
    assert.deepEqual(payload.video.canPublishSources,kind==='call' ? ['microphone','camera'] : ['microphone']);
    assert.equal(state.calls.length,3);
    state={user:true,allowed:[false],reserved:true,calls:[]};response=await handler(request(body));assert.equal(response.status,403);assert.equal(state.calls.length,1);
    state={user:true,allowed:[true],reserved:false,calls:[]};response=await handler(request(body));assert.equal(response.status,429);assert.equal(state.calls.length,2);
    state={user:true,allowed:[true,false],reserved:true,calls:[]};response=await handler(request(body));assert.equal(response.status,403);
    assert.equal(Object.hasOwn(await response.json(),'participant_token'),false);
    state={user:false,allowed:[],reserved:true,calls:[]};response=await handler(request(body));assert.equal(response.status,401);assert.equal(state.calls.length,0);
    state={user:false,allowed:[],reserved:true,calls:[],authThrows:true};response=await handler(request(body));assert.equal(response.status,503);assert.equal(state.calls.length,0);
    state={user:false,allowed:[],reserved:true,calls:[],authError:{status:503}};response=await handler(request(body));assert.equal(response.status,503);
    state={user:false,allowed:[],reserved:true,calls:[],authError:{status:401}};response=await handler(request(body));assert.equal(response.status,401);
    state={user:true,allowed:[],reserved:true,calls:[]};response=await handler(request({}));assert.equal(response.status,400);
  }
  console.log('PASS: isolated token scope, authorization recheck, rate limits and Auth failure handling');
} finally {
  delete globalThis.Deno;delete globalThis.__papiTokenClient;delete globalThis.__papiAccessToken;delete globalThis.__papiTrackSource;
  await rm(dir,{recursive:true,force:true});
}
