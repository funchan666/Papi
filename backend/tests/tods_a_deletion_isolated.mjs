// Isolated test account only; no real data, no purchases and no device files.
import {createRequire} from 'node:module';
import {randomBytes} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const base='https://bezftktzpyuykuvnbilm.supabase.co',key=process.env.PAPI_ISOLATED_PUBLISHABLE_KEY;
if(!key?.startsWith('sb_publishable_'))throw new Error('Isolated key required');
const {createClient}=createRequire('/tmp/papi-isolated-supabase/package.json')('@supabase/supabase-js');
const c=createClient(base,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});let stage='sign-in';let id;
const need=(r,label)=>{if(r.error)throw Object.assign(new Error(label),{stage:label,status:r.error.status,code:r.error.code});return r.data};
try {
 const user=need(await c.auth.signInAnonymously(),'sign-in').user;id=user.id;
 await writeFile('/tmp/papi-isolated-supabase/tods-delete-current-ids.json',JSON.stringify({project:'bezftktzpyuykuvnbilm',users:[id]}),{mode:0o600});
 need(await c.from('coffee_profiles').insert({id,display_name:'Deletion fixture',biography:''}),'profile');
 stage='delete';const receipt=randomBytes(32).toString('hex');assert.equal(need(await c.rpc('begin_coffee_deletion',{p_secret:receipt}),'begin-delete'),true);
 assert.equal(need(await c.from('coffee_profiles').select('id').eq('id',id),'stale-profile').length,0);
 for(let attempt=0;attempt<3;attempt++) {
  const response=await fetch(`${base}/functions/v1/delete-coffee-account`,{method:'POST',headers:{apikey:key,'content-type':'application/json'},body:JSON.stringify({receipt})});
  const result=await response.json();if(response.status===200 && result.status==='complete'){console.log('PASS: isolated deletion, stale-session denial and completion');process.exit(0)}
  if(response.status!==202 || result.status!=='pending')throw new Error(`Unexpected deletion response ${response.status}`);
  await new Promise(resolve=>setTimeout(resolve,1000));
 }
 throw new Error('Deletion still pending after retries');
} catch(e){console.error(JSON.stringify({stage:e.stage??stage,status:e.status??null,code:e.code??null,error:e.message}));process.exitCode=1}
