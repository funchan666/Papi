// Uses only the disposable native PostgreSQL instance initialized by
// live_isolated.mjs. Never connect this script to a remote or production DB.
import { createRequire } from 'node:module';
import { readFile, realpath } from 'node:fs/promises';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const root=process.env.PAPI_NATIVE_PG_ROOT;
if (!root || !resolve(root).startsWith('/tmp/')) throw new Error('An isolated temporary PostgreSQL prefix is required');
const database=process.env.PAPI_NATIVE_TEST_DB || 'postgres';
if (database!=='postgres' && !/^papi_test_[a-z0-9]+$/.test(database)) throw new Error('Invalid isolated database name');
const {Client}=createRequire(resolve(root,'package.json'))('pg');
const connect=async ()=>{const c=new Client({host:root,port:55472,user:'papi_test',database});await c.connect();return c;};
const admin=await connect();
const identity=await admin.query("select current_setting('data_directory') as dir,inet_server_addr() as addr,to_regclass('public.coffee_profiles') as fixture");
if (identity.rows[0].addr!==null || identity.rows[0].fixture===null ||
    await realpath(identity.rows[0].dir)!==await realpath(resolve(root,'data'))) {
  await admin.end();throw new Error('Refusing to modify a non-isolated database');
}
const runFile=async file=>admin.query(await readFile(resolve('backend',file),'utf8'));
const pause=()=>new Promise(resolve=>setTimeout(resolve,150));
const claims=id=>JSON.stringify({sub:id,role:'authenticated',session_id:id});
const start=async (client,id)=>{await client.query('begin');await client.query('set local role authenticated');await client.query("select set_config('request.jwt.claims',$1,true)",[claims(id)]);};
const one=async (client,query,args=[]) => (await client.query(query,args)).rows[0];
const makePair=async (a,b)=>{
  await admin.query('insert into auth.users(id) values($1),($2)',[a,b]);
  await admin.query('insert into auth.sessions(id,user_id) values($1,$1),($2,$2)',[a,b]);
  await admin.query("insert into public.coffee_profiles(id,display_name) values($1,'A'),($2,'B')",[a,b]);
  await admin.query('insert into public.coffee_follows(follower_id,followed_id) values($1,$2),($2,$1)',[a,b]);
};

