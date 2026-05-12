import { NextRequest, NextResponse } from "next/server";
import { isAllowedAdminEmail } from "@/lib/auth/allowlist";
import { adminPath } from "@/lib/routes";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(request: NextRequest) {
  let email = "";

  try {
    const body = await request.json();
    email = String(body.email ?? "").trim().toLowerCase();
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  if (!email) {
    return NextResponse.json(
      { error: "Enter your admin email first." },
      { status: 400 },
    );
  }

  if (!isAllowedAdminEmail(email)) {
    return NextResponse.json(
      { error: "This email is not on the admin allowlist." },
      { status: 403 },
    );
  }

  const origin = request.headers.get("origin") ?? new URL(request.url).origin;
  const redirectTo = `${origin}${adminPath("/auth/callback")}`;
  let errorMessage: string | undefined;
  try {
    const supabase = createAdminClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: redirectTo,
        shouldCreateUser: true,
      },
    });
    errorMessage = error?.message;
  } catch (error) {
    errorMessage =
      error instanceof Error ? error.message : "Could not start magic link.";
  }

  if (errorMessage) {
    return NextResponse.json({ error: errorMessage }, { status: 400 });
  }

  return NextResponse.json({ ok: true });
}
