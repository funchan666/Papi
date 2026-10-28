// Deployed behind single-use scheduler tickets. The scheduler is inactive until
// removal, revocation and retries are verified.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { RoomServiceClient } from "npm:livekit-server-sdk@2.19.2";

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply=(status:number,body:object)=>new Response(JSON.stringify(body),{
  status,headers:{"content-type":"application/json","cache-control":"no-store"},
});

Deno.serve(async (request:Request) => {
  if (request.method!=="POST") return reply(405,{error:"Method not allowed"});
  const provided=request.headers.get("x-papi-cleanup-ticket");
  const url=Deno.env.get("SUPABASE_URL"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const liveURL=Deno.env.get("LIVEKIT_URL"),apiKey=Deno.env.get("LIVEKIT_API_KEY"),apiSecret=Deno.env.get("LIVEKIT_API_SECRET");
  if (!url || !serviceKey || !liveURL || !apiKey || !apiSecret)
    return reply(503,{error:"Call cleanup unavailable"});
  if (!provided || !/^[0-9a-f]{64}$/.test(provided)) return reply(401,{error:"Unauthorized"});
  let host:string;
  try {
    const parsed=new URL(liveURL);
    if (parsed.protocol!=="wss:" || parsed.username || parsed.password || parsed.search || parsed.hash) throw new Error("Invalid host");
    parsed.protocol="https:";host=parsed.toString();
  } catch {return reply(503,{error:"Call cleanup unavailable"});}
  const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  // Single-use scheduler capability; neither database nor network queues hold
  // the long-lived service-role or LiveKit credentials.
  const {data:authorized,error:ticketError}=await service.rpc("consume_coffee_cleanup_ticket",{p_ticket:provided});
  if (ticketError || authorized!==true) return reply(401,{error:"Unauthorized"});
  const rooms=new RoomServiceClient(host,apiKey,apiSecret);
  try {
    const {data:jobs,error}=await service.rpc("pending_call_revocations");
    if (error || !Array.isArray(jobs)) throw error ?? new Error("Invalid queue");
    let completed=0,failed=0;
    for (const job of jobs) {
      try {
        if (!job || !uuid.test(job.call_id) || !uuid.test(job.caller_id) || !uuid.test(job.recipient_id)) throw new Error("Invalid job");
        const room=`papi-call-${job.call_id.toLowerCase()}`;
        // A one-second future cutoff includes tokens minted in the current second.
        const cutoff=BigInt(Math.floor(Date.now()/1000)+1);
        // Attempt both even if one removal fails, and acknowledge only when
        // both succeed so the worker can retry a partial failure.
        const results=await Promise.allSettled([
          rooms.removeParticipant(room,job.caller_id,{revokeTokenTs:cutoff}),
          rooms.removeParticipant(room,job.recipient_id,{revokeTokenTs:cutoff}),
        ]);
        if (results.some(result=>result.status==="rejected")) throw new Error("Participant cleanup failed");
        const {data:done,error:finishError}=await service.rpc("complete_call_revocation",{p_call:job.call_id});
        if (finishError || done!==true) throw finishError ?? new Error("Queue update failed");
        completed++;
      } catch {failed++;}
    }
    const {data:voiceJobs,error:voiceError}=await service.rpc("pending_voice_revocations");
    if (voiceError || !Array.isArray(voiceJobs)) throw voiceError ?? new Error("Invalid voice queue");
    let voiceCompleted=0;
    for (const job of voiceJobs) {
      try {
        if (!job || typeof job.topic_id!=="string" || !/^room-[a-z]{1,30}$/.test(job.topic_id) ||
            typeof job.session_id!=="string" || !uuid.test(job.session_id) || typeof job.owner_id!=="string" || !uuid.test(job.owner_id)) throw new Error("Invalid voice job");
        const cutoff=BigInt(Math.floor(Date.now()/1000)+1);
        const participantID=`${job.owner_id.toLowerCase()}:${job.session_id.toLowerCase()}`;
        await rooms.removeParticipant(`papi-${job.topic_id}`,participantID,{revokeTokenTs:cutoff});
        const {data:done,error:finishError}=await service.rpc("complete_voice_revocation",{p_session:job.session_id});
        if (finishError || done!==true) throw finishError ?? new Error("Voice queue update failed");
        voiceCompleted++;
      } catch {failed++;}
    }
    return reply(failed ? 503 : 200,{completed,voice_completed:voiceCompleted,failed,more:jobs.length===20 || voiceJobs.length===20});
  } catch {return reply(503,{error:"Call cleanup needs retry"});}
});
