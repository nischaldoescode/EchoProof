/**
 * Google Play Real-time Developer Notifications webhook.
 *
 * Pub/Sub authenticates the request with a Google-signed OIDC JWT. The
 * notification only signals that something changed; the Play API is queried
 * before any entitlement is changed.
 */

import { createClient } from "@supabase/supabase-js";
import {
  createRemoteJWKSet,
  jwtVerify,
  type JWTPayload,
} from "npm:jose@5.10.0";
import {
  GooglePlayApiError,
  getGoogleAccessToken,
  getSubscriptionV2,
  snapshotSubscription,
} from "../_shared/google_play.ts";
import { rejectBadBrowserOrigin } from "../_shared/cors.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const PLAY_PACKAGE_NAME = "com.echoproof.app";
const GOOGLE_OIDC_KEYS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/oauth2/v3/certs"),
);
const STALE_PROCESSING_AFTER_MS = 10 * 60 * 1000;

type EventRow = {
  message_id: string;
  status: string;
  received_at: string;
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST" && req.method !== "OPTIONS") {
    return new Response("forbidden", { status: 403 });
  }
  const badOrigin = rejectBadBrowserOrigin(req);
  if (badOrigin) return badOrigin;
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  let eventId: string | null = null;
  const serviceClient = createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  try {
    await verifyPubSubOidc(req);
    const body = await req.json() as {
      message?: {
        data?: string;
        messageId?: string;
        message_id?: string;
      };
    };
    const message = body.message;
    const messageData = message?.data;
    eventId = message?.messageId ?? message?.message_id ?? null;
    if (!eventId || !messageData) return new Response("invalid Pub/Sub message", { status: 400 });

    const decoded = new TextDecoder().decode(
      Uint8Array.from(atob(messageData), (char) => char.charCodeAt(0)),
    );
    const notification = JSON.parse(decoded) as {
      packageName?: string;
      subscriptionNotification?: {
        notificationType?: number;
        purchaseToken?: string;
        subscriptionId?: string;
      };
      voidedPurchaseNotification?: {
        purchaseToken?: string;
        orderId?: string;
        productType?: number;
        refundType?: number;
      };
      testNotification?: unknown;
    };
    if (notification.packageName !== PLAY_PACKAGE_NAME) {
      return new Response("package not recognized", { status: 400 });
    }

    const subscriptionNotification = notification.subscriptionNotification;
    const voidedPurchaseNotification = notification.voidedPurchaseNotification;
    const notificationType = subscriptionNotification?.notificationType ?? null;
    const purchaseToken = subscriptionNotification?.purchaseToken ??
      voidedPurchaseNotification?.purchaseToken ?? null;
    const claim = await claimEvent(serviceClient, {
      message_id: eventId,
      package_name: PLAY_PACKAGE_NAME,
      notification_type: notificationType,
      purchase_token: purchaseToken,
      status: "processing",
    });
    if (!claim) return accepted();

    if (voidedPurchaseNotification) {
      await processVoidedPurchase(
        serviceClient,
        eventId,
        purchaseToken,
        voidedPurchaseNotification.orderId ?? null,
      );
      return accepted();
    }

    if (!subscriptionNotification || !purchaseToken) {
      console.log(`rtdn-handler: accepted test/non-subscription message event=${eventId}`);
      await completeEvent(serviceClient, eventId, "processed");
      return accepted();
    }

    const { data: historyRow, error: historyError } = await serviceClient
      .from("purchase_history")
      .select("user_id, plan_type, status")
      .eq("purchase_token", purchaseToken)
      .maybeSingle();
    if (historyError) throw historyError;

    // A PURCHASED event can arrive before the app has submitted the token.
    // There is no user id in RTDN, so the client verification request is the
    // only safe way to associate that token with an account.
    if (!historyRow) {
      console.warn("rtdn-handler: token is not associated with a user yet");
      await completeEvent(serviceClient, eventId, "unmatched");
      return accepted();
    }

    const googleServiceAccount = requiredEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
    const accessToken = await getGoogleAccessToken(googleServiceAccount);
    let playResource;
    try {
      playResource = await getSubscriptionV2(accessToken, purchaseToken);
    } catch (error) {
      // A revoked token may disappear from the API. The RTDN itself is still
      // authoritative for immediate revocation in that one case.
      if (
        error instanceof GooglePlayApiError &&
        error.status === 404 &&
        notificationType === 12
      ) {
        await applyEntitlement(serviceClient, eventId, purchaseToken, historyRow, {
          status: "refunded",
          expiresAt: null,
          expiresTimeMs: null,
          isEntitled: false,
        });
        return accepted();
      }
      throw error;
    }

    const snapshot = snapshotSubscription(
      playResource,
      subscriptionNotification.subscriptionId,
    );
    if (
      snapshot.productId &&
      subscriptionNotification.subscriptionId &&
      snapshot.productId !== subscriptionNotification.subscriptionId
    ) {
      throw new Error("RTDN product does not match subscriptionsv2 response");
    }

    await applyEntitlement(serviceClient, eventId, purchaseToken, historyRow, snapshot);
    return accepted();
  } catch (error) {
    if (error instanceof HttpError) {
      return new Response(error.message, { status: error.status, headers: CORS });
    }
    console.error("rtdn-handler error:", error);
    if (eventId) {
      await serviceClient
        .from("billing_rtdn_events")
        .update({
          status: "failed",
          error_message: error instanceof Error ? error.message.slice(0, 1000) : "unknown error",
        })
        .eq("message_id", eventId)
        .then(() => {});
    }
    // A 5xx tells Pub/Sub to retry transient failures.
    return new Response("temporary processing failure", { status: 500, headers: CORS });
  }
});

