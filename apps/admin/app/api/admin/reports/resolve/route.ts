// admin API: resolve one report or all unresolved reports for an echo

import { requireAdmin } from "@/lib/auth/require-admin";
import { createAdminClient } from "@/lib/supabase/admin";
import { adminUrl } from "@/lib/public-url";
import { NextRequest, NextResponse } from "next/server";

type ResolvePayload = {
  report_id?: string;
  echo_id?: string;
};

export async function POST(req: NextRequest) {
  const admin = await requireAdmin();
  if (!admin.ok) return admin.response;

  const supabase = createAdminClient();
  const payload = await readPayload(req);

  if (!payload.report_id && !payload.echo_id) {
    return NextResponse.json(
      { error: "report_id or echo_id is required" },
      { status: 400 },
    );
  }

  let query = supabase
    .from("echo_reports")
    .update({ resolved: true })
    .eq("resolved", false);

  if (payload.report_id) {
    query = query.eq("id", payload.report_id);
  } else if (payload.echo_id) {
    query = query.eq("echo_id", payload.echo_id);
  }

  const { error } = await query;

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  if (isJsonRequest(req)) {
    return NextResponse.json({ success: true });
  }

  return NextResponse.redirect(adminUrl(req, "/reports"));
}

async function readPayload(req: NextRequest): Promise<ResolvePayload> {
  if (isJsonRequest(req)) return (await req.json()) as ResolvePayload;

  const body = await req.formData();
  return {
    report_id: (body.get("report_id") as string | null) ?? undefined,
    echo_id: (body.get("echo_id") as string | null) ?? undefined,
  };
}

function isJsonRequest(req: NextRequest) {
  return req.headers.get("content-type")?.includes("application/json") ?? false;
}
