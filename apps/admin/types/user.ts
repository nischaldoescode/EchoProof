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
  created_at: string;
}

export interface PrivateUser {
  id: string;
  email: string;
  identity_score: number;
  is_identity_verified: boolean;
  ip_risk_score: number;
}