async function verifyPubSubOidc(req: Request): Promise<void> {
  const authorization = req.headers.get("authorization");
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new HttpError(401, "missing Pub/Sub OIDC token");

  const audience = requiredEnv("PUBSUB_PUSH_AUDIENCE");
  const expectedEmail = requiredEnv("PUBSUB_PUSH_SERVICE_ACCOUNT_EMAIL");
  let payload: JWTPayload;
  try {
    ({ payload } = await jwtVerify(match[1], GOOGLE_OIDC_KEYS, {
      issuer: ["https://accounts.google.com", "accounts.google.com"],
      audience,
    }));
  } catch {
    throw new HttpError(401, "invalid Pub/Sub OIDC token");
  }
  if (
    payload.email !== expectedEmail ||
    (payload.email_verified !== true && payload.email_verified !== "true")
  ) {
    throw new HttpError(401, "unexpected Pub/Sub service account");
  }
}

async function claimEvent(
  client: ReturnType<typeof createClient>,
  row: {
    message_id: string;
    package_name: string;
    notification_type: number | null;
    purchase_token: string | null;
    status: string;
  },
): Promise<boolean> {
  const { data: inserted, error: insertError } = await client
    .from("billing_rtdn_events")
    .insert(row, { onConflict: "message_id", ignoreDuplicates: true })
    .select("message_id, status, received_at")
    .maybeSingle();
  if (insertError) throw insertError;
  if (inserted) return true;

  const { data: existing, error: lookupError } = await client
    .from("billing_rtdn_events")
    .select("message_id, status, received_at")
    .eq("message_id", row.message_id)
    .maybeSingle() as { data: EventRow | null; error: unknown };
  if (lookupError) throw lookupError;
  if (!existing || existing.status === "processed" || existing.status === "unmatched") {
    return false;
  }

  const age = Date.now() - Date.parse(existing.received_at);
  if (existing.status === "processing" && age < STALE_PROCESSING_AFTER_MS) {
    return false;
  }

  const { error: reclaimError } = await client
    .from("billing_rtdn_events")
    .update({ status: "processing", received_at: new Date().toISOString(), error_message: null })
    .eq("message_id", row.message_id);
  if (reclaimError) throw reclaimError;
  return true;
}

async function completeEvent(
  client: ReturnType<typeof createClient>,
  eventId: string,
  status: string,
): Promise<void> {
  const { error } = await client
    .from("billing_rtdn_events")
    .update({ status, processed_at: new Date().toISOString(), error_message: null })
    .eq("message_id", eventId);
  if (error) throw error;
}

