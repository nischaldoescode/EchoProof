// admin supabase env helper
// @params none

export function getSupabaseProjectUrl() {
  return normalizeSupabaseUrl(
    process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL,
  );
}

export function getSupabaseBrowserUrl() {
  return normalizeSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);
}

export function getSupabaseAnonKey() {
  return (
    process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  );
}

export function getSupabaseBrowserAnonKey() {
  return process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
}

function normalizeSupabaseUrl(value?: string) {
  const trimmed = value?.trim().replace(/\/+$/, "") ?? "";
  if (!trimmed) return "";

  return trimmed.replace(/\/rest\/v1$/i, "");
}
