import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) return err(401, "missing authorization header");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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
    if (authError || !user) return err(401, "unauthenticated");

    let body: { echo_id?: string; type?: string };
    try {
      body = await req.json();
    } catch {
      return err(400, "invalid json body");
    }

    const { echo_id, type } = body;
    if (!echo_id || typeof echo_id !== "string")
      return err(400, "echo_id is required");
    if (!type || !["support", "challenge"].includes(type))
      return err(400, "type must be support or challenge");

    const { data: publicProfile, error: profileError } = await serviceClient
      .from("users_public")
      .select("trust_tier, is_suspended, is_shadow_banned")
      .eq("id", user.id)
      .single();

    if (profileError || !publicProfile)
      return err(404, "user profile not found");
    if (publicProfile.is_suspended) return err(403, "account suspended");

    const { data: echo, error: echoError } = await serviceClient
      .from("echoes")
      .select("id, user_id, status, category")
      .eq("id", echo_id)
      .single();

    if (echoError || !echo) return err(404, "echo not found");
    if (echo.user_id === user.id)
      return err(403, "cannot interact with own echo");
    if (["hidden", "rejected"].includes(echo.status))
      return err(403, "echo is not interactable");

    // rate limit using postgres — no upstash needed
    // simple count query with index on (user_id, created_at)
    const oneHourAgo = new Date(Date.now() - 3_600_000).toISOString();
    const { count: recentCount } = await serviceClient
      .from("echo_interactions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", oneHourAgo);

    if ((recentCount ?? 0) >= 50)
      return err(429, "interaction rate limit exceeded");

    const { data: weightData } = await serviceClient.rpc(
      "calculate_interaction_weight",
      { p_user_id: user.id },
    );
    const weight = (weightData as number) ?? 1;
    const effectiveWeight = publicProfile.is_shadow_banned ? 0 : weight;

    const { error: interactionError } = await serviceClient
      .from("echo_interactions")
      .upsert(
        {
          echo_id,
          user_id: user.id,
          type,
          weight: effectiveWeight,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "echo_id,user_id" },
      );

    if (interactionError) {
      console.error("interaction upsert error:", interactionError);
      return err(500, "failed to record interaction");
    }

    // record feed signal — fire and forget
    if (echo.category) {
      (async () => {
        const { error } = await serviceClient.rpc("record_feed_signal", {
          p_user_id: user.id,
          p_signal_type:
            type === "support" ? "category_support" : "category_challenge",
          p_signal_value: echo.category,
          p_weight: type === "support" ? 2.0 : 1.0,
        });

        if (error) console.warn("feed signal failed:", error);
      })();
    }

    // recalculate echo scores
    const { error: engineError } = await serviceClient.rpc(
      "recalculate_echo_scores",
      { p_echo_id: echo_id },
    );
    if (engineError) console.error("engine error:", engineError);

    // no upstash — feed cache is handled by postgres directly
    // personalized-feed function fetches fresh data each time
    // at scale: add postgres-based cache invalidation or use a background job

    const { data: updatedEcho } = await serviceClient
      .from("echoes")
      .select(
        "trust_score, confidence_score, controversy_score, status, support_count, challenge_count",
      )
      .eq("id", echo_id)
      .single();

    return new Response(JSON.stringify({ success: true, echo: updatedEcho }), {
      headers: { ...CORS, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error("on-interaction unhandled error:", error);
    return err(500, "internal server error");
  }
});

function err(status: number, message: string): Response {
  return new Response(JSON.stringify({ success: false, error: message }), {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Content-Type": "application/json",
    },
    status,
  });
}
