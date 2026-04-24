// supabase client for the admin panel
// uses service role key — never expose this to users
// this file is imported by server components only

import { createClient } from '@supabase/supabase-js';

const supabaseUrl  = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

// client-side client — uses anon key, subject to RLS
export function createBrowserClient() {
  return createClient(supabaseUrl, supabaseAnon);
}

// server-side client — uses service role key, bypasses RLS
// import this only in Server Components or API routes
export function createServerClient() {
  return createClient(
    supabaseUrl,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
  );
}