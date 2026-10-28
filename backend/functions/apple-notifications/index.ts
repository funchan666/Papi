// Draft only. Do not deploy or configure in App Store Connect until a durable
// processor, refund accounting and reconciliation have been completed.
import { Buffer } from "node:buffer";
import { X509Certificate } from "node:crypto";
import { Environment, SignedDataVerifier, Type } from "npm:@apple/app-store-server-library@3.1.0";
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply = (status: number) => new Response(null, { status, headers: { "cache-control": "no-store" } });

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply(405);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const bundleID = Deno.env.get("APPLE_BUNDLE_ID");
  const environmentName = Deno.env.get("APPLE_ENVIRONMENT");
  const appIDText = Deno.env.get("APPLE_APP_ID");
  const appID = appIDText && /^[1-9][0-9]*$/.test(appIDText) ? Number(appIDText) : undefined;
  if (!url || !serviceKey || !bundleID ||
      (environmentName !== "Sandbox" && environmentName !== "Production") ||
      (environmentName === "Production" && (!appID || !Number.isSafeInteger(appID)))) return reply(503);
  if (Number(request.headers.get("content-length") || 0) > 140000) return reply(413);

  let payload: unknown;
  try {
    const bytes = await request.arrayBuffer();
    if (bytes.byteLength > 140000) return reply(413);
    const body: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (!body || typeof body !== "object" || Array.isArray(body)) return reply(400);
    payload = (body as Record<string, unknown>).signedPayload;
  } catch { return reply(400); }
  if (typeof payload !== "string" || !payload || payload.length > 131072) return reply(400);

  let notification;
  let verifiedTransaction;
  try {
    const root = await Deno.readTextFile(new URL("../verify-apple-purchase/AppleRootCA-G3.pem", import.meta.url));
    const environment = environmentName === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
    const verifier = new SignedDataVerifier([Buffer.from(new X509Certificate(root).raw)], true, environment, bundleID, appID);
    notification = await verifier.verifyAndDecodeNotification(payload);
    if (["ONE_TIME_CHARGE", "REFUND", "REVOKE", "REFUND_REVERSED"].includes(notification.notificationType ?? "")) {
      if (!notification.data?.signedTransactionInfo) return reply(503);
      verifiedTransaction = await verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo);
    }
  } catch { return reply(503); }
  if (!notification.notificationUUID || !uuid.test(notification.notificationUUID) ||
      !notification.notificationType || notification.notificationType.length > 100) return reply(422);

  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await service.rpc("queue_apple_notification", {
    p_id: notification.notificationUUID, p_environment: environmentName,
    p_type: notification.notificationType, p_payload: payload,
  });
  if (error || data !== true) return reply(503);
  if (verifiedTransaction) {
    if (verifiedTransaction.type !== Type.CONSUMABLE) return reply(200);
    if (!verifiedTransaction.transactionId || !/^[0-9]{1,32}$/.test(verifiedTransaction.transactionId) ||
        !verifiedTransaction.appAccountToken || !uuid.test(verifiedTransaction.appAccountToken) ||
        !verifiedTransaction.productId || verifiedTransaction.quantity !== 1 ||
        (notification.notificationType === "ONE_TIME_CHARGE" && verifiedTransaction.revocationDate != null)) return reply(503);
    const recorded = await service.rpc("record_verified_apple_notification", {
      p_id: notification.notificationUUID, p_type: notification.notificationType,
      p_transaction: verifiedTransaction.transactionId, p_order: verifiedTransaction.appAccountToken,
      p_product: verifiedTransaction.productId, p_environment: environmentName,
    });
    if (recorded.error || recorded.data !== true) return reply(503);
  }
  // Keep non-purchase events retryable until their accounting processor exists.
  if (notification.notificationType !== "ONE_TIME_CHARGE") return reply(503);
  return reply(200);
});
