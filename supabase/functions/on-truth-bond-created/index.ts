import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const payload = await req.json();
    const bondId = payload?.record?.id as string | undefined;
    if (!bondId) return errorResponse(400, "missing bond id");

    const response = await fetch(
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/solana-memo`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        },
        body: JSON.stringify({
          kind: "truth_bond",
          bond_id: bondId,
        }),
      },
    );

    if (!response.ok) {
      return errorResponse(response.status, await response.text());
    }

    return ok({ processed: true, bond_id: bondId });
  } catch (err) {
    console.error("on-truth-bond-created error:", err);
    return errorResponse(500, "internal server error");
  }
});

function ok(data: Record<string, unknown>): Response {
  return new Response(JSON.stringify(data), {
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    status: 200,
  });
}

function errorResponse(status: number, message: string): Response {
  return new Response(JSON.stringify({ success: false, error: message }), {
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    status,
  });
}
