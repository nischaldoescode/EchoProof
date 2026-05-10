// send-notification edge function
// called by other edge functions (on-echo-verified, trust-engine, etc.)
// uses FCM HTTP v1 API — the v1 API is the current standard
// legacy API was deprecated june 2023, removed june 2024
//
// to set up:
//   1. firebase console → project settings → service accounts → generate new private key
//   2. supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='<contents of json>'
//   3. supabase secrets set FIREBASE_PROJECT_ID='your-project-id'

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// generates a google oauth2 access token from service account credentials
// FCM v1 API requires this — not the server key
async function getAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  const now     = Math.floor(Date.now() / 1000);
  const payload = {
    iss:   serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud:   "https://oauth2.googleapis.com/token",
    iat:   now,
    exp:   now + 3600,
  };

  // encode header
  const header  = { alg: "RS256", typ: "JWT" };
  const encHead  = btoa(JSON.stringify(header)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const encPay   = btoa(JSON.stringify(payload)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const unsigned = `${encHead}.${encPay}`;

  // sign with private key
  const keyData = serviceAccount.private_key
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

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsigned),
  );

  const encSig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const jwt = `${unsigned}.${encSig}`;

  // exchange jwt for access token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion:  jwt,
    }),
  });

  const tokenData = await tokenRes.json() as { access_token: string };
  return tokenData.access_token;
}

interface SendNotifPayload {
  user_id:  string;
  title:    string;
  body:     string;
  data?:    Record<string, string>;
  route?:   string;
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { user_id, title, body, data, route }: SendNotifPayload = await req.json();

    const serviceAccountRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    const projectId          = Deno.env.get("FIREBASE_PROJECT_ID");

    if (!serviceAccountRaw || !projectId) {
      console.warn("firebase not configured — skipping notification");
      return new Response(
        JSON.stringify({ skipped: true }),
        { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    const serviceAccount = JSON.parse(serviceAccountRaw) as Record<string, string>;
    const accessToken    = await getAccessToken(serviceAccount);

    // fetch device tokens for this user from supabase
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: tokens } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", user_id);

    if (!tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ sent: 0 }),
        { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    // send to each device token via FCM HTTP v1 API
    const sends = tokens.map(async (row: { token: string }) => {
      const message = {
        message: {
          token: row.token,
          notification: { title, body },
          android: {
            priority:     "high",
            notification: {
              channel_id:            "echoproof_default",
              click_action:          "FLUTTER_NOTIFICATION_CLICK",
              notification_priority: "PRIORITY_HIGH",
              color:                 "#4CAF6E",
            },
          },
          data: {
            ...(data ?? {}),
            route: route ?? "/notifications",
          },
        },
      };

      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method:  "POST",
          headers: {
            Authorization:  `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(message),
        },
      );

      if (!res.ok) {
        const err = await res.text();
        console.error(`fcm send failed for token: ${err}`);
        return false;
      }
      return true;
    });

    const results = await Promise.all(sends);
    const sent    = results.filter(Boolean).length;

    return new Response(
      JSON.stringify({ sent }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );

  } catch (err) {
    console.error("send-notification error:", err);
    return new Response(
      JSON.stringify({ error: "internal error" }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});