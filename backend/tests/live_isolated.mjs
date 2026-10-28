// Local, in-memory SQL checks only. No production endpoint or credentials.
// Install @electric-sql/pglite@0.5.12 into a temporary prefix and set
// PAPI_PGLITE_ROOT to that prefix before running this file with Node.
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { readFile, realpath } from 'node:fs/promises';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const root=process.env.PAPI_PGLITE_ROOT;
const nativeRoot=process.env.PAPI_NATIVE_PG_ROOT;
let db,Client;
if (nativeRoot) {
  if (!root || !resolve(root).startsWith('/tmp/') || resolve(root)!==resolve(nativeRoot)) throw new Error('Native test server must be in the isolated temporary prefix');
  const database=process.env.PAPI_NATIVE_TEST_DB || 'postgres';
  if (database!=='postgres' && !/^papi_test_[a-z0-9]+$/.test(database)) throw new Error('Invalid isolated database name');
  const require=createRequire(resolve(nativeRoot,'package.json'));
  ({Client}=require('pg'));
  const client=new Client({host:root,port:55472,user:'papi_test',database});
  await client.connect();
  const identity=await client.query("select current_setting('data_directory') as dir,inet_server_addr() as addr,to_regclass('public.coffee_profiles') as existing");
  if (identity.rows[0].addr!==null || identity.rows[0].existing!==null ||
      await realpath(identity.rows[0].dir)!==await realpath(resolve(root,'data'))) {
    await client.end();throw new Error('Refusing to modify a nonempty or non-isolated database');
  }
  db={exec:q=>client.query(q),query:q=>client.query(q),close:()=>client.end()};
} else {
  if (!root) throw new Error('Set PAPI_PGLITE_ROOT to an isolated package prefix');
  const require=createRequire(resolve(root,'package.json'));
  const {PGlite}=await import(pathToFileURL(require.resolve('@electric-sql/pglite')).href);
  const {pgcrypto}=await import(pathToFileURL(require.resolve('@electric-sql/pglite/contrib/pgcrypto')).href);
  db=await PGlite.create({extensions:{pgcrypto}});
}
const sql=async text=>db.exec(text);
const scalar=async text=>(await db.query(text)).rows[0];
const apply=async file=>sql(await readFile(resolve('backend',file),'utf8'));
const actor=async (id,role='authenticated')=>sql(`select set_config('request.jwt.claims','${JSON.stringify({sub:id,role,session_id:id})}',false)`);
const service=()=>actor('00000000-0000-4000-8000-000000000099','service_role');
const mustFail=async (query,match)=>{
  try {await sql(query);} catch (e) {assert.match(e.message,match);return;}
  throw new Error(`Expected SQL failure: ${query}`);
};

