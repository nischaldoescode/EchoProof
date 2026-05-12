import { NextRequest, NextResponse } from "next/server";
import { adminPath } from "@/lib/routes";
import { createServer } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const next = safeNextPath(requestUrl.searchParams.get("next"));

  if (!code) {
    return NextResponse.redirect(
      new URL(adminPath("/login?error=auth_callback"), request.url),
    );
  }

  const supabase = await createServer();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    const url = new URL(adminPath("/login"), request.url);
    url.searchParams.set("error", "auth_callback");
    return NextResponse.redirect(url);
  }

  return NextResponse.redirect(new URL(adminPath(next), request.url));
}

function safeNextPath(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return "/";
  return value;
}
