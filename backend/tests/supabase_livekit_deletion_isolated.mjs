// Real cloud deletion while synthetic voice/call sessions are active, confined
// to the dedicated test projects. No real users, files or production keys.
import {createRequire} from 'node:module';
import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {randomBytes,randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const supabaseURL='https://bezftktzpyuykuvnbilm.supabase.co';
const liveURL='wss://papi-isolated-validation-64n1xwg7.livekit.cloud';
const key=process.env.PAPI_ISOLATED_PUBLISHABLE_KEY,rtcRoot=process.env.PAPI_LIVEKIT_TEST_ROOT;
const sdkRoot=process.env.PAPI_ISOLATED_SDK_ROOT,credentialPath=process.env.PAPI_LIVEKIT_CREDENTIAL_FILE;
if(!key?.startsWith('sb_publishable_') || !rtcRoot || !sdkRoot || !credentialPath ||
   ![rtcRoot,sdkRoot,credentialPath].every(p=>resolve(p).startsWith('/tmp/'))) throw new Error('Isolated test configuration required');
const credentials=JSON.parse(await readFile(credentialPath,'utf8'));
if(credentials.LIVEKIT_URL!==liveURL || !credentials.LIVEKIT_API_KEY || !credentials.LIVEKIT_API_SECRET) throw new Error('Unexpected LiveKit project');
const rtcRequire=createRequire(resolve(rtcRoot,'package.json')),sbRequire=createRequire(resolve(sdkRoot,'package.json'));
const rtc=await import(pathToFileURL(rtcRequire.resolve('@livekit/rtc-node')).href);
const lk=await import(pathToFileURL(rtcRequire.resolve('livekit-server-sdk')).href);
const {createClient}=sbRequire('@supabase/supabase-js');const {Room,RoomEvent,dispose}=rtc;
const server=new lk.RoomServiceClient(liveURL.replace('wss:','https:'),credentials.LIVEKIT_API_KEY,credentials.LIVEKIT_API_SECRET);
const make=()=>createClient(supabaseURL,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const a=make(),b=make(),rooms=[new Room(),new Room(),new Room(),new Room()];
const call=randomUUID(),voiceA=randomUUID(),voiceB=randomUUID(),receipt=randomBytes(32).toString('hex');
let heartbeat,stage='sign-in';
const need=(result,label)=>{if(result.error) throw Object.assign(new Error(label),{stage:label,status:result.error.status,code:result.error.code});return result.data;};
const timeout=(promise,label,ms=25000)=>{let t;return Promise.race([promise,new Promise((_,reject)=>{t=setTimeout(()=>reject(Object.assign(new Error('timeout'),{stage:label})),ms)})]).finally(()=>clearTimeout(t));};
const token=async(c,name,body)=>{const r=need(await c.functions.invoke(name,{body}),name);if(r.server_url!==liveURL || !r.participant_token) throw Error('Unexpected token response');return r.participant_token;};
try {
  const userA=need(await a.auth.signInAnonymously(),'first sign-in').user,userB=need(await b.auth.signInAnonymously(),'second sign-in').user;
  assert.ok(userA && userB && userA.id!==userB.id);
  const owned=`${userA.id}/deletion-fixture.jpg`,other=`${userB.id}/retained-fixture.jpg`;
  await writeFile('/tmp/papi-isolated-supabase/last-deletion-live-fixture.json',JSON.stringify({project:'bezftktzpyuykuvnbilm',a:userA.id,b:userB.id,call,voiceA,voiceB,owned,other}));
  for(const [c,u] of [[a,userA],[b,userB]]) need(await c.from('coffee_profiles').insert({id:u.id,display_name:'Deletion fixture',biography:''}),'profile');
  need(await a.rpc('set_coffee_follow',{p_member:userB.id,p_enabled:true}),'follow A');
  need(await b.rpc('set_coffee_follow',{p_member:userA.id,p_enabled:true}),'follow B');
  const blob=Uint8Array.from([0xff,0xd8,0xff,0xd9]);
  need(await a.storage.from('coffee-media').upload(owned,blob,{contentType:'image/jpeg'}),'owned file');
  need(await b.storage.from('coffee-media').upload(other,blob,{contentType:'image/jpeg'}),'other file');
  stage='voice and call';
  assert.equal(need(await a.rpc('enter_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),'voice A'),true);
  assert.equal(need(await b.rpc('enter_coffee_voice',{p_topic:'room-chat',p_session:voiceB}),'voice B'),true);
  heartbeat=setInterval(()=>{void Promise.all([a.rpc('heartbeat_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),b.rpc('heartbeat_coffee_voice',{p_topic:'room-chat',p_session:voiceB})]).catch(()=>{});},10000);
  await timeout(rooms[0].connect(liveURL,await token(a,'livekit-voice-token',{topic_id:'room-chat',session_id:voiceA})),'voice connect A');
  await timeout(rooms[1].connect(liveURL,await token(b,'livekit-voice-token',{topic_id:'room-chat',session_id:voiceB})),'voice connect B');
  assert.equal(need(await a.rpc('request_coffee_call',{p_id:call,p_recipient:userB.id}),'call request'),call);
  assert.equal(need(await b.rpc('answer_coffee_call',{p_id:call,p_accept:true}),'call accept'),true);
  await timeout(rooms[2].connect(liveURL,await token(a,'livekit-call-token',{call_id:call})),'call connect A');
  await timeout(rooms[3].connect(liveURL,await token(b,'livekit-call-token',{call_id:call})),'call connect B');
  stage='start deletion';
  const disconnected=[0,2,3].map(i=>new Promise(r=>rooms[i].once(RoomEvent.Disconnected,r)));
  assert.equal(need(await a.rpc('begin_coffee_deletion',{p_secret:receipt}),'begin deletion'),true);
  stage='cleanup and deletion';
  let completed=false;
  for(let i=0;i<30 && !completed;i++) {
    const res=await fetch(`${supabaseURL}/functions/v1/delete-coffee-account`,{method:'POST',headers:{apikey:key,'content-type':'application/json'},body:JSON.stringify({receipt})});
    if(res.status===200) {assert.equal((await res.json()).status,'complete');completed=true;break;}
    if(res.status!==202 && res.status!==503) throw Object.assign(new Error('unexpected deletion status'),{status:res.status});
    await new Promise(r=>setTimeout(r,2000));
  }
  assert.equal(completed,true,'live cleanup and deletion must complete');
  await timeout(Promise.all(disconnected),'participant cleanup',30000);
  need(await b.storage.from('coffee-media').download(other),'other user file retained');
  const retry=await fetch(`${supabaseURL}/functions/v1/delete-coffee-account`,{method:'POST',headers:{apikey:key,'content-type':'application/json'},body:JSON.stringify({receipt})});
  assert.equal(retry.status,200);assert.equal((await retry.json()).status,'complete');
  console.log('PASS: isolated cloud deletion closes live sessions, preserves other files and supports retry');
} catch(error) {
  console.error(JSON.stringify({stage:error.stage ?? stage,status:error.status ?? null,code:error.code ?? null,errorType:error.name ?? 'Error'}));
  process.exitCode=1;
} finally {
  if(heartbeat)clearInterval(heartbeat);
  await Promise.allSettled(rooms.map(r=>r.disconnect()));
  await server.deleteRoom(`papi-call-${call}`).catch(()=>{});
  await server.deleteRoom('papi-room-chat').catch(()=>{});
  await dispose();
}