try {
  await sql(`
    do $$ begin
      if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
      if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
      if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
    end $$;
    create schema auth; create schema storage; create schema extensions;
    create extension pgcrypto with schema extensions;
    create table auth.users(id uuid primary key);
    create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id) on delete cascade,not_after timestamptz);
    create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
    create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub','')::uuid $$;
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text not null,name text not null,owner_id text);
    alter table storage.objects enable row level security;
    grant usage on schema auth,storage to authenticated,service_role;
    grant select on storage.objects to authenticated;
  `);
  for (const file of [
    'papi_foundation.sql','papi_block_cleanup.sql','papi_message_delivery.sql','papi_social_pair_rpcs.sql',
    'papi_message_attachments.sql','papi_call_runtime_gate.sql','papi_call_sessions.sql',
    'papi_call_revocations.sql','papi_voice_topics.sql','papi_voice_runtime_gate.sql',
    'papi_voice_membership.sql','papi_livekit_token_limits.sql',
    'papi_account_deletion_runtime.sql','papi_account_deletion_receipt_privacy.sql',
    'papi_account_deletion_private_guards.sql','papi_account_deletion_private_begin.sql',
    'papi_account_deletion_service_rpcs.sql','papi_retained_message_attachments.sql',
  ]) await apply(file);
  await sql(`grant usage on schema papi_private to service_role;
    create table public.coffee_purchase_orders(id uuid primary key,owner_id uuid not null references public.coffee_profiles(id) on delete cascade,completed_at timestamptz);`);
  const a='00000000-0000-4000-8000-000000000001',b='00000000-0000-4000-8000-000000000002';
  const call='10000000-0000-4000-8000-000000000001',call2='10000000-0000-4000-8000-000000000002';
  const session='20000000-0000-4000-8000-000000000001',sessionB='20000000-0000-4000-8000-000000000003';
  const late='20000000-0000-4000-8000-000000000002',msg='30000000-0000-4000-8000-000000000001';
  const receipt='a'.repeat(64);
  await sql(`insert into auth.users(id) values('${a}'),('${b}');
    insert into auth.sessions(id,user_id) values('${a}','${a}'),('${b}','${b}');
    insert into public.coffee_profiles(id,display_name) values('${a}','A'),('${b}','B');
    insert into public.coffee_follows(follower_id,followed_id) values('${a}','${b}'),('${b}','${a}');`);

  await actor(a);
  await sql('set role authenticated');
  await mustFail('select * from papi_private.livekit_token_limits',/permission denied/);
  await mustFail(`select public.complete_coffee_deletion('${receipt}')`,/permission denied/);
  await sql('reset role');
  await mustFail(`select public.request_coffee_call('${call}','${b}')`,/Call unavailable/);
  assert.equal((await scalar(`select public.leave_coffee_voice('room-chat','${late}') as ok`)).ok,true);
  assert.equal((await scalar(`select completed_at is not null as done from papi_private.voice_revocations where session_id='${late}'`)).done,true);
  await sql(`update papi_private.call_runtime_config set enabled=true; update papi_private.voice_runtime_config set enabled=true;`);
  await mustFail(`select public.enter_coffee_voice('room-chat','${late}')`,/Voice session ended/);
  assert.equal((await scalar(`select public.request_coffee_call('${call}','${b}') as id`)).id,call);
  await actor(b);
  assert.equal((await scalar(`select public.answer_coffee_call('${call}',true) as ok`)).ok,true);
  await actor(a);
  assert.equal((await scalar(`select public.can_join_coffee_call('${call}') as ok`)).ok,true);
  assert.equal((await scalar(`select public.enter_coffee_voice('room-chat','${session}') as ok`)).ok,true);
  await actor(b);
  assert.equal((await scalar(`select public.enter_coffee_voice('room-chat','${sessionB}') as ok`)).ok,true);
  await actor(a);
  assert.equal((await scalar(`select public.set_coffee_block('${b}',true) as ok`)).ok,true);
  assert.equal((await scalar(`select status from public.coffee_calls where id='${call}'`)).status,'ended');
  await actor(b);
  assert.equal((await scalar(`select public.can_join_coffee_voice('room-chat','${sessionB}') as ok`)).ok,false);
  await service();
  assert.equal((await scalar(`select public.complete_call_revocation('${call}') as ok`)).ok,true);
  assert.equal((await scalar(`select public.complete_voice_revocation('${sessionB}') as ok`)).ok,true);
  await actor(a);
  assert.equal((await scalar(`select public.set_coffee_block('${b}',false) as ok`)).ok,true);
  assert.equal((await scalar(`select public.set_coffee_follow('${b}',true) as ok`)).ok,true);
  await actor(b);
  assert.equal((await scalar(`select public.set_coffee_follow('${a}',true) as ok`)).ok,true);
  await actor(a);
  assert.equal((await scalar(`select public.request_coffee_call('${call2}','${b}') as id`)).id,call2);
  await actor(b);
  assert.equal((await scalar(`select public.answer_coffee_call('${call2}',true) as ok`)).ok,true);
  await actor(a);
  for (let i=0;i<6;i++) assert.equal((await scalar(`select public.reserve_coffee_voice_token('room-chat','${session}') as ok`)).ok,true);
  assert.equal((await scalar(`select public.reserve_coffee_voice_token('room-chat','${session}') as ok`)).ok,false);

  await sql(`insert into storage.objects(bucket_id,name,owner_id) values
      ('coffee-media','${a}/own.jpg','${a}'),('coffee-media','${b}/message-${msg}.jpg','${b}');
    insert into public.coffee_messages(id,sender_id,recipient_id,body,kind,media_path)
      values('${msg}','${b}','${a}','Photo','photo','${b}/message-${msg}.jpg');
    update papi_private.account_deletion_runtime set enabled=true;
    insert into public.coffee_purchase_orders(id,owner_id) values('40000000-0000-4000-8000-000000000001','${a}');`);
  await mustFail(`select papi_private.begin_coffee_deletion('${receipt}')`,/Purchase reconciliation required/);
  await sql(`delete from public.coffee_purchase_orders where owner_id='${a}';`);
  assert.equal((await scalar(`select papi_private.begin_coffee_deletion('${receipt}') as ok`)).ok,true);
  await service();
  assert.equal((await scalar(`select public.coffee_deletion_sessions_cleared('${receipt}') as ok`)).ok,false);
  assert.equal((await scalar(`select public.complete_call_revocation('${call2}') as ok`)).ok,true);
  assert.equal((await scalar(`select public.complete_voice_revocation('${session}') as ok`)).ok,true);
  assert.equal((await scalar(`select public.coffee_deletion_sessions_cleared('${receipt}') as ok`)).ok,true);
  assert.equal((await scalar(`select public.coffee_deletion_storage_clear('${receipt}') as ok`)).ok,false);
  await sql(`delete from storage.objects where owner_id='${a}';`);
  await sql(`insert into storage.objects(bucket_id,name,owner_id) values('coffee-media','${a}/unexpected.jpg','${b}');`);
  assert.equal((await scalar(`select public.coffee_deletion_storage_clear('${receipt}') as ok`)).ok,false);
  await sql(`delete from storage.objects where name='${a}/unexpected.jpg';`);
  assert.equal((await scalar(`select public.coffee_deletion_storage_clear('${receipt}') as ok`)).ok,true);
  await sql(`delete from auth.users where id='${a}';`);
  assert.equal((await scalar(`select count(*)::int as n from papi_private.retained_message_attachments where message_id='${msg}'`)).n,1);
  assert.equal((await scalar(`select count(*)::int as n from storage.objects where owner_id='${b}'`)).n,1);
  assert.equal((await scalar(`select public.complete_coffee_deletion('${receipt}') as ok`)).ok,true);
  assert.equal((await scalar(`select owner_id is null and state='complete' as ok from papi_private.account_deletions`)).ok,true);
  assert.equal((await scalar(`select public.complete_coffee_deletion('${receipt}') as ok`)).ok,true);
  await actor(a);
  assert.equal((await scalar('select papi_private.coffee_actor_active() as ok')).ok,false);
  console.log('PASS: local SQL privileges, call consent and blocking, voice cancellation and limits, deletion prerequisites, retained attachment, receipt retry');
} finally {await db.close();}
