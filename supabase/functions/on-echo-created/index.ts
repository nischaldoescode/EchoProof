/**
 * on-echo-created edge function
 *
 * triggered by a supabase database webhook when a new echo row is inserted.
 * calls openai to score the echo for spam likelihood and claim clarity.
 * writes the result back to the echo row as metadata.
 *
 * webhook setup in supabase dashboard:
 *   database > webhooks > create webhook
 *   table: echoes, event: insert
 *   url: {project_url}/functions/v1/on-echo-created
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: CORS_HEADERS });

  try {
    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const payload = await req.json();
    const echo = payload.record; // new echo row

    if (!echo?.id || !echo?.content) {
      return new Response("missing echo data", { status: 400 });
    }

    // FIX — extract user_id from echo row
    const userId = echo.user_id;
    if (!userId) {
      return new Response("missing user_id", { status: 400 });
    }
    // Content moderation — call our moderate-content function.
    // This runs text and media checks via SightEngine.
    const moderationRes = await fetch(
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/moderate-content`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        },
        body: JSON.stringify({
          echo_id: echo.id,
          user_id: userId,
          text: `${echo.title ?? ""} ${echo.content ?? ""}`,
          media_urls: echo.media_urls ?? [],
        }),
      },
    );

    if (moderationRes.ok) {
      const modResult = (await moderationRes.json()) as { allowed: boolean };
      if (!modResult.allowed) {
        // Already hidden and notified by moderate-content function.
        return new Response(
          JSON.stringify({ processed: true, blocked: true }),
          {
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Rate-limit: max 3 posts per 15 minutes
    const fifteenMinutesAgo = new Date(Date.now() - 900_000).toISOString();

    const { count: recentEchoes } = await serviceClient
      .from("echoes")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("created_at", fifteenMinutesAgo);

    if ((recentEchoes ?? 0) >= 3) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "posting too fast — wait 15 minutes",
        }),
        {
          status: 429,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Simple heuristic spam detection — no external AI needed for basic checks.
    // SightEngine handles deeper analysis in moderate-content function.
    // This runs fast pattern checks in-process.
    const spamScore = _computeHeuristicSpamScore(
      echo.title ?? "",
      echo.content ?? "",
    );
    const newStatus = spamScore >= 80 ? "hidden" : "pending_verification";

    await serviceClient
      .from("echoes")
      .update({ status: newStatus })
      .eq("id", echo.id);

    if (newStatus !== "hidden") {
      const anchorRes = await fetch(
        `${Deno.env.get("SUPABASE_URL")}/functions/v1/solana-memo`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
          },
          body: JSON.stringify({
            kind: "echo_created",
            echo_id: echo.id,
          }),
        },
      );

      if (!anchorRes.ok) {
        console.error(
          "on-echo-created: solana anchor failed",
          anchorRes.status,
          await anchorRes.text(),
        );
      }
    }

    // If high spam score, notify user.
    if (spamScore >= 80) {
      await serviceClient.from("notifications").insert({
        user_id: userId,
        type: "content_removed",
        title: "Echo removed",
        body: "Your echo was flagged as spam and removed automatically.",
        data: { echo_id: echo.id, reason: "spam" },
      });
    }

    return new Response(
      JSON.stringify({
        processed: true,
        spam_score: spamScore,
        status: newStatus,
      }),
      { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("on-echo-created unhandled error:", err);
    return new Response("internal error", { status: 500 });
  }
});


// Heuristic spam scorer. No external calls, runs in microseconds.
// Returns 0-100 where 100 = definite spam.
function _computeHeuristicSpamScore(title: string, content: string): number {
  const combined = `${title} ${content}`.toLowerCase();
  let score = 0;

  // All caps (shouting) = +20
  const capsRatio = (combined.match(/[A-Z]/g) ?? []).length / Math.max(combined.length, 1);
  if (capsRatio > 0.5) score += 20;

  // Excessive exclamation marks = +15
  if ((combined.match(/!/g) ?? []).length > 3) score += 15;

  // Repeated characters (hellooooo) = +10
  if (/(.)\1{4,}/.test(combined)) score += 10;

  // URL spam — more than 3 URLs = +25
  const urlCount = (combined.match(/https?:\/\//gi) ?? []).length;
  if (urlCount > 3) score += 25;

  // Very short content with only a URL = +30
  if (content.trim().length < 30 && urlCount > 0) score += 30;

  // Phone numbers = +15 (likely contact spam)
  if (/\b\d{10,}\b/.test(combined)) score += 15;

  // Common spam phrases
  const spamPhrases = [
    "click here", "buy now", "free money", "act now",
    "limited offer", "make money", "earn $", "dm me",
    "whatsapp", "telegram", "follow back",
  ];
  for (const phrase of spamPhrases) {
    if (combined.includes(phrase)) {
      score += 12;
      break; // Only penalize once per post
    }
  }

  return Math.min(score, 100);
}
