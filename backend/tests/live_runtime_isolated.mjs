// Tests capacity, expiry and disable switches on a disposable PostgreSQL DB.
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {realpath} from 'node:fs/promises';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const root=process.env.PAPI_NATIVE_PG_ROOT,database=process.env.PAPI_NATIVE_TEST_DB;
if (!root || !resolve(root).startsWith('/tmp/') || !/^papi_test_[a-z0-9]+$/.test(database || '')) throw new Error('Disposable database required');
const {Client}=createRequire(resolve(root,'package.json'))('pg');
const db=new Client({host:root,port:55472,user:'papi_test',database});await db.connect();
const check=(await db.query("select current_setting('data_directory') as dir,inet_server_addr() as addr,to_regclass('public.coffee_profiles') as fixture")).rows[0];
if(check.addr!==null || !check.fixture || await realpath(check.dir)!==await realpath(resolve(root,'data'))) {await db.end();throw new Error('Not an isolated fixture');}
const one=async(q,p=[]) => (await db.query(q,p)).rows[0];
const actor=async(id,role='authenticated')=>db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,role,session_id:id})]);
try {
  const people=Array.from({length:21},()=>({id:randomUUID(),session:randomUUID()}));
  for(const p of people) {
    await db.query('insert into auth.users(id) values($1)',[p.id]);
    await db.query('insert into auth.sessions(id,user_id) values($1,$1)',[p.id]);
    await db.query("insert into public.coffee_profiles(id,display_name) values($1,'Fixture')",[p.id]);
  }
  for(const p of people.slice(0,20)) {
    await actor(p.id);assert.equal((await one("select public.enter_coffee_voice('room-breeze',$1) as ok",[p.session])).ok,true);
  }
  const extra=people[20];await actor(extra.id);
  await assert.rejects(db.query("select public.enter_coffee_voice('room-breeze',$1)",[extra.session]),/Voice room is full/);
  await db.query("update papi_private.voice_members set heartbeat_at=now()-interval '60 seconds' where owner_id=$1",[people[0].id]);
  await actor(people[0].id,'service_role');await db.query('select * from public.pending_voice_revocations()');
  assert.equal((await one('select status from papi_private.voice_members where owner_id=$1',[people[0].id])).status,'closing');
  await actor(extra.id);await assert.rejects(db.query("select public.enter_coffee_voice('room-breeze',$1)",[extra.session]),/Voice room is full/);
  await actor(people[0].id,'service_role');assert.equal((await one('select public.complete_voice_revocation($1) as ok',[people[0].session])).ok,true);
  await actor(extra.id);assert.equal((await one("select public.enter_coffee_voice('room-breeze',$1) as ok",[extra.session])).ok,true);

  await actor(extra.id,'service_role');assert.equal((await one('select public.set_voice_runtime(false) as ok')).ok,true);
  assert.equal((await one("select count(*)::int as n from papi_private.voice_members where topic_id='room-breeze' and status='active'")).n,0);
  await actor(extra.id);assert.equal((await one("select public.heartbeat_coffee_voice('room-breeze',$1) as ok",[extra.session])).ok,false);
  await assert.rejects(db.query("select public.enter_coffee_voice('room-breeze',$1)",[randomUUID()]),/Voice room unavailable/);

  const [caller,callee]=people;const call=randomUUID();
  await db.query('insert into public.coffee_follows(follower_id,followed_id) values($1,$2),($2,$1)',[caller.id,callee.id]);
  await actor(caller.id);assert.equal((await one('select public.request_coffee_call($1,$2) as id',[call,callee.id])).id,call);
  await actor(callee.id);assert.equal((await one('select public.answer_coffee_call($1,true) as ok',[call])).ok,true);
  await actor(callee.id,'service_role');assert.equal((await one('select public.set_call_runtime(false) as ok')).ok,true);
  assert.equal((await one('select status from public.coffee_calls where id=$1',[call])).status,'ended');
  assert.equal((await one('select count(*)::int as n from papi_private.call_revocations where call_id=$1 and completed_at is null',[call])).n,1);
  await actor(caller.id);assert.equal((await one('select public.can_join_coffee_call($1) as ok',[call])).ok,false);
  console.log('PASS: voice capacity, heartbeat expiry, cleanup and voice/call runtime disable');
} finally {await db.end();}
