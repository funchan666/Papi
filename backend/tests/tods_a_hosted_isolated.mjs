// Real API validation against the explicitly designated isolated project only.
// Records only fixture user IDs locally for exact cleanup; never stores tokens.
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const url='https://bezftktzpyuykuvnbilm.supabase.co';
const key=process.env.PAPI_ISOLATED_PUBLISHABLE_KEY;
if (!key?.startsWith('sb_publishable_')) throw new Error('Isolated publishable key required');
const {createClient}=createRequire('/tmp/papi-isolated-supabase/package.json')('@supabase/supabase-js');
const make=()=>createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const clients=[make(),make()], users=[];let stage='setup';let mediaPath;
const saveIDs=async()=>writeFile('/tmp/papi-isolated-supabase/tods-a-current-ids.json',JSON.stringify({project:'bezftktzpyuykuvnbilm',users:users.map(x=>x.id)}),{mode:0o600});
const need=(response,label)=>{if(response.error)throw Object.assign(new Error(label),{stage:label,code:response.error.code,status:response.error.status});return response.data};
try {
  for (const [i,c] of clients.entries()) {
    const session=need(await c.auth.signInAnonymously(),`sign-in-${i}`);assert.ok(session.user?.id && session.session?.access_token);users.push(session.user);await saveIDs();
    const bootstrap=need(await c.functions.invoke('papi-bootstrap',{body:{}}),`bootstrap-${i}`);assert.deepEqual(bootstrap,{code:0,message:'ok',data:{}});
    need(await c.from('coffee_profiles').insert({id:session.user.id,display_name:`Test ${i}`,biography:''}),`profile-${i}`);
  }
  const [a,b]=clients;assert.notEqual(users[0].id,users[1].id);
  stage='catalogs';
  for(const [table,count] of [['coffee_asset_catalog',81],['coffee_editorial_catalog',40],['coffee_editorial_people',41],['coffee_reference_guides',10],['coffee_brew_recipes',5],['coffee_gift_catalog',8]]) {
    const rows=need(await a.from(table).select('*'),table);assert.equal(rows.length,count,table);
  }
  stage='personal';
  assert.equal(need(await a.rpc('set_saved_coffee_scene',{p_scene:'home-espresso-corner',p_enabled:true}),'scene-save'),true);
  const idea=randomUUID();assert.equal(need(await a.rpc('save_coffee_gift_idea',{p_id:idea,p_gift:'love',p_quantity:2,p_context:'fixture'}),'idea-save'),true);
  assert.equal(need(await a.rpc('record_coffee_room_visit',{p_topic:'room-chat'}),'room-visit'),true);
  const ideas=need(await a.from('coffee_gift_ideas').select('id'),'own-ideas');assert.ok(ideas.some(x=>x.id===idea));
  assert.equal(need(await b.from('coffee_gift_ideas').select('id').eq('id',idea),'other-ideas').length,0);
  assert.equal(need(await b.from('coffee_saved_scenes').select('owner_id').eq('owner_id',users[0].id),'other-scenes').length,0);
  assert.equal(need(await b.from('coffee_recent_voice_rooms').select('owner_id').eq('owner_id',users[0].id),'other-rooms').length,0);
  assert.ok((await b.rpc('save_coffee_gift_idea',{p_id:idea,p_gift:'love',p_quantity:2,p_context:'fixture'})).error,'foreign idea ID must be rejected');
  stage='wallet';
  assert.equal(Number(need(await a.rpc('coffee_wallet_snapshot'),'wallet-A').balance),800);
  assert.equal(Number(need(await b.rpc('coffee_wallet_snapshot'),'wallet-B').balance),800);
  assert.equal(Number(need(await a.rpc('collect_coffee_item',{order_id:randomUUID(),item:'love',item_quantity:1}),'collect')),720);
  assert.equal(need(await a.rpc('set_coffee_displayed_gift',{p_gift:'love'}),'display-gift'),true);
  assert.equal(need(await b.from('coffee_displayed_gifts').select('owner_id').eq('owner_id',users[0].id),'other-display').length,0);
  assert.equal(Number(need(await b.rpc('coffee_wallet_snapshot'),'wallet-B-after').balance),800);
  stage='book';
  const book=need(await a.rpc('save_coffee_brew_book',{p_request:randomUUID(),p_revision:0,p_contents:{fixture:'isolated'}}),'book-write');assert.equal(Number(book.committed_revision),1);
  assert.equal(need(await b.from('coffee_brew_books').select('owner_id').eq('owner_id',users[0].id),'other-book').length,0);
  stage='social';
  need(await a.rpc('set_coffee_follow',{p_member:users[1].id,p_enabled:true}),'follow-A');need(await b.rpc('set_coffee_follow',{p_member:users[0].id,p_enabled:true}),'follow-B');
  const message=randomUUID();need(await a.rpc('send_coffee_message',{p_id:message,p_recipient:users[1].id,p_body:'isolated fixture'}),'send-message');
  assert.equal(need(await b.from('coffee_messages').select('id').eq('id',message),'receive-message').length,1);
  stage='private-storage';
  mediaPath=`${users[0].id}/moment-${randomUUID()}.jpg`;
  need(await a.storage.from('coffee-media').upload(mediaPath,Uint8Array.from([255,216,255,217]),{contentType:'image/jpeg'}),'own-upload');
  assert.ok((await b.storage.from('coffee-media').download(mediaPath)).error,'private object must reject another user');
  need(await a.storage.from('coffee-media').remove([mediaPath]),'remove-fixture-media');mediaPath=undefined;
  console.log('PASS: isolated Auth, bootstrap, six catalogs, personal data, RLS, wallet, brew book, messaging and private storage');
} catch(e) {console.error(JSON.stringify({stage:e.stage??stage,status:e.status??null,code:e.code??null,error:e.message}));process.exitCode=1}
finally {if(mediaPath){const r=await clients[0].storage.from('coffee-media').remove([mediaPath]);if(r.error){console.error('fixture media cleanup failed');process.exitCode=1}};await saveIDs()}
