// Draft only: deploy and enable checkout only after isolated and Apple sandbox validation.
// verifyReceipt is deprecated; this endpoint handles consumables without an API key.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply = (status: number, body: object) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply(405, { error: "Method not allowed" });
  const token = request.headers.get("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return reply(401, { error: "Authentication required" });
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const bundleID = Deno.env.get("APPLE_BUNDLE_ID");
  const environment = Deno.env.get("APPLE_RECEIPT_ENVIRONMENT");
  if (!url || !anonKey || !serviceKey || !bundleID || (environment !== "Production" && environment !== "Sandbox")) {
    return reply(503, { error: "Receipt verification is not configured" });
  }
  if (Number(request.headers.get("content-length") || 0) > 2800000) return reply(413, { error: "Request too large" });
  let body: Record<string, unknown>;
  try {
    const bytes = await request.arrayBuffer();
    if (bytes.byteLength > 2800000) return reply(413, { error: "Request too large" });
    const value: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (!value || typeof value !== "object" || Array.isArray(value)) return reply(400, { error: "Invalid request" });
    body = value as Record<string, unknown>;
  } catch { return reply(400, { error: "Invalid request" }); }
  const { order_id, transaction_id, receipt_data } = body;
  if (typeof order_id !== "string" || !uuid.test(order_id) ||
      typeof transaction_id !== "string" || !/^[0-9]{1,32}$/.test(transaction_id) ||
      typeof receipt_data !== "string" || receipt_data.length < 1 || receipt_data.length > 2667000 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(receipt_data)) return reply(400, { error: "Invalid request" });

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: identity, error: authError } = await userClient.auth.getUser(token);
  if (authError || !identity.user) return reply(401, { error: "Authentication required" });
  const { data: order, error: orderError } = await userClient.from("coffee_purchase_orders")
    .select("id,owner_id,product_id").eq("id", order_id).maybeSingle();
  if (orderError) return reply(503, { error: "Order unavailable; retry later" });
  if (!order || order.owner_id !== identity.user.id) return reply(404, { error: "Order unavailable" });

  // Environments are deliberately separate: never credit a sandbox transaction in production.
  const endpoint = environment === "Production"
    ? "https://buy.itunes.apple.com/verifyReceipt" : "https://sandbox.itunes.apple.com/verifyReceipt";
  let response: Record<string, unknown>;
  try {
    const apple = await fetch(endpoint, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ "receipt-data": receipt_data }), signal: AbortSignal.timeout(15000),
    });
    if (!apple.ok || Number(apple.headers.get("content-length") || 0) > 5000000) throw new Error("Apple unavailable");
    const raw = await apple.text();
    if (raw.length > 5000000) throw new Error("Apple response too large");
    const value: unknown = JSON.parse(raw);
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid Apple response");
    response = value as Record<string, unknown>;
  } catch { return reply(503, { error: "Apple verification unavailable; retry later" }); }
  if (response.status !== 0 || response.environment !== environment) return reply(422, { error: "Receipt unavailable for this environment" });
  const receipt = response.receipt as Record<string, unknown> | undefined;
  if (!receipt || receipt.bundle_id !== bundleID) return reply(422, { error: "Receipt does not match this app" });
  const rows = [receipt.in_app, response.latest_receipt_info]
    .filter(Array.isArray).flat() as Record<string, unknown>[];
  const matches = rows.filter((row) => row && typeof row === "object" && row.transaction_id === transaction_id);
  if (matches.length === 0 || matches.some((row) =>
      row.product_id !== order.product_id || row.quantity !== "1" ||
      (row.app_account_token != null && (typeof row.app_account_token !== "string" || row.app_account_token.toLowerCase() !== order.id.toLowerCase())) ||
      row.cancellation_date != null || row.cancellation_date_ms != null)) {
    return reply(422, { error: "Transaction cannot be matched to this order" });
  }

  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  // The signed Apple notification supplies account binding even if a consumable receipt omits it.
  // The RPC checks it and settles under one transaction lock; absent notification stays pending.
  const { data: balance, error } = await service.rpc("settle_notified_apple_charge", {
    p_order: order.id, p_owner: identity.user.id, p_product: order.product_id,
    p_transaction: transaction_id, p_environment: environment,
  });
  if (error) return reply(503, { error: "Settlement unavailable; retry later" });
  return reply(200, { balance });
});
