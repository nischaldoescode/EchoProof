/**
 * trust engine edge function
 *
 * a scheduled function that runs periodic maintenance tasks:
 *   1. expires zero-engagement echoes older than 72 hours
 *   2. recalculates trust tiers for users whose scores may have drifted
 *   3. promotes echoes that crossed a threshold since last engine run
 *
 * schedule setup in supabase dashboard:
 *   database > extensions > enable pg_cron
 *   then run this sql:
 *     select cron.schedule(
 *       'trust-engine-hourly',
 *       '0 * * * *',
 *       $$ select net.http_post(
 *         url := '{project_url}/functions/v1/trust-engine',
 *         headers := '{"Authorization": "Bearer {service_role_key}"}'::jsonb
 *       ) $$
 *     );
 *
 * can also be triggered manually via:
 *   curl -X POST {supabase_url}/functions/v1/trust-engine \
 *     -H "Authorization: Bearer {service_role_key}"
 *
 * method: POST
 * auth: service role key only (not user jwt)
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
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const serviceClient = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const results: Record<string, unknown> = {};

    // --------------------------------------------------
    // task 1: expire zero-engagement echoes
    // calls the sql function from 003_trust_engine.sql
    // marks echoes with no interactions older than 72h as low priority
    // --------------------------------------------------

    const { error: expireError } = await serviceClient
      .rpc("expire_zero_engagement_echoes");

    results["expire_zero_engagement"] = expireError
      ? { error: expireError.message }
      : { success: true };

    // --------------------------------------------------
    // task 2: find echoes that need score recalculation
    // targets echoes that have new interactions since last engine run
    // limits to 50 per run to avoid timeout (edge functions max 150s)
    // --------------------------------------------------

    const { data: staleEchoes, error: staleError } = await serviceClient
      .from("echoes")
      .select("id")
      .not("status", "in", '("hidden","rejected")')
      .or("last_engine_run_at.is.null,last_engine_run_at.lt." +
        new Date(Date.now() - 3_600_000).toISOString()) // older than 1 hour
      .limit(50);

    if (staleError) {
      results["recalculate_stale"] = { error: staleError.message };
    } else {
      let recalculated = 0;
      let failed = 0;

      for (const echo of staleEchoes ?? []) {
        const { error } = await serviceClient
          .rpc("recalculate_echo_scores", { p_echo_id: echo.id });

        if (error) {
          console.warn(`engine failed for echo ${echo.id}:`, error.message);
          failed++;
        } else {
          recalculated++;
        }
      }

      results["recalculate_stale"] = { recalculated, failed };
    }

    // --------------------------------------------------
    // task 3: refresh trust tiers for users whose
    // identity verification may have completed since last check
    // limits to 20 per run
    // --------------------------------------------------

    const { data: usersToUpdate, error: usersError } = await serviceClient
      .from("users_private")
      .select("id")
      .eq("is_identity_verified", true)
      .gt("updated_at",
        new Date(Date.now() - 86_400_000).toISOString()) // verified in last 24h
      .limit(20);

    if (usersError) {
      results["trust_tier_refresh"] = { error: usersError.message };
    } else {
      let refreshed = 0;

      for (const user of usersToUpdate ?? []) {
        const { error } = await serviceClient
          .rpc("update_user_trust_tier", { p_user_id: user.id });

        if (!error) refreshed++;
      }

      results["trust_tier_refresh"] = { refreshed };
    }

    return new Response(
      JSON.stringify({
        success:    true,
        ran_at:     new Date().toISOString(),
        results,
      }),
      {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        status: 200,
      }
    );

  } catch (err) {
    console.error("trust-engine unhandled error:", err);
    return new Response(
      JSON.stringify({ success: false, error: "internal server error" }),
      {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});