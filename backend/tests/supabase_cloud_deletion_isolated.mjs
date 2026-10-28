// Runs only against the explicitly created Papi-Isolated-Validation project.
// Creates synthetic guest users/files and deletes one synthetic user through
// the actual Edge Function. Never pass production credentials or real data.
import {createRequire} from 'node:module';
import {randomBytes,randomUUID} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';

const url='https://bezftktzpyuykuvnbilm.supabase.co';
const key=process.env.PAPI_ISOLATED_PUBLISHABLE_KEY;
const root=process.env.PAPI_ISOLATED_SDK_ROOT;
if(!key?.startsWith('sb_publishable_') || !root || !resolve(root).startsWith('/tmp/')) throw new Error('Isolated project key and temporary SDK prefix required');
const {createClient}=createRequire(resolve(root,'package.json'))('@supabase/supabase-js');
const make=()=>createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const recipient=make(),sender=make();
let stage='initialization';
const need=(result,label)=>{
  if(result.error) throw Object.assign(new Error(label),{stage:label,status:result.error.status,code:result.error.code});
  return result.data;
};
try {
  stage='anonymous sign-in';
  const a=need(await recipient.auth.signInAnonymously(),'recipient sign-in').user;
  const b=need(await sender.auth.signInAnonymously(),'sender sign-in').user;
  assert.ok(a && b && a.id!==b.id);
  const message=randomUUID(),owned=`${a.id}/owned-fixture.jpg`,sent=`${b.id}/message-${message}.jpg`;
  const receipt=randomBytes(32).toString('hex');
  await writeFile('/tmp/papi-isolated-supabase/last-fixture.json',JSON.stringify({project:'bezftktzpyuykuvnbilm',recipient:a.id,sender:b.id,message,owned,sent}));
  stage='profile creation';
  for(const [client,user] of [[recipient,a],[sender,b]]) need(await client.from('coffee_profiles').insert({id:user.id,display_name:'Isolated fixture',biography:''}),'profile creation');
  stage='private storage';
  const blob=Uint8Array.from([0xff,0xd8,0xff,0xd9]);
  need(await recipient.storage.from('coffee-media').upload(owned,blob,{contentType:'image/jpeg'}),'recipient upload');
  need(await sender.storage.from('coffee-media').upload(sent,blob,{contentType:'image/jpeg'}),'sender upload');
  assert.ok((await recipient.storage.from('coffee-media').download(sent)).error,'unrelated user must not read private file');
  stage='mutual follow and attachment';
  need(await recipient.rpc('set_coffee_follow',{p_member:b.id,p_enabled:true}),'recipient follow');
  need(await sender.rpc('set_coffee_follow',{p_member:a.id,p_enabled:true}),'sender follow');
  assert.equal(need(await sender.rpc('send_coffee_attachment',{p_id:message,p_recipient:a.id,p_kind:'photo'}),'send attachment'),true);
  need(await recipient.storage.from('coffee-media').download(sent),'recipient attachment access');
  stage='begin deletion';
  assert.equal(need(await recipient.rpc('begin_coffee_deletion',{p_secret:receipt}),'begin deletion'),true);
  const rows=need(await recipient.from('coffee_profiles').select('id').eq('id',a.id),'stale profile read');
  assert.equal(rows.length,0,'old session must not read profile');
  assert.ok((await recipient.storage.from('coffee-media').upload(`${a.id}/late-fixture.jpg`,blob,{contentType:'image/jpeg'})).error,'old session must not upload');
  assert.ok((await recipient.rpc('set_coffee_follow',{p_member:b.id,p_enabled:true})).error,'old session must not mutate');
  stage='edge deletion';
  const result=await fetch(`${url}/functions/v1/delete-coffee-account`,{method:'POST',headers:{apikey:key,'content-type':'application/json'},body:JSON.stringify({receipt})});
  if(result.status!==200) throw Object.assign(new Error('deletion endpoint did not complete'),{status:result.status});
  assert.equal((await result.json()).status,'complete');
  need(await sender.storage.from('coffee-media').download(sent),'sender attachment retained');
  const retry=await fetch(`${url}/functions/v1/delete-coffee-account`,{method:'POST',headers:{apikey:key,'content-type':'application/json'},body:JSON.stringify({receipt})});
  assert.equal(retry.status,200);assert.equal((await retry.json()).status,'complete');
  console.log('PASS: real isolated Supabase Auth, private Storage, stale session, deletion and receipt retry');
} catch(error) {
  console.error(JSON.stringify({stage:error.stage ?? stage,status:error.status ?? null,code:error.code ?? null,message:error.message}));
  process.exitCode=1;
}
