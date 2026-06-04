// admin trust engine run api
// @params none

import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/auth/require-admin";
import { getSupabaseProjectUrl } from "@/lib/supabase-env";

export async function POST() {
  const admin = await requireAdmin();
  if (!admin.ok) return admin.response;

  const supabaseUrl = getSupabaseProjectUrl();
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !serviceRoleKey) {
    return NextResponse.json(
      { error: "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required." },
      { status: 500 },
    );
  }

  const response = await fetch(`${supabaseUrl}/functions/v1/trust-engine`, {
    method: "POST",
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
    },
  });

  const data = (await response.json().catch(() => ({}))) as unknown;

  if (!response.ok) {
    return NextResponse.json(
      { error: "Trust engine failed.", details: data },
      { status: response.status },
    );
  }

  return NextResponse.json(data);
}
