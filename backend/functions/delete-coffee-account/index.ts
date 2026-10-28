// This endpoint is inert until both the implementation readiness setting and
// database gate are enabled after end-to-end deletion verification.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const reply=(status:number,body:object)=>new Response(JSON.stringify(body),{
  status,headers:{"content-type":"application/json","cache-control":"no-store"},
});
Deno.serve(async (request:Request) => {
  if (request.method!=="POST") return reply(405,{error:"Method not allowed"});
  if (Number(request.headers.get("content-length") || 0)>2048) return reply(413,{error:"Request too large"});
  let secret:unknown;
  try {
    const reader=request.body?.getReader();
    if (!reader) return reply(400,{error:"Invalid request"});
    const chunks:Uint8Array[]=[];
    let size=0;
    while (true) {
      const {done,value}=await reader.read();
      if (done) break;
      size+=value.byteLength;
      if (size>2048) {await reader.cancel();return reply(413,{error:"Request too large"});}
      chunks.push(value);
    }
    const bytes=new Uint8Array(size);
    let offset=0;
    for (const chunk of chunks) {bytes.set(chunk,offset);offset+=chunk.byteLength;}
    const body:unknown=JSON.parse(new TextDecoder().decode(bytes));
    if (!body || typeof body!=="object" || Array.isArray(body)) return reply(400,{error:"Invalid request"});
    secret=(body as Record<string,unknown>).receipt;
  } catch {return reply(400,{error:"Invalid request"});}
  // A 256-bit random receipt is a secret capability, not a public request ID.
  if (typeof secret!=="string" || !/^[0-9a-f]{64}$/.test(secret)) return reply(400,{error:"Invalid request"});
  const url=Deno.env.get("SUPABASE_URL"), publicKey=Deno.env.get("SUPABASE_ANON_KEY"), serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publicKey || !serviceKey) return reply(503,{error:"Deletion unavailable"});
  if (Deno.env.get("PAPI_DELETION_IMPLEMENTATION_READY")!=="true") return reply(503,{error:"Deletion unavailable"});
  const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const lookup=async () => {
    const {data,error}=await service.rpc("coffee_deletion_work",{p_secret:secret});
    if (error) throw error;
    return data?.[0] as {owner_id:string|null;state:string}|undefined;
  };
  try {
    const {data:enabled,error:gateError}=await service.rpc("coffee_deletion_available");
    if (gateError || enabled!==true) return reply(503,{error:"Deletion unavailable"});
    let work=await lookup();
    if (!work) {
      const bearer=request.headers.get("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
      if (!bearer) return reply(401,{error:"Authentication required"});
      const user=createClient(url,publicKey,{global:{headers:{Authorization:`Bearer ${bearer}`}},auth:{persistSession:false,autoRefreshToken:false}});
      const {data:identity,error:authError}=await user.auth.getUser(bearer);
      if (authError || !identity.user) return reply(401,{error:"Authentication required"});
      const {data:started,error:startError}=await user.rpc("begin_coffee_deletion",{p_secret:secret});
      if (startError || started!==true) return reply(409,{error:"Deletion could not start; purchase reconciliation may be required"});
      work=await lookup();
      if (work?.state==="complete") return reply(200,{status:"complete"});
      if (!work || work.owner_id!==identity.user.id) return reply(503,{error:"Deletion needs attention"});
    }
    if (work.state==="complete") return reply(200,{status:"complete"});
    if (work.state!=="requested") return reply(503,{error:"Deletion needs attention"});
    if (typeof work.owner_id!=="string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(work.owner_id)) return reply(503,{error:"Deletion needs attention"});
    const ownerID=work.owner_id;
    const {data:sessionsCleared,error:sessionsError}=await service.rpc("coffee_deletion_sessions_cleared",{p_secret:secret});
    if (sessionsError) throw sessionsError;
    if (sessionsCleared!==true) return reply(202,{status:"pending"});
    for (let batch=0;batch<5;batch++) {
      const {data:files,error:listError}=await service.rpc("coffee_deletion_files",{p_secret:secret});
      if (listError) throw listError;
      if (!files?.length) break;
      const names=files.map((item:{name:string})=>item.name);
      if (names.some((name:string)=>typeof name!=="string" || !name.startsWith(ownerID+"/"))) throw new Error("Unexpected owned path");
      const {error:removeError}=await service.storage.from("coffee-media").remove(names);
      if (removeError) throw removeError;
      if (batch===4) return reply(202,{status:"pending"});
    }
    const {data:exists,error:existsError}=await service.rpc("coffee_deletion_user_exists",{p_secret:secret});
    if (existsError) throw existsError;
    if (exists===true) {
      const {error:deleteError}=await service.auth.admin.deleteUser(ownerID,false);
      if (deleteError) throw deleteError;
    }
    const {data:complete,error:finishError}=await service.rpc("complete_coffee_deletion",{p_secret:secret});
    if (finishError || complete!==true) return reply(202,{status:"pending"});
    return reply(200,{status:"complete"});
  } catch {return reply(503,{error:"Deletion needs attention; retry with the same receipt"});}
});
