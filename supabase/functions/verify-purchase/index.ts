/**
 * Verifies a Google Play purchase server-side and grants the entitlement.
 * The client never decides whether a purchase is active or how long it lasts.
 */

import { createClient } from "@supabase/supabase-js";
import {
  acknowledgeSubscription,
  getGoogleAccessToken,
  getSubscriptionV2,
  snapshotSubscription,
} from "../_shared/google_play.ts";
import {
  corsPreflight,
  rejectBadBrowserOrigin,
} from "../_shared/cors.ts";

const VALID_PRODUCT_IDS = new Set([
  "echoproof_pro_monthly",
  "echoproof_pro_yearly",
]);

type PurchaseBody = {
  purchase_token?: string;
  product_id?: string;
  order_id?: string | null;
  purchase_time_ms?: number;
  obfuscated_account_id?: string;
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST" && req.method !== "OPTIONS") {
    return new Response("forbidden", { status: 403 });
  }
  if (req.method === "OPTIONS") return corsPreflight(req);

  const badOrigin = rejectBadBrowserOrigin(req);
  if (badOrigin) return badOrigin;

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) return errRes(401, "missing authorization");

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const googleServiceAccount = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
    if (!googleServiceAccount) {
      console.error("verify-purchase: missing GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
      return errRes(500, "server misconfigured - contact support");
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const serviceClient = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();
    if (authError || !user) return errRes(401, "unauthenticated");

    let body: PurchaseBody;
    try {
      body = await req.json() as PurchaseBody;
    } catch {
      return errRes(400, "invalid json");
    }

    const purchaseToken = body.purchase_token?.trim();
    const productId = body.product_id?.trim();
    const clientOrderId = body.order_id?.trim() || null;
    const purchaseTimeMs = body.purchase_time_ms;
    if (!purchaseToken || !productId) {
      return errRes(400, "missing purchase token or product id");
    }
    if (!VALID_PRODUCT_IDS.has(productId)) {
      return errRes(400, "invalid product id");
    }
    if (purchaseTimeMs !== undefined &&
        (!Number.isSafeInteger(purchaseTimeMs) || purchaseTimeMs <= 0)) {
      return errRes(400, "invalid purchase time");
    }

    // A token is globally unique. Never allow it to move between accounts.
    const { data: existingToken, error: tokenLookupError } = await serviceClient
      .from("purchase_history")
      .select("id, user_id")
      .eq("purchase_token", purchaseToken)
      .maybeSingle();
    if (tokenLookupError) throw tokenLookupError;
    if (existingToken && existingToken.user_id !== user.id) {
      return errRes(403, "purchase not associated with this account");
    }

    if (clientOrderId) {
      const { data: existingOrder, error: orderLookupError } = await serviceClient
        .from("purchase_history")
        .select("id, user_id, purchase_token")
        .eq("order_id", clientOrderId)
        .maybeSingle();
      if (orderLookupError) throw orderLookupError;
      if (existingOrder && existingOrder.user_id !== user.id) {
        return errRes(403, "purchase not associated with this account");
      }
      if (existingOrder && existingOrder.purchase_token !== purchaseToken) {
        return errRes(409, "order id is already associated with another purchase");
      }
    }

    const accessToken = await getGoogleAccessToken(googleServiceAccount);
    const playResource = await getSubscriptionV2(accessToken, purchaseToken);
    const snapshot = snapshotSubscription(playResource, productId);

    if (snapshot.productId && snapshot.productId !== productId) {
      return errRes(400, "purchase product does not match the requested product");
    }
    if (
      body.obfuscated_account_id &&
      snapshot.obfuscatedAccountId &&
      body.obfuscated_account_id !== snapshot.obfuscatedAccountId
    ) {
      console.error("verify-purchase: obfuscated account id mismatch");
      return errRes(403, "purchase is not associated with this account");
    }

    if (!snapshot.isEntitled) {
      if (snapshot.status === "pending") {
        return ok({
          success: false,
          pending: true,
          status: snapshot.status,
        });
      }
      return errRes(409, `Google Play subscription is ${snapshot.status}`);
    }
    if (snapshot.expiresTimeMs === null) {
      return errRes(502, "Google Play returned no subscription expiry");
    }
    if (!snapshot.latestOrderId && !clientOrderId) {
      return errRes(409, "Google Play purchase is not complete");
    }

    if (snapshot.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED") {
      await acknowledgeSubscription(accessToken, productId, purchaseToken);
    }

    const planType = productId.includes("yearly") ? "pro_yearly" : "pro_monthly";
    const serverOrderId = snapshot.latestOrderId ?? clientOrderId!;
    const serverPurchaseTimeMs = snapshot.purchaseTimeMs ?? purchaseTimeMs ?? Date.now();
    const verifiedAt = new Date().toISOString();
    const { data: currentSub, error: currentSubError } = await serviceClient
      .from("subscriptions")
      .select("expires_at")
      .eq("user_id", user.id)
      .maybeSingle();
    if (currentSubError) throw currentSubError;

    // A late restore event must never shorten a newer entitlement.
    const currentExpiryMs = currentSub?.expires_at
      ? Date.parse(currentSub.expires_at as string)
      : NaN;
    const effectiveExpiresTimeMs = Number.isFinite(currentExpiryMs) &&
        currentExpiryMs > snapshot.expiresTimeMs
      ? currentExpiryMs
      : snapshot.expiresTimeMs;
    const expiresAt = new Date(effectiveExpiresTimeMs).toISOString();

    const purchaseUpsert = await serviceClient.from("purchase_history").upsert({
      user_id: user.id,
      order_id: serverOrderId,
      product_id: productId,
      purchase_token: purchaseToken,
      plan_type: planType,
      status: snapshot.status,
      purchase_time_ms: serverPurchaseTimeMs,
      expires_time_ms: snapshot.expiresTimeMs,
      obfuscated_account_id: snapshot.obfuscatedAccountId ?? body.obfuscated_account_id ?? null,
      acknowledged: true,
      verified_at: verifiedAt,
      upgrade_bonus_days: 0,
      amount_micros: snapshot.amountMicros,
      currency_code: snapshot.currencyCode,
      updated_at: verifiedAt,
    }, { onConflict: "purchase_token" });
    if (purchaseUpsert.error) throw purchaseUpsert.error;

    const subscriptionUpsert = await serviceClient.from("subscriptions").upsert({
      user_id: user.id,
      plan: planType,
      status: snapshot.status,
      granted_by: "google_play",
      expires_at: expiresAt,
      updated_at: verifiedAt,
    }, { onConflict: "user_id" });
    if (subscriptionUpsert.error) throw subscriptionUpsert.error;

    const publicUpdate = await serviceClient
      .from("users_public")
      .update({
        is_pro: true,
        pro_expires_at: expiresAt,
        pro_plan: planType,
      })
      .eq("id", user.id);
    if (publicUpdate.error) throw publicUpdate.error;

    await serviceClient.functions.invoke("send-notification", {
      body: {
        user_id: user.id,
        title: "Welcome to Echoproof Pro",
        body: `Your ${planType === "pro_yearly" ? "yearly" : "monthly"} Pro subscription is active.`,
        route: "/subscribe",
      },
    }).catch(() => {});

    return ok({
      success: true,
      plan: planType,
      status: snapshot.status,
      expires_at: expiresAt,
      upgrade_bonus_days: 0,
    });
  } catch (error) {
    console.error("verify-purchase error:", error);
    return errRes(502, "could not verify purchase with Google Play - please try again");
  }
});

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
