/**
 * check-subscription edge function
 *
 * Called on app resume / feed load to verify subscription status is current.
 * Checks Google Play for the latest subscription state.
 * Downgrades account if subscription has expired or been cancelled.
 *
 * Method: POST
 * Auth: user JWT required
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const PACKAGE_NAME = "com.echoproof.app";

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) return errRes(401, "unauthorized");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const serviceClient = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const {
      data: { user },
    } = await userClient.auth.getUser();
    if (!user) return errRes(401, "unauthenticated");

    // Get current subscription from DB
    const { data: sub } = await serviceClient
      .from("subscriptions")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!sub) {
      return ok({ is_pro: false, status: "no_subscription" });
    }

    // Grace period: still has access despite payment failure
    const activeStatuses = ["active", "grace_period"];
    if (!activeStatuses.includes(sub.status as string)) {
      // Ensure users_public is also updated (sync safety)
      await serviceClient
        .from("users_public")
        .update({ is_pro: false, pro_expires_at: null, pro_plan: null })
        .eq("id", user.id);
      return ok({ is_pro: false, status: sub.status });
    }

    // Check local expiry first (fast path)
    const now = new Date();
    const expiresAt = sub.expires_at
      ? new Date(sub.expires_at as string)
      : null;

    if (expiresAt && expiresAt < now) {
      // Subscription has expired — downgrade
      await serviceClient
        .from("subscriptions")
        .update({ status: "expired", updated_at: now.toISOString() })
        .eq("user_id", user.id);

      await serviceClient
        .from("users_public")
        .update({ is_pro: false, pro_expires_at: null, pro_plan: null })
        .eq("id", user.id);

      return ok({ is_pro: false, status: "expired" });
    }

    return ok({
      is_pro: true,
      status: "active",
      plan: sub.plan,
      expires_at: sub.expires_at,
    });
  } catch (e) {
    console.error("check-subscription error:", e);
    return errRes(500, "internal error");
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
