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

    const openaiKey = Deno.env.get("OPENAI_API_KEY");

    if (!openaiKey) {
      // openai not configured — skip ai analysis, just mark as processed
      console.warn("OPENAI_API_KEY not set — skipping ai analysis");
      return new Response(JSON.stringify({ skipped: true }), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const prompt = `
you are a content quality analyzer for a community fact-checking platform.
analyze the following post and return ONLY valid JSON with these fields:
- spam_score: integer 0-100 (0 = clearly not spam, 100 = definite spam)
- clarity_score: integer 0-100 (how clearly stated the claim is)
- has_verifiable_claim: boolean (is there a specific claim that can be verified?)
- suggested_category: one of [tech, finance, startups, social_issues, web3, ai, gaming, education, other]
- summary: string max 80 chars summarizing the claim

post title: ${echo.title}
post content: ${echo.content}

respond with JSON only. no explanation.
    `.trim();

    const openaiRes = await fetch(
      "https://api.openai.com/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${openaiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini", // fast and cheap — good for hackathon
          max_tokens: 200,
          temperature: 0,
          messages: [{ role: "user", content: prompt }],
        }),
      },
    );

    if (!openaiRes.ok) {
      console.error("openai error:", await openaiRes.text());
      return new Response("openai error", { status: 500 });
    }

    const openaiData = await openaiRes.json();
    const rawText = openaiData.choices?.[0]?.message?.content ?? "{}";

    let analysis: Record<string, unknown> = {};
    try {
      analysis = JSON.parse(rawText);
    } catch {
      console.error("failed to parse openai response:", rawText);
    }

    const spamScore = Number(analysis.spam_score ?? 0);

    // --------------------------------------------------------
    // if spam score is very high, immediately hide the echo
    // --------------------------------------------------------

    const newStatus = spamScore >= 80 ? "hidden" : "pending_verification";

    await serviceClient
      .from("echoes")
      .update({
        status: newStatus,
        // store ai metadata in a jsonb column
        // TODO: add ai_metadata jsonb column to echoes table in a new migration
        // column definition: ai_metadata jsonb default '{}'::jsonb
        // this stores: spam_score, clarity_score, summary, suggested_category
      })
      .eq("id", echo.id);

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
