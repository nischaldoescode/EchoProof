// server supabase client — use in server components and route handlers

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import {
  ADMIN_SESSION_COOKIE,
  verifyAdminSessionToken,
} from "@/lib/auth/admin-session";
import { createAdminClient } from "@/lib/supabase/admin";

export async function createServer() {
  const cookieStore = await cookies();
  const staticSession = await verifyAdminSessionToken(
    cookieStore.get(ADMIN_SESSION_COOKIE)?.value,
  );
  if (staticSession) return createAdminClient();

  const supabaseUrl =
    process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey =
    process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    return createAdminClient();
  }

  return createServerClient(
    supabaseUrl,
    supabaseAnonKey,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (cookiesToSet) => {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // server component — cookie setting is best-effort
          }
        },
      },
    }
  );
}

// Backward-compatible alias for older admin pages and data helpers.
export const createClient = createServer;
