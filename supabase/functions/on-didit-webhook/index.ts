// on-didit-webhook edge function
// Didit calls this URL after a user completes identity verification.
// Configure in Didit dashboard under webhook settings.
// URL: {supabase_project_url}/functions/v1/on-didit-webhook
// Events: session.approved, session.declined
//
// On success: updates users_private.is_identity_verified = true
//             calculates identity_score
//             calls update_user_trust_tier SQL function
//             sends push + in-app notification

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createHmac } from "https://deno.land/std@0.177.0/node/crypto.ts";

serve(async (req: Request) => {
  try {
    const body = await req.text();

    // Verify Didit webhook signature (HMAC-SHA256).
    // Secret is in Didit dashboard → webhook settings → signing secret.
    const diditSignature = req.headers.get("x-didit-signature") ?? "";
    const diditSecret = Deno.env.get("DIDIT_WEBHOOK_SECRET") ?? "";

    if (diditSecret) {
      const expected = createHmac("sha256", diditSecret)
        .update(body)
        .digest("hex");

      const received = diditSignature.replace("sha256=", "");

      if (expected !== received) {
        console.error("on-didit-webhook: invalid signature");
        return new Response("invalid signature", { status: 401 });
      }
    }

    const payload = JSON.parse(body);

    // Didit v3 webhook payload structure.
    // session_id is the didit session id, vendor_data is the user_id we passed.
    const sessionStatus = payload?.status as string;
    const userId = payload?.vendor_data as string;
    const sessionId = payload?.session_id as string;

    if (!userId) {
      console.error("on-didit-webhook: missing vendor_data (user_id)");
      return new Response("missing user_id", { status: 400 });
    }

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    // Update verification_sessions table.
    if (sessionId) {
      await serviceClient
        .from("verification_sessions")
        .update({
          status: sessionStatus === "approved" ? "completed" : "failed",
          updated_at: new Date().toISOString(),
        })
        .eq("didit_session_id", sessionId);
    }

    const isPassed = sessionStatus === "approved";

    if (!isPassed) {
      // Record rejection — cooldown enforced server-side.
      await serviceClient
        .from("users_private")
        .update({
          identity_score: 10,
          verification_rejection_at: new Date().toISOString(),
        })
        .eq("id", userId);

      // Increment attempt count atomically.
      await serviceClient.rpc("increment_verification_attempts", {
        p_user_id: userId,
      });

      // Notify user of rejection.
      await serviceClient.from("notifications").insert({
        user_id: userId,
        type: "trust_update",
        title: "Verification unsuccessful",
        body: "Your identity verification was not approved. You can try again in 30 days.",
        data: { type: "identity_rejected" },
      });

      return new Response("verification failed recorded", { status: 200 });
    }

    // Verification passed. Calculate identity score.
    // Didit returns document type in payload.kyc.document_type.
    const docType = (payload?.kyc?.document_type as string ?? "").toLowerCase();
    const idBonus = docType.includes("passport") ? 10 : 5;
    const score = 50 + 20 + idBonus; // base + liveness check + document type

    // Check document age — must be issued at least 2 months ago.
    // Didit returns issue_date in payload.kyc.document.issue_date (YYYY-MM-DD).
    const issueDate = payload?.kyc?.document?.issue_date as string | undefined;
    if (issueDate) {
      const issued = new Date(issueDate);
      const twoMonthsAgo = new Date();
      twoMonthsAgo.setMonth(twoMonthsAgo.getMonth() - 2);

      if (issued > twoMonthsAgo) {
        // Document is less than 2 months old — reject.
        console.warn(`on-didit-webhook: document too new for user ${userId}, issued ${issueDate}`);

        await serviceClient
          .from("users_private")
          .update({
            verification_rejection_at: new Date().toISOString(),
          })
          .eq("id", userId);

        await serviceClient.from("notifications").insert({
          user_id: userId,
          type: "trust_update",
          title: "Verification unsuccessful",
          body: "Your identity document must be at least 2 months old. Please try again with a valid document.",
          data: { type: "identity_rejected_doc_too_new" },
        });

        return new Response(
          JSON.stringify({ verified: false, reason: "document_too_new" }),
          { headers: { "Content-Type": "application/json" }, status: 200 },
        );
      }
    }

    // Update users_private with verified status.
    await serviceClient
      .from("users_private")
      .update({
        is_identity_verified: true,
        identity_score: score,
      })
      .eq("id", userId);

    // Recalculate public trust tier.
    await serviceClient.rpc("update_user_trust_tier", { p_user_id: userId });

    // Send push notification via FCM.
    await serviceClient.functions.invoke("send-notification", {
      body: {
        user_id: userId,
        title: "Identity verified ✓",
        body: "Your identity has been confirmed. Your trust tier has been upgraded.",
        route: "/profile",
        data: { type: "identity_verified" },
      },
    }).catch((e: unknown) => {
      console.warn("on-didit-webhook: send-notification failed", e);
    });

    // Insert in-app notification.
    await serviceClient.from("notifications").insert({
      user_id: userId,
      type: "trust_update",
      title: "Identity verified ✓",
      body: "Your identity has been confirmed. Your trust tier has been upgraded.",
      data: { type: "identity_verified" },
    });

    return new Response(JSON.stringify({ verified: true, score }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err) {
    console.error("on-didit-webhook error:", err);
    return new Response("internal error", { status: 500 });
  }
});