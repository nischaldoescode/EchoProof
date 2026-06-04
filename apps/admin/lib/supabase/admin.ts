// admin supabase helper
// @params none

import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { getSupabaseProjectUrl } from "@/lib/supabase-env";

export function createAdminClient() {
  const supabaseUrl = getSupabaseProjectUrl();
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl) {
    throw new Error("SUPABASE_URL is required for admin actions");
  }
  if (!serviceRoleKey) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is required for admin actions");
  }

  return createSupabaseClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}
