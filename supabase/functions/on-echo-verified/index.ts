// on-echo-verified edge function
// triggered by a database webhook on echoes table when status changes to 'verified'
// creates a permanent on-chain record via solana memo program
// stores the transaction signature back in echoes.verified_record_tx
//
// webhook setup:
//   table: public.echoes
//   event: update
//   condition: new.status = 'verified' AND old.status != 'verified'
//   url: {project_url}/functions/v1/on-echo-verified

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sha256Hex, writeSolanaMemo } from "../_shared/solana.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface WebhookPayload {
  type: string;
  record: {
    id: string;
    content: string;
    confidence_score: number;
    status: string;
    verified_record_tx: string | null;
  };
  old_record: {
    status: string;
  };
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const payload = await req.json() as WebhookPayload;

    // only process update events where status just became verified
    if (payload.type !== "UPDATE") return ok({ skipped: "not an update" });
    if (payload.record.status !== "verified") return ok({ skipped: "not verified status" });
    if (payload.old_record.status === "verified") return ok({ skipped: "already was verified" });
    if (payload.record.verified_record_tx) return ok({ skipped: "record already exists" });

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    );

    await serviceClient
      .from("echoes")
      .update({
        verified_record_status: "recording",
        verified_record_error: null,
      })
      .eq("id", payload.record.id);

    // create a simple sha-256 hash of the content for the on-chain record
    const contentHash = (await sha256Hex(payload.record.content)).slice(0, 32);

    // build the memo data
    // format: echoproof:verified:{echoId}:{contentHash}:{confidence}
    const memoData = `echoproof:verified:${payload.record.id}:${contentHash}:${Math.round(payload.record.confidence_score)}`;

    const result = await writeSolanaMemo(memoData).catch(async (err) => {
      await serviceClient
        .from("echoes")
        .update({
          verified_record_status: "failed",
          verified_record_error: toErrorMessage(err),
        })
        .eq("id", payload.record.id);
      throw err;
    });

    // store the real signature and timestamp in the echo row
    const { error } = await serviceClient
      .from("echoes")
      .update({
        verified_record_tx: result.signature,
        verified_record_at: new Date().toISOString(),
        verified_record_status: "anchored",
        verified_record_error: null,
      })
      .eq("id", payload.record.id);

    if (error) {
      console.error("failed to store verified record tx:", error);
      return errorResponse(500, error.message);
    }

    return ok({
      processed: true,
      echo_id: payload.record.id,
      signature: result.signature,
      explorer_url: result.explorerUrl,
      cluster: result.cluster,
      memo: memoData,
    });

  } catch (err) {
    console.error("on-echo-verified error:", err);
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

function toErrorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}
