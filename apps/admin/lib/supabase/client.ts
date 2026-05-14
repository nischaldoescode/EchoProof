// Supabase browser client for the admin panel. Service-role access lives in
// lib/supabase/admin.ts so it cannot be pulled into client bundles by mistake.

import {
  type SupabaseClient,
} from '@supabase/supabase-js';
import { createBrowserClient as createSupabaseBrowserClient } from '@supabase/ssr';
import {
  getSupabaseBrowserAnonKey,
  getSupabaseBrowserUrl,
} from '@/lib/supabase-env';

const supabaseUrl = getSupabaseBrowserUrl();
const supabaseAnon = getSupabaseBrowserAnonKey();
let browserClient: SupabaseClient | null = null;

// client-side client — uses anon key, subject to RLS
export function createBrowserClient() {
  if (!supabaseUrl || !supabaseAnon) {
    throw new Error(
      'NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY are required',
    );
  }

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
