// Supabase browser client for the admin panel. Service-role access lives in
// lib/supabase/admin.ts so it cannot be pulled into client bundles by mistake.

import { createClient as createSupabaseClient } from '@supabase/supabase-js';

const supabaseUrl  = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

// client-side client — uses anon key, subject to RLS
export function createBrowserClient() {
  return createSupabaseClient(supabaseUrl, supabaseAnon);
}

// Backward-compatible alias for existing client components.
export const createClient = createBrowserClient;
