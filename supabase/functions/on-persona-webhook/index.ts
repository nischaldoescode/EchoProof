/**
 * on-persona-webhook edge function
 *
 * persona calls this url after a user completes identity verification.
 * this is configured in persona dashboard under:
 *   integrations > webhooks > add endpoint
 *   url: {supabase_project_url}/functions/v1/on-persona-webhook
 *   events: inquiry.completed, inquiry.failed
 *
 * on success: updates users_private.is_identity_verified = true
 *             updates users_private.identity_score
 *             calls update_user_trust_tier sql function
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHmac } from "https://deno.land/std@0.177.0/node/crypto.ts";

serve(async (req: Request) => {
  try {
    const body = await req.text();

    // --------------------------------------------------------
    // verify persona webhook signature
    // persona signs every webhook with hmac-sha256
    // secret is in persona dashboard > webhooks > signing secret
    // --------------------------------------------------------

    const personaSignature = req.headers.get("persona-signature") ?? "";
    const personaSecret = Deno.env.get("PERSONA_WEBHOOK_SECRET") ?? "";

    if (personaSecret) {
      const expected = createHmac("sha256", personaSecret)
        .update(body)
        .digest("hex");

      const received = personaSignature.replace("sha256=", "");

      if (expected !== received) {
        return new Response("invalid signature", { status: 401 });
      }
    }

    const payload = JSON.parse(body);
    const event = payload?.data?.type as string;

    if (!["inquiry.completed", "inquiry.failed"].includes(event)) {
      return new Response("ignored event", { status: 200 });
    }

    const inquiry = payload.data.attributes;
    const userId = inquiry["reference-id"] as string; // the user id we passed
    const isPassed =
      event === "inquiry.completed" && inquiry.status === "completed";

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    if (!isPassed) {
      // Record rejection — user cannot re-apply for 30 days (server-enforced)
      await serviceClient
        .from("users_private")
        .update({
          identity_score: 10,
          verification_rejection_at: new Date().toISOString(),
          verification_attempt_count: serviceClient.rpc(
            "increment_verification_attempts",
            {
              p_user_id: userId,
            },
          ),
        })
        .eq("id", userId);
      return new Response("verification failed recorded", { status: 200 });
    }

    // identity score calculation matching the sql formula
    const idType = (inquiry["identification-class"] as string) ?? "";
    const idBonus = idType.includes("passport")
      ? 10
      : idType.includes("national")
        ? 10
        : 5;
    const score = 50 + 20 + idBonus; // base + liveness + id type

    // update private table
    await serviceClient
      .from("users_private")
      .update({
        is_identity_verified: true,
        identity_score: score,
      })
      .eq("id", userId);

    // recalculate public trust tier
    await serviceClient.rpc("update_user_trust_tier", { p_user_id: userId });

    return new Response(JSON.stringify({ verified: true, score }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err) {
    console.error("on-persona-webhook error:", err);
    return new Response("internal error", { status: 500 });
  }
});
