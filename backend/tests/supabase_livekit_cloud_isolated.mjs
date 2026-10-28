// End-to-end synthetic media test against the two explicitly isolated cloud
// projects. Reads temporary test credentials from a private file; never use
// production users, URLs or keys. No credentials or tokens are printed.
import {createRequire} from 'node:module';
import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const supabaseURL='https://bezftktzpyuykuvnbilm.supabase.co';
const expectedLiveURL='wss://papi-isolated-validation-64n1xwg7.livekit.cloud';
const key=process.env.PAPI_ISOLATED_PUBLISHABLE_KEY;
const rtcRoot=process.env.PAPI_LIVEKIT_TEST_ROOT,sdkRoot=process.env.PAPI_ISOLATED_SDK_ROOT,credentialPath=process.env.PAPI_LIVEKIT_CREDENTIAL_FILE;
if(!key?.startsWith('sb_publishable_') || !rtcRoot || !sdkRoot || !credentialPath ||
   ![rtcRoot,sdkRoot,credentialPath].every(p=>resolve(p).startsWith('/tmp/'))) throw new Error('Isolated test configuration required');
const credentials=JSON.parse(await readFile(credentialPath,'utf8'));
if(credentials.LIVEKIT_URL!==expectedLiveURL || !credentials.LIVEKIT_API_KEY || !credentials.LIVEKIT_API_SECRET) throw new Error('Unexpected LiveKit project');
const rtcRequire=createRequire(resolve(rtcRoot,'package.json'));
const supabaseRequire=createRequire(resolve(sdkRoot,'package.json'));
const rtc=await import(pathToFileURL(rtcRequire.resolve('@livekit/rtc-node')).href);
const lk=await import(pathToFileURL(rtcRequire.resolve('livekit-server-sdk')).href);
const {createClient}=supabaseRequire('@supabase/supabase-js');
const {Room,RoomEvent,AudioSource,AudioFrame,AudioStream,LocalAudioTrack,VideoSource,VideoFrame,VideoStream,VideoBufferType,LocalVideoTrack,TrackPublishOptions,TrackSource,dispose}=rtc;
const server=new lk.RoomServiceClient(expectedLiveURL.replace('wss:','https:'),credentials.LIVEKIT_API_KEY,credentials.LIVEKIT_API_SECRET);
const client=()=>createClient(supabaseURL,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const a=client(),b=client();const rooms=[new Room(),new Room(),new Room(),new Room(),new Room(),new Room(),new Room()];
const call=randomUUID(),voiceA=randomUUID(),voiceB=randomUUID(),voiceNew=randomUUID();
const callRoom=`papi-call-${call}`,voiceRoom='papi-room-chat';
let audioSource,audioTrack,audioReader,videoSource,videoTrack,videoReader,videoTimer,heartbeatTimer,stage='sign-in';
const need=(result,label)=>{if(result.error) throw Object.assign(new Error(label),{stage:label,status:result.error.status,code:result.error.code});return result.data;};
const timeout=(promise,label,ms=25000)=>{let t;return Promise.race([promise,new Promise((_,reject)=>{t=setTimeout(()=>reject(Object.assign(new Error('timeout'),{stage:label})),ms)})]).finally(()=>clearTimeout(t));};
const invoke=async(c,name,body)=>{const r=need(await c.functions.invoke(name,{body}),name);if(r.server_url!==expectedLiveURL || !r.participant_token) throw Error('Unexpected token service response');return r.participant_token;};
const assertRevoked=async(room,token,label)=>{
  let rejected=false;
  try {await timeout(room.connect(expectedLiveURL,token,{autoSubscribe:true}),label,15000);} catch(error) {
    if(error.stage===label || !/unauthori[sz]ed|permission|not allowed|forbidden|revoked|401|403/i.test(error.message ?? '')) throw error;
    rejected=true;
  }
  assert.equal(rejected,true,`${label} must be rejected`);
  await room.disconnect().catch(()=>{});
};
try {
  const userA=need(await a.auth.signInAnonymously(),'first sign-in').user,userB=need(await b.auth.signInAnonymously(),'second sign-in').user;
  assert.ok(userA && userB && userA.id!==userB.id);
  await writeFile('/tmp/papi-isolated-supabase/last-endtoend-fixture.json',JSON.stringify({project:'bezftktzpyuykuvnbilm',a:userA.id,b:userB.id,call,voiceA,voiceB,voiceNew}));
  for(const [c,u] of [[a,userA],[b,userB]]) need(await c.from('coffee_profiles').insert({id:u.id,display_name:'RTC fixture',biography:''}),'profile');
  need(await a.rpc('set_coffee_follow',{p_member:userB.id,p_enabled:true}),'follow A');
  need(await b.rpc('set_coffee_follow',{p_member:userA.id,p_enabled:true}),'follow B');
  stage='voice membership and tokens';
  assert.equal(need(await a.rpc('enter_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),'voice A'),true);
  assert.equal(need(await b.rpc('enter_coffee_voice',{p_topic:'room-chat',p_session:voiceB}),'voice B'),true);
  heartbeatTimer=setInterval(()=>{void Promise.all([
    a.rpc('heartbeat_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),
    b.rpc('heartbeat_coffee_voice',{p_topic:'room-chat',p_session:voiceB}),
  ]).catch(()=>{});},10000);
  const tokenA=await invoke(a,'livekit-voice-token',{topic_id:'room-chat',session_id:voiceA});
  const tokenB=await invoke(b,'livekit-voice-token',{topic_id:'room-chat',session_id:voiceB});
  const subscribed=new Promise(r=>rooms[1].once(RoomEvent.TrackSubscribed,r));
  await timeout(rooms[0].connect(expectedLiveURL,tokenA,{autoSubscribe:true}),'voice connect A');
  await timeout(rooms[1].connect(expectedLiveURL,tokenB,{autoSubscribe:true}),'voice connect B');
  audioSource=new AudioSource(16000,1);audioTrack=LocalAudioTrack.createAudioTrack('fixture-audio',audioSource);
  const ao=new TrackPublishOptions();ao.source=TrackSource.SOURCE_MICROPHONE;
  await timeout(rooms[0].localParticipant.publishTrack(audioTrack,ao),'audio publish');
  const remote=await timeout(subscribed,'audio subscribe');audioReader=new AudioStream(remote,16000,1).getReader();
  const frame=AudioFrame.create(16000,1,160);for(let i=0;i<frame.data.length;i++)frame.data[i]=Math.round(4000*Math.sin(i*Math.PI/12));
  const receive=audioReader.read();for(let i=0;i<35;i++)await audioSource.captureFrame(frame);
  assert.equal((await timeout(receive,'audio receive')).done,false);

  stage='call consent and tokens';
  assert.equal(need(await a.rpc('request_coffee_call',{p_id:call,p_recipient:userB.id}),'call request'),call);
  assert.equal(need(await b.rpc('answer_coffee_call',{p_id:call,p_accept:true}),'call answer'),true);
  const callA=await invoke(a,'livekit-call-token',{call_id:call}),callB=await invoke(b,'livekit-call-token',{call_id:call});
  const videoSubscribed=new Promise(r=>rooms[3].once(RoomEvent.TrackSubscribed,r));
  await timeout(rooms[2].connect(expectedLiveURL,callA,{autoSubscribe:true}),'call connect A');
  await timeout(rooms[3].connect(expectedLiveURL,callB,{autoSubscribe:true}),'call connect B');
  videoSource=new VideoSource(64,64);videoTrack=LocalVideoTrack.createVideoTrack('fixture-video',videoSource);
  const vo=new TrackPublishOptions();vo.source=TrackSource.SOURCE_CAMERA;
  await timeout(rooms[2].localParticipant.publishTrack(videoTrack,vo),'video publish');
  const vf=new VideoFrame(new Uint8Array(64*64*4).fill(128),64,64,VideoBufferType.RGBA);
  videoTimer=setInterval(()=>videoSource.captureFrame(vf),40);
  const remoteVideo=await timeout(videoSubscribed,'video subscribe');videoReader=new VideoStream(remoteVideo).getReader();
  assert.equal((await timeout(videoReader.read(),'video receive')).done,false);

  stage='block and hosted cleanup';
  const removed=[0,2,3].map(i=>new Promise(r=>rooms[i].once(RoomEvent.Disconnected,r)));
  assert.equal(need(await b.rpc('set_coffee_block',{p_member:userA.id,p_enabled:true}),'block'),true);
  await timeout(Promise.all(removed),'hosted cleanup',60000);
  assert.equal(need(await a.rpc('can_join_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),'closed voice check'),false);
  assert.equal(need(await a.rpc('can_join_coffee_call',{p_id:call}),'closed call check'),false);
  stage='revoked token rejoin';
  await assertRevoked(rooms[4],tokenA,'old voice token');
  await assertRevoked(rooms[5],callA,'old call token');

  stage='new voice session';
  assert.equal(need(await b.rpc('set_coffee_block',{p_member:userA.id,p_enabled:false}),'unblock'),true);
  let joined=false;
  for(let attempt=0;attempt<10 && !joined;attempt++) {
    const response=await a.rpc('enter_coffee_voice',{p_topic:'room-chat',p_session:voiceNew});
    if(!response.error && response.data===true) {joined=true;break;}
    await new Promise(resolve=>setTimeout(resolve,1000));
  }
  assert.equal(joined,true,'new voice session should become available after cleanup');
  const fresh=await invoke(a,'livekit-voice-token',{topic_id:'room-chat',session_id:voiceNew});
  await timeout(rooms[6].connect(expectedLiveURL,fresh,{autoSubscribe:true}),'new voice connect');
  await timeout(server.removeParticipant(voiceRoom,`${userA.id}:${voiceA}`,{revokeTokenTs:BigInt(Math.floor(Date.now()/1000)+1)}),'old session cleanup retry');
  const members=await server.listParticipants(voiceRoom);
  assert.ok(members.some(p=>p.identity===`${userA.id}:${voiceNew}`),'old cleanup must not remove the new session');
  console.log('PASS: isolated LiveKit Cloud audio/video, block cleanup, token revocation and new-session isolation');
} catch(error) {
  console.error(JSON.stringify({stage:error.stage ?? stage,status:error.status ?? null,code:error.code ?? null,errorType:error.name ?? 'Error'}));
  process.exitCode=1;
} finally {
  if(videoTimer)clearInterval(videoTimer);
  if(heartbeatTimer)clearInterval(heartbeatTimer);
  if(audioReader)await audioReader.cancel().catch(()=>{});
  if(videoReader)await videoReader.cancel().catch(()=>{});
  if(audioTrack)await audioTrack.close().catch(()=>{});
  if(audioSource)await audioSource.close().catch(()=>{});
  if(videoTrack)await videoTrack.close().catch(()=>{});
  if(videoSource)await videoSource.close().catch(()=>{});
  await Promise.allSettled(rooms.map(r=>r.disconnect()));
  // These room names belong exclusively to the isolated test project.
  await server.deleteRoom(callRoom).catch(()=>{});
  await server.deleteRoom(voiceRoom).catch(()=>{});
  await dispose();
}
