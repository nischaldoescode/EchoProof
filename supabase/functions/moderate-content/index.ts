// moderate-content edge function
// Called when a new echo is created to screen text, images, and videos.
// Text: SightEngine rule-based + ML models.
// Images/Videos: SightEngine genai detection (AI-generated content check).
// Falls back gracefully if API is unavailable.
// Rate-limited per user: max 10 calls per hour on free tier protection.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ModerationResult {
  allowed: boolean;
  reason?: string;
  category?: string;
}

async function moderateText(text: string, lang = "en"): Promise<ModerationResult> {
  const apiUser = Deno.env.get("SIGHTENGINE_API_USER");
  const apiSecret = Deno.env.get("SIGHTENGINE_API_SECRET");

  if (!apiUser || !apiSecret) {
    console.warn("moderate: SightEngine not configured, skipping text moderation");
    return { allowed: true };
  }

  try {
    // Rule-based first (fast, low latency)
    const ruleForm = new FormData();
    ruleForm.append("text", text);
    ruleForm.append("lang", lang);
    ruleForm.append("models", "profanity,self-harm,violence");
    ruleForm.append("mode", "rules");
    ruleForm.append("api_user", apiUser);
    ruleForm.append("api_secret", apiSecret);

    const ruleRes = await fetch("https://api.sightengine.com/1.0/text/check.json", {
      method: "POST",
      body: ruleForm,
    });

    if (ruleRes.ok) {
      const data = await ruleRes.json() as Record<string, unknown>;
      const profanity = data.profanity as { matches?: Array<{ intensity: string }> } | undefined;
      const matches = profanity?.matches ?? [];

      // Block high-intensity profanity.
      const hasHighIntensity = matches.some((m) => m.intensity === "high");
      if (hasHighIntensity) {
        return { allowed: false, reason: "content_policy", category: "profanity" };
      }

      const selfHarm = data["self-harm"] as { matches?: unknown[] } | undefined;
      if ((selfHarm?.matches?.length ?? 0) > 0) {
        return { allowed: false, reason: "content_policy", category: "self_harm" };
      }
    }

    // ML models for semantic understanding (use sparingly — one call per echo).
    const mlForm = new FormData();
    mlForm.append("text", text);
    mlForm.append("lang", lang);
    mlForm.append("models", "general");
    mlForm.append("mode", "ml");
    mlForm.append("api_user", apiUser);
    mlForm.append("api_secret", apiSecret);

    const mlRes = await fetch("https://api.sightengine.com/1.0/text/check.json", {
      method: "POST",
      body: mlForm,
    });

    if (mlRes.ok) {
      const mlData = await mlRes.json() as Record<string, unknown>;
      const classes = mlData.moderation_classes as Record<string, number> | undefined;
      if (classes) {
        if ((classes.toxic ?? 0) > 0.85) {
          return { allowed: false, reason: "content_policy", category: "toxic" };
        }
        if ((classes.violent ?? 0) > 0.9) {
          return { allowed: false, reason: "content_policy", category: "violent" };
        }
      }
    }

    return { allowed: true };
  } catch (e) {
    console.error("moderate: text check failed", e);
    // Fail open — do not block content if API is down.
    return { allowed: true };
  }
}

async function checkMediaForAI(mediaUrl: string): Promise<boolean> {
  const apiUser = Deno.env.get("SIGHTENGINE_API_USER");
  const apiSecret = Deno.env.get("SIGHTENGINE_API_SECRET");

  if (!apiUser || !apiSecret) return false;

  try {
    const res = await fetch(
      `https://api.sightengine.com/1.0/check.json?url=${encodeURIComponent(mediaUrl)}&models=genai&api_user=${apiUser}&api_secret=${apiSecret}`,
    );
    if (!res.ok) return false;
    const data = await res.json() as Record<string, unknown>;
    const typeData = data.type as { ai_generated?: number } | undefined;
    return (typeData?.ai_generated ?? 0) > 0.75;
  } catch (e) {
    console.error("moderate: media AI check failed", e);
    return false;
  }
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { echo_id, user_id, text, media_urls = [] } = await req.json();

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    // Rate-limit: max 10 moderation calls per user per hour.
    const oneHourAgo = new Date(Date.now() - 3_600_000).toISOString();
    const { count } = await serviceClient
      .from("moderation_log")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user_id)
      .gte("created_at", oneHourAgo);

    if ((count ?? 0) >= 10) {
      console.warn(`moderate: rate limit hit for user ${user_id}`);
      return new Response(JSON.stringify({ allowed: true, skipped: "rate_limit" }), {
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    // Log this call.
    await serviceClient.from("moderation_log").insert({ user_id, echo_id });

    // Moderate text.
    const textResult = await moderateText(text ?? "");
    if (!textResult.allowed) {
      // Hide the echo and notify user.
      await serviceClient
        .from("echoes")
        .update({ status: "hidden" })
        .eq("id", echo_id);

      await serviceClient.from("notifications").insert({
        user_id,
        type: "content_removed",
        title: "Echo removed",
        body: "Your echo was removed because it violated our community guidelines.",
        data: { echo_id, reason: textResult.category },
      });

      return new Response(
        JSON.stringify({ allowed: false, reason: textResult.reason }),
        { headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    // Check media for AI-generated content.
    for (const url of media_urls) {
      const isAI = await checkMediaForAI(url as string);
      if (isAI) {
        await serviceClient
          .from("echoes")
          .update({ status: "hidden" })
          .eq("id", echo_id);

        await serviceClient.from("notifications").insert({
          user_id,
          type: "content_removed",
          title: "Echo removed",
          body: "Your echo was removed because it contained AI-generated media, which is not allowed.",
          data: { echo_id, reason: "ai_generated_media" },
        });

        return new Response(
          JSON.stringify({ allowed: false, reason: "ai_generated_media" }),
          { headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }
    }

    return new Response(JSON.stringify({ allowed: true }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("moderate-content error:", e);
    // Fail open — never block content due to our own errors.
    return new Response(JSON.stringify({ allowed: true, error: "internal" }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});