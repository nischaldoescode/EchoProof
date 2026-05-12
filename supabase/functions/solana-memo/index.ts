import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sha256Hex, writeSolanaMemo } from "../_shared/solana.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type MemoKind = "echo_created" | "proof_created" | "truth_bond";

interface Body {
  kind?: MemoKind;
  echo_id?: string;
  proof_id?: string;
  bond_id?: string;
  memo?: string;
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") return errorResponse(405, "method not allowed");

  try {
    const body = await req.json() as Body;
    const authHeader = req.headers.get("authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "");

    if (!token) return errorResponse(401, "missing authorization");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const isServiceRole = token === serviceKey;

    const serviceClient = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const {
      data: { user },
    } = isServiceRole
      ? { data: { user: null } }
      : await userClient.auth.getUser();

    if (!isServiceRole && !user) return errorResponse(401, "unauthenticated");

    if (body.memo) {
      if (!user && !isServiceRole) return errorResponse(401, "unauthenticated");
      const result = await writeSolanaMemo(body.memo);
      return ok({ success: true, ...result });
    }

    if (!body.kind) return errorResponse(400, "missing memo kind");

    switch (body.kind) {
      case "echo_created":
        return await anchorEchoCreated(serviceClient, body.echo_id, user?.id, isServiceRole);
      case "proof_created":
        return await anchorProofCreated(serviceClient, body.proof_id, user?.id, isServiceRole);
      case "truth_bond":
        return await anchorTruthBond(serviceClient, body.bond_id, user?.id, isServiceRole);
      default:
        return errorResponse(400, "unsupported memo kind");
    }
  } catch (err) {
    console.error("solana-memo error:", err);
    return errorResponse(500, toErrorMessage(err));
  }
});

async function anchorEchoCreated(
  serviceClient: ReturnType<typeof createClient>,
  echoId: string | undefined,
  userId: string | undefined,
  isServiceRole: boolean,
): Promise<Response> {
  if (!echoId) return errorResponse(400, "missing echo_id");

  const { data: echo, error } = await serviceClient
    .from("echoes")
    .select("id, user_id, title, content, created_at, created_record_tx")
    .eq("id", echoId)
    .maybeSingle();

  if (error) return errorResponse(500, error.message);
  if (!echo) return errorResponse(404, "echo not found");
  if (!isServiceRole && echo.user_id !== userId) {
    return errorResponse(403, "not allowed to anchor this echo");
  }
  if (echo.created_record_tx) {
    return ok({
      success: true,
      skipped: "already anchored",
      signature: echo.created_record_tx,
    });
  }

  const { data: claimed, error: claimError } = await serviceClient
    .from("echoes")
    .update({
      solana_status: "recording",
      solana_error: null,
    })
    .eq("id", echo.id)
    .is("created_record_tx", null)
    .neq("solana_status", "recording")
    .select("id")
    .maybeSingle();

  if (claimError) return errorResponse(500, claimError.message);
  if (!claimed) {
    return ok({
      success: true,
      skipped: "already recording",
      echo_id: echo.id,
    });
  }

  try {
    const hash = (await sha256Hex(
      `${echo.title ?? ""}|${echo.content ?? ""}|${echo.created_at ?? ""}`,
    )).slice(0, 32);
    const result = await writeSolanaMemo(`echoproof:echo:${echo.id}:${hash}`);

    const { error: updateError } = await markEchoCreation(serviceClient, echo.id, {
      created_record_tx: result.signature,
      created_record_at: new Date().toISOString(),
      solana_status: "anchored",
      solana_error: null,
    });
    if (updateError) return errorResponse(500, updateError.message);

    return ok({ success: true, echo_id: echo.id, ...result });
  } catch (err) {
    await markEchoCreation(serviceClient, echo.id, {
      solana_status: "failed",
      solana_error: toErrorMessage(err),
    });
    return errorResponse(502, toErrorMessage(err));
  }
}

