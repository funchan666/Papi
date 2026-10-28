// Real settlement SQL against disposable fixture rows on a local-only server.
// Run after live_isolated.mjs against a new papi_test_* database.
import { createRequire } from 'node:module';
import { readFile, realpath } from 'node:fs/promises';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const root=process.env.PAPI_NATIVE_PG_ROOT, database=process.env.PAPI_NATIVE_TEST_DB;
if (!root || !resolve(root).startsWith('/tmp/') || !/^papi_test_[a-z0-9]+$/.test(database || '')) throw new Error('Disposable database required');
const {Client}=createRequire(resolve(root,'package.json'))('pg');
const connect=async()=>{const c=new Client({host:root,port:55472,user:'papi_test',database});await c.connect();return c;};
const admin=await connect();
const check=(await admin.query("select current_setting('data_directory') as dir,inet_server_addr() as addr,to_regclass('public.coffee_profiles') as fixture")).rows[0];
if (check.addr!==null || !check.fixture || await realpath(check.dir)!==await realpath(resolve(root,'data'))) {await admin.end();throw new Error('Not an isolated fixture');}
const owner='00000000-0000-4000-8000-000000000031';
const order='40000000-0000-4000-8000-000000000031';
const product='rkbybzkkqpeaxovi';
const auth=async(c,role)=>c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:owner,role,session_id:owner})]);
const one=async(c,q,p=[]) => (await c.query(q,p)).rows[0];
try {
  await admin.query(`drop table public.coffee_purchase_orders;
    create table public.coffee_wallets(owner_id uuid primary key references public.coffee_profiles(id) on delete cascade,balance bigint not null default 0,updated_at timestamptz);
    create table public.coffee_wallet_movements(owner_id uuid not null references public.coffee_profiles(id) on delete cascade,delta integer,reason text,idempotency_key text unique);`);
  await admin.query(await readFile(resolve('backend/papi_apple_orders.sql'),'utf8'));
  await admin.query('insert into auth.users(id) values($1)',[owner]);
  await admin.query('insert into auth.sessions(id,user_id) values($1,$1)',[owner]);
  await admin.query("insert into public.coffee_profiles(id,display_name) values($1,'Fixture')",[owner]);
  await admin.query('insert into public.coffee_wallets(owner_id,balance) values($1,0)',[owner]);
  await admin.query('insert into public.coffee_purchase_orders(id,owner_id,product_id) values($1,$2,$3)',[order,owner,product]);
  const settlement=await connect(),deletion=await connect();
  try {
    await settlement.query('begin');await auth(settlement,'service_role');
    const settled=await one(settlement,'select papi_private.settle_apple_order($1,$2,$3,$4,$5) as balance',[order,owner,product,'123456789','Sandbox']);
    assert.equal(Number(settled.balance),480);
    await deletion.query('begin');await auth(deletion,'authenticated');
    await assert.rejects(deletion.query('select papi_private.begin_coffee_deletion($1)',['8'.repeat(64)]),/Purchase reconciliation required/);
    await deletion.query('rollback');
    await settlement.query('commit');
    assert.equal((await one(admin,'select completed_at is not null as done from public.coffee_purchase_orders where id=$1',[order])).done,true);
    assert.equal(Number((await one(admin,'select balance from public.coffee_wallets where owner_id=$1',[owner])).balance),480);

    await deletion.query('begin');await auth(deletion,'authenticated');
    assert.equal((await one(deletion,'select papi_private.begin_coffee_deletion($1) as ok',['8'.repeat(64)])).ok,true);
    await deletion.query('commit');
    await settlement.query('begin');await auth(settlement,'service_role');
    assert.equal(Number((await one(settlement,'select papi_private.settle_apple_order($1,$2,$3,$4,$5) as balance',[order,owner,product,'123456789','Sandbox'])).balance),480);
    await settlement.query('commit');
    assert.equal(Number((await one(admin,'select balance from public.coffee_wallets where owner_id=$1',[owner])).balance),480);
    assert.equal((await one(admin,'select count(*)::int as n from papi_private.apple_transactions where owner_id=$1',[owner])).n,1);
    console.log('PASS: pending settlement blocks deletion; repeated settlement after deletion starts does not double-credit');
  } finally {await settlement.end();await deletion.end();}
} finally {await admin.end();}
