// creates a didit identity verification session
// called by the flutter app, returns the session url
// didit sends webhooks to on-didit-webhook when verification completes

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { user_id, workflow_id, redirect_uri } = await req.json();

    const diditApiKey = Deno.env.get("DIDIT_API_KEY");
    if (!diditApiKey) {
      return new Response(
        JSON.stringify({ error: "DIDIT_API_KEY not configured" }),
        { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    // create session via didit api
    const diditRes = await fetch("https://verification.didit.me/v3/session/", {
      method: "POST",
      headers: {
        "x-api-key":    diditApiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        workflow_id:  workflow_id,
        vendor_data:  user_id,  // links session to our user
        callback:     redirect_uri,
      }),
    });

    if (!diditRes.ok) {
      const err = await diditRes.text();
      console.error("didit session creation failed:", err);
      return new Response(
        JSON.stringify({ error: "verification session creation failed" }),
        { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    const session = await diditRes.json();

    // store session id in supabase for webhook reconciliation
    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    await serviceClient.from("verification_sessions").insert({
      user_id,
      didit_session_id: session.session_id,
      status:           "pending",
    });

    return new Response(
      JSON.stringify({
        session_id:  session.session_id,
        session_url: session.session_url,
      }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("create-didit-session error:", err);
    return new Response(
      JSON.stringify({ error: "internal server error" }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});