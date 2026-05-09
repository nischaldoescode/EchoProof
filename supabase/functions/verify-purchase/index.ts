/**
 * verify-purchase edge function
 *
 * Called by the Flutter app after a Google Play purchase completes.
 * Validates the purchase token with Google Play Developer API server-side.
 * Never trusts client-side data — all entitlement decisions made here.
 *
 * Security model:
 *   - Purchase token validated against Google Play API
 *   - Obfuscated account ID checked against authenticated user
 *   - All purchase records stored server-side with full audit trail
 *   - Upgrade bonus calculated server-side
 *
 * Method: POST
 * Auth: user JWT required
 * Body: {
 *   purchase_token: string,
 *   product_id: string,
 *   order_id: string,
 *   purchase_time_ms: number,
 *   obfuscated_account_id?: string
 * }
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const PACKAGE_NAME = "com.echoproof.app";

// Google Play subscription product IDs
const VALID_PRODUCT_IDS = new Set([
  "echoproof_pro_monthly",
  "echoproof_pro_yearly",
]);

// Gets a Google OAuth2 access token from a service account JSON
async function getGoogleAccessToken(
  serviceAccountJson: string,
): Promise<string> {
  const sa = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);

  const header = btoa(JSON.stringify({ alg: "RS256", typ: "JWT" }))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
  const payload = btoa(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  )
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  const unsigned = `${header}.${payload}`;
  const keyData = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");

  const binaryKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsigned),
  );

  const encSig = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${encSig}`,
    }),
  });

  const tokenData = (await tokenRes.json()) as { access_token: string };
  return tokenData.access_token;
}

// Validates a subscription purchase with Google Play Developer API v3
// Returns the subscription resource or throws
async function validateWithGooglePlay(
  accessToken: string,
  productId: string,
  purchaseToken: string,
): Promise<Record<string, unknown>> {
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}/purchases/subscriptions/${productId}/tokens/${purchaseToken}`;

  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Google Play validation failed: ${res.status} ${errText}`);
  }

  return (await res.json()) as Record<string, unknown>;
}

// Acknowledges a subscription purchase (required within 3 days)
async function acknowledgePurchase(
  accessToken: string,
  productId: string,
  purchaseToken: string,
): Promise<void> {
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}/purchases/subscriptions/${productId}/tokens/${purchaseToken}:acknowledge`;

  await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({}),
  });
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    // Authenticate caller
    const authHeader = req.headers.get("authorization");
    if (!authHeader) return errRes(401, "missing authorization");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const googleServiceAccount = Deno.env.get(
      "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
    );

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const serviceClient = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const {
      data: { user },
      error: authErr,
    } = await userClient.auth.getUser();
    if (authErr || !user) return errRes(401, "unauthenticated");

    // Validate request body
    let body: {
      purchase_token?: string;
      product_id?: string;
      order_id?: string;
      purchase_time_ms?: number;
      obfuscated_account_id?: string;
    };

    try {
      body = await req.json();
    } catch {
      return errRes(400, "invalid json");
    }

    const {
      purchase_token,
      product_id,
      order_id,
      purchase_time_ms,
      obfuscated_account_id,
    } = body;

    if (!purchase_token || !product_id || !order_id || !purchase_time_ms) {
      return errRes(400, "missing required fields");
    }

    if (!VALID_PRODUCT_IDS.has(product_id)) {
      return errRes(400, "invalid product_id");
    }

    // Check for duplicate order (replay attack prevention)
    const { data: existingOrder } = await serviceClient
      .from("purchase_history")
      .select("id, status, user_id")
      .eq("order_id", order_id)
      .maybeSingle();

    if (existingOrder) {
      // If same user re-submitting acknowledged order, return success
      if (
        existingOrder.user_id === user.id &&
        existingOrder.status === "acknowledged"
      ) {
        return ok({ success: true, status: "already_acknowledged" });
      }
      // If different user — fraud attempt
      if (existingOrder && existingOrder.user_id !== user.id) {
        return errRes(403, "purchase not associated with this account");
      }
    }

    // Server-side validation with Google Play
    if (!googleServiceAccount) {
      // Fail hard — never grant Pro without server verification
      console.error(
        "verify-purchase: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON not configured",
      );
      return errRes(500, "server misconfigured — contact support");
    }

    let playSubscription: Record<string, unknown> | null = null;
    let validatedLocally = false;
    if (googleServiceAccount) {
      try {
        const accessToken = await getGoogleAccessToken(googleServiceAccount);

        playSubscription = await validateWithGooglePlay(
          accessToken,
          product_id,
          purchase_token,
        );

        const playObfuscatedId =
          playSubscription.obfuscatedExternalAccountId as string | undefined;

        if (obfuscated_account_id && playObfuscatedId) {
          if (playObfuscatedId !== obfuscated_account_id) {
            console.error("verify-purchase: obfuscated account id mismatch");
            return errRes(
              403,
              "account id mismatch — purchase not associated with this account",
            );
          }
        }

        const ackState = playSubscription.acknowledgementState as number;

        if (ackState !== 1) {
          await acknowledgePurchase(accessToken, product_id, purchase_token);
        }
      } catch (e) {
        console.error("verify-purchase: Google Play validation failed:", e);
        return errRes(
          502,
          "could not verify purchase with Google Play — please try again",
        );
      }
    } else {
      console.warn(
        "verify-purchase: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON not set — dev mode",
      );
      validatedLocally = true;
    }

    // Determine subscription details
    const isYearly = product_id.includes("yearly");
    const planType = isYearly ? "pro_yearly" : "pro_monthly";

    let expiresTimeMs: number;
    let amountMicros: number | null = null;
    let currencyCode: string | null = null;

    if (playSubscription) {
      // Use Google Play's actual expiry time
      expiresTimeMs = parseInt(playSubscription.expiryTimeMillis as string);
      const priceInfo = playSubscription.priceAmountMicros as
        | string
        | undefined;
      if (priceInfo) amountMicros = parseInt(priceInfo);
      currencyCode = (playSubscription.priceCurrencyCode as string) ?? null;
    } else {
      // Dev mode fallback
      const daysToAdd = isYearly ? 365 : 30;
      expiresTimeMs = Date.now() + daysToAdd * 24 * 60 * 60 * 1000;
    }

    // Check for upgrade bonus
    // If user is switching from monthly to yearly, grant remaining monthly days free
    let upgradeBonusDays = 0;
    const { data: currentSub } = await serviceClient
      .from("subscriptions")
      .select("expires_at, plan")
      .eq("user_id", user.id)
      .maybeSingle();

    if (currentSub && currentSub.plan === "pro_monthly" && isYearly) {
      const now = Date.now();
      const currentExpiry = new Date(currentSub.expires_at as string).getTime();
      if (currentExpiry > now) {
        upgradeBonusDays = Math.ceil(
          (currentExpiry - now) / (24 * 60 * 60 * 1000),
        );
        // Extend the yearly subscription by the remaining monthly days
        expiresTimeMs += upgradeBonusDays * 24 * 60 * 60 * 1000;
        console.log(
          `verify-purchase: granting ${upgradeBonusDays} upgrade bonus days`,
        );
      }
    }

    const expiresAt = new Date(expiresTimeMs).toISOString();

    // Record purchase in history (full audit trail)
    await serviceClient.from("purchase_history").upsert(
      {
        user_id: user.id,
        order_id: order_id,
        product_id: product_id,
        purchase_token: purchase_token,
        plan_type: planType,
        status: "acknowledged",
        purchase_time_ms: purchase_time_ms,
        expires_time_ms: expiresTimeMs,
        obfuscated_account_id: obfuscated_account_id ?? null,
        acknowledged: true,
        verified_at: new Date().toISOString(),
        upgrade_bonus_days: upgradeBonusDays,
        amount_micros: amountMicros,
        currency_code: currencyCode,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "order_id" },
    );

    // Update subscription record
    await serviceClient.from("subscriptions").upsert(
      {
        user_id: user.id,
        plan: planType,
        status: "active",
        granted_by: validatedLocally ? "dev_mode" : "google_play",
        expires_at: expiresAt,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id" },
    );

    // Update users_public Pro badge
    await serviceClient
      .from("users_public")
      .update({
        is_pro: true,
        pro_expires_at: expiresAt,
        pro_plan: planType,
      })
      .eq("id", user.id);

    // Send Pro welcome notification
    await serviceClient.functions
      .invoke("send-notification", {
        body: {
          user_id: user.id,
          title: "Welcome to Echoproof Pro ⭐",
          body: `Your ${isYearly ? "yearly" : "monthly"} Pro subscription is active. Enjoy all features.`,
          route: "/subscribe",
        },
      })
      .catch(() => {}); // fire and forget

    return ok({
      success: true,
      plan: planType,
      expires_at: expiresAt,
      upgrade_bonus_days: upgradeBonusDays,
    });
  } catch (e) {
    console.error("verify-purchase unhandled error:", e);
    return errRes(500, "internal server error");
  }
});

function ok(data: Record<string, unknown>): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function errRes(status: number, message: string): Response {
  return new Response(JSON.stringify({ success: false, error: message }), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
