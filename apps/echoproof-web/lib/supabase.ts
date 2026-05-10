import { createBrowserClient } from "@supabase/supabase-js";

const supabaseUrl        = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey    = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

// client for browser (anon key — subject to RLS)
export const supabase = createBrowserClient(supabaseUrl, supabaseAnonKey);

// server-side client (service role — bypasses RLS)
// only import this in getServerSideProps or API routes
export const supabaseAdmin = createBrowserClient(supabaseUrl, supabaseServiceKey);

// types for echo and profile data
export interface Echo {
  id:               string;
  title:            string;
  content:          string;
  category:         string;
  status:           string;
  trust_score:      number;
  confidence_score: number;
  support_count:    number;
  challenge_count:  number;
  created_at:       string;
  user_id:          string;
  users_public?: {
    username:            string;
    avatar_url:          string | null;
    trust_tier:          string;
    is_identity_verified: boolean;
  };
}

export interface Profile {
  id:                  string;
  username:            string;
  avatar_url:          string | null;
  trust_tier:          string;
  trust_score:         number;
  echo_count:          number;
  bio:                 string | null;
  is_identity_verified: boolean;
  wallet_address:      string | null;
}
