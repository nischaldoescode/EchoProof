import type { User } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { isAllowedAdminEmail } from "@/lib/auth/allowlist";
import { createServer } from "@/lib/supabase/server";

type AdminGuard =
  | { ok: true; user: User }
  | { ok: false; response: NextResponse };

export async function requireAdmin(): Promise<AdminGuard> {
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