async function processVoidedPurchase(
  client: ReturnType<typeof createClient>,
  eventId: string,
  purchaseToken: string | null,
  orderId: string | null,
): Promise<void> {
  let historyRow: { user_id: string; plan_type: string } | null = null;

  if (purchaseToken) {
    const { data, error } = await client
      .from("purchase_history")
      .select("user_id, plan_type")
      .eq("purchase_token", purchaseToken)
      .maybeSingle();
    if (error) throw error;
    historyRow = data;
  }

  if (!historyRow && orderId) {
    const { data, error } = await client
      .from("purchase_history")
      .select("user_id, plan_type, purchase_token")
      .eq("order_id", orderId)
      .maybeSingle();
    if (error) throw error;
    historyRow = data;
    purchaseToken = data?.purchase_token ?? purchaseToken;
  }

  if (!historyRow || !purchaseToken) {
    console.warn(`rtdn-handler: unmatched voided purchase order=${orderId ?? "unknown"}`);
    await completeEvent(client, eventId, "unmatched");
    return;
  }

  const now = new Date().toISOString();
  const historyUpdate = await client
    .from("purchase_history")
    .update({
      status: "refunded",
      error_message: "Voided by Google Play",
      acknowledged: false,
      updated_at: now,
    })
    .eq("purchase_token", purchaseToken);
  if (historyUpdate.error) throw historyUpdate.error;

  // Do not revoke a user who still has another valid purchase token.
  const { data: otherPurchases, error: otherError } = await client
    .from("purchase_history")
    .select("status, expires_time_ms")
    .eq("user_id", historyRow.user_id)
    .neq("purchase_token", purchaseToken);
  if (otherError) throw otherError;
  const nowMs = Date.now();
  const hasOtherEntitlement = (otherPurchases ?? []).some((row) =>
    ["active", "acknowledged", "grace_period", "canceled"].includes(row.status) &&
    Number(row.expires_time_ms ?? 0) > nowMs
  );

  if (!hasOtherEntitlement) {
    const subscriptionUpdate = await client
      .from("subscriptions")
      .update({
        status: "expired",
        expires_at: null,
        updated_at: now,
      })
      .eq("user_id", historyRow.user_id);
    if (subscriptionUpdate.error) throw subscriptionUpdate.error;

    const publicUpdate = await client
      .from("users_public")
      .update({ is_pro: false, pro_expires_at: null, pro_plan: null })
      .eq("id", historyRow.user_id);
    if (publicUpdate.error) throw publicUpdate.error;
    await sendStateNotification(client, historyRow.user_id, "refunded");
  }

  await completeEvent(client, eventId, "processed");
}

async function applyEntitlement(
  client: ReturnType<typeof createClient>,
  eventId: string,
  purchaseToken: string,
  historyRow: { user_id: string; plan_type: string; status: string },
  snapshot: {
    status: string;
    expiresAt: Date | null;
    expiresTimeMs: number | null;
    isEntitled: boolean;
  },
): Promise<void> {
  const now = new Date().toISOString();
  const { data: previous, error: previousError } = await client
    .from("subscriptions")
    .select("status")
    .eq("user_id", historyRow.user_id)
    .maybeSingle();
  if (previousError) throw previousError;

  const status = snapshot.status === "refunded" ? "expired" : snapshot.status;
  const historyStatus = snapshot.status === "refunded" ? "refunded" : status;
  const subscriptionUpdate = await client
    .from("subscriptions")
    .upsert({
      user_id: historyRow.user_id,
      plan: historyRow.plan_type,
      status,
      granted_by: "google_play",
      expires_at: snapshot.expiresAt?.toISOString() ?? null,
      updated_at: now,
    }, { onConflict: "user_id" });
  if (subscriptionUpdate.error) throw subscriptionUpdate.error;

  const publicUpdate = await client
    .from("users_public")
    .update(snapshot.isEntitled
      ? {
        is_pro: true,
        pro_expires_at: snapshot.expiresAt?.toISOString() ?? null,
        pro_plan: historyRow.plan_type,
      }
      : { is_pro: false, pro_expires_at: null, pro_plan: null })
    .eq("id", historyRow.user_id);
  if (publicUpdate.error) throw publicUpdate.error;

  const historyUpdate = await client
    .from("purchase_history")
    .update({
      status: historyStatus,
      expires_time_ms: snapshot.expiresTimeMs,
      acknowledged: true,
      verified_at: now,
      updated_at: now,
    })
    .eq("purchase_token", purchaseToken);
  if (historyUpdate.error) throw historyUpdate.error;

  if (previous?.status !== status) {
    await sendStateNotification(client, historyRow.user_id, snapshot.status);
  }
  await completeEvent(client, eventId, "processed");
}

async function sendStateNotification(
  client: ReturnType<typeof createClient>,
  userId: string,
  status: string,
): Promise<void> {
  const messages: Record<string, { title: string; body: string }> = {
    canceled: {
      title: "Subscription canceled",
      body: "Your Pro access remains available until the current billing period ends.",
    },
    grace_period: {
      title: "Payment issue - action needed",
      body: "Please update your payment method to keep Pro access.",
    },
    on_hold: {
      title: "Pro access paused",
      body: "Your subscription is on hold until the payment issue is resolved.",
    },
    expired: {
      title: "Pro subscription expired",
      body: "Renew your subscription to keep Pro features.",
    },
    refunded: {
      title: "Subscription revoked",
      body: "Your Google Play subscription was revoked. Contact support if this is unexpected.",
    },
  };
  const message = messages[status];
  if (!message) return;
  await client.functions.invoke("send-notification", {
    body: {
      user_id: userId,
      title: message.title,
      body: message.body,
      route: "/subscribe",
    },
  }).catch(() => {});
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function accepted(): Response {
  return new Response(null, { status: 204, headers: CORS });
}

class HttpError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}
