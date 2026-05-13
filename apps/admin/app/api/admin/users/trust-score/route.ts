import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(request: NextRequest) {
  const admin = await requireAdmin();
  if (!admin.ok) return admin.response;

  const body = (await request.json().catch(() => null)) as {
    userId?: string;
    score?: number;
  } | null;
  const score = Number(body?.score);

  if (!body?.userId || !Number.isFinite(score)) {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  const clampedScore = Math.min(Math.max(Math.round(score), 0), 100);
  const supabase = createAdminClient();
  const { error: updateError } = await supabase
    .from("users_public")
    .update({ trust_score: clampedScore })
    .eq("id", body.userId);

  if (updateError) {
    return NextResponse.json({ error: updateError.message }, { status: 500 });
  }

  const { error: tierError } = await supabase.rpc("update_user_trust_tier", {
    p_user_id: body.userId,
  });

  if (tierError) {
    return NextResponse.json({ error: tierError.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
