import type { User } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { isAllowedAdminEmail } from "@/lib/auth/allowlist";
import {
  ADMIN_SESSION_COOKIE,
  verifyAdminSessionToken,
  type StaticAdminSession,
} from "@/lib/auth/admin-session";
import { createServer } from "@/lib/supabase/server";

type AdminGuard =
  | { ok: true; user: User | StaticAdminSession }
  | { ok: false; response: NextResponse };

export async function requireAdmin(): Promise<AdminGuard> {
  const cookieStore = await cookies();
  const staticSession = await verifyAdminSessionToken(
    cookieStore.get(ADMIN_SESSION_COOKIE)?.value,
  );
  if (staticSession) return { ok: true, user: staticSession };

  const supabase = await createServer();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    return {
      ok: false,
      response: NextResponse.json({ error: "unauthorized" }, { status: 401 }),
    };
  }

  if (!isAllowedAdminEmail(user.email)) {
    return {
      ok: false,
      response: NextResponse.json({ error: "forbidden" }, { status: 403 }),
    };
  }

  return { ok: true, user };
}
