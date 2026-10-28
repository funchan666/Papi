// Checks every draft public deletion guard against revoked and pending sessions.
// Private business implementations are not exercised by these denial checks.
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
const pending='00000000-0000-4000-8000-000000000091',revoked='00000000-0000-4000-8000-000000000092';
const claims=id=>JSON.stringify({sub:id,role:'authenticated',session_id:id});
try {
  for(const id of [pending,revoked]) {
    await db.query('insert into auth.users(id) values($1)',[id]);
    await db.query('insert into auth.sessions(id,user_id) values($1,$1)',[id]);
    await db.query("insert into public.coffee_profiles(id,display_name) values($1,'Fixture')",[id]);
  }
  const draft=await readFile(resolve('backend/papi_account_deletion_rpc_guards_draft.sql'),'utf8');
  const names=[...draft.matchAll(/create or replace function public\.([a-z_]+)\(/g)].map(m=>m[1]);
  assert.equal(names.length,27);assert.equal(new Set(names).size,27);
  await db.query(draft);
  const funcs=(await db.query(`select p.proname,
    array(select pg_catalog.format_type(t.oid,null) from unnest(p.proargtypes::oid[]) with ordinality as arg(oid,ord)
      join pg_catalog.pg_type t on t.oid=arg.oid order by arg.ord) as argtypes
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any($1::text[]) order by p.proname`,[names])).rows;
  assert.equal(funcs.length,names.length);
  await db.query("select set_config('request.jwt.claims',$1,false)",[claims(pending)]);
  await db.query('select papi_private.require_coffee_actor_active()');
  assert.equal((await db.query('select papi_private.begin_coffee_deletion($1) as ok',['9'.repeat(64)])).rows[0].ok,true);
  await db.query('delete from auth.sessions where id=$1',[revoked]);
  const client=await connect();
  try {
    for(const id of [pending,revoked]) {
      await client.query('begin');await client.query('set local role authenticated');
      await client.query("select set_config('request.jwt.claims',$1,true)",[claims(id)]);
      for(const fn of funcs) {
        assert.match(fn.proname,/^[a-z_]+$/);
        for(const type of fn.argtypes) assert.match(type,/^[a-z ]+$/);
        const args=fn.argtypes.map(type=>`null::${type}`).join(',');
        await client.query('savepoint before_rpc');
        await assert.rejects(client.query(`select public.${fn.proname}(${args})`),/Account unavailable/,fn.proname);
        await client.query('rollback to savepoint before_rpc');
      }
      await client.query('rollback');
    }
  } finally {await client.end();}
  console.log('PASS: all 27 draft RPC guards reject pending-deletion and revoked sessions');
} finally {await db.end();}
