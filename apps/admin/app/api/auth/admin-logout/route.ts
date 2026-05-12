import { NextResponse } from "next/server";
import { adminBasePath } from "@/lib/routes";
import { ADMIN_SESSION_COOKIE } from "@/lib/auth/admin-session";

export async function POST() {
  const response = NextResponse.json({ ok: true });
  response.cookies.set(ADMIN_SESSION_COOKIE, "", {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: adminBasePath || "/",
    maxAge: 0,
  });
  return response;
}
