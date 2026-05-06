/**
 * personalized-feed edge function
 *
 * returns a ranked list of echoes for a specific user.
 * uses upstash redis for 2-minute cache — critical at 1M+ users.
 * falls back to direct sql if redis is not configured.
 *
 * method: GET
 * auth: required (jwt bearer token)
 * query params: offset (default 0), limit (default 20)
 * returns: { echoes: EchoRecord[], has_more: boolean }
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const CACHE_TTL_SECONDS = 120; // 2 minutes per user per page

// lightweight upstash redis client using the rest api
// no npm package needed — just http calls
async function redisGet(key: string): Promise<string | null> {
  const url = Deno.env.get("UPSTASH_REDIS_REST_URL");
  const token = Deno.env.get("UPSTASH_REDIS_REST_TOKEN");

  if (!url || !token) return null;

  try {
    const res = await fetch(`${url}/get/${encodeURIComponent(key)}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { result: string | null };
    return data.result;
  } catch {
    return null;
  }
}

async function redisSet(
  key: string,
  value: string,
  ttlSeconds: number,
): Promise<void> {
  const url = Deno.env.get("UPSTASH_REDIS_REST_URL");
  const token = Deno.env.get("UPSTASH_REDIS_REST_TOKEN");

  if (!url || !token) return;

  try {
    await fetch(
      `${url}/set/${encodeURIComponent(key)}/${encodeURIComponent(value)}/ex/${ttlSeconds}`,
      {
        headers: { Authorization: `Bearer ${token}` },
      },
    );
  } catch {
    // cache write failure is never fatal
  }
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) return error(401, "missing authorization header");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();
    if (authError || !user) return error(401, "unauthenticated");

    const serviceClient = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // after getting user from auth:
    const { data: userPublic } = await serviceClient
      .from("users_public")
      .select("id, trust_tier")
      .eq("id", user.id)
      .maybeSingle();

    // if user profile doesn't exist yet, return empty feed
    if (!userPublic) {
      return new Response(
        JSON.stringify({ success: true, echoes: [], hasMore: false }),
        {
          status: 200,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const url = new URL(req.url);
    const offset = parseInt(url.searchParams.get("offset") ?? "0", 10);
    const limit = Math.min(
      parseInt(url.searchParams.get("limit") ?? "20", 10),
      50,
    );

    // check if client requests a forced refresh (after user interaction)
    const forceRefresh = url.searchParams.get("refresh") === "1";

    // redis cache key — unique per user, per page
    const cacheKey = `feed:${user.id}:${offset}:${limit}`;

    // try cache first (skip if force refresh)
    if (!forceRefresh) {
      const cached = await redisGet(cacheKey);
      if (cached) {
        console.log(`feed: cache hit for user ${user.id} offset ${offset}`);
        return new Response(cached, {
          headers: {
            ...CORS_HEADERS,
            "Content-Type": "application/json",
            "X-Cache": "HIT",
          },
          status: 200,
        });
      }
    }

    console.log(
      `feed: cache miss for user ${user.id} offset ${offset} — querying db`,
    );

    // get personalized echo ids from the sql scoring function
    const { data: ranked, error: rankError } = await serviceClient.rpc(
      "get_personalized_feed",
      {
        p_user_id: user.id,
        p_offset: offset,
        p_limit: limit,
      },
    );

    if (rankError) {
      console.error("feed ranking error:", rankError);
      return error(500, "feed ranking failed");
    }

    const echoIds = (ranked ?? []).map((r: { echo_id: string }) => r.echo_id);

    if (echoIds.length === 0) {
      const emptyResponse = JSON.stringify({ echoes: [], has_more: false });
      await redisSet(cacheKey, emptyResponse, CACHE_TTL_SECONDS);
      return new Response(emptyResponse, {
        headers: {
          ...CORS_HEADERS,
          "Content-Type": "application/json",
          "X-Cache": "MISS",
        },
        status: 200,
      });
    }

    // fetch full echo data for ranked ids
    const { data: echoes, error: echoError } = await serviceClient
      .from("echoes")
      .select(`
        id, title, content, category, status, version,
        trust_score, confidence_score, controversy_score, report_score,
        support_count, challenge_count, bond_count, response_count, created_at,
        verified_record_tx,
        users_public(username, avatar_url, trust_tier)
      `)
      .in("id", echoIds);

    if (echoError) {
      console.error("feed fetch error:", echoError);
      return error(500, "echo fetch failed");
    }

    // re-sort to match ranking order — sql IN clause does not preserve order
    const echoMap = new Map(
      (echoes ?? []).map((e: { id: string }) => [e.id, e]),
    );
    const sorted = echoIds.map((id: string) => echoMap.get(id)).filter(Boolean);

    // record passive category signals for feed learning
    // fire and forget — never block feed response
    const topCategories = sorted
      .slice(0, 5)
      .map((e: { category: string }) => e.category);

    for (const category of [...new Set(topCategories)]) {
      Promise.resolve(
        serviceClient.rpc("record_feed_signal", {
          p_user_id: user.id,
          p_signal_type: "category_view",
          p_signal_value: category,
          p_weight: 0.1,
        }),
      ).catch(() => {});
    }

    const responseBody = JSON.stringify({
      echoes: sorted,
      has_more: sorted.length === limit,
    });

    // cache the result
    await redisSet(cacheKey, responseBody, CACHE_TTL_SECONDS);

    return new Response(responseBody, {
      headers: {
        ...CORS_HEADERS,
        "Content-Type": "application/json",
        "X-Cache": "MISS",
      },
      status: 200,
    });
  } catch (err) {
    console.error("personalized-feed unhandled error:", err);
    return error(500, "internal server error");
  }
});

function error(status: number, message: string): Response {
  return new Response(JSON.stringify({ success: false, error: message }), {
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    status,
  });
}
