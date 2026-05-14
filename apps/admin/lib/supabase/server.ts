// server supabase client — use in server components and route handlers

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import {
  ADMIN_SESSION_COOKIE,
  verifyAdminSessionToken,
} from "@/lib/auth/admin-session";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  getSupabaseAnonKey,
  getSupabaseProjectUrl,
} from "@/lib/supabase-env";

export async function createServer() {
  const cookieStore = await cookies();
  const staticSession = await verifyAdminSessionToken(
    cookieStore.get(ADMIN_SESSION_COOKIE)?.value,
  );
  if (staticSession) return createAdminClient();

  const supabaseUrl = getSupabaseProjectUrl();
  const supabaseAnonKey = getSupabaseAnonKey();

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
