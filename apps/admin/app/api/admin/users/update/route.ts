import { NextRequest, NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";

const allowedFields = new Set(["is_suspended", "is_shadow_banned"]);

export async function POST(request: NextRequest) {
  const admin = await requireAdmin();
  if (!admin.ok) return admin.response;

  const body = (await request.json().catch(() => null)) as {
    userId?: string;
    field?: string;
    value?: boolean;
  } | null;

  if (!body?.userId || !body.field || typeof body.value !== "boolean") {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  if (!allowedFields.has(body.field)) {
    return NextResponse.json({ error: "Unsupported field." }, { status: 400 });
  }

  const supabase = createAdminClient();
  const { error } = await supabase
    .from("users_public")
    .update({ [body.field]: body.value })
    .eq("id", body.userId);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
