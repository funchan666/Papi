// Scheduler SQL with a local fake pg_net. No real HTTP calls or credentials.
// Run after live_isolated.mjs against a new local papi_test_* database.
import {createRequire} from 'node:module';
import {readFile,realpath} from 'node:fs/promises';
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
try {
  await admin.query(`create schema net; create table net.requests(id bigint generated always as identity,headers jsonb);
    create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) returns bigint language sql as $$
      insert into net.requests(headers) values(headers) returning id
    $$;`);
  await admin.query(await readFile(resolve('backend/papi_livekit_cleanup_scheduler_draft.sql'),'utf8'));
  await admin.query(await readFile(resolve('backend/papi_livekit_cleanup_fairness_draft.sql'),'utf8'));
  await admin.query(`update papi_private.voice_runtime_config set enabled=false; update papi_private.call_runtime_config set enabled=false;
    delete from papi_private.voice_revocations; delete from papi_private.call_revocations;`);
  await admin.query('select papi_private.wake_coffee_cleanup()');
  assert.equal((await one(admin,'select count(*)::int as n from net.requests')).n,0);
  await admin.query("insert into papi_private.voice_revocations(session_id,owner_id,topic_id) values('90000000-0000-4000-8000-000000000071','00000000-0000-4000-8000-000000000071','room-chat')");
  await admin.query('select papi_private.wake_coffee_cleanup()');
  const ticket=(await one(admin,"select headers->>'x-papi-cleanup-ticket' as ticket from net.requests")).ticket;
  assert.match(ticket,/^[0-9a-f]{64}$/);
  const a=await connect(),b=await connect();
  try {
    for(const c of [a,b]) {await c.query('begin');await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({role:'service_role'})]);}
    assert.equal((await one(a,'select public.consume_coffee_cleanup_ticket($1) as ok',[ticket])).ok,true);
    let waiting=true;
    const second=one(b,'select public.consume_coffee_cleanup_ticket($1) as ok',[ticket]).then(v=>{waiting=false;return v;});
    await new Promise(r=>setTimeout(r,150));assert.equal(waiting,true);
    await a.query('commit');assert.equal((await second).ok,false);await b.query('commit');
    await a.query('begin');await a.query('set local role authenticated');
    await assert.rejects(a.query('select public.consume_coffee_cleanup_ticket($1)',[ticket]),/permission denied/);await a.query('rollback');
    await admin.query("insert into papi_private.cleanup_tickets(ticket_hash,expires_at) values(extensions.digest($1,'sha256'),clock_timestamp()-interval '1 second')",['f'.repeat(64)]);
    await b.query('begin');await b.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({role:'service_role'})]);
    assert.equal((await one(b,'select public.consume_coffee_cleanup_ticket($1) as ok',['f'.repeat(64)])).ok,false);await b.query('commit');

    // With 25 pending calls, concurrent readers divide the locked rows and do
    // not starve the five rows behind the first batch.
    await admin.query(`insert into papi_private.call_revocations(call_id,caller_id,recipient_id)
      select gen_random_uuid(),'00000000-0000-4000-8000-000000000071','00000000-0000-4000-8000-000000000072' from generate_series(1,25)`);
    for(const c of [a,b]) {await c.query('begin');await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({role:'service_role'})]);}
    const first=(await a.query('select * from public.pending_call_revocations()')).rows;
    const next=(await b.query('select * from public.pending_call_revocations()')).rows;
    assert.equal(first.length,20);assert.equal(next.length,5);
    assert.equal(new Set([...first,...next].map(row=>row.call_id)).size,25);
    await a.query('commit');await b.query('commit');

    // A voice queue larger than a batch rotates unattempted rows first.
    await admin.query(`delete from papi_private.voice_revocations;
      insert into papi_private.voice_revocations(session_id,owner_id,topic_id)
      select gen_random_uuid(),'00000000-0000-4000-8000-000000000071','room-chat' from generate_series(1,25)`);
    await a.query('begin');await a.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({role:'service_role'})]);
    const firstVoice=(await a.query('select * from public.pending_voice_revocations()')).rows;await a.query('commit');
    await b.query('begin');await b.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({role:'service_role'})]);
    const nextVoice=(await b.query('select * from public.pending_voice_revocations()')).rows;await b.query('commit');
    assert.equal(firstVoice.length,20);assert.equal(nextVoice.length,20);
    assert.equal(new Set([...firstVoice,...nextVoice].map(row=>row.session_id)).size,25);
    console.log('PASS: isolated scheduler, ticket single use, concurrent call batches and voice queue fairness');
  } finally {await a.end();await b.end();}
} finally {await admin.end();}
