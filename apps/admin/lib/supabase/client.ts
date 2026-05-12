// Supabase browser client for the admin panel. Service-role access lives in
// lib/supabase/admin.ts so it cannot be pulled into client bundles by mistake.

import {
  type SupabaseClient,
} from '@supabase/supabase-js';
import { createBrowserClient as createSupabaseBrowserClient } from '@supabase/ssr';

const supabaseUrl  = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
let browserClient: SupabaseClient | null = null;

// client-side client — uses anon key, subject to RLS
export function createBrowserClient() {
  browserClient ??= createSupabaseBrowserClient(supabaseUrl, supabaseAnon, {
    auth: {
      storageKey: 'echoproof-admin-auth',
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  });

  return browserClient;
}

// Backward-compatible alias for existing client components.
export const createClient = createBrowserClient;
