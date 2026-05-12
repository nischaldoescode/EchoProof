import { NextRequest, NextResponse } from "next/server";
import { isAllowedAdminEmail } from "@/lib/auth/allowlist";
import { adminBasePath } from "@/lib/routes";
import {
  ADMIN_SESSION_COOKIE,
  createAdminSessionToken,
  hasStaticAdminLoginConfig,
  verifyAdminAccessKey,
} from "@/lib/auth/admin-session";

export async function POST(request: NextRequest) {
  let email = "";
  let accessKey = "";

  try {
    const body = await request.json();
    email = String(body.email ?? "").trim().toLowerCase();
    accessKey = String(body.accessKey ?? "");
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  if (!hasStaticAdminLoginConfig()) {
    return NextResponse.json(
      {
        error:
          "Admin access login is not configured. Set ADMIN_ACCESS_KEY and ADMIN_SESSION_SECRET.",
      },
      { status: 500 },
    );
  }

  if (!email || !accessKey) {
    return NextResponse.json(
      { error: "Email and admin access key are required." },
      { status: 400 },
    );
  }

  if (!isAllowedAdminEmail(email) || !verifyAdminAccessKey(accessKey)) {
    return NextResponse.json(
      { error: "Invalid admin email or access key." },
      { status: 401 },
    );
  }

  const token = await createAdminSessionToken(email);
  const response = NextResponse.json({ ok: true });
  response.cookies.set(ADMIN_SESSION_COOKIE, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: adminBasePath || "/",
    maxAge: 60 * 60 * 8,
  });

  return response;
}