try {
  // These empty local stubs permit installation of the full guard policies;
  // only message/call/voice tables in this script use their real definitions.
  await runFile('papi_moment_reactions.sql');
  const publicStubs=['coffee_brew_books','coffee_brew_history','coffee_checkins',
    'coffee_collectible_orders','coffee_collectibles','coffee_profile_images',
    'coffee_progress','coffee_recipe_unlocks','coffee_wallet_movements','coffee_wallets'];
  for (const name of publicStubs) await admin.query(`create table public.${name}(id uuid primary key default gen_random_uuid()); alter table public.${name} enable row level security`);
  for (const name of ['brew_book_writes','removed_post_media','removed_profile_media'])
    await admin.query(`create table papi_private.${name}(id uuid primary key default gen_random_uuid())`);
  await admin.query('alter table public.coffee_purchase_orders enable row level security');
  await runFile('papi_account_pair_lock.sql');
  await runFile('papi_account_deletion_draft.sql');
  await runFile('papi_account_deletion_guards_draft.sql');
  await runFile('papi_account_deletion_pair_lock_draft.sql');
  await runFile('papi_account_deletion_post_guard_draft.sql');
  await admin.query(`grant insert on storage.objects to authenticated;
    create policy isolated_owned_upload on storage.objects for insert to authenticated
      with check (bucket_id='coffee-media' and owner_id=auth.uid()::text and name like auth.uid()::text || '/%')`);
  await admin.query(`grant insert on public.coffee_purchase_orders to authenticated;
    create policy isolated_owned_order on public.coffee_purchase_orders for insert to authenticated
      with check (owner_id=auth.uid() and completed_at is null)`);
  const wrappers=await readFile(resolve('backend/papi_account_deletion_rpc_guards_draft.sql'),'utf8');
  await admin.query(wrappers.slice(0,wrappers.indexOf('create or replace function public.')));
  const block=wrappers.match(/create or replace function public\.send_coffee_message\([\s\S]*?\n\$\$;/);
  if (!block) throw new Error('Guarded message wrapper missing');
  await admin.query(block[0]);
  await admin.query('update papi_private.account_deletion_runtime set enabled=true');

  const a='00000000-0000-4000-8000-000000000011',b='00000000-0000-4000-8000-000000000012';
  const c='00000000-0000-4000-8000-000000000013',d='00000000-0000-4000-8000-000000000014';
  const e='00000000-0000-4000-8000-000000000015',f='00000000-0000-4000-8000-000000000016';
  const g='00000000-0000-4000-8000-000000000017',h='00000000-0000-4000-8000-000000000018';
  const i='00000000-0000-4000-8000-000000000019',j='00000000-0000-4000-8000-000000000020';
  const k='00000000-0000-4000-8000-000000000021',l='00000000-0000-4000-8000-000000000022';
  const m='00000000-0000-4000-8000-000000000023',n='00000000-0000-4000-8000-000000000024';
  const o='00000000-0000-4000-8000-000000000025',p='00000000-0000-4000-8000-000000000026';
  const q='00000000-0000-4000-8000-000000000027',r='00000000-0000-4000-8000-000000000028';
  await makePair(a,b);await makePair(c,d);await makePair(e,f);await makePair(g,h);
  await makePair(i,j);await makePair(k,l);await makePair(m,n);
  await makePair(o,p);await makePair(q,r);
  await admin.query("insert into public.coffee_posts(id,author_id,caption,media_path,media_kind,moderation_status) values($1,$2,'one','one.jpg','photo','approved'),($3,$4,'two','two.jpg','photo','approved')",['70000000-0000-4000-8000-000000000001',i,'70000000-0000-4000-8000-000000000002',k]);
  const sender=await connect(),deleting=await connect();
  try {
    // The sender holds the pair lock; deletion must wait until its message commits.
    await start(sender,b);
    assert.equal((await one(sender,"select public.send_coffee_message($1,$2,'first') as ok",['50000000-0000-4000-8000-000000000001',a])).ok,true);
    await start(deleting,a);
    let state='waiting';
    const deletion=deleting.query('select public.begin_coffee_deletion($1) as ok',['b'.repeat(64)]).then(x=>{state='done';return x;},e=>{state='error';throw e;});
    await pause();assert.equal(state,'waiting');
    await sender.query('commit');assert.equal((await deletion).rows[0].ok,true);await deleting.query('commit');
    // The still-valid JWT is no longer allowed to read its profile or mutate it.
    await start(sender,a);
    assert.equal((await one(sender,'select count(*)::int as n from public.coffee_profiles where id=$1',[a])).n,0);
    await assert.rejects(sender.query("insert into public.coffee_purchase_orders(id,owner_id) values($1,$2)",['40000000-0000-4000-8000-000000000004',a]),/Account unavailable|row-level security/);
    await sender.query('rollback');

    // Deletion holds the target lock; a later send must wait and then fail.
    await start(deleting,c);
    assert.equal((await one(deleting,'select public.begin_coffee_deletion($1) as ok',['c'.repeat(64)])).ok,true);
    await start(sender,d);
    state='waiting';
    const send=sender.query("select public.send_coffee_message($1,$2,'late') as ok",['50000000-0000-4000-8000-000000000002',c]).then(()=>{state='done';return null;},e=>{state='error';return e;});
    await pause();assert.equal(state,'waiting');
    await deleting.query('commit');const failure=await send;assert.ok(failure);assert.match(failure.message,/Mutual following required|Account unavailable/);
    await sender.query('rollback');

    // A call request already holding the call lock finishes before deletion.
    await start(sender,f);
    assert.equal((await one(sender,'select public.request_coffee_call($1,$2) as id',['60000000-0000-4000-8000-000000000001',e])).id,'60000000-0000-4000-8000-000000000001');
    await start(deleting,e);
    state='waiting';
    const afterCall=deleting.query('select public.begin_coffee_deletion($1) as ok',['d'.repeat(64)]).then(x=>{state='done';return x;},err=>{state='error';throw err;});
    await pause();assert.equal(state,'waiting');
    await sender.query('commit');assert.equal((await afterCall).rows[0].ok,true);await deleting.query('commit');
    assert.equal((await one(admin,"select status from public.coffee_calls where id='60000000-0000-4000-8000-000000000001'")).status,'ended');

    // A call request behind deletion must not create a fresh session.
    await start(deleting,g);
    assert.equal((await one(deleting,'select public.begin_coffee_deletion($1) as ok',['e'.repeat(64)])).ok,true);
    await start(sender,h);
    state='waiting';
    const lateCall=sender.query('select public.request_coffee_call($1,$2) as id',['60000000-0000-4000-8000-000000000002',g]).then(()=>{state='done';return null;},err=>{state='error';return err;});
    await pause();assert.equal(state,'waiting');
    await deleting.query('commit');const callFailure=await lateCall;assert.ok(callFailure);assert.match(callFailure.message,/Mutual following required|Account unavailable/);
    await sender.query('rollback');

    // A reaction holds both accounts before deletion starts.
    await start(sender,j);
    await sender.query('insert into public.coffee_likes(moment_id,member_id) values($1,$2)',['70000000-0000-4000-8000-000000000001',j]);
    await start(deleting,i);
    state='waiting';
    const afterLike=deleting.query('select public.begin_coffee_deletion($1) as ok',['f'.repeat(64)]).then(x=>{state='done';return x;},err=>{state='error';throw err;});
    await pause();assert.equal(state,'waiting');
    await sender.query('commit');assert.equal((await afterLike).rows[0].ok,true);await deleting.query('commit');

    // A comment behind deletion must fail after the author is marked pending.
    await start(deleting,k);
    assert.equal((await one(deleting,'select public.begin_coffee_deletion($1) as ok',['1'.repeat(64)])).ok,true);
    await start(sender,l);
    state='waiting';
    const lateComment=sender.query("insert into public.coffee_comments(id,post_id,author_id,body) values($1,$2,$3,'late')",['80000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000002',l]).then(()=>{state='done';return null;},err=>{state='error';return err;});
    await pause();assert.equal(state,'waiting');
    await deleting.query('commit');const commentFailure=await lateComment;assert.ok(commentFailure);assert.match(commentFailure.message,/Post unavailable|row-level security/);
    await sender.query('rollback');

    // A voice join already in progress must finish before deletion closes it.
    await start(sender,m);
    assert.equal((await one(sender,"select public.enter_coffee_voice('room-chat',$1) as ok",['90000000-0000-4000-8000-000000000001'])).ok,true);
    await start(deleting,m);
    state='waiting';
    const afterVoice=deleting.query('select public.begin_coffee_deletion($1) as ok',['2'.repeat(64)]).then(x=>{state='done';return x;},err=>{state='error';throw err;});
    await pause();assert.equal(state,'waiting');
    await sender.query('commit');assert.equal((await afterVoice).rows[0].ok,true);await deleting.query('commit');
    assert.equal((await one(admin,"select status from papi_private.voice_members where owner_id=$1",[m])).status,'closing');

    // A later join from another device with the same account must fail.
    await start(deleting,n);
    assert.equal((await one(deleting,'select public.begin_coffee_deletion($1) as ok',['3'.repeat(64)])).ok,true);
    await start(sender,n);
    state='waiting';
    const lateVoice=sender.query("select public.enter_coffee_voice('room-chat',$1) as ok",['90000000-0000-4000-8000-000000000002']).then(()=>{state='done';return null;},err=>{state='error';return err;});
    await pause();assert.equal(state,'waiting');
    await deleting.query('commit');const voiceFailure=await lateVoice;assert.ok(voiceFailure);assert.match(voiceFailure.message,/Account unavailable|Voice room unavailable/);
    await sender.query('rollback');

    // An in-flight upload finishes before deletion takes its owner lock.
    await start(sender,o);
    await sender.query("insert into storage.objects(bucket_id,name,owner_id) values('coffee-media',$1,$2)",[o+'/before.jpg',o]);
    await start(deleting,o);
    state='waiting';
    const afterUpload=deleting.query('select public.begin_coffee_deletion($1) as ok',['4'.repeat(64)]).then(x=>{state='done';return x;},err=>{state='error';throw err;});
    await pause();assert.equal(state,'waiting');
    await sender.query('commit');assert.equal((await afterUpload).rows[0].ok,true);await deleting.query('commit');
    assert.equal((await one(admin,'select count(*)::int as n from storage.objects where owner_id=$1',[o])).n,1);

    // A stale session attempting an upload after deletion has begun is denied.
    await start(deleting,p);
    assert.equal((await one(deleting,'select public.begin_coffee_deletion($1) as ok',['5'.repeat(64)])).ok,true);
    await start(sender,p);
    state='waiting';
    const lateUpload=sender.query("insert into storage.objects(bucket_id,name,owner_id) values('coffee-media',$1,$2)",[p+'/late.jpg',p]).then(()=>{state='done';return null;},err=>{state='error';return err;});
    await pause();assert.equal(state,'waiting');
    await deleting.query('commit');const uploadFailure=await lateUpload;assert.ok(uploadFailure);assert.match(uploadFailure.message,/row-level security/);
    await sender.query('rollback');
    assert.equal((await one(admin,'select count(*)::int as n from storage.objects where owner_id=$1',[p])).n,0);

    // A pending order committed first prevents deletion, preserving reconciliation.
    await start(sender,q);
    await sender.query('insert into public.coffee_purchase_orders(id,owner_id) values($1,$2)',['40000000-0000-4000-8000-000000000002',q]);
    await start(deleting,q);
    state='waiting';
    const afterOrder=deleting.query('select public.begin_coffee_deletion($1) as ok',['6'.repeat(64)]).then(()=>{state='done';return null;},err=>{state='error';return err;});
    await pause();assert.equal(state,'waiting');
    await sender.query('commit');const orderFailure=await afterOrder;assert.ok(orderFailure);assert.match(orderFailure.message,/Purchase reconciliation required/);
    await deleting.query('rollback');
    assert.equal((await one(admin,'select count(*)::int as n from public.coffee_purchase_orders where owner_id=$1',[q])).n,1);

    // A new order cannot be inserted behind a deletion already in progress.
    await start(deleting,r);
    assert.equal((await one(deleting,'select public.begin_coffee_deletion($1) as ok',['7'.repeat(64)])).ok,true);
    await start(sender,r);
    state='waiting';
    const lateOrder=sender.query('insert into public.coffee_purchase_orders(id,owner_id) values($1,$2)',['40000000-0000-4000-8000-000000000003',r]).then(()=>{state='done';return null;},err=>{state='error';return err;});
    await pause();assert.equal(state,'waiting');
    await deleting.query('commit');const lateOrderFailure=await lateOrder;assert.ok(lateOrderFailure);assert.match(lateOrderFailure.message,/Account unavailable|row-level security/);
    await sender.query('rollback');
    console.log('PASS: stale sessions and concurrent messages, calls, reactions, comments, voice joins, uploads and order creation versus deletion');
  } finally {await sender.end();await deleting.end();}
} finally {await admin.end();}
