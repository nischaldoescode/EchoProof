/**
 * on-report edge function
 *
 * called when a user files a report against an echo.
 * responsibilities:
 *   1. validate caller is authenticated and has not already reported
 *   2. get reporter's trust weight
 *   3. insert the report row
 *   4. recalculate echo scores (report score affects status)
 *   5. if report score crosses 20, send notification to echo author
 *
 * method: POST
 * auth: required (jwt bearer token)
 * body: { echo_id: string, reason: string, description?: string }
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const VALID_REASONS = new Set([
  "spam",
  "misinformation",
  "harassment",
  "fake_proof",
  "other",
]);

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    // --------------------------------------------------
    // 1. authenticate caller
    // --------------------------------------------------

    const authHeader = req.headers.get("authorization");
    if (!authHeader) return errorResponse(401, "missing authorization header");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey     = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // user client — respects rls, used only to verify the jwt
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return errorResponse(401, "unauthenticated");

    // service client — bypasses rls, used for all db writes
    const serviceClient = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // --------------------------------------------------
    // 2. validate request body
    // --------------------------------------------------

    let body: { echo_id?: string; reason?: string; description?: string };

    try {
      body = await req.json();
    } catch {
      return errorResponse(400, "invalid json body");
    }

    const { echo_id, reason, description } = body;

    if (!echo_id || typeof echo_id !== "string") {
      return errorResponse(400, "echo_id is required");
    }

    if (!reason || !VALID_REASONS.has(reason)) {
      return errorResponse(
        400,
        `reason must be one of: ${[...VALID_REASONS].join(", ")}`
      );
    }

    if (description && description.length > 500) {
      return errorResponse(400, "description exceeds 500 character limit");
    }

    // --------------------------------------------------
    // 3. check echo exists and is reportable
    // --------------------------------------------------

    const { data: echo, error: echoError } = await serviceClient
      .from("echoes")
      .select("id, user_id, status")
      .eq("id", echo_id)
      .single();

    if (echoError || !echo) return errorResponse(404, "echo not found");

    // prevent reporting own echo
    if (echo.user_id === user.id) {
      return errorResponse(403, "cannot report your own echo");
    }

    // already hidden — reporting has no further effect
    if (echo.status === "hidden") {
      return errorResponse(400, "echo is already hidden");
    }

    // --------------------------------------------------
    // 4. check user is not suspended
    // --------------------------------------------------

    const { data: profile } = await serviceClient
      .from("users_public")
      .select("trust_tier, is_suspended")
      .eq("id", user.id)
      .single();

    if (profile?.is_suspended) {
      return errorResponse(403, "account suspended");
    }

    // --------------------------------------------------
    // 5. calculate reporter weight from trust tier
    // --------------------------------------------------

    const reporterWeight = tierToWeight(profile?.trust_tier ?? "unverified");

    // --------------------------------------------------
    // 6. insert report — unique constraint prevents duplicate reports
    // --------------------------------------------------

    const { error: reportError } = await serviceClient
      .from("echo_reports")
      .insert({
        echo_id:         echo_id,
        reporter_id:     user.id,
        reason:          reason,
        description:     description ?? null,
        reporter_weight: reporterWeight,
      });

    if (reportError) {
      // unique constraint violation — user already reported this echo
      if (reportError.code === "23505") {
        return errorResponse(409, "you have already reported this echo");
      }
      console.error("report insert error:", reportError);
      return errorResponse(500, "failed to file report");
    }

    // --------------------------------------------------
    // 7. recalculate echo scores — report score now updated
    //    this may change status to under_review or hidden
    // --------------------------------------------------

    const { error: engineError } = await serviceClient
      .rpc("recalculate_echo_scores", { p_echo_id: echo_id });

    if (engineError) {
      console.warn("engine error after report:", engineError.message);
      // non-fatal — report is already recorded
    }

    // --------------------------------------------------
    // 8. fetch updated echo to return new status
    // --------------------------------------------------

    const { data: updated } = await serviceClient
      .from("echoes")
      .select("status, report_score")
      .eq("id", echo_id)
      .single();

    return new Response(
      JSON.stringify({
        success:      true,
        new_status:   updated?.status ?? echo.status,
        report_score: updated?.report_score ?? 0,
      }),
      {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        status: 200,
      }
    );

  } catch (err) {
    console.error("on-report unhandled error:", err);
    return errorResponse(500, "internal server error");
  }
});

function tierToWeight(tier: string): number {
  switch (tier) {
    case "elite":      return 5;
    case "high":       return 4;
    case "medium":     return 3;
    case "low":        return 2;
    case "unverified": return 1;
    default:           return 1;
  }
}

function errorResponse(status: number, message: string): Response {
  return new Response(
    JSON.stringify({ success: false, error: message }),
    {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      status,
    }
  );
}