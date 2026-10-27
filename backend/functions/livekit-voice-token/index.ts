// Draft only. Do not deploy or enable until blocking between room participants,
// participant removal, moderation, abuse limits and client lifecycle are ready.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { AccessToken } from "npm:livekit-server-sdk@2.19.2";
import { TrackSource } from "npm:@livekit/protocol@1.51.0";

const reply=(status:number,body:object)=>new Response(JSON.stringify(body),{
  status,headers:{"content-type":"application/json","cache-control":"no-store"},
});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
Deno.serve(async (request:Request) => {
  if (request.method!=="POST") return reply(405,{error:"Method not allowed"});
  const bearer=request.headers.get("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!bearer) return reply(401,{error:"Authentication required"});
  const dbURL=Deno.env.get("SUPABASE_URL"), publicKey=Deno.env.get("SUPABASE_ANON_KEY");
  const liveURL=Deno.env.get("LIVEKIT_URL"), apiKey=Deno.env.get("LIVEKIT_API_KEY"), apiSecret=Deno.env.get("LIVEKIT_API_SECRET");
  if (!dbURL || !publicKey || !liveURL || !apiKey || !apiSecret) return reply(503,{error:"Voice rooms are not configured"});
  try {
    const url=new URL(liveURL);
    if (url.protocol!=="wss:" || url.username || url.password || url.search || url.hash) return reply(503,{error:"Voice rooms are not configured"});
  } catch {return reply(503,{error:"Voice rooms are not configured"});}
  if (Number(request.headers.get("content-length") || 0)>2048) return reply(413,{error:"Request too large"});
  let topicID:unknown,sessionID:unknown;
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
    topicID=(body as Record<string,unknown>).topic_id;sessionID=(body as Record<string,unknown>).session_id;
  } catch {return reply(400,{error:"Invalid request"});}
  if (typeof topicID!=="string" || !/^room-[a-z]{1,30}$/.test(topicID) || typeof sessionID!=="string" || !uuid.test(sessionID)) return reply(400,{error:"Invalid request"});
  const client=createClient(dbURL,publicKey,{global:{headers:{Authorization:`Bearer ${bearer}`}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:authError}=await client.auth.getUser(bearer);
  if (authError || !identity.user) return reply(401,{error:"Authentication required"});
  try {
    const allowed=async () => {
      const {data,error}=await client.rpc("can_join_coffee_voice",{p_topic:topicID,p_session:sessionID});
      if (error) throw error;
      return data===true;
    };
    if (!await allowed()) return reply(403,{error:"Voice room unavailable"});
    const token=new AccessToken(apiKey,apiSecret,{identity:identity.user.id,ttl:120});
    token.addGrant({roomJoin:true,room:`papi-${topicID}`,canSubscribe:true,
      canPublishSources:[TrackSource.MICROPHONE],canPublishData:false,canUpdateOwnMetadata:false});
    const signed=await token.toJwt();
    if (!await allowed()) return reply(403,{error:"Voice room unavailable"});
    return reply(200,{server_url:liveURL,participant_token:signed});
  } catch {return reply(503,{error:"Voice room unavailable"});}
});
