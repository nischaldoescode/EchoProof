export type TrustTier = "unverified" | "low" | "medium" | "high" | "elite";

export interface PublicUser {
  id: string;
  username: string;
  avatar_url: string | null;
  trust_tier: TrustTier;
  trust_score: number;
  echo_count: number;
  proof_count: number;
  is_suspended: boolean;
  is_shadow_banned: boolean;
  wallet_address: string | null;
  trust_anchor_tx: string | null;
  categories: string[];
  created_at: string;
  updated_at: string;
}