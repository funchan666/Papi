// Concurrent LiveKit membership and call SQL against disposable local data.
// Run after live_isolated.mjs with PAPI_NATIVE_PG_ROOT and PAPI_NATIVE_TEST_DB.
import {createRequire} from 'node:module';
import {realpath} from 'node:fs/promises';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';

const root=process.env.PAPI_NATIVE_PG_ROOT,database=process.env.PAPI_NATIVE_TEST_DB;
if (!root || !resolve(root).startsWith('/tmp/') || !/^papi_test_[a-z0-9]+$/.test(database || '')) throw new Error('Disposable database required');
const {Client}=createRequire(resolve(root,'package.json'))('pg');
const connect=async()=>{const c=new Client({host:root,port:55472,user:'papi_test',database});await c.connect();return c;};
const admin=await connect();
const check=(await admin.query("select current_setting('data_directory') as dir,inet_server_addr() as addr,to_regclass('public.coffee_profiles') as fixture")).rows[0];
if(check.addr!==null || !check.fixture || await realpath(check.dir)!==await realpath(resolve(root,'data'))) {await admin.end();throw new Error('Not an isolated fixture');}
const one=async(c,q,p=[]) => (await c.query(q,p)).rows[0];
const start=async(c,id,role='authenticated')=>{await c.query('begin');await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:id,role,session_id:id})]);};
const pause=()=>new Promise(r=>setTimeout(r,150));
const a='00000000-0000-4000-8000-000000000081',b='00000000-0000-4000-8000-000000000082';
const c='00000000-0000-4000-8000-000000000083',d='00000000-0000-4000-8000-000000000084';
const e='00000000-0000-4000-8000-000000000085',f='00000000-0000-4000-8000-000000000086';
const voice1='90000000-0000-4000-8000-000000000081',voice2='90000000-0000-4000-8000-000000000082';
const voice3='90000000-0000-4000-8000-000000000083',voice4='90000000-0000-4000-8000-000000000084';
const voice5='90000000-0000-4000-8000-000000000085';
const call='60000000-0000-4000-8000-000000000081';
try {
  for(const id of [a,b,c,d,e,f]) {
    await admin.query('insert into auth.users(id) values($1)',[id]);
    await admin.query('insert into auth.sessions(id,user_id) values($1,$1)',[id]);
    await admin.query("insert into public.coffee_profiles(id,display_name) values($1,'Fixture')",[id]);
  }
  await admin.query('insert into public.coffee_follows(follower_id,followed_id) values($1,$2),($2,$1)',[e,f]);
  const left=await connect(),right=await connect();
  try {
    // B enters while A blocks: block waits, then marks B closing.
    await start(left,a);assert.equal((await one(left,"select public.enter_coffee_voice('room-chat',$1) as ok",[voice1])).ok,true);await left.query('commit');
    await start(right,b);assert.equal((await one(right,"select public.enter_coffee_voice('room-chat',$1) as ok",[voice2])).ok,true);
    await start(left,a);let waiting=true;
    const block=one(left,'select public.set_coffee_block($1,true) as ok',[b]).then(v=>{waiting=false;return v;});
    await pause();assert.equal(waiting,true);await right.query('commit');assert.equal((await block).ok,true);await left.query('commit');
    assert.equal((await one(admin,'select status from papi_private.voice_members where owner_id=$1',[b])).status,'closing');
    assert.equal((await one(admin,'select count(*)::int as n from papi_private.voice_revocations where session_id=$1 and completed_at is null',[voice2])).n,1);

    // Block first, then a competing join cannot enter the room.
    await start(left,c);assert.equal((await one(left,"select public.enter_coffee_voice('room-chat',$1) as ok",[voice3])).ok,true);await left.query('commit');
    await start(left,c);assert.equal((await one(left,'select public.set_coffee_block($1,true) as ok',[d])).ok,true);
    await start(right,d);waiting=true;
    const join=right.query("select public.enter_coffee_voice('room-chat',$1)",[voice4]).then(()=>{waiting=false;return null;},err=>{waiting=false;return err;});
    await pause();assert.equal(waiting,true);await left.query('commit');assert.match((await join).message,/Voice room unavailable/);await right.query('rollback');

    // A retried cleanup for the previous session cannot delete the new one.
    await start(left,a);assert.equal((await one(left,"select public.leave_coffee_voice('room-chat',$1) as ok",[voice1])).ok,true);await left.query('commit');
    await start(left,a,'service_role');
    assert.equal((await one(left,'select public.complete_voice_revocation($1) as ok',[voice1])).ok,true);
    assert.equal((await one(left,'select public.complete_voice_revocation($1) as ok',[voice2])).ok,true);await left.query('commit');
    await start(left,a);assert.equal((await one(left,"select public.enter_coffee_voice('room-chat',$1) as ok",[voice5])).ok,true);await left.query('commit');
    await start(left,a,'service_role');assert.equal((await one(left,'select public.complete_voice_revocation($1) as ok',[voice1])).ok,true);await left.query('commit');
    assert.equal((await one(admin,'select session_id from papi_private.voice_members where owner_id=$1',[a])).session_id,voice5);

    // Unfollow racing an accepted call ends it and queues revocation.
    await start(left,e);assert.equal((await one(left,'select public.request_coffee_call($1,$2) as id',[call,f])).id,call);await left.query('commit');
    await start(right,f);assert.equal((await one(right,'select public.answer_coffee_call($1,true) as ok',[call])).ok,true);
    await start(left,e);waiting=true;
    const unfollow=one(left,'select public.set_coffee_follow($1,false) as ok',[f]).then(v=>{waiting=false;return v;});
    await pause();assert.equal(waiting,true);await right.query('commit');assert.equal((await unfollow).ok,true);await left.query('commit');
    assert.equal((await one(admin,'select status from public.coffee_calls where id=$1',[call])).status,'ended');
    assert.equal((await one(admin,'select count(*)::int as n from papi_private.call_revocations where call_id=$1 and completed_at is null',[call])).n,1);
    console.log('PASS: voice join/block races, stale cleanup and accepted call/unfollow race');
  } finally {await left.end();await right.end();}
} finally {await admin.end();}
