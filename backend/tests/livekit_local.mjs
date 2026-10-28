// Explicitly local-only media exercise. Requires livekit-server --dev bound
// to loopback and temporary @livekit/rtc-node and livekit-server-sdk packages.
// This does not test LiveKit Cloud's token revocation semantics.
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const root=process.env.PAPI_LIVEKIT_TEST_ROOT;
if (!root || !resolve(root).startsWith('/tmp/')) throw new Error('Temporary LiveKit package prefix required');
const require=createRequire(resolve(root,'package.json'));
const rtc=await import(pathToFileURL(require.resolve('@livekit/rtc-node')).href);
const sdk=await import(pathToFileURL(require.resolve('livekit-server-sdk')).href);
const protocol=await import(pathToFileURL(require.resolve('@livekit/protocol')).href);
const {Room,RoomEvent,AudioSource,AudioFrame,AudioStream,LocalAudioTrack,VideoSource,VideoFrame,VideoStream,VideoBufferType,LocalVideoTrack,TrackPublishOptions,TrackSource,dispose}=rtc;
const url='ws://127.0.0.1:7880', roomName=`papi-local-${randomUUID()}`,callName=`papi-local-call-${randomUUID()}`;
const ownerA=randomUUID(),ownerB=randomUUID();
const identityA=`${ownerA}:${randomUUID()}`,identityB=`${ownerB}:${randomUUID()}`;
const server=new sdk.RoomServiceClient('http://127.0.0.1:7880','devkey','secret');
const rooms=[new Room(),new Room(),new Room(),new Room()];let track,source,reader,videoTrack,videoSource,videoReader,videoTimer;
const withTimeout=(promise,label)=>{
  let timer;
  return Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error(`${label} timed out`)),15000);})])
    .finally(()=>clearTimeout(timer));
};
const token=async (identity,room=roomName,sources=[protocol.TrackSource.MICROPHONE])=>{
  const t=new sdk.AccessToken('devkey','secret',{identity,ttl:120});
  t.addGrant({roomJoin:true,room,canSubscribe:true,canPublishSources:sources,canPublishData:false,canUpdateOwnMetadata:false});
  return t.toJwt();
};
try {
  const subscribed=new Promise(resolve=>rooms[1].once(RoomEvent.TrackSubscribed,resolve));
  await withTimeout(rooms[0].connect(url,await token(identityA),{autoSubscribe:true}),'first join');
  await withTimeout(rooms[1].connect(url,await token(identityB),{autoSubscribe:true}),'second join');
  const participants=await server.listParticipants(roomName);
  assert.deepEqual(new Set(participants.map(p=>p.identity)),new Set([identityA,identityB]));
  const permission=participants.find(p=>p.identity===identityA)?.permission;
  assert.deepEqual(permission?.canPublishSources,[protocol.TrackSource.MICROPHONE]);

  source=new AudioSource(16000,1);
  track=LocalAudioTrack.createAudioTrack('local-test-audio',source);
  const options=new TrackPublishOptions();options.source=TrackSource.SOURCE_MICROPHONE;
  await withTimeout(rooms[0].localParticipant.publishTrack(track,options),'publish');
  const remote=await withTimeout(subscribed,'subscribe');
  reader=new AudioStream(remote,16000,1).getReader();
  const frame=AudioFrame.create(16000,1,160);
  for (let i=0;i<frame.data.length;i++) frame.data[i]=Math.round(4000*Math.sin(i*Math.PI/12));
  const received=reader.read();
  for (let i=0;i<35;i++) await source.captureFrame(frame);
  const first=await withTimeout(received,'audio frame');
  assert.equal(first.done,false);assert.ok(first.value.data.length>0);

  const disconnected=new Promise(resolve=>rooms[1].once(RoomEvent.Disconnected,resolve));
  await withTimeout(server.removeParticipant(roomName,identityB),'participant removal');
  await withTimeout(disconnected,'disconnection');
  assert.deepEqual((await server.listParticipants(roomName)).map(p=>p.identity),[identityA]);

  const callSubscribed=new Promise(resolve=>rooms[3].once(RoomEvent.TrackSubscribed,resolve));
  const callSources=[protocol.TrackSource.MICROPHONE,protocol.TrackSource.CAMERA];
  await withTimeout(rooms[2].connect(url,await token(ownerA,callName,callSources),{autoSubscribe:true}),'call caller join');
  await withTimeout(rooms[3].connect(url,await token(ownerB,callName,callSources),{autoSubscribe:true}),'call recipient join');
  videoSource=new VideoSource(64,64);
  videoTrack=LocalVideoTrack.createVideoTrack('local-test-video',videoSource);
  const videoOptions=new TrackPublishOptions();videoOptions.source=TrackSource.SOURCE_CAMERA;
  await withTimeout(rooms[2].localParticipant.publishTrack(videoTrack,videoOptions),'video publish');
  const videoFrame=new VideoFrame(new Uint8Array(64*64*4).fill(128),64,64,VideoBufferType.RGBA);
  videoTimer=setInterval(()=>videoSource.captureFrame(videoFrame),40);
  const remoteVideo=await withTimeout(callSubscribed,'video subscribe');
  videoReader=new VideoStream(remoteVideo).getReader();
  const videoReceived=videoReader.read();
  const video=await withTimeout(videoReceived,'video frame');
  assert.equal(video.done,false);assert.equal(video.value.frame.width,64);assert.equal(video.value.frame.height,64);
  const callDisconnected=new Promise(resolve=>rooms[3].once(RoomEvent.Disconnected,resolve));
  await withTimeout(server.removeParticipant(callName,ownerB),'call participant removal');
  await withTimeout(callDisconnected,'call disconnection');
  console.log('PASS: local LiveKit voice/audio and call/video delivery, permissions and participant removal');
} finally {
  if (videoTimer) clearInterval(videoTimer);
  if (reader) await reader.cancel().catch(()=>{});
  if (videoReader) await videoReader.cancel().catch(()=>{});
  if (track) await track.close().catch(()=>{});
  if (source) await source.close().catch(()=>{});
  if (videoTrack) await videoTrack.close().catch(()=>{});
  if (videoSource) await videoSource.close().catch(()=>{});
  await Promise.allSettled(rooms.map(r=>r.disconnect()));
  await server.deleteRoom(roomName).catch(()=>{});
  await server.deleteRoom(callName).catch(()=>{});
  await dispose();
}
