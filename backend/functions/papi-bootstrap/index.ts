import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const reply = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json", "cache-control": "no-store" },
});

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply(405, { error: "Method not allowed" });
  const token = request.headers.get("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return reply(401, { error: "Authentication required" });
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key) return reply(503, { error: "Configuration unavailable" });
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) return reply(401, { error: "Authentication required" });
  return reply(200, { code: 0, message: "ok", data: {} });
});
