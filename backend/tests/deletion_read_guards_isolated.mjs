// Exercises the actual public read RPCs with the draft deletion RLS policies.
// Only isolated local fixture data is created or modified.
import {createRequire} from 'node:module';
import {readFile,realpath} from 'node:fs/promises';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const root=process.env.PAPI_NATIVE_PG_ROOT,database=process.env.PAPI_NATIVE_TEST_DB;
if(!root || !resolve(root).startsWith('/tmp/') || !/^papi_test_[a-z0-9]+$/.test(database || '')) throw new Error('Disposable database required');
const {Client}=createRequire(resolve(root,'package.json'))('pg');
const connect=async()=>{const c=new Client({host:root,port:55472,user:'papi_test',database});await c.connect();return c;};
const db=await connect();
const check=(await db.query("select current_setting('data_directory') as dir,inet_server_addr() as addr,to_regclass('public.coffee_profiles') as fixture")).rows[0];
if(check.addr!==null || !check.fixture || await realpath(check.dir)!==await realpath(resolve(root,'data'))) {await db.end();throw new Error('Not an isolated fixture');}
const apply=async name=>db.query(await readFile(resolve('backend',name),'utf8'));
const actor='00000000-0000-4000-8000-000000000101',peer='00000000-0000-4000-8000-000000000102';
const revokedSession='00000000-0000-4000-8000-000000000103';
const post='70000000-0000-4000-8000-000000000101',comment='80000000-0000-4000-8000-000000000101';
const image='a0000000-0000-4000-8000-000000000101',message='50000000-0000-4000-8000-000000000101';
const claims=(id,session=id)=>JSON.stringify({sub:id,role:'authenticated',session_id:session});
try {
  for(const file of ['papi_moment_reactions.sql','papi_wallet_foundation.sql','papi_daily_checkin.sql']) await apply(file);
  await db.query('begin');await apply('papi_progress.sql');await db.query('commit');
  for(const file of ['papi_collectibles.sql','papi_recipe_unlock.sql','papi_moderation.sql']) await apply(file);
  const images=await readFile(resolve('backend/papi_profile_images.sql'),'utf8');
  await db.query(images.slice(0,images.indexOf('alter table papi_private.moderation_events')));
  for(const file of ['papi_content_pagination.sql','papi_moment_shelves.sql','papi_profile_image_summary.sql',
    'papi_message_pagination.sql','papi_wallet_snapshot.sql','papi_recent_moments.sql']) await apply(file);
  for(const name of ['coffee_brew_books','coffee_brew_history']) await db.query(`create table public.${name}(id uuid primary key default gen_random_uuid());alter table public.${name} enable row level security`);
  for(const name of ['brew_book_writes','removed_post_media','removed_profile_media']) await db.query(`create table papi_private.${name}(id uuid primary key default gen_random_uuid())`);
  await db.query('alter table public.coffee_purchase_orders enable row level security');
  for(const id of [actor,peer]) {
    await db.query('insert into auth.users(id) values($1)',[id]);
    await db.query('insert into auth.sessions(id,user_id) values($1,$1)',[id]);
    await db.query("insert into public.coffee_profiles(id,display_name) values($1,'Fixture')",[id]);
  }
  await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[revokedSession,actor]);
  await db.query('insert into public.coffee_follows(follower_id,followed_id) values($1,$2),($2,$1)',[actor,peer]);
  await db.query("insert into public.coffee_posts(id,author_id,caption,media_path,media_kind,moderation_status) values($1,$2,'Fixture','fixture.jpg','photo','approved')",[post,peer]);
  await db.query("insert into public.coffee_comments(id,post_id,author_id,body,moderation_status) values($1,$2,$3,'Fixture','approved')",[comment,post,peer]);
  await db.query("insert into public.coffee_profile_images(id,owner_id,kind,media_path,moderation_status) values($1,$2,'avatar','fixture-avatar.jpg','approved')",[image,peer]);
  await db.query("insert into public.coffee_messages(id,sender_id,recipient_id,body) values($1,$2,$3,'Fixture')",[message,peer,actor]);
  await db.query('insert into public.coffee_bookmarks(moment_id,member_id) values($1,$2)',[post,actor]);
  await apply('papi_account_deletion_guards_draft.sql');
  const calls=[
    ['comment','select count(*)::int as n from public.coffee_comment_page($1,null,null)',[post]],
    ['conversation','select count(*)::int as n from public.coffee_conversation_page($1,null,null)',[peer]],
    ['inbox','select count(*)::int as n from public.coffee_message_inbox()',[]],
    ['shelf','select count(*)::int as n from public.coffee_moment_shelf($1,false,null,null)',[peer]],
    ['profile image page','select count(*)::int as n from public.coffee_profile_image_page($1,null,null)',[peer]],
    ['profile image summary','select count(*)::int as n from public.coffee_profile_image_summary($1::uuid[])',[[peer]]],
    ['wallet','select (public.coffee_wallet_snapshot() is not null)::int as n',[]],
    ['recent','select count(*)::int as n from public.recent_coffee_moments(null,null,$1)',[post]],
  ];
  const client=await connect();
  try {
    await client.query('begin');await client.query('set local role authenticated');
    await client.query("select set_config('request.jwt.claims',$1,true)",[claims(actor)]);
    for(const [label,sql,args] of calls) assert.equal((await client.query(sql,args)).rows[0].n,1,`${label} should be visible before deletion`);
    await client.query('rollback');
    await db.query('delete from auth.sessions where id=$1',[revokedSession]);
    await client.query('begin');await client.query('set local role authenticated');
    await client.query("select set_config('request.jwt.claims',$1,true)",[claims(actor,revokedSession)]);
    for(const [label,sql,args] of calls) assert.equal((await client.query(sql,args)).rows[0].n,0,`${label} must be hidden after session revocation`);
    await client.query('rollback');
    await db.query("select set_config('request.jwt.claims',$1,false)",[claims(actor)]);
    assert.equal((await db.query('select papi_private.begin_coffee_deletion($1) as ok',['a'.repeat(63)+'b'])).rows[0].ok,true);
    await client.query('begin');await client.query('set local role authenticated');
    await client.query("select set_config('request.jwt.claims',$1,true)",[claims(actor)]);
    for(const [label,sql,args] of calls) assert.equal((await client.query(sql,args)).rows[0].n,0,`${label} must be hidden during deletion`);
    await client.query('rollback');
  } finally {await client.end();}
  console.log('PASS: eight actual read RPCs hide data after session revocation or deletion begins under draft RLS');
} finally {await db.end();}
