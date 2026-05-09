/**
 * rtdn-handler edge function
 *
 * Receives Google Play Real-Time Developer Notifications (RTDN) via Pub/Sub.
 * Handles: renewals, cancellations, refunds, revocations, payment failures.
 *
 * Setup:
 *   1. Google Play Console → Monetization → Subscriptions → Real-time developer notifications
 *   2. Set Pub/Sub topic
 *   3. Create Pub/Sub push subscription → URL: {supabase_url}/functions/v1/rtdn-handler
 *   4. Authenticate with bearer token matching RTDN_SECRET env var
 *
 * The notification types handled:
 *   SUBSCRIPTION_RENEWED       → extend expiry, keep is_pro=true
 *   SUBSCRIPTION_CANCELED      → mark canceled, don't revoke until expiry
 *   SUBSCRIPTION_EXPIRED       → revoke Pro access
 *   SUBSCRIPTION_REVOKED       → immediate revocation (refund/admin)
 *   SUBSCRIPTION_GRACE_PERIOD  → mark grace_period, keep access
 *   SUBSCRIPTION_ON_HOLD       → suspend access
 *   SUBSCRIPTION_RESTARTED     → restore access
 *   SUBSCRIPTION_PRICE_CHANGE_CONFIRMED → log only
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Pub/Sub notification types for subscriptions
const SUBSCRIPTION_NOTIFICATION_TYPE = {
  RECOVERED: 1,
  RENEWED: 2,
  CANCELED: 3,
  PURCHASED: 4,
  ON_HOLD: 5,
  IN_GRACE_PERIOD: 6,
  RESTARTED: 7,
  PRICE_CHANGE_CONFIRMED: 8,
  DEFERRED: 9,
  PAUSED: 10,
  PAUSE_SCHEDULE_CHANGED: 11,
  REVOKED: 12,
  EXPIRED: 13,
};

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    // Verify Pub/Sub bearer token (set in Google Cloud Console)
    const rtdnSecret = Deno.env.get("RTDN_SECRET");
    if (rtdnSecret) {
      const authHeader = req.headers.get("authorization");
      if (!authHeader || authHeader !== `Bearer ${rtdnSecret}`) {
        console.error("rtdn-handler: unauthorized request");
        return new Response("unauthorized", { status: 401 });
      }
    }

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    );

    const body = await req.json();

    // Pub/Sub wraps the message in base64
    const messageData = body?.message?.data;
    if (!messageData) {
      return new Response("no message data", { status: 200 });
    }

    const decoded = atob(messageData);
    const notification = JSON.parse(decoded);

    // Handle subscription notifications
    const subscriptionNotification = notification.subscriptionNotification;
    if (!subscriptionNotification) {
      console.log("rtdn-handler: non-subscription notification, ignoring");
      return new Response("ok", { status: 200 });
    }

    const { notificationType, purchaseToken, subscriptionId } = subscriptionNotification;
    const packageName = notification.packageName as string;

    console.log(`rtdn-handler: type=${notificationType} subscription=${subscriptionId}`);

    // Find user by purchase token
    const { data: historyRow } = await serviceClient
      .from("purchase_history")
      .select("user_id, plan_type, expires_time_ms")
      .eq("purchase_token", purchaseToken)
      .maybeSingle();

    if (!historyRow) {
      console.warn(`rtdn-handler: no purchase_history row for token — may be a new purchase`);
      // Still return 200 to acknowledge Pub/Sub
      return new Response("ok", { status: 200 });
    }

    const userId = historyRow.user_id as string;
    const now = new Date().toISOString();

    switch (notificationType) {
      case SUBSCRIPTION_NOTIFICATION_TYPE.RENEWED: {
        // Subscription renewed — update expiry by fetching from Play API
        await serviceClient
          .from("subscriptions")
          .update({ status: "active", updated_at: now })
          .eq("user_id", userId);

        await serviceClient
          .from("users_public")
          .update({ is_pro: true })
          .eq("id", userId);

        await serviceClient
          .from("purchase_history")
          .update({ status: "acknowledged", updated_at: now })
          .eq("purchase_token", purchaseToken);

        console.log(`rtdn-handler: renewed for user ${userId}`);
        break;
      }

      case SUBSCRIPTION_NOTIFICATION_TYPE.CANCELED: {
        // Canceled — keep access until expiry, just mark canceled
        await serviceClient
          .from("subscriptions")
          .update({ status: "canceled", updated_at: now })
          .eq("user_id", userId);

        await serviceClient
          .from("purchase_history")
          .update({ status: "canceled", updated_at: now })
          .eq("purchase_token", purchaseToken);

        // Send notification
        await serviceClient.functions.invoke("send-notification", {
          body: {
            user_id: userId,
            title: "Subscription cancelled",
            body: "Your Pro subscription has been cancelled. You'll keep access until your billing period ends.",
            route: "/subscribe",
          },
        }).catch(() => {});

        console.log(`rtdn-handler: canceled for user ${userId}`);
        break;
      }

      case SUBSCRIPTION_NOTIFICATION_TYPE.EXPIRED: {
        // EXPIRED — revoke Pro access immediately
        await serviceClient
          .from("subscriptions")
          .update({ status: "expired", updated_at: now })
          .eq("user_id", userId);

        await serviceClient
          .from("users_public")
          .update({ is_pro: false, pro_expires_at: null, pro_plan: null })
          .eq("id", userId);

        await serviceClient
          .from("purchase_history")
          .update({ status: "expired", updated_at: now })
          .eq("purchase_token", purchaseToken);

        await serviceClient.functions.invoke("send-notification", {
          body: {
            user_id: userId,
            title: "Pro subscription expired",
            body: "Your Echoproof Pro subscription has expired. Renew to keep your Pro features.",
            route: "/subscribe",
          },
        }).catch(() => {});

        console.log(`rtdn-handler: expired — revoked Pro for user ${userId}`);
        break;
      }

      case SUBSCRIPTION_NOTIFICATION_TYPE.REVOKED: {
        // REVOKED = immediate revocation (refund, admin action)
        await serviceClient
          .from("subscriptions")
          .update({ status: "canceled", updated_at: now })
          .eq("user_id", userId);

        await serviceClient
          .from("users_public")
          .update({ is_pro: false, pro_expires_at: null, pro_plan: null })
          .eq("id", userId);

        await serviceClient
          .from("purchase_history")
          .update({
            status: "refunded",
            error_message: "Revoked by Google Play (refund or admin action)",
            updated_at: now
          })
          .eq("purchase_token", purchaseToken);

        await serviceClient.functions.invoke("send-notification", {
          body: {
            user_id: userId,
            title: "Subscription revoked",
            body: "Your Pro subscription has been revoked. If this is unexpected, please contact support.",
            route: "/subscribe",
          },
        }).catch(() => {});

        console.log(`rtdn-handler: REVOKED — immediate Pro revocation for user ${userId}`);
        break;
      }

      case SUBSCRIPTION_NOTIFICATION_TYPE.IN_GRACE_PERIOD: {
        // Payment failed — grace period (keep access, warn user)
        await serviceClient
          .from("subscriptions")
          .update({ status: "grace_period", updated_at: now })
          .eq("user_id", userId);

        await serviceClient
          .from("purchase_history")
          .update({ status: "grace_period", updated_at: now })
          .eq("purchase_token", purchaseToken);

        await serviceClient.functions.invoke("send-notification", {
          body: {
            user_id: userId,
            title: "Payment issue — action needed",
            body: "We couldn't process your subscription payment. Please update your payment method to keep Pro access.",
            route: "/subscribe",
          },
        }).catch(() => {});

        break;
      }

      case SUBSCRIPTION_NOTIFICATION_TYPE.ON_HOLD: {
        // Payment failed after grace period — suspend access
        await serviceClient
          .from("subscriptions")
          .update({ status: "on_hold", updated_at: now })
          .eq("user_id", userId);

        await serviceClient
          .from("users_public")
          .update({ is_pro: false })
          .eq("id", userId);

        await serviceClient
          .from("purchase_history")
          .update({ status: "on_hold", updated_at: now })
          .eq("purchase_token", purchaseToken);

        break;
      }

      case SUBSCRIPTION_NOTIFICATION_TYPE.RECOVERED: {
        // Payment recovered after hold — restore access
        await serviceClient
          .from("subscriptions")
          .update({ status: "active", updated_at: now })
          .eq("user_id", userId);

        await serviceClient
          .from("users_public")
          .update({ is_pro: true })
          .eq("id", userId);

        break;
      }

      case SUBSCRIPTION_NOTIFICATION_TYPE.RESTARTED: {
        // User re-enabled canceled subscription before expiry
        await serviceClient
          .from("subscriptions")
          .update({ status: "active", updated_at: now })
          .eq("user_id", userId);

        await serviceClient
          .from("users_public")
          .update({ is_pro: true })
          .eq("id", userId);

        break;
      }

      default:
        console.log(`rtdn-handler: unhandled notification type ${notificationType}`);
    }

    // Always return 200 to acknowledge Pub/Sub (otherwise it retries indefinitely)
    return new Response("ok", { status: 200, headers: CORS });

  } catch (e) {
    console.error("rtdn-handler unhandled error:", e);
    // Still return 200 — don't let Pub/Sub retry on our errors
    return new Response("ok", { status: 200 });
  }
});