import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const reply = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json", "cache-control": "no-store" },
});
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply(405, { error: "Method not allowed" });
  const token = request.headers.get("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return reply(401, { error: "Authentication required" });
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!url || !anon || !serviceKey || !groqKey) return reply(503, { error: "Coffee guide unavailable" });
  if (Number(request.headers.get("content-length") || 0) > 8192) return reply(413, { error: "Question too large" });

  let body: Record<string, unknown>;
  try {
    const data = await request.arrayBuffer();
    if (data.byteLength > 8192) return reply(413, { error: "Question too large" });
    const parsed: unknown = JSON.parse(new TextDecoder().decode(data));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Invalid input");
    body = parsed as Record<string, unknown>;
  } catch { return reply(400, { error: "Invalid input" }); }
  if (typeof body.request_id !== "string" || !uuid.test(body.request_id) ||
      body.consent !== true || typeof body.question !== "string") return reply(400, { error: "Invalid input" });
  const question = body.question.trim();
  if (!question || question.length > 1200) return reply(400, { error: "Invalid question" });

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: identity, error: authError } = await userClient.auth.getUser(token);
  if (authError || !identity.user) return reply(401, { error: "Authentication required" });
  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: reserved, error: quotaError } = await service.rpc("reserve_coffee_ai_request", {
    p_id: body.request_id, p_owner: identity.user.id,
  });
  if (quotaError) return reply(503, { error: "Coffee guide unavailable" });
  if (!reserved) return reply(429, { error: "Question limit reached" });

  try {
    const upstream = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { authorization: `Bearer ${groqKey}`, "content-type": "application/json" },
      body: JSON.stringify({
        model: "openai/gpt-oss-20b",
        messages: [
          { role: "system", content: "You are Papi's coffee guide. Answer the user's coffee and brewing questions clearly and helpfully in the language of the question, usually within 250 words. Do not claim to be a person. For health or safety concerns, avoid definitive medical advice." },
          { role: "user", content: question },
        ],
        max_completion_tokens: 2048,
        reasoning_effort: "low",
      }),
      signal: AbortSignal.timeout(25000),
    });
    if (upstream.status === 429) return reply(429, { error: "Coffee guide is busy" });
    if (!upstream.ok) return reply(503, { error: "Coffee guide unavailable" });
    const raw = await upstream.text();
    if (raw.length > 100000) return reply(502, { error: "Invalid response" });
    const result = JSON.parse(raw);
    const choice = result?.choices?.[0];
    const answer = choice?.message?.content;
    if (typeof answer !== "string" || !answer.trim() || answer.length > 12000 ||
        choice?.finish_reason !== "stop") return reply(502, { error: "Incomplete answer" });
    return reply(200, { answer: answer.trim() });
  } catch { return reply(503, { error: "Coffee guide unavailable" }); }
});
