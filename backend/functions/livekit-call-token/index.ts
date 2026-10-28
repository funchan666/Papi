// Deployed with the call runtime disabled. Do not enable calls until session
// termination, participant removal, client lifecycle and blocks are verified.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { AccessToken } from "npm:livekit-server-sdk@2.19.2";
import { TrackSource } from "npm:@livekit/protocol@1.51.0";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply = (status:number, body:object) => new Response(JSON.stringify(body), {
  status, headers: { "content-type":"application/json", "cache-control":"no-store" },
});

Deno.serve(async (request:Request) => {
  if (request.method!=="POST") return reply(405,{error:"Method not allowed"});
  const bearer=request.headers.get("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!bearer) return reply(401,{error:"Authentication required"});
  const dbURL=Deno.env.get("SUPABASE_URL"), publicKey=Deno.env.get("SUPABASE_ANON_KEY");
  const liveURL=Deno.env.get("LIVEKIT_URL"), apiKey=Deno.env.get("LIVEKIT_API_KEY"), apiSecret=Deno.env.get("LIVEKIT_API_SECRET");
  if (!dbURL || !publicKey || !liveURL || !apiKey || !apiSecret) return reply(503,{error:"Calling is not configured"});
  try {
    const parsed=new URL(liveURL);
    if (parsed.protocol!=="wss:" || parsed.username || parsed.password || parsed.search || parsed.hash) return reply(503,{error:"Calling is not configured"});
  } catch {return reply(503,{error:"Calling is not configured"});}
  if (Number(request.headers.get("content-length") || 0)>2048) return reply(413,{error:"Request too large"});
  let callID:unknown;
  try {
    const reader=request.body?.getReader();
    if (!reader) return reply(400,{error:"Invalid request"});
    const chunks:Uint8Array[]=[];let size=0;
    while (true) {
      const {done,value}=await reader.read();if (done) break;
      size+=value.byteLength;
      if (size>2048) {await reader.cancel();return reply(413,{error:"Request too large"});}
      chunks.push(value);
    }
    const bytes=new Uint8Array(size);let offset=0;
    for (const chunk of chunks) {bytes.set(chunk,offset);offset+=chunk.byteLength;}
    const body:unknown=JSON.parse(new TextDecoder().decode(bytes));
    if (!body || typeof body!=="object" || Array.isArray(body)) return reply(400,{error:"Invalid request"});
    callID=(body as Record<string,unknown>).call_id;
  } catch {return reply(400,{error:"Invalid request"});}
  if (typeof callID!=="string" || !uuid.test(callID)) return reply(400,{error:"Invalid request"});
  try {
    const client=createClient(dbURL,publicKey,{
      global:{headers:{Authorization:`Bearer ${bearer}`}},
      auth:{persistSession:false,autoRefreshToken:false},
    });
    const {data:identity,error:authError}=await client.auth.getUser(bearer);
    if (authError) return [400,401,403].includes(authError.status ?? 0)
      ? reply(401,{error:"Authentication required"}) : reply(503,{error:"Call unavailable; retry later"});
    if (!identity.user) return reply(401,{error:"Authentication required"});
    const authorized=async () => {
      const {data,error}=await client.rpc("can_join_coffee_call",{p_id:callID});
      if (error) throw error;
      return data===true;
    };
    if (!await authorized()) return reply(403,{error:"Call unavailable"});
    const {data:reserved,error:reserveError}=await client.rpc("reserve_coffee_call_token",{p_id:callID});
    if (reserveError) throw reserveError;
    if (reserved!==true) return reply(429,{error:"Call unavailable; retry later"});
    const token=new AccessToken(apiKey,apiSecret,{identity:identity.user.id,ttl:120});
    token.addGrant({roomJoin:true,room:`papi-call-${callID.toLowerCase()}`,canSubscribe:true,
      canPublishSources:[TrackSource.MICROPHONE,TrackSource.CAMERA],canPublishData:false,canUpdateOwnMetadata:false});
    const signed=await token.toJwt();
    if (!await authorized()) return reply(403,{error:"Call unavailable"});
    return reply(200,{server_url:liveURL,participant_token:signed});
  } catch {return reply(503,{error:"Call unavailable; retry later"});}
});