async function anchorProofCreated(
  serviceClient: ReturnType<typeof createClient>,
  proofId: string | undefined,
  userId: string | undefined,
  isServiceRole: boolean,
): Promise<Response> {
  if (!proofId) return errorResponse(400, "missing proof_id");

  const { data: proof, error } = await serviceClient
    .from("echo_proofs")
    .select("id, echo_id, user_id, proof_url, description, created_at, stake_tx")
    .eq("id", proofId)
    .maybeSingle();

  if (error) return errorResponse(500, error.message);
  if (!proof) return errorResponse(404, "proof not found");
  if (!isServiceRole && proof.user_id !== userId) {
    return errorResponse(403, "not allowed to anchor this proof");
  }
  if (proof.stake_tx) {
    return ok({
      success: true,
      skipped: "already anchored",
      signature: proof.stake_tx,
    });
  }

  const { data: claimed, error: claimError } = await serviceClient
    .from("echo_proofs")
    .update({
      solana_status: "recording",
      solana_error: null,
    })
    .eq("id", proof.id)
    .is("stake_tx", null)
    .neq("solana_status", "recording")
    .select("id")
    .maybeSingle();

  if (claimError) return errorResponse(500, claimError.message);
  if (!claimed) {
    return ok({
      success: true,
      skipped: "already recording",
      proof_id: proof.id,
    });
  }

  try {
    const hash = (await sha256Hex(
      `${proof.proof_url ?? ""}|${proof.description ?? ""}|${proof.created_at ?? ""}`,
    )).slice(0, 32);
    const result = await writeSolanaMemo(
      `echoproof:proof:${proof.id}:${proof.echo_id}:${hash}`,
    );

    const { error: updateError } = await markProof(serviceClient, proof.id, {
      stake_tx: result.signature,
      solana_status: "anchored",
      solana_record_at: new Date().toISOString(),
      solana_error: null,
    });
    if (updateError) return errorResponse(500, updateError.message);

    return ok({ success: true, proof_id: proof.id, ...result });
  } catch (err) {
    await markProof(serviceClient, proof.id, {
      solana_status: "failed",
      solana_error: toErrorMessage(err),
    });
    return errorResponse(502, toErrorMessage(err));
  }
}

async function anchorTruthBond(
  serviceClient: ReturnType<typeof createClient>,
  bondId: string | undefined,
  userId: string | undefined,
  isServiceRole: boolean,
): Promise<Response> {
  if (!bondId) return errorResponse(400, "missing bond_id");

  const { data: bond, error } = await serviceClient
    .from("truth_bonds")
    .select("id, echo_id, user_id, mint_tx, created_at")
    .eq("id", bondId)
    .maybeSingle();

  if (error) return errorResponse(500, error.message);
  if (!bond) return errorResponse(404, "truth bond not found");
  if (!isServiceRole && bond.user_id !== userId) {
    return errorResponse(403, "not allowed to anchor this bond");
  }
  if (bond.mint_tx) {
    return ok({
      success: true,
      skipped: "already anchored",
      signature: bond.mint_tx,
    });
  }

  const { data: claimed, error: claimError } = await serviceClient
    .from("truth_bonds")
    .update({
      solana_status: "recording",
      solana_error: null,
    })
    .eq("id", bond.id)
    .is("mint_tx", null)
    .neq("solana_status", "recording")
    .select("id")
    .maybeSingle();

  if (claimError) return errorResponse(500, claimError.message);
  if (!claimed) {
    return ok({
      success: true,
      skipped: "already recording",
      bond_id: bond.id,
    });
  }

  try {
    const hash = (await sha256Hex(
      `${bond.echo_id}|${bond.user_id}|${bond.created_at ?? ""}`,
    )).slice(0, 32);
    const result = await writeSolanaMemo(
      `echoproof:bond:${bond.id}:${bond.echo_id}:${hash}`,
    );

    const { error: updateError } = await markBond(serviceClient, bond.id, {
      mint_tx: result.signature,
      solana_status: "anchored",
      solana_record_at: new Date().toISOString(),
      solana_error: null,
    });
    if (updateError) return errorResponse(500, updateError.message);

    return ok({ success: true, bond_id: bond.id, ...result });
  } catch (err) {
    await markBond(serviceClient, bond.id, {
      solana_status: "failed",
      solana_error: toErrorMessage(err),
    });
    return errorResponse(502, toErrorMessage(err));
  }
}

function markEchoCreation(
  serviceClient: ReturnType<typeof createClient>,
  echoId: string,
  values: Record<string, unknown>,
) {
  return serviceClient.from("echoes").update(values).eq("id", echoId);
}

function markProof(
  serviceClient: ReturnType<typeof createClient>,
  proofId: string,
  values: Record<string, unknown>,
) {
  return serviceClient.from("echo_proofs").update(values).eq("id", proofId);
}

function markBond(
  serviceClient: ReturnType<typeof createClient>,
  bondId: string,
  values: Record<string, unknown>,
) {
  return serviceClient.from("truth_bonds").update(values).eq("id", bondId);
}

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
