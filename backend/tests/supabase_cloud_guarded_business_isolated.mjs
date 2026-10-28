// Positive-path smoke checks for draft guards against synthetic users and coins
// in the explicitly isolated project. No real user data or Apple transactions.
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const url='https://bezftktzpyuykuvnbilm.supabase.co',key=process.env.PAPI_ISOLATED_PUBLISHABLE_KEY,root=process.env.PAPI_ISOLATED_SDK_ROOT;
if(!key?.startsWith('sb_publishable_') || !root || !resolve(root).startsWith('/tmp/')) throw new Error('Isolated configuration required');
const {createClient}=createRequire(resolve(root,'package.json'))('@supabase/supabase-js');
const make=()=>createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const a=make(),b=make();let stage='sign-in';
const need=(result,label)=>{if(result.error) throw Object.assign(new Error(label),{stage:label,status:result.error.status,code:result.error.code});return result.data;};
try {
  const first=need(await a.auth.signInAnonymously(),'sign-in A').user,second=need(await b.auth.signInAnonymously(),'sign-in B').user;
  assert.ok(first && second && first.id!==second.id);
  for(const [c,u] of [[a,first],[b,second]]) need(await c.from('coffee_profiles').insert({id:u.id,display_name:'Guard fixture',biography:''}),'profile');
  stage='wallet and book';
  assert.equal(Number(need(await a.rpc('coffee_wallet_snapshot'),'wallet').balance),800);
  need(await a.rpc('check_in_coffee'),'check-in');
  assert.equal(Number(need(await a.rpc('unlock_coffee_recipe',{recipe:'bright-four-pour'}),'recipe')),690);
  assert.equal(Number(need(await a.rpc('collect_coffee_item',{order_id:randomUUID(),item:'love',item_quantity:1}),'collectible')),610);
  const request=randomUUID(),book={fixture:'isolated'};
  const saved=need(await a.rpc('save_coffee_brew_book',{p_request:request,p_revision:0,p_contents:book}),'book');assert.equal(Number(saved.committed_revision),1);
  assert.equal(Number(need(await a.rpc('save_coffee_brew_book',{p_request:request,p_revision:0,p_contents:book}),'book retry').committed_revision),1);
  stage='media submission';
  const bytes=Uint8Array.from([0xff,0xd8,0xff,0xd9]),moment=randomUUID(),path=`${first.id}/moment-${moment}.jpg`;
  need(await a.storage.from('coffee-media').upload(path,bytes,{contentType:'image/jpeg'}),'moment upload');
  assert.equal(Number(need(await a.rpc('submit_coffee_moment',{moment_id:moment,caption:'isolated fixture',media_path:path,media_kind:'photo'}),'moment')),570);
  const image=randomUUID(),imagePath=`${first.id}/profile-${image}.jpg`;
  need(await a.storage.from('coffee-media').upload(imagePath,bytes,{contentType:'image/jpeg'}),'profile image upload');
  assert.equal(need(await a.rpc('submit_coffee_profile_image',{p_id:image,p_kind:'avatar'}),'profile image'),true);
  assert.equal(need(await a.rpc('remove_coffee_profile_image',{p_id:image}),'remove profile image'),imagePath);
  stage='social';
  need(await a.rpc('set_coffee_follow',{p_member:second.id,p_enabled:true}),'follow A');
  need(await b.rpc('set_coffee_follow',{p_member:first.id,p_enabled:true}),'follow B');
  const friendship=randomUUID();assert.equal(need(await a.rpc('request_coffee_friendship',{p_id:friendship,p_recipient:second.id}),'friendship request'),friendship);
  assert.equal(need(await b.rpc('answer_coffee_friendship',{p_id:friendship,p_accept:true}),'friendship answer'),true);
  assert.equal(need(await a.rpc('send_coffee_message',{p_id:randomUUID(),p_recipient:second.id,p_body:'isolated fixture'}),'message'),true);
  console.log('PASS: isolated guarded wallet, book, media and social positive paths');
} catch(error) {
  console.error(JSON.stringify({stage:error.stage ?? stage,status:error.status ?? null,code:error.code ?? null,errorType:error.name ?? 'Error'}));
  process.exitCode=1;
}
