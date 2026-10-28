// Real Auth/RPC checks against the isolated Papi test project only. No media
// is sent and no production account, credential or endpoint is used.
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const url='https://bezftktzpyuykuvnbilm.supabase.co';
const key=process.env.PAPI_ISOLATED_PUBLISHABLE_KEY,root=process.env.PAPI_ISOLATED_SDK_ROOT;
if(!key?.startsWith('sb_publishable_') || !root || !resolve(root).startsWith('/tmp/')) throw new Error('Isolated key and temporary SDK prefix required');
const {createClient}=createRequire(resolve(root,'package.json'))('@supabase/supabase-js');
const make=()=>createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const a=make(),b=make();let stage='sign in';
const need=(result,label)=>{if(result.error) throw Object.assign(new Error(label),{stage:label,status:result.error.status,code:result.error.code});return result.data;};
try {
  const userA=need(await a.auth.signInAnonymously(),'first sign-in').user;
  const userB=need(await b.auth.signInAnonymously(),'second sign-in').user;
  assert.ok(userA && userB && userA.id!==userB.id);
  const call=randomUUID(),voiceA=randomUUID(),voiceB=randomUUID();
  await writeFile('/tmp/papi-isolated-supabase/last-live-fixture.json',JSON.stringify({project:'bezftktzpyuykuvnbilm',a:userA.id,b:userB.id,call,voiceA,voiceB}));
  stage='profiles';
  for(const [client,user] of [[a,userA],[b,userB]]) need(await client.from('coffee_profiles').insert({id:user.id,display_name:'Live fixture',biography:''}),'profile creation');
  stage='mutual follow';
  need(await a.rpc('set_coffee_follow',{p_member:userB.id,p_enabled:true}),'first follow');
  need(await b.rpc('set_coffee_follow',{p_member:userA.id,p_enabled:true}),'second follow');
  stage='voice join';
  assert.equal(need(await a.rpc('enter_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),'first voice join'),true);
  assert.equal(need(await b.rpc('enter_coffee_voice',{p_topic:'room-chat',p_session:voiceB}),'second voice join'),true);
  assert.equal(need(await a.rpc('can_join_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),'voice authorization'),true);
  stage='call consent';
  assert.equal(need(await a.rpc('request_coffee_call',{p_id:call,p_recipient:userB.id}),'call request'),call);
  assert.ok((await a.rpc('answer_coffee_call',{p_id:call,p_accept:true})).error,'caller cannot accept on recipient behalf');
  assert.equal(need(await b.rpc('answer_coffee_call',{p_id:call,p_accept:true}),'call acceptance'),true);
  assert.equal(need(await a.rpc('can_join_coffee_call',{p_id:call}),'call authorization'),true);
  stage='block cleanup';
  assert.equal(need(await b.rpc('set_coffee_block',{p_member:userA.id,p_enabled:true}),'block'),true);
  assert.equal(need(await a.rpc('can_join_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),'blocked voice authorization'),false);
  assert.equal(need(await a.rpc('can_join_coffee_call',{p_id:call}),'blocked call authorization'),false);
  assert.equal(need(await a.rpc('leave_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),'blocked voice leave'),true);
  console.log('PASS: real isolated Supabase voice membership, call consent and block authorization');
} catch(error) {
  console.error(JSON.stringify({stage:error.stage ?? stage,status:error.status ?? null,code:error.code ?? null,message:error.message}));
  process.exitCode=1;
}
