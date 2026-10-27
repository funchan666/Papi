// Draft only. Do not deploy or configure in App Store Connect until a durable
// processor, refund accounting and reconciliation have been completed.
import { Buffer } from "node:buffer";
import { X509Certificate } from "node:crypto";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@3.1.0";
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
  try {
    const root = await Deno.readTextFile(new URL("../verify-apple-purchase/AppleRootCA-G3.pem", import.meta.url));
    const environment = environmentName === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
    const verifier = new SignedDataVerifier([Buffer.from(new X509Certificate(root).raw)], true, environment, bundleID, appID);
    notification = await verifier.verifyAndDecodeNotification(payload);
  } catch { return reply(503); }
  if (!notification.notificationUUID || !uuid.test(notification.notificationUUID) ||
      !notification.notificationType || notification.notificationType.length > 100) return reply(422);

  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await service.rpc("queue_apple_notification", {
    p_id: notification.notificationUUID, p_environment: environmentName,
    p_type: notification.notificationType, p_payload: payload,
  });
  return reply(!error && data === true ? 200 : 503);
});
