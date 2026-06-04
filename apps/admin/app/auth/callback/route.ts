// admin auth callback api
// @params none

import { NextRequest, NextResponse } from "next/server";
import { adminUrl } from "@/lib/public-url";
import { createServer } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const next = safeNextPath(requestUrl.searchParams.get("next"));

  if (!code) {
    return NextResponse.redirect(
      adminUrl(request, "/login?error=auth_callback"),
    );
  }

  const supabase = await createServer();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    const url = adminUrl(request, "/login");
    url.searchParams.set("error", "auth_callback");
    return NextResponse.redirect(url);
  }

  return NextResponse.redirect(adminUrl(request, next));
}

function safeNextPath(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return "/";
  return value;
}
