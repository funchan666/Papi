import { Buffer } from "node:buffer";
import { X509Certificate } from "node:crypto";
import { Environment, SignedDataVerifier, Type } from "npm:@apple/app-store-server-library@3.1.0";
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const response = (status: number, body: object) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { error: "Method not allowed" });
  const token = request.headers.get("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return response(401, { error: "Authentication required" });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const bundleID = Deno.env.get("APPLE_BUNDLE_ID");
  const configuredEnvironment = Deno.env.get("APPLE_ENVIRONMENT");
  const appIDText = Deno.env.get("APPLE_APP_ID");
  const appID = appIDText && /^[1-9][0-9]*$/.test(appIDText) ? Number(appIDText) : undefined;
  if (!url || !anonKey || !serviceKey || !bundleID ||
      (configuredEnvironment !== "Sandbox" && configuredEnvironment !== "Production") ||
      (configuredEnvironment === "Production" && (!appID || !Number.isSafeInteger(appID)))) {
    return response(503, { error: "Purchase verification is not configured" });
  }

  // Set the JWT explicitly for each request; never give a user the service key.
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: identity, error: authError } = await userClient.auth.getUser(token);
  if (authError || !identity.user) return response(401, { error: "Authentication required" });

  if (Number(request.headers.get("content-length") || 0) > 32768) return response(413, { error: "Request too large" });
  let input: unknown;
  try {
    const bytes = await request.arrayBuffer();
    if (bytes.byteLength > 32768) return response(413, { error: "Request too large" });
    input = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return response(400, { error: "Invalid request" });
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) return response(400, { error: "Invalid request" });
  const { order_id, signed_transaction } = input as Record<string, unknown>;
  if (typeof order_id !== "string" || !uuid.test(order_id) ||
      typeof signed_transaction !== "string" || signed_transaction.length > 30000 || !signed_transaction) {
    return response(400, { error: "Invalid request" });
  }

  const { data: order, error: orderError } = await userClient.from("coffee_purchase_orders")
    .select("id,owner_id,product_id").eq("id", order_id).maybeSingle();
  if (orderError) return response(503, { error: "Order unavailable; retry later" });
  if (!order || order.owner_id !== identity.user.id) return response(404, { error: "Order unavailable" });

  let transaction;
  try {
    const root = await Deno.readTextFile(new URL("./AppleRootCA-G3.pem", import.meta.url));
    const rootDER = Buffer.from(new X509Certificate(root).raw);
    const environment = configuredEnvironment === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
    const verifier = new SignedDataVerifier([rootDER], true, environment, bundleID, appID);
    transaction = await verifier.verifyAndDecodeTransaction(signed_transaction);
  } catch {
    // Certificate checks can fail temporarily; leave the transaction unfinished for retry.
    return response(503, { error: "Apple verification unavailable or invalid" });
  }

  if (!transaction.transactionId || !/^[0-9]{1,32}$/.test(transaction.transactionId) ||
      transaction.productId !== order.product_id || transaction.type !== Type.CONSUMABLE ||
      transaction.quantity !== 1 || transaction.revocationDate != null ||
      transaction.appAccountToken?.toLowerCase() !== order.id.toLowerCase()) {
    return response(422, { error: "Transaction does not match this order" });
  }

  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: balance, error: settlementError } = await service.rpc("settle_verified_apple_order", {
    p_order: order.id, p_owner: identity.user.id, p_product: order.product_id,
    p_transaction: transaction.transactionId, p_environment: configuredEnvironment,
  });
  if (settlementError) return response(503, { error: "Settlement unavailable; retry later" });
  return response(200, { balance });
});
