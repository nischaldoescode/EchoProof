// creates a didit identity verification session
// called by the flutter app, returns the session url
// didit sends webhooks to on-didit-webhook when verification completes

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const serviceClient = createClient(supabaseUrl, serviceRoleKey);

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { user_id, workflow_id, redirect_uri } = await req.json();

    // Get client IP from request headers.
    // Supabase edge functions receive CF-Connecting-IP from Cloudflare.
    const clientIp =
      req.headers.get("cf-connecting-ip") ??
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      "unknown";

    const now = new Date();

    // 1. Per-account: max 2 attempts in any 30-day window.
    const { data: userAttemptCount } = await serviceClient.rpc(
      "count_verification_attempts_by_user",
      { p_user_id: user_id, p_days: 30 },
    );

    if ((userAttemptCount ?? 0) >= 2) {
      return new Response(
        JSON.stringify({
          error: "verification_account_limit",
          message:
            "You have reached the maximum of 2 verification attempts per month per account.",
        }),
        {
          status: 429,
          headers: { ...CORS, "Content-Type": "application/json" },
        },
      );
    }

    // 2. Per-IP: max 3 attempts in 30 days (prevents account farming).
    if (clientIp !== "unknown") {
      const { data: ipAttemptCount } = await serviceClient.rpc(
        "count_verification_attempts_by_ip",
        { p_ip: clientIp, p_days: 30 },
      );

      if ((ipAttemptCount ?? 0) >= 3) {
        return new Response(
          JSON.stringify({
            error: "verification_ip_limit",
            message:
              "Too many verification attempts from this network. Please try again later.",
          }),
          {
            status: 429,
            headers: { ...CORS, "Content-Type": "application/json" },
          },
        );
      }
    }

    // 3. 30-day cooldown after rejection.
    const { data: privateRow } = await serviceClient
      .from("users_private")
      .select(
        "last_verification_request_at, verification_rejection_at, verification_attempt_count",
      )
      .eq("id", user_id)
      .maybeSingle();

    if (privateRow) {
      const rejectionAt = privateRow.verification_rejection_at
        ? new Date(privateRow.verification_rejection_at as string)
        : null;

      if (rejectionAt) {
        const daysSinceRejection =
          (now.getTime() - rejectionAt.getTime()) / (1000 * 60 * 60 * 24);
        if (daysSinceRejection < 30) {
          const daysRemaining = Math.ceil(30 - daysSinceRejection);
          return new Response(
            JSON.stringify({
              error: "verification_cooldown",
              days_remaining: daysRemaining,
              message: `You can re-apply for verification in ${daysRemaining} day(s).`,
            }),
            {
              status: 429,
              headers: { ...CORS, "Content-Type": "application/json" },
            },
          );
        }
      }
    }

    // 4. Log this attempt (for both account and IP rate limiting).
    await serviceClient.from("verification_ip_log").insert({
      ip_address: clientIp,
      user_id,
    });

    // 5. Update last request timestamp on users_private.
    await serviceClient
      .from("users_private")
      .update({ last_verification_request_at: now.toISOString() })
      .eq("id", user_id);

    const diditApiKey = Deno.env.get("DIDIT_API_KEY");
    if (!diditApiKey) {
      return new Response(
        JSON.stringify({ error: "DIDIT_API_KEY not configured" }),
        {
          status: 500,
          headers: { ...CORS, "Content-Type": "application/json" },
        },
      );
    }

    const diditRes = await fetch("https://verification.didit.me/v3/session/", {
      method: "POST",
      headers: {
        "x-api-key": diditApiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        workflow_id: workflow_id,
        vendor_data: user_id,
        callback: redirect_uri,
      }),
    });

    if (!diditRes.ok) {
      const err = await diditRes.text();
      console.error("didit session creation failed:", err);
      return new Response(
        JSON.stringify({ error: "verification session creation failed" }),
        {
          status: 500,
          headers: { ...CORS, "Content-Type": "application/json" },
        },
      );
    }

    const session = await diditRes.json();
    console.log("didit session response:", JSON.stringify(session));

    const sessionUrl =
      session.session_url ?? session.url ?? session.verification_url ?? null;

    if (!sessionUrl) {
      console.error(
        "didit: no session url in response:",
        JSON.stringify(session),
      );
      return new Response(
        JSON.stringify({ error: "no session url returned from didit" }),
        {
          status: 500,
          headers: { ...CORS, "Content-Type": "application/json" },
        },
      );
    }

    await serviceClient
      .from("verification_sessions")
      .insert({
        user_id,
        didit_session_id: session.session_id,
        status: "pending",
      })
      .then(({ error }) => {
        if (error)
          console.warn("didit: could not store session:", error.message);
      });

    return new Response(
      JSON.stringify({
        session_id: session.session_id,
        session_url: sessionUrl,
        session_token: session.session_token ?? session.sessionToken ?? null,
      }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("create-didit-session error:", err);
    return new Response(JSON.stringify({ error: "internal server error" }), {
      status: 500,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
