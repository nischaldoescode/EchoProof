/**
 * Reconciles a user's subscription with Google Play.
 * RTDN is fast, but this check repairs missed or delayed notifications.
 */

import { createClient } from "@supabase/supabase-js";
import {
  getGoogleAccessToken,
  getSubscriptionV2,
  snapshotSubscription,
} from "../_shared/google_play.ts";
import {
  corsPreflight,
  rejectBadBrowserOrigin,
} from "../_shared/cors.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST" && req.method !== "OPTIONS") {
    return new Response("forbidden", { status: 403 });
  }
  if (req.method === "OPTIONS") return corsPreflight(req);

  const badOrigin = rejectBadBrowserOrigin(req);
  if (badOrigin) return badOrigin;

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) return errRes(401, "unauthorized");
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) return errRes(401, "unauthorized");

    const serviceClient = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const {
      data: { user },
      error: authError,
    } = await serviceClient.auth.getUser(jwt);
    if (authError || !user) return errRes(401, "unauthenticated");

    const { data: sub, error: subError } = await serviceClient
      .from("subscriptions")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();
    if (subError) throw subError;

    const { data: history, error: historyError } = await serviceClient
      .from("purchase_history")
      .select("purchase_token, product_id, plan_type, status, expires_time_ms, created_at")
      .eq("user_id", user.id)
      .neq("status", "declined")
      .not("purchase_token", "is", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (historyError) throw historyError;

    if (!history?.purchase_token) {
      return sub ? localStatus(sub) : ok({ is_pro: false, status: "no_subscription" });
    }

    const googleServiceAccount = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
    if (!googleServiceAccount) {
      console.error("check-subscription: missing GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
      return errRes(503, "subscription verification temporarily unavailable");
    }

    let playResource;
    try {
      const accessToken = await getGoogleAccessToken(googleServiceAccount);
      playResource = await getSubscriptionV2(accessToken, history.purchase_token);
    } catch (error) {
      // Do not revoke a paid user because Google or the network is temporarily
      // unavailable. The next app resume and RTDN will retry reconciliation.
      console.error("check-subscription: Google Play lookup failed:", error);
      return errRes(503, "subscription verification temporarily unavailable");
    }

    const snapshot = snapshotSubscription(playResource);
    const productId = snapshot.productId ?? history.product_id;
    const plan = productId?.includes("yearly")
      ? "pro_yearly"
      : productId?.includes("monthly")
      ? "pro_monthly"
      : history.plan_type;
    const expiresAt = snapshot.expiresAt?.toISOString() ?? null;
    const now = new Date().toISOString();

    const subscriptionUpdate = await serviceClient
      .from("subscriptions")
      .upsert({
        user_id: user.id,
        plan,
        status: snapshot.status,
        granted_by: "google_play",
        expires_at: expiresAt,
        updated_at: now,
      }, { onConflict: "user_id" });
    if (subscriptionUpdate.error) throw subscriptionUpdate.error;

    const publicUpdate = await serviceClient
      .from("users_public")
      .update(snapshot.isEntitled
        ? { is_pro: true, pro_expires_at: expiresAt, pro_plan: plan }
        : { is_pro: false, pro_expires_at: null, pro_plan: null })
      .eq("id", user.id);
    if (publicUpdate.error) throw publicUpdate.error;

    const historyUpdate = await serviceClient
      .from("purchase_history")
      .update({
        status: snapshot.status,
        expires_time_ms: snapshot.expiresTimeMs,
        updated_at: now,
      })
      .eq("purchase_token", history.purchase_token);
    if (historyUpdate.error) throw historyUpdate.error;

    return ok({
      is_pro: snapshot.isEntitled,
      status: snapshot.status,
      plan,
      expires_at: expiresAt,
    });
  } catch (error) {
    console.error("check-subscription error:", error);
    return errRes(500, "internal error");
  }
});

function localStatus(sub: Record<string, unknown>): Response {
  const activeStatuses = new Set(["active", "grace_period", "canceled", "cancelled"]);
  const expiresAt = typeof sub.expires_at === "string"
    ? new Date(sub.expires_at)
    : null;
  const isPro = activeStatuses.has(String(sub.status)) &&
    (!expiresAt || expiresAt.getTime() > Date.now());
  return ok({
    is_pro: isPro,
    status: isPro ? sub.status : "expired",
    plan: isPro ? sub.plan : null,
    expires_at: isPro ? sub.expires_at : null,
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function ok(data: Record<string, unknown>): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: {
      "Access-Control-Allow-Origin": "https://echoproof.online",
      "Vary": "Origin",
      "Content-Type": "application/json",
    },
  });
}

function errRes(status: number, message: string): Response {
  return new Response(JSON.stringify({ success: false, error: message }), {
    status,
    headers: {
      "Access-Control-Allow-Origin": "https://echoproof.online",
      "Vary": "Origin",
      "Content-Type": "application/json",
    },
  });
}
