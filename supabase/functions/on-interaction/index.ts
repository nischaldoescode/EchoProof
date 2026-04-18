/**
 * on-interaction edge function
 *
 * triggered when a user supports or challenges an echo.
 * responsibilities:
 *   - validate the request and rate-limit the caller
 *   - calculate interaction weight based on user trust tier
 *   - upsert the interaction row
 *   - record feed signal for personalization algorithm
 *   - call recalculate_echo_scores to update the echo atomically
 *   - return updated echo scores to flutter for optimistic ui sync
 *
 * method: POST
 * auth: required (jwt bearer token)
 * body: { echo_id: string, type: 'support' | 'challenge' }
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    // 1. authenticate caller

    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return errorResponse(401, "missing authorization header");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey     = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // user client — used only to verify the jwt token
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth:   { autoRefreshToken: false, persistSession: false },
    });

    // service client — bypasses rls, used for all db reads and writes
    const serviceClient = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return errorResponse(401, "unauthenticated");
    }

    // 2. validate body

    let body: { echo_id?: string; type?: string };
    try {
      body = await req.json();
    } catch {
      return errorResponse(400, "invalid json body");
    }

    const { echo_id, type } = body;

    if (!echo_id || typeof echo_id !== "string") {
      return errorResponse(400, "echo_id is required");
    }

    if (!type || !["support", "challenge"].includes(type)) {
      return errorResponse(400, "type must be support or challenge");
    }

    // 3. check user is not suspended or shadow-banned

    const { data: publicProfile, error: profileError } = await serviceClient
      .from("users_public")
      .select("trust_tier, is_suspended, is_shadow_banned")
      .eq("id", user.id)
      .single();

    if (profileError || !publicProfile) {
      return errorResponse(404, "user profile not found");
    }

    if (publicProfile.is_suspended) {
      return errorResponse(403, "account suspended");
    }

    // 4. check echo exists and is interactable
    // only select fields needed for validation — no title or content needed here

    const { data: echo, error: echoError } = await serviceClient
      .from("echoes")
      .select("id, user_id, status, category")
      .eq("id", echo_id)
      .single();

    if (echoError || !echo) {
      return errorResponse(404, "echo not found");
    }

    // prevent users from interacting with their own echo
    if (echo.user_id === user.id) {
      return errorResponse(403, "cannot interact with own echo");
    }

    // hidden and rejected echoes cannot be interacted with
    if (["hidden", "rejected"].includes(echo.status)) {
      return errorResponse(403, "echo is not interactable");
    }

    // 5. rate limiting — max 50 interactions per hour per user
    // using postgres count as fallback — replace with upstash redis at scale
    // redis key pattern: rate:interaction:{user_id} with sliding window of 3600s

    const oneHourAgo = new Date(Date.now() - 3_600_000).toISOString();

    const { count: recentCount } = await serviceClient
      .from("echo_interactions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", oneHourAgo);

    if ((recentCount ?? 0) >= 50) {
      return errorResponse(429, "interaction rate limit exceeded");
    }

    // 6. calculate weight based on trust tier

    const { data: weightData } = await serviceClient
      .rpc("calculate_interaction_weight", { p_user_id: user.id });

    const weight = (weightData as number) ?? 1;

    // shadow-banned users: interactions are recorded silently with weight 0
    // they see normal behavior but their votes have no effect on scores
    const effectiveWeight = publicProfile.is_shadow_banned ? 0 : weight;

    // 7. upsert interaction
    // unique constraint on (echo_id, user_id) means user can change their vote
    // support -> challenge is allowed, but only one vote per user per echo

    const { error: interactionError } = await serviceClient
      .from("echo_interactions")
      .upsert(
        {
          echo_id,
          user_id:    user.id,
          type,
          weight:     effectiveWeight,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "echo_id,user_id" }
      );

    if (interactionError) {
      console.error("interaction upsert error:", interactionError);
      return errorResponse(500, "failed to record interaction");
    }

    // 8. record feed signal for personalization algorithm
    // this teaches the feed what categories the user engages with
    // support weight 2.0, challenge weight 1.0 — both signal interest

    if (echo.category) {
      // fire and forget — never block the response for signal recording
      Promise.resolve(
        serviceClient.rpc("record_feed_signal", {
          p_user_id:      user.id,
          p_signal_type:  type === "support" ? "category_support" : "category_challenge",
          p_signal_value: echo.category,
          p_weight:       type === "support" ? 2.0 : 1.0,
        })
      ).catch((err: unknown) => {
        console.warn("feed signal recording failed:", err);
      });
    }

    // 9. run trust engine to recalculate echo scores
    // non-fatal — if this fails, scores will be recalculated by the hourly trust-engine run

    const { error: engineError } = await serviceClient
      .rpc("recalculate_echo_scores", { p_echo_id: echo_id });

    if (engineError) {
      console.error("engine recalculation error:", engineError);
    }

    // 10. fetch updated echo scores and return to flutter
    // flutter uses these to sync the optimistic update with real server values

    const { data: updatedEcho } = await serviceClient
      .from("echoes")
      .select(
        "trust_score, confidence_score, controversy_score, status, support_count, challenge_count"
      )
      .eq("id", echo_id)
      .single();

    return new Response(
      JSON.stringify({ success: true, echo: updatedEcho }),
      {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        status:  200,
      }
    );

  } catch (err) {
    console.error("on-interaction unhandled error:", err);
    return errorResponse(500, "internal server error");
  }
});

function errorResponse(status: number, message: string): Response {
  return new Response(
    JSON.stringify({ success: false, error: message }),
    {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      status,
    }
  );
}