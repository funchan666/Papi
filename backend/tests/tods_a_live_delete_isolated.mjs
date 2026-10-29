// Real API checks against Papi-Isolated-Validation only; synthetic accounts.
import {createRequire} from 'node:module';
import {randomUUID,randomBytes} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const base='https://bezftktzpyuykuvnbilm.supabase.co',key=process.env.PAPI_ISOLATED_PUBLISHABLE_KEY;
if(!key?.startsWith('sb_publishable_'))throw new Error('Isolated key required');
const {createClient}=createRequire('/tmp/papi-isolated-supabase/package.json')('@supabase/supabase-js');
const make=()=>createClient(base,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const clients=[make(),make()],users=[];let stage='sign-in';
const save=()=>writeFile('/tmp/papi-isolated-supabase/tods-live-current-ids.json',JSON.stringify({project:'bezftktzpyuykuvnbilm',users:users.map(u=>u.id)}),{mode:0o600});
const need=(r,label)=>{if(r.error)throw Object.assign(new Error(label),{stage:label,status:r.error.status,code:r.error.code});return r.data};
try {
 for(const [i,c] of clients.entries()){const u=need(await c.auth.signInAnonymously(),`sign-in-${i}`).user;users.push(u);await save();need(await c.from('coffee_profiles').insert({id:u.id,display_name:'Live fixture',biography:''}),`profile-${i}`)}
 const [a,b]=clients;stage='follow';need(await a.rpc('set_coffee_follow',{p_member:users[1].id,p_enabled:true}),'follow-A');need(await b.rpc('set_coffee_follow',{p_member:users[0].id,p_enabled:true}),'follow-B');
 stage='voice';const voiceA=randomUUID(),voiceB=randomUUID();assert.equal(need(await a.rpc('enter_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),'join-A'),true);assert.equal(need(await b.rpc('enter_coffee_voice',{p_topic:'room-chat',p_session:voiceB}),'join-B'),true);
 const message=randomUUID();need(await a.rpc('send_coffee_voice_message',{p_topic:'room-chat',p_session:voiceA,p_id:message,p_body:'test'}),'voice-message');
 assert.ok(need(await b.rpc('coffee_voice_messages',{p_topic:'room-chat',p_session:voiceB}),'voice-read').some(m=>m.id===message));
 stage='call';const call=randomUUID();assert.equal(need(await a.rpc('request_coffee_call',{p_id:call,p_recipient:users[1].id}),'call-request'),call);assert.ok((await a.rpc('answer_coffee_call',{p_id:call,p_accept:true})).error);assert.equal(need(await b.rpc('answer_coffee_call',{p_id:call,p_accept:true}),'call-accept'),true);assert.equal(need(await a.rpc('can_join_coffee_call',{p_id:call}),'call-join'),true);
 stage='block';assert.equal(need(await b.rpc('set_coffee_block',{p_member:users[0].id,p_enabled:true}),'block'),true);assert.equal(need(await a.rpc('can_join_coffee_voice',{p_topic:'room-chat',p_session:voiceA}),'voice-block'),false);assert.equal(need(await a.rpc('can_join_coffee_call',{p_id:call}),'call-block'),false);
 stage='deletion';const receipt=randomBytes(32).toString('hex');assert.equal(need(await a.rpc('begin_coffee_deletion',{p_secret:receipt}),'begin-delete'),true);assert.equal(need(await a.from('coffee_profiles').select('id').eq('id',users[0].id),'deleted-user-read').length,0);
 const result=await fetch(`${base}/functions/v1/delete-coffee-account`,{method:'POST',headers:{apikey:key,'content-type':'application/json'},body:JSON.stringify({receipt})});assert.equal(result.status,200);assert.equal((await result.json()).status,'complete');
 const retry=await fetch(`${base}/functions/v1/delete-coffee-account`,{method:'POST',headers:{apikey:key,'content-type':'application/json'},body:JSON.stringify({receipt})});assert.equal(retry.status,200);assert.equal((await retry.json()).status,'complete');
 console.log('PASS: isolated voice, messages, call consent, block revocation and account deletion');
} catch(e){console.error(JSON.stringify({stage:e.stage??stage,status:e.status??null,code:e.code??null,error:e.message}));process.exitCode=1} finally {await save()}
