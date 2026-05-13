import { NextRequest, NextResponse } from "next/server";
import { isAllowedAdminEmail } from "@/lib/auth/allowlist";
import { adminBasePath } from "@/lib/routes";
import {
  ADMIN_SESSION_COOKIE,
  createAdminSessionToken,
  hasStaticAdminLoginConfig,
  staticAdminEmail,
  verifyAdminPassword,
} from "@/lib/auth/admin-session";

export async function POST(request: NextRequest) {
  let email = "";
  let password = "";

  try {
    const body = await request.json();
    email = String(body.email ?? "").trim().toLowerCase();
    password = String(body.password ?? body.accessKey ?? "");
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  if (!hasStaticAdminLoginConfig()) {
    return NextResponse.json(
      {
        error:
          "Admin password login is not configured. Set ADMIN_PASSWORD and ADMIN_SESSION_SECRET.",
      },
      { status: 500 },
    );
  }

  if (!email || !password) {
    return NextResponse.json(
      { error: "Email and admin password are required." },
      { status: 400 },
    );
  }

  const expectedEmail = staticAdminEmail();
  if (
    email !== expectedEmail ||
    !isAllowedAdminEmail(email) ||
    !verifyAdminPassword(password)
  ) {
    return NextResponse.json(
      { error: "Invalid admin email or password." },
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
